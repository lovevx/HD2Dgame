extends RefCounted
## 任务档案（HUD「任务面板」的唯一数据源）：把散落在存档里的进度读成一份任务表。
## 权威状态只有 GameState.campaign 一处，本表只做只读映射 —— 不新增存档字段、
## 不改写任何流程，任务面板显示的状态因此永远与实际进度一致。
## 后续新增地区 / 支线时回来改这里，别另立第二份任务表。
##
## 本模块是纯函数：存档字典由调用方显式传入（面板传 GameState.campaign，校验脚本喂构造档），
## 不引用任何 autoload —— 这样 headless 校验可以 preload 它并直接构造各种进度状态。

const Data := preload("res://data/campaign.gd")
## 目标文案里的键名现读（玩家改键后「剃（空格）」这类字眼跟着变）。
## 本模块仍然不引用任何 autoload —— key_bindings 是零依赖叶子，只读 InputMap。
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")

## 任务状态：已完成 / 待交接（条件已满足，还差交付或离场）/ 进行中 / 未解锁
const DONE := "done"
const PENDING := "pending"
const ACTIVE := "active"
const LOCKED := "locked"

const STATUS_CN := {DONE: "已完成", PENDING: "待交接", ACTIVE: "进行中", LOCKED: "未解锁"}
const STATUS_COLOR := {
	DONE: Color("6fdc9a"),
	PENDING: Color("ffd76e"),
	ACTIVE: Color("6fa8ff"),
	LOCKED: Color("7f949b"),
}
## 列表行前缀：像素方块 —— 实心 = 已完成，菱形 = 待交接，三角 = 进行中，空心 = 未解锁。
const STATUS_MARK := {DONE: "■", PENDING: "◆", ACTIVE: "▶", LOCKED: "□"}

## 各地图所在处（与 Data.STAGES 一一对应；STAGES 只写了名字，地点在这里补）。
const PLACES := [
	"王都郊外 · 废品终点站",
	"王都入口 · 城门口",
	"侍卫总部 · 演武场",
	"欢乐街 · 灯市",
	"科尔波山 · 外围丛林 → 决战空地",
]

## 整份档案：章 = {"title": String, "entries": Array}；空章不返回。
static func groups(campaign: Dictionary) -> Array:
	var c := campaign
	var out: Array = []
	var prologue := _prologue(c)
	if not prologue.is_empty():
		out.append({"title": "序章 · 乐园契约", "entries": prologue})
	out.append({"title": "主线 · 第一轮试炼", "entries": _main_line(c)})
	var sides := _sides(c)
	if not sides.is_empty():
		out.append({"title": "支线 · 港务委托", "entries": sides})
	var record := _record(c)
	if not record.is_empty():
		out.append({"title": "轮回记录", "entries": record})
	return out

## 拍平后的任务顺序（列表选中与验收断言都用它，顺序 = 面板从上到下）。
static func entries(campaign: Dictionary) -> Array:
	var out: Array = []
	for group in groups(campaign):
		for entry in group["entries"]:
			out.append(entry)
	return out

static func find(id: String, campaign: Dictionary) -> Dictionary:
	for entry in entries(campaign):
		if str(entry["id"]) == id:
			return entry
	return {}

## 列表默认选中项：优先当前主线（进行中 / 待交接），其次任一进行中的任务，
## 都没有就落到最后一条（结算记录）—— 打开面板第一眼看到的是「现在该做什么」。
static func default_id(campaign: Dictionary) -> String:
	var list := entries(campaign)
	for entry in list:
		if str(entry["kind"]) == "主线" and _is_current(str(entry["status"])):
			return str(entry["id"])
	for entry in list:
		if _is_current(str(entry["status"])):
			return str(entry["id"])
	return str(list[-1]["id"]) if not list.is_empty() else ""

static func _is_current(status: String) -> bool:
	return status == ACTIVE or status == PENDING

static func status_cn(status: String) -> String:
	return str(STATUS_CN.get(status, status))

static func status_color(status: String) -> Color:
	return STATUS_COLOR.get(status, Color("7f949b"))

static func status_mark(status: String) -> String:
	return str(STATUS_MARK.get(status, "·"))

# ---------------------------------------------------------------- 序章

## 序章三步（码头对话 / 演武场教学 / 委托所接取）按 campaign.flow 的推进档位判定。
## 木桩与剃的过程计数不落档，教学一完成三项一起打勾，不假装有分步进度。
static func _prologue(c: Dictionary) -> Array:
	var step := _pre_step(str(c.get("flow", "")))
	var learned := step >= 2 or bool(c.get("training_done", false))
	var out: Array = []
	var arrive := [_obj("在码头与港口向导对话", step >= 1)]
	out.append(_entry("ep_arrive", "船靠岸 · 抵达灰潮港", "序章",
		DONE if step >= 1 else ACTIVE,
		"港口向导", "灰潮港 · 码头",
		"跟码头上的向导对话，问清乐园的规矩。",
		"「新人，先别急着往城里跑。」\n\n向导指了指东侧：「练熟了再去委托所接活，乐园不养闲人。」",
		arrive, []))
	var learn := [
		_obj("在演武场命中练功木桩 ×3", learned),
		_obj("使用一次剃（%s）" % KeyBindings.key_text("dodge"), learned),
		_obj("领取整套基础装备", learned),
	]
	out.append(_entry("ep_training", "演武场 · 新手教学", "序章",
		LOCKED if step == 0 else (DONE if step >= 2 else ACTIVE),
		"港口向导", "灰潮港 · 演武场",
		"打三下木桩、用一次剃，然后领走整套基础装备。",
		"演武场里只有一根打不坏的练功木桩。\n\n木桩命中 ×3、剃用过 1 次，轮回乐园就认可你的身手。",
		learn, ["整套基础装备：刀刃 · 护额 · 皮甲 · 护臂 · 皮靴 · 披风 · 戒指"]))
	var accept := [
		_obj("完成演武场教学", learned),
		_obj("前往西侧 · 任务委托所接取任务", step >= 3),
		_obj("前往北侧传送阵开始试炼", step >= 4),
	]
	out.append(_entry("ep_accept", "猎杀者试炼 · 接取", "序章", _status_by(accept),
		"轮回乐园", "灰潮港 · 任务委托所",
		"在委托所接下第一个任务，再从北侧传送阵出发。",
		"「第一个任务，废品终点站。」\n\n任务已刻进你的契约印记，出发吧。",
		accept, []))
	return out

## 序章推进档位：0 船到港 / 1 演武场教学 / 2 待接任务 / 3 已接待出发 / 4 已出发（序章结束）。
## 旧档与调试档 flow 为空串时按 4 处理（当作已走完序章）。
static func _pre_step(flow: String) -> int:
	match flow:
		"ship": return 0
		"training": return 1
		"equipped": return 2
		"quested": return 3
		_: return 4

# ---------------------------------------------------------------- 主线

static func _main_line(c: Dictionary) -> Array:
	var out: Array = []
	for i in Data.STAGES.size():
		var stage: Dictionary = Data.STAGES[i]
		out.append(_entry("stage_%d" % i, str(stage["name"]), "主线", _stage_status(i, c),
			"轮回乐园", str(PLACES[i]) if i < PLACES.size() else "",
			str(stage.get("brief", "")), str(stage.get("story", "")),
			_stage_objectives(i, c), _stage_rewards(i), _stage_records(i, c)))
	return out

## 当前地区：未清场 = 进行中，已清场待离场 = 待交接；走过的 = 已完成，没到的 = 未解锁。
## 任务还没接取（序章档位 < 3）时整条主线都压成未解锁。
static func _stage_status(i: int, c: Dictionary) -> String:
	if not _stage_unlocked(c):
		return LOCKED
	if _past(c, i):
		return DONE
	if i > int(c.get("stage", 0)):
		return LOCKED
	return PENDING if bool(c.get("cleared", false)) else ACTIVE

## 该地区是否已经走完（清场后离开，或整轮已结算回港）。
static func _past(c: Dictionary, i: int) -> bool:
	if bool(c.get("hub", false)) and bool(c.get("settled", false)):
		return true
	return int(c.get("stage", 0)) > i

static func _stage_objectives(i: int, c: Dictionary) -> Array:
	var past := _past(c, i)
	var here := int(c.get("stage", 0)) == i and bool(c.get("cleared", false))
	var tutorials: Dictionary = c.get("tutorial_steps", {})
	match i:
		0:
			return [
				_obj("击败持械流民", past or _killed(c, "0_0")),
				_obj("靠近战利品标记按 %s 领取" % KeyBindings.key_text("interact"), past or here),
				_obj("前往北侧出口传送门", past),
			]
		1:
			return [
				_obj("击败黑市商人·卡洛斯", past or _killed(c, "1_0")),
				_obj("装备并试射燧发枪", past or bool(tutorials.get("gun", false))),
				_obj("开启卡洛斯白色宝箱 · 取得引荐信", past or _bag(c, "letter") > 0),
				_obj("携引荐信前往北侧出口", past),
			]
		2:
			return [
				_obj("通过考核教官的实战考核", past or _killed(c, "2_0")),
				_obj("使用直踹", past or bool(tutorials.get("kick", false))),
				_obj("使用影刺", past or bool(tutorials.get("shadow", false))),
				_obj("取得斩龙闪", past or _bag(c, "dragon") > 0 or _equipped(c, "dragon")),
				_obj("装备斩龙闪并完成技能练习后前往北侧出口", past),
			]
		3:
			return [
				_obj("击败布兰登·欧卡", past or _killed(c, "3_0")),
				_obj("清掉欧卡的护卫", past or _killed(c, "3_1")),
				_obj("释放刀芒", past or bool(tutorials.get("wave", false))),
				_obj("释放环断", past or bool(tutorials.get("ring", false))),
				_obj("开启欧卡白色宝箱", past or _bag(c, "pendant") > 0),
				_obj("整备后前往科尔波山外围", past),
			]
		_:
			return [
				_obj("清理外围三波威胁", past or bool(c.get("colpo_outer_cleared", false))),
				_obj("开启傲歌护盾", past or bool(tutorials.get("shield", false))),
				_obj("开启猎魔", past or bool(tutorials.get("hunter", false))),
				_obj("预埋一枚陷阱引出巨虎", past or bool(c.get("tutorial_steps", {}).get("trap", false))),
				_obj("猎杀科尔波山巨虎", past or _killed(c, "tiger")),
				_obj("开启巨虎的绿色宝箱", past or _bag(c, "claw") > 0 or _bag(c, "crystal") > 0),
				_obj("领取战利品并完成阶段结算", past or bool(c.get("settled", false))),
			]

static func _stage_rewards(i: int) -> Array:
	var out: Array = []
	var stage: Dictionary = Data.STAGES[i]
	var loot: Dictionary = stage.get("loot", {})
	for id in loot:
		out.append("%s ×%d" % [_item_name(str(id)), int(loot[id])])
	if float(stage.get("source", 0.0)) > 0.0:
		out.append("世界之源 +%.1f%%" % float(stage.get("source", 0.0)))
	out.append("沿途场景宝箱：火药陷阱 · 恢复药剂 · 随机本土装备")
	if i >= 4:
		out.append("阶段结算：属性点 · 乐园币（按本轮世界之源折算）")
	return out

## 当前地区额外展示的进度行（世界之源只在本轮进行中才有意义，结算回港后不再显示）。
static func _stage_records(i: int, c: Dictionary) -> Array:
	if not _stage_unlocked(c) or _past(c, i) or i != int(c.get("stage", 0)):
		return []
	return [
		"本轮世界之源 %.1f%%" % float(c.get("source", 0.0)),
		"噬灵者法力 %d / 100" % int(c.get("world_mana", 0)),
	]

## 任务是否已接取（序章档位 < 3 时主线还没上桌，不该显示世界之源之类的本轮进度）。
static func _stage_unlocked(c: Dictionary) -> bool:
	return _pre_step(str(c.get("flow", ""))) >= 3

# ---------------------------------------------------------------- 支线

static func _sides(c: Dictionary) -> Array:
	var out: Array = []
	var tooth := [
		_obj("猎杀科尔波山巨虎", _killed(c, "tiger")),
		_obj("取得虎齿", _bag(c, "tiger_tooth") > 0),
		_obj("交付左大臣的藏品（后续版本开放）", false),
	]
	out.append(_entry("side_tiger", "左大臣的藏品 · 虎齿", "支线", _status_by(tooth),
		"港务委托所", "科尔波山 → 灰潮港",
		"猎杀科尔波山巨虎，取得虎齿。",
		"登记官点了点公告板：\n\n「左大臣点名要那畜生的牙。牙到手就算你有本事 —— 交货的门路还没开。」",
		tooth, ["虎齿 ×1（交付后续版本开放）"]))
	var chests := [
		_obj("1.2 废品终点站补给箱", _chest(c, "arena_0")),
		_obj("1.3 王都入口补给箱", _chest(c, "arena_1")),
		_obj("1.4 侍卫总部补给箱", _chest(c, "arena_2")),
		_obj("1.5 欢乐街补给箱", _chest(c, "arena_3")),
		_obj("1.6 科尔波山外围补给箱", _chest(c, "outer")),
		_obj("1.6 决战空地补给箱", _chest(c, "clearing")),
	]
	out.append(_entry("side_chest", "沿途补给箱", "支线", _status_by(chests),
		"轮回乐园", "各试炼场地",
		"每个地区都藏着一口场景宝箱，路过就开。",
		"轮回乐园在每块试炼场地都留了一口补给箱 —— 白盒阶段的固定产出是\n火药陷阱 ×1、恢复药剂 ×1 与一件随机本土装备。\n\n本土装备带不出本世界，结算时清除。",
		chests, ["火药陷阱 ×1 · 恢复药剂 ×1 · 随机本土装备"]))
	return out

# ---------------------------------------------------------------- 记录

static func _record(c: Dictionary) -> Array:
	var report := str(c.get("report", ""))
	if report == "":
		return []
	var lines: Array = []
	for line in report.split("\n"):
		if str(line).strip_edges() != "":
			lines.append(str(line))
	var out := [_entry("rec_settle", "阶段试炼结算 · 第 %d 轮" % int(c.get("run", 1)), "记录", DONE,
		"轮回乐园", "灰潮港 · 传送广场",
		"本轮试炼的结算结果。",
		"收益已入账。下一轮试炼仍从废品终点站开始，世界之源归零重算。",
		[], [], lines)]
	return out

# ---------------------------------------------------------------- 工具

static func _entry(id: String, name: String, kind: String, status: String,
		giver: String, place: String, brief: String, story: String,
		objectives: Array, rewards: Array, records: Array = []) -> Dictionary:
	return {"id": id, "name": name, "kind": kind, "status": status,
		"giver": giver, "place": place, "brief": brief, "story": story,
		"objectives": objectives, "rewards": rewards, "records": records}

static func _obj(text: String, done: bool) -> Dictionary:
	return {"text": text, "done": done}

## 状态由目标完成度推出：全完成 = 已完成，全没完成 = 未解锁，其余 = 进行中。
static func _status_by(objectives: Array) -> String:
	if objectives.is_empty():
		return LOCKED
	var done := 0
	for obj in objectives:
		if bool(obj["done"]):
			done += 1
	if done == objectives.size():
		return DONE
	return LOCKED if done == 0 else ACTIVE

static func _killed(c: Dictionary, id: String) -> bool:
	return c.get("kills", []).has(id)

static func _bag(c: Dictionary, id: String) -> int:
	return int(c.get("bag", {}).get(id, 0))

static func _equipped(c: Dictionary, id: String) -> bool:
	for slot in c.get("equipment", {}):
		if str(c["equipment"][slot]) == id:
			return true
	return false

static func _chest(c: Dictionary, key: String) -> bool:
	return c.get("opened_chests", []).has(key)

static func _item_name(id: String) -> String:
	return str(Data.ITEMS.get(id, {}).get("name", id))
