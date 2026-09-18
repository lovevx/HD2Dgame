extends RefCounted
## 装备系统静态查表：品质 Q / 评分 / 配色、肉体修正系数、力量攻击倍率、
## 强化 AttackAdd / 成功率 / Kstr 系数、击杀扣耐、出售分解倍率。
## 口径：docs/EQUIPMENT_SYSTEM.md §二 / §4 / §6；所有数值集中这里，策划改表不动代码。
const Attributes := preload("res://data/attributes.gd")

## ---------- 品质（5 档全做） ----------
## key → {cn 品质名, score_min/max 乐园评分区间, q 品质基础值 Q, color 配色（槽/文本）}
const QUALITY := {
	"white": {
		"cn": "白", "rarity": "白色", "score_min": 1, "score_max": 10, "q": 1000,
		"color": Color("d8e0e8"),
	},
	"green": {
		"cn": "绿", "rarity": "绿色", "score_min": 10, "score_max": 30, "q": 2500,
		"color": Color("7ed89a"),
	},
	"blue": {
		"cn": "蓝", "rarity": "蓝色", "score_min": 30, "score_max": 100, "q": 8000,
		"color": Color("6ab7ff"),
	},
	"purple": {
		"cn": "紫", "rarity": "紫色", "score_min": 100, "score_max": 260, "q": 12000,
		"color": Color("c08aff"),
	},
	"gold_light": {
		"cn": "淡金", "rarity": "淡金色", "score_min": 260, "score_max": 310, "q": 30000,
		"color": Color("ffd76e"),
	},
}
## 品质展示名（入 tooltip / 详情）
static func quality_cn(key: String) -> String:
	return QUALITY.get(key, QUALITY["white"]).get("rarity", "白色")
static func quality_color(key: String) -> Color:
	return QUALITY.get(key, QUALITY["white"]).get("color", Color.WHITE)
## 品质基础值 Q（强化/修复/出售/分解共用一套）
static func quality_q(key: String) -> int:
	return int(QUALITY.get(key, QUALITY["white"]).get("q", 1000))

## ---------- 肉体伤害修正系数（con 查表，±2%/点，con=5 → 1.00） ----------
static func con_hit_factor(con: int) -> float:
	return 1.0 + (con - 5) * 0.02

## ---------- 裸装力量近战攻击倍率（查表，上限锁死） ----------
const STR_ATK_COEF_ROWS := [[5, 1.00], [10, 1.10], [18, 1.22], [30, 1.35], [2147483647, 1.45]]
static func str_atk_coef(str_val: int) -> float:
	for row in STR_ATK_COEF_ROWS:
		if str_val <= row[0]:
			return row[1]
	return 1.45

## ---------- 强化 AttackAdd（每 +1 上下限同步增幅，按武器类型查表） ----------
## weapon_type 与 ITEMS 条目上的 weapon_type 保持一致。
const ATTACK_ADD_BY_TYPE := {
	"1h_sword": 1.5,  # 单手刀剑（斩龙闪类）
	"heavy": 2.2,     # 重型双手武器
	"dagger": 0.9,    # 匕首 / 轻型
	"gun": 1.2,       # 枪械
}
const ENHANCE_MAX := 12

## ---------- 强化成功率 & 失败掉级（+0~+9 共 10 档；+10 以上统一 <10%） ----------
## 每行 {p: 成功率, fail_min/max: 失败掉级区间（≥0 表示不掉级）}
const ENHANCE_ROWS := [
	{"p": 0.98, "fail_min": 0, "fail_max": 0},  # +0→+1
	{"p": 0.94, "fail_min": 0, "fail_max": 0},  # +1→+2
	{"p": 0.88, "fail_min": 0, "fail_max": 0},  # +2→+3
	{"p": 0.82, "fail_min": 0, "fail_max": 0},  # +3→+4
	{"p": 0.80, "fail_min": 1, "fail_max": 1},  # +4→+5
	{"p": 0.72, "fail_min": 1, "fail_max": 2},  # +5→+6
	{"p": 0.65, "fail_min": 1, "fail_max": 2},  # +6→+7
	{"p": 0.55, "fail_min": 99, "fail_max": 99},# +7→+8 清零
	{"p": 0.40, "fail_min": 99, "fail_max": 99},# +8→+9 清零
	{"p": 0.25, "fail_min": 99, "fail_max": 99},# +9→+10（简化版：不掉耐久不灭失，只掉级）
]
## 简化版：+10 以上一律 <10% 且失败清零
const ENHANCE_ULTRA_P := 0.08
static func enhance_success_rate(level: int) -> float:
	if level < ENHANCE_ROWS.size():
		return ENHANCE_ROWS[level]["p"]
	return ENHANCE_ULTRA_P

## 强化等级系数 Kstr（出售/分解用）
const KSTR := [1.00, 1.05, 1.10, 1.15, 1.20, 1.28, 1.36, 1.45, 1.55, 1.65, 1.80]
static func kstr(level: int) -> float:
	return KSTR[clampi(level, 0, KSTR.size() - 1)]

## ---------- 成长装备 / 倍率 ----------
const GROW_ENHANCE := 1.5   # 成长装备强化花费倍率
const GROW_REPAIR := 1.5    # 成长装备修复倍率
const GROW_SELL := 1.2      # 成长装备出售/分解产出倍率
const GROW_MAX_FURY := 100.0  # 斩龙闪锋刃值阈值（晋升品质）

## ---------- 出售 / 分解 ----------
const SELL_R := 0.4
const DECOMP_R := 0.35

## ---------- 击杀武器扣耐表 ----------
const KILL_DUR := {"normal": 1, "elite": 3, "boss": 8}
static func kill_dur(tier: int) -> int:
	return {"normal": 1, "elite": 3, "boss": 8}.get(tier, 1)

## 强化成功 +1 的耐久上限提升（武器 +3~5 取 4、护甲 +4~7 取 5、首饰无耐久）
static func enhance_dur_max_add(item: Dictionary) -> int:
	match item.get("item_kind", "other"):
		"weapon":
			match item.get("weapon_type", "1h_sword"):
				"heavy": return 5
				"gun": return 4
				_: return 3
		"armor": return 5
		_: return 0

## 成长晋升时的攻击区间提升（按目标品质档数递增，数值待校准）
static func growth_tier_attack_add(tier: int) -> float:
	return [0.0, 2.0, 4.0, 6.0, 9.0][clampi(tier, 0, 4)]