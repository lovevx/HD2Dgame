extends CharacterBody3D
const GameAudio := preload("res://data/game_audio.gd")
## 科尔波山之主（巨型变异巨虎）：能量型精英 BOSS。
## P1 完整霸主 → P2 受伤狂暴（65%）→ P3 残血诈死偷袭（25%）。
## 所有招式都先在地面亮红圈预警再结算，玩家能用剃位移或岩石掩体规避。
## 巨虎使用 2D 像素精灵，战斗碰撞与攻击判定仍由 3D 身体负责。

signal phase_changed(index: int, text: String)
signal defeated
const CombatSkills := preload("res://data/combat_skills.gd")
## 头顶眩晕条（scripts/combat/stun_gauge.gd）。显式 preload，不依赖编辑器全局类缓存。
const StunGaugeScript := preload("res://scripts/combat/stun_gauge.gd")
const STUN_DURATION := 2.0
const TIGER_P1_SHEET := preload("res://assets/enemies/directions/runtime/colpo_tiger_clean_8dir.png")
const TIGER_P2_SHEET := preload("res://assets/enemies/directions/runtime/colpo_tiger_wounded_8dir.png")
const TIGER_DIRECTIONS: Array[String] = [
	"down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left",
]
## 3×3 atlas: down-left/down/down-right, left/empty/right, up-left/up/up-right.
const TIGER_DIRECTION_CELLS := {
	"down_left": Vector2i(0, 0), "down": Vector2i(1, 0), "down_right": Vector2i(2, 0),
	"left": Vector2i(0, 1), "right": Vector2i(2, 1),
	"up_left": Vector2i(0, 2), "up": Vector2i(1, 2), "up_right": Vector2i(2, 2),
}
## 每张 3×3 图集按 TIGER_DIRECTIONS 顺序记录脚底锚点（像素）。
const TIGER_P1_GROUND_OFFSETS: Array[float] = [207.0, 197.0, 156.0, 155.0, 138.0, 155.0, 156.0, 196.0]
const TIGER_P2_GROUND_OFFSETS: Array[float] = [209.0, 209.0, 160.0, 135.0, 153.0, 135.0, 160.0, 209.0]

enum Phase { P1, P2, P3 }
enum State { ROAR, APPROACH, HESITATE, WINDUP, STRIKE, RECOVER, FAKE_DEATH, DEAD }

const PHASE_TEXT := {Phase.P1: "P1 完整霸主", Phase.P2: "P2 受伤狂暴", Phase.P3: "P3 残血诈死"}
const P2_AT := 0.65
const P3_AT := 0.25  # P2 锁血线；P3 入场改由时间触发

## 招式表：前摇 / 伤害 / 预警圈半径 / 触发距离 / 爪击前伸偏移 / 后摇
const ATTACKS := {
	"claw": {"windup": 0.55, "damage": 22.0, "radius": 4.6, "reach": 7.0, "offset": 3.4, "recover": 0.85},
	"stomp": {"windup": 0.80, "damage": 26.0, "radius": 7.0, "reach": 9.5, "offset": 0.0, "recover": 1.00},
	"pounce": {"windup": 0.65, "damage": 30.0, "radius": 3.4, "reach": 21.0, "offset": 0.0, "recover": 1.00},
	"ambush": {"windup": 0.35, "damage": 32.0, "radius": 5.5, "reach": 6.0, "offset": 0.0, "recover": 1.10},
}

@export var max_hp: float = 650.0
@export var walk_speed: float = 5.0
@export var charge_speed: float = 21.0
@export var preferred_distance: float = 6.0
@export var hesitate_time: float = 1.0
@export var ambush_range: float = 6.5  # 以身体中心算：正面约离身体 2.8 米就够触发暴起偷袭
@export_range(5.0, 120.0, 1.0) var p3_delay: float = 30.0  # 进入 P2 后的战斗时间，之后转入 P3 诈死
@export_range(30.0, 180.0, 1.0) var evacuation_duration: float = 60.0
@export_range(5.0, 60.0, 1.0) var evacuation_rise_after: float = 30.0

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
var body_part: Node3D
var tiger_sprite: Sprite3D
var _tiger_direction_textures: Dictionary = {}
var _tiger_ground_offsets: Array[float] = []
var _tiger_direction := "down"

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
var _p2_elapsed := 0.0
var _evacuation_active := false
var _evacuation_elapsed := 0.0
var _evacuation_risen := false
var _marker_radius := 1.0
var _flash_timer := 0.0
var tendon_hits := 0
var tendon_broken := false

## ---------- 即时战斗硬直 ----------
## 满值时 Boss 停止行动一小段时间，然后眩晕条清空并继续实时战斗。
var stun := 0.0
var stun_max := CombatSkills.STUN_MAX
var _stun_gauge: Node3D = null
var _stun_timer := 0.0

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
	GameAudio.play_sfx("boss_roar", global_position)

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

func is_evacuation_active() -> bool:
	return _evacuation_active

func evacuation_seconds_left() -> float:
	return maxf(0.0, evacuation_duration - _evacuation_elapsed)

func evacuation_has_risen() -> bool:
	return _evacuation_risen

func cancel_evacuation() -> void:
	_evacuation_active = false

func confirm_evacuation_kill() -> bool:
	if not _evacuation_active or _evacuation_risen or state != State.FAKE_DEATH:
		return false
	_evacuation_active = false
	hp = 0.0
	_update_label()
	_die()
	return true

## 当前正在前摇或结算的招式名。
func current_attack() -> String:
	return _current

## 叠加眩晕；满值后 Boss 短暂硬直，随后恢复即时行动。
## **不衰减**（作者 2026-09-22 定，与 enemy.gd 同口径）。
func add_stun(amount: float) -> void:
	if not is_alive() or amount <= 0.0 or is_stunned():
		return
	stun = minf(stun_max, stun + amount)
	_update_stun_gauge()
	if is_stunned():
		_stun_timer = STUN_DURATION
		_attack_cd = STUN_DURATION
		if state != State.FAKE_DEATH:
			state = State.RECOVER
			_current = ""
			velocity = Vector3.ZERO
			_hide_marker()
		GameState.push_message("科尔波山之主陷入短暂硬直")

func is_stunned() -> bool:
	return is_alive() and stun >= stun_max

## 硬直结束时清空眩晕（这不是衰减，是状态重置）。
func clear_stun() -> void:
	stun = 0.0
	_stun_timer = 0.0
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

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	if phase == Phase.P2 and is_instance_valid(player) and player.alive:
		_p2_elapsed += delta
		if _p2_elapsed >= p3_delay:
			_enter_phase(Phase.P3)
	if _evacuation_active and is_instance_valid(player) and player.alive:
		_evacuation_elapsed = minf(evacuation_duration, _evacuation_elapsed + delta)
		if not _evacuation_risen and _evacuation_elapsed >= minf(evacuation_rise_after, evacuation_duration):
			_rise_for_evacuation()
		if _evacuation_elapsed >= evacuation_duration:
			_evacuation_active = false
			GameState.push_message("撤离时间结束 · 巨虎仍在战斗")
	# 满眩晕时给玩家实时输出窗口，结束后清空眩晕并恢复 AI。
	if is_stunned() and state != State.FAKE_DEATH:
		_stun_timer = maxf(0.0, _stun_timer - delta)
		_attack_cd = maxf(0.0, _attack_cd - delta)
		if _stun_timer <= 0.0:
			clear_stun()
			state = State.APPROACH
			_current = ""
			_timer = 0.0
		velocity = Vector3.ZERO
		marker.visible = false
		move_and_slide()
		return
	if player == null or not player.alive:
		velocity = Vector3.ZERO
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
			velocity = Vector3.ZERO
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
	if dist <= 3.0:
		options = ["claw"]
	elif dist <= 8.0:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var is_behind := to_player.length_squared() > 0.001 and global_basis.z.normalized().dot(to_player.normalized()) > 0.35
		options = ["stomp"] if is_behind else ["pounce"]
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
	GameAudio.play_sfx("enemy_attack", global_position, -5.0, 0.8)
	if name == "ambush":
		# 装死暴起：先把身体立回来，再瞬间扑出去
		_tilt_body(0.0, 0.15)
		if not _evacuation_risen:
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
	if not _hit_done:
		_apply_area_damage(_target_point, attack["radius"], attack["damage"])
		_hit_done = true
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
	_update_tiger_sprite_direction()

# ---------------------------------------------------------------- 阶段

func take_damage(amount: float, _knock_dir := Vector3.ZERO, _attacker: Node = null, true_damage := 0.0) -> void:
	if state == State.DEAD:
		return
	if state == State.FAKE_DEATH and _evacuation_active:
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
	var damage := maxf(0.0, amount) * (1.0 - clampf(physical_reduction, 0.0, 0.9)) + maxf(0.0, true_damage)
	var hp_floor := 0.0
	if phase == Phase.P1:
		hp_floor = max_hp * P2_AT
	elif phase == Phase.P2:
		hp_floor = max_hp * P3_AT
	hp = maxf(hp_floor, hp - damage)
	_flash()
	_update_label()
	if hp <= 0.0:
		_die()
		return
	_check_phase()

func _check_phase() -> void:
	var ratio := hp / max_hp
	if phase == Phase.P1 and ratio <= P2_AT:
		_enter_phase(Phase.P2)

func _enter_phase(next: int) -> void:
	phase = next
	match phase:
		Phase.P2:
			# 受伤狂暴：前摇更短、出招更密、扑击二连，同时露出焦痕
			_p2_elapsed = 0.0
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
	phase_changed.emit(phase, PHASE_TEXT[phase])
	_update_label()

func _enter_fake_death() -> void:
	state = State.FAKE_DEATH
	_timer = 0.0
	_evacuation_active = true
	_evacuation_elapsed = 0.0
	_evacuation_risen = false
	velocity = Vector3.ZERO
	_hide_marker()
	label.hide()
	_tilt_body(1.15, 0.6)
	GameState.push_message("[科尔波山] 巨虎轰然倒地 · %d 秒内返回灰潮港" % int(ceil(evacuation_duration)))
	GameAudio.play_sfx("boss_roar", global_position, -5.0, 0.86)

func _rise_for_evacuation() -> void:
	_evacuation_risen = true
	_tilt_body(0.0, 0.4)
	state = State.APPROACH
	_timer = 0.0
	_current = ""
	velocity = Vector3.ZERO
	_hide_marker()
	label.show()
	_update_label()
	GameState.push_message("[科尔波山] 巨虎突然站起 · 剩余 %d 秒撤离" % int(ceil(evacuation_seconds_left())))
	if is_stunned():
		state = State.RECOVER
		_timer = 0.4
		return
	var dist := player.global_position.distance_to(global_position)
	if dist <= ambush_range:
		_begin_windup("ambush")
	else:
		_attack_cd = 0.0

func _die() -> void:
	_evacuation_active = false
	state = State.DEAD
	velocity = Vector3.ZERO
	label.show()
	_hide_marker()
	collision_layer = 0
	collision_mask = 0
	_tilt_body(1.5, 0.9)
	label.text = "科尔波山之主  已被猎杀"
	GameAudio.play_sfx("quest_complete", global_position)
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
	if tiger_sprite != null:
		tiger_sprite.modulate = Color(1.8, 1.8, 1.8) if lit else Color.WHITE

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

## 底图为无伤形态；P2 会切换为同姿势的受伤图。
func _build_body() -> void:
	_create_tiger_sprite(TIGER_P1_SHEET, TIGER_P1_GROUND_OFFSETS)

func _build_tiger_direction_textures(sheet: Texture2D) -> Dictionary:
	var cell_width := int(sheet.get_width() / 3.0)
	var cell_height := int(sheet.get_height() / 3.0)
	var textures: Dictionary = {}
	for direction in TIGER_DIRECTIONS:
		var cell: Vector2i = TIGER_DIRECTION_CELLS[direction]
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(cell.x * cell_width, cell.y * cell_height, cell_width, cell_height)
		textures[direction] = atlas
	return textures

func _create_tiger_sprite(sheet: Texture2D, ground_offsets: Array[float]) -> void:
	_tiger_direction_textures = _build_tiger_direction_textures(sheet)
	_tiger_ground_offsets = ground_offsets
	tiger_sprite = Sprite3D.new()
	tiger_sprite.name = "TigerSprite"
	tiger_sprite.texture = _tiger_direction_textures["down"]
	tiger_sprite.pixel_size = 0.0125
	tiger_sprite.offset = Vector2(0, _tiger_ground_offsets[0])
	tiger_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tiger_sprite.shaded = true
	tiger_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	tiger_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	body_part.add_child(tiger_sprite)
	_update_tiger_sprite_direction()

func _show_wounds() -> void:
	_tiger_direction_textures = _build_tiger_direction_textures(TIGER_P2_SHEET)
	_tiger_ground_offsets = TIGER_P2_GROUND_OFFSETS
	tiger_sprite.texture = _tiger_direction_textures[_tiger_direction]
	tiger_sprite.offset.y = _tiger_ground_offsets[TIGER_DIRECTIONS.find(_tiger_direction)]

func _update_tiger_sprite_direction() -> void:
	if tiger_sprite == null or _tiger_direction_textures.is_empty():
		return
	var facing := -global_basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return
	var view_direction := facing
	if is_instance_valid(player) and player.has_method("view_dir"):
		view_direction = player.call("view_dir", facing)
	var index := int(round(atan2(view_direction.x, view_direction.z) / (PI / 4.0))) % 8
	if index < 0:
		index += 8
	var direction := TIGER_DIRECTIONS[index]
	if direction == _tiger_direction:
		return
	_tiger_direction = direction
	tiger_sprite.texture = _tiger_direction_textures[direction]
	tiger_sprite.offset.y = _tiger_ground_offsets[index]
