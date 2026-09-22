extends SceneTree
## 离屏渲染对比：用 SubViewport 把 待机/跑步/攻击 的 AnimatedSprite3D 实际渲染成 PNG。
## headless 下 dummy 渲染驱动不支持，但先试；失败则提示用编辑器跑。

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var frames: SpriteFrames = load("res://assets/characters/player_frames_video.tres")
	if frames == null:
		print("加载失败")
		quit(1)
		return
	var samples := [
		["idle_down", 0, "idle"],
		["run_down", 0, "run"],
		["attack_down", 0, "attack_s"],
		["attack_down", 6, "attack_swing"],
		["attack_down", 12, "attack_hit"],
	]
	for s in samples:
		var sprite := AnimatedSprite3D.new()
		sprite.sprite_frames = frames
		sprite.animation = s[0]
		sprite.frame = s[1]
		sprite.pixel_size = 0.016
		# 与 player_visual._sync_offset 一致
		var tex: AtlasTexture = frames.get_frame_texture(s[0], 0)
		sprite.offset = Vector2(0, tex.region.size.y / 2.0 - 16.0)
		var vp := SubViewport.new()
		vp.size = Vector2i(int(tex.region.size.x * 1.5), int(tex.region.size.y * 2.0))
		vp.transparent_bg = true
		var cam := Camera3D.new()
		cam.current = true
		cam.position = Vector3(0, 3.0, 6.0)
		cam.look_at(Vector3.ZERO)
		vp.add_child(cam)
		vp.add_child(sprite)
		root.add_child(vp)
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img != null:
			img.save_png("res://.tmp_preview/compare_attack/render_%s.png" % s[2])
			print("已渲染 ", s[2], " ", img.get_size())
		else:
			print(s[2], " 渲染失败（headless 无渲染驱动）")
		vp.queue_free()
	quit(0)
