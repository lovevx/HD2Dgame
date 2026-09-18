extends RefCounted
## 六维属性静态数值表：单一定义来源。消费方用 preload 引用（本项目工具脚本惯例）。
## 六维键统一用 ASCII 短键，避免中文键在 ConfigFile / Dictionary 序列化中的坑。
## 口径：GDD.md 第 6 节 + NOVEL_CORE_SYSTEMS.md 第 2 节。起始六维统一 5。

## 六维键名。
const KEY_STR := "str"   # 力量
const KEY_AGI := "agi"   # 敏捷
const KEY_CON := "con"   # 体力
const KEY_INT := "int"   # 智力
const KEY_CHA := "cha"   # 魅力
const KEY_LUK := "luk"   # 幸运

## 成年男性标准属性基准；本项目起始六维统一 5，幸运虽原著为 1，首版模板统一 5。
const BASE := 5
## 武器基础攻击（力量之外的部分），见 GDD.md 第 6 节「攻击 = 武器基础 7 + 力量」。
const WEAPON_BASE_ATK := 7
## 首版允许用属性点提升的维度：力量/敏捷/体力/智力；魅力、幸运不透支。
const SPENDABLE := [KEY_STR, KEY_AGI, KEY_CON, KEY_INT]

## 六维中文显示名，供 HUD / 面板使用。
const CN_NAMES := {
	KEY_STR: "力量", KEY_AGI: "敏捷", KEY_CON: "体力",
	KEY_INT: "智力", KEY_CHA: "魅力", KEY_LUK: "幸运",
}

## 全部键，按展示顺序。
const ALL_KEYS := [KEY_STR, KEY_AGI, KEY_CON, KEY_INT, KEY_CHA, KEY_LUK]

## 初始六维（全部 5 点）。
static func defaults() -> Dictionary:
	return {KEY_STR: BASE, KEY_AGI: BASE, KEY_CON: BASE, KEY_INT: BASE, KEY_CHA: BASE, KEY_LUK: BASE}

## 合并读取存档：旧档缺字段时用默认值兜底。
static func merged(raw: Dictionary) -> Dictionary:
	var out := defaults()
	for key in ALL_KEYS:
		if raw.get(key) is int:
			out[key] = raw[key]
	return out

static func is_spendable(key: String) -> bool:
	return SPENDABLE.has(key)

## 最大 HP = 50 + 体力×10（六维 5 → 100）。
static func max_hp(a: Dictionary) -> float:
	return 50.0 + float(a.get(KEY_CON, BASE)) * 10.0

## 最大 MP = 智力×10（六维 5 → 50）。
static func max_mp(a: Dictionary) -> float:
	return float(a.get(KEY_INT, BASE)) * 10.0

## 攻击 = 武器基础 7 + 力量（六维 5 → 12）。
static func attack(a: Dictionary) -> float:
	return float(WEAPON_BASE_ATK + a.get(KEY_STR, BASE))

## 移动速度：基准 5.0，敏捷每点小幅修正 +0.05（待校准，P1 不改攻速/缓冲/闪避）。
static func move_speed(a: Dictionary) -> float:
	return 5.0 + (a.get(KEY_AGI, BASE) - BASE) * 0.05