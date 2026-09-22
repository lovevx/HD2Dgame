extends CharacterBody3D
## 科尔波山之主（巨型变异巨虎）：能量型精英 BOSS。
## P1 完整霸主 → P2 受伤狂暴（65%）→ P3 残血诈死偷袭（25%）。
## 所有招式都先在地面亮红圈预警再结算，玩家能用剃位移或岩石掩体规避。
## 白盒阶段身体用程序化几何拼装：肩高 4.2 米、体长 7 米上下，P2 起叠加焦痕与眼部伤。

signal phase_changed(index: int, text: String)
signal defeated
const CombatSkills := preload("res://data/combat_skills.gd")
## 头顶眩晕条（scripts/battle/stun_gauge.gd）。显式 preload，不依赖编辑器全局类缓存。
const StunGaugeScript := preload("res://scripts/battle/stun_gauge.gd")

enum Phase { P1, P2, P3 }
enum State { ROAR, APPROACH, HESITATE, WINDUP, STRIKE, RECOVER, FAKE_DEATH, DEAD }

const PHASE_TEXT := {Phase.P1: "P1 完整霸主", Phase.P2: "P2 受伤狂暴", Phase.P3: "P3 残血诈死"}
const P2_AT := 0.65
const P3_AT := 0.25

## 招式表：前摇 / 伤害 / 预警圈半径 / 触发距离 / 爪击前伸偏移 / 后摇
const ATTACKS := {
	"claw": {"windup": 0.55, "damage": 22.0, "radius": 4.6, "reach": 7.0, "offset": 3.4, "recover": 0.85},
	"stomp": {"windup": 0.80, "damage": 26.0, "radius": 7.0, "reach": 9.5, "offset": 0.0, "recover": 1.00},
	"pounce": {"windup": 0.65, "damage": 30.0, "radius": 3.4, "reach": 21.0, "offset": 0.0, "recover": 1.00},
	"ambush": {"windup": 0.12, "damage": 45.0, "radius": 5.5, "reach": 6.0, "offset": 0.0, "recover": 1.10},
}

@export var max_hp: float = 800.0
@export var walk_speed: float = 5.0
@export var charge_speed: float = 21.0
@export var preferred_distance: float = 9.0
@export var hesitate_time: float = 1.0
@export var fake_death_time: float = 4.0
@export var ambush_range: float = 6.5  # 以身体中心算：正面约离身体 2.8 米就够触发暴起偷袭

var hp: float
var has_energy := true
var physical_reduction := 0.0
var kill_tier: int = 8  # BOSS 级：击杀扣主武器 8 点耐久（策划案 §6.3.1）
var phase: int = Phase.P1
var state: int = State.ROAR
var player: Node3D
var marker: MeshInstance3D
var marker_mat: StandardMaterial3D
var label: Label3D
var wounds: Node3D
var body_part: Node3D

var _timer := 0.6
var _attack_cd := 2.0
var _strafe := 1.0
var _strafe_clock := 0.0
var _current := ""
var _target_point := Vector3.ZERO
var _pounce_dir := Vector3.ZERO
var _hit_done := false
var _second_pounce := false
var _windup_scale := 1.0
var _cooldown_scale := 1.0
var _double_pounce := false
var _hesitate_cd := 0.0
var _eye_mat: StandardMaterial3D
var _marker_radius := 1.0
var _flash_timer := 0.0
var tendon_hits := 0
var tendon_broken := false

## ---------- 眩晕条（即时战斗侧，见 docs/COMBAT_DESIGN.md §1.4） ----------
## 打满 → 玩家再次攻击命中即进入回合制；回合内不再积累，退战后清零。
var stun := 0.0
var stun_max := CombatSkills.STUN_MAX
var _stun_gauge: Node3D = null

## ---------- 回合制战斗接口（见 docs/COMBAT_DESIGN.md 第二部） ----------
## battle_driven：回合战期间由 controller 驱动移动/攻击，本体的实时 AI 让位。
var battle_driven := false
## 回合内最近一次选定招式的伤害，供 controller 结算（实时伤害仍走 ATTACKS 前摇流程）。
var battle_damage := 0.0
## 回合内接近到该距离即出手（实时招式的 reach 差异太大，回合内统一）。
var battle_reach := 7.0
## 教程 / 训练模式：站着面向玩家，不主动接近、不出手；回合内出手也不结算伤害。
## 血量照常会被打、眩晕照常会积 —— 只有威胁被摘掉。
@export var passive := false

func _ready() -> void:
	add_to_group("enemies")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	body_part = Node3D.new()
	body_part.name = "Body"
	add_child(body_part)
	_build_body()
	_build_marker()
	label = Label3D.new()
	label.position.y = 6.6  # 抬过高处，避免压住白盒里的区域标记
	label.font_size = 48
	label.pixel_size = 0.011
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	add_child(label)
	_update_label()
	GameState.push_message("[科尔波山] 巨虎现身，咆哮震得林间树叶簌簌掉落")

## 大体型目标：攻击判定按这个半径放宽，不然要贴到身体中心才算命中。
func hit_radius() -> float:
	return 3.0

func is_alive() -> bool:
	return state != State.DEAD

## 教程 / 训练用：直接设定血量上限并回满（覆盖导出的默认值）。
func set_max_hp(value: float) -> void:
	max_hp = maxf(1.0, value)
	hp = max_hp
	_update_label()

func phase_text() -> String:
	return PHASE_TEXT[phase]

## 是否正在装死（供关卡脚本与验证脚本判断，不直接读私有状态）。
func is_faking_death() -> bool:
	return state == State.FAKE_DEATH

## 当前正在前摇或结算的招式名。
func current_attack() -> String:
	return _current

## ---------- 眩晕与回合制接口 ----------

## 叠加眩晕；满值后玩家再攻击命中即触发回合制（由训练场 / 关卡脚本接管）。
## **不衰减**（作者 2026-09-22 定，与 enemy.gd 同口径）。
func add_stun(amount: float) -> void:
	if not is_alive() or amount <= 0.0 or is_stunned():
		return
	stun = minf(stun_max, stun + amount)
	_update_stun_gauge()

func is_stunned() -> bool:
	return is_alive() and stun >= stun_max

## 进入回合制时调用：清掉眩晕，让山之主能正常参与回合（这不是衰减，是状态重置）。
func clear_stun() -> void:
	stun = 0.0
	_update_stun_gauge()

func _update_stun_gauge() -> void:
	if stun <= 0.0:
		if _stun_gauge != null:
			_stun_gauge.set_ratio(0.0)
		return
	if _stun_gauge == null:
		var gauge: Node3D = StunGaugeScript.new()
		gauge.name = "StunGauge"
		add_child(gauge)
		gauge.setup(stun_max, 5.2, 2.8)   # 肩高 4.2，黄条挂在模型之上并按体型加宽
		_stun_gauge = gauge
	_stun_gauge.set_ratio(_stun_gauge.ratio_of(stun))

## 回合制行动：接近或攻击，返回意图文本供 AT 栏显示；伤害按阶段取招式表。
func battle_advance(target_world: Vector3) -> String:
	if not is_alive() or is_faking_death():
		return "待机"
	var flat := target_world - global_position
	flat.y = 0.0
	var dist := flat.length()
	if dist <= battle_reach + hit_radius():
		# 训练模式下照样"出手"（让回合结构与意图可见），但不结算伤害。
		battle_damage = 0.0 if passive else float(_turn_attack()["damage"])
		return "攻击"
	var dir: Vector3 = flat.normalized() if dist > 0.01 else Vector3.FORWARD
	global_position += dir * minf(walk_speed, maxf(0.0, dist - battle_reach))
	if is_instance_valid(player):
		_face_player(1.0)
	return "接近"

## 回合内招式：按阶段取一档（P1 爪击 / P2 踏击 / P3 扑击）。
func _turn_attack() -> Dictionary:
	match phase:
		Phase.P2:
			return ATTACKS["stomp"]
		Phase.P3:
			return ATTACKS["pounce"]
		_:
			return ATTACKS["claw"]

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	# 回合制期间：实时 AI 完全让位给 battle_controller。
	if battle_driven:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	# 眩晕态：停止行动（等待玩家补刀进回合 / 自然回落）。
	if is_stunned():
		velocity = Vector3.ZERO
		marker.visible = false
		move_and_slide()
		return
	if player == null or not player.alive:
		velocity = Vector3.ZERO
		move_and_slide()
		return
	# 教程 / 训练模式：站着面向玩家，不接近也不出手（被击打、积眩晕照常）。
	if passive:
		velocity = Vector3.ZERO
		marker.visible = false
		_face_player(delta)
		move_and_slide()
		return
	_timer -= delta
	_hesitate_cd = maxf(0.0, _hesitate_cd - delta)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_apply_flash(false)
	match state:
		State.ROAR:
			velocity = Vector3.ZERO
			_face_player(delta)
			if _timer <= 0.0:
				_enter_approach()
		State.APPROACH:
			_tick_approach(delta)
		State.HESITATE:
			velocity = Vector3.ZERO
			_face_player(delta)
			if _timer <= 0.0:
				_enter_approach()
		State.WINDUP:
			velocity = Vector3.ZERO
			var pulse := 1.0 + 0.05 * sin(_timer * 26.0)
			marker.scale = Vector3(_marker_radius * pulse, 1.0, _marker_radius * pulse)
			if _timer <= 0.0:
				_strike()
		State.STRIKE:
			_tick_strike(delta)
		State.RECOVER:
			velocity = Vector3.ZERO
			if _timer <= 0.0:
				_enter_approach()
		State.FAKE_DEATH:
			_tick_fake_death(delta)
	move_and_slide()
	position.y = 0

func _enter_approach() -> void:
	state = State.APPROACH

# ---------------------------------------------------------------- 行为

func _tick_approach(delta: float) -> void:
	var offset := player.global_position - global_position
	offset.y = 0
	var dist := offset.length()
	_strafe_clock -= delta
	if _strafe_clock <= 0.0:
		_strafe_clock = randf_range(1.5, 3.0)
		_strafe = 1.0 if randf() < 0.5 else -1.0
	var forward := offset.normalized() if dist > 0.1 else Vector3.FORWARD
	var side := Vector3(-forward.z, 0, forward.x) * _strafe
	# 大范围迂回绕侧：太远贴近、太近后撤、中距离横移找扑击角度
	var desired := Vector3.ZERO
	if dist > preferred_distance + 2.0:
		desired = forward
	elif dist < preferred_distance - 3.0:
		desired = -forward * 0.6
	else:
		desired = side * 0.8
	velocity = desired.normalized() * walk_speed if desired.length() > 0.01 else Vector3.ZERO
	_face_player(delta)
	# P1 嗅到预埋炸弹会迟疑一下，P2 狂暴后再不理会
	if phase == Phase.P1 and _hesitate_cd <= 0.0 and _bomb_nearby():
		state = State.HESITATE
		_timer = hesitate_time
		_hesitate_cd = 6.0
		velocity = Vector3.ZERO
		_update_label()
		return
	_attack_cd -= delta
	if _attack_cd <= 0.0:
		_choose_attack(dist)

## 附近有没有苏晓预埋的炸弹：巨虎嗅得到气味。
func _bomb_nearby() -> bool:
	for bomb in get_tree().get_nodes_in_group("alchemy_bombs"):
		if bomb is Node3D and bomb.global_position.distance_to(global_position) <= 9.0:
			return true
	return false

func _choose_attack(dist: float) -> void:
	var options := []
	if dist <= 7.0:
		options = ["claw", "stomp"]
	elif dist <= ATTACKS["pounce"]["reach"]:
		options = ["pounce"]
	if options.is_empty():
		return
	_begin_windup(options.pick_random())

func _begin_windup(name: String) -> void:
	var attack: Dictionary = ATTACKS[name]
	_current = name
	state = State.WINDUP
	_timer = attack["windup"] * _windup_scale
	_hit_done = false
	# 爪击锁在身前，其余锁在玩家当前位置：前摇结束前走出去就能躲开
	if name == "claw":
		var forward := (player.global_position - global_position)
		forward.y = 0
		_target_point = global_position + forward.normalized() * attack["offset"]
	else:
		_target_point = player.global_position
	_target_point.y = 0.05
	# 扑击与突袭都是朝落点冲刺，方向在这里一次性锁死
	if name == "pounce" or name == "ambush":
		_pounce_dir = _target_point - global_position
		_pounce_dir.y = 0
		_pounce_dir = _pounce_dir.normalized() if _pounce_dir.length() > 0.05 else Vector3.FORWARD
	_show_marker(_target_point, attack["radius"])
	if name == "ambush":
		# 装死暴起：先把身体立回来，再瞬间扑出去
		_tilt_body(0.0, 0.15)
		GameState.push_message("[科尔波山] 巨虎突然暴起，扑向靠近的猎手")

func _strike() -> void:
	var attack: Dictionary = ATTACKS[_current]
	if _current == "pounce" or _current == "ambush":
		state = State.STRIKE
		_timer = 0.42 if _current == "pounce" else 0.28
		_hit_done = false
		return
	_apply_area_damage(_target_point, attack["radius"], attack["damage"])
	_hide_marker()
	state = State.RECOVER
	_timer = attack["recover"] * _cooldown_scale
	_attack_cd = randf_range(1.2, 2.0) * _cooldown_scale

func _tick_strike(delta: float) -> void:
	var attack: Dictionary = ATTACKS[_current]
	velocity = _pounce_dir * charge_speed
	if not _hit_done and player.global_position.distance_to(global_position) <= attack["radius"] + hit_radius():
		_apply_area_damage(global_position, attack["radius"] + 1.0, attack["damage"])
		_hit_done = true
	if _timer > 0.0:
		return
	_apply_area_damage(_target_point, attack["radius"], attack["damage"])
	_hide_marker()
	# P2 起扑击打成二连，玩家必须连着躲两次
	if _current == "pounce" and _double_pounce and not _second_pounce:
		_second_pounce = true
		_begin_windup("pounce")
		return
	_second_pounce = false
	state = State.RECOVER
	_timer = attack["recover"] * _cooldown_scale
	_attack_cd = randf_range(1.4, 2.2) * _cooldown_scale

func _apply_area_damage(center: Vector3, radius: float, damage: float) -> void:
	var offset: Vector3 = player.global_position - center
	offset.y = 0
	if offset.length() <= radius:
		player.take_damage(damage)

func _face_player(delta: float) -> void:
	var offset := player.global_position - global_position
	offset.y = 0
	if offset.length() < 0.1:
		return
	# 模型正面朝 -Z，所以目标朝向取反
	var target_yaw := atan2(-offset.x, -offset.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, minf(1.0, delta * 3.0))

# ---------------------------------------------------------------- 阶段

func take_damage(amount: float, _knock_dir := Vector3.ZERO, _attacker: Node = null, true_damage := 0.0) -> void:
	if state == State.DEAD:
		return
	if _attacker is Node3D and not tendon_broken:
		var direction: Vector3 = (_attacker.global_position - global_position).normalized()
		if direction.dot(global_basis.z) > 0.35:
			tendon_hits += 1
			if tendon_hits >= 3:
				tendon_broken = true
				walk_speed *= 0.6
				charge_speed *= 0.65
				GameState.push_message("巨虎后腿筋腱受损，移动与扑击速度降低")
	hp = maxf(0.0, hp - maxf(0.0, amount) * (1.0 - clampf(physical_reduction, 0.0, 0.9)) - maxf(0.0, true_damage))
	_flash()
	_update_label()
	# 装死时被打：骗不到人，自己起身继续打
	if state == State.FAKE_DEATH:
		_rise()
	if hp <= 0.0:
		_die()
		return
	_check_phase()

func _check_phase() -> void:
	var ratio := hp / max_hp
	if phase == Phase.P1 and ratio <= P2_AT:
		_enter_phase(Phase.P2)
	elif phase == Phase.P2 and ratio <= P3_AT:
		_enter_phase(Phase.P3)

func _enter_phase(next: int) -> void:
	phase = next
	phase_changed.emit(phase, PHASE_TEXT[phase])
	_update_label()
	match phase:
		Phase.P2:
			# 受伤狂暴：前摇更短、出招更密、扑击二连，同时露出焦痕
			_windup_scale = 0.8
			_cooldown_scale = 0.65
			_double_pounce = true
			_show_wounds()
			GameState.push_message("[科尔波山] 陷阱重创了巨虎，它带着焦痕暴怒咆哮，攻势加快")
			state = State.ROAR
			_timer = 0.8
			velocity = Vector3.ZERO
		Phase.P3:
			_enter_fake_death()

func _enter_fake_death() -> void:
	state = State.FAKE_DEATH
	_timer = fake_death_time
	velocity = Vector3.ZERO
	_hide_marker()
	_tilt_body(1.15, 0.6)
	_update_label()
	GameState.push_message("[科尔波山] 巨虎轰然倒地，一动不动……")

func _tick_fake_death(delta: float) -> void:
	velocity = Vector3.ZERO
	var dist: float = player.global_position.distance_to(global_position)
	if dist <= ambush_range:
		_begin_windup("ambush")
		return
	if _timer <= 0.0:
		_rise()

## 装死被识破：起身继续打。
func _rise() -> void:
	_tilt_body(0.0, 0.4)
	state = State.RECOVER
	_timer = 0.5
	_attack_cd = 0.6
	_update_label()

func _die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	_hide_marker()
	collision_layer = 0
	collision_mask = 0
	_tilt_body(1.5, 0.9)
	label.text = "科尔波山之主  已被猎杀"
	defeated.emit()

# ---------------------------------------------------------------- 表现

func _show_marker(center: Vector3, radius: float) -> void:
	_marker_radius = radius
	marker.global_position = center + Vector3(0, 0.05, 0)
	marker.scale = Vector3(radius, 1.0, radius)
	marker.visible = true

func _hide_marker() -> void:
	marker.visible = false

## 受击闪白：只在状态切换时改一次颜色，不逐个网格建补间。
func _flash() -> void:
	_apply_flash(true)
	_flash_timer = 0.16

func _apply_flash(lit: bool) -> void:
	for child in body_part.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = child.material_override
			var base: Color = mat.get_meta("base_color", mat.albedo_color)
			mat.albedo_color = base.lightened(0.45) if lit else base

## 倒地 / 起身：侧翻的同时把身体沉下去，免得看着像悬在半空翻跟头。
func _tilt_body(angle: float, duration: float) -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(body_part, "rotation:z", angle, duration)
	tween.tween_property(body_part, "position:y", -angle * 1.1, duration)

func _update_label() -> void:
	var extra := "（迟疑）" if state == State.HESITATE else ""
	label.text = "科尔波山之主  [能量]  · %s%s" % [PHASE_TEXT[phase], extra]

func _build_marker() -> void:
	marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.03
	marker.mesh = disc
	marker_mat = StandardMaterial3D.new()
	marker_mat.albedo_color = Color(1, 0.16, 0.1, 0.34)
	marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = marker_mat
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.top_level = true
	marker.visible = false
	add_child(marker)

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.set_meta("base_color", color)
	return mat

func _part(label_name: String, at: Vector3, size: Vector3, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)
	return mesh

## 白盒巨虎：肩高 4.2 米、体长 7 米上下，形体靠躯干 + 四条粗腿 + 宽头巨吻撑出压迫感。
func _build_body() -> void:
	var hide_mat := _material(Color("c79a34"), 0.55)   # 深金黄厚毛，略降粗糙度做出油亮感
	var dark_mat := _material(Color("7d5f1f"), 0.75)
	var belly_mat := _material(Color("e2cd8e"), 0.6)
	_part("Torso", Vector3(0, 3.0, 0), Vector3(3.4, 2.4, 5.0), hide_mat, body_part)
	_part("Belly", Vector3(0, 1.95, 0.1), Vector3(3.0, 0.7, 4.6), belly_mat, body_part)
	for i in 4:
		_part("Stripe", Vector3(0, 4.06, -1.7 + i * 1.15), Vector3(3.45, 0.18, 0.3), dark_mat, body_part)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part("Leg", Vector3(sx * 1.25, 0.9, sz * 1.75), Vector3(0.85, 1.8, 0.85), dark_mat, body_part)
	_part("Head", Vector3(0, 3.35, -3.25), Vector3(2.4, 1.9, 2.3), hide_mat, body_part)
	_part("Snout", Vector3(0, 2.95, -4.45), Vector3(1.35, 1.0, 1.2), belly_mat, body_part)
	_part("Jaw", Vector3(0, 2.45, -4.5), Vector3(1.1, 0.45, 1.0), dark_mat, body_part)
	_part("Ear", Vector3(-0.78, 4.42, -3.0), Vector3(0.5, 0.62, 0.35), dark_mat, body_part)
	_part("Ear", Vector3(0.78, 4.42, -3.0), Vector3(0.5, 0.62, 0.35), dark_mat, body_part)
	_part("Tail", Vector3(0, 3.4, 3.5), Vector3(0.4, 0.4, 2.6), dark_mat, body_part)
	var eye_mat := _material(Color("ffd24d"), 0.4)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color("ffd24d")
	eye_mat.emission_energy_multiplier = 1.6
	_eye_mat = eye_mat
	_part("Eye", Vector3(-0.62, 3.55, -4.4), Vector3(0.3, 0.22, 0.12), eye_mat, body_part)
	_part("Eye", Vector3(0.62, 3.55, -4.4), Vector3(0.3, 0.22, 0.12), eye_mat, body_part)
	_build_wounds()

## 受伤态：焦黑毛皮、破损眼球、扎在体表的铁钉碎片，P2 起才显示。
func _build_wounds() -> void:
	wounds = Node3D.new()
	wounds.name = "Wounds"
	wounds.visible = false
	body_part.add_child(wounds)
	var char_mat := _material(Color("2b2318"), 0.95)
	var blood_mat := _material(Color("6e1a1a"), 0.8)
	var metal_mat := _material(Color("4c4a45"), 0.5)
	_part("Char", Vector3(-1.5, 3.6, -1.1), Vector3(0.9, 1.6, 1.9), char_mat, wounds)
	_part("Char", Vector3(1.35, 3.9, 0.7), Vector3(0.85, 1.3, 1.4), char_mat, wounds)
	_part("Char", Vector3(0.2, 2.2, 1.6), Vector3(1.7, 0.8, 1.1), char_mat, wounds)
	_part("EyeWound", Vector3(0.62, 3.5, -4.46), Vector3(0.42, 0.34, 0.16), blood_mat, wounds)
	for i in 5:
		_part("Nail", Vector3(-1.2 + i * 0.6, 4.15, -0.6 + (i % 2) * 1.6), Vector3(0.12, 0.45, 0.12), metal_mat, wounds)

func _show_wounds() -> void:
	wounds.visible = true
	_eye_mat.albedo_color = Color("6e1a1a")
	_eye_mat.set_meta("base_color", Color("6e1a1a"))  # 闪白恢复时要回到破损后的颜色
	_eye_mat.emission_energy_multiplier = 0.2
