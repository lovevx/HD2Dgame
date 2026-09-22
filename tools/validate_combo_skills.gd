extends SceneTree
## 三段动作、刀芒路径与影刺前置的隔离集成检查。
const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
const Skills := preload("res://data/combat_skills.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func run() -> void:
	await process_frame
	var gs := root.get_node("GameState")
	gs.save_path = "user://combo_skills_validation.cfg"
	gs.reset_progress()
	var scene: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_practice()
	scene.set_process(false)
	var player: Node = scene.player
	player.set_physics_process(false)
	player.campaign_mode = true
	player.reset()
	var visual: AnimatedSprite3D = player.get_node("pivot/CharacterSprite")
	for direction in ["left", "right", "down", "up"]:
		check(visual.sprite_frames.has_animation("attack_" + direction) and visual.sprite_frames.has_animation("kick_" + direction), "斩与直踹四方向 %s" % direction)
		check(visual.sprite_frames.get_frame_count("attack_" + direction) == 12 and visual.sprite_frames.get_frame_count("kick_" + direction) == 12, "每个新动作十二帧 %s" % direction)
	check(visual.COMBO_CLIPS.size() == 1 and visual.COMBO_CLIPS[0] == "attack", "连段已取消：动作表只剩斜劈")
	check(InputMap.has_action("sword_wave") and InputMap.has_action("shadow_stab"), "R/T 按键已映射")

	var enemy := EnemyScene.instantiate()
	enemy.kind = EnemyScript.Kind.WOLF
	enemy.position = Vector3(0, 0, -2.0)
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	player.facing = Vector3.FORWARD
	var mp_before: float = player.mp
	player._start_shadow()
	check(player.mp == mp_before and player.shadow_cd == 0.0, "未刺中时 T 不耗蓝且不进入冷却")
	player._start_attack()
	check(player.combo_stage == 0 and visual.animation == &"attack_up", "单段攻击使用斜劈帧")
	player._physics_process(Skills.COMBO_HIT_TIMES[0] - 0.01)
	check(player.pierced_target == null, "有效帧前无影刺标记")
	player._physics_process(0.02)
	check(player.pierced_target == enemy and player.pierce_timer > 0.0, "斩击命中目标留下影刺标记")
	if DisplayServer.get_name() != "headless":
		visual.frame = 3
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/combo-stab.png")
	mp_before = player.mp
	var hp_before: float = enemy.hp_
	player._start_shadow()
	check(player.mp == mp_before - Skills.SHADOW_MP_COST and player.pierced_target == null, "T 仅消耗已刺入目标的标记")
	player._physics_process(Skills.SHADOW_WINDUP + 0.01)
	check(enemy.hp_ < hp_before and player.shadow_cd > 0.0, "影刺在目标身上爆发伤害")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/shadow-stab.png")
	mp_before = player.mp
	player._start_shadow()
	check(player.mp == mp_before, "同一前刺不能重复影刺")
	enemy.queue_free()
	await process_frame

	player.reset()
	player.facing = Vector3.FORWARD
	player._start_attack()
	player._physics_process(Skills.COMBO_HIT_TIMES[0] + 0.01)
	check(player.pierced_target == null, "斩击挥空不生成标记")
	player._physics_process(Skills.COMBO_COOLDOWNS[0])
	player._start_attack()
	check(player.combo_stage == 0 and visual.animation == &"attack_up", "冷却后再次攻击仍是单段斩击")
	if DisplayServer.get_name() != "headless":
		visual.frame = 3
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/combo-heavy.png")
		player.facing = Vector3.RIGHT
		visual._on_attacked(0)
		visual.frame = 3
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/combo-stab-side.png")
		player.facing = Vector3.BACK
		visual._on_attacked(0)
		visual.frame = 3
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/combo-heavy-down.png")
	player._physics_process(Skills.COMBO_COOLDOWNS[0] + 0.2)
	player._start_attack()
	check(player.combo_stage == 0, "连段取消后连续攻击不切换段位")
	var marked := EnemyScene.instantiate()
	marked.kind = EnemyScript.Kind.WOLF
	marked.position = Vector3(0, 0, -2.0)
	scene.add_child(marked)
	marked.set_physics_process(false)
	player.reset()
	player._mark_pierced(marked)
	player._physics_process(Skills.PIERCE_WINDOW + 0.01)
	check(player.pierced_target == null, "影刺标记超时清除")
	player._mark_pierced(marked)
	player.position = Vector3(10, 0, 0)
	mp_before = player.mp
	player._start_shadow()
	check(player.mp == mp_before and player.pierced_target == null, "目标超距时影刺空放不扣蓝")
	marked.queue_free()
	await process_frame

	player.reset()
	player.position = Vector3.ZERO
	var wave_enemy := EnemyScene.instantiate()
	wave_enemy.kind = EnemyScript.Kind.WOLF
	wave_enemy.max_hp = 100.0
	wave_enemy.position = Vector3(0, 0, -5.0)
	scene.add_child(wave_enemy)
	wave_enemy.set_physics_process(false)
	wave_enemy.physical_reduction = 0.5
	player._toggle_hunter()
	mp_before = player.mp
	player._start_wave(Vector3.FORWARD)
	check(player.mp == mp_before - Skills.WAVE_MP_COST and player.wave_cd > 0.0, "R 扣蓝并进入冷却")
	player._physics_process(Skills.WAVE_WINDUP + 0.01)
	check(get_nodes_in_group("sword_waves").size() == 1, "刀芒在挥刀有效帧释放飞行体")
	var wave_damage: float = get_nodes_in_group("sword_waves")[0].damage
	if DisplayServer.get_name() != "headless":
		await create_timer(0.08).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/sword-wave.png")
	await create_timer(0.6).timeout
	check(is_equal_approx(wave_enemy.hp_, wave_enemy.max_hp - wave_damage * 0.5), "刀芒命中且不附加猎魔真伤")
	var last_mp: float = player.mp
	player._start_wave(Vector3.FORWARD)
	check(player.mp == last_mp, "刀芒冷却内不能连续释放")

	player.reset()
	wave_enemy.hp_ = wave_enemy.max_hp
	var wall := StaticBody3D.new()
	wall.position = Vector3(0, 1, -3.0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	await physics_frame
	player._start_wave(Vector3.FORWARD)
	player._physics_process(Skills.WAVE_WINDUP + 0.01)
	await create_timer(0.6).timeout
	check(wave_enemy.hp_ == wave_enemy.max_hp, "刀芒被实体墙阻挡")
	print("COMBO_SKILLS_FAILURES=", failures)
	quit(1 if failures else 0)
