extends RefCounted
## 灰潮港东侧「铸潮工坊」（装备强化区）：
## 沿强化巷北侧起一排锻造铺面——西端两层锻造楼 + 东端宽车间，
## 门前设熔炉与烟囱、锻造台、武器架、淬火缸、石灯，立面上挂矿石标本与招牌，
## 街南侧收矿石石堆、魔晶与料箱，把「装备强化」读成一处开工的铁匠铺。
##
## 素材：只用已入库的 assets/hd2d_presets 共享预设，不新增美术。
## 坐标基准：地面 y=0；强化巷 z=-9（铺装 z∈[-10.7,-7.3]、x∈[-14,18]）；
##   主街 x∈[-3,3] 是南北主路；陆地基座 x∈[-42,42]、z∈[-32,12]。
## 实测 AABB（tools/probe_quest_forge_presets.gd；这批预设原点均在脚底中心）：
##   SM_JN_fangzi001 6.00×8.10×6.33（两层锻造楼）/ SM_JN_fangzi002 9.00×5.30×6.33（宽车间）
##   SM_Item_luzi001 1.67×2.45×1.73（熔炉）/ SM_Item_yancong002 1.24×3.97×1.24（烟囱）
##   SM_Item_zaotai001 2.97×0.88×1.87（锻造台）/ SM_gsc_gu002 1.86×1.47×1.86（淬火大缸）
##   SM_Item_NJhuojia001 2.15×2.00×1.15（武器架）/ SM_Item_damoshuijing001 4.16×3.12×3.44（魔晶）
##   SM_Item_*kuang001 2.88×1.19~1.56×0（矿石标本，0 厚度贴片）
##
## 碰撞：铺面、熔炉、烟囱、锻造台、武器架、水缸、水晶、石堆沿用预设自带碰撞（COLLIDE_PRESET）；
##   矿石标本、木柴、招牌是薄片/贴片，必须 COLLIDE_OFF。
##
## 布置约束（别踩）：
##   · 服务点可达断言走 z=-9 的东西向直线（x 从 0 到 10），这条线必须净空。
##     门前陈设排压到 z≤-11.3 之后，与 -9 仍留 2 米以上。
##   · 主街 x∈[-3,3] 是南北主路：工坊立面从 x=3 起，别往西探进主街。
##   · 已有灯柱 LanternPost 立在 (11.3, 0, -12)（harbor_lighting.gd），别在这里摆东西。
##   · 铺面南沿必须留在 z≤-12.3：灯柱 (11.3, -12) 要露在门外，不能被楼吞掉。

const PortLayout := preload("res://tools/harbor_port_layout.gd")

const NODE_NAME := "ForgeDistrict"

## 服务点（交互圈圆心）：门前广场中线，与 harbor_zones.gd 的 ForgeService 一致。
const SERVICE_AT := Vector3(10.0, 0.0, -9.0)

## 强化巷净空带（铺装 z∈[-10.7,-7.3]）：门前陈设一律不进这条带。
const LANE := Vector2(-10.7, -7.3)
## 铺面排：南墙在 z=-12.83，门面朝南对着强化巷。
const ROW_Z := -16.0
const FRONTAGE_Z := -12.83
## 门前陈设排（贴铺面南墙，离净空带 2 米以上）。
const STALL_LINE := -12.3
## 街南侧收尾排（强化巷以南，离净空带同样留足）。
const SOUTH_LINE := -5.2


static func make_node() -> Node3D:
	var holder := Node3D.new()
	holder.name = NODE_NAME
	_forge_row(holder)
	_frontage(holder)
	_yard(holder)
	_lights(holder)
	return holder


## 北排锻造铺面（立面朝南，正对强化巷）：西端两层锻造楼 + 东端宽车间。
## 两栋紧贴拼成 15 米连续立面（x 从 3 到 18），与强化巷东端 x=18 对齐收口。
##
## ※ 与商店区同一条约束：这批民居预设**只有南立面有门窗**，一律 yaw 0 面朝南，
##   别指望横转 90° 变出侧向店面（那只会露一面空白山墙）。
static func _forge_row(holder: Node3D) -> void:
	# 锻造楼：两层，自带二层立面，压在主街东沿收口。
	PortLayout.prop(holder, "SM_JN_fangzi001", Vector3(6.0, 0.0, ROW_Z), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 宽车间：单层长铺面，门窗齐全，把整排拉到 x=18。
	PortLayout.prop(holder, "SM_JN_fangzi002", Vector3(13.5, 0.0, ROW_Z), 0.0, 1.0, PortLayout.COLLIDE_PRESET)


## 门前：熔炉与烟囱、锻造台、武器架、淬火缸、石灯，加立面招牌与矿石标本。
static func _frontage(holder: Node3D) -> void:
	# 匾额：压在两栋的檐口之间（两层楼的二层窗沿），嵌进墙面半指深。
	PortLayout.prop(holder, "SM_gsc_gusuchengpaizi001", Vector3(6.0, 5.35, -12.87), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	# 车间小招牌：单层楼门楣上方，给东半幅一个竖向的路标。
	PortLayout.prop(holder, "SM_mjsz_jianxintingpaizi001", Vector3(13.5, 3.40, -12.90), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	# 矿石标本：四件贴片挂在立面外侧，横排展示"收来的料"（0 厚度，必须关碰撞）。
	for entry in [
			["SM_Item_Tiekuang001", Vector3(7.0, 1.40, -12.86)],
			["SM_Item_Wujingkuang001", Vector3(10.4, 1.50, -12.86)],
			["SM_Item_Huangtongkuang001", Vector3(13.8, 1.40, -12.86)],
			["SM_Item_Yingkuang001", Vector3(17.2, 1.50, -12.86)]]:
		PortLayout.prop(holder, entry[0], entry[1], 0.0, 1.0, PortLayout.COLLIDE_OFF)
	# 熔炉 + 烟囱：门面西端一组，炉体在前、烟囱在其东侧，读成"炉子连排烟道"。
	PortLayout.prop(holder, "SM_Item_luzi001", Vector3(4.2, 0.0, -12.4), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_yancong002", Vector3(6.3, 0.0, -12.35), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 锻造台：正对服务点，当"干活的那张台子"。
	PortLayout.prop(holder, "SM_Item_zaotai001", Vector3(8.6, 0.0, STALL_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 石灯：一盏立在炉子与锻造台之间，一盏给车间门口（灯柱在 x=11.3，别撞上）。
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(12.7, 0.0, -12.2), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	# 武器架两座：车间门口东侧，架上成排摆家伙。
	PortLayout.prop(holder, "SM_Item_NJhuojia001", Vector3(15.0, 0.0, STALL_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_NJhuojia002", Vector3(16.9, 0.0, STALL_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 淬火缸：两口，缸沿临街，是"打完水"的那一步。
	PortLayout.prop(holder, "SM_gsc_gu002", Vector3(18.6, 0.0, -12.4), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_gsc_gu001", Vector3(19.9, 0.0, -11.9), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 木柴垛：靠炉子西侧（薄片，关碰撞）。
	for entry in [[Vector3(3.2, 0.0, -12.0), 12.0], [Vector3(3.6, 0.0, -12.7), -24.0]]:
		PortLayout.prop(holder, "SM_Item_muchai001", entry[0], float(entry[1]), 1.0, PortLayout.COLLIDE_OFF)
	# 招幌：立在车间东山墙外，给整排一个高处的识别标志。
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(20.6, 0.0, -13.6), 8.0, 0.9, PortLayout.COLLIDE_PRESET)


## 街南侧（强化巷以南）：石料堆、大魔晶、货箱与坐具，把工坊街补成一条有来有往的巷子。
static func _yard(holder: Node3D) -> void:
	# 石料堆：贴地铺开，读成"等着下炉的料"。
	PortLayout.prop(holder, "SM_NJ_Shitoudui001", Vector3(5.2, 0.0, SOUTH_LINE - 0.6), 18.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_Shitoudui001", Vector3(7.4, 0.0, SOUTH_LINE + 0.4), -14.0, 0.85, PortLayout.COLLIDE_PRESET)
	# 大魔晶：街南侧的视觉重物，把"铸潮"的冷色意象立在巷口。
	PortLayout.prop(holder, "SM_Item_damoshuijing001", Vector3(13.5, 0.0, SOUTH_LINE - 0.9), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 货箱堆：车间对面，成组堆放。
	for entry in [
			[Vector3(19.6, 0.0, SOUTH_LINE - 0.4), 16.0, 1.3],
			[Vector3(20.5, 0.0, SOUTH_LINE + 0.9), -12.0, 1.15],
			[Vector3(18.5, 0.0, SOUTH_LINE + 1.0), 34.0, 1.2]]:
		PortLayout.prop(holder, "SM_Box001Close", entry[0], float(entry[1]), float(entry[2]), PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Box001Open", Vector3(21.4, 0.0, SOUTH_LINE - 0.2), -20.0, 1.25, PortLayout.COLLIDE_PRESET)
	# 石桌石凳：巷口歇脚处（工坊街也得有人坐得下）。
	PortLayout.prop(holder, "SM_mjsz_shizhuozi001", Vector3(10.2, 0.0, SOUTH_LINE - 1.2), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_mjsz_Mudunzi001", Vector3(8.8, 0.0, SOUTH_LINE - 1.0), -20.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_mjsz_Mudunzi001", Vector3(11.6, 0.0, SOUTH_LINE - 1.0), 20.0, 1.0, PortLayout.COLLIDE_PRESET)


## 灯光：炉火暖橙打熔炉与锻造台，门前与车间各一盏暖色门灯。
static func _lights(holder: Node3D) -> void:
	# 炉火：低矮、偏红、范围收在炉子周边，读成"炭火正旺"。
	var fire := OmniLight3D.new()
	fire.name = "ForgeFireGlow"
	fire.position = Vector3(4.2, 1.25, -12.2)
	fire.light_color = Color("ff7f3a")
	fire.light_energy = 3.2
	fire.omni_range = 6.5
	fire.omni_attenuation = 1.5
	fire.light_size = 0.25
	fire.light_volumetric_fog_energy = 0.4
	holder.add_child(fire)
	# 门灯：沿铺面排两盏暖色，把门口与武器架照亮。
	_lamp(holder, Vector3(12.7, 0.0, -12.2), 3.6, 6.5)
	_lamp(holder, Vector3(17.0, 0.0, -12.3), 3.4, 6.0)
	var door := OmniLight3D.new()
	door.name = "ForgeDoorLantern"
	door.position = Vector3(8.6, 2.2, -12.0)
	door.light_color = Color("ffc17b")
	door.light_energy = 2.6
	door.omni_range = 7.0
	door.omni_attenuation = 1.5
	door.light_size = 0.22
	door.light_volumetric_fog_energy = 0.4
	holder.add_child(door)
	# 车间顶灯：宽车间门口一盏高位的暖光，压住整排立面的下缘。
	var shop := OmniLight3D.new()
	shop.name = "ForgeShopLantern"
	shop.position = Vector3(15.5, 3.2, -12.4)
	shop.light_color = Color("ffc98a")
	shop.light_energy = 2.8
	shop.omni_range = 8.0
	shop.omni_attenuation = 1.5
	shop.light_size = 0.25
	shop.light_volumetric_fog_energy = 0.4
	holder.add_child(shop)


## 门灯：石灯上方一盏暖色点光（与商店区、码头岸灯同一套做法）。
static func _lamp(parent: Node3D, at: Vector3, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.name = "ForgeLantern"
	light.position = at + Vector3(0, 1.62, 0)
	light.light_color = Color("ffc17b")
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.light_size = 0.2
	light.light_volumetric_fog_energy = 0.4
	parent.add_child(light)
