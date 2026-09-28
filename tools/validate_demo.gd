extends SceneTree
## 自由练习场冒烟：开场面板 → 打木桩 → 单次伤害结算 → 倒下重开 → 不动正式资源。
## 运行：godot --headless --path . --script res://tools/validate_demo.gd
const TestEnv := preload("res://tools/test_env.gd")
var failures: Array[String] = []
func check(ok: bool, detail: String) -> void:
	if not ok:
		failures.append(detail)
		push_error(detail)
func _initialize() -> void:
	call_deferred("run_checks")
func run_checks() -> void:
	# 隔离存档 + 固定初始状态。末尾那条「练习不动正式资源」要拿前后值来比，
	# 所以先把全局状态换成固定的空档 —— 否则本机存档里的乐园币就成了断言的一部分。
	var gs: Node = root.get_node("GameState")
	TestEnv.isolate(gs, "demo")
	var coins_before: int = int(gs.coins)
	var scene = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	check(scene.practice == false, "starts at instruction panel")
	scene.start_practice()
	scene.set_process(false)
	var player = scene.player
	player.set_physics_process(false)
	var dummies = get_nodes_in_group("targets")
	check(dummies.size() == 1, "practice ground has exactly one dummy")
	var dummy = dummies[0]
	# 场上另有一只巡逻野狼，用于练习移动目标追击。
	# 它按设计进 enemies 组（enemy.gd 只把 DUMMY 放进 targets），所以旧断言
	# 「enemies 组为空 = 没有波次」在野狼上线那刻就成了假红 —— 改成钉住它的设计约束：
	# 只有一只、且永不主动攻击。
	var foes = get_nodes_in_group("enemies")
	check(foes.size() == 1, "practice ground has exactly one encounter wolf, got %d" % foes.size())
	if foes.size() == 1:
		check(bool(foes[0].get("patrol_only")), "encounter wolf never attacks (patrol_only)")
		check(not foes[0].is_in_group("targets"), "encounter wolf is not a damage dummy")
	dummy.position = Vector3(0, 0, -2)
	player.facing = Vector3.FORWARD
	player._start_attack()
	check(dummy.hp_ == dummy.max_hp, "no damage before active frame")
	player._physics_process(0.13)
	var after_hit: float = dummy.hp_
	check(after_hit < dummy.max_hp, "active frame damages dummy")
	player._physics_process(0.05)
	check(dummy.hp_ == after_hit, "one damage application per swing")
	player._physics_process(0.65)
	player._start_attack()
	check(player.combo_stage == 0, "single attack repeats after cooldown (combo removed)")
	# 打不坏：连续重击后仍存活，血量保底 1
	for i in 5:
		dummy.take_damage(999.0)
	check(dummy.is_alive() and dummy.hp_ > 1.0, "dummy survives heavy hits")
	dummy.take_damage(999999.0)
	check(dummy.hp_ == 1.0 and dummy.is_alive(), "dummy hp clamps at 1 instead of dying")
	player.invulnerable = true
	var hp_before: float = player.hp
	player.take_damage(30)
	check(player.hp == hp_before, "invulnerability prevents damage")
	player.reset()
	check(not player.dodging and player.attack_cd == 0 and player.hp == player.max_hp and player.mp == player.max_mp, "reset clears action state")
	# 倒下 → 重开练习：玩家重生、木桩还在
	scene.start_practice()
	player.take_damage(999)
	check(scene.practice == false and not player.alive, "death reaches restart panel")
	check(scene.hud.panel_title.text == "倒下了", "restart panel shows fall message")
	scene.start_practice()
	check(scene.practice and player.alive and get_nodes_in_group("targets").size() == 1, "restart clears fallen state and keeps dummy")
	check(gs.coins == coins_before, "practice does not change official currency（前 %d / 后 %d）" % [coins_before, gs.coins])
	if "--capture" in OS.get_cmdline_user_args():
		scene.set_process(true)
		player.set_physics_process(false)
		for enemy in get_nodes_in_group("targets"):
			enemy.set_physics_process(false)
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/demo_preview.png")
	TestEnv.cleanup(gs)
	print("P0_SMOKE: ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
