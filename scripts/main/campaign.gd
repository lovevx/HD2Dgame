extends Node3D
## 复用现有场景与HUD，只负责跨场景进度和奖励；地图保留自己的镜头/光照/遮挡。
const Data := preload("res://data/campaign.gd")
const HudScene := preload("res://scripts/ui/hud.tscn")
const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const ARENA := "res://scenes/main/main.tscn"
const HARBOR := "res://scenes/world/harbor.tscn"
const OUTER := "res://scenes/world/colpo_forest_outer.tscn"
const CLEARING := "res://scenes/world/colpo_forest_clearing.tscn"
var player: CharacterBody3D
var world: Node
var hud: CanvasLayer
var sheet: Control
var notice: Label
var director: Node
var enemies: Array[Node] = []
var pending_hunts: Array[String] = []
var state := "prepare"
var location := "arena"
var boss: Node
var loot_position := Vector3.ZERO
var loot_marker: Label3D
var _paused := false

func _ready() -> void:
	add_to_group("campaign_controller")
	if GameState.campaign_practice:
		location = "practice"
		state = "practice"
	elif GameState.campaign.hub:
		location = "hub"
		state = "hub"
	elif GameState.campaign.stage == 4:
		location = "clearing" if GameState.campaign.get("colpo_outer_cleared", false) or GameState.campaign.cleared else "outer"
	if GameState.campaign.cleared and not GameState.campaign.hub:
		state = "cleared"
	_build_world()
	hud = HudScene.instantiate()
	hud.campaign_controller = self
	add_child(hud)
	sheet = hud.char_panel
	notice = hud.message
	if director and location == "clearing":
		director.player = player
		director.hud = hud
		director.spawn_point = world.get_node("BossSpawn").global_position
		director.boss_spawned.connect(_on_boss_spawned)
	if location == "practice":
		world._spawn_dummy()
		player.hp = player.max_hp
		player.potions = 2
		player.bombs = 3
	_refresh_objective()
	sync_pause()

func _build_world() -> void:
	var path: String = {"hub": HARBOR, "outer": OUTER, "clearing": CLEARING}.get(location, ARENA)
	world = load(path).instantiate()
	world.campaign_managed = true
	player = world.get_node("player" if location in ["arena", "practice"] else "Player")
	player.campaign_mode = true
	if location == "outer":
		director = world.get_node("WaveDirector")
		director.campaign_managed = true
		director.finished.connect(_outer_finished)
	elif location == "clearing":
		director = world.get_node("BossDirector")
		director.campaign_managed = true
	_wire_interactions()
	add_child(world)
	player.hp = player.max_hp * float(GameState.campaign.hp_ratio)
	player.potions = GameState.item_count("potion")
	player.bombs = GameState.item_count("trap")
	player.bullets = GameState.campaign.bullets
	player.died.connect(_on_death)
	loot_marker = Label3D.new()
	loot_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	loot_marker.font_size = 40
	loot_marker.pixel_size = 0.012
	loot_marker.modulate = Color("ffe09a")
	loot_marker.hide()
	add_child(loot_marker)

func _wire_interactions() -> void:
	if location == "outer":
		var portal = world.get_node("ExitPortal")
		portal.campaign_action = enter_clearing
		portal.campaign_can_enter = func(): return state == "outer_cleared"
		portal.locked_text = "先清除外围三波威胁"
	elif location == "clearing":
		var portal = world.get_node("ReturnPortal")
		portal.campaign_action = primary_action
		portal.campaign_can_enter = func(): return state == "cleared"
		portal.prompt_text = "阶段结算 · 返回灰潮港"
		portal.locked_text = "先击杀巨虎并领取战利品"
		world.get_node("AreaLabel_007").text = "结算 · 返回灰潮港"
		_set_return_gate_visible(GameState.campaign.cleared)
	elif location == "hub":
		world.get_node("DeparturePortal").campaign_action = depart
		world.get_node("DeparturePortal").prompt_text = "接受下一次阶段试炼"
		world.get_node("DeparturePortalSign").text = "世界入口 · 阶段试炼"
		world.get_node("TrialPortal").campaign_action = enter_practice
		world.get_node("ShopService").campaign_action = show_shop
		world.get_node("ForgeService").campaign_action = show_forge
		world.get_node("QuestService").campaign_action = show_tasks

func _process(_delta: float) -> void:
	if state == "combat":
		var living := 0
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.is_alive(): living += 1
		if is_instance_valid(boss):
			hud.set_boss_state(boss.hp, "%s · %.0f%%" % [boss.phase_text(), boss.hp / boss.max_hp * 100])
		if living == 0 and player.alive:
			state = "loot"
			loot_position = player.global_position
			loot_marker.position = loot_position + Vector3(0, 2, 0)
			loot_marker.text = "战利品 · V 领取"
			loot_marker.show()
			hud.hide_boss()
			_refresh_objective()
	# 使用原地图活动边界，不再把大地图中的巨虎夹回原型小场地。
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.position.x = clampf(enemy.position.x, -player.bounds_x, player.bounds_x)
		enemy.position.z = clampf(enemy.position.z, player.bounds_z.x, player.bounds_z.y)
	if hud.is_modal_open() != _paused: sync_pause()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not hud.is_modal_open() and location not in ["hub", "practice"]:
		if state != "outer_cleared": primary_action()
		get_viewport().set_input_as_handled()

func _refresh_objective() -> void:
	var title: String = Data.STAGES[GameState.campaign.stage].name
	var text: String = Data.STAGES[GameState.campaign.stage].brief
	if location == "hub":
		title = "灰潮港 · 单机乐园"
		text = "北：世界入口
西：补给 / 委托所
东：工坊整备 / 演武场
靠近功能点按 V"
	elif location == "practice":
		title = "灰潮 · 自由练习场"
		text = "打木桩练习连击 / 拼刀
不消耗正式物资
Esc 返回灰潮港"
	elif location == "outer":
		title = "科尔波山 · 原始丛林外围"
		text = "清除三波威胁后，经北侧传送门进入决战空地"
	elif state == "cleared":
		text = "战利品已保存 · C开箱/换装
V " + ("阶段结算 / 回灰潮港" if GameState.campaign.stage == 4 else "前往下一地区")
	hud.configure(title, text)
	if state == "prepare": hud.show_prompt("V 开始15秒猎虎准备 · 1预埋陷阱" if location == "clearing" else "V 开始遭遇")
	elif state == "loot": hud.show_prompt("靠近战利品 · V领取 · C查看背包")
	elif state == "cleared": hud.show_prompt("C 开箱/换装 · V继续")
	else: hud.hide_prompt()

func primary_action() -> void:
	if hud.is_modal_open() or GameState.is_transitioning(): return
	match state:
		"prepare": start_encounter()
		"loot": claim_loot()
		"cleared":
			_store_supplies()
			if GameState.campaign.stage == 4:
				if GameState.settle_trial(): reload_scene()
			elif GameState.advance_region(): reload_scene()
			else: GameState.push_message("先在 C 背包中开启卡洛斯宝箱取得引荐信，或装备斩龙闪。")
		"hub": depart()
		"dead": reload_scene()

func start_encounter() -> void:
	if state != "prepare": return
	hud.hide_prompt()
	if location == "outer":
		state = "outer_combat"
		director.set_process(true)
	elif location == "clearing":
		state = "preparing"
		director.set_process(true)
		director._begin_prep()
	else:
			state = "combat"
			var profiles: Array = Data.STAGES[GameState.campaign.stage].enemies
			for i in profiles.size():
				var enemy = EnemyScene.instantiate()
				enemy.enemy_name = profiles[i][0]
				enemy.max_hp = profiles[i][1]
				enemy.attack_damage = profiles[i][2]
				enemy.kill_tier = 3 if profiles[i][1] >= 170 else 1  # 精英（欧卡）击杀扣 3 点耐
				enemy.position = Vector3(-3 + i * 6, 0, -5)
				add_child(enemy)
				enemy.defeated.connect(_on_hunt.bind("%d_%d" % [GameState.campaign.stage, i]))
				enemies.append(enemy)

func _on_boss_spawned(target: Node3D) -> void:
	boss = target
	enemies.append(boss)
	boss.defeated.connect(_on_hunt.bind("tiger"))
	state = "combat"

func _outer_finished() -> void:
	if state != "outer_combat" or not player.alive: return
	state = "outer_cleared"
	# 外围作为1.6内部检查点，不重复计算源/天赋；保留原波次和奖励防重入。
	GameState.campaign.colpo_outer_cleared = true
	_store_supplies()
	GameState.push_message("外围已清理并保存 · 前往北侧传送门，进入林间决战空地")

func enter_clearing() -> void:
	if state != "outer_cleared" or hud.is_modal_open(): return
	_store_supplies()
	reload_scene()

func _on_hunt(id: String) -> void:
	pending_hunts.append(id)
	var total := int(GameState.campaign.world_mana)
	for hunted in pending_hunts: total = mini(100, total + int(Data.HUNTS.get(hunted, 0)))
	player.max_mp = GameState.effective_attributes().int * 10 + GameState.campaign.permanent_mana + total - GameState.campaign.world_mana
	GameState.push_message("目标已击败 · 噬灵者法力 +%d（领取战利品后保存）" % int(Data.HUNTS.get(id, 0)))

func claim_loot() -> void:
	if state != "loot" or not player.alive: return
	if player.global_position.distance_to(loot_position) > 3.0:
		GameState.push_message("靠近战利品标记后按 V。")
		return
	var gained := 0
	for id in pending_hunts: gained += GameState.record_hunt(id)
	_copy_supplies()
	GameState.clear_region(player.hp / player.max_hp)
	state = "cleared"
	if location == "clearing": _set_return_gate_visible(true)
	loot_marker.hide()
	_sync_inventory()
	GameState.push_message("战利品入库 · 永久法力 +%d · C开箱/换装" % gained)
	_refresh_objective()
	show_sheet()

func _on_death() -> void:
	state = "dead"
	sync_pause()
	hud.hide_boss()
	hud.show_panel("行动失败", "未提交的本场消耗与收益回滚。\n可从最近检查点重新挑战。", "重试当前地区", reload_scene)
	if location == "practice": hud.add_choice("返回灰潮港", return_from_practice)

func _set_return_gate_visible(enabled: bool) -> void:
	# 原出口位于出生点镜头前方；猎虎过程中收起门面避免遮挡，清场后点亮。
	for id in ["PortalGate_001", "PortalBeam_001", "AreaLabel_007"]:
		world.get_node(id).visible = enabled

func sync_pause() -> void:
	if hud == null: return
	_paused = hud.is_modal_open()
	_freeze(_paused)

func _freeze(frozen: bool) -> void:
	player.set_physics_process(not frozen and state != "dead")
	player.set_process_unhandled_input(not frozen and state != "dead")
	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.set_physics_process(not frozen and state != "dead")
	for bomb in get_tree().get_nodes_in_group("alchemy_bombs"):
		bomb.set_process(not frozen and state != "dead")
	if director: director.set_process(not frozen and state in ["preparing", "combat", "outer_combat"])

func can_manage_items() -> bool:
	return state in ["prepare", "cleared", "hub", "outer_cleared"]

func show_sheet() -> void:
	hud.show_character()

func close_sheet() -> void:
	hud.char_panel.hide()

func use_item(id: String) -> void:
	if not can_manage_items(): return
	if state in ["cleared", "outer_cleared"]: _store_supplies()
	if Data.CHESTS.has(id): GameState.open_chest(id)
	else: GameState.equip_item(id)
	player._refresh_derived_stats()
	hud._refresh_char_panel()

func _use_item(id: String) -> void:
	use_item(id)
	show_sheet()

func show_shop() -> void:
	hud.show_panel("潮汐杂货 · 补给", "恢复药剂 ×1 / 100乐园币\n当前乐园币：%d · 已有药剂：%d" % [GameState.coins, GameState.item_count("potion")], "返回港口", hud.hide_panel)
	hud.add_choice("购买恢复药剂 · 100币", func():
		GameState.push_message("购买成功" if GameState.buy_potion() else "乐园币不足")
		_sync_inventory()
		show_shop())

func show_forge() -> void:
	var body := "铸潮工坊 · 装备整备\n强化 / 修复 / 分解 / 出售 / 成长吞噬\n乐园币：%d" % GameState.coins
	hud.show_panel("铸潮工坊 · 装备区", body, "返回港口", hud.hide_panel)
	hud.add_choice("装备强化机", _forge_enhance)
	hud.add_choice("锻造铺 · 修复", _forge_repair)
	hud.add_choice("分解机", _forge_decompose)
	hud.add_choice("乐园回收 · 出售", _forge_sell)
	if GameState.item_count("dragon") > 0:
		hud.add_choice("成长锻造 · 斩龙闪吞噬", _forge_devour)
	hud.add_choice("属性强化与刀术训练", _show_forge_attrs)

## 可操作的装备池：已穿戴 + 背包装备（去重）。
func _forge_pool() -> Array[String]:
	var seen: Array[String] = []
	for slot in GameState.campaign.equipment:
		var id := str(GameState.campaign.equipment[slot])
		if id != "" and not seen.has(id):
			seen.append(id)
	for id in GameState.campaign.bag:
		if GameState.item_count(id) > 0 and GameState.Campaign.is_equippable(id) and not seen.has(id):
			seen.append(id)
	return seen

func _forge_line(id: String) -> String:
	var def := GameState.item_def(id)
	var lvl := GameState.Campaign.enhance_level(GameState.campaign, id)
	var st: Dictionary = GameState.Campaign.dura_state(GameState.campaign, id)
	var dur := ("耐%d/%d" % [int(st["cur"]), int(st["max"])]) if int(st["max"]) > 0 else "无耐"
	return "%s · %s%d · +%d · %s" % [def.get("name", id), GameState.Equip.quality_cn(def.get("quality", "white")), int(def.get("score", 0)), lvl, dur]

func _forge_enhance() -> void:
	var lines := ["乐园强化机 · 仅公证装备可强化，+0~+4 失败无惩罚\n乐园币：%d" % GameState.coins]
	for id in _forge_pool():
		lines.append(_forge_line(id))
	hud.show_panel("装备强化机", "\n".join(lines), "返回工坊", show_forge)
	for id in _forge_pool():
		var def := GameState.item_def(id)
		if not def.get("export", false):
			continue
		var lvl := GameState.Campaign.enhance_level(GameState.campaign, id)
		if lvl >= GameState.Equip.ENHANCE_MAX:
			continue
		var cost := int(GameState.Equip.quality_q(def.get("quality", "white")) * (GameState.Equip.GROW_ENHANCE if def.get("growth", false) else 1.0))
		var p := int(GameState.Equip.enhance_success_rate(lvl) * 100)
		hud.add_choice("%s 强化 → +%d · %d币 · %d%%" % [_forge_line(id), lvl + 1, cost, p], func():
			GameState.enhance_item(id)
			player._refresh_derived_stats()
			_forge_enhance())

func _forge_repair() -> void:
	var lines := ["乐园锻造铺 · 修复当前耐久（上限永不下降）\n乐园币：%d" % GameState.coins]
	for id in _forge_pool():
		lines.append(_forge_line(id))
	hud.show_panel("锻造铺 · 修复", "\n".join(lines), "返回工坊", show_forge)
	for id in _forge_pool():
		var def := GameState.item_def(id)
		if not def.get("export", false):
			continue
		var st: Dictionary = GameState.Campaign.dura_state(GameState.campaign, id)
		if st["max"] <= 0 or st["cur"] >= st["max"]:
			continue
		var cost := GameState.Campaign.dura_state(GameState.campaign, id)
		var fee := int(GameState.Equip.quality_q(def.get("quality", "white")) * (cost["max"] - cost["cur"]) / cost["max"] * (GameState.Equip.GROW_REPAIR if def.get("growth", false) else 1.0))
		hud.add_choice("%s 修复 → 满耐 · %d币" % [_forge_line(id), fee], func():
			GameState.repair_item(id)
			_forge_repair())

func _forge_decompose() -> void:
	var lines := ["分解机 · 出对应品质锻造材料（几乎不给币）\n乐园币：%d" % GameState.coins]
	for id in _forge_pool():
		lines.append(_forge_line(id))
	hud.show_panel("分解机", "\n".join(lines), "返回工坊", show_forge)
	for id in _forge_pool():
		var def := GameState.item_def(id)
		if not def.get("can_decompose", false):
			continue
		hud.add_choice("%s · 分解" % _forge_line(id), func():
			GameState.decompose_item(id)
			_forge_decompose())

func _forge_sell() -> void:
	var lines := ["乐园回收 · 4 折回收公式 / 材料固定单价\n乐园币：%d" % GameState.coins]
	for id in _forge_pool():
		lines.append(_forge_line(id))
	var bag_lines: Array[String] = []
	for id in GameState.campaign.bag:
		if GameState.item_count(id) > 0 and not GameState.Campaign.is_equippable(id):
			bag_lines.append(GameState.item_def(id).get("name", id))
	if not bag_lines.is_empty():
		lines.append("其他可售：" + "、".join(bag_lines))
	hud.show_panel("乐园回收 · 出售", "\n".join(lines), "返回工坊", show_forge)
	for id in _forge_pool():
		var def := GameState.item_def(id)
		if not def.get("can_sell", true):
			continue
		hud.add_choice("%s · 出售" % _forge_line(id), func():
			GameState.sell_item(id)
			_forge_sell())
	for id in GameState.campaign.bag.keys():
		if GameState.item_count(id) <= 0 or GameState.Campaign.is_equippable(id):
			continue
		var def := GameState.item_def(id)
		if def.is_empty() or not def.get("can_sell", true):
			continue
		hud.add_choice("%s · 出售" % def.get("name", id), func():
			GameState.sell_item(id)
			_forge_sell())

func _forge_devour() -> void:
	var lines := ["成长锻造 · 斩龙闪【至尊锋刃】吞噬同类型刀类武器\n锋刃值：%.0f / %.0f（满则品质晋升）" % [float(GameState.campaign.get("item_fury", {}).get("dragon", 0.0)), GameState.Equip.GROW_MAX_FURY]]
	for id in _forge_pool():
		lines.append(_forge_line(id))
	hud.show_panel("成长锻造 · 吞噬", "\n".join(lines), "返回工坊", show_forge)
	for id in _forge_pool():
		if id == "dragon":
			continue
		var def := GameState.item_def(id)
		if def.get("item_kind", "") != "weapon" or def.get("weapon_type", "") not in ["1h_sword", "dagger"]:
			continue
		hud.add_choice("%s · 吞噬（+%.0f 锋刃）" % [_forge_line(id), float(def.get("score", 1)) * 3.0], func():
			GameState.devour_item("dragon", id)
			player._refresh_derived_stats()
			_forge_devour())

func _show_forge_attrs() -> void:
	hud.show_panel("铸潮工坊 · 属性强化与刀术训练", "可用属性点：%d · 乐园币：%d\n刀术训练 Lv.%d / 3 · 灵魂结晶小：%d" % [GameState.attr_points, GameState.coins, GameState.campaign.training, GameState.item_count("crystal")], "返回工坊", show_forge)
	for key in ["str", "agi", "con", "int"]:
		hud.add_choice("%s +1 · 消耗1属性点" % GameState.Attributes.CN_NAMES[key], _upgrade.bind(key))
	hud.add_choice("刀术训练 · 1000币 + 灵魂结晶小", func():
		GameState.push_message("训练完成" if GameState.train_blade() else "材料/乐园币不足，或已达上限")
		player._refresh_derived_stats()
		_show_forge_attrs())

func _upgrade(key: String) -> void:
	if state != "hub": return
	GameState.push_message("强化完成" if GameState.spend_attr_point(key) else "属性点不足")
	player.hp = player.max_hp
	show_forge()

func show_tasks() -> void:
	var body := "国王主线：未完成（本次范围外）\n左大臣的藏品：" + ("虎齿已获取，后续交付未开放" if GameState.item_count("tiger_tooth") > 0 else "猎杀科尔波山巨虎，取得虎齿")
	if state == "hub": body += "\n\n" + str(GameState.campaign.report)
	else: body += "\n当前地区：" + Data.STAGES[GameState.campaign.stage].name
	hud.show_panel("港务委托 · 任务与阶段记录", body, "返回", hud.hide_panel)

func depart() -> void:
	if state != "hub": return
	if GameState.begin_next_trial(): reload_scene()

func enter_practice() -> void:
	if state != "hub": return
	GameState.campaign_practice = true
	reload_scene()

func return_from_practice() -> void:
	GameState.campaign_practice = false
	reload_scene()

func _sync_inventory() -> void:
	player.potions = GameState.item_count("potion")
	player.bombs = GameState.item_count("trap")
	player._refresh_derived_stats()

func reload_scene() -> void:
	GameState.change_scene(Data.SCENE)

func _copy_supplies() -> void:
	GameState.campaign.bag.potion = player.potions
	GameState.campaign.bag.trap = player.bombs
	GameState.campaign.bullets = player.bullets
	GameState.campaign.hp_ratio = player.hp / player.max_hp

func _store_supplies() -> void:
	_copy_supplies()
	GameState.save_game()

func leave() -> void:
	if state in ["cleared", "outer_cleared"]: _store_supplies()
	GameState.campaign_practice = false
	GameState.save_game()
	GameState.change_scene(GameState.MAIN_MENU_SCENE)
