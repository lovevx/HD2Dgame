extends SceneTree
## Art integration checks complementary to validate_colpo.gd's gameplay checks.
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

## 素材正面为 +Z：节点的 +Z 应当指向相机，误差小于 1°。
func faces_camera(node: Node3D, camera: Node3D) -> bool:
	var forward := node.global_transform.basis.z
	var to_camera := camera.global_position - node.global_position
	if Vector2(to_camera.x, to_camera.z).length_squared() < 0.0001:
		return true
	return absf(wrapf(atan2(forward.x, forward.z) - atan2(to_camera.x, to_camera.z), -PI, PI)) < 0.02

## 取一块已转向相机的 MultiMesh 分块所属的散布层，用来验证逐帧转向确实在跑。
func billboard_foliage(scene: Node3D) -> HD2DFoliage:
	for node in scene.get_children():
		if node is HD2DFoliage and not node._billboards.is_empty():
			return node
	return null

## 实例本地 +Z 在世界空间里的水平朝向。
func instance_forward_yaw(instance: MultiMeshInstance3D) -> float:
	var forward := instance.global_transform.basis * instance.multimesh.get_instance_transform(0).basis.z
	return atan2(forward.x, forward.z)

func run() -> void:
	var library := load("res://assets/environments/jungle/jungle_library.tres") as HD2DAssetLibrary
	check(library != null and library.assets.size() == 16, "Curated library must contain 16 assets")
	var identities := {}
	for asset in library.assets:
		check(not asset.source_missing(), "Missing dependency: " + asset.title)
		check(not identities.has(asset.library_entry_id), "Duplicate library identity: " + asset.title)
		identities[asset.library_entry_id] = true
		check(asset.source_path.begins_with("res://assets/environments/jungle/props/"), "Uncurated source: " + asset.title)
	var palette: HD2DStage = load("res://scenes/workshop/jungle_palette.tscn").instantiate()
	root.add_child(palette)
	await process_frame
	check(palette.library == library, "Workshop palette must use the curated library")
	check(palette.get_node("Scenery").get_child_count() == 17, "Palette must expose all 16 assets plus its foliage layer")
	palette.free()
	for level in ["outer", "clearing"]:
		var scene: Node3D = load("res://scenes/world/colpo_forest_%s.tscn" % level).instantiate()
		for name in ["WaveDirector", "BossDirector"]:
			var director := scene.get_node_or_null(name)
			if director:
				director.free()
		root.add_child(scene)
		await process_frame
		var camera: Camera3D = scene.get_node("Camera3D")
		check(camera.rotation_degrees.x >= -29 and camera.rotation_degrees.x <= -19 and camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Low-angle HD2D camera/card contract changed")
		var cards_face_camera := true
		var turning_faces_camera := true
		var plants_face_camera := 0
		var lane_clear := true
		var sources_curated := true
		for node in scene.get_children():
			if node is HD2DProp:
				sources_curated = sources_curated and node.asset.resource_path.begins_with("res://assets/environments/jungle/")
				if node.is_in_group("colpo_tree"):
					if node.asset.facing == 2:
						plants_face_camera += 1
						turning_faces_camera = turning_faces_camera and faces_camera(node, camera)
					else:
						cards_face_camera = cards_face_camera and absf(node.rotation_degrees.y - 8.0) <= 7.1
			if node is HD2DFoliage:
				for record in node.records:
					if record.asset.facing == 2:
						plants_face_camera += 1
					else:
						cards_face_camera = cards_face_camera and absf(rad_to_deg(record.yaw) - 8.0) <= 9.1
					if node.name == "GroundCover":
						var p: Vector3 = record.position
						lane_clear = lane_clear and (absf(p.x) >= 3.4 if level == "outer" else Vector2(p.x / 16.0, p.z / 19.5).length() >= 1.0)
		check(cards_face_camera, "Pixel cards became edge-on in " + level)
		check(turning_faces_camera, level + ": turning assets do not face the camera")
		check(plants_face_camera > 0, "No plant keeps facing the camera in " + level)
		# 薄片植被必须逐帧转向相机。MultiMesh 的实例数据存在渲染服务器里，无头模式读回来全是单位矩阵，
		# 因此无头只验证分组与处理已就绪；实际转向在有渲染时逐帧比对朝向。
		var foliage := billboard_foliage(scene)
		check(foliage != null, "Foliage billboard group missing in " + level)
		if foliage != null:
			check(foliage.is_processing(), level + ": billboard foliage is not updating")
			if DisplayServer.get_name() != "headless":
				var instance: MultiMeshInstance3D = foliage._billboards[0].instance
				var before := instance_forward_yaw(instance)
				camera.position += Vector3(30, 0, 0)
				# process_frame 在节点 _process 之前发出，多等两帧再读转向结果。
				for i in 3:
					await process_frame
				check(absf(wrapf(before - instance_forward_yaw(instance), -PI, PI)) > 0.02, level + ": billboard foliage did not follow the camera")
				camera.position -= Vector3(30, 0, 0)
				for i in 3:
					await process_frame
		check(lane_clear, "Ground cover obstructs the gameplay lane in " + level)
		check(sources_curated, "Props bypass curated wrappers in " + level)
		for node in get_nodes_in_group("colpo_layout_marker"):
			check(not node.visible, "Layout-only marker visible during normal play")
		scene.free()
		await process_frame
	for failure in failures:
		push_error(failure)
	print("JUNGLE_ART: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)
