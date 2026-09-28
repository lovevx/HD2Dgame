extends SceneTree
## 战斗技能与法力经济的隔离检查，不碰玩家正式存档。
const Skills := preload("res://data/combat_skills.gd")
const Bomb := preload("res://scripts/combat/alchemy_bomb.gd")
var failures := 0
var enemy_scene: PackedScene
var enemy_kinds: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func add_enemy(parent: Node, at: Vector3, kind: int) -> Node:
	var enemy := enemy_scene.instantiate()
	enemy.kind = kind
	enemy.position = at
	parent.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy

func run() -> void:
	await process_frame
	var enemy_script := load("res://scripts/combat/enemy.gd") as GDScript
	enemy_scene = load("res://scripts/combat/enemy.tscn") as PackedScene
	if enemy_script == null or enemy_scene == null:
		push_error("Cannot load enemy resources after autoload initialization")
		quit(1)
		return
	enemy_kinds = enemy_script.get_script_constant_map().get("Kind", {})
	var gs := root.get_node("GameState")
	gs.save_path = "user://combat_skills_validation.cfg"
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
	check(InputMap.has_action("hunter_toggle") and InputMap.has_action("aoge") and InputMap.has_action("huanduan"), "Q/E/F 技能键已映射")
	check(gs.Equip.kill_dur(1) == 1 and gs.Equip.kill_dur(3) == 3 and gs.Equip.kill_dur(8) == 8, "击杀耐久档位 1/3/8")
	var boss_script: GDScript = load("res://scripts/combat/boss_colpo.gd")
	var boss_values: Dictionary = boss_script.get_script_constant_map()
	var boss_sample: Node = boss_script.new()
	check(Bomb.EXPLOSION_DAMAGE * 3.0 <= float(boss_sample.get("max_hp")) * (1.0 - float(boss_values["P2_AT"])), "三枚陷阱不会被巨虎 P1 锁血吞掉伤害")
	check(float(boss_values["ATTACKS"]["ambush"]["windup"]) >= 0.3, "巨虎诈死偷袭有可反应的前摇")
	boss_sample.free()

	var mp_before: float = player.mp
	player._toggle_shield()
	check(player.shield_hp == Skills.shield_capacity(gs.effective_attributes().int) and player.mp == mp_before - Skills.SHIELD_MP_COST, "傲歌扣蓝并生成有上限护盾")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/combat-aoge.png")
	var hp_before: float = player.hp
	player.take_damage(10.0)
	check(player.hp == hp_before and player.shield_hp > 0.0, "傲歌优先吸收伤害")
	player.take_damage(100.0)
	check(player.shield_hp == 0.0 and not player.shield_visual.visible and player.hp < hp_before, "护盾破碎后溢出扣血")
	player.reset()
	player._toggle_shield()
	player._physics_process(Skills.SHIELD_DURATION + 0.01)
	check(player.shield_hp == 0.0, "傲歌超时自动消失")
	player.reset()

	var energy := add_enemy(scene, Vector3(0, 0, -2.0), enemy_kinds.WOLF)
	var no_energy := add_enemy(scene, Vector3(2.0, 0, 0), enemy_kinds.GOLEM)
	energy.physical_reduction = 0.5
	no_energy.physical_reduction = 0.5
	player.facing = Vector3(0, 0, -1)
	player._toggle_hunter()
	check(player.hunter_active, "猎魔可开启")
	player._hurt_in_cone(3.0, 10.0)
	check(is_equal_approx(energy.hp_, energy.max_hp - 5.0 - energy.max_hp * Skills.HUNTER_TRUE_RATIO), "猎魔真伤按目标最大生命 2% 跳过物理减免")
	player.facing = Vector3(1, 0, 0)
	player._hurt_in_cone(3.0, 10.0)
	check(is_equal_approx(no_energy.hp_, no_energy.max_hp - 5.0), "无能量敌人只受减免后的物理伤害")
	player.mp = player.max_mp * 0.01
	player._physics_process(0.1)
	check(not player.hunter_active, "法力低于 1% 强制关闭猎魔")
	energy.queue_free()
	no_energy.queue_free()
	await process_frame
	player.reset()
	var left := add_enemy(scene, Vector3(-2, 0, 0), enemy_kinds.WOLF)
	var right := add_enemy(scene, Vector3(2, 0, 0), enemy_kinds.BOAR)
	var far := add_enemy(scene, Vector3(7, 0, 0), enemy_kinds.WOLF)
	mp_before = player.mp
	player._start_ring()
	check(player.mp == mp_before - Skills.RING_MP_COST and player.ring_cd > 0, "环断扣蓝并进入冷却")
	player._physics_process(Skills.RING_WINDUP + 0.02)
	check(left.hp_ < left.max_hp and right.hp_ < right.max_hp and far.hp_ == far.max_hp, "环断仅命中范围内的复数目标")
	if DisplayServer.get_name() != "headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/combat-huanduan.png")
	var last_mp: float = player.mp
	player._start_ring()
	check(player.mp == last_mp, "环断冷却内不能重复释放")

	scene.free()
	gs.campaign.stage = 0
	gs.campaign.mp_ratio = 0.35
	scene = load("res://scenes/main/campaign.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	# await 期间会有一帧被动回蓝（0.2%/秒），断言留出余量，只校验比例本身
	var expected_mp: float = scene.player.max_mp * 0.35
	check(absf(scene.player.mp - expected_mp) <= 0.05, "进关按存档比例恢复剩余法力")
	scene.player.mp = scene.player.max_mp * 0.2
	scene._store_supplies()
	check(is_equal_approx(gs.campaign.mp_ratio, 0.2), "检查点保存剩余法力")
	print("COMBAT_SKILLS_FAILURES=", failures)
	quit(1 if failures else 0)
