extends RefCounted
## 灰潮港南岸客货码头：补完 Pier0 / Pier22 两座 L 形码头的木作外观，
## 把两座之间的水域整成一处内港泊位，并沿岸补齐系泊石作与货运陈设。
##
## 素材：只用已入库的 assets/hd2d_presets 共享预设，不新增美术。
##   · SM_JN_matou        —— L 形木码头。实测甲板顶面在模型原点上方 4.31 米（下沉 4.31 后与石板街齐平）；
##                           模型原点是俯视几何中心而非角点（包围盒 x∈[-8.23,8.06]、z∈[-6.5,6.5]，
##                           主段 z∈[-6.5,0]、西侧支段 z∈[0,6.5]），故世界摆放 = 中轴 x + 0.085 / z = SHORE_Z+PIER_SPAN.y。
##   · SM_JN_yuchuan003   —— 渔船，兼作货船泊在货运码头外档与内港。
##   · SM_JN_yuchuan004   —— 大渔船，锚在内港外海。
##   · SM_JN_xiaochuan005 —— 长条平底船，作渡船靠泊客运码头对侧。
##   · 木作 / 石作 / 货箱 / 灯具见 _deck_passenger()、_deck_cargo()、_basin()、_quay_line()。
##
## 坐标：与 build_harbor.gd 的 PIER_CENTERS / PIER_SPAN / PIER_LEG 对齐。
##   水岸线 SHORE_Z=12.0；陆地与主城在 -z，海在 +z。
##   两座码头中轴 x=0 / 22；主段贴岸 z∈[12,18.5]，西侧支段伸海 z∈[18.5,25]。
##   中间空档＝内港：喉口水域 x∈[8.145,13.855]、z∈[12,18.5]；支段以南展开为港池 x∈[-1.855,13.855]、z∈[18.5,25]。
##
## 碰撞：两座码头的甲板盒体与沿水拦水已由 build_harbor.gd 生成（Pier0Deck / Pier0LegDeck / Pier*Rail*），
## 本模块只补外观与陈设，不新增可行走面，不改动玩家活动范围与水域屏障。
## 甲板模型（SM_JN_matou）必须用 COLLIDE_OFF 摆：可行走碰撞已经由 Pier*Deck 提供，
## 重复叠一层模型自带碰撞会把角色卡在甲板与砖路的接缝处。详见 COLLIDE_* 常量说明。

const Catalog := preload("res://tools/preset_catalog.gd")
const WallShader := preload("res://shaders/harbor_wall.gdshader")

const NODE_NAME := "SouthPort"

const SHORE_Z := 12.0
const WATER_Y := -0.72
const PIER_SPAN := Vector2(16.29, 6.5)
const PIER_LEG := Vector2(6.29, 6.5)
const PIER_CENTERS := [0.0, 22.0]
## 中间内港的喉口 x 区间（＝两座码头之间的空档宽度）。
## 场景里 HarborWall 还留着上一版南岸矮墙，正好砌在这个区间上；apply 脚本据此把它拆开。
const BASIN_MOUTH := Vector2(8.145, 13.855)
## SM_JN_matou 几何原点相对主段西沿的偏移（实测：原点在包围盒中心，不是角点）。
const MATOU_ORIGIN_X := 0.085
const MATOU_DECK_TOP := 4.31
const MATOU_DROP := -MATOU_DECK_TOP

## 石砌勒脚 / 岸沿：与城墙南沿同一套层高剖面。
const PLINTH_BOTTOM := -1.70
const PLINTH_TOP := -0.26
const EDGE_WIDTH := 0.5

const PASSENGER := "passenger"
const CARGO := "cargo"

## prop() 的碰撞口径。注意：这批共享预设多数自带 `static_collision = true`，
## 所以「不传碰撞参数」＝照旧生成碰撞。要关掉必须**显式**覆盖。
##   COLLIDE_OFF    —— 纯装饰，强制关掉碰撞。
##                     ※ 甲板模型（SM_JN_matou）必须用这个：可行走碰撞已由 build_harbor.gd 的
##                     Pier*Deck 提供，再叠一层模型自带碰撞会让角色在甲板／砖路接缝处被卡住
##                     （实测：走过去没事，走回来在 z≈12.7 被 SM_JN_matou_col 挡住）。
##   COLLIDE_PRESET —— 沿用预设自身设置（实体摆件：货箱、货架、竹棚、石灯、系船石…）。
##   COLLIDE_BOX    —— 按包围盒补一个方盒碰撞体。
const COLLIDE_OFF := -1
const COLLIDE_PRESET := 0
const COLLIDE_BOX := 1


# ------------------------------------------------------------------ 装配

## 返回南岸码头整组节点。mats 由场景里的 HarborWall 取（见 apply_harbor_south_port.gd）。
static func make_node(mats: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = NODE_NAME
	_pier(holder, mats, 0.0, "Pier0", PASSENGER)
	_pier(holder, mats, 22.0, "Pier22", CARGO)
	_basin(holder, mats)
	_quay_line(holder, mats)
	return holder


## 一座码头：木甲板（SM_JN_matou）+ 石砌岸沿 + 石砌墩柱 + 客/货运陈设。
static func _pier(holder: Node3D, mats: Dictionary, center_x: float, tag: String, kind: String) -> void:
	var root := Node3D.new()
	root.name = tag
	holder.add_child(root)

	var half := PIER_SPAN.x * 0.5
	var west := center_x - half
	var east := center_x + half
	var mid := SHORE_Z + PIER_SPAN.y
	var sea_end := mid + PIER_LEG.y
	var leg_east := west + PIER_LEG.x

	# 木码头主体：原点在几何中心，故西沿对齐 west 时要右移 0.085。
	# 必须 COLLIDE_OFF：可行走碰撞已由 build_harbor.gd 的 Pier*Deck 提供，
	# 叠上模型自带碰撞会让角色在甲板／砖路接缝处被卡住。
	prop(root, "SM_JN_matou", Vector3(center_x + MATOU_ORIGIN_X, MATOU_DROP, mid), 0.0, 1.0, COLLIDE_OFF)

	# 石砌岸沿：沿 L 形轮廓收边，免得木面像一块浮板。
	_shore_edge(root, mats, Vector3(west - EDGE_WIDTH * 0.5, 0.0, (SHORE_Z + sea_end) * 0.5), Vector2(EDGE_WIDTH, sea_end - SHORE_Z))
	_shore_edge(root, mats, Vector3(east + EDGE_WIDTH * 0.5, 0.0, (SHORE_Z + mid) * 0.5), Vector2(EDGE_WIDTH, PIER_SPAN.y))
	_shore_edge(root, mats, Vector3((leg_east + east) * 0.5, 0.0, mid), Vector2(east - leg_east, EDGE_WIDTH))
	_shore_edge(root, mats, Vector3(leg_east + EDGE_WIDTH * 0.5, 0.0, (mid + sea_end) * 0.5), Vector2(EDGE_WIDTH, PIER_LEG.y))
	_shore_edge(root, mats, Vector3((west + leg_east) * 0.5, 0.0, sea_end + EDGE_WIDTH * 0.5), Vector2(PIER_LEG.x, EDGE_WIDTH))

	# 石砌墩柱：支段端头两根 + 主段东南角一根，把木板托在水面上。
	for at in [Vector3(west + 0.8, 0.0, sea_end - 1.6), Vector3(leg_east - 0.8, 0.0, sea_end - 1.6),
			Vector3(east - 0.9, 0.0, mid - 1.4)]:
		_slab(root, "PierPile", Vector3(at.x, PLINTH_BOTTOM + (PLINTH_TOP - PLINTH_BOTTOM) * 0.5, at.z),
			Vector3(0.62, PLINTH_TOP - PLINTH_BOTTOM, 0.62), mats["base"])

	# 系船柱：沿临水三面等距布置。
	for at in [Vector3(east - 0.55, 0.0, SHORE_Z + 1.6), Vector3(east - 0.55, 0.0, SHORE_Z + 4.2), Vector3(east - 0.55, 0.0, SHORE_Z + 6.4),
			Vector3(leg_east - 0.55, 0.0, mid + 1.8), Vector3(leg_east - 0.55, 0.0, sea_end - 1.8)]:
		prop(root, "SM_Licheng_shizhuzi001", at, 0.0, 1.15, COLLIDE_PRESET)

	if kind == PASSENGER:
		_deck_passenger(root, west, east, mid)
	else:
		_deck_cargo(root, west, east, mid)

	# 码头灯：石灯笼 + 暖色点光，与港口岸灯同一套做法。
	# z 取 mid-2.0 而不是 mid-0.8：灯笼碰撞体约 0.72 宽、伸到 z+0.36，
	# 靠接缝太近会跟着装卸棚一起把支段出口挤没（见 _deck_cargo 的注释）。
	_lantern(root, Vector3((west + leg_east) * 0.5, 0.0, sea_end - 1.2))
	_lantern(root, Vector3(west + 4.6, 0.0, mid - 2.0))


## 客运码头（Pier0）：小巧的候船竹棚、候船长凳、行李堆。
## 竹棚特意用小尺寸的 SM_NJ_ZhuPengzi001，与货运码头的大装卸棚区分开。
static func _deck_passenger(root: Node3D, west: float, east: float, mid: float) -> void:
	# 候船棚压在主段西端，东侧留出 8 米宽的上落客通道。
	prop(root, "SM_NJ_ZhuPengzi001", Vector3(west + 2.4, 0.0, SHORE_Z + 3.4), 0.0, 1.0, COLLIDE_PRESET)
	# 候船长凳与行李。z 不超过 SHORE_Z+5.0：长凳碰撞体约 1.2 深，再往南就会顶到
	# 支段出口（接缝 z=18.5），把「从支段走回主段」的路封掉。
	prop(root, "SM_mjsz_Mudunzi001", Vector3(west + 1.6, 0.0, SHORE_Z + 5.0), 0.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_mjsz_Mudunzi001", Vector3(west + 3.4, 0.0, SHORE_Z + 5.0), 0.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_mjsz_Mudunzi001", Vector3(west + 2.5, 0.0, SHORE_Z + 1.4), 0.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_Box001Close", Vector3(east - 1.8, 0.0, SHORE_Z + 1.5), 12.0, 1.2, COLLIDE_PRESET)
	prop(root, "SM_Box001Open", Vector3(east - 2.9, 0.0, SHORE_Z + 2.4), 24.0, 1.1, COLLIDE_PRESET)
	# 码头木牌：立在贴岸开口东侧，朝主城方向。
	prop(root, "SM_NJ_ZhuPai002", Vector3(west + 6.4, 0.0, SHORE_Z + 0.5), 180.0, 1.0, COLLIDE_PRESET)
	# 渔具：客码头西侧也兼做小船靠泊，挂一面网。
	prop(root, "SM_jiangnan_yuwang001", Vector3(west + 0.9, 0.0, mid - 2.6), 90.0, 1.0, COLLIDE_PRESET)
	# 渡船：靠在内港喉口东侧，与 Pier0 东沿平行。
	prop(root, "SM_JN_xiaochuan005", Vector3(12.3, WATER_Y, 16.2), 90.0, 1.0, COLLIDE_PRESET)


## 货运码头（Pier22）：装卸棚、货箱堆场、货架、垫石。
##
## ※ 布置约束（踩过坑）：支段接缝在 z=mid=18.5，且支段宽度只有 PIER_LEG.x=6.29（x∈[west, west+6.29]），
##   正好落在主段西半幅。所以**西半幅 z 超过 ~17 的地方不能摆东西**：
##   装卸棚碰撞体实测约 4.9 × 5.1（0.78 缩放后），原来放在 z=SHORE_Z+3.5 时伸到 z≈18.0，
##   再叠上石灯笼与木墩，就把整条支段出口横断——能走进支段却走不回主段。
##   现在的取值让 z∈[~17.2, 18.5] 保持净空。
static func _deck_cargo(root: Node3D, west: float, east: float, mid: float) -> void:
	# 装卸棚压在主段西端，东侧留出堆场；z 收紧到 +2.6 给支段出口让路。
	prop(root, "SM_jzc_mapeng001", Vector3(west + 2.7, 0.0, SHORE_Z + 2.6), 0.0, 0.78, COLLIDE_PRESET)
	# 货架贴棚东侧立两座。
	prop(root, "SM_Item_NJhuojia003", Vector3(west + 5.6, 0.0, SHORE_Z + 1.0), 90.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_Item_NJhuojia003", Vector3(west + 5.6, 0.0, SHORE_Z + 2.4), 90.0, 1.0, COLLIDE_PRESET)
	# 货箱堆场：东半幅成组堆放，中间留 3 米通行带。
	for entry in [
			[Vector3(east - 2.0, 0.0, SHORE_Z + 1.6), 14.0, 1.5],
			[Vector3(east - 3.3, 0.0, SHORE_Z + 2.5), -8.0, 1.3],
			[Vector3(east - 1.5, 0.0, SHORE_Z + 3.9), 30.0, 1.4],
			[Vector3(east - 2.8, 0.0, SHORE_Z + 5.2), 4.0, 1.2],
			[Vector3(east - 4.4, 0.0, SHORE_Z + 4.4), -22.0, 1.35]]:
		prop(root, "SM_Box001Close", entry[0], float(entry[1]), float(entry[2]), COLLIDE_PRESET)
	prop(root, "SM_Box001Open", Vector3(east - 2.2, 0.0, SHORE_Z + 3.0), 18.0, 1.5, COLLIDE_PRESET)
	prop(root, "SM_Box001Open", Vector3(east - 4.0, 0.0, SHORE_Z + 2.0), -12.0, 1.2, COLLIDE_PRESET)
	# 石砌垫石与踏步：堆场边缘收纳散货。
	prop(root, "SM_NJ_Shitoudui001", Vector3(east - 6.0, 0.0, SHORE_Z + 5.4), 20.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_mjsz_Mudunzi001", Vector3(west + 5.8, 0.0, SHORE_Z + 3.2), 0.0, 1.0, COLLIDE_PRESET)
	# 码头木牌：朝主城方向，标明货码头。
	prop(root, "SM_NJ_ZhuPai002", Vector3(west + 6.4, 0.0, SHORE_Z + 0.5), 180.0, 1.0, COLLIDE_PRESET)
	# 货船：一艘靠东外档，一艘大船锚在内港外海。
	prop(root, "SM_JN_yuchuan003", Vector3(34.6, WATER_Y, 16.6), 90.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_JN_yuchuan004", Vector3(33.0, -0.9, 31.0), 96.0, 1.0, COLLIDE_PRESET)


# ------------------------------------------------------------------ 中间内港

## 两座码头之间的内港：喉口砌踏步下水，两岸布系船石墩，港池里泊一条渔船。
static func _basin(holder: Node3D, mats: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "InnerBasin"
	holder.add_child(root)
	var throat_mid := (BASIN_MOUTH.x + BASIN_MOUTH.y) * 0.5
	# 石砌踏步：从岸线逐级下到水面。
	for i in 3:
		_slab(root, "BasinStep", Vector3(throat_mid, -0.34 - i * 0.62, SHORE_Z + 0.35 + i * 1.0),
			Vector3(2.6, 0.66, 1.02), mats["base"])
	# 系船石墩：喉口两岸各一处。
	for at in [Vector3(9.0, 0.0, SHORE_Z - 0.6), Vector3(13.0, 0.0, SHORE_Z - 0.6)]:
		prop(root, "SM_Nanjiang_YYPshidun002", at, 0.0, 1.0, COLLIDE_PRESET)
	# 内港木牌与码头灯：立在喉口正对的主街上，把这片水域指认为泊位。
	prop(root, "SM_NJ_ZhuPai002", Vector3(throat_mid, 0.0, SHORE_Z - 1.8), 0.0, 1.05, COLLIDE_PRESET)
	_lantern(root, Vector3(throat_mid - 2.2, 0.0, SHORE_Z - 1.4))
	_lantern(root, Vector3(throat_mid + 2.2, 0.0, SHORE_Z - 1.4))
	# 港池泊船：支段以南的展开水域正好容一条渔船横泊。
	prop(root, "SM_JN_yuchuan003", Vector3(4.8, WATER_Y, 21.9), 4.0, 1.0, COLLIDE_PRESET)


# ------------------------------------------------------------------ 南岸沿线

## 南岸陆侧沿水一线：系船石与渔具，把整条岸线读成一处成形的港。
static func _quay_line(holder: Node3D, mats: Dictionary) -> void:
	var root := Node3D.new()
	root.name = "QuayLine"
	holder.add_child(root)
	# 只铺在两座码头开口以外的岸段，避免挡住上桥通道。
	for x in [-24.0, -18.0, -12.0, 34.0, 38.0]:
		prop(root, "SM_Nanjiang_YYPshidun002", Vector3(x, 0.0, SHORE_Z - 0.7), 0.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_jiangnan_yuwang001", Vector3(-20.6, 0.0, SHORE_Z - 1.1), 100.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_jiangnan_yuwang001", Vector3(36.4, 0.0, SHORE_Z - 1.2), -84.0, 1.0, COLLIDE_PRESET)
	prop(root, "SM_Box001Close", Vector3(-15.6, 0.0, SHORE_Z - 1.3), 16.0, 1.3, COLLIDE_PRESET)
	prop(root, "SM_Box001Close", Vector3(-14.2, 0.0, SHORE_Z - 1.9), -10.0, 1.1, COLLIDE_PRESET)
	prop(root, "SM_Box001Open", Vector3(37.8, 0.0, SHORE_Z - 2.0), 26.0, 1.2, COLLIDE_PRESET)


# ------------------------------------------------------------------ 构件

## 石砌驳岸：与城墙南沿用同一层高剖面（勒脚 + 台面），把木甲板收边。
static func _shore_edge(parent: Node3D, mats: Dictionary, at: Vector3, footprint: Vector2) -> void:
	_slab(parent, "PierRevetment", Vector3(at.x, PLINTH_BOTTOM + (PLINTH_TOP - PLINTH_BOTTOM) * 0.5, at.z),
		Vector3(footprint.x, PLINTH_TOP - PLINTH_BOTTOM, footprint.y), mats["base"])
	_slab(parent, "PierCoping", Vector3(at.x, -0.13, at.z), Vector3(footprint.x, 0.26, footprint.y), mats["eave"])


static func _slab(parent: Node3D, label: String, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node


## 石灯笼 + 暖色点光：港口岸灯的同一套做法，节点归入 harbor_dock_light 便于统查。
static func _lantern(parent: Node3D, at: Vector3) -> void:
	prop(parent, "SM_NJ_ShiDeng_001", at, 0.0, 0.85, COLLIDE_PRESET)
	var light := OmniLight3D.new()
	light.name = "PortLantern"
	light.position = at + Vector3(0, 1.62, 0)
	light.light_color = Color("ffc17b")
	light.light_energy = 4.5
	light.omni_range = 7.5
	light.omni_attenuation = 1.5
	light.light_size = 0.2
	light.light_volumetric_fog_energy = 0.45
	light.add_to_group("harbor_dock_light")
	parent.add_child(light)


## 放置一个共享库预设。collide 取 COLLIDE_* 之一，决定碰撞口径。
static func prop(parent: Node3D, title: String, at: Vector3, yaw_deg := 0.0, size_scale := 1.0, collide := COLLIDE_PRESET) -> HD2DProp:
	var asset: HD2DAsset = Catalog.asset(title)
	if asset == null:
		return null
	var node := HD2DProp.new()
	node.name = title
	var overrides := {}
	if collide == COLLIDE_OFF:
		# 必须显式覆盖：预设自带 static_collision=true，只"不传参数"是关不掉的。
		overrides["static_collision"] = false
	elif collide == COLLIDE_BOX:
		var parts := asset.mesh_parts()
		if not parts.is_empty():
			var footprint: Vector3 = (parts[0]["mesh"] as Mesh).get_aabb().size * size_scale
			var yawed := Basis(Vector3.UP, deg_to_rad(yaw_deg))
			var width := absf(yawed.x.x) * footprint.x + absf(yawed.x.z) * footprint.z
			var depth := absf(yawed.z.x) * footprint.x + absf(yawed.z.z) * footprint.z
			overrides = {
				"static_collision": true,
				"collision_mode": 1,
				"collision_size": Vector3(width, footprint.y, depth),
				"collision_offset": Vector3(0, footprint.y * 0.5, 0),
			}
	if not overrides.is_empty():
		node.asset_overrides = overrides
	node.asset = asset
	node.position = at
	node.rotation_degrees = Vector3(0, yaw_deg, 0)
	node.scale = Vector3.ONE * size_scale
	parent.add_child(node)
	return node
