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
	var dirs := ["up", "up_right", "right", "down_right", "down", "down_left", "left", "up_left"]
	var move_axes := {
		"up": ["move_up"], "up_right": ["move_up", "move_right"], "right": ["move_right"],
		"down_right": ["move_down", "move_right"], "down": ["move_down"],
		"down_left": ["move_down", "move_left"], "left": ["move_left"],
		"up_left": ["move_up", "move_left"],
	}
	var mirrored := ["left", "up_left", "down_left"]
	for direction in dirs:
		var before: Vector3 = player.position
		for action in move_axes[direction]:
			Input.action_press(action)
		await create_timer(0.25).timeout
		check(visual.animation == "walk_" + direction, "Move input selects " + direction)
		check(player.position.distance_to(before) > 0.1, "Player actually moves " + direction)
		check(visual.flip_h == (direction in mirrored), "Walk mirror " + direction)
		var observed_frames := {}
		for _sample in 4:
			observed_frames[visual.frame] = true
			await create_timer(0.1).timeout
		check(observed_frames.size() > 1, "Walk animation advances frames " + direction)
		# 步频必须跟随实际移速（脚不打滑）：speed_scale = 移速 × CLIP_LEN / 步幅，并受上下限夹取
		var ground_speed := Vector2(player.velocity.x, player.velocity.z).length()
		var expected_scale: float = clampf(
			ground_speed * visual.CLIP_LEN / visual.WALK_STRIDE_PER_CYCLE,
			visual.WALK_SPEED_SCALE.x, visual.WALK_SPEED_SCALE.y)
		check(absf(visual.speed_scale - expected_scale) < 0.01,
			"Walk cycle syncs to ground speed " + direction)
		# 45° 斜向图集偏大，必须按补偿系数缩小，否则斜向移动时角色会突然变大
		var expect_scale: float = (
			float(visual.DIAGONAL_SCALE.get("walk", 1.0))
			if direction in visual.DIAGONAL_DIRS else 1.0)
		check(absf(visual.pixel_size - visual.BASE_PIXEL_SIZE * expect_scale) < 0.0001,
			"Walk pixel_size compensates diagonal " + direction)
		for action in move_axes[direction]:
			Input.action_release(action)
		await create_timer(0.05).timeout
		check(visual.animation == "idle_" + direction, "Stopping keeps facing " + direction)
		_buffer_attack_toward(player, direction)
		await physics_frame
		await process_frame
		check(visual.animation == "attack_" + direction, "Attack selects " + direction)
		check(visual.flip_h == (direction in mirrored), "Attack mirror " + direction)
		check(player.attack_cd > 0.0, "Attack gameplay still triggers")
		if DisplayServer.get_name() != "headless" and direction in ["up", "down"]:
			await create_timer(0.12).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(
				"res://art/meowa/black_swordsman_fourdir/qa/godot_attack_%s.png" % direction
			)
		await create_timer(0.5).timeout
		check(visual.animation == "idle_" + direction, "Attack returns to idle " + direction)
	# === 剃：蓄力下蹲 → 瞬间爆发 → 落地骤停 ===
	# 按键绑定：剃必须挂在左 Shift 上
	var dodge_events := InputMap.action_get_events("dodge")
	check(dodge_events.size() == 1 and (dodge_events[0] as InputEventKey).physical_keycode == KEY_SHIFT,
		"Dash is bound to Left Shift")
	player.position = Vector3.ZERO
	Input.action_press("move_right")
	await create_timer(0.1).timeout
	Input.action_press("dodge")
	await create_timer(0.05).timeout
	check(player.dodging, "Dash triggers")
	check(visual.animation == "dodge_right", "Dash follows movement direction")
	check(not visual.flip_h, "Right dash uses the unmirrored clip")
	check(absf(visual.speed_scale - visual.CLIP_LEN / player.dodge_duration) < 0.05, "Dash clip spans dash duration")
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
	# 左向剃走镜像 clip
	Input.action_press("move_left")
	await create_timer(0.1).timeout
	Input.action_press("dodge")
	await create_timer(0.05).timeout
	check(visual.animation == "dodge_left", "Left dash selects left clip")
	check(visual.flip_h, "Left dash uses the mirrored clip")
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
