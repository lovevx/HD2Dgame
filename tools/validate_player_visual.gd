extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var scene = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	for enemy in get_nodes_in_group("enemies"):
		enemy.queue_free()
	await process_frame
	var player = scene.get_node("player")
	# main.gd 试炼开场面板会禁用玩家物理；本验证只测视觉层，直接启用物理绕过开场门。
	player.set_physics_process(true)
	var visual = player.get_node("pivot/CharacterSprite")
	# 对齐契约：帧尺寸一致；offset 由帧区域高度推出（224x192→80）。
	# 帧数：2026-09-21 起全部动作都是最新版 sheet 按块切出的 12 帧剪辑（统一 224×192 格）。
	for anim in visual.sprite_frames.get_animation_names():
		var count: int = visual.sprite_frames.get_frame_count(anim)
		var want: int = 12
		check(count == want, "Clip has %d frames (%d actually): %s" % [want, count, anim])
		var sizes := {}
		for i in count:
			var tex = visual.sprite_frames.get_frame_texture(anim, i)
			check(tex is AtlasTexture, "Frame is an AtlasTexture: " + anim)
			if tex is AtlasTexture:
				sizes[str(tex.region.size)] = true
		check(sizes.size() == 1, "All frames of a clip share one cell size: " + anim)
	var dirs := ["up", "up_right", "right", "down_right", "down", "down_left", "left", "up_left"]
	var move_axes := {
		"up": ["move_up"], "up_right": ["move_up", "move_right"], "right": ["move_right"],
		"down_right": ["move_down", "move_right"], "down": ["move_down"],
		"down_left": ["move_down", "move_left"], "left": ["move_left"],
		"up_left": ["move_up", "move_left"],
	}
	# 新版图集 8 个朝向都是真实绘制 → MIRRORED_DIRS 必须为空、任何朝向都不镜像
	check(visual.MIRRORED_DIRS.is_empty(), "No direction is mirrored (8 real drawings)")
	for direction in dirs:
		var before: Vector3 = player.position
		for action in move_axes[direction]:
			Input.action_press(action)
		await create_timer(0.25).timeout
		check(visual.animation == "run_" + direction, "Move input selects " + direction)
		check(player.position.distance_to(before) > 0.1, "Player actually moves " + direction)
		check(not visual.flip_h, "Run never mirrors " + direction)
		var observed_frames := {}
		for _sample in 4:
			observed_frames[visual.frame] = true
			await create_timer(0.1).timeout
		check(observed_frames.size() > 1, "Run animation advances frames " + direction)
		# 步频必须跟随实际移速（脚不打滑）：speed_scale = 移速 × 剪辑时长 / 步幅 × 步频衰减，并受上下限夹取。
		# 常驻移动模式即跑步：移动一律用 run 剪辑与 RUN_STRIDE_PER_CYCLE。
		var stride: float = visual.RUN_STRIDE_PER_CYCLE
		var clip_seconds: float = float(visual.sprite_frames.get_frame_count(visual.animation)) \
			/ visual.sprite_frames.get_animation_speed(visual.animation)
		var ground_speed := Vector2(player.velocity.x, player.velocity.z).length()
		var expected_scale: float = clampf(
			ground_speed * clip_seconds / stride * visual.RUN_CADENCE_FACTOR,
			visual.WALK_SPEED_SCALE.x, visual.WALK_SPEED_SCALE.y)
		check(absf(visual.speed_scale - expected_scale) < 0.01,
			"Run cycle syncs to ground speed " + direction)
		# 斜向不再做尺寸补偿（打包脚本已把本体高统一到 104px）→ pixel_size 恒为基准值
		var expect_scale: float = (
			float(visual.DIAGONAL_SCALE.get("run", 1.0))
			if direction in visual.DIAGONAL_DIRS else 1.0)
		check(absf(visual.pixel_size - visual.BASE_PIXEL_SIZE * expect_scale) < 0.0001,
			"Run pixel_size is the base value " + direction)
		check(_offset_matches_cell(visual), "Offset tracks cell height " + direction)
		for action in move_axes[direction]:
			Input.action_release(action)
		await create_timer(0.05).timeout
		check(visual.animation == "idle_" + direction, "Stopping keeps facing " + direction)
		_buffer_attack_toward(player, direction)
		await physics_frame
		await process_frame
		check(visual.animation == "attack_" + direction, "Attack selects " + direction)
		check(not visual.flip_h, "Attack never mirrors " + direction)
		# 攻击图集已归一化到本体 104px（tools/extract_latest_12.py）→ pixel_size 恒为基准值
		check(absf(visual.pixel_size - visual.BASE_PIXEL_SIZE) < 0.0001,
			"Attack pixel_size stays at the base value " + direction)
		check(player.attack_cd > 0.0, "Attack gameplay still triggers")
		if DisplayServer.get_name() != "headless" and direction in ["up", "down"]:
			await create_timer(0.12).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"res://art/meowa/black_swordsman_fourdir/qa/godot_attack_%s.png" % direction
			)
		# 攻击动画被压缩到整个冷却内播放（speed_scale = CLIP_LEN / attack_cd），
		# 等待时长必须跟随实际冷却——写死会在冷却调整后假摔（0.42→0.6 踩过）。
		await create_timer(player.attack_cd + 0.15).timeout
		check(visual.animation == "idle_" + direction, "Attack returns to idle " + direction)
	# === 跑步：常驻移动模式（2026-09-21 起移动一律跑步，不再需要 Shift） ===
	player.position = Vector3.ZERO
	player.facing = Vector3.RIGHT
	Input.action_press("move_right")
	await create_timer(0.3).timeout
	check(player.running, "Moving sets the running state")
	check(visual.animation == "run_right", "Movement uses the run clip")
	check(player.position.distance_to(Vector3.ZERO) > 0.15, "Run actually moves")
	check(Vector2(player.velocity.x, player.velocity.z).length() > player.move_speed * 0.9,
		"Run moves at the run speed")
	var run_clip_seconds: float = float(visual.sprite_frames.get_frame_count(visual.animation)) \
		/ visual.sprite_frames.get_animation_speed(visual.animation)
	var run_scale: float = clampf(
		Vector2(player.velocity.x, player.velocity.z).length() * run_clip_seconds / visual.RUN_STRIDE_PER_CYCLE
			* visual.RUN_CADENCE_FACTOR,
		visual.WALK_SPEED_SCALE.x, visual.WALK_SPEED_SCALE.y)
	check(absf(visual.speed_scale - run_scale) < 0.01, "Run cycle syncs to ground speed")
	Input.action_release("move_right")
	await create_timer(0.05).timeout
	# === 剃：蓄力下蹲 → 瞬间爆发 → 落地骤停 ===
	# 按键绑定：剃必须挂在空格上
	var dodge_events := InputMap.action_get_events("dodge")
	check(dodge_events.size() == 1 and (dodge_events[0] as InputEventKey).physical_keycode == KEY_SPACE,
		"Dash is bound to Space")
	player.position = Vector3.ZERO
	Input.action_press("move_right")
	await create_timer(0.1).timeout
	Input.action_press("dodge")
	await create_timer(0.05).timeout
	check(player.dodging, "Dash triggers")
	check(visual.animation == "dodge_right", "Dash follows movement direction")
	check(not visual.flip_h, "Right dash uses the unmirrored clip")
	# 新契约（2026-09-22）：动画压到「闪避时长 − DODGE_SETTLE」内播完，提前收尾停帧，
	# 避免动画与闪避结束边界竞态重播（旧契约"全程铺满时长"正是"最后一跳"的根因）。
	check(absf(visual.speed_scale - visual._clip_seconds(visual.animation) / (player.dodge_duration - visual.DODGE_SETTLE)) < 0.05,
		"Dash clip settles before dash ends")
	# 蓄力下蹲：踩地借力，人还留在原地，但按下的瞬间已获得无敌帧
	check(player.velocity.length() < 0.5, "Windup keeps the player planted")
	check(player.invulnerable, "Windup grants invulnerability")
	# 特效挂载：尘土、气流与三段音效
	var dash_fx = player.get_node_or_null("DashFX")
	check(dash_fx != null, "DashFX node is attached to the player")
	check(get_nodes_in_group("dash_particles").size() == 3, "Three dust emitters are attached")
	check(dash_fx.get_node("StompDust").emitting, "Stomp dust fires during the windup")
	var audio_count := 0
	for child in dash_fx.get_children():
		if child is AudioStreamPlayer and child.stream != null:
			audio_count += 1
	check(audio_count == 3, "Three dash sounds are wired")
	var dash_from: Vector3 = player.position
	Input.action_release("move_right")
	# 爆发：蓄力结束后一步到位满速
	await create_timer(player.DODGE_WINDUP).timeout
	check(player.velocity.length() > player.dodge_speed * 0.9, "Burst snaps to full speed")
	# 残影：爆发段在旧位置留下半透明灰色分身
	var afterimages := get_nodes_in_group("dash_afterimages")
	check(afterimages.size() > 0, "Burst leaves afterimages")
	if afterimages.size() > 0:
		var ghost = afterimages[0]
		var ghost_material: ShaderMaterial = ghost.material_override
		check(ghost_material != null, "Afterimage uses a silhouette shader")
		if ghost_material != null:
			var tint: Color = ghost_material.get_shader_parameter("ghost_tint")
			check(tint.a > 0.0 and tint.a < 1.0, "Afterimage is semi-transparent")
		check(Vector2(ghost.global_position.x, ghost.global_position.z).distance_to(
			Vector2(dash_from.x, dash_from.z)) < 1.5, "Afterimage stays at the old position")
	check(dash_fx.get_node("DashTrail").emitting, "Air trail runs during the burst")
	# 位移总量：单次短距离爆发
	var guard := 0
	while player.dodging and guard < 300:
		guard += 1
		await physics_frame
	var dash_dist := Vector2(player.position.x - dash_from.x, player.position.z - dash_from.z).length()
	check(dash_dist > 5.0 and dash_dist < 8.5, "Dash covers one short burst (%.1f m)" % dash_dist)
	print("DASH_DISTANCE_M: %.2f" % dash_dist)
	check(not visual.animation.begins_with("dodge_"), "Dash returns to locomotion")
	check(not dash_fx.get_node("DashTrail").emitting, "Air trail stops when the dash ends")
	# 冷却：冷却期内再次按下不触发
	Input.action_press("dodge")
	await create_timer(0.05).timeout
	check(not player.dodging, "Cooldown blocks an immediate second dash")
	Input.action_release("dodge")
	player.dodge_cd = 0.0  # 跳过冷却，继续验证左侧镜像
	# 左向剃用自己的图集（真实绘制），不再镜像
	Input.action_press("move_left")
	await create_timer(0.1).timeout
	Input.action_press("dodge")
	await create_timer(0.05).timeout
	check(visual.animation == "dodge_left", "Left dash selects left clip")
	check(not visual.flip_h, "Left dash uses its own drawing, not a mirror")
	check(visual.sprite_frames.get_frame_texture("dodge_left", 3)
		!= visual.sprite_frames.get_frame_texture("dodge_right", 3), "Left dash has its own atlas")
	Input.action_release("move_left")
	Input.action_release("dodge")
	# 等最后一个残影渐隐完（末尾残影在冲刺末段生成，需再等一个 AFTERIMAGE_LIFE）
	await create_timer(1.0).timeout
	check(get_nodes_in_group("dash_afterimages").is_empty(), "Afterimages free themselves")
	# 上下有独立素材：不镜像，且图集与侧向不同
	player.dodge_cd = 0.0
	Input.action_press("move_up")
	await create_timer(0.1).timeout
	Input.action_press("dodge")
	await create_timer(0.05).timeout
	check(visual.animation == "dodge_up", "Up dash selects the up clip")
	check(not visual.flip_h, "Up dash is not mirrored")
	check(visual.sprite_frames.get_frame_texture("dodge_up", 3)
		!= visual.sprite_frames.get_frame_texture("dodge_left", 3), "Up dash uses its own atlas")
	Input.action_release("move_up")
	Input.action_release("dodge")
	await create_timer(0.8).timeout
	# A05：拼刀替换右键按住格挡后，guard 停帧分支已删除，动画应始终回到移动/待机
	check(not visual.animation.begins_with("guard_"), "No guard clip after A05 removed hold-block")
	# === 闪避收尾不重播（2026-09-22 修复回归） ===
	# 整段闪避逐物理帧采样：动画应从 0 单调推进到末帧，之后冻结在末帧，
	# 绝不闪回起手帧（旧版边界竞态会让播完的动画重启，表现为"最后一跳"）。
	player.dodge_cd = 0.0
	player.facing = Vector3.RIGHT
	Input.action_press("dodge")
	await create_timer(0.05).timeout  # 与前段成功触发路径同口径：等 dodge 消费并置位
	Input.action_release("dodge")
	var dash_seq: Array[int] = []
	var dash_guard := 0
	while player.dodging and dash_guard < 120:
		dash_guard += 1
		dash_seq.append(visual.frame)
		await physics_frame
	check(dash_seq.size() > 0, "Dash sequence sampled")
	var dash_last: int = visual.sprite_frames.get_frame_count("dodge_right") - 1
	check(dash_seq.has(dash_last), "Dash animation reaches its last frame")
	var dash_fell_back := false
	for i in range(1, dash_seq.size()):
		if dash_seq[i] < dash_seq[i - 1]:
			dash_fell_back = true
			break
	check(not dash_fell_back, "Dash frames never fall back (no replay of frame 0)")
	player.reset()
	check(visual.attack_time_left == 0.0, "Respawn clears visual attack lock")
	if DisplayServer.get_name() != "headless":
		player.position = Vector3.ZERO
		player.facing = Vector3(0, 0, 1)
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://art/meowa/black_swordsman_fourdir/qa/godot_player.png")
	print("PLAYER_VISUAL_CHECKS: ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

## 填充攻击方向缓冲以驱动攻击。headless 下 64×64 虚拟窗口与 1920×1080 内容缩放不一致，
## 鼠标事件坐标会被错误放大导致瞄准射线失效，故跳过鼠标射线，直接走缓冲→物理帧→攻击→信号链路。
func _buffer_attack_toward(player: Node, direction: String) -> void:
	var dir: Vector3 = {
		"up": Vector3(0, 0, -1), "up_right": Vector3(1, 0, -1).normalized(),
		"right": Vector3(1, 0, 0), "down_right": Vector3(1, 0, 1).normalized(),
		"down": Vector3(0, 0, 1), "down_left": Vector3(-1, 0, 1).normalized(),
		"left": Vector3(-1, 0, 0), "up_left": Vector3(-1, 0, -1).normalized(),
	}[direction]
	player.buffered_direction = dir
	player.buffer_time = 0.15

## 对齐契约：offset.y == 当前帧区域高/2 − GROUND_SLACK（224×192 → 80）。
func _offset_matches_cell(visual: AnimatedSprite3D) -> bool:
	var tex = visual.sprite_frames.get_frame_texture(visual.animation, 0)
	if not (tex is AtlasTexture):
		return false
	var h: float = (tex as AtlasTexture).region.size.y
	return absf(visual.offset.y - (h / 2.0 - float(visual.GROUND_SLACK))) < 0.001
