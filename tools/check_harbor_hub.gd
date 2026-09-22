extends SceneTree
## 灰潮港主城白盒验收：五个功能点、V 交互、门与传送（走进即传）。
## 运行：godot --headless --path . --script res://tools/check_harbor_hub.gd
const TestEnv := preload("res://tools/test_env.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	print("HUB_CHECK: %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures.append(label)

func run() -> void:
	# 商店/锻造/任务服务点都会 save_game()，不隔离就会写进玩家的真实存档。
	var gs: Node = root.get_node("GameState")
	TestEnv.isolate(gs, "harbor_hub")
	change_scene_to_file("res://scenes/world/harbor.tscn")
	await create_timer(1).timeout
	var scene = current_scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var hud = get_first_node_in_group("hud")
	check(get_nodes_in_group("harbor_services").size() == 5, "五个功能点")
	# 服务点（V 交互）：从主街可达、靠近提示、V 打开、Esc 关闭、离开收提示。
	# 传送门（走进即传，scene_portal.gd）不能把玩家真放进门里——会直接触发传送，单独在后面验证。
	for id in ["ShopService", "ForgeService", "QuestService"]:
		var service = scene.get_node(id)
		var start := Vector3(0, 0, service.position.z)
		player.position = start
		await create_timer(0.1).timeout
		check(not player.test_move(player.global_transform, service.position - start), id + " 从主街可达")
		player.position = service.position
		await create_timer(0.2).timeout
		check(hud.prompt.visible, id + " 靠近显示提示")
		if id.ends_with("Service"):
			var interact := InputEventAction.new()
			interact.action = "interact"
			interact.pressed = true
			Input.parse_input_event(interact)
			await process_frame
			await process_frame
			interact.pressed = false
			Input.parse_input_event(interact)
			# 轮回商店与港务委托所都走完整 UI（panel_handler / campaign.show_tasks 接线），
			# 其余服务仍是默认说明面板。
			if id == "ShopService":
				var shop_panel = get_first_node_in_group("shop_panel")
				check(shop_panel != null and shop_panel.visible, id + " V 打开轮回商店")
			elif id == "QuestService":
				var quest_panel = get_first_node_in_group("quest_panel")
				check(quest_panel != null and quest_panel.visible, id + " V 打开任务档案")
			else:
				check(service.opened and hud.overlay.visible, id + " V 打开面板")
			check(not player.is_physics_processing(), id + " 面板阻止移动")
			if id == "QuestService" and DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://docs/harbor_quest_panel.png")
			var esc := InputEventAction.new()
			esc.action = "open_menu"
			esc.pressed = true
			Input.parse_input_event(esc)
			await process_frame
			if id == "ShopService":
				var shop_panel_after = get_first_node_in_group("shop_panel")
				check(shop_panel_after != null and not shop_panel_after.visible and player.is_physics_processing(),
					id + " Esc 关闭并恢复移动")
			elif id == "QuestService":
				var quest_panel_after = get_first_node_in_group("quest_panel")
				check(quest_panel_after != null and not quest_panel_after.visible and player.is_physics_processing(),
					id + " Esc 关闭并恢复移动")
			else:
				check(not service.opened and not hud.overlay.visible and player.is_physics_processing(), id + " Esc 关闭并恢复移动")
			player.set_physics_process(false)
			player.position = Vector3.ZERO
			await create_timer(0.2).timeout
			check(not hud.prompt.visible, id + " 离开隐藏提示")
	# 传送门：走进即传（scene_portal.gd），不做提示断言，只验证目标场景存在；
	# 实际传送与返回主城在下方过场链路里验证。
	for id in ["DeparturePortal", "TrialPortal"]:
		var portal = scene.get_node(id)
		check(ResourceLoader.exists(portal.target_scene), id + " 目标场景存在")
	if DisplayServer.get_name() != "headless":
		for shot in [{"at": Vector3(-10, 0, 0.5), "name": "quest"}, {"at": Vector3(10, 0, -9), "name": "forge"}, {"at": Vector3(0, 0, -21), "name": "gate"}]:
			player.position = shot.at
			await create_timer(1).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/harbor_%s.png" % shot.name)
	# 实际切换目标与返回主城，验证过场链路。
	for id in ["DeparturePortal", "TrialPortal"]:
		var portal = current_scene.get_node(id)
		var target: String = portal.target_scene
		portal.enter()
		await create_timer(2).timeout
		check(current_scene.scene_file_path == target, id + " 实际传送成功")
		root.get_node("GameState").change_scene("res://scenes/world/harbor.tscn")
		await create_timer(2).timeout
		check(current_scene.scene_file_path == "res://scenes/world/harbor.tscn", "返回灰潮港口")
	TestEnv.cleanup(gs)
	print("HUB_RESULT: ", "PASS" if failures.is_empty() else failures)
	current_scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
