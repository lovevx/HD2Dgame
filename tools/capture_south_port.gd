extends SceneTree
## 渲染南岸客货码头的四个机位到 docs/harbor_south_port_<tag>.png。
## 需要真实渲染设备，用窗口模式跑（**不要**加 --headless，否则取不到画面）：
##   godot --path . --script res://tools/capture_south_port.gd
## 机位：aerial 斜俯全景 / top 正俯 / town 从砖路南望 / sea 自海面向北看。
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene = load("res://scenes/world/harbor.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.8).timeout
	var cam := Camera3D.new()
	cam.fov = 34.0
	scene.add_child(cam)
	cam.make_current()
	var shots := [
		{"tag": "aerial", "pos": Vector3(11.0, 30.0, 34.0), "look": Vector3(11.0, 0.5, 17.0)},
		{"tag": "top", "pos": Vector3(11.0, 40.0, 18.2), "look": Vector3(11.0, 0.0, 18.0)},
		{"tag": "town", "pos": Vector3(9.0, 7.0, -1.0), "look": Vector3(12.0, 1.0, 19.0)},
		{"tag": "sea", "pos": Vector3(30.0, 6.0, 36.0), "look": Vector3(13.0, 1.0, 16.0)},
	]
	for s in shots:
		cam.global_position = s["pos"]
		cam.look_at(s["look"], Vector3.UP)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		var path := "res://docs/harbor_south_port_%s.png" % s["tag"]
		var img := root.get_texture().get_image()
		img.save_png(path)
		print("SHOT: %s  %dx%d  <- %s" % [path, img.get_width(), img.get_height(), str(s["pos"])])
	quit(0)
