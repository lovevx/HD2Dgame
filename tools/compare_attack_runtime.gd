extends SceneTree
## 运行时对比 v3：用"宽行判定"（排除刀/刀光）测量攻击 vs 待机/跑步的本体世界尺寸。
## 宽行 = 暗像素宽度 >= FOOT_MIN_WIDTH 的行（刀是 2-4px 细条，人物躯干/脚是宽块）。
## 运行：godot --headless --path . --script res://tools/compare_attack_runtime.gd

const FRAMES_PATH := "res://assets/characters/player_frames_video.tres"
const BASE_PIXEL := 0.016
const GROUND_SLACK := 16
const DARK_SUM := 420
const FOOT_MIN_WIDTH := 10

func _init() -> void:
	var frames: SpriteFrames = load(FRAMES_PATH)
	if frames == null:
		quit(1)
		return
	var dirs := ["down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right"]
	var action_heights := {}
	for action in ["idle", "run", "attack"]:
		action_heights[action] = {}
		for direction in dirs:
			var anim := "%s_%s" % [action, direction]
			if not frames.has_animation(anim):
				continue
			var hs: Array[float] = []
			for i in frames.get_frame_count(anim):
				var tex: AtlasTexture = frames.get_frame_texture(anim, i) as AtlasTexture
				var region: Rect2i = tex.region
				var img := tex.atlas.get_image()
				if img == null:
					continue
				var rows: Array[float] = []
				for y in range(int(region.position.y), int(region.position.y + region.size.y)):
					var w := 0
					for x in range(int(region.position.x), int(region.position.x + region.size.x)):
						var c: Color = img.get_pixel(x, y)
						if c.a > 0.09 and (int(c.r * 255) + int(c.g * 255) + int(c.b * 255)) < DARK_SUM:
							w += 1
					if w >= FOOT_MIN_WIDTH:
						rows.append(float(y))
				if rows.is_empty():
					continue
				hs.append((rows.max() - rows.min() + 1.0) * BASE_PIXEL)
			action_heights[action][direction] = hs

	var reference: Array[float] = []
	for direction in dirs:
		reference.append_array(action_heights["idle"].get(direction, []))
		reference.append_array(action_heights["run"].get(direction, []))
	var ref_min := float(reference.min()) * 1.0
	var ref_max := float(reference.max()) * 1.0
	print("== 待机+跑步 宽行本体世界高: %.3f ~ %.3f（基准）" % [ref_min, ref_max])
	for direction in dirs:
		var hs: Array[float] = action_heights["attack"].get(direction, [])
		if hs.is_empty():
			continue
		print("  攻击_%-12s 世界 %.3f~%.3f 波幅%3dpx" % [
			direction, hs.min(), hs.max(), int((hs.max() - hs.min()) / BASE_PIXEL)])
	quit(0)
