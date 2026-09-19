extends Node3D
## 刀芒：有速度、射程与墙体阻挡的物理斩击，首个命中的目标结算一次。
const Skills := preload("res://data/combat_skills.gd")
var source: Node3D
var direction := Vector3.FORWARD
var damage := 0.0
var traveled := 0.0

func configure(attacker: Node3D, forward: Vector3, physical_damage: float) -> void:
	source = attacker
	direction = forward.normalized()
	damage = physical_damage

func _ready() -> void:
	add_to_group("sword_waves")
	var wave := MeshInstance3D.new()
	wave.mesh = _arc_mesh()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.06, 0.05, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.06, 0.04)
	wave.material_override = mat
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wave.position.y = 0.65
	add_child(wave)
	var raised := MeshInstance3D.new()
	raised.mesh = wave.mesh
	raised.material_override = mat
	raised.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	raised.position.y = 0.9
	raised.rotation_degrees.x = 60.0
	raised.scale = Vector3(0.8, 0.8, 0.8)
	add_child(raised)
	rotation.y = atan2(-direction.x, -direction.z)

func _arc_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 16:
		var a0 := lerpf(-0.9, 0.9, float(i) / 16.0)
		var a1 := lerpf(-0.9, 0.9, float(i + 1) / 16.0)
		var inner0 := Vector3(sin(a0) * 0.75, 0, -cos(a0) * 0.75)
		var outer0 := Vector3(sin(a0) * 1.15, 0, -cos(a0) * 1.15)
		var inner1 := Vector3(sin(a1) * 0.75, 0, -cos(a1) * 0.75)
		var outer1 := Vector3(sin(a1) * 1.15, 0, -cos(a1) * 1.15)
		for point in [inner0, outer0, outer1, inner0, outer1, inner1]:
			surface.add_vertex(point)
	return surface.commit()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(source):
		queue_free()
		return
	var step := minf(Skills.WAVE_SPEED * delta, Skills.WAVE_RANGE - traveled)
	var start := global_position
	var end := start + direction * step
	var query := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 0.65, end + Vector3.UP * 0.65)
	query.exclude = [source.get_rid()]
	var obstacle := get_world_3d().direct_space_state.intersect_ray(query)
	var blocked: bool = not obstacle.is_empty() and not obstacle.collider.is_in_group("enemies") and not obstacle.collider.is_in_group("targets")
	if blocked:
		end = obstacle.position - Vector3.UP * 0.65
	if _hit_target(start, end):
		queue_free()
		return
	global_position = end
	traveled += start.distance_to(end)
	if blocked or traveled >= Skills.WAVE_RANGE - 0.001:
		queue_free()

func _hit_target(start: Vector3, end: Vector3) -> bool:
	var candidates := get_tree().get_nodes_in_group("enemies")
	candidates.append_array(get_tree().get_nodes_in_group("targets"))
	var segment := end - start
	for enemy in candidates:
		if not enemy.is_alive():
			continue
		var offset: Vector3 = enemy.global_position - start
		offset.y = 0
		var progress := clampf(offset.dot(segment) / maxf(segment.length_squared(), 0.0001), 0.0, 1.0)
		var closest := start + segment * progress
		var bulk := float(enemy.hit_radius()) if enemy.has_method("hit_radius") else 0.0
		if enemy.global_position.distance_to(closest) > Skills.WAVE_HALF_WIDTH + bulk:
			continue
		source._damage_target(enemy, damage, direction * 3.0)
		return true
	return false
