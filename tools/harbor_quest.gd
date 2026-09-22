extends RefCounted
## 灰潮港西侧「港务委托所」（任务功能区）：
## 沿任务巷北侧起一处带前院的委托所——主楼挂匾额、门前设公告板与登记柜台、
## 门口一对石狮与石灯，副楼在缺口以西单独成院，巷南侧摆下等号的石桌竹椅与书架，
## 把「任务接取与交付」读成一处官署模样的办事机构。
##
## 素材：只用已入库的 assets/hd2d_presets 共享预设，不新增美术。
## 坐标基准：地面 y=0；任务巷 z=1（铺装 z∈[-0.7,2.7]、x∈[-14,18]）；
##   主街 x∈[-3,3] 是南北主路；陆地基座 x∈[-42,42]、z∈[-32,12]；
##   西北角商店区占 x∈[-35,-5]、z∈[-28,-14]，与本区不重叠。
## 实测 AABB（tools/probe_quest_forge_presets.gd；这批预设原点均在脚底中心）：
##   SM_JN_fangzi002 9.00×5.30×6.33（主楼，宽单层铺面）/ SM_JN_fangzi005 6.00×5.28×6.33（副楼）
##   SM_NJ_ZhuPai002 与 SM_Item_paizi002 均 2.05×3.73×0.36（公告板）
##   SM_Item_guitai002 1.00×0.81×0.94（登记柜台）/ SM_xgg_yjzptong001 0.90×1.43×0.90（卷轴筒）
##   SM_xgg_yjzpjuanzhou001 0.16×0.74×0.16（卷轴）/ SM_xhj_shenkan002 1.39×3.60×1.39（神龛）
##   SM_Item_shishizi001 0.67×1.53×1.03（石狮）/ SM_gsc_gusuchengpaizi001 4.00×1.50×0.19（匾额）
##
## 碰撞：铺面、石狮、石灯、柜台、卷轴筒、神龛、坐具沿用预设自带碰撞（COLLIDE_PRESET）；
##   卷轴、匾额、招牌、前院地贴是薄片/0 高度贴片，必须 COLLIDE_OFF。
##
## 布置约束（别踩）：
##   · 服务点可达断言走 z=0.5 的东西向直线（x 从 0 到 -10），这条线必须净空。
##     门前陈设排压到 z≤-2.1 之后，与 0.5 仍留 2.6 米以上。
##   · 主街 x∈[-3,3] 是南北主路，且 check_harbor_port 还测了 (-4,0,-4)→(-4,0,-1) 这条线：
##     主楼东沿收到 x=-5.5，东侧 2.5 米一律不摆东西。
##   · 已经有灯柱 LanternPost 立在 (-13.7, 0, -1)（harbor_lighting.gd），别在这里摆东西。
##   · 副楼必须留在 x≤-20.5：check_harbor_port 有一条「(-20,0,-7) 向 -z 可走」的历史断言，
##     摆到 x=-20 一带会把它顶成 FAIL。

const PortLayout := preload("res://tools/harbor_port_layout.gd")

const NODE_NAME := "QuestDistrict"

## 服务点（交互圈圆心）：主楼门前广场中线，与 harbor_zones.gd 的 QuestService 一致。
const SERVICE_AT := Vector3(-10.0, 0.0, 0.5)

## 任务巷净空带（铺装 z∈[-0.7,2.7]）：门前陈设一律不进这条带。
const LANE := Vector2(-0.7, 2.7)
## 铺面排：南墙在 z=-2.83，门面朝南对着任务巷。
const ROW_Z := -6.0
const FRONTAGE_Z := -2.83
## 门前陈设排（贴铺面南墙，离净空带 2.5 米以上）。
const STALL_LINE := -2.3
## 巷南侧收尾排（任务巷以南，留给等号的办事人）。
const SOUTH_LINE := 4.2


static func make_node() -> Node3D:
	var holder := Node3D.new()
	holder.name = NODE_NAME
	_office_row(holder)
	_frontage(holder)
	_forecourt(holder)
	_south_side(holder)
	_lights(holder)
	return holder


## 北排委托所（立面朝南，正对任务巷）：主楼对准服务点，副楼在 6 米缺口以西单独成院。
##
## ※ 与商店区同一条约束：这批民居预设**只有南立面有门窗**，一律 yaw 0 面朝南。
## ※ 主楼与副楼之间刻意留出 6 米缺口当委托所前院（也避开 (-20,-7) 那条历史通行断言）。
static func _office_row(holder: Node3D) -> void:
	# 主楼：宽单层铺面，正对服务点，两侧挂匾额与公告板。
	PortLayout.prop(holder, "SM_JN_fangzi002", Vector3(-10.0, 0.0, ROW_Z), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 副楼：西端单层屋舍，与前院一起把立面拉到 x=-26.5。
	PortLayout.prop(holder, "SM_JN_fangzi005", Vector3(-23.5, 0.0, ROW_Z), 0.0, 1.0, PortLayout.COLLIDE_PRESET)


## 主楼门前：匾额、公告板、登记柜台与卷轴、石狮、石灯、神龛。
static func _frontage(holder: Node3D) -> void:
	# 匾额：门楣上方，嵌进墙面露出一指厚（单层楼，压在檐口下沿）。
	PortLayout.prop(holder, "SM_gsc_gusuchengpaizi001", Vector3(-10.0, 3.60, -2.72), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	# 公告板两座：分立大门两侧，朝街心——委托所最要紧的一件家具。
	PortLayout.prop(holder, "SM_NJ_ZhuPai002", Vector3(-11.9, 0.0, STALL_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_paizi002", Vector3(-22.0, 0.0, STALL_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 登记柜台：门前正中，办事的人站在柜台外。
	PortLayout.prop(holder, "SM_Item_guitai002", Vector3(-10.0, 0.0, -2.2), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 柜台上的卷轴与旁边立着的卷轴筒（薄片，关碰撞）。
	PortLayout.prop(holder, "SM_xgg_yjzpjuanzhou001", Vector3(-10.0, 0.81, -2.2), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	PortLayout.prop(holder, "SM_xgg_yjzptong001", Vector3(-15.3, 0.0, STALL_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 石狮一对：蹲在门两侧的空档里。
	PortLayout.prop(holder, "SM_Item_shishizi001", Vector3(-7.6, 0.0, -2.2), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_shishizi001", Vector3(-6.6, 0.0, -2.2), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 石灯：门前一盏（另一盏在副楼前），贴门脸立在柜台与公告板之间。
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(-9.0, 0.0, -2.2), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	# 神龛：门西角落，嵌进墙面半步。
	PortLayout.prop(holder, "SM_xhj_shenkan002", Vector3(-13.9, 0.0, -2.4), 0.0, 1.0, PortLayout.COLLIDE_PRESET)


## 前院：主楼与副楼之间的 6 米缺口，铺一块地砖当办事人排队的院子。
## 地贴是 0 高度贴片，必须 COLLIDE_OFF。
static func _forecourt(holder: Node3D) -> void:
	PortLayout.prop(holder, "SM_mjsz_diban001", Vector3(-17.5, 0.005, -4.0), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(-19.8, 0.0, -1.4), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(-15.2, 0.0, -1.4), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_NJhuojia016", Vector3(-17.5, 0.0, -1.5), 0.0, 1.0, PortLayout.COLLIDE_PRESET)


## 巷南侧（任务巷以南）：等号用的石桌竹椅、书架与招幌。
static func _south_side(holder: Node3D) -> void:
	# 石桌石凳：一组，摆在委托所正对面。
	PortLayout.prop(holder, "SM_mjsz_shizhuozi001", Vector3(-9.0, 0.0, SOUTH_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_mjsz_Mudunzi001", Vector3(-7.6, 0.0, SOUTH_LINE), -20.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_mjsz_Mudunzi001", Vector3(-10.4, 0.0, SOUTH_LINE), 20.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 竹桌椅：茶座角，往东错开一组，别和石桌挤在一起。
	PortLayout.prop(holder, "SM_NJ_ZhuZhuozi001", Vector3(-14.6, 0.0, SOUTH_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ZhuYizi001", Vector3(-13.7, 0.0, SOUTH_LINE), -70.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ZhuYizi001", Vector3(-15.5, 0.0, SOUTH_LINE), 70.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 书架：跟卷轴呼应的一排，立在竹桌椅西侧。
	PortLayout.prop(holder, "SM_Item_NJhuojia016", Vector3(-17.8, 0.0, SOUTH_LINE - 0.2), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 招幌：立在副楼西侧外沿（不给主街添竖向遮挡——3.88×6.2 的旗摆到主街边会顶进
	# (-4,0,-4) 那台机位的视线，check_occlusion_fade 的「石板街中段 单元数=0」立刻 FAIL）。
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(-28.5, 0.0, -3.0), 8.0, 0.9, PortLayout.COLLIDE_PRESET)
	# 巷口木牌：立在任务巷南侧当路标。**必须躲开主街 x=-4 那条列**——港口机位与玩家同 x，
	# 「镜头→玩家」的射线是一条竖列，木牌包围盒东沿压到 -4 就会顶进 (-4,0,-4) 那台机位的视线。
	PortLayout.prop(holder, "SM_NJ_ZhuPai002", Vector3(-5.7, 0.0, 4.6), 0.0, 1.0, PortLayout.COLLIDE_PRESET)


## 灯光：青绿灯打在匾额与公告板上（呼应任务功能区的分区色），门口与副楼各一盏暖色门灯。
static func _lights(holder: Node3D) -> void:
	var jade := OmniLight3D.new()
	jade.name = "QuestSignGlow"
	jade.position = Vector3(-10.0, 3.9, -3.4)
	jade.light_color = Color("a4efc2")
	jade.light_energy = 2.2
	jade.omni_range = 8.0
	jade.omni_attenuation = 1.4
	jade.light_size = 0.3
	jade.light_volumetric_fog_energy = 0.4
	holder.add_child(jade)
	var door := OmniLight3D.new()
	door.name = "QuestDoorLantern"
	door.position = Vector3(-10.0, 2.1, -2.6)
	door.light_color = Color("ffc17b")
	door.light_energy = 2.4
	door.omni_range = 6.5
	door.omni_attenuation = 1.5
	door.light_size = 0.2
	door.light_volumetric_fog_energy = 0.35
	holder.add_child(door)
	_lamp(holder, Vector3(-9.0, 0.0, -2.2), 3.4, 6.0)
	_lamp(holder, Vector3(-19.8, 0.0, -1.4), 3.0, 5.5)
	var west := OmniLight3D.new()
	west.name = "QuestWestLantern"
	west.position = Vector3(-23.5, 2.4, -2.6)
	west.light_color = Color("ffc98a")
	west.light_energy = 2.8
	west.omni_range = 7.5
	west.omni_attenuation = 1.5
	west.light_size = 0.25
	west.light_volumetric_fog_energy = 0.4
	holder.add_child(west)


## 门灯：石灯上方一盏暖色点光（与商店区、码头岸灯同一套做法）。
static func _lamp(parent: Node3D, at: Vector3, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.name = "QuestLantern"
	light.position = at + Vector3(0, 1.62, 0)
	light.light_color = Color("ffc17b")
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.light_size = 0.2
	light.light_volumetric_fog_energy = 0.4
	parent.add_child(light)
