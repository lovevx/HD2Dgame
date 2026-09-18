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
	scene.player.hp = 40
	var drink := InputEventAction.new()
	drink.action = "potion"
	drink.pressed = true
	scene.player._unhandled_input(drink)
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
			await capture("tiger")
		scene.show_sheet()
		check(not scene.player.is_physics_processing() and not scene.enemies[0].is_physics_processing(), "烙印暂停双方 stage%d" % stage)
		scene.close_sheet()
		if stage == 1:
			var camera: Camera3D = root.get_camera_3d()
			var saved_rotation := camera.rotation
			camera.rotation.x = -PI / 2.0 # 无头环境鼠标固定在视口边缘，让测试射线落地。
			var point: Vector3 = scene.player.mouse_ground_point()
			var direction: Vector3 = point - scene.player.global_position
			direction.y = 0
			scene.enemies[0].global_position = scene.player.global_position + direction.normalized() * 4
			var old_hp: float = scene.enemies[0].hp_
			gs.campaign.equipment.offhand = "flintlock"  # 副手槽装备燧发枪（右键触发）
			scene.player._fire_flintlock()
			camera.rotation = saved_rotation
			# 枪械攻击区间 2-13 × 力量倍率，双 roll 伪随机：确认命中并扣弹、伤害落区间内
			check(scene.player.bullets == 5 and scene.enemies[0].hp_ < old_hp and scene.enemies[0].hp_ >= old_hp - 15, "副手燧发枪命中并消耗弹药")
		if stage == 4:
			var tiger: Node = scene.boss
			var trap: Node = load("res://scripts/combat/alchemy_bomb.tscn").instantiate()
			scene.add_child(trap)
			trap.place_at(tiger.global_position)
			trap._on_body_entered(tiger)
			trap._process(0.4)
			check(tiger.hp == tiger.max_hp - 90, "火药陷阱踩踏引爆伤害")
			tiger.take_damage(290)
			check(tiger.phase == 1, "巨虎65%狂暴")
			tiger.take_damage(320)
			check(tiger.is_faking_death(), "巨虎25%诈死尚未胜利")
			check(scene.state == "combat" and not gs.campaign.cleared, "诈死不能领取奖励")
			for i in 3:
				scene.player.global_position = tiger.global_position + tiger.global_basis.z * 4
				tiger.take_damage(1, Vector3.ZERO, scene.player)
			check(tiger.tendon_broken, "后方三次命中破坏筋腱")
		for enemy in scene.enemies:
			enemy.take_damage(10000)
		await process_frame
		await process_frame
		check(scene.state == "loot", "清场生成可领取战利品 stage%d" % stage)
		scene.claim_loot()
		check(gs.campaign.cleared, "领取后持久化 stage%d" % stage)
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
			use_inventory("carlos_chest")
			check(gs.item_count("letter") == 1 and gs.item_count("carlos_chest") == 0, "原背包按钮开箱取得引荐信")
			check(not gs.open_chest("carlos_chest"), "宝箱不能重复开启")
		if stage == 2:
			check(not gs.advance_region(), "斩龙闪装备门槛")
			use_inventory("dragon")
			# 新攻击模型：区间中点 10.5 × 力量倍率 1.10（str 6）× 刀术训练 1.0 = 11.55
			check(gs.campaign.equipment.main_weapon == "dragon" and is_equal_approx(scene.player.attack_damage, 11.55), "原背包装备按钮即时提高攻击")
		if stage == 3:
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
		if stage < 4: check(gs.advance_region(), "推进下一地区 stage%d" % stage)
	check(is_equal_approx(float(gs.campaign.source), 8.9), "世界之源8.9%")
	check(gs.campaign.permanent_mana == 31, "噬灵者5+10+1+15 =31")
	check(gs.item_count("tiger_tooth") == 1 and gs.item_count("tiger_chest") == 1, "虎齿与绿宝箱入库")
	check(gs.settle_trial(), "阶段结算返回乐园")
	var coins: int = gs.coins
	check(not gs.settle_trial() and gs.coins == coins, "结算幂等")
	check(gs.attr_points == 4 and gs.campaign.level == 2, "首轮噩梦双倍，等级仅权限")
	check(gs.item_count("flintlock") == 0 and gs.item_count("dragon") == 1, "世界限定清理与规则装备保留")
	check(gs.open_chest("tiger_chest"), "返乐园仍可打开保留宝箱")
	check(gs.spend_attr_point("str") and gs.attributes.str == 7, "属性强化")
	check(gs.train_blade() and gs.campaign.training == 1, "灵魂结晶加币刀术训练")
	check(not gs.train_blade(), "缺材料拒绝训练")
	check(gs.buy_potion(), "乐园补给")
	await mount()
	check(scene.state == "hub" and scene.world.scene_file_path == scene.HARBOR and scene.player.visible, "返回原港口可行走主城")
	await capture("harbor")
	var shop: Node = scene.world.get_node("ShopService")
	scene.player.global_position = shop.global_position
	await create_timer(0.25).timeout
	check(shop.visitor == scene.player, "港口商店实际碰撞触发")
	var interact := InputEventAction.new()
	interact.action = "interact"
	interact.pressed = true
	shop._unhandled_input(interact)
	check(scene.hud.overlay.visible and scene.hud.panel_title.text.contains("杂货"), "原商店V交互打开真实购买服务")
	var before: int = gs.coins
	scene.hud._choice_buttons[0].pressed.emit()
	check(gs.coins == before - 100 and not scene.player.is_physics_processing(), "商店按钮扣币并暂停玩家")
	scene.hud.hide_panel()
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
	await capture("forge")
	scene.hud.hide_panel()
	scene.world.get_node("QuestService").campaign_action.call()
	check(scene.hud.panel_body.text.contains("虎齿已获取"), "原委托所读取真实任务与结算")
	scene.hud.hide_panel()
	var saved: Dictionary = gs.campaign.duplicate(true)
	scene.world.get_node("TrialPortal").enter()
	await create_timer(0.85).timeout
	scene = current_scene
	check(scene.location == "practice" and get_nodes_in_group("targets").size() == 1, "原演武场传送与练功木桩")
	scene.player.potions = 0
	scene.player.bombs = 0
	scene.return_from_practice()
	await create_timer(0.85).timeout
	scene = current_scene
	check(scene.location == "hub" and gs.campaign == saved, "演武场返回港口且正式物资不变")
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
