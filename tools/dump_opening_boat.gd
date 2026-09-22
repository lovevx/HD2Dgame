extends SceneTree
## 客观校验 3D 船镜头：无条件投影码头灯位 + 夜空高区采样。
##   godot --path . --script res://tools/dump_opening_boat.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	var scene = load("res://scenes/main/opening_boat.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	scene.capture_pose(0)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	print("CAM_NULL=", cam_of(scene) == null)
	print("PTS=", scene.get("_port_pts").size())
	var img: Image = root.get_texture().get_image()
	var probes := [Vector3(0.0, 4.0, 16.0), Vector3(6.0, 2.2, 16.5), Vector3(-15.0, 2.2, 16.5)]
	for p in probes:
		var sp: Vector2 = cam_of(scene).unproject_position(p)
		if sp.x < 0 or sp.x > 1919 or sp.y < 0 or sp.y > 1079:
			print("PROJ ", p, " -> OFFSCREEN ", int(sp.x), ",", int(sp.y))
			continue
		var c: Color = img.get_pixel(int(sp.x), int(sp.y))
		print("PROJ ", p, " -> px(", int(sp.x), ",", int(sp.y), ") = ", c)
	# 夜空高区（标题上方 y<170）最亮点
	var best := Color(0, 0, 0)
	var bx := 0
	var by := 0
	for y in range(40, 175):
		for x in range(0, 1920, 2):
			var c: Color = img.get_pixel(x, y)
			if c.get_luminance() > best.get_luminance():
				best = c
				bx = x
				by = y
	print("SKY_BRIGHTEST px(", bx, ",", by, ") = ", best)
	quit(0)

func cam_of(scene: Node) -> Camera3D:
	for c in scene.get_children():
		if c is Camera3D:
			return c
	return null