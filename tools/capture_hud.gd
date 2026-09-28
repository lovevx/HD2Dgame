extends SceneTree
## 战斗 HUD 出图：满状态 / 受伤低血 + 技能冷却 两张，落到 docs/ui/。
## 带渲染窗口跑（不要 --headless）：
##   godot --path . --script res://tools/capture_hud.gd
## 可选第一个用户参数作文件名前缀（对比改版前后）：... -- before

const TestEnv := preload("res://tools/test_env.gd")

func _initialize() -> void:
	call_deferred("run")

func _shot(name: String, wait := 0.6) -> void:
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/ui/%s.png" % name)
	print("UI_CAP ", name)

func run() -> void:
	await process_frame
	var prefix := "hud"
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		prefix = "hud_%s" % args[0]
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("res://docs/ui"):
		dir.make_dir_recursive("res://docs/ui")
	var gs: Node = root.get_node("GameState")
	TestEnv.isolate(gs, "hud_capture")
	gs.complete_contract("苏晓")
	gs.begin_onboarding()
	gs.campaign.flow = "trial"
	gs.campaign.stage = 1
	gs.campaign.bag = {"dragon": 1, "potion": 2, "flintlock": 1}
	gs.campaign.equipment = {"main_weapon": "dragon", "offhand": "flintlock"}
	var scene = load("res://scenes/main/campaign.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.6).timeout
	var hud = scene.hud
	hud.hide_story()
	hud.hide_panel()
	hud.close_dialogue(false)
	await _shot("%s_full" % prefix)

	var player = hud.player
	player.hp = player.max_hp * 0.22
	player.mp = player.max_mp * 0.3
	player.stamina = player.max_stamina * 0.15
	player.ring_cd = 3.2
	player.wave_cd = 1.4
	player.dodge_cd = 0.6
	player.hunter_active = true
	player.shield_hp = 24.0
	player.shield_timer = 3.0
	player.take_damage(1.0)
	gs.push_message("受到重击 · 生命告急")
	await _shot("%s_low" % prefix, 0.25)
	# 残影追上、冷却转好之后的稳态
	await _shot("%s_low_settled" % prefix, 1.4)
	TestEnv.cleanup(gs)
	quit(0)
