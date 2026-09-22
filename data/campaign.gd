extends RefCounted
## 本次纵向切片的区域、奖励与物品表；战斗技能初值见 combat_skills.gd。
## 装备口径见 docs/EQUIPMENT_SYSTEM.md；查表配置集中 data/equip_tables.gd。
const SCENE := "res://scenes/main/campaign.tscn"
const BASE_STATS := {"str": 6, "agi": 7, "con": 5, "int": 6, "cha": 3, "luk": 1}
const STAGES := [
	{"name": "1.2 废品终点站", "brief": "击败持械流民，搜集燧发枪与恢复品。", "enemies": [["持械流民", 38, 8, "vagrant"]], "loot": {"flintlock": 1, "potion": 2}, "source": 0.0,
	 "story": "签订乐园契约的苏晓，从剧痛中醒来——身下是堆满锈铁与碎布的废品山丘。\n\n这里是王都郊外的废品终点站，流民握刀在垃圾堆间逡巡。活下去，然后进城。"},
	{"name": "1.3 王都入口", "brief": "击败卡洛斯，打开白色宝箱取得引荐信。", "enemies": [["黑市商人·卡洛斯", 75, 12, "carlos"]], "loot": {"carlos_chest": 1}, "source": 0.0,
	 "story": "伪装成商人的苏晓混进了王都入口。城门口的黑市商人卡洛斯眯起眼——这面孔太陌生了。\n\n他拔出了腰间的匕首。要进城，先过这一关。"},
	{"name": "1.4 侍卫总部", "brief": "持引荐信完成入队实战考核，领取并装备斩龙闪。", "enemies": [["考核教官（切磋）", 100, 10, "instructor"]], "loot": {"dragon": 1, "guard_badge": 1}, "source": 2.1,
	 "story": "引荐信递到侍卫长手里，换来一句冷笑：\n\n“入队前先过实战考核。”操场上，考核教官提着佩刀，缓步走进演武圈。"},
	{"name": "1.5 欢乐街", "brief": "击败欧卡与护卫，开启白色宝箱，准备猎虎。", "enemies": [["布兰登·欧卡", 170, 17, "oka"], ["欧卡护卫", 55, 10, "guard"]], "loot": {"oka_chest": 1, "trap": 3, "potion": 2, "catnip": 1}, "source": 3.6,
	 "story": "欢乐街的灯笼还没点完，前侍卫首领布兰登·欧卡正带着护卫巡视夜市。\n\n在他身后，是一口封好的白色宝箱。苏晓压低斗笠，踏入红灯下的街巷。"},
	{"name": "1.6 科尔波山", "brief": "先用 1 预埋火药陷阱，V 引诱巨虎。注意狂暴和诈死。", "enemies": [], "loot": {"tiger_chest": 1, "tiger_tooth": 1}, "source": 3.2,
	 "story": "科尔波山的虎啸在林间回荡。山民说，一头小山般的巨虎盘踞山顶，噬人无数。\n\n苏晓掂了掂怀里的火药陷阱——猎杀这头山林之主的时候到了。"},
]
## 装备位（原著 11 位，见策划案 §3.3）：主武器/副武器/头部/躯干/护臂左/护臂右/足部/披风/项链/戒指/戒指2
const SLOTS := ["main_weapon", "offhand", "head", "body", "left_arm", "right_arm", "boots", "cloak", "necklace", "ring", "ring_sub"]
## 槽位中文名（hud 用）
const SLOT_CN := {
	"main_weapon": "主武器", "offhand": "副武器", "head": "头部", "body": "躯干",
	"left_arm": "护臂 · 左", "right_arm": "护臂 · 右", "boots": "足部", "cloak": "披风",
	"necklace": "项链", "ring": "戒指", "ring_sub": "戒指Ⅱ",
}

## 物品表：字段口径见策划案 §四（品质/评分/词条/耐久/强化/出售分解/成长）。
## export = 乐园公证可带出；false = 本土世界限定。slot 缺省 = 不可穿戴（道具/材料/宝箱/信物）。
const ITEMS := {
	# ---- 武器 ----
	"knife": {"name": "普通匕首", "slot": "main_weapon", "item_kind": "weapon", "weapon_type": "dagger",
		"quality": "white", "score": 3, "attack_min": 4.0, "attack_max": 9.0, "stats": {},
		"dur_max": 18, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "开局装备"},
	"dragon": {"name": "斩龙闪", "slot": "main_weapon", "item_kind": "weapon", "weapon_type": "1h_sword",
		"quality": "white", "score": 10, "attack_min": 5.0, "attack_max": 16.0, "stats": {},
		"dur_max": 40, "req": {"str": 2}, "export": true, "growth": true,
		"can_sell": true, "can_decompose": true,
		"passive": ["龙之威严：削减敌方气势"], "source": "侍卫总部仓库获取"},
	"flintlock": {"name": "破旧燧发枪", "slot": "offhand", "item_kind": "weapon", "weapon_type": "gun",
		"quality": "green", "score": 12, "attack_min": 2.0, "attack_max": 13.0, "stats": {},
		"dur_max": 20, "req": {}, "export": false, "growth": false,
		"can_sell": false, "can_decompose": false, "passive": [], "source": "废品终点站拾取"},
	# ---- 首饰（无耐久） ----
	"pendant": {"name": "亡妻的项坠", "slot": "necklace", "item_kind": "jewelry",
		"quality": "white", "score": 8, "stats": {"str": 1}, "dur_max": 0,
		"req": {}, "export": true, "growth": false,
		"can_sell": true, "can_decompose": true,
		"passive": ["力量+1", "支持隐藏装备外观"], "source": "欧卡的白色宝箱"},
	# ---- 前期本土装备（1.2~1.6 掉落 / 场景宝箱产出；不可带出，结算时清除） ----
	"worn_blade": {"name": "缺口铁刀", "slot": "main_weapon", "item_kind": "weapon", "weapon_type": "1h_sword",
		"quality": "white", "score": 6, "attack_min": 4.0, "attack_max": 11.0, "stats": {},
		"dur_max": 22, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	"iron_sword": {"name": "精铁刀", "slot": "main_weapon", "item_kind": "weapon", "weapon_type": "1h_sword",
		"quality": "green", "score": 18, "attack_min": 5.0, "attack_max": 14.0, "stats": {},
		"dur_max": 28, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	"leather_cap": {"name": "皮质护额", "slot": "head", "item_kind": "armor",
		"quality": "white", "score": 5, "stats": {"con": 1}, "def_pct": 0.02,
		"dur_max": 16, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	"hunter_hat": {"name": "猎户皮帽", "slot": "head", "item_kind": "armor",
		"quality": "green", "score": 15, "stats": {"con": 1, "agi": 1}, "def_pct": 0.03,
		"dur_max": 20, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	"ragged_vest": {"name": "褴褛皮甲", "slot": "body", "item_kind": "armor",
		"quality": "white", "score": 7, "stats": {"con": 1}, "def_pct": 0.03,
		"dur_max": 20, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	"leather_bracer": {"name": "皮质护臂", "slot": "left_arm", "item_kind": "armor",
		"quality": "white", "score": 4, "stats": {}, "def_pct": 0.02,
		"dur_max": 14, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	"worn_boots": {"name": "旧皮靴", "slot": "boots", "item_kind": "armor",
		"quality": "white", "score": 4, "stats": {"agi": 1}, "def_pct": 0.01,
		"dur_max": 14, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	"tattered_cloak": {"name": "破损披风", "slot": "cloak", "item_kind": "armor",
		"quality": "white", "score": 5, "stats": {}, "def_pct": 0.02,
		"dur_max": 16, "req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	"copper_ring": {"name": "铜戒指", "slot": "ring", "item_kind": "jewelry",
		"quality": "white", "score": 6, "stats": {"luk": 1}, "dur_max": 0,
		"req": {}, "export": false, "growth": false,
		"can_sell": true, "can_decompose": true, "passive": [], "source": "前期世界掉落"},
	# ---- 消耗品 ----
	"potion": {"name": "恢复药剂 · 2使用", "item_kind": "consumable", "export": true},
	"trap": {"name": "火药陷阱 · 1投掷", "item_kind": "consumable", "export": false},
	"catnip": {"name": "木天芷 · 猎虎诱饵", "item_kind": "consumable", "export": false},
	# ---- 材料 ----
	"crystal": {"name": "灵魂结晶（小）", "item_kind": "material", "quality": "purple", "score": 109, "export": true, "can_sell": true, "can_decompose": false},
	"claw": {"name": "虎爪", "item_kind": "material", "quality": "green", "score": 16, "export": true, "can_sell": true, "can_decompose": false},
	"white_mat": {"name": "白色锻造材料", "item_kind": "material", "quality": "white", "score": 2, "export": true, "can_sell": true, "can_decompose": false, "sell_price": 12},
	"green_mat": {"name": "绿色锻造材料", "item_kind": "material", "quality": "green", "score": 15, "export": true, "can_sell": true, "can_decompose": false, "sell_price": 60},
	"blue_mat": {"name": "蓝色锻造材料", "item_kind": "material", "quality": "blue", "score": 60, "export": true, "can_sell": true, "can_decompose": false, "sell_price": 180},
	"purple_mat": {"name": "紫色锻造材料", "item_kind": "material", "quality": "purple", "score": 150, "export": true, "can_sell": true, "can_decompose": false, "sell_price": 400},
	"gold_mat": {"name": "淡金色锻造材料", "item_kind": "material", "quality": "gold_light", "score": 280, "export": true, "can_sell": true, "can_decompose": false, "sell_price": 900},
	# ---- 剧情 / 任务 ----
	"letter": {"name": "卡洛斯的引荐信", "item_kind": "quest", "export": false},
	"guard_badge": {"name": "侍卫身份凭证", "item_kind": "quest", "export": false},
	"tiger_tooth": {"name": "虎齿 · 支线目标（本次不交付）", "item_kind": "quest", "export": true},
	# ---- 宝箱 ----
	"carlos_chest": {"name": "卡洛斯的白色宝箱", "item_kind": "chest", "export": true, "can_sell": false, "can_decompose": false},
	"oka_chest": {"name": "欧卡的白色宝箱", "item_kind": "chest", "export": true, "can_sell": false, "can_decompose": false},
	"tiger_chest": {"name": "巨虎的绿色宝箱", "item_kind": "chest", "export": true, "can_sell": false, "can_decompose": false},
}
const CHESTS := {
	"carlos_chest": {"coins": 120, "items": {"letter": 1}},
	"oka_chest": {"coins": 240, "items": {"pendant": 1}},
	"tiger_chest": {"coins": 400, "items": {"claw": 1, "crystal": 1}},
}
const HUNTS := {"1_0": 5, "3_0": 10, "3_1": 1, "tiger": 15}
## 随机装备产出池：前期小关击杀掉落 / 场景宝箱共用（全为本土装备，结算时清除）。
const RANDOM_EQUIP_POOL := ["worn_blade", "iron_sword", "leather_cap", "hunter_hat",
	"ragged_vest", "leather_bracer", "worn_boots", "tattered_cloak", "copper_ring"]
## 场景宝箱固定产出：1 炸弹 + 1 血药 + 1 随机装备。
const SCENE_CHEST_ITEMS := {"trap": 1, "potion": 1}

## 从随机装备池抽一件（池为空时返回空串）。
static func random_equip_id(rng: RandomNumberGenerator = null) -> String:
	if RANDOM_EQUIP_POOL.is_empty():
		return ""
	if rng != null:
		return RANDOM_EQUIP_POOL[rng.randi_range(0, RANDOM_EQUIP_POOL.size() - 1)]
	return RANDOM_EQUIP_POOL[randi() % RANDOM_EQUIP_POOL.size()]

static func fresh() -> Dictionary:
	return {"stage": 0, "cleared": false, "hub": false, "run": 1, "level": 1,
		"source": 0.0, "world_mana": 0, "permanent_mana": 0, "kills": [],
		"bag": {"knife": 1, "potion": 2}, "equipment": {"main_weapon": "knife"},
		"opened_chests": [],
		# 装备动态状态（按物品 id 存放；强化/耐久/成长值），旧档缺省由 load 兜底
		"item_dura": {}, "item_enhance": {}, "item_fury": {},
		"hp_ratio": 1.0, "mp_ratio": 1.0, "bullets": 6, "settled": false, "training": 0, "report": "", "colpo_outer_cleared": false,
		# 新手流程阶段：ship=船到港引导 / training=试炼场教学 / equipped=已发装备待接任务 / quested=已接任务 / ""=正式循环
		"flow": "", "training_done": false}

## 该物品是否为可穿戴装备（有 slot）
static func is_equippable(id: String) -> bool:
	return ITEMS.get(id, {}).has("slot")

## 当前耐久 / 耐久上限 / 强化等级 / 锋刃值（带默认兜底，配合存档 merged）
static func dura_state(campaign: Dictionary, id: String) -> Dictionary:
	var item: Dictionary = ITEMS.get(id, {})
	var max_v: float = float(item.get("dur_max", 0))
	var entry: Dictionary = campaign.get("item_dura", {}).get(id, {"cur": max_v, "max": max_v})
	return {"cur": float(entry.get("cur", max_v)), "max": float(entry.get("max", max_v))}

static func enhance_level(campaign: Dictionary, id: String) -> int:
	return int(campaign.get("item_enhance", {}).get(id, 0))

static func fury_value(campaign: Dictionary, id: String) -> float:
	return float(campaign.get("item_fury", {}).get(id, 0.0))
