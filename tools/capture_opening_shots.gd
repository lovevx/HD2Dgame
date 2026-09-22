extends SceneTree
## 开场过场逐镜头截屏验收（不覆盖任何既有 docs 图，全部输出到 docs/opening/）。
## 带渲染窗口跑（不要 --headless）：
##   godot --path . --script res://tools/capture_opening_shots.gd

const OPENING := "res://scenes/main/opening.tscn"
const OUT_DIR := "res://docs/opening"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	var dir := DirAccess.open("res://")
	if not dir.dir_exists(OUT_DIR):
		dir.make_dir_recursive(OUT_DIR)
	var open = load(OPENING).instantiate()
	root.add_child(open)
	current_scene = open
	await process_frame
	await process_frame
	# ---------- 第一幕（2D）：SHOTS_0 十镜 ----------
	for i in 10:
		open.capture_pose(i, 0)
		await create_timer(0.28).timeout
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var p := "%s/shot_%02d.png" % [OUT_DIR, i + 1]
		img.save_png(p)
		print("SHOT_CAP ", p)
	quit(0)