extends RefCounted
## 灰潮港城门：与城墙同一套砌筑语言——石砌勒脚、砖砌台身、叠涩券顶、青瓦出檐，
## 由 tools/harbor_walls.gd 在墙线中央调用。城台比城墙更厚更高，门洞贯穿整个进深，
## 玩家从门洞穿行到北面的科尔波山。

## 门洞半宽，与城墙在城门处的开口半宽一致。
const HALF_SPAN := 2.2
## 城台半宽（沿墙方向）。
const PIER_HALF := 6.0
## 城台进深（门洞贯穿）。
const DEPTH := 8.0
## 城台高。比城墙 5.76 米高出一截，形成主次。
const HEIGHT := 8.6
## 门洞直段净高，往上叠涩收口。
const OPENING_HEIGHT := 4.8
const CORBEL_HEIGHT := 0.4
const CORBEL_INSET := 0.55
const LINTEL_HEIGHT := 0.5
const BASE_HEIGHT := 0.9
const EAVE_HEIGHT := 0.42
const EAVE_OUTSET := 0.6
const RIDGE_HEIGHT := 0.34
const RIDGE_INSET := 0.8

static func build(parent: Node3D, mats: Dictionary, center_z: float) -> void:
	var gate := Node3D.new()
	gate.name = "HarborGate"
	gate.position = Vector3(0.0, 0.0, center_z)
	parent.add_child(gate)
	var half_depth := DEPTH * 0.5
	var pier_width := PIER_HALF - HALF_SPAN
	var pier_center := HALF_SPAN + pier_width * 0.5
	var head_bottom := OPENING_HEIGHT + CORBEL_HEIGHT * 2.0 + LINTEL_HEIGHT
	# 两座门墩：石勒脚 + 砖台身，在中间夹出门洞
	for side in [-1.0, 1.0]:
		_box(gate, "GateBase", Vector3(side * pier_center, BASE_HEIGHT * 0.5, 0.0),
			Vector3(pier_width + 0.7, BASE_HEIGHT, DEPTH + 0.7), mats["base"])
		_box(gate, "GatePier", Vector3(side * pier_center, (BASE_HEIGHT + HEIGHT) * 0.5, 0.0),
			Vector3(pier_width, HEIGHT - BASE_HEIGHT, DEPTH), mats["body"])
	# 叠涩券：每层从门洞两侧向内伸进一块，洞口逐级收窄
	for step in 2:
		var inner := HALF_SPAN - float(step) * CORBEL_INSET
		var outer := inner - CORBEL_INSET
		var y := OPENING_HEIGHT + CORBEL_HEIGHT * (float(step) + 0.5)
		for side in [-1.0, 1.0]:
			_box(gate, "GateCorbel", Vector3(side * (inner + outer) * 0.5, y, 0.0),
				Vector3(CORBEL_INSET, CORBEL_HEIGHT, DEPTH), mats["base"])
	# 券顶封口与上部楣墙
	_box(gate, "GateLintel", Vector3(0.0, OPENING_HEIGHT + CORBEL_HEIGHT + LINTEL_HEIGHT * 0.5, 0.0),
		Vector3((HALF_SPAN - CORBEL_INSET * 2.0) * 2.0, LINTEL_HEIGHT, DEPTH), mats["base"])
	_box(gate, "GateHead", Vector3(0.0, (head_bottom + HEIGHT) * 0.5, 0.0),
		Vector3(PIER_HALF * 2.0, HEIGHT - head_bottom, DEPTH), mats["body"])
	# 出檐：瓦檐挑出、瓦脊收进，与城墙同一断面
	_box(gate, "GateEave", Vector3(0.0, HEIGHT + EAVE_HEIGHT * 0.5, 0.0),
		Vector3(PIER_HALF * 2.0 + EAVE_OUTSET * 2.0, EAVE_HEIGHT, DEPTH + EAVE_OUTSET * 2.0), mats["eave"])
	_box(gate, "GateRidge", Vector3(0.0, HEIGHT + EAVE_HEIGHT + RIDGE_HEIGHT * 0.5, 0.0),
		Vector3(PIER_HALF * 2.0 - RIDGE_INSET * 2.0, RIDGE_HEIGHT, DEPTH - RIDGE_INSET * 2.0), mats["ridge"])
	# 门额：楣墙南面的匾额，比墙面凸出一点
	_box(gate, "GatePlaque", Vector3(0.0, head_bottom + 1.2, half_depth + 0.06),
		Vector3(3.0, 1.15, 0.22), mats["base"])
	# 门扇：深色木门，落在门洞进深中段
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("4a3527")
	wood.roughness = 0.85
	for side in [-1.0, 1.0]:
		_box(gate, "GateLeaf", Vector3(side * (HALF_SPAN * 0.5), (OPENING_HEIGHT - 0.1) * 0.5, 0.0),
			Vector3(HALF_SPAN - 0.1, OPENING_HEIGHT - 0.1, 0.22), wood)

static func _box(parent: Node3D, label: String, at: Vector3, size: Vector3, mat: Material) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var box := BoxMesh.new()
	box.size = size
	node.mesh = box
	node.material_override = mat
	node.position = at
	parent.add_child(node)
