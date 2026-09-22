extends SceneTree
## 第二幕 3D 过场逐镜头截屏验收（输出到 docs/opening_boat/）。
## 带渲染窗口跑（不要 --headless）：
##   godot --path . --script res://tools/capture_opening_boat.gd

const SCENE := "res://scenes/main/opening_boat.tscn"
const OUT_DIR := "res://docs/opening_boat"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	var dir := DirAccess.open("res://")
	if not dir.dir_exists(OUT_DIR):
		dir.make_dir_recursive(OUT_DIR)
	var scene = load(SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var n: int = scene.line_count()
	for i in range(n):
		scene.capture_pose(i)
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var p := "%s/boat_shot_%02d.png" % [OUT_DIR, i + 1]
		img.save_png(p)
		print("BOAT_CAP ", p)
	quit(0)