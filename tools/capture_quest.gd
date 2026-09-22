extends SceneTree
## 任务面板出图：序章档（船到港）与中局档（1.4 清场待离场）两张，落到 docs/ui/。
## 带渲染窗口跑（不要 --headless）：
##   godot --path . --script res://tools/capture_quest.gd

func _initialize() -> void:
	call_deferred("run")

func _shot(name: String) -> void:
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/ui/%s.png" % name)
	print("UI_CAP ", name)

func run() -> void:
	await process_frame
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("res://docs/ui"):
		dir.make_dir_recursive("res://docs/ui")
	var gs: Node = root.get_node("GameState")
	gs.save_path = "user://quest_capture.cfg"   # 出图不碰正式存档
	gs.reset_progress()
	gs.complete_contract("苏晓")
	gs.begin_onboarding()
	var scene = load("res://scenes/main/campaign.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(1.4).timeout
	var hud = scene.hud
	hud.open_quest_log()
	await _shot("quest_panel_prologue")

	# 中局档：1.2~1.4 已走过，1.4 清场待离场（列表上能看到已完成 / 待交接 / 未解锁三态）
	gs.campaign.flow = "trial"
	gs.campaign.stage = 2
	gs.campaign.cleared = true
	gs.campaign.kills = ["0_0", "1_0", "2_0"]
	gs.campaign.bag = {"letter": 1, "dragon": 1, "potion": 2}
	gs.campaign.equipment = {"main_weapon": "dragon"}
	gs.campaign.opened_chests = ["arena_0"]
	gs.campaign.source = 5.4
	gs.campaign.world_mana = 26
	hud.close_quest_log()
	hud.quest_panel._selected_id = ""
	hud.open_quest_log()
	await _shot("quest_panel_run")

	# 灰潮港委托所档：新手教学做完、待接任务 —— 面板底栏出现「接取任务」按钮
	gs.campaign.flow = "equipped"
	gs.campaign.training_done = true
	gs.campaign.kills = []
	gs.campaign.bag = {"knife": 1, "potion": 2}
	gs.campaign.equipment = {"main_weapon": "knife"}
	hud.quest_panel._selected_id = ""   # 首次走到委托所：按默认选中（当前序章那步）
	scene.world.get_node("QuestService").campaign_action.call()
	await _shot("quest_panel_accept")
	quit(0)
