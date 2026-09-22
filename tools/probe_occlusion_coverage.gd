extends SceneTree
## 前景遮挡淡出的覆盖面诊断（只读，不改场景、不渲染截图）。
##   1) 材质覆盖：全场景扫「够高」网格，按淡出模式分组统计，
##      点名「不在淡出材质登记表里 → 永远不会淡」的着色器；
##   2) 多 surface 且各面材质不一致的网格（_material_of 只看 surface 0，可能误判）；
##   3) 广撒网：玩家摆上主城网格化点位（13 列 × 10 行），确定性摆好相机后直接跑
##      _scan，打印每个点位命中的淡出单元 —— 一张「谁在哪儿挡人」的覆盖地图。
##
## 用法：godot --headless --path . --script res://tools/probe_occlusion_coverage.gd

const SCENE_PATH := "res://scenes/world/harbor.tscn"

## 与 harbor.gd 的机位常量保持一致（相机位置确定性手摆，不等 lerp 收敛）。
const CAM_PITCH := 16.0
const CAM_DISTANCE := 48.1
const FOCUS_LIMIT_X := 36.0
const FOCUS_LIMIT_Z := Vector2(-27.0, 16.0)
const LOOK_AHEAD_Z := -3.0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load(SCENE_PATH).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.4).timeout
	# 停掉场景的相机跟随，相机位置全程由本脚本确定性控制。
	scene.set_process(false)
	var player: Node3D = scene.get_node("Player")
	player.set_physics_process(false)
	var controller: Node = player.get_node_or_null("CameraOcclusionFade")
	if controller == null:
		print("COV_CHECK: FAIL  玩家身上找不到 CameraOcclusionFade")
		quit(1)
		return
	controller.set_physics_process(false)
	var camera: Camera3D = scene.get_node_or_null("Camera3D")
	if camera == null:
		print("COV_CHECK: FAIL  场景里没有 Camera3D")
		quit(1)
		return

	# ---- 1) 材质覆盖统计 ----
	controller._refresh()
	var shader_paths := {}
	var unsupported: Array[String] = []
	var standard_count := 0
	var shader_count := 0
	var mixed_surface: Array[String] = []
	for candidate in controller._candidates:
		# 与 camera_occlusion_fade 同款：候选缓存里可能留着已释放实例，
		# 判存活必须在带类型的赋值之前。
		var node_ref = candidate["node"]
		if not is_instance_valid(node_ref):
			continue
		var inst := node_ref as GeometryInstance3D
		if inst == null:
			continue
		# 多 surface 检查：surface 0 之外还有不同材质的面。
		var mesh_inst := inst as MeshInstance3D
		if mesh_inst != null and mesh_inst.mesh != null and mesh_inst.mesh.get_surface_count() > 1:
			var first: Material = mesh_inst.get_active_material(0)
			for s in range(1, mesh_inst.mesh.get_surface_count()):
				var other: Material = mesh_inst.get_active_material(s)
				if other != null and other != first:
					mixed_surface.append("%s(surface %d=%s)" % [inst.name, s, other.get_class()])
					break
		var mode: String = controller._fade_mode(inst)
		var material: Material = controller._material_of(inst)
		if material is ShaderMaterial:
			var path: String = (material as ShaderMaterial).shader.resource_path \
				if (material as ShaderMaterial).shader != null else "(inline)"
			shader_paths[path] = int(shader_paths.get(path, 0)) + 1
			shader_count += 1
			if mode == "":
				unsupported.append("%s → %s" % [inst.name, path])
		elif material is StandardMaterial3D or material == null:
			standard_count += 1
	print("COV_CHECK: 候选网格 %d 个 = 着色器 %d + 标准材质 %d" % [
		controller._candidates.size(), shader_count, standard_count])
	for path in shader_paths:
		var supported: bool = path.contains("preset_normal") or path.contains("harbor_wall")
		print("COV_CHECK:   shader %-58s x%d  %s" % [path, shader_paths[path], "已支持" if supported else "!! 不支持（不会淡）"])
	for line in unsupported:
		print("COV_CHECK:   不淡实例: %s" % line)
	print("COV_CHECK: 多 surface 材质不一致 %d 个 %s" % [mixed_surface.size(), str(mixed_surface)])

	# ---- 2) 广撒网扫描 ----
	var xs := [-36.0, -30.0, -24.0, -18.0, -12.0, -6.0, 0.0, 6.0, 12.0, 18.0, 24.0, 30.0, 36.0]
	var zs := [-26.0, -22.0, -18.0, -14.0, -10.0, -6.0, -2.0, 2.0, 6.0, 10.0]
	var hit_rows: Array[String] = []
	var unit_hits := {}
	for x in xs:
		for z in zs:
			var at := Vector3(x, 0, z)
			player.position = at
			_place_camera(camera, at)
			for key in controller._active:
				controller._active[key]["wanted"] = false
			controller._scan(camera)
			var names: Array[String] = []
			for key in controller._active:
				if bool(controller._active[key]["wanted"]):
					var label := str(key.name)
					names.append(label)
					unit_hits[label] = int(unit_hits.get(label, 0)) + 1
			if not names.is_empty():
				names.sort()
				hit_rows.append("(%5.1f,%5.1f): %s" % [x, z, ", ".join(names)])
	print("COV_CHECK: ---- 遮挡地图（%d/%d 个点位命中）----" % [hit_rows.size(), xs.size() * zs.size()])
	for row in hit_rows:
		print("COV_CHECK:   %s" % row)
	var ranking: Array[String] = []
	for label in unit_hits:
		ranking.append("%d 次 %s" % [unit_hits[label], label])
	ranking.sort()
	ranking.reverse()
	print("COV_CHECK: ---- 挡人次数排行 ----")
	for row in ranking:
		print("COV_CHECK:   %s" % row)
	quit(0)

## 按 harbor.gd 的机位公式确定性摆相机：锚点(收边) + 构图偏移(北推3m) + 轨道偏移(16°/48.1m)。
func _place_camera(camera: Camera3D, player_at: Vector3) -> void:
	var anchor := Vector3(
		clampf(player_at.x, FOCUS_LIMIT_X * -1.0, FOCUS_LIMIT_X), 0.0,
		clampf(player_at.z, FOCUS_LIMIT_Z.x, FOCUS_LIMIT_Z.y))
	# z ≤ 8 的街市段构图偏移为北推 3m（smoothstep 在 z≤8 时为 0）。
	var look := 3.0 if player_at.z <= 8.0 else LOOK_AHEAD_Z * -1.0 * (1.0 - smoothstep(8.0, 14.0, player_at.z))
	var pitch := deg_to_rad(CAM_PITCH)
	var orbit_offset := Vector3(0.0, sin(pitch) * CAM_DISTANCE, cos(pitch) * CAM_DISTANCE)
	camera.global_position = anchor + Vector3(0, 0, -look) + orbit_offset
	camera.rotation_degrees = Vector3(-CAM_PITCH, 0.0, 0.0)
