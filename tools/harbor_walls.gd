extends RefCounted
## 灰潮港城墙：沿陆地基座外缘砌一圈砖石城墙，北面在城门处断开、南面在两座码头贴岸段断开。
## 被 tools/build_harbor.gd（整体重建）与 tools/apply_harbor_walls.gd（增量应用）共用，改布局只改这里。
##
## 为什么不是素材墙段连续排列：共享库里的 SM_JN_*Weiqiang* 每段自带一圈四面瓦檐，本质是
## 独立的墙墩，首尾相接只会排成一排"牌位"；把它们嵌进几何墙里又只剩顶上一片孤零零的瓦檐，
## 反而更怪。所以整圈墙统一由四层几何砌筑——石砌勒脚 / 砖砌墙身 / 挑出瓦檐 / 收进瓦脊，
## 质感靠 shaders/harbor_wall.gdshader 的三平面砖缝，竖向节奏靠石砌壁柱。
##
## 墙线：内表面与地基边缘齐平，墙心线比地基边缘内收半个墙厚。
## 城墙不生成碰撞：边界碰撞仍由 build_actors() 的隐形屏障负责，城墙只把边界做成看得见的东西。

const WallShader := preload("res://shaders/harbor_wall.gdshader")

const NODE_NAME := "HarborWall"
const FOUNDATION_X := 42.0
## 地基北沿 / 南沿（南沿即水岸线 SHORE_Z）。
const FOUNDATION_NORTH := -32.0
const FOUNDATION_SOUTH := 12.0
const WALL_HALF_THICKNESS := 0.5
## 北墙城门开口半宽：城门 SM_xgg_chengmen001 宽 8.19 米，两侧各留约 0.3 米余量贴齐。
const GATE_HALF_WIDTH := 4.4
## 两座码头贴岸段的 x 区间（build_harbor.gd 的 PIER_CENTERS 与 PIER_SPAN），南墙在此断开。
const PIER_OPENINGS := [Vector2(-8.145, 8.145), Vector2(13.855, 30.145)]

## 石砌壁柱：间距 9.4 米，凸出墙身两侧各约 0.3 米，顶端比墙脊高 0.34 米。
const PILASTER_STEP := 9.4
const PILASTER_WIDTH := 1.10
const PILASTER_DEPTH := 1.70
const PILASTER_TOP := 6.10
const PILASTER_CAP_HEIGHT := 0.34

## 剖面：从下到上四层，宽度比墙身逐层外放或收进，形成勒脚与檐口的层次。
## bottom 为该层底面高度，height 层高，width 为墙厚（沿墙法线方向）。
const INLAND_LAYERS := [
	{"kind": "base", "bottom": 0.00, "height": 0.80, "width": 1.74},
	{"kind": "body", "bottom": 0.80, "height": 4.30, "width": 1.12},
	{"kind": "eave", "bottom": 5.10, "height": 0.36, "width": 1.80},
	{"kind": "ridge", "bottom": 5.46, "height": 0.30, "width": 0.98},
]
## 临水岸墙：同构但收矮，6 米墙立在 16° 俯角的取景里会挡掉海面与码头远景。
const SHORE_LAYERS := [
	{"kind": "base", "bottom": 0.00, "height": 0.56, "width": 1.62},
	{"kind": "body", "bottom": 0.56, "height": 2.54, "width": 1.06},
	{"kind": "eave", "bottom": 3.10, "height": 0.30, "width": 1.70},
	{"kind": "ridge", "bottom": 3.40, "height": 0.24, "width": 0.92},
]
## 角墩：方柱加一圈挑檐，比墙脊略高，把两面墙的接缝收在里面。
const CORNER_BODY_TOP := 5.46
const CORNER_SHORE_TOP := 3.40
const CORNER_CAP_HEIGHT := 0.55
const CORNER_SHORE_CAP_HEIGHT := 0.45

static func make_node() -> Node3D:
	var holder := Node3D.new()
	holder.name = NODE_NAME
	var mats := _materials()
	var north := FOUNDATION_NORTH + WALL_HALF_THICKNESS
	var south := FOUNDATION_SOUTH - WALL_HALF_THICKNESS
	var west := -FOUNDATION_X + WALL_HALF_THICKNESS
	var east := FOUNDATION_X - WALL_HALF_THICKNESS
	# 内陆三面：城门两侧各一段、东西各一段。
	var runs := [
		[Vector2(-FOUNDATION_X, north), Vector2(-GATE_HALF_WIDTH, north), "NorthWest"],
		[Vector2(GATE_HALF_WIDTH, north), Vector2(FOUNDATION_X, north), "NorthEast"],
		[Vector2(west, FOUNDATION_NORTH), Vector2(west, south), "West"],
		[Vector2(east, FOUNDATION_NORTH), Vector2(east, south), "East"],
	]
	for run in runs:
		_run(holder, run[0], run[1], INLAND_LAYERS, mats, run[2])
		_pilasters(holder, run[0], run[1], mats)
	# 南面不砌墙：临水一面交给石砌驳岸与码头（tools/harbor_pier.gd）。
	# 角墩：内陆两只用高墩，临水两只配矮墙。
	_corner(holder, Vector2(west, north), mats, CORNER_BODY_TOP, CORNER_CAP_HEIGHT)
	_corner(holder, Vector2(east, north), mats, CORNER_BODY_TOP, CORNER_CAP_HEIGHT)
	_corner(holder, Vector2(west, south), mats, CORNER_BODY_TOP, CORNER_CAP_HEIGHT)
	_corner(holder, Vector2(east, south), mats, CORNER_BODY_TOP, CORNER_CAP_HEIGHT)
	# 驳岸与两座码头
	preload("res://tools/harbor_pier.gd").build(holder, mats)
	# 城门：与城墙同一断面砌筑，坐在北墙中央的开口上
	preload("res://tools/harbor_gate.gd").build(holder, mats, north)
	return holder

## 南墙可铺区间：整条南沿减去两座码头的贴岸段。
static func _south_spans() -> Array[Vector2]:
	var spans: Array[Vector2] = []
	var cursor := -FOUNDATION_X
	for opening in PIER_OPENINGS:
		spans.append(Vector2(cursor, float(opening.x)))
		cursor = float(opening.y)
	spans.append(Vector2(cursor, FOUNDATION_X))
	return spans

## 沿 from→to 砌一段墙：按剖面逐层生成轴对齐长方体，再整体绕 Y 转到墙的走向上。
static func _run(parent: Node3D, from: Vector2, to: Vector2, layers: Array, mats: Dictionary, tag: String) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.5:
		return
	var yaw := atan2(-delta.y, delta.x)
	var center := (from + to) * 0.5
	for layer in layers:
		var part := MeshInstance3D.new()
		part.name = "%s_%s" % [tag, layer.kind]
		var box := BoxMesh.new()
		box.size = Vector3(length, float(layer.height), float(layer.width))
		part.mesh = box
		part.material_override = mats[layer.kind]
		part.position = Vector3(center.x, float(layer.bottom) + float(layer.height) * 0.5, center.y)
		part.rotation.y = yaw
		parent.add_child(part)

## 壁柱：石砌方柱贴墙而立，比墙身厚、比墙脊高，给整圈墙一个竖向节奏；
## 两端不贴角墩与城门，避免挤在一起。
static func _pilasters(parent: Node3D, from: Vector2, to: Vector2, mats: Dictionary) -> void:
	var delta := to - from
	var length := delta.length()
	var count := int(floor(length / PILASTER_STEP))
	if count < 1:
		return
	var yaw := atan2(-delta.y, delta.x)
	for i in count:
		var at := from + delta * ((i + 1.0) / (count + 1.0))
		var shaft := MeshInstance3D.new()
		shaft.name = "WallPier"
		var shaft_box := BoxMesh.new()
		shaft_box.size = Vector3(PILASTER_WIDTH, PILASTER_TOP, PILASTER_DEPTH)
		shaft.mesh = shaft_box
		shaft.material_override = mats["base"]
		shaft.position = Vector3(at.x, PILASTER_TOP * 0.5, at.y)
		shaft.rotation.y = yaw
		parent.add_child(shaft)
		var cap := MeshInstance3D.new()
		cap.name = "WallPierCap"
		var cap_box := BoxMesh.new()
		cap_box.size = Vector3(PILASTER_WIDTH + 0.34, PILASTER_CAP_HEIGHT, PILASTER_DEPTH + 0.36)
		cap.mesh = cap_box
		cap.material_override = mats["eave"]
		cap.position = Vector3(at.x, PILASTER_TOP + PILASTER_CAP_HEIGHT * 0.5, at.y)
		cap.rotation.y = yaw
		parent.add_child(cap)

## 角墩：方柱 + 挑檐，把两面墙的接缝收在里面。
static func _corner(parent: Node3D, at: Vector2, mats: Dictionary, body_top: float, cap_height: float) -> void:
	var body := MeshInstance3D.new()
	body.name = "CornerPier"
	var body_box := BoxMesh.new()
	body_box.size = Vector3(2.0, body_top, 2.0)
	body.mesh = body_box
	body.material_override = mats["base"]
	body.position = Vector3(at.x, body_top * 0.5, at.y)
	parent.add_child(body)
	var cap := MeshInstance3D.new()
	cap.name = "CornerCap"
	var cap_box := BoxMesh.new()
	cap_box.size = Vector3(2.6, cap_height, 2.6)
	cap.mesh = cap_box
	cap.material_override = mats["eave"]
	cap.position = Vector3(at.x, body_top + cap_height * 0.5, at.y)
	parent.add_child(cap)

static func _materials() -> Dictionary:
	# 勒脚：大块毛石，脏一点。
	var base := ShaderMaterial.new()
	base.shader = WallShader
	base.set_shader_parameter("brick_color", Color("6d7166"))
	base.set_shader_parameter("brick_size", Vector2(0.74, 0.40))
	base.set_shader_parameter("mortar", 0.08)
	base.set_shader_parameter("wear", 0.16)
	# 墙身：细砖，冷调米白；偏冷是为了在黄昏暖光下不过度泛粉。
	var body := ShaderMaterial.new()
	body.shader = WallShader
	body.set_shader_parameter("brick_color", Color("c8c6b8"))
	body.set_shader_parameter("brick_size", Vector2(0.46, 0.22))
	body.set_shader_parameter("mortar", 0.12)
	body.set_shader_parameter("wear", 0.10)
	# 瓦檐与瓦脊：同一套格子逻辑当瓦片用，格子接近方形，俯角下是一片青瓦。
	var eave := ShaderMaterial.new()
	eave.shader = WallShader
	eave.set_shader_parameter("brick_color", Color("39424a"))
	eave.set_shader_parameter("brick_size", Vector2(0.19, 0.27))
	eave.set_shader_parameter("mortar", 0.14)
	eave.set_shader_parameter("wear", 0.22)
	var ridge := ShaderMaterial.new()
	ridge.shader = WallShader
	ridge.set_shader_parameter("brick_color", Color("272d33"))
	ridge.set_shader_parameter("brick_size", Vector2(0.22, 0.30))
	ridge.set_shader_parameter("mortar", 0.14)
	ridge.set_shader_parameter("wear", 0.20)
	return {"base": base, "body": body, "eave": eave, "ridge": ridge}
