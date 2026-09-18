extends CharacterBody3D
## P0 独立战斗试炼：所有动作通过同一时间轴推进，重置不遗留回调。
const BombScene := preload("res://scripts/combat/alchemy_bomb.tscn")
const Attributes := preload("res://data/attributes.gd")
const MAX_THROW := 11.0   # 数字 1 最远投掷距离
@export var move_speed: float = 5.0
## 活动范围：x 正负上限 / z 上下限。场景构建脚本按各自尺寸写入，默认是 P0 试炼的小场地。
@export var bounds_x: float = 12.0
@export var bounds_z: Vector2 = Vector2(-12.0, 12.0)
@export var acceleration: float = 14.0
@export var friction: float = 12.0
@export var max_hp: float = 100.0
@export var attack_damage: float = 16.0
@export var attack_range: float = 2.5
@export var attack_arc_half: float = 1.0
@export var combo_window: float = 0.75
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
var alive: bool = true
var invulnerable: bool = false
var input_dir := Vector2.ZERO
var facing := Vector3(0, 0, -1)
var combo_stage: int = -1
var combo_timer: float = 0.0
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
signal hp_changed(current: float, maximum: float)
signal bombs_changed(count: int)
signal attacked(stage: int)
signal hit_target(target: Node, dmg: float)
signal received_hit   # 受到伤害时触发（用于受击动画）
signal died

func _ready() -> void:
	add_to_group("player")
	shield_visual = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.85
	sphere.height = 1.7
	shield_visual.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.3, 0.22, 0.28)  # 能量护盾统一暗红，规避原作蓝光视觉
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_visual.material_override = material
	shield_visual.position.y = 0.85
	add_child(shield_visual)
	GameState.attributes_changed.connect(_refresh_derived_stats)
	reset()

func reset() -> void:
	_refresh_derived_stats()
	hp = max_hp
	mp = max_mp
	alive = true
	invulnerable = false
	dodging = false
	combo_stage = -1
	combo_timer = 0.0
	attack_cd = 0.0
	dodge_cd = 0.0
	dodge_timer = 0.0
	clash_cd = 0.0
	attack_elapsed = -1.0
	buffer_time = 0.0
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
	# 副手武器（燧发枪）由鼠标右键触发；旧 F 键方案已迁移（策划案 §3.3）。
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_fire_flintlock()
	if healing_time > 0:
		return
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
	if event.is_action_pressed("potion") and potions > 0 and hp < max_hp:
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
	shot_cd = maxf(0.0, shot_cd - delta)
	if healing_time > 0:
		healing_time -= delta
		velocity = Vector3.ZERO
		if healing_time <= 0:
			hp = minf(max_hp, hp + max_hp * 0.4 / float(healing_uses))
			hp_changed.emit(hp, max_hp)
		return
	input_dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	attack_cd = maxf(0, attack_cd - delta)
	dodge_cd = maxf(0, dodge_cd - delta)
	clash_cd = maxf(0, clash_cd - delta)
	combo_timer = maxf(0, combo_timer - delta)
	if combo_timer <= 0:
		combo_stage = -1
	mp = clampf(mp + (3.0 / 3600.0 if campaign_mode else 12.0) * delta, 0, max_mp)
	if Input.is_action_just_pressed("dodge") and dodge_cd <= 0 and attack_cd <= 0 and _is_grounded():
		dodging = true
		dodge_timer = dodge_duration
		dodge_cd = dodge_cooldown
		dodge_dir = Vector3(input_dir.x, 0, input_dir.y).normalized() if input_dir != Vector2.ZERO else facing
	if buffer_time > 0 and attack_cd <= 0 and not dodging:
		facing = buffered_direction
		buffer_time = 0
		_start_attack()
	buffer_time = maxf(0, buffer_time - delta)
	if attack_elapsed >= 0:
		attack_elapsed += delta
		if attack_elapsed >= ATTACK_HIT_TIME and not attack_hit:
			attack_hit = true
			_hurt_in_cone(attack_range + 0.3 * combo_stage, roll_attack_damage() * [1.0, 1.15, 1.8][combo_stage])
		if attack_cd <= 0:
			attack_elapsed = -1
	if input_dir != Vector2.ZERO and attack_cd <= 0 and not dodging:
		facing = Vector3(input_dir.x, 0, input_dir.y)
	if dodging:
		dodge_timer -= delta
		# 无敌帧只覆盖蓄力下蹲（按下即受保护），爆发后的规避靠高速位移本身
		invulnerable = dodge_duration - dodge_timer < DODGE_WINDUP
		if dodge_timer <= 0:
			dodging = false
			invulnerable = false
	var target := Vector3(input_dir.x, 0, input_dir.y) * move_speed * (0.35 if attack_cd > 0 else 1.0)
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
	combo_stage = 0 if combo_timer <= 0 else (combo_stage + 1) % 3
	combo_timer = combo_window
	attack_cd = base_attack_cooldown
	attack_elapsed = 0
	attack_hit = false
	attacked.emit(combo_stage)

func _hurt_in_cone(reach: float, damage: float) -> void:
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
		if offset.length() > 0.2 and offset.normalized().dot(facing) < cos(attack_arc_half):
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
		var was: bool = enemy.is_alive()
		enemy.take_damage(damage, facing * 6, self)
		hit_target.emit(enemy, damage)
		# 击杀判定 → 主武器耐久（普通 1 / 精英 3 / BOSS 8）
		if was and not enemy.is_alive() and campaign_mode:
			var wid := str(GameState.campaign.equipment.get("main_weapon", ""))
			if wid != "":
				var tier := int(enemy.get("kill_tier") if enemy.get("kill_tier") != null else 1)
				GameState.damage_item_dura(wid, GameState.Equip.kill_dur(tier))

## 玩家是否处于可拼刀的挥击窗口：出手到命中后一小段。敌人攻击在这期间落地则双方对拼。
func can_clash_now() -> bool:
	return clash_cd <= 0.0 and attack_elapsed >= 0.0 and attack_elapsed <= ATTACK_HIT_TIME + CLASH_WINDOW

## 拼刀已触发（玩家侧冷却与提示，玩家本次攻击与敌人攻击均不结算伤害）。
func register_clash() -> void:
	clash_cd = CLASH_COOLDOWN
	GameState.message.emit("拼刀！")

func take_damage(amount: float, _from_dir := Vector3.ZERO) -> void:
	if not alive or invulnerable:
		return
	healing_time = 0.0 # 受击打断饮用；消耗不返还。
	var final := amount
	if campaign_mode:
		# 结算链路（策划案 §4.2）：护甲百分比减免(③) → 肉体修正系数查表(④)
		final = amount * (1.0 - GameState.armor_reduction())
		final *= GameState.Equip.con_hit_factor(int(GameState.effective_attributes().get("con", Attributes.BASE)))
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
