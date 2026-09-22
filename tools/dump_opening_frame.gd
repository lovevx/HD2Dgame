extends SceneTree
## 客观校验：采样开场镜头关键像素亮度，判断卡车光暴等元素是否真的没画出来。
##   godot --path . --script res://tools/dump_opening_frame.gd

const OPENING := "res://scenes/main/opening.tscn"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	await process_frame
	var open = load(OPENING).instantiate()
	root.add_child(open)
	current_scene = open
	await process_frame
	await process_frame
	# 卡车镜头
	open.capture_pose(2, 0)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var pts := [
		Vector2i(727, 640), Vector2i(1193, 640), Vector2i(960, 630),
		Vector2i(960, 470), Vector2i(300, 300), Vector2i(1650, 300),
		Vector2i(960, 900)]
	for p in pts:
		var c: Color = img.get_pixel(p.x, p.y)
		print("PX ", p, " -> ", c)
	var lo := 1e9
	var hi := -1e9
	var sum := 0.0
	var n := 0
	for y in range(0, 1080, 8):
		for x in range(0, 1920, 8):
			var v: float = img.get_pixel(x, y).get_luminance()
			lo = mini(int(lo), int(v * 255.0))
			hi = maxi(int(hi), int(v * 255.0))
			sum += v
			n += 1
	print("LUM range 8..%d..%d avg=%.2f/255" % [lo, hi, sum / n * 255.0])
	quit(0)