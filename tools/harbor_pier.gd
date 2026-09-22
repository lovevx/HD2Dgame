extends RefCounted
## 灰潮港码头与驳岸：石砌墩台配木铺甲板，与城墙共用石作材质与砖缝 shader。
## 甲板面与石板街齐平（y=0）；碰撞仍由 build_harbor.gd 的 platform 盒体负责，这里只做外观。
## 南侧不再砌墙——临水一面改由石砌驳岸收口，两座码头贴岸段断开供人上船。

const WallShader := preload("res://shaders/harbor_wall.gdshader")

const PIER_SPAN := Vector2(16.29, 6.5)
const PIER_LEG := Vector2(6.3, 6.5)
const PIER_LEG_X := -7.8
const PIER_CENTERS := [0.0, 22.0]
const SHORE_Z := 12.0
const DECK_THICKNESS := 0.5
const EDGE_HEIGHT := 0.8
const EDGE_WIDTH := 0.5
const PILE_SIZE := 0.6
const PILE_BOTTOM := -2.2
## 驳岸向海侧伸出：玩家活动范围到不了它，正好把水陆边界收干净。
const EDGE_Z_CENTER := SHORE_Z + 0.8
const EDGE_Z_WIDTH := 1.6

static func build(parent: Node3D, mats: Dictionary) -> void:
	_shore_edge(parent, mats)
	for center_x in PIER_CENTERS:
		_pier(parent, float(center_x), mats)

## 石砌驳岸：沿水岸线收口，两座码头贴岸段留口。
static func _shore_edge(parent: Node3D, mats: Dictionary) -> void:
	for span in _shore_spans():
		_box(parent, "ShoreEdge", Vector3((span.x + span.y) * 0.5, -0.15, EDGE_Z_CENTER),
			Vector3(span.y - span.x, 0.9, EDGE_Z_WIDTH), mats["base"])

static func _shore_spans() -> Array[Vector2]:
	var spans: Array[Vector2] = []
	var cursor := -42.0
	for center_x in PIER_CENTERS:
		var opening := Vector2(float(center_x) - PIER_SPAN.x * 0.5, float(center_x) + PIER_SPAN.x * 0.5)
		spans.append(Vector2(cursor, opening.x))
		cursor = opening.y
	spans.append(Vector2(cursor, 42.0))
	return spans

static func _pier(parent: Node3D, center_x: float, mats: Dictionary) -> void:
	var pier := Node3D.new()
	pier.name = "HarborPier%d" % int(center_x)
	parent.add_child(pier)
	var half := PIER_SPAN.x * 0.5
	var near := SHORE_Z
	var far := SHORE_Z + PIER_SPAN.y
	var sea_end := far + PIER_LEG.y
	var leg_x0 := center_x + PIER_LEG_X
	var leg_x1 := leg_x0 + PIER_LEG.x
	var wood := _wood()
	# 甲板：主段贴岸、支段伸海
	_box(pier, "PierDeck", Vector3(center_x, -DECK_THICKNESS * 0.5, (near + far) * 0.5),
		Vector3(PIER_SPAN.x, DECK_THICKNESS, PIER_SPAN.y), wood)
	_box(pier, "PierLegDeck", Vector3((leg_x0 + leg_x1) * 0.5, -DECK_THICKNESS * 0.5, (far + sea_end) * 0.5),
		Vector3(PIER_LEG.x, DECK_THICKNESS, PIER_LEG.y), wood)
	# 石砌岸沿：把木面收边，免得甲板像一块浮板
	_edge(pier, mats, Vector3(center_x - half - EDGE_WIDTH * 0.5, (near + far) * 0.5), Vector3(EDGE_WIDTH, PIER_SPAN.y))
	_edge(pier, mats, Vector3(center_x + half + EDGE_WIDTH * 0.5, (near + far) * 0.5), Vector3(EDGE_WIDTH, PIER_SPAN.y))
	_edge(pier, mats, Vector3(center_x, far + EDGE_WIDTH * 0.5), Vector3(PIER_SPAN.x, EDGE_WIDTH))
	_edge(pier, mats, Vector3(leg_x0 - EDGE_WIDTH * 0.5, (far + sea_end) * 0.5), Vector3(EDGE_WIDTH, PIER_LEG.y))
	_edge(pier, mats, Vector3(leg_x1 + EDGE_WIDTH * 0.5, (far + sea_end) * 0.5), Vector3(EDGE_WIDTH, PIER_LEG.y))
	_edge(pier, mats, Vector3((leg_x0 + leg_x1) * 0.5, sea_end + EDGE_WIDTH * 0.5), Vector3(PIER_LEG.x, EDGE_WIDTH))
	# 墩柱：甲板四角往水下伸
	for at in [Vector3(center_x - half + PILE_SIZE, 0.0, far - PILE_SIZE),
			Vector3(center_x + half - PILE_SIZE, 0.0, far - PILE_SIZE),
			Vector3(leg_x0 + PILE_SIZE, 0.0, sea_end - PILE_SIZE),
			Vector3(leg_x1 - PILE_SIZE, 0.0, sea_end - PILE_SIZE)]:
		_pile(pier, mats, at)

## 沿边压条用平面 x/z 表达，size 的第二个分量是沿墙方向的长度。
static func _edge(parent: Node3D, mats: Dictionary, at: Vector3, footprint: Vector2) -> void:
	_box(parent, "PierEdge", Vector3(at.x, -EDGE_HEIGHT * 0.5, at.y),
		Vector3(footprint.x, EDGE_HEIGHT, footprint.y), mats["base"])

static func _pile(parent: Node3D, mats: Dictionary, at: Vector3) -> void:
	var height := -PILE_BOTTOM - DECK_THICKNESS
	_box(parent, "PierPile", Vector3(at.x, PILE_BOTTOM + height * 0.5, at.z),
		Vector3(PILE_SIZE, height, PILE_SIZE), mats["base"])

## 木铺甲板：借用城墙的砖缝 shader，把砖格拉成长板条。
static func _wood() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = WallShader
	mat.set_shader_parameter("brick_color", Color("7a6850"))
	mat.set_shader_parameter("brick_size", Vector2(3.2, 0.26))
	mat.set_shader_parameter("mortar", 0.16)
	mat.set_shader_parameter("wear", 0.20)
	return mat

static func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, mat: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = mat
	node.position = at
	parent.add_child(node)
