extends SceneTree
## 即时战斗的起手、有效帧、后摇闪避和命中反馈。
const TestEnv := preload("res://tools/test_env.gd")
const Skills := preload("res://data/combat_skills.gd")
var failures := 0
var enemy_scene: PackedScene
var enemy_wolf_kind := -1

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
	var enemy_kinds: Dictionary = enemy_script.get_script_constant_map().get("Kind", {})
	enemy_wolf_kind = int(enemy_kinds.get("WOLF", -1))
	if enemy_wolf_kind < 0:
		push_error("Cannot find WOLF in enemy Kind enum")
		quit(1)
		return
	var gs := root.get_node("GameState")
	TestEnv.isolate(gs, "realtime_feel")
	var scene: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_practice()
	scene.set_process(false)
	var player: CharacterBody3D = scene.player
	player.set_physics_process(false)
	player.campaign_mode = true
	player.reset()
	player.facing = Vector3.FORWARD
	var visual: AnimatedSprite3D = player.get_node("pivot/CharacterSprite")
	var enemy := enemy_scene.instantiate()
	enemy.kind = enemy_wolf_kind
	enemy.position = Vector3(0, 0, -2)
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	var hp_before: float = enemy.hp_
	player._start_kick()
	check(enemy.hp_ == hp_before and visual.animation.begins_with("kick_"), "直踹起手先播动作，不提前命中")
	player._physics_process(Skills.KICK_HIT_TIME - 0.01)
	check(enemy.hp_ == hp_before and not player._try_dodge(), "有效帧前不可剃取消")
	player._physics_process(0.02)
	check(enemy.hp_ < hp_before and get_nodes_in_group("hit_feedback").size() > 0, "有效帧结算伤害并显示命中反馈")
	var hp_after: float = enemy.hp_
	check(player._try_dodge() and player.dodging and player.attack_cd == 0.0, "命中后可用剃取消直踹后摇")
	visual._process(0.016)
	check(visual.animation.begins_with("dodge_"), "取消后立刻切到剃动画")
	player._physics_process(0.05)
	check(enemy.hp_ == hp_after, "直踹每次只结算一次伤害")
	player.reset()
	player.facing = Vector3.FORWARD
	player._start_attack()
	check(player.current_attack_animation == "attack_horizontal" and visual.animation.begins_with("attack_horizontal_"),
		"第一下斩击播放横斩动画")
	player._physics_process(Skills.HORIZONTAL_ATTACK_HIT_TIME - 0.01)
	check(not player._try_dodge(), "横斩命中前不可剃取消")
	player._physics_process(0.02)
	check(player._try_dodge(), "横斩命中后可用剃取消后摇")
	player.dodging = false
	player.attack_cd = 0.0
	player._start_attack()
	check(player.current_attack_animation == "attack", "第二下普攻交替返回原竖斩")
	player._physics_process(Skills.COMBO_HIT_TIMES[0] + 0.01)
	check(player.attack_hit, "原竖斩仍按原有效帧结算")
	scene.free()
	TestEnv.cleanup(gs)
	print("REALTIME_FEEL_FAILURES=", failures)
	quit(1 if failures else 0)
