extends SceneTree
## 新手流程集成测试：签约 → 船到港 → 向导对话 → 试炼场教学 → 发装备
## → 回港接任务 → 传送阵开始废品终点站试炼。
var failures := 0
var gs: Node
var scene: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func mount() -> void:
	if is_instance_valid(scene):
		scene.free()
	scene = load("res://scenes/main/campaign.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

func run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	gs.save_path = "user://onboarding_flow_validation.cfg"
	gs.reset_progress()
	gs.complete_contract("新手验收")
	gs.begin_onboarding()
	check(gs.campaign.hub and gs.campaign.flow == "ship", "签约后进入港口引导阶段")
	await mount()
	check(scene.location == "hub" and scene.world.scene_file_path == scene.HARBOR, "船靠岸后过场进灰潮港")
	check(is_equal_approx(scene.player.position.z, 9.0), "从码头跳板边出生")
	var npc: Node = scene.world.get_node_or_null("GuideNpc")
	check(npc != null and npc.campaign_action.is_valid(), "港口向导 NPC 已接线")
	check(scene.world.get_node("DeparturePortal")._locked(), "未完成教学时传送阵锁定")
	check(scene.hud.objective.text.contains("港口向导"), "引导目标指向向导")
	npc.campaign_action.call()
	check(gs.campaign.flow == "training", "对话后流程进入教学")
	scene.hud.hide_panel()
	scene.world.get_node("TrialPortal").enter()
	await create_timer(0.85).timeout
	scene = current_scene
	check(scene.location == "practice" and scene.hud.objective.text.contains("木桩"), "试炼场教学目标")
	check(gs.campaign.flow == "training" and scene.player.hit_target.is_connected(scene._on_training_hit), "教学命中统计已接线")
	var dummy: Node = null
	for n in get_nodes_in_group("targets"):
		dummy = n
	check(dummy != null, "练功木桩在场")
	for i in 3:
		scene._on_training_hit(dummy, 8.0)
	check(gs.campaign.flow == "training", "只命中木桩未完成")
	scene._was_dodging = false
	scene.player.dodging = true
	scene._process(0.016)
	check(gs.campaign.flow == "equipped" and gs.campaign.training_done, "教学完成进入发装备阶段")
	check(gs.item_count("worn_blade") == 1 and gs.item_count("leather_cap") == 1, "基础装备已发放")
	check(gs.campaign.equipment.body == "ragged_vest" and gs.campaign.equipment.boots == "worn_boots", "基础防具自动穿戴")
	check(gs.campaign.equipment.main_weapon == "worn_blade", "基础武器替换匕首")
	scene.hud.hide_panel()
	scene.return_from_practice()
	await create_timer(0.85).timeout
	scene = current_scene
	check(scene.location == "hub" and scene.hud.objective.text.contains("任务委托所"), "回港目标指向任务委托所")
	scene.world.get_node("QuestService").campaign_action.call()
	check(scene.hud.quest_panel.visible, "委托所 V 打开任务档案")
	check(scene.hud.quest_panel._action_button.visible, "待接任务时面板给出接取按钮")
	scene.hud.quest_panel._action_button.pressed.emit()
	check(gs.campaign.flow == "quested", "接取废品终点站任务")
	check(not scene.hud.quest_panel.visible, "接取后面板自动收起")
	check(not scene.world.get_node("DeparturePortal")._locked(), "接取任务后传送阵解锁")
	scene.world.get_node("DeparturePortal").enter()
	await create_timer(0.85).timeout
	scene = current_scene
	check(scene.location == "arena" and gs.campaign.stage == 0 and not gs.campaign.hub, "传送阵开始废品终点站试炼")
	check(scene.state == "prepare" and scene.hud.header.text.contains("废品"), "废品终点站准备态目标")
	gs.persistence_enabled = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	print("ONBOARDING_FLOW_FAILURES=", failures)
	quit(1 if failures else 0)
