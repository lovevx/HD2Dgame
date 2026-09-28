extends SceneTree
## 即时斩击、刀芒与影刺的接线检查。
const Skills := preload("res://data/combat_skills.gd")
const TestEnv := preload("res://tools/test_env.gd")
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
	TestEnv.isolate(gs, "combo_skills")
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
	check(visual.COMBO_CLIPS.size() == 1 and visual.COMBO_CLIPS[0] == "attack", "即时斩击只有单段")
	var enemy := enemy_scene.instantiate()
	enemy.kind = enemy_kinds.WOLF
	enemy.position = Vector3(0, 0, -2)
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	player.facing = Vector3.FORWARD
	player._start_attack()
	check(player.current_attack_animation == "attack_horizontal", "首下斩击选择横斩视觉")
	player._physics_process(player.current_attack_hit_time + 0.01)
	check(enemy.hp_ < enemy.max_hp, "斩击命中仍正常结算")
	check(player.pierced_target == enemy and player.pierce_timer > 0.0, "斩击命中留下影缝标记")
	player.reset()
	player._mark_pierced(enemy)
	var mp_before: float = player.mp
	for action in ["sword_wave", "shadow_stab"]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = true
		player.set_physics_process(true)
		player._unhandled_input(event)
		if action == "sword_wave":
			player._physics_process(Skills.WAVE_WINDUP + 0.01)
		else:
			player._physics_process(Skills.SHADOW_WINDUP + 0.01)
		player.set_physics_process(false)
	check(is_equal_approx(player.mp, mp_before - Skills.WAVE_MP_COST - Skills.SHADOW_MP_COST), "R/T 输入触发技能并扣除对应法力")
	check(get_nodes_in_group("sword_waves").size() == 1, "R 输入释放刀芒飞行体")
	scene.free()
	TestEnv.cleanup(gs)
	print("COMBO_SKILLS_FAILURES=", failures)
	quit(1 if failures else 0)
