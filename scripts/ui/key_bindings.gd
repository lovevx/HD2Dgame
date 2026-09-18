extends RefCounted
## 按键映射的唯一数据源：HUD 底部提示条与 F1 说明面板都从这里取，避免两处文案走偏。
## 键位依据 docs/COMBAT_SPEC_SUXIAO.md v1.1 的按键表；status 反映当前工程实际进度，
## 换键（任务 A01）或实装新技能后，回来改这一份即可。

const READY := 1     # 已实装：当前版本按键有效
const PLANNED := 2   # 键位已定，功能随后续任务接入
const DEFERRED := 3  # P1 明确后置，暂不制作

## 底部提示条：只列当前真正能按出来的键。换键后同步这一行。
const HINT := "WASD 移动 · 左键 朝鼠标连击 · 右键 副手武器 · Shift 剃 · 数字 1 炸弹 · 数字 2 药剂 · V 交互 · C 角色面板 · F1 按键说明"

const GROUPS := [
	{
		"title": "移动与位移",
		"entries": [
			{"keys": "W A S D", "action": "移动 / 战斗奔跑 / 走位拉扯", "status": READY},
			{"keys": "Left-Shift", "action": "六式・剃：地面高速突进闪避，带冷却，空中不可用", "status": READY},
			{"keys": "鼠标移动", "action": "平移镜头取景；指针为游戏内剑刃光标（战斗中系统光标隐藏）", "status": READY},
		],
	},
	{
		"title": "近战",
		"entries": [
			{"keys": "鼠标左键", "action": "正手劈砍 / 反手突刺，最多三段连击，朝鼠标所指方向出手", "status": READY},
			{"keys": "无按键", "action": "拼刀格挡：双方近战有效帧重叠时自动触发，双方都不结算伤害", "status": READY},
		],
	},
	{
		"title": "刀术",
		"entries": [
			{"keys": "R", "action": "刀芒：中距离远程刀气，只打物理伤害", "status": PLANNED},
			{"keys": "F", "action": "环断：原地环形刀芒，清包围的复数敌人，耗蓝更高", "status": PLANNED},
			{"keys": "T", "action": "影刺：必须先刺击命中敌人，能量从敌人体内爆发", "status": PLANNED},
		],
	},
	{
		"title": "青钢影（能量）",
		"entries": [
			{"keys": "Q", "action": "猎魔：开启 / 关闭，燃烧敌人能量打真实伤害", "status": PLANNED},
			{"keys": "E", "action": "傲歌：生成 / 撤销能量护盾，有吸收上限与时限", "status": PLANNED},
		],
	},
	{
			"title": "道具与远程",
			"entries": [
				{"keys": "鼠标右键", "action": "副手武器（燧发枪）：远程射击，弹药有限；副手槽需装备副武器", "status": READY},
				{"keys": "数字 1", "action": "炼金炸弹：投掷输出，或预埋地面做陷阱", "status": READY},
				{"keys": "数字 2", "action": "药剂：回复生命，每局携带量有限", "status": READY},
			],
		},
	{
		"title": "侦查与其他",
		"entries": [
			{"keys": "Tab", "action": "使徒之眼：侦查敌人威胁等级（黑色 = 极高威胁）", "status": DEFERRED},
			{"keys": "鼠标中键", "action": "吞噬之核：贴脸读条吸收敌人高等能量", "status": DEFERRED},
			{"keys": "V", "action": "交互：传送门、NPC、撤离信标与可交互物", "status": READY},
			{"keys": "C", "action": "角色面板：左侧人物形象 + 装备栏，右侧六维属性与可用属性点", "status": READY},
			{"keys": "Esc", "action": "面板 / 菜单：返回选关", "status": READY},
			{"keys": "F1", "action": "按键映射说明（本面板）", "status": READY},
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
