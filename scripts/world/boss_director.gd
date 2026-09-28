extends Node3D
signal boss_spawned(target: Node3D)
var campaign_managed := false
## 林间空地 BOSS 关流程：开场剧情 → 15 秒准备（发 3 颗炼金炸弹）→ 巨虎登场 → 三阶段 → 胜负结算。
## BOSS 本体与阶段 AI 在 scripts/combat/boss_colpo.gd，这里只负责关卡节奏与 HUD。

const BossScene := preload("res://scripts/combat/boss_colpo.tscn")
## 提示文案里的键名现读（改键后不会还写着旧键）。
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")

@export var prep_time := 15.0      # 准备阶段时长：预埋炸弹、规划作战位置
@export var bombs_granted := 3     # 准备阶段发放的炼金炸弹

var boss: Node3D
var player: Node3D
var hud: CanvasLayer
var phase := "intro"               # intro / prep / fight / result
var prep_left := 0.0
var spawn_point := Vector3(0, 0, -7.0)
var _boss_bar_hidden_for_fake := false
var _prep_gate_announced := false

func _ready() -> void:
	# 编辑器直接打开地图时由 campaign 控制器接管（get_parent() 即地图根节点），
	# BOSS 流程门控与正式游玩一致：等 V 开始遭遇才放开。
	if campaign_managed or get_tree().current_scene == get_parent():
		set_process(false)
		return
	# 等父节点（关卡脚本）把 HUD 挂好再取引用
	call_deferred("_start")

func _start() -> void:
	player = get_tree().get_first_node_in_group("player")
	hud = get_tree().get_first_node_in_group("hud")
	var marker := get_parent().get_node_or_null("BossSpawn")
	if marker is Node3D:
		spawn_point = marker.position
	if player != null:
		player.died.connect(_on_player_died)
		player.set_physics_process(false)  # 开场剧情期间不放手让玩家乱跑
	if hud != null:
		hud.show_panel("科尔波山 · 林间决战",
			"科尔波山深处，猛兽盘踞。\n苏晓提前在林间空地布置炼金炸弹陷阱，准备狩猎这座山林的霸主。\n\n"
			+ ("%s 朝光标落点预埋炼金炸弹 · WASD 走位 · %s 剃 · 左键朝鼠标斩击" % [KeyBindings.key_text("bomb"), KeyBindings.key_text("dodge")]),
			"开始准备（15 秒）", _begin_prep)

func _process(delta: float) -> void:
	match phase:
		"prep":
			prep_left = maxf(0.0, prep_left - delta)
			_update_objective()
			if prep_left <= 0.0:
				if campaign_managed and not _prep_tutorial_done():
					if not _prep_gate_announced:
						_prep_gate_announced = true
						GameState.push_message("完成护盾、猎魔与陷阱练习后，巨虎才会出现")
					_update_objective()
					return
				_spawn_boss()
		"fight":
			if is_instance_valid(boss) and hud != null:
				if boss.is_faking_death():
					hud.hide_boss()
					_boss_bar_hidden_for_fake = true
				else:
					if _boss_bar_hidden_for_fake:
						hud.show_boss("科尔波山之主 · 巨型变异巨虎", boss.max_hp)
						_boss_bar_hidden_for_fake = false
					hud.set_boss_state(boss.hp, boss.phase_text())
				if boss.is_evacuation_active():
					var seconds := int(ceil(boss.evacuation_seconds_left()))
					var objective := "巨虎反扑 · %d 秒内撤离" if boss.evacuation_has_risen() else "巨虎倒地 · %d 秒内返回主城"
					hud.set_objective(objective % seconds)

func _begin_prep() -> void:
	phase = "prep"
	prep_left = prep_time
	if hud != null:
		hud.hide_panel()
	if player != null:
		player.set_physics_process(true)
		if not campaign_managed:
			player.bombs += bombs_granted
		elif player.bombs <= 0 and not _tutorial_step_done("trap"):
			# 让核心教学在缺少正式补给时仍可完成；这枚临时练习陷阱不进入背包。
			player.bombs = 1
			player.bombs_changed.emit(player.bombs)
			GameState.push_message("补给不足 · 临时补发一枚训练陷阱")
	GameState.push_message("[科尔波山] 埋设炼金炸弹，准备迎击山林霸主")

func _spawn_boss() -> void:
	phase = "fight"
	boss = BossScene.instantiate()
	get_parent().add_child(boss)
	boss.global_position = spawn_point
	_boss_bar_hidden_for_fake = false
	boss.phase_changed.connect(_on_phase_changed)
	boss.defeated.connect(_on_boss_defeated)
	boss_spawned.emit(boss)
	if hud != null:
		hud.show_boss("科尔波山之主 · 巨型变异巨虎", boss.max_hp)
		_update_fight_objective()

func _on_phase_changed(_index: int, text: String) -> void:
	if hud != null and is_instance_valid(boss):
		if boss.is_faking_death():
			hud.hide_boss()
			_boss_bar_hidden_for_fake = true
		else:
			if _boss_bar_hidden_for_fake:
				hud.show_boss("科尔波山之主 · 巨型变异巨虎", boss.max_hp)
				_boss_bar_hidden_for_fake = false
			hud.set_boss_state(boss.hp, text)

func _on_boss_defeated() -> void:
	phase = "result"
	if campaign_managed:
		return
	if hud != null:
		hud.hide_boss()
		hud.show_panel("猎杀完成",
			"科尔波山之主已被猎杀，山林恢复暂时的平静。\n"
			+ "白盒阶段不写存档；噬灵者回蓝与青钢影真实伤害将随对应系统一并接入。",
			"返回选关", _back_to_select)

func _on_player_died() -> void:
	if hud != null:
		hud.hide_boss()

func _back_to_select() -> void:
	GameState.change_scene(GameState.LEVEL_SELECT_SCENE)

func _update_objective() -> void:
	if hud == null:
		return
	if campaign_managed:
		var missing := _missing_prep_steps()
		var practice_text := "猎虎准备已完成" if missing.is_empty() else "待完成：" + " · ".join(missing)
		if prep_left <= 0.0 and not missing.is_empty():
			practice_text = "完成后才会引出巨虎：" + " · ".join(missing)
		practice_text += "\n陷阱余量 %d" % player.bombs
		hud.set_objective("准备阶段 · 剩余 %d 秒\n%s" % [int(ceil(prep_left)), practice_text])
	else:
		hud.set_objective("准备阶段 · 剩余 %d 秒\n%s 预埋炼金炸弹（%d / %d）" % [int(ceil(prep_left)), KeyBindings.key_text("bomb"), player.bombs if player != null else 0, bombs_granted])

func _update_fight_objective() -> void:
	if hud == null:
		return
	if campaign_managed:
		hud.set_objective("猎杀科尔波山之主\n离开红圈预警范围 · %s 剃闪避" % KeyBindings.key_text("dodge"))
	else:
		hud.set_objective("猎杀科尔波山之主 · 红圈亮起前离开预警范围\n%s 预埋炼金炸弹 · %s 剃躲扑击" % [KeyBindings.key_text("bomb"), KeyBindings.key_text("dodge")])

func _tutorial_step_done(step_id: String) -> bool:
	var steps: Dictionary = GameState.campaign.get("tutorial_steps", {})
	return bool(steps.get(step_id, false))

func _prep_tutorial_done() -> bool:
	return _tutorial_step_done("shield") and _tutorial_step_done("hunter") and _tutorial_step_done("trap")

func _missing_prep_steps() -> Array[String]:
	var missing: Array[String] = []
	if not _tutorial_step_done("shield"):
		missing.append("%s 开启傲歌护盾" % KeyBindings.key_text("aoge"))
	if not _tutorial_step_done("hunter"):
		missing.append("%s 开启猎魔" % KeyBindings.key_text("hunter_toggle"))
	if not _tutorial_step_done("trap"):
		missing.append("%s 预埋一枚陷阱" % KeyBindings.key_text("bomb"))
	return missing
