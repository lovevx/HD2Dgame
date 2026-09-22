class_name EncounterZone
extends Node3D
## 遭遇区（P1 v1）：玩家踏入且圈内有存活敌人 → 触发回合战斗。
## 结界 = 程序化半透明网格环，暗示战斗活动边界；机体由脚本运行时搭，无需 .tscn 编辑器配置。

const RADIUS := 8.0
const GRID_STEP := 0.9
const EnemyScript := preload("res://scripts/combat/enemy.gd")

var radius := RADIUS
var active := true

func _ready() -> void:
	_build_fence()

func _build_fence() -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.8
	mesh.rings = 3
	mesh.radial_segments = 48
	ring.mesh = mesh
	ring.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.37, 0.85, 0.94, 0.08)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

## 圈判定（世界 x/z 平面，圆心 = 本节点）。
func in_radius(world: Vector3) -> bool:
	var flat := world - global_position
	flat.y = 0.0
	return flat.length() <= radius

## 玩家踏入且圈内存在存活敌人（非木桩）→ 返回圈内敌人数组（触发用），无敌人返回空。
func enemies_in_zone(enemies: Array[Node]) -> Array:
	var foes: Array[Node] = []
	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if enemy.has_method("is_alive") and not enemy.is_alive():
			continue
		if enemy.get("kind") != null and enemy.get("kind") == EnemyScript.Kind.DUMMY:
			continue
		if in_radius(enemy.global_position):
			foes.append(enemy)
	return foes