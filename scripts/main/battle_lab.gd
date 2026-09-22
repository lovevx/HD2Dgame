extends Node
## 新手教程 · 战斗训练场：**一只小怪 + 一只科尔波山之主**，两个都是不还手的训练靶。
## 设计依据 docs/COMBAT_DESIGN.md。
##
## 教程路径：
##   1) 小怪（野狼）：平A 攒眩晕 → 打满后停止移动 → 用【直踹 K】处决击杀。
##   2) 山之主：同样用平A / 直踹 / 环断 攒眩晕 → 打满后【再次攻击命中】→ 进入回合制，
##      我方先手 1 回合 → 五条指令（攻击 / 战技 / 防御 / 道具 / 逃跑）各试一次即完成。
##
## 训练靶配置（2026-09-22 定）：
##   · 两个敌人**都不主动攻击**（野狼 `patrol_only` 且移速 0 = 原地不动；山之主 `passive`）。
##   · 血量调高到足以打满眩晕条 —— 否则还没学会"攒眩晕"就把目标打死了。
##   · 回合制内山之主"出手"但不结算伤害，玩家不可能在教程里死。
## 调试键：R 重开训练场 · H 直接给山之主叠 25 点眩晕（省去手动打满）。

const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
const BossScene := preload("res://scripts/combat/boss_colpo.tscn")
const HudScene := preload("res://scripts/ui/hud.tscn")
const AssetCatalog := preload("res://tools/preset_catalog.gd")
const CameraStyle := preload("res://scripts/world/jungle_camera_style.gd")
const Orbit := preload("res://scripts/world/camera_orbit_controls.gd")
const Attributes := preload("res://data/attributes.gd")
const CombatSkills := preload("res://data/combat_skills.gd")

const CAM_YAW := CameraStyle.YAW
const CAMERA_LEAD := 0.75
const FOLLOW_SPEED := 5.5
const FOCUS_BOUNDS := Rect2(-13, -13, 26, 26)
## 对手站位：小怪在左前，山之主在右前（都在场地内、摄像机一眼能看到）。
const MOB_AT := Vector3(-5.0, 0, -3.0)
const BOSS_AT := Vector3(6.0, 0, -6.0)
const PLAYER_AT := Vector3(0, 0, 6.0)
## 训练靶血量：野狼原档 34 会在攒满眩晕前就死（平A 每次约 7 点），
## 山之主原档 800 本身够用，这里一并抬高，让"打满眩晕"成为唯一节奏。
const TUTORIAL_MOB_HP := 260.0
const TUTORIAL_BOSS_HP := 1200.0
## 教程收尾：指令都试过就结束回合战。条数取 BattleMenu.COMMANDS，不再各写一份常量
## （旧口径这里写死 3，与练习场的 5 条并存过；作者 2026-09-23 统一为五条）。
## 训练靶不还手又血厚，不收尾玩家会陷在一场打不完的战斗里；想改成"打到死"就置 false。
const TUTORIAL_END_AFTER_ALL_COMMANDS := true

@onready var player: CharacterBody3D = $player
@onready var camera: Camera3D = $Camera3D
var hud: CanvasLayer
var _orbit := Orbit.new()
var _camera_lead := Vector3.ZERO
var _mob: Node = null
var _boss: Node = null
var _battle_running := false
var _battle_controller := BattleController.new()
## 教程进度：用过哪几条指令（下标 → true）。全部试过即收尾（条数见 BattleMenu.COMMANDS）。
var _tutorial_used := {}
var _order_bar: OrderBar = null
var _battle_menu: BattleMenu = null
var rng := RandomNumberGenerator.new()

func _input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		get_viewport().set_input_as_handled()

func _ready() -> void:
	rng.randomize()
	CameraStyle.configure(camera, true)
	_orbit.configure(camera, CameraStyle.PITCH, CameraStyle.YAW, CameraStyle.distance(true))
	_orbit.snap(camera, _camera_target(), CameraStyle.composition(_orbit.forward_flat()))
	_build_arena()
	player.position = PLAYER_AT
	player.reset()
	player.died.connect(_on_player_died)
	# 命中"已经眩晕的山之主" → 进入回合制（设计 §2.2 的触发条件）。
	player.struck_stunned_foe.connect(_on_struck_stunned_foe)
	hud = HudScene.instantiate()
	add_child(hud)
	hud.configure("新手教程 · 战斗训练场", "两个训练靶都不会还手：打满眩晕条，再决定是处决还是进回合")
	hud.set_objective("① 野狼：平A 打满眩晕 → 直踹(K)处决　② 山之主：打满眩晕 → 再补一刀进回合")
	_build_battle_ui()
	_spawn_opponents()
	GameState.push_message("训练靶不会还手 · R 重开 · H 给山之主叠眩晕（调试）")

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_R:
			restart()
		KEY_H:
			if is_instance_valid(_boss) and _boss.is_alive():
				_boss.add_stun(CombatSkills.KICK_STUN)
				GameState.push_message("调试：山之主眩晕 %d%%" % int(_boss.stun))

func _process(delta: float) -> void:
	_update_camera(delta)

## 重开训练场：清掉两个对手重新摆好（玩家满血满蓝、退出回合战、清空指令记录）。
func restart() -> void:
	if _battle_running:
		_end_battle(false, true)
	if is_instance_valid(_mob):
		_mob.queue_free()
	if is_instance_valid(_boss):
		_boss.queue_free()
	_mob = null
	_boss = null
	_tutorial_used.clear()
	player.position = PLAYER_AT
	player.reset()
	player.set_physics_process(true)
	hud.hide_panel()
	hud.set_objective("① 野狼：平A 打满眩晕 → 直踹(K)处决　② 山之主：打满眩晕 → 再补一刀进回合")
	_spawn_opponents()
	GameState.push_message("训练场已重置")

func _on_player_died() -> void:
	if _battle_running:
		_end_battle(false, true)
	player.set_physics_process(false)
	player.input_dir = Vector2.ZERO
	hud.show_panel("倒下了", "训练靶不会还手，理论上不该发生 —— 请按「重开训练场」恢复。", "重开训练场", restart)

# ---------------------------------------------------------------- 场地

func _build_arena() -> void:
	var paving := ShaderMaterial.new()
	paving.shader = preload("res://shaders/trial_floor.gdshader")
	paving.set_shader_parameter("stone_color", Color("414a55"))
	paving.set_shader_parameter("tile_scale", 0.5)
	paving.set_shader_parameter("grout", 0.05)
	$ground/MeshInstance3D.material_override = paving
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	var env := world.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("3d4b57")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7798bd")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.ssil_enabled = true
	env.ssil_intensity = 0.65
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color("778f9d")
	env.fog_density = 0.0012
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color("aebfce")
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.25
	add_child(world)
	_build_boundary()

## 边界四角石柱 + 石灯，把 25 米见方的验证场压成规则四边形（纯装饰无碰撞）。
func _build_boundary() -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_prop("SM_Licheng_shizhuzi001", Vector3(sx * 12.7, 0, sz * 12.7), 0.0, 1.4)
	for side in [-1.0, 1.0]:
		_prop("SM_NJ_ShiDeng_001", Vector3(side * 12.7, 0, 0), 0.0, 1.0)
		_prop("SM_NJ_ShiDeng_001", Vector3(0, 0, side * 12.7), 0.0, 1.0)

func _prop(title: String, at: Vector3, yaw := 0.0, size := 1.0) -> void:
	var asset: HD2DAsset = AssetCatalog.asset(title)
	if asset == null:
		return
	var node := HD2DProp.new()
	node.name = title
	node.asset = asset
	node.asset_overrides = {"static_collision": false}
	node.position = at
	node.rotation_degrees = Vector3(0, yaw, 0)
	node.scale = Vector3.ONE * size
	add_child(node)

func _update_camera(delta: float) -> void:
	var movement := Vector3(player.velocity.x, 0, player.velocity.z)
	var lead_target := movement.limit_length(4.0) * (CAMERA_LEAD / 4.0)
	_camera_lead = _camera_lead.lerp(lead_target, 1.0 - exp(-3.0 * delta))
	_orbit.place(camera, _camera_target(), CameraStyle.composition(_orbit.forward_flat()), delta, FOLLOW_SPEED)

func _camera_target() -> Vector3:
	var focus := player.position + _camera_lead
	focus.x = clampf(focus.x, FOCUS_BOUNDS.position.x, FOCUS_BOUNDS.end.x)
	focus.z = clampf(focus.z, FOCUS_BOUNDS.position.y, FOCUS_BOUNDS.end.y)
	return focus

# ---------------------------------------------------------------- 两个对手

func _spawn_opponents() -> void:
	_spawn_mob()
	_spawn_boss()

## 小怪：一只野狼，**不由主动攻击**（`patrol_only` + 移速 0 = 原地站桩），
## 血量调到 260 让玩家能从容打满眩晕条，再用直踹处决。
func _spawn_mob() -> void:
	_marker("小怪 · 野狼（训练靶）", MOB_AT, Color("ff8a5c"))
	var mob: Node = EnemyScene.instantiate()
	mob.name = "LabMob"
	mob.set("kind", EnemyScript.Kind.WOLF)
	mob.position = MOB_AT
	add_child(mob)
	# 注意：enemy.gd 的 _ready 会按 PROFILES 覆盖 max_hp / move_speed，
	# 所以训练靶这三项必须在入树之后再设，否则会被档位值盖掉。
	mob.set("patrol_only", true)   # 永不攻击
	mob.set("move_speed", 0.0)     # 站原地，方便新手瞄准
	mob.set_max_hp(TUTORIAL_MOB_HP)
	_mob = mob
	mob.defeated.connect(func() -> void: GameState.push_message("小怪已被处决 · 教程第一步完成"))

## 山之主：同样**不主动攻击**（`passive`），血量 1200，被击杀前足够反复练"攒眩晕 → 补刀"。
func _spawn_boss() -> void:
	_marker("科尔波山之主（训练靶）", BOSS_AT, Color("e8b45a"))
	var boss: Node = BossScene.instantiate()
	boss.name = "ColpoLord"
	boss.position = BOSS_AT
	add_child(boss)
	boss.set("passive", true)      # 不主动接近、不出手；回合内出手也不掉血
	boss.set_max_hp(TUTORIAL_BOSS_HP)
	_boss = boss
	if boss.has_signal("phase_changed"):
		boss.phase_changed.connect(func(_i: int, text: String) -> void:
			GameState.push_message("山之主 · %s" % text))
	if boss.has_signal("defeated"):
		boss.defeated.connect(func() -> void:
			GameState.push_message("科尔波山之主已被讨伐")
			if not _battle_running:
				hud.show_panel("讨伐完成", "训练靶也能真的打完 —— 你已经掌握即时战斗与回合制两条链路。\n\n按「重开训练场」可以再来一遍。", "重开训练场", restart))

## 站位标记：地面光环 + 悬浮标签，一眼分清谁是"小怪"、谁是"山之主"。
func _marker(text: String, at: Vector3, color: Color) -> void:
	var holder := Node3D.new()
	holder.name = "Marker"
	holder.position = at
	add_child(holder)
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.0
	cyl.bottom_radius = 2.0
	cyl.height = 0.02
	disc.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.22)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.02
	holder.add_child(disc)
	var label := Label3D.new()
	label.text = text
	label.position.y = 3.6
	label.font_size = 40
	label.pixel_size = 0.010
	label.outline_size = 12
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	holder.add_child(label)

# ---------------------------------------------------------------- 回合制战斗

func _build_battle_ui() -> void:
	_order_bar = OrderBar.new()
	_order_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_order_bar.offset_top = 96.0
	_order_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_order_bar.visible = false
	hud.add_child(_order_bar)
	_battle_menu = BattleMenu.new()
	_battle_menu.visible = false
	hud.add_child(_battle_menu)

## 触发入口：命中了"已经眩晕"的目标——若是山之主，则进入回合制（设计 §2.2）。
func _on_struck_stunned_foe(foe: Node) -> void:
	if _battle_running or not is_instance_valid(_boss):
		return
	if foe != _boss:
		GameState.push_message("小怪已在眩晕态 · 用直踹处决")
		return
	start_battle()

func start_battle() -> void:
	if _battle_running or not is_instance_valid(_boss) or not _boss.is_alive():
		return
	_battle_running = true
	player.battle_mode = true
	player.velocity = Vector3.ZERO
	_boss.clear_stun()          # 进入回合后不再吃眩晕（设计 Q1 口径）
	_boss.set("battle_driven", true)
	var agi := int(GameState.effective_attributes().get("agi", Attributes.BASE))
	_battle_controller.set_units([
		BattleUnit.from_player(player, agi),
		BattleUnit.from_enemy(_boss),
	])
	# 进入奖励：我方先手 1 回合（设计 §2.4）。
	_battle_controller.begin_battle_with_player_first()
	_order_bar.visible = true
	GameState.push_message("山之主露出破绽 · 进入回合制（我方先手）")
	_run_battle()

## 回合主循环：按 AT 顺序轮流行动，直到山之主被讨伐 / 玩家阵亡。
func _run_battle() -> void:
	while _battle_running:
		var unit := _battle_controller.current()
		if unit == null:
			_battle_running = false
			break
		if _battle_controller.all_enemies_dead():
			_end_battle(true)
			return
		if not player.alive:
			_end_battle(false)
			return
		_order_bar.build(_battle_controller.order_labels(), _battle_controller.index)
		if not BattleController.node_alive(unit.node):
			_battle_controller.finish_turn()
			await get_tree().process_frame
			continue
		if unit.is_player:
			await _player_command(unit)
			# 教程收尾：五条指令都试过就结束回合战（训练靶血厚又不还手，不收尾打不完）。
			# 先看 _battle_running：逃跑已经在 _player_command 里收过尾了，别再叠一个面板。
			if _battle_running and TUTORIAL_END_AFTER_ALL_COMMANDS \
					and _tutorial_used.size() >= BattleMenu.COMMANDS.size():
				_end_battle(true, false, true)
				return
		else:
			await _enemy_command(unit)
		if _battle_running and not _battle_controller.all_enemies_dead() and player.alive:
			_battle_controller.finish_turn()
			# 每整轮回蓝结算在作战单位上，wrap 后抄回玩家实体（玩家才是权威）。
			_battle_controller.flush_player_mp()
		await get_tree().process_frame

## 我方回合：自动走位到攻击距离 → **五条指令**（与练习场同一套，见 BattleMenu.COMMANDS）。
func _player_command(unit: BattleUnit) -> void:
	_auto_approach(unit)
	_battle_menu.open(BattleMenu.COMMANDS)
	var idx: int = await _battle_menu.confirmed
	_battle_menu.close()
	if not _battle_running:
		return
	var foe := _battle_controller.nearest_foe_to(unit)
	_face(foe)
	_tutorial_used[idx] = true   # 教程进度（只记录"试过"，不要求这次一定成功）
	match idx:
		0:  # 攻击
			if foe != null and _in_attack_range(foe):
				player.battle_execute_attack(_battle_controller.attack_bonus(unit, foe))
			else:
				GameState.push_message("攻击落空 · 距离不够")
		1:  # 战技
			await _player_skill()
		2:  # 防御
			unit.set_defend(true)
			GameState.push_message("防御姿态 · 本回合受伤大幅降低")
		3:  # 道具
			await _player_item()
		4:  # 逃跑
			if _battle_controller.flee(unit):
				GameState.push_message("成功脱离战斗")
				_end_battle(true, true)
				return
			GameState.push_message("逃跑失败 · 白白浪费一回合")
	# 玩家实体是 HP/MP 的唯一权威：出手（战技扣蓝 / 药剂回血）后立刻抄回作战单位，
	# 这样整轮 wrap 时把回蓝抄回实体才是安全的（见 battle_controller 的两个同步点）。
	_battle_controller.pull_player_stats()

func _auto_approach(unit: BattleUnit) -> void:
	var foe := _battle_controller.nearest_foe_to(unit)
	if foe == null:
		return
	_face(foe)
	var dist := foe.node.global_position.distance_to(player.global_position)
	if dist > player.attack_range + 0.1:
		var step := minf(unit.move_power, dist - player.attack_range)
		player.battle_execute_move(step)

func _face(foe: BattleUnit) -> void:
	if foe == null or foe.node == null:
		return
	var to_target: Vector3 = foe.node.global_position - player.global_position
	to_target.y = 0.0
	if to_target.length_squared() > 0.001:
		player.battle_turn_dir = to_target.normalized()

func _in_attack_range(foe: BattleUnit) -> bool:
	if foe.node == null:
		return false
	var bulk := 0.0
	if foe.node.has_method("hit_radius"):
		bulk = foe.node.hit_radius()
	return foe.node.global_position.distance_to(player.global_position) <= player.attack_range + bulk + 0.05

## 技能子页：目前只接已实装的刀芒与环断（影刺 / 傲歌 / 青钢影的回合化属 P2）。
## MP 判定与扣除都收在 battle_execute_skill 里（那里也负责"不扣蓝就出手"的老 bug），
## 这里只把失败原因说出来。
func _player_skill() -> void:
	_battle_menu.open(["剑气·断空", "环断"])
	var opt: int = await _battle_menu.confirmed
	_battle_menu.close()
	var label: String = "剑气·断空" if opt == 0 else "环断"
	var skill: String = "sword_wave" if opt == 0 else "ring"
	var ok: bool = player.battle_execute_skill(skill)
	if not ok:
		var cost: float = CombatSkills.WAVE_MP_COST if opt == 0 else CombatSkills.RING_MP_COST
		GameState.push_message("蓝量不足 · %s 需要 %d MP" % [label, int(cost)])

func _player_item() -> void:
	_battle_menu.open(["药剂", "炼金炸弹"])
	var opt: int = await _battle_menu.confirmed
	_battle_menu.close()
	match opt:
		0:
			if player.potions <= 0:
				GameState.push_message("药剂用完了")
			else:
				player.battle_execute_item("potion")
		1:
			if player.bombs <= 0:
				GameState.push_message("没有炸弹")
			else:
				player.battle_execute_item("bomb")

## 敌人回合：一步接近或攻击。训练靶出手但不结算伤害（`battle_damage = 0`）。
func _enemy_command(unit: BattleUnit) -> void:
	await get_tree().create_timer(0.55).timeout
	if not _battle_running or not player.alive:
		return
	var intent: String = unit.node.battle_advance(player.global_position)
	if intent != "攻击":
		return
	var dmg := float(unit.attack_power)
	if unit.node.get("battle_damage") != null:
		dmg = float(unit.node.get("battle_damage"))
	if dmg > 0.0:
		player.take_damage(dmg)
	else:
		GameState.push_message("山之主扑了一记空（训练靶不结算伤害）")
	await get_tree().process_frame

func _end_battle(won: bool, silent := false, tutorial_done := false) -> void:
	_battle_running = false
	player.battle_mode = false
	_order_bar.visible = false
	_battle_menu.visible = false
	if is_instance_valid(_boss):
		_boss.set("battle_driven", false)
	# 不再把快照 MP 写回玩家 —— 玩家的蓝由实体自己持有，收尾时单位只是镜像。
	# 旧实现正是在这里用开战快照覆盖 player.mp，把回合内花掉的蓝整笔退了回来。
	if silent:
		return
	if tutorial_done:
		GameState.push_message("教程完成 · 五条指令都试过了")
		hud.show_panel("教程完成", "即时战斗：平A 攒眩晕 → 直踹处决。\n回合制：打满眩晕后补一刀进入，先手 1 回合，五条指令（攻击 / 战技 / 防御 / 道具 / 逃跑）都试过了。\n\n训练靶没有还手，可以放心多练几遍。", "重开训练场", restart)
		return
	if won:
		GameState.push_message("回合制战斗胜利 · 山之主已被讨伐")
		hud.show_panel("讨伐完成", "走完了整条链路：即时战斗打满眩晕 → 补刀进回合制 → 打完。\n\n可以重开再练一遍。", "重开训练场", restart)
	else:
		hud.show_panel("教程中断", "回合战被中止了（训练靶不会还手，正常不该走到这里）。", "重开训练场", restart)
