extends SceneTree
## 出「铸潮工坊 / 港务委托所」的验收图到 .tmp_preview/hub_zones/。
## 只写 .tmp_preview，不动 docs/ 里既有的文档预览图（那是 check_harbor_hub 非无头运行的产物）。
## 需要真实渲染设备，用窗口模式跑（**不要**加 --headless，否则取不到画面）：
##   godot --path . --script res://tools/capture_hub_districts.gd
##
## 机位分两类：
##   free —— 自由机位，近距离正视门面（用来核对立面到底有没有门窗，别再出白墙）；
##   game —— 玩家站到某点、用港口默认机位（16° 俯角 / 48 米）收敛后实拍，看玩家真正看到什么。
const OUT_DIR := "res://.tmp_preview/hub_zones"

const SHOTS := [
	{"tag": "forge_front", "mode": "free", "pos": Vector3(10.5, 4.2, -1.5), "look": Vector3(10.5, 2.6, -13.0), "fov": 42.0},
	{"tag": "forge_front_west", "mode": "free", "pos": Vector3(4.0, 4.2, -1.0), "look": Vector3(6.0, 2.8, -13.0), "fov": 42.0},
	{"tag": "forge_aerial", "mode": "free", "pos": Vector3(24.0, 20.0, 8.0), "look": Vector3(10.0, 1.0, -13.5), "fov": 34.0},
	{"tag": "quest_front", "mode": "free", "pos": Vector3(-10.5, 4.2, 7.5), "look": Vector3(-10.5, 2.6, -5.0), "fov": 42.0},
	{"tag": "quest_west", "mode": "free", "pos": Vector3(-21.0, 4.5, 6.5), "look": Vector3(-20.0, 2.6, -5.0), "fov": 46.0},
	{"tag": "quest_aerial", "mode": "free", "pos": Vector3(-26.0, 20.0, 12.0), "look": Vector3(-15.0, 1.0, -6.0), "fov": 34.0},
	{"tag": "hub_pair", "mode": "free", "pos": Vector3(0.0, 26.0, 4.0), "look": Vector3(0.0, 0.0, -9.0), "fov": 46.0},
	{"tag": "game_forge", "mode": "game", "player": Vector3(10.0, 0.0, -6.5)},
	{"tag": "game_quest", "mode": "game", "player": Vector3(-10.0, 0.0, 3.0)},
	{"tag": "game_street", "mode": "game", "player": Vector3(0.0, 0.0, -8.0)},
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
			# 用港口自己的机位：先让轨道控制器把相机收敛到默认档。
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
