extends SceneTree
## 探明 SpriteFrames 逐帧时长的 API 与播放语义。
## 1) 列出 SpriteFrames 里带 "frame"/"duration"/"speed" 的方法；
## 2) 造 3 帧动画：帧0 duration=3.0、其余默认 1.0，fps=15，播放 2 秒记录切帧时刻。
## 用法：godot --headless --path . --script res://tools/probe_frame_duration.gd

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var methods: Array[String] = []
	for m in ClassDB.class_get_method_list("SpriteFrames", true):
		var name := String(m["name"])
		if name.contains("frame") or name.contains("duration") or name.contains("speed"):
			methods.append(name)
	methods.sort()
	print("PROBE: SpriteFrames 相关方法: ", methods)

	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("t")
	sf.set_animation_speed("t", 15.0)
	for i in 3:
		var im := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		im.fill(Color(float(i) / 2.0, 0.0, 0.0))
		# 帧0 给 3.0 秒的时长，其余用默认
		sf.add_frame("t", ImageTexture.create_from_image(im), 3.0 if i == 0 else 1.0)
	var s := AnimatedSprite3D.new()
	s.sprite_frames = sf
	s.animation = &"t"
	root.add_child(s)
	s.play()
	var t0 := Time.get_ticks_msec()
	var last: int = s.frame
	var events: Array[String] = []
	while Time.get_ticks_msec() - t0 < 2000:
		await process_frame
		if s.frame != last:
			events.append("->%d@%dms" % [s.frame, Time.get_ticks_msec() - t0])
			last = s.frame
	print("PROBE: fps=15、帧0 duration=3.0、其余 1.0 | 切换时刻: ", events)
	quit(0)
