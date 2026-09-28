extends Node3D
## 复用现有场景与HUD，只负责跨场景进度和奖励；地图保留自己的镜头/光照/遮挡。
const Data := preload("res://data/campaign.gd")
## 提示文案里的键名一律现读 —— 写死键名会在玩家改键后变成假提示。
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")
const HudScene := preload("res://scripts/ui/hud.tscn")
const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
const EquipmentDropScript := preload("res://scripts/combat/equipment_drop.gd")
const SceneChestScript := preload("res://scripts/world/scene_chest.gd")
const GameAudio := preload("res://data/game_audio.gd")
const TUTORIAL_STEPS_BY_STAGE := {
	1: ["gun", "potion"],
	2: ["kick", "shadow"],
	3: ["wave", "ring"],
	4: ["shield", "hunter", "trap"],
}
const TUTORIAL_LABELS := {
	"gun": "试射燧发枪", "potion": "使用药剂", "kick": "使用直踹",
	"shadow": "使用影刺", "wave": "释放刀芒", "ring": "释放环断",
	"shield": "开启傲歌护盾", "hunter": "开启猎魔", "trap": "预埋火药陷阱",
}
const HUB_GUIDE_STEPS := ["growth", "supplies", "training", "archive", "practice"]
const HUB_GUIDE_LABELS := {
	"growth": "属性成长", "supplies": "补给查看", "training": "工坊整备",
	"archive": "任务档案", "practice": "自选练习",
}
const ARENA := "res://scenes/main/main.tscn"
const HARBOR := "res://scenes/world/harbor.tscn"
const OUTER := "res://scenes/world/colpo_forest_outer.tscn"
const CLEARING := "res://scenes/world/colpo_forest_clearing.tscn"
var player: CharacterBody3D
var world: Node
## 编辑器直接打开地图调试：非空时复用当前场景（不再新实例化），
## 由地图根的 _ready 注入本控制器，让调试所见与正式游玩完全一致。
var adopt_world: Node = null
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
var _boss_evacuation_seen := false
var _boss_bar_hidden_for_fake := false
## 新手教学进度（仅试炼场教学用，不落档）：木桩命中 / 剃使用次数。
var training_hits := 0
var training_dashes := 0
var _was_dodging := false
var tutorial_steps: Dictionary = {}
var _tutorial_was_hunting := false
var _tutorial_healing_uses := 0
var _tutorial_bullets := 0
var _tutorial_bombs := 0

func _ready() -> void:
	add_to_group("campaign_controller")
	if adopt_world != null:
		# 编辑器直接打开地图调试：区域按场景文件定，不信任存档里的流程位置标志。
		location = _location_of(adopt_world)
		state = "prepare"
	elif GameState.campaign_practice:
		location = "practice"
		state = "practice"
	elif GameState.campaign.hub:
		location = "hub"
		state = "hub"
	elif GameState.campaign.stage == 4:
		location = "clearing" if GameState.campaign.get("colpo_outer_cleared", false) or GameState.campaign.cleared else "outer"
	if GameState.campaign.cleared and not GameState.campaign.hub and location != "practice":
		state = "cleared"
	# 出击事务：只有战斗区域才开本局记账，灰潮港/演武场没有「未提交的本场状态」。
	# 死亡重试会重新进入本函数，于是重新拍一次快照（基线即回滚后的状态）。
	if location in ["arena", "outer", "clearing"]:
		GameState.begin_sortie()
	else:
		GameState.end_sortie()
	_build_world()
	_load_tutorial_progress()
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
		player.mp = player.max_mp
		player.potions = 2
		player.bombs = 3
		if _training_active():
			player.hit_target.connect(_on_training_hit)
	_connect_tutorial_tracking()
	if location == "hub" and _onboarding():
		# 船靠岸后从码头出生，港口向导就在跳板边
		player.position = Vector3(0, 0, 9)
	if location == "clearing":
		_restore_full_state()
	_refresh_objective()
	if location == "hub" and GameState.campaign.get("settled", false) \
			and not GameState.campaign.get("settlement_intro_seen", false):
		_show_settlement_intro()
	if state == "prepare" and location not in ["practice", "hub"]:
		_show_story()
	sync_pause()

## 正式关卡开场剧情：进关在上方显示剧情条，按任意操作自动收起。
## 战斗仍由 V 开始，与各区域原有流程一致。
func _show_story() -> void:
	var stage: Dictionary = Data.STAGES[GameState.campaign.stage]
	var story := str(stage.get("story", stage.brief))
	var hint := _tutorial_hint(GameState.campaign.stage)
	if hint != "":
		story += "\n\n" + hint
	hud.show_story(stage.name, story)

func _show_settlement_intro() -> void:
	hud.show_panel("阶段试炼结算", "%s\n\n先去东侧工坊分配本次获得的属性点。补给、工坊和任务档案会按整备顺序逐步提示。" % GameState.campaign.report,
		"开始整备", _dismiss_settlement_intro)
	sync_pause()

func _dismiss_settlement_intro() -> void:
	GameState.campaign.settlement_intro_seen = true
	GameState.save_game()
	hud.hide_panel()
	_refresh_objective()
	sync_pause()

func _hub_guide_step() -> String:
	if not GameState.campaign.get("settled", false):
		return ""
	var done: Dictionary = GameState.campaign.get("hub_guide_done", {}).duplicate(true)
	if GameState.get_attr_points() <= 0:
		done["growth"] = true
	for step_id in HUB_GUIDE_STEPS:
		if not bool(done.get(step_id, false)):
			return str(step_id)
	return "depart"

func _hub_guide_objective() -> String:
	match _hub_guide_step():
		"growth":
			return "阶段结算已完成 · 可用属性点 %d\n先到东侧工坊分配 1 点属性。" % GameState.get_attr_points()
		"supplies":
			return "属性成长已完成\n前往西侧商店查看药剂与陷阱补给；购买按需选择。"
		"training":
			return "补给已查看\n回到东侧工坊查看装备修理与刀术训练；材料不足可先跳过。"
		"archive":
			return "工坊整备已查看\n前往西南委托所查看任务档案中的下一轮目标。"
		"practice":
			return "任务档案已查看\n东南演武场可自选练习；准备好后可直接去北侧出发。"
		_:
			return "主城整备完成\n前往北侧世界入口开始下一轮试炼。"

func _mark_hub_guide_step(step_id: String) -> void:
	if not GameState.campaign.get("settled", false) or step_id not in HUB_GUIDE_STEPS:
		return
	var done: Dictionary = GameState.campaign.get("hub_guide_done", {}).duplicate(true)
	if bool(done.get(step_id, false)):
		return
	done[step_id] = true
	GameState.campaign.hub_guide_done = done
	GameState.save_game()
	GameState.push_message("主城整备已完成 · %s" % HUB_GUIDE_LABELS[step_id])
	_refresh_objective()

func _build_world() -> void:
	var path: String = {"hub": HARBOR, "outer": OUTER, "clearing": CLEARING}.get(location, ARENA)
	if adopt_world != null:
		# 编辑器直接打开调试：世界就是当前场景，只补战役装配，不再实例化新地图。
		world = adopt_world
	else:
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
	if adopt_world == null:
		add_child(world)
	_wire_interactions()
	_spawn_scene_chest()
	player.hp = player.max_hp * float(GameState.campaign.hp_ratio)
	player.mp = player.max_mp * clampf(float(GameState.campaign.mp_ratio), 0.0, 1.0)
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

func _load_tutorial_progress() -> void:
	tutorial_steps = GameState.campaign.get("tutorial_steps", {}).duplicate(true)
	# 兼容曾进入欢乐街后集中技能教学的旧存档。
	var legacy_steps: Dictionary = GameState.campaign.get("skill_training_steps", {})
	for step_id in TUTORIAL_LABELS:
		if bool(legacy_steps.get(step_id, false)):
			tutorial_steps[step_id] = true
	GameState.campaign.tutorial_steps = tutorial_steps.duplicate(true)

func _connect_tutorial_tracking() -> void:
	_tutorial_was_hunting = player.hunter_active
	_tutorial_healing_uses = player.healing_uses
	_tutorial_bullets = player.bullets
	_tutorial_bombs = player.bombs
	player.kicked.connect(_on_tutorial_kicked)
	player.skill_animation_requested.connect(_on_tutorial_skill_animation)
	player.guarded.connect(_on_tutorial_guarded)
	player.bombs_changed.connect(_on_tutorial_bombs_changed)

func _tutorial_hint(stage: int) -> String:
	var pending: Array[String] = []
	for step_id in TUTORIAL_STEPS_BY_STAGE.get(stage, []):
		if not bool(tutorial_steps.get(step_id, false)):
			pending.append(str(step_id))
	match stage:
		0:
			if state == "cleared":
				return "战利品已入包 · 背包查看药剂；受伤时按 %s 使用" % KeyBindings.key_text("potion")
			if state == "loot":
				return "战后按 %s 领取战利品，再打开背包查看药剂。" % KeyBindings.key_text("interact")
			return "留意敌人的红色预警并及时离开范围，观察生命值。战后按 %s 领取战利品。" % KeyBindings.key_text("interact")
		1:
			var cues: Array[String] = []
			if pending.has("gun") and state != "cleared":
				cues.append("先在背包装备燧发枪，再按 %s 试射" % KeyBindings.key_text("shoot"))
			if pending.has("potion"):
				cues.append("受伤后按 %s 使用药剂" % KeyBindings.key_text("potion"))
			return " · ".join(cues)
		2:
			var cues: Array[String] = []
			if pending.has("kick"):
				cues.append("按 %s 直踹打断教官" % KeyBindings.key_text("kick"))
			if pending.has("shadow"):
				cues.append("按 %s 斩中后贴近，再按 %s 影刺" % [KeyBindings.key_text("attack"), KeyBindings.key_text("shadow_stab")])
			return "完成直踹与影刺以解锁欢乐街：" + " · ".join(cues) + "（未完成可在清场后的木桩补练）" if not cues.is_empty() else ""
		3:
			var cues: Array[String] = []
			if pending.has("wave"):
				cues.append("按 %s 释放刀芒远程攻击" % KeyBindings.key_text("sword_wave"))
			if pending.has("ring"):
				cues.append("等欧卡与护卫靠近后按 %s 环断" % KeyBindings.key_text("huanduan"))
			return "完成刀芒与环断以解锁科尔波山：" + " · ".join(cues) + "（未完成可在清场后的木桩补练）" if not cues.is_empty() else ""
		4:
			var cues: Array[String] = []
			if pending.has("shield"):
				cues.append("%s 傲歌护盾" % KeyBindings.key_text("aoge"))
			if pending.has("hunter"):
				cues.append("%s 开启猎魔（持续耗蓝）" % KeyBindings.key_text("hunter_toggle"))
			if pending.has("trap"):
				cues.append("%s 预埋一枚陷阱" % KeyBindings.key_text("bomb"))
			return "完成全部猎虎准备练习后才会引出巨虎：" + " · ".join(cues) if not cues.is_empty() else ""
	return ""

func _free_practice_hint() -> String:
	var actions := {
		"kick": "%s 直踹" % KeyBindings.key_text("kick"),
		"shadow": "%s 影刺" % KeyBindings.key_text("shadow_stab"),
		"wave": "%s 刀芒" % KeyBindings.key_text("sword_wave"),
		"ring": "%s 环断" % KeyBindings.key_text("huanduan"),
		"shield": "%s 傲歌" % KeyBindings.key_text("aoge"),
		"hunter": "%s 猎魔" % KeyBindings.key_text("hunter_toggle"),
	}
	var pending: Array[String] = []
	for step_id in actions:
		if not bool(tutorial_steps.get(step_id, false)):
			pending.append(str(actions[step_id]))
	return "自选练习：" + " · ".join(pending) if not pending.is_empty() else "技能均已尝试 · 继续自由练习"

func _progression_blocker_text() -> String:
	match GameState.campaign.stage:
		1:
			var tasks: Array[String] = []
			if not bool(tutorial_steps.get("gun", false)):
				tasks.append("装备燧发枪并试射（%s）" % KeyBindings.key_text("shoot"))
			if GameState.item_count("letter") == 0:
				tasks.append("打开 %s 背包中的卡洛斯宝箱取得引荐信" % KeyBindings.key_text("character_panel"))
			return "解锁下一地区前：" + "；".join(tasks)
		2:
			var tasks: Array[String] = []
			if GameState.campaign.equipment.get("main_weapon", "") != "dragon":
				tasks.append("打开 %s 背包装备斩龙闪" % KeyBindings.key_text("character_panel"))
			if not bool(tutorial_steps.get("kick", false)) or not bool(tutorial_steps.get("shadow", false)):
				tasks.append("完成直踹与影刺练习")
			return "解锁欢乐街前：" + "；".join(tasks)
		3:
			return "完成刀芒与环断练习以解锁科尔波山"
	return "完成当前地区目标后继续"

func _ensure_progression_practice_dummy() -> void:
	var required_steps: Array = TUTORIAL_STEPS_BY_STAGE.get(GameState.campaign.stage, [])
	for step_id in required_steps:
		if not bool(tutorial_steps.get(step_id, false)):
			if world.get_node_or_null("PracticeDummy") == null:
				world._spawn_dummy()
			player.mp = player.max_mp
			player.stamina = player.max_stamina
			GameState.push_message("安全补练木桩已开放 · 完成当前技能后可继续")
			return

func _mark_tutorial_step(step_id: String) -> void:
	if not TUTORIAL_LABELS.has(step_id) or bool(tutorial_steps.get(step_id, false)):
		return
	tutorial_steps[step_id] = true
	GameState.campaign.tutorial_steps = tutorial_steps.duplicate(true)
	if not GameState.is_sortie_active():
		GameState.save_game()
	GameState.push_message("已掌握 · %s" % TUTORIAL_LABELS[step_id])
	if location == "clearing" and director != null:
		if director.phase == "prep":
			director.call("_update_objective")
		elif director.phase == "fight" and is_instance_valid(boss) and not boss.is_evacuation_active():
			director.call("_update_fight_objective")
	elif not (location == "clearing" and director != null and director.phase == "fight"):
		_refresh_objective()

func _on_tutorial_kicked() -> void:
	_mark_tutorial_step("kick")

func _on_tutorial_skill_animation(action: String) -> void:
	match action:
		"sword_wave": _mark_tutorial_step("wave")
		"ring_break": _mark_tutorial_step("ring")

func _on_tutorial_guarded() -> void:
	_mark_tutorial_step("shield")

func _on_tutorial_bombs_changed(count: int) -> void:
	if count < _tutorial_bombs:
		_mark_tutorial_step("trap")
	_tutorial_bombs = count

func _track_tutorial_actions() -> void:
	if player.hunter_active and not _tutorial_was_hunting:
		_mark_tutorial_step("hunter")
	_tutorial_was_hunting = player.hunter_active
	if player.healing_uses > _tutorial_healing_uses:
		_mark_tutorial_step("potion")
	_tutorial_healing_uses = player.healing_uses
	if player.bullets < _tutorial_bullets:
		_mark_tutorial_step("gun")
	_tutorial_bullets = player.bullets
	if player.shadow_cd > 0.0:
		_mark_tutorial_step("shadow")

func _wire_interactions() -> void:
	if location == "outer":
		var portal = world.get_node("ExitPortal")
		portal.campaign_action = enter_clearing
		portal.campaign_can_enter = func(): return state == "outer_cleared"
		portal.locked_text = "先清除外围三波威胁"
	elif location == "clearing":
		var portal = world.get_node("ReturnPortal")
		portal.campaign_action = func():
			if state == "cleared":
				advance_next()
			elif is_instance_valid(boss) and boss.is_evacuation_active():
				retreat_from_boss()
		portal.campaign_can_enter = func():
			return state == "cleared" or (is_instance_valid(boss) and boss.is_evacuation_active())
		portal.prompt_text = "阶段结算 · 返回灰潮港"
		portal.locked_text = "先击杀巨虎并领取战利品，或趁其倒地限时撤离"
		world.get_node("AreaLabel_007").text = "结算 · 返回灰潮港"
		_set_return_gate_visible(GameState.campaign.cleared)
	elif location == "arena":
		var portal = world.get_node("ExitPortal")
		portal.campaign_action = advance_next
		portal.campaign_can_enter = func(): return state == "cleared" and GameState.can_advance_region()
		portal.prompt_text = "进入科尔波山外围" if GameState.campaign.stage == 3 else "进入下一地区"
		portal.locked_text = {
			1: "试射燧发枪并打开卡洛斯宝箱取得引荐信",
			2: "装备斩龙闪并完成直踹、影刺练习",
			3: "完成刀芒、环断练习后前往科尔波山",
		}.get(GameState.campaign.stage, "清场领奖后，完成当前地区目标")
	elif location == "hub":
		var portal := world.get_node("DeparturePortal")
		# 新手流程：传送阵门控与动作都随 flow 动态判定（接完任务即解锁出发），
		# 不依赖接线时刻的 flow 快照，流程推进后无需重接线。
		portal.campaign_can_enter = func(): return _flow() == "quested" or not _onboarding()
		portal.locked_text = "先完成新手教学并接取任务"
		portal.campaign_action = func():
			if _flow() == "quested":
				start_first_trial()
			elif _onboarding():
				GameState.push_message("先完成新手教学并接取任务")
			else:
				depart()
		var resume_boss: bool = GameState.campaign.stage == 4 and bool(GameState.campaign.get("colpo_outer_cleared", false)) \
			and not GameState.campaign.cleared and not GameState.campaign.settled
		portal.prompt_text = "传送阵 · 开始试炼（废品终点站）" if _flow() == "quested" else ("返回科尔波山决战" if resume_boss else "接受下一次阶段试炼")
		world.get_node("DeparturePortalSign").text = "返回科尔波山决战" if resume_boss else "世界入口 · 阶段试炼"
		world.get_node("TrialPortal").campaign_action = enter_practice
		# 轮回商店走 ShopPanel 完整商店 UI（harbor.gd 已把 panel_handler 接到 open，买药等全部商品统一走它）
		var shop_service = world.get_node("ShopService")
		var open_shop: Callable = shop_service.panel_handler
		shop_service.panel_handler = func():
			if open_shop.is_valid(): open_shop.call()
			_mark_hub_guide_step("supplies")
		world.get_node("ForgeService").campaign_action = func():
			show_forge()
			_mark_hub_guide_step("training")
		world.get_node("QuestService").campaign_action = show_tasks
		var npc := world.get_node_or_null("GuideNpc")
		if npc != null:
			npc.set("campaign_action", talk_to_guide)

## 每个场景一个场景宝箱（1.2~1.5 按关、科尔波山外围与 BOSS 房各一）：
## 开启产出 1 炸弹 + 1 血药 + 1 随机装备，开启记录落档，重进同一关不再刷新。
func _spawn_scene_chest() -> void:
	var key := ""
	var at := Vector3.ZERO
	match location:
		"arena":
			key = "arena_%d" % GameState.campaign.stage
			at = Vector3(7.5, 0, 5.0)
		"outer":
			key = "outer"
			at = Vector3(5.0, 0, 15.5)
		"clearing":
			key = "clearing"
			at = Vector3(5.0, 0, 16.0)
		_:
			return
	if GameState.is_scene_chest_opened(key):
		return
	var chest := SceneChestScript.new()
	chest.chest_key = key
	world.add_child(chest)
	chest.global_position = at

## 击杀掉落：按概率在世界里放一件随机装备拾取物（精英概率更高；BOSS 不掉，由宝箱与结算负责）。
func _spawn_equipment_drop(enemy: Node, chance: float) -> void:
	if not is_instance_valid(enemy):
		return
	var id := GameState.roll_equipment_drop(chance)
	if id == "":
		return
	var drop := EquipmentDropScript.new()
	drop.item_id = id
	world.add_child(drop)
	drop.global_position = enemy.global_position

## 编辑器直接打开地图调试：按场景文件反推所在区域，绕开存档里的流程位置标志。
func _location_of(world: Node) -> String:
	var p := str(world.scene_file_path)
	if p.ends_with("harbor.tscn"):
		return "hub"
	if p.ends_with("colpo_forest_outer.tscn"):
		return "outer"
	if p.ends_with("colpo_forest_clearing.tscn"):
		return "clearing"
	return "arena"

## 进入 BOSS 房（林间决战空地）自动全回复：生命/法力回满 + 所有已持有装备耐久修满。
func _restore_full_state() -> void:
	player._refresh_derived_stats()
	player.hp = player.max_hp
	player.mp = player.max_mp
	GameState.campaign.hp_ratio = 1.0
	GameState.campaign.mp_ratio = 1.0
	var repaired := GameState.repair_all_equipment()
	# 决战前休整是检查点：即使没修到装备，满血满蓝也要落盘（提交本局）。
	GameState.save_game()
	GameState.push_message("[科尔波山] 决战前休整：生命与法力回满%s" % ("，装备耐久全部修满" if repaired > 0 else ""))

func _process(_delta: float) -> void:
	# 新手教学：记一次剃（按下即进入闪避态），与木桩命中一起凑完成条件。
	if location == "practice" and _training_active():
		if player.dodging and not _was_dodging:
			training_dashes += 1
			GameState.push_message("剃 ×%d / 1" % training_dashes)
			_check_training_done()
		_was_dodging = player.dodging
	_track_tutorial_actions()
	if state == "combat":
		var living := 0
		for enemy in enemies:
			if is_instance_valid(enemy) and enemy.is_alive(): living += 1
		if is_instance_valid(boss):
			if boss.is_faking_death():
				hud.hide_boss()
				_boss_bar_hidden_for_fake = true
			else:
				if _boss_bar_hidden_for_fake:
					hud.show_boss("科尔波山之主 · 巨型变异巨虎", boss.max_hp)
					_boss_bar_hidden_for_fake = false
				hud.set_boss_state(boss.hp, "%s · %.0f%%" % [boss.phase_text(), boss.hp / boss.max_hp * 100])
			if boss.is_evacuation_active():
				if not _boss_evacuation_seen:
					_boss_evacuation_seen = true
					_set_return_gate_visible(true)
					world.get_node("AreaLabel_007").text = "限时撤离 · 返回灰潮港"
					world.get_node("ReturnPortal").prompt_text = "限时撤离 · 返回灰潮港"
				var seconds := int(ceil(boss.evacuation_seconds_left()))
				if boss.evacuation_has_risen():
					hud.set_objective("巨虎反扑 · 剩余 %d 秒撤离" % seconds)
				else:
					hud.set_objective("巨虎倒地 · %d 秒内返回主城" % seconds)
			elif _boss_evacuation_seen:
				_boss_evacuation_seen = false
				_set_return_gate_visible(false)
				world.get_node("AreaLabel_007").text = "结算 · 返回灰潮港"
				world.get_node("ReturnPortal").prompt_text = "阶段结算 · 返回灰潮港"
				hud.set_objective("撤离窗口关闭 · 击杀科尔波山之主")
		if living == 0 and player.alive:
			state = "loot"
			loot_position = player.global_position
			loot_marker.position = loot_position + Vector3(0, 2, 0)
			loot_marker.text = "战利品 · %s 领取" % KeyBindings.key_text("interact")
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
		if state in ["combat", "outer_combat"]:
			return
		# 站在场景宝箱触发圈里时，V 归宝箱，避免同时推进关卡流程
		if get_tree().get_first_node_in_group("scene_chest_focus") != null:
			return
		if state != "outer_cleared": primary_action()
		get_viewport().set_input_as_handled()

func _refresh_objective() -> void:
	if location == "arena" and world.has_method("set_route_phase"):
		world.set_route_phase(state, GameState.can_advance_region())
	var title: String = Data.STAGES[GameState.campaign.stage].name
	var task_name: String = title
	var text: String = Data.STAGES[GameState.campaign.stage].brief
	if location == "hub":
		title = "灰潮港 · 单机乐园"
		if GameState.player_name != "":
			title += "　契约者 %s" % GameState.player_name
		if GameState.campaign.get("settled", false):
			task_name = "猎虎归港整备"
			text = _hub_guide_objective()
		else:
			match _flow():
				"ship":
					task_name = "初抵灰潮港"
					text = "港口向导在码头等你\n靠近向导按 %s 对话" % KeyBindings.key_text("interact")
				"training":
					task_name = "新手教学"
					text = "前往东侧 · 试炼传送阵（演武场）\n完成新手教学"
				"equipped":
					task_name = "猎杀者试炼"
					text = "轮回乐园已发布新任务\n前往西侧 · 任务委托所接取"
				"quested":
					task_name = str(Data.STAGES[0].name)
					text = "任务已接取\n前往北侧 · 传送阵开始试炼"
				_:
					text = "北：世界入口
	西：补给 / 委托所
	东：工坊整备 / 演武场
	靠近功能点按 %s · %s 任务档案" % [KeyBindings.key_text("interact"), KeyBindings.key_text("quest_log")]
	elif location == "practice":
		if _training_active():
			task_name = "新手教学"
			title = "灰潮 · 新手教学"
			text = "新手教学：攻击木桩 ×3 · 剃 ×1（%s）\n完成后发放整套基础装备\n%s 返回灰潮港" % [KeyBindings.key_text("dodge"), KeyBindings.key_text("open_menu")]
		else:
			task_name = "自由练习"
			title = "灰潮 · 自由练习场"
			text = "打木桩练习斩击 / 剃
	不消耗正式物资
	%s 返回灰潮港
	%s" % [KeyBindings.key_text("open_menu"), _free_practice_hint()]
	elif location == "outer":
		title = "科尔波山 · 原始丛林外围"
		text = "清除三波威胁后，经北侧传送门进入决战空地"
	elif state == "cleared":
		var next_step := " · 阶段结算 / 回灰潮港" if GameState.campaign.stage == 4 else (" · 进入科尔波山外围" if GameState.campaign.stage == 3 else " · 进入下一地区")
		text = "战利品已保存 · %s 开箱/换装\n前往北侧出口传送门" % KeyBindings.key_text("character_panel") + next_step
		if location == "arena" and not GameState.can_advance_region():
			text = _progression_blocker_text()
	if (location == "arena" and GameState.campaign.stage <= 3) or location == "clearing":
		var hint := _tutorial_hint(GameState.campaign.stage)
		if hint != "":
			text += "\n" + hint
	hud.configure(title, text, task_name)
	if state == "prepare":
		if location == "clearing":
			hud.show_prompt("%s 开始15秒猎虎准备 · %s 预埋陷阱" % [KeyBindings.key_text("interact"), KeyBindings.key_text("bomb")])
		else:
			hud.show_prompt("%s 开始遭遇" % KeyBindings.key_text("interact"))
	elif state == "loot": hud.show_prompt("靠近战利品 · %s领取 · %s查看背包" % [KeyBindings.key_text("interact"), KeyBindings.key_text("character_panel")])
	elif state == "cleared": hud.show_prompt("%s 开箱/换装 · 走向北侧传送门" % KeyBindings.key_text("character_panel"))
	else: hud.hide_prompt()

func primary_action() -> void:
	if hud.is_modal_open() or GameState.is_transitioning(): return
	match state:
		"prepare": start_encounter()
		"loot": claim_loot()
		"cleared":
			GameState.push_message("前往北侧出口传送门" + ("结算并返回灰潮港" if location == "clearing" else "进入下一地区"))
		"hub": depart()
		"dead": reload_scene()

## 清场结算后推进：arena 由出口传送门走进触发；科尔波山决战由返回门触发。
func advance_next() -> void:
	if state != "cleared": return
	_store_supplies()
	if GameState.campaign.stage == 4:
		if GameState.settle_trial(): reload_scene()
	elif GameState.advance_region(): reload_scene()
	else: GameState.push_message(_progression_blocker_text())

func retreat_from_boss() -> void:
	if state != "combat" or not is_instance_valid(boss) or not boss.is_evacuation_active():
		return
	if boss.is_faking_death() and not boss.evacuation_has_risen():
		if not boss.confirm_evacuation_kill():
			return
		for id in pending_hunts:
			GameState.record_hunt(id)
		pending_hunts.clear()
		_copy_supplies()
		GameState.clear_region(player.hp / player.max_hp)
		state = "cleared"
		advance_next()
		return
	boss.cancel_evacuation()
	state = "retreating"
	_boss_evacuation_seen = false
	_set_return_gate_visible(false)
	_freeze(true)
	GameState.settle_sortie(GameState.Sortie.ABANDON)
	GameState.campaign.hub = true
	GameState.campaign.cleared = false
	GameState.campaign_practice = false
	GameState.push_message("已撤回灰潮港 · 巨虎未击杀，决战可再次进入")
	GameState.save_game()
	reload_scene()

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
			enemy.kind = EnemyScript.Kind.HUMAN  # 人形白盒模型 + 举刀/挥击动作
			enemy.model = str(profiles[i][3]) if profiles[i].size() > 3 else ""
			match GameState.campaign.stage:
				0: enemy.position = Vector3(0, 0, -3.5)
				1: enemy.position = Vector3(0, 0, -4.5)
				2: enemy.position = Vector3(0, 0, -2.8)
				3: enemy.position = Vector3(-2.5, 0, -4.8) if i == 0 else Vector3(2.6, 0, -3.0)
			add_child(enemy)
			enemy.defeated.connect(_on_hunt.bind("%d_%d" % [GameState.campaign.stage, i]))
			# 精英（欧卡）掉落概率更高；普通小怪给基础概率
			enemy.defeated.connect(_spawn_equipment_drop.bind(enemy, 0.9 if profiles[i][1] >= 150 else 0.5))
			enemies.append(enemy)
		world.set_route_phase(state, false)

func _on_boss_spawned(target: Node3D) -> void:
	boss = target
	_boss_bar_hidden_for_fake = false
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
	var before: float = player.max_mp
	player.max_mp = GameState.effective_attributes().int * 10 + GameState.campaign.permanent_mana + total - GameState.campaign.world_mana
	player.mp = minf(player.max_mp, player.mp + player.max_mp - before)
	GameState.push_message("目标已击败 · 噬灵者法力 +%d（领取战利品后保存）" % int(Data.HUNTS.get(id, 0)))

func claim_loot() -> void:
	if state != "loot" or not player.alive: return
	if player.global_position.distance_to(loot_position) > 3.0:
		GameState.push_message("靠近战利品标记后按 %s。" % KeyBindings.key_text("interact"))
		return
	var gained := 0
	for id in pending_hunts: gained += GameState.record_hunt(id)
	_copy_supplies()
	GameState.clear_region(player.hp / player.max_hp)
	state = "cleared"
	if location == "clearing": _set_return_gate_visible(true)
	if location == "arena" and GameState.campaign.stage in [2, 3]:
		_ensure_progression_practice_dummy()
	loot_marker.hide()
	_sync_inventory()
	GameState.push_message("战利品入库 · 永久法力 +%d · %s开箱/换装" % [gained, KeyBindings.key_text("character_panel")])
	_refresh_objective()
	show_sheet()

func _on_death() -> void:
	state = "dead"
	sync_pause()
	hud.hide_boss()
	# 四条结束路径共用同一事务（P1：正常撤离 / 逃脱币救援 / 无币永久死亡 / 超时）。
	# 战死走回滚：未提交的途中拾取与战斗中耐久损耗一并作废，已提交部分保留。
	var body := "练习场不消耗正式物资。\n可直接重试或返回灰潮港。"
	if GameState.is_sortie_active():
		var had_uncommitted := GameState.is_sortie_dirty()
		GameState.settle_sortie(GameState.Sortie.DEATH)
		body = ("未提交的本场拾取与装备损耗已回滚。\n" if had_uncommitted else "本场没有未提交的收益或损耗。\n") \
			+ "已提交的进度（宝箱、换装、乐园消费）保留。\n可从最近检查点重新挑战。"
	hud.show_panel("行动失败", body, "重试当前地区", reload_scene)
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
	if id == "carlos_chest" and GameState.campaign.stage == 1 and not bool(tutorial_steps.get("gun", false)):
		GameState.push_message("先在 %s 背包装备燧发枪，再按 %s 试射，然后开启卡洛斯宝箱。" % [
			KeyBindings.key_text("character_panel"), KeyBindings.key_text("shoot"),
		])
		return
	if state in ["cleared", "outer_cleared"]: _store_supplies()
	if Data.CHESTS.has(id): GameState.open_chest(id)
	else: GameState.equip_item(id)
	player._refresh_derived_stats()
	hud._refresh_char_panel()
	_refresh_objective()

func _use_item(id: String) -> void:
	use_item(id)
	show_sheet()

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
	var spent := GameState.spend_attr_point(key)
	GameState.push_message("强化完成" if spent else "属性点不足")
	if spent: _mark_hub_guide_step("growth")
	player.hp = player.max_hp
	show_forge()

## 灰潮港西侧「港务委托所」（V）：打开任务档案面板。
## 新手流程有待接任务时（flow == equipped）在面板底栏挂一个接取按钮 —— 接取动作仍在战役控制器里，
## 面板只负责显示；其余档位（船到港 / 教学中 / 已接取 / 常规循环）都是只读查看，
## 原来那几段纯文字说明由面板的序章条目与「轮回记录」章承接。
func show_tasks() -> void:
	if _flow() == "equipped":
		hud.open_quest_log_with("接取任务 · 猎杀者试炼", _accept_first_quest)
	else:
		hud.open_quest_log()
	_mark_hub_guide_step("archive")

func depart() -> void:
	if state != "hub": return
	if GameState.campaign.stage == 4 and GameState.campaign.get("colpo_outer_cleared", false) \
			and not GameState.campaign.cleared and not GameState.campaign.settled:
		GameState.campaign.hub = false
		GameState.save_game()
		reload_scene()
		return
	if GameState.begin_next_trial(): reload_scene()

func enter_practice() -> void:
	if state != "hub": return
	_mark_hub_guide_step("practice")
	# 新手流程：没跟向导对话就先进演武场，也按教学处理（流程推进到 training）
	if _flow() == "ship":
		GameState.campaign.flow = "training"
		GameState.save_game()
	GameState.campaign_practice = true
	reload_scene()

func return_from_practice() -> void:
	GameState.campaign_practice = false
	reload_scene()

# ---------------------------------------------------------------- 新手流程

## 当前新手流程阶段（campaign.flow 兜底空串）。
func _flow() -> String:
	return str(GameState.campaign.get("flow", ""))

## 是否处于新手流程（船到港 → 教学 → 接任务 → 传送阵出发）。
func _onboarding() -> bool:
	return _flow() in ["ship", "training", "equipped", "quested"]

## 试炼场教学是否进行中：进入教学阶段且还没领过基础装备。
func _training_active() -> bool:
	return location == "practice" and _flow() == "training" \
		and not GameState.campaign.get("training_done", false)

## 港口向导对话：V 触发（campaign.gd 注入到 GuideNpc 的 campaign_action）。
func talk_to_guide() -> void:
	if state != "hub": return
	if _flow() == "ship":
		GameState.campaign.flow = "training"
		GameState.save_game()
		hud.show_dialogue("港口向导", [
			"新人，快去东侧的试炼场地熟悉一下身手吧！",
			"东侧码头旁的试炼传送阵会送你去练武场。",
			"在练武场打三下木桩、用一次剃（%s），就能领到整套基础装备。" % KeyBindings.key_text("dodge"),
		], _refresh_objective)
	else:
		hud.show_dialogue("港口向导", ["练熟了就去任务委托所看看吧，乐园在等着你的第一次猎杀。"])

## 木桩命中（player.hit_target 只统计 targets 组，即练功木桩）。
func _on_training_hit(target: Node, _dmg: float) -> void:
	if not _training_active() or not target.is_in_group("targets"):
		return
	training_hits += 1
	GameState.push_message("木桩命中 %d / 3" % training_hits)
	_check_training_done()

## 教学完成判定：命中木桩 3 次 + 使用 1 次剃 → 发放整套基础装备，流程进 equipped。
func _check_training_done() -> void:
	if not _training_active():
		return
	if training_hits < 3 or training_dashes < 1:
		return
	GameState.campaign.training_done = true
	GameState.campaign.flow = "equipped"
	var gear := GameState.grant_starter_gear()
	GameState.save_game()
	GameState.push_message("[乐园] 新手教学完成 · 已发放整套基础装备")
	GameAudio.play_sfx("quest_complete", global_position)
	hud.show_panel("新手教学完成", "已发放整套基础装备：\n%s\n\n轮回乐园检测到新的试炼任务，回到灰潮港后前往西侧 · 任务委托所接取。" % "、".join(gear), "返回灰潮港", return_from_practice)
	_refresh_objective()

## 接取第一个任务（废品终点站）：流程进 quested，目标改为北侧传送阵。
func _accept_first_quest() -> void:
	if state != "hub": return
	GameState.campaign.flow = "quested"
	GameState.save_game()
	hud.hide_panel()
	GameState.push_message("[乐园] 任务已接取 · 前往北侧传送阵开始试炼")
	_refresh_objective()

## 传送阵出发：开始第一次正式试炼（废品终点站），此后进入常规战役循环。
func start_first_trial() -> void:
	if state != "hub": return
	GameState.campaign.hub = false
	GameState.campaign.flow = "trial"
	GameState.campaign_practice = false
	GameState.save_game()
	GameState.push_message("[乐园] 开始试炼 · 废品终点站")
	reload_scene()

func _sync_inventory() -> void:
	player.potions = GameState.item_count("potion")
	player.bombs = GameState.item_count("trap")
	player._refresh_derived_stats()

func reload_scene() -> void:
	GameState.change_scene(Data.SCENE)

func _copy_supplies() -> void:
	if GameState.debug_mode_active:
		return
	GameState.campaign.bag.potion = player.potions
	GameState.campaign.bag.trap = player.bombs
	GameState.campaign.bullets = player.bullets
	GameState.campaign.hp_ratio = player.hp / player.max_hp
	GameState.campaign.mp_ratio = player.mp / player.max_mp
	# 这里直接写 campaign 易变键，绕过 give_item 的记账，需要手动标脏。
	GameState.mark_sortie_dirty()

func _store_supplies() -> void:
	_copy_supplies()
	GameState.save_game()

func leave() -> void:
	if state in ["cleared", "outer_cleared"]:
		_store_supplies()  # 已清场：正常撤离，提交本局
	else:
		# 战斗中退回主菜单按「放弃出击」处理，否则退菜单/关窗会变成偷偷提交。
		GameState.settle_sortie(GameState.Sortie.ABANDON)
	GameState.campaign_practice = false
	GameState.save_game()
	GameState.change_scene(GameState.MAIN_MENU_SCENE)
