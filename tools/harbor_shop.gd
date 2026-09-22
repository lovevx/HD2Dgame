extends RefCounted
## 灰潮港左上（西北角）商街「轮回商店」：
## 把原来孤零零一间店面扩成一条小商街——北排三家铺面 + 西侧两家沿墙铺子，
## 街心成排货摊与竹棚、门楣悬匾与旗帜、晾绳挂药材、石狮门帘、灯笼与灯串。
##
## 素材：只用已入库的 assets/hd2d_presets 共享预设，不新增美术。
## 坐标基准：地面 y=0；陆地基座 x∈[-42,42]、z∈[-32,12]；城墙内表面 x=±41.5、z=-31.5。
## 模型原点即脚底中心，实测 AABB：
##   SM_JN_fangzi006 6.00×8.10×6.35（两层店面，轮回商店）
##   SM_JN_fangzi005 6.00×5.28×6.33 / SM_JN_fangzi007 6.00×5.28×6.33 / SM_JN_fangzi002 9.00×5.30×6.33
##   SM_JN_Gongmen001 6.00×3.91×1.57（牌楼）/ SM_Wuxianjiao_qizi003 3.88×6.20×0.63（旗帜）
##   SM_Item_NJtanwei001 2.15×0.81×1.15（货摊）/ SM_NJ_ZhuPengzi001 3.33×2.74×2.71（竹棚）
##   SM_gsc_shengzi001 6.00×0.10×0（晾绳，扁平）/ SM_Item_NJcaoyao009/010 为 0 厚度贴片（药材束）
##
## 碰撞：铺面、货摊、竹棚、旗帜、石狮、木箱、货架沿用预设自带碰撞（COLLIDE_PRESET）；
##   晾绳、药材、门帘、牌楼是纯装饰（牌楼必须 COLLIDE_OFF，否则会把整条街堵死），
##   集市红毯/蓝布地贴是 0 高度贴片，同样必须 COLLIDE_OFF。
##
## 布置约束（别踩）：
##   · 服务点走廊 z∈[-18.4,-17.6]、x∈[-24,0] 必须净空（check_harbor_hub 的直线可达断言走这条线）。
##   · 城门通道 x∈[-4.4,4.4] 通往 z=-31.5 的北门，不能有东西伸进来。
##   · 传送门是"走进即传"：DeparturePortal 在 (0,0,-21)，半径约 2 米内不要摆东西。

const PortLayout := preload("res://tools/harbor_port_layout.gd")

const NODE_NAME := "ShopDistrict"

## 服务点（交互圈圆心）：店面正前方约 2.3 米。
const SERVICE_AT := Vector3(-24.0, 0.0, -18.0)
## 旧服务点位置（apply 脚本据此把 ShopService / 分区标记从主街西段搬过来）。
const SERVICE_LEGACY_AT := Vector3(-10.0, 0.0, -9.0)

## 街面：铺面门脸（南侧立面）在 z≈-20.4~-21.8，主街心 z≈-18，街南侧陈设 z≈-16。
## ※ 南侧坐具排必须留出余量：这几件预设的碰撞盒比网格外扩得比看上去大
##   （木凳碰撞实测已探到 z≈-17.6），压到 -16.7 一带就会啃进 z∈[-18.4,-17.6] 的直达走廊。
const STREET_LANE := Vector2(-18.4, -17.6)   # 直达走廊（净空带）
const STALL_LINE := -19.9                     # 货摊/货架贴铺面那一排
const SOUTH_LINE := -15.9                     # 街南侧的坐具与散货（离走廊 ≥1.2 米）


static func make_node() -> Node3D:
	var holder := Node3D.new()
	holder.name = NODE_NAME
	_shop_row(holder)
	_shop_frontage(holder)
	_west_yard(holder)
	_market(holder)
	_banners(holder)
	_lights(holder)
	return holder


## 北排铺面（立面朝南，正对街心）：成衣铺 + 轮回商店 + 茶馆 + 杂货铺。
## 东端止于 x≈-5，给城门通道（x∈[-4.4,4.4]）与传送门 (0,-21) 让路。
##
## ※ 摆法约束（实测）：这批民居预设**只有南立面有门窗**，横转 90° 只会露出一面空白山墙
##   （早先在 x=-34 立了两家朝东的铺子，从街上看到的就是两堵白墙）。要"多建筑"就往北排加长，
##   别指望侧转能变出店面来。
static func _shop_row(holder: Node3D) -> void:
	# 成衣铺：两层小楼，压在北排西端收口。
	PortLayout.prop(holder, "SM_JN_fangzi001", Vector3(-32.2, 0.0, -23.6), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 轮回商店：两层小楼，自带格子窗与二层立面（主店）。
	PortLayout.prop(holder, "SM_JN_fangzi006", Vector3(-24.0, 0.0, -23.5), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 茶馆：单层长铺，门窗齐全。
	PortLayout.prop(holder, "SM_JN_fangzi005", Vector3(-16.6, 0.0, -24.2), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 杂货铺：更宽的临街铺面，把北排收成一整排。
	PortLayout.prop(holder, "SM_JN_fangzi002", Vector3(-9.5, 0.0, -25.0), 0.0, 1.0, PortLayout.COLLIDE_PRESET)


## 轮回商店门面：匾额、货架、石灯、木牌、货箱（原有）+ 石狮、门帘、二层阳台。
static func _shop_frontage(holder: Node3D) -> void:
	# 匾额：楼正面 z=-20.34，匾厚 0.19，嵌进墙面半指深；y=5.55 正好压在二层窗上沿。
	PortLayout.prop(holder, "SM_gsc_gusuchengpaizi001", Vector3(-24.0, 5.55, -20.28), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	# 门帘：挂在门洞上（薄片，纯装饰）。
	PortLayout.prop(holder, "SM_Item_lianzi001", Vector3(-24.0, 2.35, -20.5), 0.0, 1.15, PortLayout.COLLIDE_OFF)
	# 石狮一对：蹲在门两侧，货架之间的空档里。
	PortLayout.prop(holder, "SM_Item_shishizi001", Vector3(-24.9, 0.0, -20.3), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_shishizi001", Vector3(-23.3, 0.0, -20.3), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 货架两座：分立门口两侧、贴着门脸斜放，摆出"店门口摆货"的样子。
	PortLayout.prop(holder, "SM_Item_NJhuojia001", Vector3(-26.4, 0.0, STALL_LINE), 18.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_NJhuojia002", Vector3(-21.6, 0.0, STALL_LINE), -14.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 石灯分立大门两侧、贴着门脸（服务圈与直达走廊之外）。
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(-25.5, 0.0, -19.4), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(-22.5, 0.0, -19.4), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	# 二层阳台：压在二层窗下沿，立面多一层挑出，街上看更像"楼上有客"。
	PortLayout.prop(holder, "SM_JN_yangtai001", Vector3(-24.0, 3.05, -20.9), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	# 木牌：立在进店小路东侧，朝主街方向。
	PortLayout.prop(holder, "SM_NJ_ZhuPai002", Vector3(-28.0, 0.0, -16.4), 18.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 货箱堆：靠楼东山墙成组堆放（楼东沿 x=-21）。
	for entry in [
			[Vector3(-20.4, 0.0, -21.8), 14.0, 1.3],
			[Vector3(-19.7, 0.0, -22.7), -10.0, 1.15],
			[Vector3(-20.7, 0.0, -23.1), 30.0, 1.2]]:
		PortLayout.prop(holder, "SM_Box001Close", entry[0], float(entry[1]), float(entry[2]), PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Box001Open", Vector3(-20.0, 0.0, -22.2), -18.0, 1.25, PortLayout.COLLIDE_PRESET)


## 街西的货栈后院：铺面西端背后的货堆与棚子，把北排西端收口处填满。
## （西侧不再立朝东的铺子——那只会露出空白山墙，见 _shop_row 的注。）
static func _west_yard(holder: Node3D) -> void:
	PortLayout.prop(holder, "SM_NJ_ZhuPengzi001", Vector3(-31.0, 0.0, -13.0), 0.0, 1.05, PortLayout.COLLIDE_PRESET)
	for entry in [
			[Vector3(-29.6, 0.0, -14.6), 18.0, 1.3],
			[Vector3(-30.4, 0.0, -11.4), -8.0, 1.15],
			[Vector3(-28.6, 0.0, -11.6), 32.0, 1.2]]:
		PortLayout.prop(holder, "SM_Box001Close", entry[0], float(entry[1]), float(entry[2]), PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Box001Open", Vector3(-30.9, 0.0, -12.2), -24.0, 1.25, PortLayout.COLLIDE_PRESET)
	# 酒旗：挂在成衣铺临街一侧，给西端一个竖向的路标。
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(-33.4, 0.0, -20.7), 8.0, 0.85, PortLayout.COLLIDE_PRESET)
	# 铺前石凳与酒坛。
	PortLayout.prop(holder, "SM_mjsz_shidengzi001", Vector3(-30.4, 0.0, -19.6), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_muxiang002", Vector3(-30.6, 0.0, -17.2), 24.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_muxiang002", Vector3(-29.4, 0.0, -16.4), -12.0, 0.9, PortLayout.COLLIDE_PRESET)


## 街心集市：货摊成排、竹棚遮阳、晾绳挂药材、散货与坐具、地贴。
static func _market(holder: Node3D) -> void:
	# 地贴（0 高度贴片，必须显式关碰撞）：集市红毯 + 蓝布，把街心铺成"摆摊的地面"。
	PortLayout.prop(holder, "SM_gsc_tanzi001", Vector3(-19.2, 0.005, -17.2), 6.0, 1.0, PortLayout.COLLIDE_OFF)
	PortLayout.prop(holder, "SM_xgg_tanzi003", Vector3(-16.0, 0.005, -20.4), 52.0, 1.0, PortLayout.COLLIDE_OFF)
	# 货摊：茶馆门前一排四座，摊面朝向街心（z 压在 -19.9，落在走廊之外）。
	PortLayout.prop(holder, "SM_Item_NJtanwei001", Vector3(-19.0, 0.0, STALL_LINE), -6.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_NJtanwei002", Vector3(-17.7, 0.0, STALL_LINE), 12.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_NJtanwei001", Vector3(-16.3, 0.0, STALL_LINE + 0.2), -18.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_NJtanwei002", Vector3(-15.0, 0.0, STALL_LINE), 28.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 摊上：木箱与草药筐，摊子才不像空桌子。
	PortLayout.prop(holder, "SM_Item_muxiang002", Vector3(-18.6, 0.0, STALL_LINE - 0.1), 20.0, 0.75, PortLayout.COLLIDE_OFF)
	PortLayout.prop(holder, "SM_Item_NJcaoyao010", Vector3(-15.2, 1.05, STALL_LINE), 0.0, 1.1, PortLayout.COLLIDE_OFF)
	# 竹棚：罩在货摊排西半幅上（z 到 -18.5，不碰走廊）。
	PortLayout.prop(holder, "SM_NJ_ZhuPengzi001", Vector3(-17.6, 0.0, -19.9), 0.0, 1.05, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ZhuPengzi001", Vector3(-26.9, 0.0, -19.6), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 晾绳 + 挂药材：横跨街心（y=3.1），绳子与药材都是薄片/贴片，纯装饰。
	PortLayout.prop(holder, "SM_gsc_shengzi001", Vector3(-21.8, 3.10, -19.6), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	for hang in [[-23.6, 2.62, 1.0], [-21.7, 2.72, 1.15], [-19.9, 2.58, 1.0]]:
		PortLayout.prop(holder, "SM_Item_NJcaoyao009",
			Vector3(float(hang[0]), float(hang[1]), -19.6), 0.0, float(hang[2]), PortLayout.COLLIDE_OFF)
	# 街南侧：石凳一排 + 石桌，给"逛街的人"准备的坐具。
	PortLayout.prop(holder, "SM_mjsz_shizhuozi001", Vector3(-19.0, 0.0, SOUTH_LINE - 0.4), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_mjsz_Mudunzi001", Vector3(-17.6, 0.0, SOUTH_LINE - 0.2), -20.0, 1.0, PortLayout.COLLIDE_PRESET)
	for x in [-22.4, -21.2, -23.6]:
		PortLayout.prop(holder, "SM_mjsz_shidengzi001", Vector3(x, 0.0, SOUTH_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 杂货铺门前：货架成对 + 晾晒的木箱（屏风那种深色立板在街上读成一块黑板，已撤）。
	PortLayout.prop(holder, "SM_Item_NJhuojia003", Vector3(-9.4, 0.0, STALL_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Item_NJhuojia003", Vector3(-8.2, 0.0, STALL_LINE), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Box001Close", Vector3(-7.2, 0.0, STALL_LINE - 0.6), 12.0, 1.25, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Box001Open", Vector3(-6.6, 0.0, STALL_LINE + 0.4), -22.0, 1.2, PortLayout.COLLIDE_PRESET)


## 招幌与牌楼。
## 牌楼必须**面朝南**（yaw 0）：这样默认机位（正南看北）看到的是它完整的立面轮廓；
## 侧转 90° 虽然也能穿，但在镜头里只剩一根立板（踩过）。
## 位置放在集市西口（x=-29.4，开阔地），当西巷门用：低俯角机位下门楼一定会压住它身后的立面，
## 摆在广场正中就会把轮回商店的石狮、门帘挡掉；摆到西口只叠到成衣铺一角，不影响主店取景。
## 玩家从主街往北进场仍可穿门而过。COLLIDE_OFF，不挡路。
static func _banners(holder: Node3D) -> void:
	PortLayout.prop(holder, "SM_JN_Gongmen001", Vector3(-29.4, 0.0, -14.3), 0.0, 1.05, PortLayout.COLLIDE_OFF)
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(-27.6, 0.0, -20.6), 8.0, 0.9, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(-13.4, 0.0, -21.0), -14.0, 0.85, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(-20.2, 0.0, -21.2), 4.0, 0.8, PortLayout.COLLIDE_PRESET)
	# 水缸沿街摆两只，集市里常见的那种；竹桌椅摆在茶馆东侧的茶座角。
	PortLayout.prop(holder, "SM_gsc_gu002", Vector3(-26.6, 0.0, -16.2), 12.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_gsc_gu001", Vector3(-25.5, 0.0, -15.6), -20.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ZhuZhuozi001", Vector3(-13.6, 0.0, -19.3), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ZhuYizi001", Vector3(-12.7, 0.0, -19.3), -70.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ZhuYizi001", Vector3(-14.5, 0.0, -19.3), 70.0, 1.0, PortLayout.COLLIDE_PRESET)


## 灯光：青色灯带打在招牌与门脸（概念图的冷色发光店面），沿街铺暖色灯串。
static func _lights(holder: Node3D) -> void:
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(-19.8, 0.0, STALL_LINE - 0.6), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(-14.6, 0.0, STALL_LINE - 0.6), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	_lamp(holder, Vector3(-19.8, 0.0, STALL_LINE - 0.6), 3.6, 6.5)
	_lamp(holder, Vector3(-14.6, 0.0, STALL_LINE - 0.6), 3.6, 6.5)
	_lamp(holder, Vector3(-25.5, 0.0, -19.4), 3.4, 6.0)
	_lamp(holder, Vector3(-22.5, 0.0, -19.4), 3.4, 6.0)
	var teal := OmniLight3D.new()
	teal.name = "ShopSignGlow"
	teal.position = Vector3(-24.0, 5.9, -21.2)
	teal.light_color = Color("6fd8ef")
	teal.light_energy = 2.4
	teal.omni_range = 8.5
	teal.omni_attenuation = 1.4
	teal.light_size = 0.3
	teal.light_volumetric_fog_energy = 0.4
	holder.add_child(teal)
	var doorway := OmniLight3D.new()
	doorway.name = "ShopDoorLantern"
	doorway.position = Vector3(-24.0, 2.1, -19.4)
	doorway.light_color = Color("ffc17b")
	doorway.light_energy = 2.2
	doorway.omni_range = 6.0
	doorway.omni_attenuation = 1.5
	doorway.light_size = 0.2
	doorway.light_volumetric_fog_energy = 0.35
	holder.add_child(doorway)
	var west := OmniLight3D.new()
	west.name = "WestRowLantern"
	west.position = Vector3(-31.0, 2.6, -17.0)
	west.light_color = Color("ffc98a")
	west.light_energy = 3.0
	west.omni_range = 8.0
	west.omni_attenuation = 1.5
	west.light_size = 0.25
	west.light_volumetric_fog_energy = 0.4
	holder.add_child(west)
	var east := OmniLight3D.new()
	east.name = "EastRowLantern"
	east.position = Vector3(-9.5, 2.6, -18.0)
	east.light_color = Color("ffc98a")
	east.light_energy = 3.0
	east.omni_range = 8.0
	east.omni_attenuation = 1.5
	east.light_size = 0.25
	east.light_volumetric_fog_energy = 0.4
	holder.add_child(east)


## 街灯：石灯上方一盏暖色点光（与码头岸灯同一套做法）。
static func _lamp(parent: Node3D, at: Vector3, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.name = "ShopLantern"
	light.position = at + Vector3(0, 1.62, 0)
	light.light_color = Color("ffc17b")
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.light_size = 0.2
	light.light_volumetric_fog_energy = 0.4
	parent.add_child(light)
