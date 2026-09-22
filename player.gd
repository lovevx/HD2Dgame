extends CharacterBody3D
## P0 独立战斗试炼：所有动作通过同一时间轴推进，重置不遗留回调。
const BombScene := preload("res://scripts/combat/alchemy_bomb.tscn")
const Attributes := preload("res://data/attributes.gd")
const CombatSkills := preload("res://data/combat_skills.gd")
const SwordWave := preload("res://scripts/combat/sword_wave.gd")
## 前景遮挡淡出：镜头被房子、城墙挡住时把它们调成半透明（见该脚本头部说明）。
const OcclusionFade := preload("res://scripts/world/camera_occlusion_fade.gd")
const MAX_THROW := 11.0   # 数字 1 最远投掷距离
@export var move_speed: float = 2.6
## 跑步提速倍率：常驻移动模式就是跑步（2026-09-21 起不再区分 walk/run），
## 移动速度 = move_speed × 此倍率。1.6 时步频同步约 1.79 倍速像风火轮，降到 1.2 更自然。
@export var run_speed_factor: float = 1.2
## 活动范围：x 正负上限 / z 上下限。场景构建脚本按各自尺寸写入，默认是 P0 试炼的小场地。
@export var bounds_x: float = 12.0
@export var bounds_z: Vector2 = Vector2(-12.0, 12.0)
@export var acceleration: float = 14.0
@export var friction: float = 12.0
@export var max_hp: float = 100.0
@export var attack_damage: float = 16.0
@export var attack_range: float = 2.5
@export var attack_arc_half: float = 1.0
@export var base_attack_cooldown: float = 0.42
const ATTACK_HIT_TIME := 0.12   # 有效帧：挥出第 0.12 秒结算命中
const CLASH_WINDOW := 0.3       # 拼刀判定窗口：双方命中时刻相差 0.3 秒内视为重叠
const CLASH_COOLDOWN := 0.9     # 拼刀冷却：避免连续刷拼刀
@export var dodge_speed: float = 18.0
@export var dodge_duration: float = 0.55
@export var dodge_cooldown: float = 2.2
const DODGE_WINDUP := 0.15  # 蓄力下蹲：脚掌踩地借力，人物基本留在原地
const DODGE_STOP_TIME := 0.08  # 落地骤停：高速冲出后快速收住，避免平滑滑行
var hp: float = 100.0
var mp: float = 50.0
var max_mp: float = 50.0   # 派生值：智力×10；由 GameState.attributes 刷新
## 体力条：闪避（剃）与直踹共用这一条能量（见 data/combat_skills.gd 的 STAMINA_*）。
## 上限派生自「体力」属性（attributes.max_stamina），所以体力属性除 HP 外还有第二条用途。
var stamina: float = 120.0
var max_stamina: float = 120.0
var alive: bool = true
var invulnerable: bool = false
## 回合战门闩：为 true 时实时输入被 battle_controller 接管，本文件只提供"回合执行动作"入口。
var battle_mode := false
## 回合内面向：由 controller 在玩家行动前写入，战技/走位朝它出手。
var battle_turn_dir := Vector3.FORWARD
var kick_cd := 0.0
var input_dir := Vector2.ZERO
var running := true   # 常驻跑步：移动时恒为 true，不再需要 Shift（2026-09-21）
var facing := Vector3(0, 0, -1)
var combo_stage: int = 0
var attack_cd: float = 0.0
var dodging: bool = false
var dodge_timer: float = 0.0
var dodge_cd: float = 0.0
var dodge_dir := Vector3.ZERO
var potions: int = 2
var campaign_mode := false
var healing_time := 0.0
var healing_uses := 0
var shot_cd := 0.0
var bullets := 6
@export var bombs: int = 0   # 炼金炸弹库存，由关卡脚本发放（科尔波山两关各 3 颗）
var clash_cd: float = 0.0    # 拼刀冷却，触发拼刀后短时冷却防连刷
var attack_elapsed: float = -1.0
var attack_hit: bool = false
var buffer_time: float = 0.0
var buffered_direction := Vector3.ZERO
var shield_visual: MeshInstance3D
var hunter_active := false
var shield_hp := 0.0
var shield_timer := 0.0
var shield_cd := 0.0
var ring_cd := 0.0
var ring_windup := 0.0
var ring_lock := 0.0
var wave_cd := 0.0
var wave_windup := 0.0
var wave_direction := Vector3.FORWARD
var pierced_target: Node3D
var pierce_marker: MeshInstance3D
var pierce_timer := 0.0
var shadow_target: Node3D
var shadow_cd := 0.0
var shadow_windup := 0.0
signal hp_changed(current: float, maximum: float)
signal bombs_changed(count: int)
signal attacked(stage: int)
signal hit_target(target: Node, dmg: float)
## 命中了一个已经处于眩晕态的目标（山之主据此进入回合制，见 docs/COMBAT_DESIGN.md §2.2）。
signal struck_stunned_foe(foe: Node)
signal received_hit   # 受到伤害时触发（用于受击动画）
signal guarded       # 傲歌起手复用已有防御姿态帧
signal died

func _ready() -> void:
	add_to_group("player")
	shield_visual = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.7
	sphere.radial_segments = 12
	sphere.rings = 6
	shield_visual.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.3, 0.22, 0.18)  # 保留角色可读性的暗红晶体护盾
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(0.45, 0.05, 0.035)
	material.emission_energy_multiplier = 0.8
	shield_visual.material_override = material
	shield_visual.position.y = 0.85
	add_child(shield_visual)
	GameState.attributes_changed.connect(_refresh_derived_stats)
	# 前景遮挡淡出：挂在玩家身上，任何关卡都自动带上。
	var fade := OcclusionFade.new()
	fade.name = "CameraOcclusionFade"
	add_child(fade)
	reset()

func reset() -> void:
	_refresh_derived_stats()
	hp = max_hp
	mp = max_mp
	stamina = max_stamina
	alive = true
	invulnerable = false
	dodging = false
	combo_stage = 0
	attack_cd = 0.0
	dodge_cd = 0.0
	dodge_timer = 0.0
	clash_cd = 0.0
	attack_elapsed = -1.0
	attack_hit = false
	buffer_time = 0.0
	buffered_direction = Vector3.ZERO
	input_dir = Vector2.ZERO
	dodge_dir = Vector3.ZERO
	healing_time = 0.0
	healing_uses = 0
	shot_cd = 0.0
	hunter_active = false
	shield_hp = 0.0
	shield_timer = 0.0
	shield_cd = 0.0
	ring_cd = 0.0
	ring_windup = 0.0
	ring_lock = 0.0
	wave_cd = 0.0
	wave_windup = 0.0
	wave_direction = Vector3.FORWARD
	_clear_pierce()
	shadow_target = null
	shadow_cd = 0.0
	shadow_windup = 0.0
	potions = 2
	velocity = Vector3.ZERO
	shield_visual.visible = false
	$pivot/CharacterSprite.reset_visual()
	hp_changed.emit(hp, max_hp)

## 从全局六维属性刷新派生值：最大 HP = 50 + 体力×10；最大 MP = 智力×10；
## 移速 = 5 + (敏捷-5)×0.05；攻击 = 武器区间中点 × 力量倍率 × 刀术训练（面板期望值）。
func _refresh_derived_stats() -> void:
	var a: Dictionary = GameState.effective_attributes() if campaign_mode else GameState.attributes
	max_hp = Attributes.max_hp(a)
	max_mp = Attributes.max_mp(a)
	max_stamina = Attributes.max_stamina(a)
	stamina = minf(stamina, max_stamina)
	attack_damage = Attributes.attack(a)
	if campaign_mode:
		max_mp += GameState.campaign.permanent_mana
		var wid := str(GameState.campaign.equipment.get("main_weapon", ""))
		if wid != "":
			var w := _weapon_range(wid)
			attack_damage = (w.x + w.y) / 2.0 * GameState.Equip.str_atk_coef(int(a.get("str", Attributes.BASE))) * (1.0 + 0.1 * GameState.campaign.training)
	move_speed = Attributes.move_speed(a)
	# 属性被扣减或重置时，把当前值收进新上限，避免越界。
	hp = minf(hp, max_hp)
	mp = minf(mp, max_mp)
	hp_changed.emit(hp, max_hp)

## 武器强化后的攻击区间（x=min, y=max）：强化整体平移、宽度不变（策划案 §4.3）。
func _weapon_range(id: String) -> Vector2:
	var def: Dictionary = GameState.item_def(id)
	var minv := float(def.get("attack_min", 0.0))
	var maxv := float(def.get("attack_max", 0.0))
	var lvl := GameState.Campaign.enhance_level(GameState.campaign, id)
	var add := float(GameState.Equip.ATTACK_ADD_BY_TYPE.get(def.get("weapon_type", "1h_sword"), 1.5))
	return Vector2(minv + add * lvl, maxv + add * lvl)

## 攻击区间伪随机：双 roll 取平均（向中间集中，保留上下限可能）；严重受损区间减半且被动失效。
func _roll_range_damage(id: String) -> float:
	var r := _weapon_range(id)
	var roll := (randf_range(r.x, r.y) + randf_range(r.x, r.y)) / 2.0
	if GameState.is_item_broken(id):
		roll *= 0.5
	var a: Dictionary = GameState.effective_attributes()
	return roll * GameState.Equip.str_atk_coef(int(a.get("str", Attributes.BASE))) * (1.0 + 0.1 * GameState.campaign.training)

func roll_attack_damage() -> float:
	return _roll_range_damage(str(GameState.campaign.equipment.get("main_weapon", "")))

func _unhandled_input(event: InputEvent) -> void:
	if not alive or not is_physics_processing():
		return
	if battle_mode:
		return  # 回合战中按键由 battle_runner 的菜单处理，实时输入一律忽略
	# 副手武器（燧发枪）由鼠标右键触发；旧 F 键方案已迁移（策划案 §3.3）。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_fire_flintlock()
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_K:
		_start_kick()
	if healing_time > 0:
		return
	if event.is_action_pressed("hunter_toggle"):
		_toggle_hunter()
	if event.is_action_pressed("aoge"):
		_toggle_shield()
	if event.is_action_pressed("huanduan"):
		_start_ring()
	if event.is_action_pressed("sword_wave"):
		_start_wave()
	if event.is_action_pressed("shadow_stab"):
		_start_shadow()
	if event.is_action_pressed("attack"):
		# 攻击朝鼠标所指的地面方向出手
		var point = mouse_ground_point()
		if point != null:
			var direction: Vector3 = point - global_position
			direction.y = 0
			if direction.length() > 0.15:
				buffered_direction = direction.normalized()
				buffer_time = 0.15
	if event.is_action_pressed("bomb") and bombs > 0 and not dodging and attack_cd <= 0:
		_throw_bomb()
	if event.is_action_pressed("potion") and potions > 0 and hp < max_hp and ring_windup <= 0.0 and wave_windup <= 0.0 and shadow_windup <= 0.0:
		potions -= 1
		if campaign_mode:
			healing_time = 1.2
			healing_uses += 1
		else:
			hp = minf(max_hp, hp + 45.0)
		hp_changed.emit(hp, max_hp)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if battle_mode:
		velocity = Vector3.ZERO
		return  # 回合战中：实时移动/普攻/闪避/技能全部让位给 battle_runner
	shot_cd = maxf(0.0, shot_cd - delta)
	shield_cd = maxf(0.0, shield_cd - delta)
	ring_cd = maxf(0.0, ring_cd - delta)
	wave_cd = maxf(0.0, wave_cd - delta)
	shadow_cd = maxf(0.0, shadow_cd - delta)
	if pierce_timer > 0.0:
		pierce_timer -= delta
		if pierce_timer <= 0.0 or not is_instance_valid(pierced_target) or not pierced_target.is_alive():
			_clear_pierce()
	if shield_hp > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			_end_shield()
	if hunter_active:
		mp = maxf(0.0, mp - CombatSkills.HUNTER_DRAIN_PER_SECOND * delta)
		if mp <= max_mp * 0.01:
			hunter_active = false
			GameState.push_message("青钢影 · 法力不足，猎魔已关闭")
	if healing_time > 0:
		healing_time -= delta
		velocity = Vector3.ZERO
		if healing_time <= 0:
			hp = minf(max_hp, hp + max_hp * 0.4 / float(healing_uses))
			hp_changed.emit(hp, max_hp)
		return
	input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# 常驻跑步：移动时恒为跑步，不再按 Shift（run_speed_factor 就是常驻移速倍率）；
	# 攻击/闪避/饮用中不提速。
	running = input_dir.length_squared() > 0.001 \
		and attack_cd <= 0.0 and not dodging and healing_time <= 0.0
	attack_cd = maxf(0, attack_cd - delta)
	kick_cd = maxf(0.0, kick_cd - delta)
	dodge_cd = maxf(0, dodge_cd - delta)
	clash_cd = maxf(0, clash_cd - delta)
	ring_lock = maxf(0.0, ring_lock - delta)
	if ring_windup > 0.0:
		ring_windup -= delta
		if ring_windup <= 0.0:
			_resolve_ring()
	if wave_windup > 0.0:
		wave_windup -= delta
		if wave_windup <= 0.0:
			_release_wave()
	if shadow_windup > 0.0:
		shadow_windup -= delta
		if shadow_windup <= 0.0:
			_resolve_shadow()
	mp = clampf(mp + max_mp * CombatSkills.MP_REGEN_PER_SECOND * delta, 0, max_mp)
	stamina = clampf(stamina + CombatSkills.STAMINA_REGEN_PER_SECOND * delta, 0, max_stamina)
	if Input.is_action_just_pressed("dodge") and dodge_cd <= 0 and attack_cd <= 0 and _is_grounded() \
			and stamina >= CombatSkills.DODGE_STAMINA_COST:
		stamina -= CombatSkills.DODGE_STAMINA_COST
		dodging = true
		dodge_timer = dodge_duration
		dodge_cd = dodge_cooldown
		dodge_dir = world_move(input_dir).normalized() if input_dir != Vector2.ZERO else facing
	if buffer_time > 0 and attack_cd <= 0 and not dodging:
		facing = buffered_direction
		buffer_time = 0
		_start_attack()
	buffer_time = maxf(0, buffer_time - delta)
	if attack_elapsed >= 0:
		attack_elapsed += delta
		if attack_elapsed >= CombatSkills.COMBO_HIT_TIMES[combo_stage] and not attack_hit:
			attack_hit = true
			_hurt_in_cone(attack_range + CombatSkills.COMBO_REACH_BONUS[combo_stage], roll_attack_damage() * CombatSkills.COMBO_MULTIPLIERS[combo_stage], CombatSkills.COMBO_ARC_HALF[combo_stage], CombatSkills.STUN_ON_ATTACK)
		if attack_cd <= 0:
			attack_elapsed = -1
	if input_dir != Vector2.ZERO and attack_cd <= 0 and not dodging:
		facing = world_move(input_dir)
	if dodging:
		dodge_timer -= delta
		# 无敌帧只覆盖蓄力下蹲（按下即受保护），爆发后的规避靠高速位移本身
		invulnerable = dodge_duration - dodge_timer < DODGE_WINDUP
		if dodge_timer <= 0:
			dodging = false
			invulnerable = false
	var target := world_move(input_dir) * move_speed * (run_speed_factor if running else 1.0) * (0.35 if attack_cd > 0 else 1.0)
	if ring_lock > 0.0:
		target = Vector3.ZERO
	if campaign_mode and hp / max_hp < 0.1:
		target *= 0.6
	if dodging:
		# 剃的速度曲线：蓄力段留在原地 → 瞬间满速爆发 → 落地骤停，三段制造爆发对比
		var elapsed_dodge := dodge_duration - dodge_timer
		var dodge_speed_factor: float
		if elapsed_dodge < DODGE_WINDUP:
			dodge_speed_factor = 0.0  # 蓄力下蹲：踩地借力，人还没动
		elif elapsed_dodge < dodge_duration - DODGE_STOP_TIME:
			dodge_speed_factor = 1.0  # 爆发冲刺：一步到位满速
		else:
			dodge_speed_factor = lerpf(1.0, 0.0, (elapsed_dodge - (dodge_duration - DODGE_STOP_TIME)) / DODGE_STOP_TIME)
		velocity = dodge_dir * dodge_speed * dodge_speed_factor
	else:
		velocity = velocity.lerp(target, minf(1, acceleration * delta))
	move_and_slide()
	_clamp_to_bounds()

## 把 WASD 的输入向量按机位朝向转成世界方向：W 永远朝画面深处走（远离镜头）。
## 机位转到 180° 之后 W 依旧往画面上方走，不会把角色往画面下方送。
## 长度保持输入长度（键盘为 1；摇杆半推就是半速），所以不额外归一化。
func world_move(input: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(input.x, 0, input.y)
	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() < 0.0001 or right.length_squared() < 0.0001:
		return Vector3(input.x, 0, input.y)
	return forward.normalized() * (-input.y) + right.normalized() * input.x

## 把世界方向转回"以机位为北"的视角系，供八方向动画取图。
## 动作的屏幕语义只跟按键有关：W 永远该播"背对镜头往画面深处走"的那张图，
## 与角色此刻实际朝世界哪边走无关。机位为空时原样返回（退回世界朝向口径）。
func view_dir(world_dir: Vector3) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return world_dir
	var forward := -camera.global_basis.z
	var right := camera.global_basis.x
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() < 0.0001 or right.length_squared() < 0.0001:
		return world_dir
	forward = forward.normalized()
	right = right.normalized()
	return Vector3(world_dir.dot(right), 0.0, -world_dir.dot(forward))

## 鼠标所指的地面点（y=0 平面）；射线打不到地面时返回 null。攻击方向与炸弹落点共用它。
func mouse_ground_point():
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var mouse := get_viewport().get_mouse_position()
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))

## 活动范围由关卡场景写入（各场景尺寸不同），默认沿用 P0 试炼的小场地。
func _clamp_to_bounds() -> void:
	position = Vector3(clampf(position.x, -bounds_x, bounds_x), 0, clampf(position.z, bounds_z.x, bounds_z.y))

## 剃必须踩实体地面借力：悬空、半空状态不能释放。
func _is_grounded() -> bool:
	return is_on_floor() or global_position.y <= 0.05

## 数字 1：把炼金炸弹扔向鼠标所指的地面，落地后成为可预埋的陷阱。
func _throw_bomb() -> void:
	var point = mouse_ground_point()
	if point == null:
		return
	var target: Vector3 = point
	target.y = 0.06
	var offset := target - global_position
	offset.y = 0
	# 太远够不着就压到最大投掷距离，太近就丢在身前，避免扔在脚下
	if offset.length() > MAX_THROW:
		target = global_position + offset.normalized() * MAX_THROW
		target.y = 0.06
	elif offset.length() < 1.0:
		target = global_position + facing * 2.5
		target.y = 0.06
	bombs -= 1
	bombs_changed.emit(bombs)
	var bomb := BombScene.instantiate()
	get_parent().add_child(bomb)
	bomb.global_position = global_position + Vector3(0, 1.1, 0)
	bomb.throw_to(target)

func _start_attack() -> void:
	combo_stage = 0
	attack_cd = CombatSkills.COMBO_COOLDOWNS[0]
	attack_elapsed = 0
	attack_hit = false
	attacked.emit(0)

## 野战战技·直踢（K 键）：即时挥踢，复用图集 kick 帧；命中附眩晕（P2 眩晕条接入后生效）。
signal kicked

func _start_kick() -> void:
	if kick_cd > 0.0 or stamina < CombatSkills.KICK_STAMINA_COST or dodging or battle_mode or attack_cd > 0.0:
		return
	stamina -= CombatSkills.KICK_STAMINA_COST
	kick_cd = CombatSkills.KICK_COOLDOWN
	attack_cd = 0.9
	attack_elapsed = -1.0
	buffer_time = 0.0
	# 前向短判定：命中叠 25 点眩晕；若目标已在眩晕态则直接处决（docs/COMBAT_DESIGN.md §1.4）。
	_hurt_in_cone(2.8, roll_attack_damage() * CombatSkills.KICK_MULTIPLIER, 0.35, CombatSkills.KICK_STUN, true)
	kicked.emit()

## ---------- 回合战执行入口（battle_runner 调用，不以按键驱动） ----------

## 回合移动：沿 battle_turn_dir 步进 move 米。
## 走 move_and_collide（物理查询）而不是直接改 global_position —— 直接赋值会穿墙；
## 旧实现还顺手把 y 拍成 0，接上真有高低差的地图后会把玩家压进地里。
## 撞上就停在接触点（move_and_collide 不滑动）；够不到目标由场景提示"距离不够"。
func battle_execute_move(move: float) -> void:
	if move <= 0.001:
		return
	if battle_turn_dir.length_squared() > 0.001:
		facing = battle_turn_dir
	var step := facing
	step.y = 0.0
	if step.length_squared() < 0.001:
		return
	move_and_collide(step.normalized() * move)

## 回合攻击：扇形判定（reach + 弧半角）；侧/背击乘数由 controller 传入。
func battle_execute_attack(bonus_mult := 1.0) -> void:
	_hurt_in_cone(attack_range + CombatSkills.COMBO_REACH_BONUS[0],
		roll_attack_damage() * CombatSkills.COMBO_MULTIPLIERS[0] * bonus_mult,
		CombatSkills.COMBO_ARC_HALF[0])
	attacked.emit(0)

## 回合战技（battle_runner 调用）：**扣完蓝立即结算**，只吃 MP 与「这一回合」这个门闩。
##
## 为什么不复用实时的 _start_wave / _start_ring：battle_mode 下 _physics_process 直接 return，
## ring_cd / wave_cd / *_windup 一个都不走，旧入口的后遗症是
##   ① 刀芒扣了 12 点蓝，但前摇（wave_windup）永远到不了点 → 伤害从不结算；
##   ② 被设成 2.5 的 wave_cd 再不递减 → 第二次选刀芒被静默拦掉，整场只能"放"一次；
##   ③ 环断直调 _resolve_ring()，干脆不扣蓝。
## 返回 false = 蓝不够（场景据此提示），true = 已出手。
func battle_execute_skill(skill: String) -> bool:
	if battle_turn_dir.length_squared() > 0.001:
		facing = battle_turn_dir
	match skill:
		"sword_wave":
			if mp < CombatSkills.WAVE_MP_COST:
				return false
			mp -= CombatSkills.WAVE_MP_COST
			wave_direction = facing
			attack_elapsed = -1.0
			attacked.emit(0)
			_release_wave()
			return true
		"ring":
			if mp < CombatSkills.RING_MP_COST:
				return false
			mp -= CombatSkills.RING_MP_COST
			attack_elapsed = -1.0
			attacked.emit(0)
			_resolve_ring()
			return true
		_:
			push_warning("battle skill not wired: " + skill)
			return false

## 回合道具：药剂即时回 40% / 炸弹原地 AoE。
func battle_execute_item(item: String) -> void:
	match item:
		"potion":
			if potions <= 0:
				return
			potions -= 1
			hp = minf(max_hp, hp + max_hp * 0.4)
			hp_changed.emit(hp, max_hp)
		"bomb":
			if bombs <= 0:
				return
			bombs -= 1
			bombs_changed.emit(bombs)
			var b := BombScene.instantiate()
			get_parent().add_child(b)
			b.global_position = global_position + Vector3(0, 1.1, 0)
			(b as Node3D).place_at(global_position + battle_turn_dir * 5.0)
		_:
			push_warning("battle item not wired: " + item)

func _start_wave(forward := Vector3.ZERO) -> void:
	if wave_cd > 0.0 or attack_cd > 0.0 or dodging or mp < CombatSkills.WAVE_MP_COST:
		return
	var direction: Vector3 = forward
	if direction.length_squared() < 0.01:
		var point = mouse_ground_point()
		if point != null:
			direction = point - global_position
	direction.y = 0.0
	if direction.length_squared() < 0.01:
		direction = facing
	wave_direction = direction.normalized()
	facing = wave_direction
	mp -= CombatSkills.WAVE_MP_COST
	wave_cd = CombatSkills.WAVE_COOLDOWN
	wave_windup = CombatSkills.WAVE_WINDUP
	attack_cd = base_attack_cooldown
	attack_elapsed = -1.0
	buffer_time = 0.0
	attacked.emit(0)

func _release_wave() -> void:
	var wave := SwordWave.new()
	wave.configure(self, wave_direction, roll_attack_damage() * CombatSkills.WAVE_WEAPON_MULTIPLIER)
	get_parent().add_child(wave)
	wave.global_position = global_position + wave_direction * 1.2

func _mark_pierced(enemy: Node3D) -> void:
	_clear_pierce()
	pierced_target = enemy
	pierce_timer = CombatSkills.PIERCE_WINDOW
	pierce_marker = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	pierce_marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.04, 0.04)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.04, 0.04)
	pierce_marker.material_override = mat
	pierce_marker.position.y = 5.6 if enemy.has_method("hit_radius") else 2.5
	enemy.add_child(pierce_marker)

func _clear_pierce() -> void:
	if is_instance_valid(pierce_marker):
		pierce_marker.queue_free()
	pierce_marker = null
	pierced_target = null
	pierce_timer = 0.0

func _start_shadow() -> void:
	# 没有前刺命中标记时完全空放：不扣蓝、不进入冷却。
	if not is_instance_valid(pierced_target) or not pierced_target.is_alive() or pierce_timer <= 0.0:
		return
	if global_position.distance_to(pierced_target.global_position) > CombatSkills.SHADOW_MAX_DISTANCE:
		_clear_pierce()
		return
	if shadow_cd > 0.0 or dodging or mp < CombatSkills.SHADOW_MP_COST:
		return
	shadow_target = pierced_target
	_clear_pierce()
	mp -= CombatSkills.SHADOW_MP_COST
	shadow_cd = CombatSkills.SHADOW_COOLDOWN
	shadow_windup = CombatSkills.SHADOW_WINDUP
	attack_elapsed = -1.0
	attack_cd = maxf(attack_cd, 0.24)
	buffer_time = 0.0

func _resolve_shadow() -> void:
	var target := shadow_target
	shadow_target = null
	if not is_instance_valid(target) or not target.is_alive() or global_position.distance_to(target.global_position) > CombatSkills.SHADOW_MAX_DISTANCE:
		mp = minf(max_mp, mp + CombatSkills.SHADOW_MP_COST)
		shadow_cd = 0.0
		return
	var bonus := CombatSkills.SHADOW_TRUE_DAMAGE if target.get("has_energy") == true else 0.0
	_damage_target(target, roll_attack_damage() * CombatSkills.SHADOW_WEAPON_MULTIPLIER, Vector3.ZERO, bonus)
	_show_shadow_fx(target.global_position)

func _show_shadow_fx(at: Vector3) -> void:
	var holder := Node3D.new()
	get_parent().add_child(holder)
	holder.global_position = at + Vector3.UP * 0.85
	for i in 6:
		var spike := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.bottom_radius = 0.11
		mesh.height = 1.3
		spike.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.025, 0.035, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(0.65, 0.04, 0.04)
		spike.material_override = mat
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := TAU * i / 6.0
		spike.position = Vector3(cos(angle) * 0.28, 0, sin(angle) * 0.28)
		spike.rotation = Vector3(sin(angle) * 0.65, 0, cos(angle) * 0.65)
		holder.add_child(spike)
	holder.scale = Vector3.ONE * 0.1
	var tween := create_tween()
	tween.tween_property(holder, "scale", Vector3.ONE, 0.12)
	tween.tween_property(holder, "scale", Vector3.ONE * 0.05, 0.22)
	tween.tween_callback(holder.queue_free)

func _toggle_hunter() -> void:
	if hunter_active:
		hunter_active = false
		GameState.push_message("青钢影 · 猎魔关闭")
	elif mp > max_mp * 0.01:
		hunter_active = true
		GameState.push_message("青钢影 · 猎魔开启")

func _toggle_shield() -> void:
	if shield_hp > 0.0:
		_end_shield()
		return
	if shield_cd > 0.0 or mp < CombatSkills.SHIELD_MP_COST or dodging:
		return
	mp -= CombatSkills.SHIELD_MP_COST
	shield_hp = CombatSkills.shield_capacity(int(GameState.effective_attributes().get("int", Attributes.BASE)))
	shield_timer = CombatSkills.SHIELD_DURATION
	shield_cd = CombatSkills.SHIELD_COOLDOWN
	shield_visual.visible = true
	guarded.emit()
	GameState.push_message("傲歌 · 护盾 %.0f" % shield_hp)

func _end_shield() -> void:
	shield_hp = 0.0
	shield_timer = 0.0
	shield_visual.visible = false

func _start_ring() -> void:
	if ring_cd > 0.0 or attack_cd > 0.0 or dodging or mp < CombatSkills.RING_MP_COST:
		return
	mp -= CombatSkills.RING_MP_COST
	ring_cd = CombatSkills.RING_COOLDOWN
	ring_windup = CombatSkills.RING_WINDUP
	ring_lock = CombatSkills.RING_RECOVERY
	attack_cd = CombatSkills.RING_RECOVERY
	buffer_time = 0.0
	attacked.emit(0)  # 复用单段斩击帧，命中仍按环断时间轴结算

func _resolve_ring() -> void:
	var damage := roll_attack_damage() * CombatSkills.RING_WEAPON_MULTIPLIER
	var foes := get_tree().get_nodes_in_group("enemies")
	foes.append_array(get_tree().get_nodes_in_group("targets"))
	for enemy in foes:
		if not enemy.is_alive():
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0.0
		var bulk := float(enemy.hit_radius()) if enemy.has_method("hit_radius") else 0.0
		if offset.length() > CombatSkills.RING_RADIUS + bulk:
			continue
		_damage_target(enemy, damage, offset.normalized() * 5.0)
	_show_ring_fx()

func _show_ring_fx() -> void:
	var fx := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.92
	mesh.outer_radius = 1.0
	fx.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.07, 0.06, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.65, 0.07, 0.05)
	fx.material_override = mat
	fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(fx)
	fx.global_position = global_position + Vector3(0, 0.12, 0)
	fx.scale = Vector3(0.25, 1.0, 0.25)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(fx, "scale", Vector3(CombatSkills.RING_RADIUS, 1.0, CombatSkills.RING_RADIUS), 0.27)
	tween.tween_property(fx, "transparency", 1.0, 0.27)
	tween.chain().tween_callback(fx.queue_free)

func _damage_target(enemy: Node, damage: float, knock_dir: Vector3, true_damage := 0.0, stun_amount := 0.0, execute := false) -> void:
	var was: bool = enemy.is_alive()
	# 眩晕态被直踹命中 = 处决击杀（docs/COMBAT_DESIGN.md §1.4）。
	var executed: bool = execute and was and enemy.has_method("is_stunned") and enemy.is_stunned() \
			and enemy.has_method("apply_execution")
	if executed:
		enemy.apply_execution()
	else:
		enemy.take_damage(damage, knock_dir, self, true_damage)
	# 命中回蓝：每次打到敌人回复最大法力的 1%（炸弹等不经本函数的伤害不计）。
	mp = minf(max_mp, mp + max_mp * CombatSkills.MP_ON_HIT_RATIO)
	hit_target.emit(enemy, damage + true_damage)
	if was and not enemy.is_alive() and campaign_mode:
		var wid := str(GameState.campaign.equipment.get("main_weapon", ""))
		if wid != "":
			var tier := int(enemy.get("kill_tier") if enemy.get("kill_tier") != null else 1)
			GameState.damage_item_dura(wid, GameState.Equip.kill_dur(tier))
	# 眩晕：即时战斗的平A / 直踹命中都叠；回合内的攻击走默认 0（回合内不再积累）。
	if not executed and stun_amount > 0.0 and enemy.is_alive() and enemy.has_method("add_stun"):
		enemy.add_stun(stun_amount)
	# 打到"本来就已经眩晕"的目标 → 通知场景（山之主据此进入回合制）。
	if was and enemy.is_alive() and enemy.has_method("is_stunned") and enemy.is_stunned():
		struck_stunned_foe.emit(enemy)

func _hurt_in_cone(reach: float, damage: float, arc_half := -1.0, stun_amount := 0.0, execute := false) -> void:
	var foes := get_tree().get_nodes_in_group("enemies")
	# 纯靶子挂在 targets 组，不进敌人组（不影响清场判定），但吃同样的近战判定。
	foes.append_array(get_tree().get_nodes_in_group("targets"))
	for enemy in foes:
		if not enemy.is_alive():
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0
		# 巨虎这类大体积目标带判定半径，不然要贴到身体中心才能打到
		var bulk := 0.0
		if enemy.has_method("hit_radius"):
			bulk = enemy.hit_radius()
		if offset.length() > reach + bulk:
			continue
		var used_arc: float = arc_half if arc_half >= 0.0 else attack_arc_half
		if offset.length() > 0.2 and offset.normalized().dot(facing) < cos(used_arc):
			continue
		# 拼刀：对方近战攻击正处在出手窗口内（其命中时刻与我们相差 ≤ CLASH_WINDOW），
		# 本次双方都不结算伤害，敌人被弹开并进入短硬直。
		if clash_cd <= 0.0 and enemy.has_method("can_be_clashed") and enemy.can_be_clashed() \
				and enemy.has_method("is_strike_imminent") and enemy.is_strike_imminent():
			register_clash()
			enemy.on_clash(offset.normalized() if offset.length() > 0.01 else facing)
			continue
		# 拼刀刚触发后短免疫：防止敌人先手判定拼刀后，玩家本段攻击的后续命中帧再补刀
		if enemy.has_method("is_clash_immune") and enemy.is_clash_immune():
			continue
		var bonus := 0.0
		if hunter_active and enemy.get("has_energy") == true and enemy.get("max_hp") != null:
			bonus = float(enemy.get("max_hp")) * CombatSkills.HUNTER_TRUE_RATIO
		_damage_target(enemy, damage, facing * 6, bonus, stun_amount, execute)
		# 单段斩击即普攻全部：每次命中都留影缝标记，保住影刺技能的前置
		if attack_elapsed >= 0.0 and enemy.is_alive():
			_mark_pierced(enemy)

## 玩家是否处于可拼刀的挥击窗口：出手到命中后一小段。敌人攻击在这期间落地则双方对拼。
func can_clash_now() -> bool:
	return clash_cd <= 0.0 and attack_elapsed >= 0.0 and attack_elapsed <= CombatSkills.COMBO_HIT_TIMES[combo_stage] + CLASH_WINDOW

## 拼刀已触发（玩家侧冷却与提示，玩家本次攻击与敌人攻击均不结算伤害）。
func register_clash() -> void:
	clash_cd = CLASH_COOLDOWN
	GameState.message.emit("拼刀！")

func take_damage(amount: float, _from_dir := Vector3.ZERO) -> void:
	if not alive or invulnerable:
		return
	healing_time = 0.0 # 受击打断饮用；消耗不返还。
	var final := maxf(0.0, amount)
	if campaign_mode:
		# 结算链路（策划案 §4.2）：护甲百分比减免(③) → 肉体修正系数查表(④)
		final *= 1.0 - GameState.armor_reduction()
		final *= GameState.Equip.con_hit_factor(int(GameState.effective_attributes().get("con", Attributes.BASE)))
	if shield_hp > 0.0:
		var absorbed := minf(shield_hp, final)
		shield_hp -= absorbed
		final -= absorbed
		if shield_hp <= 0.0:
			_end_shield()
			GameState.push_message("傲歌 · 护盾破碎")
	var before := hp
	hp = maxf(0, hp - final)
	hp_changed.emit(hp, max_hp)
	received_hit.emit()
	if campaign_mode and final > 0:
		# 护甲耐久：实际扣血 /10 向上取整，最低 1，单次上限 5（简化版 §6.3.1）
		var lost := before - hp
		if lost > 0:
			var cost := clampi(ceili(lost / 10.0), 1, 5)
			_spend_armor_dura(cost)
	if hp <= 0:
		alive = false
		_clear_pierce()
		hunter_active = false
		shield_hp = 0.0
		shield_visual.visible = false
		died.emit()

## 按护甲槽位扣耐久：本次命中只扣一件护甲（取第一件带耐久且未损毁的）。
func _spend_armor_dura(cost: int) -> void:
	for slot in GameState.campaign.equipment.keys():
		var id := str(GameState.campaign.equipment[slot])
		var def: Dictionary = GameState.item_def(id)
		if def.get("item_kind", "") != "armor":
			continue
		if GameState.is_item_broken(id):
			continue
		GameState.damage_item_dura(id, cost)
		return

func _fire_flintlock() -> void:
	# 副手槽必须装备燧发枪（右键使用）；旧 F 键已迁移。
	if GameState.campaign.equipment.get("offhand", "") != "flintlock" or bullets <= 0 or shot_cd > 0 or healing_time > 0 or dodging:
		return
	var point = mouse_ground_point()
	if point == null:
		return
	var direction: Vector3 = point - global_position
	direction.y = 0
	if direction.length() < 0.1:
		return
	bullets -= 1
	shot_cd = 1.8
	facing = direction.normalized()
	var nearest: Node3D = null
	var distance := 22.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_alive():
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0
		if offset.length() < distance and offset.normalized().dot(facing) > 0.92:
			nearest = enemy
			distance = offset.length()
	if nearest:
		# 枪械攻击区间（2-13）双 roll，击杀判定 → 副手武器耐久
		var was: bool = nearest.is_alive()
		nearest.take_damage(_roll_range_damage("flintlock"), facing * 3, self)
		if was and not nearest.is_alive() and campaign_mode:
			var tier := int(nearest.get("kill_tier") if nearest.get("kill_tier") != null else 1)
			GameState.damage_item_dura("flintlock", GameState.Equip.kill_dur(tier))
	GameState.push_message("燧发枪发射 · 剩余弹药 %d" % bullets)
