extends Node3D
signal boss_spawned(target: Node3D)
var campaign_managed := false
## 林间空地 BOSS 关流程：开场剧情 → 15 秒准备（发 3 颗炼金炸弹）→ 巨虎登场 → 三阶段 → 胜负结算。
## BOSS 本体与阶段 AI 在 scripts/combat/boss_colpo.gd，这里只负责关卡节奏与 HUD。

const BossScene := preload("res://scripts/combat/boss_colpo.tscn")

@export var prep_time := 15.0      # 准备阶段时长：预埋炸弹、规划作战位置
@export var bombs_granted := 3     # 准备阶段发放的炼金炸弹

var boss: Node3D
var player: Node3D
var hud: CanvasLayer
var phase := "intro"               # intro / prep / fight / result
var prep_left := 0.0
var spawn_point := Vector3(0, 0, -7.0)

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
			+ "数字 1 朝光标落点预埋炼金炸弹 · WASD 走位 · Shift 剃 · 左键朝鼠标连击",
			"开始准备（15 秒）", _begin_prep)

func _process(delta: float) -> void:
	match phase:
		"prep":
			prep_left = maxf(0.0, prep_left - delta)
			_update_objective()
			if prep_left <= 0.0:
				_spawn_boss()
		"fight":
			if is_instance_valid(boss) and hud != null:
				hud.set_boss_state(boss.hp, boss.phase_text())

func _begin_prep() -> void:
	phase = "prep"
	prep_left = prep_time
	if hud != null:
		hud.hide_panel()
	if player != null:
		player.set_physics_process(true)
		if not campaign_managed:
			player.bombs += bombs_granted
	GameState.push_message("[科尔波山] 埋设炼金炸弹，准备迎击山林霸主")

func _spawn_boss() -> void:
	phase = "fight"
	boss = BossScene.instantiate()
	get_parent().add_child(boss)
	boss.global_position = spawn_point
	boss.phase_changed.connect(_on_phase_changed)
	boss.defeated.connect(_on_boss_defeated)
	boss_spawned.emit(boss)
	if hud != null:
		hud.show_boss("科尔波山之主 · 巨型变异巨虎", boss.max_hp)
		hud.set_objective("猎杀科尔波山之主\n离开红圈预警范围\n1 火药陷阱 · Shift 闪避" if campaign_managed else "猎杀科尔波山之主 · 红圈亮起前离开预警范围\n数字 1 预埋炼金炸弹 · Shift 剃躲扑击")

func _on_phase_changed(_index: int, text: String) -> void:
	if hud != null and is_instance_valid(boss):
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
		hud.set_objective("准备阶段 · 剩余 %d 秒\n1 预埋火药陷阱 · 余量 %d" % [int(ceil(prep_left)), player.bombs])
	else:
		hud.set_objective("准备阶段 · 剩余 %d 秒\n数字 1 预埋炼金炸弹（%d / %d）" % [int(ceil(prep_left)), player.bombs if player != null else 0, bombs_granted])
