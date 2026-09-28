extends RefCounted
## 按键映射的唯一数据源：HUD 底部提示条、F1 说明面板与设置页的「按键」表都从这里取，
## 避免三处文案走偏。**键名一律现读 InputMap**，所以玩家在设置页改键之后，
## 提示条与说明面板会跟着变 —— 两张表里只留「这个键干什么」的短语，不留键名副本。
##
## 条目字段约定（两张表一致）：
##   binds / bind = InputMap 动作名（列表 / 单个），键名现读，可在设置页改；
##   keys         = 写死的键名（鼠标手势、后置功能）或「无按键」；
##   desc         = 这个键干什么（唯一的文案正本）。
##
## 键位依据 docs/REALTIME_COMBAT_EXTRACTION.md；status 反映当前工程实际进度。
## 默认键位本身的正本是 project.godot 的 [input]，这里不抄副本。

const READY := 1     # 已实装：当前版本按键有效
const PLANNED := 2   # 键位已定，功能随后续任务接入
const DEFERRED := 3  # P1 明确后置，暂不制作

## 键名显示用的中文别名（其余交给 OS.get_keycode_string）。
const KEY_ALIAS := {
	KEY_SPACE: "空格", KEY_ESCAPE: "Esc", KEY_SHIFT: "Shift", KEY_TAB: "Tab",
	KEY_ENTER: "回车", KEY_BACKSPACE: "退格", KEY_DELETE: "Del",
	KEY_UP: "↑", KEY_DOWN: "↓", KEY_LEFT: "←", KEY_RIGHT: "→",
}
const MOUSE_ALIAS := {
	MOUSE_BUTTON_LEFT: "左键", MOUSE_BUTTON_RIGHT: "右键", MOUSE_BUTTON_MIDDLE: "中键",
	MOUSE_BUTTON_XBUTTON1: "侧键1", MOUSE_BUTTON_XBUTTON2: "侧键2",
}
const WHEEL_BUTTONS := [
	MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT,
]

## 底部提示条：只列当前真正能按出来的键（顺序＝玩家上手顺序）。
const HINT_ITEMS := [
	{"binds": ["move_up", "move_left", "move_down", "move_right"], "desc": "移动"},
	{"bind": "dodge", "desc": "剃"},
	{"bind": "kick", "desc": "直踹"},
	{"bind": "attack", "desc": "斩击"},
	{"bind": "shoot", "desc": "枪"},
	{"bind": "hunter_toggle", "desc": "猎魔"},
	{"bind": "aoge", "desc": "护盾"},
	{"bind": "huanduan", "desc": "环断"},
	{"bind": "sword_wave", "desc": "刀芒"},
	{"bind": "shadow_stab", "desc": "影刺"},
	{"bind": "bomb", "desc": "陷阱"},
	{"bind": "potion", "desc": "药剂"},
	{"bind": "interact", "desc": "交互"},
	{"bind": "character_panel", "desc": "背包"},
	{"bind": "quest_log", "desc": "任务"},
]

## 可在设置页改键的动作（顺序即「按键」页的行序，group 相同的归到同一小节）。
## 只列玩家真正会按的动作：run（Shift）在工程里没有任何消费方，故不列出；
## 「鼠标中键拖动取景 / 滚轮推拉」是 camera_orbit_controls 里硬判的按钮、不是 InputMap 动作，
## 改不了，所以只在 F1 说明里出现，不进改键表。
const REBINDABLE := [
	{"group": "移动与位移", "bind": "move_up", "label": "向上移动"},
	{"group": "移动与位移", "bind": "move_down", "label": "向下移动"},
	{"group": "移动与位移", "bind": "move_left", "label": "向左移动"},
	{"group": "移动与位移", "bind": "move_right", "label": "向右移动"},
	{"group": "移动与位移", "bind": "dodge", "label": "六式・剃（闪避）"},
	{"group": "近战与道具", "bind": "attack", "label": "斩击"},
	{"group": "近战与道具", "bind": "kick", "label": "直踹（眩晕 / 处决）"},
	{"group": "近战与道具", "bind": "shoot", "label": "燧发枪（副手）"},
	{"group": "近战与道具", "bind": "bomb", "label": "炼金炸弹 / 陷阱"},
	{"group": "近战与道具", "bind": "potion", "label": "饮用药剂"},
	{"group": "刀术与青钢影", "bind": "huanduan", "label": "环断"},
	{"group": "刀术与青钢影", "bind": "sword_wave", "label": "刀芒"},
	{"group": "刀术与青钢影", "bind": "shadow_stab", "label": "影刺"},
	{"group": "刀术与青钢影", "bind": "hunter_toggle", "label": "猎魔（开关）"},
	{"group": "刀术与青钢影", "bind": "aoge", "label": "傲歌（护盾）"},
	{"group": "界面", "bind": "interact", "label": "交互 / 拾取"},
	{"group": "界面", "bind": "character_panel", "label": "角色背包"},
	{"group": "界面", "bind": "quest_log", "label": "任务档案"},
	{"group": "界面", "bind": "key_guide", "label": "按键说明"},
	{"group": "界面", "bind": "open_menu", "label": "菜单 / 返回"},
]

## 战斗关卡 F1 说明的四行键位（键名现读，改键后 HUD 会重算这些 Label）。
const CAMPAIGN_GUIDE_LINES := [
	[
		{"binds": ["move_up", "move_left", "move_down", "move_right"], "desc": "移动"},
		{"keys": "鼠标中键拖动", "desc": "取景"},
		{"bind": "attack", "desc": "斩击"},
		{"bind": "dodge", "desc": "剃"},
	],
	[
		{"bind": "shoot", "desc": "燧发枪（需装备）"},
		{"bind": "kick", "desc": "直踹"},
		{"bind": "bomb", "desc": "火药陷阱"},
		{"bind": "potion", "desc": "饮用药剂"},
	],
	[
		{"bind": "hunter_toggle", "desc": "猎魔"},
		{"bind": "aoge", "desc": "傲歌"},
		{"bind": "huanduan", "desc": "环断"},
		{"bind": "sword_wave", "desc": "刀芒"},
		{"bind": "shadow_stab", "desc": "影刺"},
	],
	[
		{"bind": "interact", "desc": "遭遇 / 拾取 / 港口服务"},
		{"bind": "character_panel", "desc": "装备背包"},
		{"bind": "open_menu", "desc": "菜单"},
	],
]

## F1 说明面板的分组表。
const GROUPS := [
	{
		"title": "移动与位移",
		"entries": [
			{"binds": ["move_up", "move_left", "move_down", "move_right"], "desc": "移动 / 奔跑（常驻移动模式即跑步）", "status": READY},
			{"bind": "dodge", "desc": "六式・剃：地面高速突进闪避，带冷却，空中不可用", "status": READY},
			{"keys": "鼠标中键拖动", "desc": "轨道镜头：左右拖动改朝向，上下拖动抬高俯角（面板打开时不生效）", "status": READY},
			{"keys": "滚轮", "desc": "推拉镜头：拉近 / 拉远相机与角色的距离（面板打开时不生效）", "status": READY},
		],
	},
	{
		"title": "近战",
		"entries": [
			{"bind": "attack", "desc": "单段斩击，朝鼠标所指方向出手；命中留下影缝标记", "status": READY},
			{"bind": "kick", "desc": "直踹：高眩晕值技，负责把敌人打进眩晕，也是小怪眩晕态的处决手段", "status": READY},
		],
	},
	{
		"title": "刀术",
		"entries": [
			{"bind": "huanduan", "desc": "环断：原地环形刀芒，清包围的复数敌人，耗蓝更高", "status": READY},
			{"bind": "sword_wave", "desc": "刀芒：朝鼠标方向发射直线刀波，耗蓝并有冷却", "status": READY},
			{"bind": "shadow_stab", "desc": "影刺：斩击留下影缝标记后，贴近目标突刺并造成真实伤害", "status": READY},
		],
	},
	{
		"title": "青钢影（能量）",
		"entries": [
			{"bind": "hunter_toggle", "desc": "猎魔：开启 / 关闭，对能量敌人附加穿透物理减免的伤害", "status": READY},
			{"bind": "aoge", "desc": "傲歌：生成 / 撤销能量护盾，有吸收上限与时限", "status": READY},
		],
	},
	{
		"title": "道具与远程",
		"entries": [
			{"bind": "shoot", "desc": "副手武器（燧发枪）：远程射击，弹药有限；副手槽需装备副武器", "status": READY},
			{"bind": "bomb", "desc": "炼金炸弹：投掷输出，或预埋地面做陷阱", "status": READY},
			{"bind": "potion", "desc": "药剂：回复生命，每局携带量有限", "status": READY},
		],
	},
	{
		"title": "侦查与其他",
		"entries": [
			{"keys": "Tab", "desc": "使徒之眼：侦查敌人威胁等级（黑色 = 极高威胁）", "status": DEFERRED},
			{"keys": "待重新指定", "desc": "吞噬之核：贴脸读条吸收敌人高等能量（原鼠标中键，已改作轨道镜头）", "status": DEFERRED},
			{"bind": "interact", "desc": "交互：NPC、港口服务、场景宝箱与撤离信标（传送门走进即触发，不用按键）", "status": READY},
			{"bind": "character_panel", "desc": "角色面板：左侧人物形象 + 装备栏，右侧六维属性与可用属性点", "status": READY},
			{"bind": "quest_log", "desc": "任务面板：左侧任务名列表（分章 + 状态），右侧选中任务的目标 / 说明 / 奖励", "status": READY},
			{"bind": "open_menu", "desc": "面板 / 菜单：返回选关", "status": READY},
			{"bind": "key_guide", "desc": "按键映射说明（本面板）", "status": READY},
		],
	},
]

static func status_text(status: int) -> String:
	match status:
		READY:
			return "可用"
		PLANNED:
			return "规划中"
		_:
			return "后置"

static func status_color(status: int) -> Color:
	match status:
		READY:
			return Color("7ee0a0")
		PLANNED:
			return Color("d8b46a")
		_:
			return Color("7f949b")

# ---------------------------------------------------------------- 键名读取
# 以下四支是「键名现读」的全部出入口：hud 提示条 / hud 说明面板 / 设置页改键表都走它们。

## 某个条目当前的按键显示名。三选一：动作组（各键名直接拼接，W+A+S+D → WASD）、
## 单个动作、或写死的 keys（鼠标手势与后置功能）。
static func keys_of(item: Dictionary) -> String:
	if item.has("binds"):
		var joined := ""
		for action in item["binds"]:
			joined += key_text(str(action))
		return joined
	var bound := str(item.get("bind", ""))
	if bound != "":
		return key_text(bound)
	return str(item.get("keys", ""))

## 一个动作当前绑定的键名（取第一个事件；本工程的默认动作都是单事件）。
static func key_text(action: String) -> String:
	if not InputMap.has_action(action):
		return "未绑定"
	var events := InputMap.action_get_events(action)
	if events.is_empty():
		return "未绑定"
	return event_text(events[0])

static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if KEY_ALIAS.has(code):
			return KEY_ALIAS[code]
		return OS.get_keycode_string(code)
	if event is InputEventMouseButton:
		var index := (event as InputEventMouseButton).button_index
		return MOUSE_ALIAS.get(index, "鼠标键 %d" % index)
	return "—"

## 把「键 + 短语」列表拼成一行提示（底部提示条与说明面板的行共用）。
static func line(items: Array) -> String:
	var parts: Array[String] = []
	for item in items:
		parts.append("%s %s" % [keys_of(item), item["desc"]])
	return " · ".join(parts)

## 底部提示条的当前文案。
static func hint_text() -> String:
	return line(HINT_ITEMS)

# ---------------------------------------------------------------- 改键用的事件打包

## 把捕获到的输入事件打包成可存盘的描述：{"kind": "key"/"mouse", "code": int}。
## 不可绑定的（滚轮、无键码的事件）返回空字典，调用方据此忽略这一次捕获。
static func binding_of(event: InputEvent) -> Dictionary:
	if event is InputEventMouseButton:
		var index := (event as InputEventMouseButton).button_index
		if WHEEL_BUTTONS.has(index):
			return {}
		return {"kind": "mouse", "code": index}
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			return {}
		return {"kind": "key", "code": code}
	return {}
