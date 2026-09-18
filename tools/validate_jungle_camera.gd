extends SceneTree
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func settle(scene: Node3D, steps := 180, dt := 1.0 / 60.0) -> void:
	for i in steps:
		scene._update_camera(dt)

func onscreen(camera: Camera3D, at: Vector3, margin: float) -> bool:
	var uv := camera.unproject_position(at) / camera.get_viewport().get_visible_rect().size
	return not camera.is_position_behind(at) and uv.x > margin and uv.x < 1.0 - margin and uv.y > margin and uv.y < 1.0 - margin

## 鼠标让路：光标方向决定焦点让出的方向，并且真的接到取景里。
func check_mouse_lead(scene: Node3D, camera: Camera3D, level: String) -> void:
	var player: CharacterBody3D = scene.get_node("Player")
	player.position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	scene._camera_lead = Vector3.ZERO
	var lead = scene.get("_mouse_lead")
	var size := Vector2(1280, 720)
	check(lead.offset_for(camera, size, size * 0.5).is_zero_approx(), level + ": cursor at screen center must not move the camera")
	check(lead.offset_for(camera, size, Vector2(size.x, size.y * 0.5)).is_equal_approx(ground_axis(camera.global_transform.basis.x) * lead.max_lean), level + ": cursor on the right must pull the camera right")
	check(lead.offset_for(camera, size, Vector2(size.x * 0.5, size.y)).is_equal_approx(ground_axis(-camera.global_transform.basis.y) * lead.max_lean), level + ": cursor at the bottom must pull the camera towards the viewer")
	settle(scene)
	var baseline := camera.position
	lead._seen_mouse = true
	settle(scene)
	var leaned := camera.position
	check(leaned.distance_to(baseline) > 0.5, level + ": mouse lead is not wired into the framing")
	lead._seen_mouse = false
	lead.offset = Vector3.ZERO
	settle(scene)
	check(camera.position.distance_to(baseline) < 0.05, level + ": camera must return when the mouse lead clears")

## 世界向量在水平面上的单位方向；纯竖直的向量返回零。
func ground_axis(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0, v.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.ZERO

func run() -> void:
	for level in ["outer", "clearing"]:
		var scene: Node3D = load("res://scenes/world/colpo_forest_%s.tscn" % level).instantiate()
		for name in ["WaveDirector", "BossDirector"]:
			var node := scene.get_node_or_null(name)
			if node:
				node.free()
		root.add_child(scene)
		scene.set_process(false)
		var player: CharacterBody3D = scene.get_node("Player")
		var camera: Camera3D = scene.get_node("Camera3D")
		player.set_physics_process(false)
		check(onscreen(camera, player.position + Vector3.UP, 0.15), level + ": spawn must already be framed")
		player.position = Vector3.ZERO
		player.velocity = Vector3.ZERO
		settle(scene)
		var uv := camera.unproject_position(player.position) / camera.get_viewport().get_visible_rect().size
		check(uv.y > 0.55 and uv.y < 0.66, level + ": feet should sit below screen center")
		var before := camera.position
		for facing in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
			player.facing = facing
			settle(scene, 30)
		check(camera.position.distance_to(before) < 0.005, level + ": aiming while stationary must not pan camera")
		var edge_x := 20.3 if level == "outer" else 24.4
		var edge_z := 23.2 if level == "outer" else 24.0
		for dimensions in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1680, 720)]:
			root.size = dimensions
			await process_frame
			for at in [Vector3.ZERO, Vector3(edge_x, 0, edge_z), Vector3(-edge_x, 0, edge_z), Vector3(edge_x, 0, -edge_z), Vector3(-edge_x, 0, -edge_z)]:
				player.position = at
				settle(scene)
				check(onscreen(camera, at + Vector3.UP, 0.08), "%s: player left safe screen area at %s / %s" % [level, at, dimensions])
				var ground_screen := camera.unproject_position(at)
				var hit = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(ground_screen), camera.project_ray_normal(ground_screen))
				check(hit != null and hit.distance_to(at) < 0.01, level + ": perspective mouse-to-ground aiming mismatch")
		player.position = Vector3(0, 0, 10)
		settle(scene)
		player.velocity = Vector3(0, 0, -22)
		var dash_visible := true
		for i in 33:
			player.position += player.velocity / 60.0
			scene._update_camera(1.0 / 60.0)
			dash_visible = dash_visible and onscreen(camera, player.position + Vector3.UP, 0.08)
		check(dash_visible, level + ": high-speed dash escaped framing")
		var results: Array[Vector3] = []
		for fps in [30, 120]:
			player.position = Vector3.ZERO
			player.velocity = Vector3.ZERO
			scene._camera_lead = Vector3.ZERO
			settle(scene)
			player.velocity = Vector3(4, 0, 0)
			for i in fps * 2:
				player.position += player.velocity / float(fps)
				scene._update_camera(1.0 / float(fps))
			results.append(camera.position)
		check(results[0].distance_to(results[1]) < 0.06, level + ": camera follow varies too much across frame rates")
		check_mouse_lead(scene, camera, level)
		scene.free()
		await process_frame
	for failure in failures:
		push_error(failure)
	print("JUNGLE_CAMERA: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
