extends SceneTree
## 出「港口装饰景观层」的验收图到 .tmp_preview/hub_zones/。
## 只写 .tmp_preview，不动 docs/ 里既有的文档预览图。
## 需要真实渲染设备，用窗口模式跑（**不要**加 --headless）：
##   godot --path . --script res://tools/capture_dressing.gd
const OUT_DIR := "res://.tmp_preview/hub_zones"

const SHOTS := [
	{"tag": "east_front", "mode": "free", "pos": Vector3(30.0, 5.0, -2.0), "look": Vector3(30.0, 2.5, -15.0), "fov": 46.0},
	{"tag": "east_aerial", "mode": "free", "pos": Vector3(43.0, 22.0, 2.0), "look": Vector3(28.0, 0.5, -16.0), "fov": 40.0},
	{"tag": "west_front", "mode": "free", "pos": Vector3(-33.0, 5.5, 10.0), "look": Vector3(-33.0, 2.2, -4.0), "fov": 48.0},
	{"tag": "west_aerial", "mode": "free", "pos": Vector3(-47.0, 22.0, 8.0), "look": Vector3(-33.0, 0.5, -4.0), "fov": 42.0},
	{"tag": "shoreline", "mode": "free", "pos": Vector3(2.0, 6.0, 3.0), "look": Vector3(4.0, 0.5, 13.0), "fov": 52.0},
	{"tag": "town_overview", "mode": "free", "pos": Vector3(0.0, 46.0, 34.0), "look": Vector3(0.0, 0.0, -9.0), "fov": 55.0},
	{"tag": "game_street_south", "mode": "game", "player": Vector3(0.0, 0.0, 2.0)},
	{"tag": "game_east_quarter", "mode": "game", "player": Vector3(26.0, 0.0, -9.5)},
	{"tag": "game_west_yard", "mode": "game", "player": Vector3(-31.0, 0.0, 1.5)},
]

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene = load("res://scenes/world/harbor.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.0).timeout
	var player: Node3D = scene.get_node("Player")
	var game_cam: Camera3D = scene.get_node("Camera3D")
	var free_cam := Camera3D.new()
	free_cam.fov = 42.0
	scene.add_child(free_cam)
	for shot in SHOTS:
		if shot["mode"] == "free":
			free_cam.fov = float(shot["fov"])
			game_cam.current = false
			free_cam.current = true
			free_cam.global_position = shot["pos"]
			free_cam.look_at(shot["look"], Vector3.UP)
			await create_timer(0.4).timeout
		else:
			free_cam.current = false
			game_cam.current = true
			player.global_position = shot["player"]
			await create_timer(2.2).timeout
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [OUT_DIR, shot["tag"]]
		var img := root.get_texture().get_image()
		img.save_png(path)
		print("SHOT: %s  %dx%d" % [path, img.get_width(), img.get_height()])
	quit(0)
