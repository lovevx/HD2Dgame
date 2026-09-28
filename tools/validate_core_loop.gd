extends SceneTree
## 隔离存档的真实场景集成测试：自动击败目标验证流程，不替代手动手感测试。
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

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tmp_preview/reuse-%s.png" % label)

## 面板子树里所有 Label / Button 文字拼起来（断言面板确实把内容渲染出来了）。
func _panel_text(node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label or child is Button:
			out += child.text + "\n"
		out += _panel_text(child)
	return out

func use_inventory(id: String) -> void:
	scene.hud._refresh_char_panel()
	for cell in scene.hud.bag_cells:
		if cell.get_meta("item_id", "") != id: continue
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		scene.hud._bag_cell_input(click, cell)
		check(not scene.hud.item_action.disabled, "原背包选中可操作物品 " + id)
		scene.hud.item_action.pressed.emit()
		return
	check(false, "原背包缺少物品 " + id)

func run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	gs.save_path = "user://core_loop_validation.cfg"
	gs.reset_progress()
	gs.complete_contract("验证猎杀者")
	check(gs.attributes == gs.Campaign.BASE_STATS, "Word 起始六维")
	check(not gs.advance_region() and not gs.settle_trial(), "未清场不能推进/结算")
	await mount()
	check(scene.world.scene_file_path == scene.ARENA and get_nodes_in_group("hud").size() == 1, "复用原练习场和唯一HUD")
	check(scene.hud.bag_cells.size() == 64 and scene.hud.equipment_slots.size() == 11, "复用64格背包与11槽人物面板")
	check(scene.player.max_mp == 60, "初始法力60，无未来职业技能")
	check(scene.hud.objective.text.contains("红色预警") and scene.hud.objective.text.contains("领取"), "1.2开场提示预警、生命与战利品交互")
	scene.player.hp = 40
	var drink := InputEventAction.new()
	drink.action = "potion"
	drink.pressed = true
	scene.player._unhandled_input(drink)
	scene._track_tutorial_actions()
	check(gs.campaign.tutorial_steps.get("potion", false), "有效使用药剂后记录教学完成")
	check(scene.player.potions == 1 and scene.player.healing_time > 0 and scene.player.hp == 40, "药剂先消耗且有饮用时间")
	scene.player._physics_process(1.3)
	check(scene.player.hp == 80, "首次药剂回复40%")
	scene.player._unhandled_input(drink)
	scene.player.take_damage(10)
	check(scene.player.healing_time == 0 and scene.player.potions == 0 and scene.player.hp == 70, "受击打断饮用且不返还")
	scene.start_encounter()
	var first: Node = scene.enemies[0]
	scene.player.global_position = first.global_position + Vector3(0, 0, 2)
	scene.player.facing = Vector3.FORWARD
	first.attack_cd = 10
	scene.player._hurt_in_cone(3, 12)
	check(first.hp_ == first.max_hp - 12, "玩家真实近战判定伤害")
	scene.player.potions = 0
	scene.player.take_damage(999)
	check(scene.state == "dead", "阵亡进入重试状态")
	await mount()
	check(scene.player.alive and scene.player.potions == 2 and gs.campaign.stage == 0, "失败回滚本区域消耗与生命")
	for stage in range(5):
		if stage > 0: await mount()
		if scene.sheet.visible: scene.close_sheet()
		if stage == 4:
			check(scene.location == "outer" and scene.world.scene_file_path == scene.OUTER, "猎虎先经过原外围地图")
			scene.world.get_node("ExitPortal").enter()
			check(not gs.is_transitioning(), "外围未清场不能跳过传送")
			await capture("outer")
			scene.start_encounter()
			for wave in range(3):
				scene.director._process(5.0)
				check(scene.director.remaining() > 0, "原波次调度生成第%d波" % (wave + 1))
				for enemy in scene.director.get_children():
					if enemy.has_method("take_damage"): enemy.take_damage(10000)
				scene.director._process(0.1)
			check(scene.state == "outer_cleared" and gs.campaign.colpo_outer_cleared and not gs.campaign.cleared, "外围独立检查点不冒充巨虎通关")
			check(is_equal_approx(float(gs.campaign.source), 5.7), "外围不重复发世界之源")
			scene.world.get_node("ExitPortal").enter()
			await create_timer(0.85).timeout
			scene = current_scene
			check(scene.location == "clearing", "原传送门实际进入决战空地")
			check(scene.world.scene_file_path == scene.CLEARING, "复用原决战地图与镜头")
		scene.start_encounter()
		if stage == 4:
			check(scene.state == "preparing" and scene.director.prep_left == 15, "原BOSS调度15秒准备")
			check(scene.player.bombs == gs.item_count("trap"), "准备不重复赠送陷阱")
			scene.show_sheet()
			check(not scene.director.is_processing(), "菜单暂停准备倒计时")
			scene.close_sheet()
			scene.director._process(16.0)
			check(scene.director.phase == "prep" and not is_instance_valid(scene.boss), "未用陷阱时巨虎不会提前出现")
			var prep_camera: Camera3D = root.get_camera_3d()
			var prep_rotation := prep_camera.rotation
			prep_camera.rotation.x = -PI / 2.0
			scene.player._throw_bomb()
			prep_camera.rotation = prep_rotation
			check(gs.campaign.tutorial_steps.get("trap", false), "预埋陷阱后记录核心练习完成")
			scene.player._toggle_shield()
			check(gs.campaign.tutorial_steps.get("shield", false), "开启傲歌护盾后记录核心练习完成")
			scene.player._toggle_hunter()
			scene._track_tutorial_actions()
			check(gs.campaign.tutorial_steps.get("hunter", false), "开启猎魔后记录核心练习完成")
			scene.director._process(0.1)
			check(is_instance_valid(scene.boss), "三项猎虎准备练习完成后引出巨虎")
			await capture("tiger")
		scene.show_sheet()
		check(not scene.player.is_physics_processing() and not scene.enemies[0].is_physics_processing(), "烙印暂停双方 stage%d" % stage)
		scene.close_sheet()
		if stage == 1:
			check(scene.hud.objective.text.contains("燧发枪"), "1.3提示装备并试射燧发枪")
			var camera: Camera3D = root.get_camera_3d()
			var saved_rotation := camera.rotation
			camera.rotation.x = -PI / 2.0 # 无头环境鼠标固定在视口边缘，让测试射线落地。
			var point: Vector3 = scene.player.mouse_ground_point()
			var direction: Vector3 = point - scene.player.global_position
			direction.y = 0
			scene.enemies[0].global_position = scene.player.global_position + direction.normalized() * 4
			scene.enemies[0].attack_cd = 10.0
			scene.enemies[0].set_physics_process(false)
			scene.enemies[0].force_update_transform()
			var old_hp: float = scene.enemies[0].hp_
			gs.campaign.equipment.offhand = "flintlock"  # 副手槽装备燧发枪（右键触发）
			scene.player._fire_flintlock()
			camera.rotation = saved_rotation
			# 枪械攻击区间 2-13 × 力量倍率，双 roll 伪随机：确认命中并扣弹、伤害落区间内
			check(scene.player.bullets == 5 and scene.enemies[0].hp_ < old_hp and scene.enemies[0].hp_ >= old_hp - 15, "副手燧发枪命中并消耗弹药")
			await process_frame
			check(gs.campaign.tutorial_steps.get("gun", false), "试射燧发枪后记录教学完成")
		if stage == 2:
			check(scene.hud.objective.text.contains("直踹") and scene.hud.objective.text.contains("影刺"), "1.4提示教官战练习直踹与影刺")
			scene.player.stamina = scene.player.max_stamina
			scene.player.kick_cd = 0.0
			scene.player.attack_cd = 0.0
			scene.player._start_kick()
			scene.player.global_position = scene.enemies[0].global_position + Vector3(0, 0, 2)
			scene.player._mark_pierced(scene.enemies[0])
			scene.player.shadow_cd = 0.0
			scene.player._start_shadow()
			await process_frame
			check(gs.campaign.tutorial_steps.get("kick", false) and gs.campaign.tutorial_steps.get("shadow", false), "直踹与影刺成功释放后记录教学完成")
		if stage == 3:
			check(scene.hud.objective.text.contains("刀芒") and scene.hud.objective.text.contains("环断"), "1.5提示双目标范围技能")
			scene.player.attack_cd = 0.0
			scene.player.wave_cd = 0.0
			scene.player._start_wave(Vector3.FORWARD)
			scene.player.attack_cd = 0.0
			scene.player.ring_cd = 0.0
			scene.player._start_ring()
			check(gs.campaign.tutorial_steps.get("wave", false) and gs.campaign.tutorial_steps.get("ring", false), "刀芒与环断释放后记录教学完成")
		if stage == 4:
			var tiger: Node = scene.boss
			var trap: Node = load("res://scripts/combat/alchemy_bomb.tscn").instantiate()
			scene.add_child(trap)
			trap.place_at(tiger.global_position)
			trap._on_body_entered(tiger)
			trap._process(0.4)
			var bomb_damage: float = trap.get_script().get_script_constant_map()["EXPLOSION_DAMAGE"]
			check(tiger.hp == tiger.max_hp - bomb_damage, "火药陷阱踩踏引爆伤害")
			tiger.take_damage(290)
			check(tiger.phase == 1, "巨虎65%狂暴")
			tiger.take_damage(320)
			for i in 3:
				scene.player.global_position = tiger.global_position + tiger.global_basis.z * 4
				tiger.take_damage(1, Vector3.ZERO, scene.player)
			check(tiger.tendon_broken, "后方三次命中破坏筋腱")
			tiger.p3_delay = 0.0
			tiger._physics_process(0.1)
			check(tiger.is_faking_death(), "巨虎25%诈死尚未胜利")
			check(scene.state == "combat" and not gs.campaign.cleared, "诈死不能领取奖励")
			check(tiger.confirm_evacuation_kill(), "诈死阶段确认补刀后击杀巨虎")
		for enemy in scene.enemies:
			enemy.take_damage(10000)
		await process_frame
		await process_frame
		check(scene.state == "loot", "清场生成可领取战利品 stage%d" % stage)
		var delayed_tutorial_steps: Array[String] = []
		if stage == 2: delayed_tutorial_steps = ["kick", "shadow"]
		elif stage == 3: delayed_tutorial_steps = ["wave", "ring"]
		for step_id in delayed_tutorial_steps:
			gs.campaign.tutorial_steps[step_id] = false
			scene.tutorial_steps[step_id] = false
		scene.claim_loot()
		check(gs.campaign.cleared, "领取后持久化 stage%d" % stage)
		if not delayed_tutorial_steps.is_empty():
			check(scene.world.get_node_or_null("PracticeDummy") != null, "技能未在战斗完成时开放安全补练木桩 stage%d" % stage)
			for step_id in delayed_tutorial_steps:
				gs.campaign.tutorial_steps[step_id] = true
				scene.tutorial_steps[step_id] = true
			scene._refresh_objective()
		var source: float = gs.campaign.source
		check(not gs.clear_region(1) and gs.campaign.source == source, "重复领奖被拒绝 stage%d" % stage)
		if stage == 0:
			check(gs.item_count("flintlock") == 1, "取得世界限定燧发枪")
			scene.player.potions -= 1
			scene._use_item("knife")
			check(gs.item_count("potion") == scene.player.potions, "清场换装不复制补给")
			scene.hud._selected_item = "flintlock"
			scene.hud._refresh_char_panel()
			check(scene.hud.item_detail.text.contains("燧发枪"), "真实物品详情写入原角色面板")
			await capture("inventory")
		if stage == 1:
			check(not gs.advance_region(), "引荐信推进门槛")
			check(scene.world.get_node("ExitPortal")._locked(), "缺引荐信时出口保持锁定")
			var gun_was_tried: bool = bool(gs.campaign.tutorial_steps.get("gun", false))
			gs.campaign.tutorial_steps["gun"] = false
			scene.tutorial_steps["gun"] = false
			use_inventory("carlos_chest")
			check(gs.item_count("carlos_chest") == 1 and gs.item_count("letter") == 0, "试射燧发枪前卡洛斯宝箱保持锁定")
			gs.campaign.tutorial_steps["gun"] = gun_was_tried
			scene.tutorial_steps["gun"] = gun_was_tried
			use_inventory("carlos_chest")
			check(gs.item_count("letter") == 1 and gs.item_count("carlos_chest") == 0, "原背包按钮开箱取得引荐信")
			check(not scene.world.get_node("ExitPortal")._locked(), "取得引荐信后出口解锁")
			check(not gs.open_chest("carlos_chest"), "宝箱不能重复开启")
		if stage == 2:
			check(not gs.advance_region(), "斩龙闪装备门槛")
			check(scene.world.get_node("ExitPortal")._locked(), "未装备斩龙闪时出口保持锁定")
			use_inventory("dragon")
			var str_val: int = int(gs.effective_attributes().str)
			var expected_attack: float = 10.5 * gs.Equip.str_atk_coef(str_val) + gs.Equip.str_attack_bonus(str_val)
			check(gs.campaign.equipment.main_weapon == "dragon" and is_equal_approx(scene.player.attack_damage, expected_attack), "原背包装备按钮即时提高攻击")
			var kick_done: bool = bool(gs.campaign.tutorial_steps.get("kick", false))
			var shadow_done: bool = bool(gs.campaign.tutorial_steps.get("shadow", false))
			gs.campaign.tutorial_steps["kick"] = false
			gs.campaign.tutorial_steps["shadow"] = false
			scene.tutorial_steps["kick"] = false
			scene.tutorial_steps["shadow"] = false
			check(scene.world.get_node("ExitPortal")._locked(), "直踹与影刺未完成时欢乐街保持锁定")
			gs.campaign.tutorial_steps["kick"] = kick_done
			gs.campaign.tutorial_steps["shadow"] = shadow_done
			scene.tutorial_steps["kick"] = kick_done
			scene.tutorial_steps["shadow"] = shadow_done
			check(not scene.world.get_node("ExitPortal")._locked(), "斩龙闪与直踹、影刺完成后出口解锁")
		if stage == 3:
			var wave_done: bool = bool(gs.campaign.tutorial_steps.get("wave", false))
			var ring_done: bool = bool(gs.campaign.tutorial_steps.get("ring", false))
			gs.campaign.tutorial_steps["wave"] = false
			gs.campaign.tutorial_steps["ring"] = false
			scene.tutorial_steps["wave"] = false
			scene.tutorial_steps["ring"] = false
			check(scene.world.get_node("ExitPortal")._locked(), "刀芒与环断未完成时科尔波山保持锁定")
			gs.campaign.tutorial_steps["wave"] = wave_done
			gs.campaign.tutorial_steps["ring"] = ring_done
			scene.tutorial_steps["wave"] = wave_done
			scene.tutorial_steps["ring"] = ring_done
			check(not scene.world.get_node("ExitPortal")._locked(), "刀芒与环断完成后科尔波山解锁")
			use_inventory("oka_chest")
			use_inventory("pendant")
			check(gs.campaign.equipment.necklace == "pendant", "原项链槽显示真实装备")
			check(gs.effective_attributes().str == 7 and gs.attributes.str == 6, "装备力量不污染裸装")
			gs.equip_item("pendant")
			check(gs.effective_attributes().str == 7, "重复装备不叠加力量")
		gs.save_game()
		gs.campaign = {}
		gs.load_game()
		check(gs.campaign.stage == stage and gs.campaign.cleared, "各阶段存读档一致 stage%d" % stage)
		if stage == 1: check(gs.campaign.bullets == 5, "弹药随地区保存")
		if stage == 3:
			if scene.sheet.visible: scene.close_sheet()
			scene.advance_next()
			check(gs.campaign.stage == 4 and not gs.campaign_practice, "欢乐街结算后直接进入科尔波山，没有技能练习阻断")
			await create_timer(0.85).timeout
			scene = current_scene
		elif stage < 4:
			check(gs.advance_region(), "推进下一地区 stage%d" % stage)
	check(is_equal_approx(float(gs.campaign.source), 8.9), "世界之源8.9%")
	check(gs.campaign.permanent_mana == 31, "噬灵者5+10+1+15 =31")
	check(gs.item_count("tiger_tooth") == 1 and gs.item_count("tiger_chest") == 1, "虎齿与绿宝箱入库")
	if scene.sheet.visible: scene.close_sheet()
	scene.primary_action()
	check(not gs.campaign.hub and scene.state == "cleared", "猎虎结算只能经返回门触发")
	scene.world.get_node("ReturnPortal").enter()
	check(gs.campaign.hub and gs.campaign.settled, "原返回门触发阶段结算")
	await create_timer(0.85).timeout
	# 过场已把场景换成新的一份，这里必须跟上引用 —— 否则下面 mount() 会再挂一份，
	# 树里同时留两套 Campaign/港口/HUD，服务点查到的是另一套的 HUD（历史遗留的重复场景坑）。
	scene = current_scene
	var coins: int = gs.coins
	check(not gs.settle_trial() and gs.coins == coins, "结算幂等")
	check(gs.attr_points == 2 and gs.campaign.level == 2, "世界之源8.9%→0点·保底1点·首轮双倍")
	check(gs.item_count("flintlock") == 0 and gs.item_count("dragon") == 1, "世界限定清理与规则装备保留")
	check(gs.open_chest("tiger_chest"), "返乐园仍可打开保留宝箱")
	check(gs.spend_attr_point("str") and gs.attributes.str == 7, "属性强化")
	check(gs.train_blade() and gs.campaign.training == 1, "灵魂结晶加币刀术训练")
	check(not gs.train_blade(), "缺材料拒绝训练")
	check(gs.buy_potion(), "乐园补给")
	await mount()
	check(scene.state == "hub" and scene.world.scene_file_path == scene.HARBOR and scene.player.visible, "返回原港口可行走主城")
	check(scene.hud.is_modal_open(), "回港先展示阶段结算报告")
	scene._dismiss_settlement_intro()
	check(not scene.hud.is_modal_open() and scene.hud.objective.text.contains("属性点"), "结算报告引导先分配属性点")
	check(not scene.world.get_node("DeparturePortal")._locked(), "主城整备引导不锁下一轮出发")
	await capture("harbor")
	var shop: Node = scene.world.get_node("ShopService")
	scene.player.global_position = shop.global_position
	await create_timer(0.25).timeout
	check(shop.visitor == scene.player, "港口商店实际碰撞触发")
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	shop._unhandled_input(interact)
	var shop_panel = scene.world.get_node_or_null("ShopPanel")
	check(shop_panel != null and shop_panel.visible, "轮回商店V交互打开完整商店UI")
	check(not scene.player.is_physics_processing(), "商店打开冻结玩家")
	var before: int = gs.coins
	var potions_before: int = gs.item_count("potion")
	shop_panel.set("_selected_id", "potion")
	shop_panel.call("_purchase")
	check(gs.coins == before - 150 and gs.item_count("potion") == potions_before + 1, "商店购买扣币入包")
	before = gs.coins
	var pendants_before: int = gs.item_count("pendant")
	shop_panel.set("_selected_id", "pendant")
	shop_panel.call("_purchase")
	check(gs.coins == before and gs.item_count("pendant") == pendants_before, "不售卖商品拒绝购买")
	shop_panel.call("close")
	check(scene.player.is_physics_processing(), "关闭商店恢复港口移动")
	scene.world.get_node("ForgeService").campaign_action.call()
	var attr_btn: Button = null
	for b in scene.hud._choice_buttons:
		if b.text.contains("属性强化"):
			attr_btn = b
	check(attr_btn != null, "铸潮工坊菜单含属性强化与刀术训练")
	attr_btn.pressed.emit()
	before = gs.attributes.str
	scene.hud._choice_buttons[0].pressed.emit()
	check(gs.attributes.str == before + 1, "原工坊按钮真实属性强化")
	check(scene.hud.objective.text.contains("任务档案"), "属性成长后引导查看任务档案")
	await capture("forge")
	scene.hud.hide_panel()
	var quest_panel = scene.hud.quest_panel
	scene.world.get_node("QuestService").campaign_action.call()
	check(quest_panel != null and quest_panel.visible, "原委托所 V 打开任务档案")
	quest_panel.call("_select", "side_tiger")
	check(_panel_text(quest_panel).contains("取得虎齿") and _panel_text(quest_panel).contains("■"),
		"任务档案读到真实任务进度（虎齿已取得）")
	quest_panel.call("close")
	check(scene.hud.objective.text.contains("演武场"), "任务档案后提示自选演武场")
	var saved: Dictionary = gs.campaign.duplicate(true)
	scene.world.get_node("TrialPortal").enter()
	check(gs.campaign.hub_guide_done.get("practice", false), "进入演武场后记录可选练习已查看")
	await create_timer(0.85).timeout
	scene = current_scene
	check(scene.location == "practice" and get_nodes_in_group("targets").size() == 1, "原演武场传送与练功木桩")
	scene.player.potions = 0
	scene.player.bombs = 0
	scene.return_from_practice()
	await create_timer(0.85).timeout
	scene = current_scene
	check(scene.location == "hub" and gs.campaign.stage == saved.stage and gs.campaign.bag == saved.bag \
		and gs.campaign.equipment == saved.equipment and gs.campaign.hub_guide_done.get("practice", false), "演武场往返保留正式物资并记住引导进度")
	saved = gs.campaign.duplicate(true)
	scene.leave()
	await create_timer(0.85).timeout
	check(current_scene.scene_file_path == gs.MAIN_MENU_SCENE, "正式菜单返回主菜单")
	gs.campaign = {}
	gs.load_game()
	check(gs.campaign == saved, "港口存读档保留装备/材料/强化和任务")
	var continue_button: Button
	for button in current_scene.find_children("*", "Button", true, false):
		if button.text.begins_with("继续游戏"): continue_button = button
	check(continue_button != null, "主菜单提供继续游戏")
	if continue_button:
		continue_button.pressed.emit()
		await create_timer(0.85).timeout
		scene = current_scene
		check(scene.location == "hub", "继续游戏恢复原港口")
	scene.world.get_node("DeparturePortal").enter()
	await create_timer(0.85).timeout
	scene = current_scene
	check(scene.location == "arena" and gs.campaign.run == 2, "原北侧世界入口实际开启下一轮")
	check(gs.campaign.world_mana == 0 and gs.campaign.permanent_mana == 31 and gs.campaign.stage == 0, "新试炼重置配额保留成长")
	await mount()
	check(scene.player.max_mp == 91 and scene.player.attack_damage > 10 and scene.player.attack_damage < 20, "成长应用到下一场战斗")
	if DisplayServer.get_name() != "headless":
		scene.start_encounter()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/core-loop-arena.png")
	gs.campaign.world_mana = 98
	check(gs.record_hunt("tiger") == 2 and gs.campaign.world_mana == 100, "噬灵者单世界上限100")
	check(gs.record_hunt("tiger") == 0 and gs.record_hunt("1_0") == 0, "重复击杀与满额不增益")
	gs.coins = 0
	check(not gs.buy_potion(), "非乐园/不足资金不能购买")
	gs.persistence_enabled = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(gs.save_path))
	print("CORE_LOOP_FAILURES=", failures)
	quit(1 if failures else 0)
