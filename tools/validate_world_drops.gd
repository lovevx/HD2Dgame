extends SceneTree
## 世界掉落与场景宝箱验收：前期本土装备掉落池、击杀掉落概率、场景宝箱（按 key 防重复）、
## BOSS 房决战全回复，以及阶段结算对本土装备的清理。
## 无头模式跑逻辑；D3D12 实渲染模式额外输出宝箱截图。
const Campaign := preload("res://data/campaign.gd")
const TestEnv := preload("res://tools/test_env.gd")
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
	root.get_texture().get_image().save_png("res://.tmp_preview/drops-%s.png" % label)

func run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	# 隔离档 + 固定初始状态。这里要真写盘（下面验宝箱记录/下一轮重置都依赖落盘），
	# 所以 keep_persistence=true，但写的仍是隔离档，不是玩家的真实存档。
	TestEnv.isolate(gs, "world_drops", true)
	gs.complete_contract("掉落验收")

	# ---- 数据层：掉落池与场景宝箱产出表 ----
	var pool_ok := true
	var pool_local := true
	for id in Campaign.RANDOM_EQUIP_POOL:
		var def: Dictionary = Campaign.ITEMS.get(str(id), {})
		if def.is_empty() or not def.has("slot"):
			pool_ok = false
		if def.get("export", true):
			pool_local = false
	check(not Campaign.RANDOM_EQUIP_POOL.is_empty() and pool_ok, "掉落池全部是可穿戴且已定义的装备")
	check(pool_local, "掉落池全为本土装备（结算带不出，不破坏跨轮成长）")
	var chest_items_ok := not Campaign.SCENE_CHEST_ITEMS.is_empty()
	for id in Campaign.SCENE_CHEST_ITEMS:
		if not Campaign.ITEMS.has(str(id)):
			chest_items_ok = false
	check(chest_items_ok, "场景宝箱固定产出物均在物品表内")

	# ---- 随机抽取与概率边界 ----
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260919
	var in_pool := true
	for i in 64:
		if not Campaign.RANDOM_EQUIP_POOL.has(Campaign.random_equip_id(rng)):
			in_pool = false
	check(in_pool, "随机装备抽取始终落在池内")
	check(gs.roll_equipment_drop(1.0) != "", "必然概率一定掉落")
	var never := true
	for i in 32:
		if gs.roll_equipment_drop(0.0) != "":
			never = false
	check(never, "零概率永远不掉落")
	check(not gs.is_scene_chest_opened("never_opened") and gs.open_scene_chest("").is_empty(), "空 key 不写入开启记录")

	# ---- 场景集成：宝箱生成 / V 让位 / 产出入包 / 防重复 ----
	await mount()
	var chests := get_nodes_in_group("scene_chest")
	check(chests.size() == 1, "1.2 关卡生成唯一场景宝箱")
	var chest: Node = chests[0] if not chests.is_empty() else null
	check(chest != null and chest.chest_key == "arena_0", "宝箱 key 绑定当前关卡")
	if chest != null:
		scene.player.global_position = chest.global_position
		await create_timer(0.25).timeout
		check(get_nodes_in_group("scene_chest_focus").size() == 1, "玩家进圈登记宝箱焦点")
		var potion_before: int = gs.item_count("potion")
		var trap_before: int = gs.item_count("trap")
		var state_before: String = scene.state
		var interact := InputEventAction.new()
		interact.action = "interact"
		interact.pressed = true
		scene._unhandled_input(interact)
		check(scene.state == state_before and not chest.opened, "站在宝箱圈里 V 让位，不触发关卡流程")
		chest._unhandled_input(interact)
		check(chest.opened, "宝箱自身接管 V 开启")
		check(gs.item_count("potion") == potion_before + 1 and gs.item_count("trap") == trap_before + 1, "宝箱补给实际入包")
		var got_equip := false
		for id in Campaign.RANDOM_EQUIP_POOL:
			if gs.item_count(str(id)) > 0:
				got_equip = true
		check(got_equip, "宝箱随机装备实际入包")
		check(gs.is_scene_chest_opened("arena_0") and gs.open_scene_chest("arena_0").is_empty(), "开启记录落档且不能重复领取")
		await capture("chest")
	await mount()
	check(get_nodes_in_group("scene_chest").is_empty(), "已开启的宝箱重进关卡不再刷新")
	if is_instance_valid(scene):
		scene.free()
		scene = null

	# ---- BOSS 房决战全回复 ----
	var knife_max: float = float(Campaign.ITEMS["knife"]["dur_max"])
	gs.campaign.item_dura["knife"] = {"cur": 1.0, "max": knife_max}
	check(gs.repair_all_equipment() >= 1 and is_equal_approx(Campaign.dura_state(gs.campaign, "knife")["cur"], knife_max), "决战前休整修复已损装备")
	check(gs.repair_all_equipment() == 0, "满耐久时不重复修复")

	# ---- 阶段结算：本土装备必须带不出 ----
	gs.give_item("dragon", 1)
	gs.give_item("worn_blade", 1)
	gs.give_item("ragged_vest", 1)
	gs.campaign.equipment["body"] = "ragged_vest"
	gs.campaign.stage = 4
	gs.campaign.cleared = true
	gs.campaign.settled = false
	gs.campaign.hub = false
	check(gs.settle_trial(), "阶段结算正常执行")
	check(gs.item_count("worn_blade") == 0 and gs.item_count("ragged_vest") == 0, "结算清理未带出的本土装备")
	check(gs.campaign.equipment.get("body", "") == "", "结算同步清除本土装备的槽位引用")
	check(gs.item_count("dragon") == 1, "公证装备结算保留")

	# ---- 下一轮重置宝箱记录 ----
	gs.campaign.opened_chests = ["arena_0", "outer"]
	check(gs.begin_next_trial(), "结算后开启下一轮")
	check(not gs.is_scene_chest_opened("arena_0") and not gs.is_scene_chest_opened("outer"), "下一轮重置宝箱开启记录")

	TestEnv.cleanup(gs)
	print("WORLD_DROPS_FAILURES=", failures)
	quit(1 if failures else 0)
