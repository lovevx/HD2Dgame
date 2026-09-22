extends SceneTree
## 机位对照渲染：把四个可玩场景按当前运行时机位各拍一张，供与参考画面比对。
## 不覆盖任何机位参数，纯粹是"现在的游戏长什么样"。
var output := "res://docs/camera_sword"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	await shoot("harbor", "res://scenes/world/harbor.tscn", "Player", Vector3(0, 0, -9.0))
	await shoot("trial", "res://scenes/main/main.tscn", "player", Vector3(0, 0, 2.0))
	await shoot("outer", "res://scenes/world/colpo_forest_outer.tscn", "Player", Vector3(0, 0, 7.0))
	await shoot("clearing", "res://scenes/world/colpo_forest_clearing.tscn", "Player", Vector3(0, 0, 3.0))
	await create_timer(0.2).timeout
	quit()

func shoot(tag: String, scene_path: String, player_path: String, at: Vector3) -> void:
	var scene: Node = load(scene_path).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.8).timeout
	var player: CharacterBody3D = scene.get_node(player_path)
	player.set_physics_process(false)
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	player.position = at
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var camera: Camera3D = scene.get_node("Camera3D")
	var path := "%s/final_%s.png" % [output, tag]
	root.get_texture().get_image().save_png(path)
	print("SWORD_CAMERA: %s pitch=%.1f fov=%.1f dist=%.1f draw_calls=%d" % [
		path, -camera.rotation_degrees.x, camera.fov, camera.position.length(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	scene.free()
	await process_frame
