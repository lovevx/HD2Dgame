extends CharacterBody3D
signal defeated
const CombatSkills := preload("res://data/combat_skills.gd")
## 头顶眩晕条（scripts/battle/stun_gauge.gd）。用显式 preload 而不是全局类名，
## 这样不依赖编辑器的全局类缓存，命令行跑回归也能解析。
const StunGaugeScript := preload("res://scripts/battle/stun_gauge.gd")
## 敌人：红色预警圈锁定位置，前摇结束后才结算；远程威胁共用范围攻击。
## kind 为 CUSTOM 时完全沿用试炼里的导出参数（近战 / 远程占位敌人）；
## 其余 kind 走 PROFILES：野狼、野猪为能量型，肉体傀儡为无能量实验体
## —— 青钢影的真实伤害对它无效，白盒阶段靠这个区分来验证苏晓的弱点。

enum Kind { CUSTOM, WOLF, BOAR, GOLEM, DUMMY, HUMAN }

## 人形敌人（HUMAN）外观查表：按 model key 取肤色/衣着/武器/体型。
## 数值仍由关卡（campaign.gd）写入，这里只负责白盒模型的样子。
const HUMAN_PROFILES := {
	"vagrant": {"name": "持械流民", "color": Color("8a7662"), "trim": Color("574a3c"),
		"weapon": "dagger", "energy": true, "tall": 1.0},
	"carlos": {"name": "黑市商人·卡洛斯", "color": Color("4a4a58"), "trim": Color("2b2b34"),
		"weapon": "dagger", "energy": true, "tall": 1.05},
	"instructor": {"name": "考核教官", "color": Color("5d6a86"), "trim": Color("3a4255"),
		"weapon": "sword", "energy": true, "tall": 1.08},
	"oka": {"name": "布兰登·欧卡", "color": Color("6b3f3a"), "trim": Color("3a2320"),
		"weapon": "sword", "energy": true, "tall": 1.1},
	"guard": {"name": "欧卡护卫", "color": Color("6e7262"), "trim": Color("40423a"),
		"weapon": "spear", "energy": true, "tall": 1.03},
}

## color 是主体毛色，trim 是四肢/头部等暗部；energy 决定头顶有没有能量核。
## 2026-09-19 整体降速：玩家移速 5.0→2.6，敌人速度同比例下调（约 0.52 倍）以保持相对快慢。
## reach / keep 是距离不是速度，保持不变。
const PROFILES := {
	Kind.WOLF: {
		"name": "野狼", "hp": 34.0, "speed": 1.7, "damage": 10.0, "reach": 2.3,
		"windup": 0.5, "keep": 1.6, "color": Color("8fa0bb"), "trim": Color("59647a"), "energy": true,
	},
	Kind.BOAR: {
		"name": "野猪", "hp": 72.0, "speed": 1.25, "damage": 16.0, "reach": 2.4,
		"windup": 0.75, "keep": 1.6, "color": Color("a9643c"), "trim": Color("67381f"), "energy": true,
	},
	Kind.GOLEM: {
		"name": "肉体傀儡", "hp": 58.0, "speed": 0.95, "damage": 18.0, "reach": 2.4,
		"windup": 0.85, "keep": 1.7, "color": Color("9a8fb5"), "trim": Color("5d5670"), "energy": false,
	},
	## 纯靶子：血量极高且打不坏（见 take_damage），站桩不动、永不攻击。
	Kind.DUMMY: {
		"name": "练功木桩", "hp": 9999.0, "speed": 0.0, "damage": 0.0, "reach": 0.0,
		"windup": 0.0, "keep": 0.0, "color": Color("c8a15c"), "trim": Color("7a5a2f"), "energy": false,
	},
}

@export var max_hp: float = 48.0
@export_range(0.0, 0.9, 0.05) var physical_reduction: float = 0.0
@export var move_speed: float = 1.2
@export var ranged: bool = false
@export var kind: Kind = Kind.CUSTOM
## 人形敌人（Kind.HUMAN）的外观档位：见 HUMAN_PROFILES。空串 = 保持默认近战守卫。
@export var model: String = ""

var has_energy: bool = true
var hp_: float
var dead: bool = false
var attack_cd: float = 1.2
var windup: float = -1.0
var target_point := Vector3.ZERO
var knock := Vector3.ZERO
var player: Node3D
var marker: MeshInstance3D
var health_label: Label3D
var material: StandardMaterial3D
var body_root: Node3D          # 白盒模型容器；CUSTOM 占位敌人不建模型，沿用胶囊
var enemy_name := "近战守卫"
var attack_damage := 14.0
var kill_tier: int = 1   # 击杀武器耐久档：普通 1 / 精英 3 / BOSS 8（策划案 §6.3.1）
var attack_reach := 2.5
var attack_windup := 0.65
var keep_distance := 1.6
var _flash_timer := 0.0
var stun_timer: float = 0.0          # 拼刀硬直：被弹开期间不能行动
var clash_immune_timer: float = 0.0  # 拼刀后短暂免疫再次判定，与玩家冷却配合防双判
var _arm_weapon: Node3D              # 人形敌人右臂（含武器），前摇举刀/出手挥击靠它
var _strike_timer := 0.0             # 挥击动作计时：出手后 0.22 秒内完成劈下-回摆
## 回合战驱动门闩：开时实时 AI 让位给 battle_controller，由 battle_advance() 步进。
var battle_driven := false
## 游荡巡逻（练习场演示用）：只绕出生点慢速转圈，永不攻击。
var patrol_only := false
var _patrol_home := Vector3.ZERO
var _patrol_setup := false
var _patrol_angle := 0.0
## ---------- 眩晕条（即时战斗的破绽资源，见 docs/COMBAT_DESIGN.md §1.4） ----------
## 打满 → 停止移动；此时用直踹命中即处决。木桩不吃眩晕。
var stun := 0.0
var stun_max := CombatSkills.STUN_MAX
var _stun_gauge: Node3D = null
const CLASH_WINDOW := 0.3   # 与 player.gd 拼刀窗口一致：双方命中时刻相差 ≤ 0.3 秒视为重叠
const CLASH_STUN := 0.8     # 拼刀硬直时长
const CLASH_REPEL := 8.0    # 拼刀弹开初速度
const CLASH_IMMUNE := 0.35  # 拼刀后免疫时长

func _ready() -> void:
	# 纯靶子不进 enemies 组，避免被试炼/波次的“清怪”逻辑算作存活敌人。
	if kind == Kind.DUMMY:
		add_to_group("targets")
	else:
		add_to_group("enemies")
	var body_color := Color("ce6654")
	var trim_color := Color("7a3a30")
	if ranged:
		enemy_name = "远程威胁"
		attack_damage = 18.0
		attack_reach = 9.0
		attack_windup = 0.95
		keep_distance = 6.0
		body_color = Color("a56fe0")
		trim_color = Color("5f3d84")
	var profile: Dictionary = PROFILES.get(kind, {})
	if not profile.is_empty():
		enemy_name = profile["name"]
		max_hp = profile["hp"]
		move_speed = profile["speed"]
		attack_damage = profile["damage"]
		attack_reach = profile["reach"]
		attack_windup = profile["windup"]
		keep_distance = profile["keep"]
		has_energy = profile["energy"]
		body_color = profile["color"]
		trim_color = profile["trim"]
	# 人形敌人：数值由关卡写入，这里只接管名字/颜色/能量，按 model 搭白盒模型。
	var human: Dictionary = HUMAN_PROFILES.get(model, {}) if kind == Kind.HUMAN else {}
	if not human.is_empty():
		enemy_name = human["name"]
		body_color = human["color"]
		trim_color = human["trim"]
		has_energy = human["energy"]
	hp_ = max_hp
	player = get_tree().get_first_node_in_group("player")
	material = StandardMaterial3D.new()
	material.albedo_color = body_color
	$MeshInstance3D.material_override = material
	if kind != Kind.CUSTOM:
		# 有白盒模型的敌人把占位胶囊藏起来，只留它当碰撞参考
		$MeshInstance3D.visible = false
		_build_body(body_color, trim_color)
	if kind != Kind.CUSTOM and has_energy:
		_add_energy_core()  # 无能量肉体傀儡不挂能量核，一眼区分两类敌人
	if kind == Kind.DUMMY:
		# 靶子不显示“无能量”标签，读作一个可击打的木桩即可
		enemy_name = "练功木桩"
	health_label = Label3D.new()
	health_label.position.y = 2.25
	health_label.font_size = 40
	health_label.pixel_size = 0.008
	health_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(health_label)
	_update_health()
	marker = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.65
	disc.bottom_radius = 1.65
	disc.height = 0.025
	marker.mesh = disc
	var warning := StandardMaterial3D.new()
	warning.albedo_color = Color(1, 0.2, 0.12, 0.4)
	warning.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = warning
	add_child(marker)
	marker.top_level = true
	marker.visible = false

## 能量型敌人头顶挂一颗发光能量核，无能量肉体傀儡没有：一眼区分两类敌人。
func _add_energy_core() -> void:
	var core := MeshInstance3D.new()
	core.name = "EnergyCore"
	var sphere := SphereMesh.new()
	sphere.radius = 0.15
	sphere.height = 0.3
	core.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("63d6ff")
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color("63d6ff")
	glow.emission_energy_multiplier = 2.4
	core.material_override = glow
	core.position = Vector3(0, 1.9, 0)  # 悬在头顶，不与上方的血量标签打架
	add_child(core)

# ---------------------------------------------------------------- 白盒模型

## 三种小怪的白盒形体：野狼低伏细长、野猪矮壮带獠牙、肉体傀儡是佝偻人形。
## 统一朝 -Z 为正面（朝向由 _physics_process 里的转向负责）。
func _build_body(color: Color, trim: Color) -> void:
	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	match kind:
		Kind.WOLF:
			_build_wolf(color, trim)
		Kind.BOAR:
			_build_boar(color, trim)
		Kind.GOLEM:
			_build_golem(color, trim)
		Kind.DUMMY:
			_build_dummy(color, trim)
		Kind.HUMAN:
			var human: Dictionary = HUMAN_PROFILES.get(model, {})
			_build_human(color, trim, str(human.get("weapon", "dagger")), float(human.get("tall", 1.0)))

func _build_wolf(color: Color, trim: Color) -> void:
	var fur := _material(color, 0.8)
	var dark := _material(trim, 0.85)
	_part("Torso", Vector3(0, 0.78, 0.05), Vector3(0.62, 0.62, 1.5), fur)
	_part("Chest", Vector3(0, 0.86, -0.55), Vector3(0.68, 0.64, 0.5), fur)
	_part("Neck", Vector3(0, 0.95, -0.86), Vector3(0.42, 0.44, 0.4), fur)
	_part("Head", Vector3(0, 1.02, -1.14), Vector3(0.46, 0.44, 0.5), fur)
	_part("Snout", Vector3(0, 0.92, -1.48), Vector3(0.26, 0.24, 0.34), dark)
	_part("EarL", Vector3(-0.17, 1.28, -1.0), Vector3(0.12, 0.2, 0.08), dark)
	_part("EarR", Vector3(0.17, 1.28, -1.0), Vector3(0.12, 0.2, 0.08), dark)
	_part("Tail", Vector3(0, 0.98, 0.9), Vector3(0.14, 0.14, 0.6), dark)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part("Leg", Vector3(sx * 0.24, 0.25, sz * 0.5), Vector3(0.16, 0.5, 0.16), dark)

func _build_boar(color: Color, trim: Color) -> void:
	var hide := _material(color, 0.85)
	var dark := _material(trim, 0.9)
	_part("Torso", Vector3(0, 0.76, 0.1), Vector3(0.86, 0.8, 1.6), hide)
	_part("Hump", Vector3(0, 1.22, -0.3), Vector3(0.7, 0.3, 0.9), dark)
	_part("Head", Vector3(0, 0.72, -1.05), Vector3(0.62, 0.56, 0.6), hide)
	_part("Snout", Vector3(0, 0.62, -1.44), Vector3(0.36, 0.32, 0.42), dark)
	_part("TuskL", Vector3(-0.19, 0.62, -1.62), Vector3(0.09, 0.1, 0.3), _material(Color("e6ddc4"), 0.5))
	_part("TuskR", Vector3(0.19, 0.62, -1.62), Vector3(0.09, 0.1, 0.3), _material(Color("e6ddc4"), 0.5))
	_part("EarL", Vector3(-0.26, 1.02, -1.1), Vector3(0.12, 0.2, 0.1), dark)
	_part("EarR", Vector3(0.26, 1.02, -1.1), Vector3(0.12, 0.2, 0.1), dark)
	for i in 4:
		_part("Bristle", Vector3(0, 1.26, -0.85 + i * 0.45), Vector3(0.1, 0.22, 0.1), dark)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_part("Leg", Vector3(sx * 0.3, 0.21, sz * 0.55), Vector3(0.2, 0.42, 0.2), dark)

func _build_golem(color: Color, trim: Color) -> void:
	var flesh := _material(color, 0.9)
	var dark := _material(trim, 0.95)
	_part("Hips", Vector3(0, 0.5, 0), Vector3(0.56, 0.42, 0.46), dark)
	_part("Torso", Vector3(0, 1.02, 0.06), Vector3(0.72, 0.86, 0.5), flesh)
	_part("Chest", Vector3(0, 1.34, 0.02), Vector3(0.8, 0.34, 0.54), dark)
	_part("Head", Vector3(0, 1.62, 0.12), Vector3(0.42, 0.44, 0.44), flesh)
	_part("Jaw", Vector3(0, 1.42, 0.24), Vector3(0.3, 0.16, 0.3), dark)
	for sx in [-1.0, 1.0]:
		_part("UpperArm", Vector3(sx * 0.5, 1.16, 0.08), Vector3(0.2, 0.5, 0.22), flesh)
		_part("Forearm", Vector3(sx * 0.52, 0.66, 0.12), Vector3(0.18, 0.5, 0.2), dark)
		_part("Thigh", Vector3(sx * 0.19, 0.52, 0), Vector3(0.24, 0.5, 0.26), flesh)
		_part("Shin", Vector3(sx * 0.19, 0.16, 0.02), Vector3(0.22, 0.32, 0.24), dark)

## 练功木桩：十字形站桩，横杆当手臂、圆木当躯干，顶上挂一块红色圆靶。
func _build_dummy(color: Color, trim: Color) -> void:
	var wood := _material(color, 0.8)
	var dark := _material(trim, 0.9)
	var red := _material(Color("c0533d"), 0.6)
	_part("Base", Vector3(0, 0.14, 0), Vector3(1.1, 0.28, 1.1), dark)
	_part("Post", Vector3(0, 0.8, 0), Vector3(0.4, 1.05, 0.4), wood)
	_part("ArmL", Vector3(-0.75, 1.05, 0), Vector3(1.1, 0.14, 0.4), wood)
	_part("ArmR", Vector3(0.75, 1.05, 0), Vector3(1.1, 0.14, 0.4), wood)
	_part("Head", Vector3(0, 1.62, 0), Vector3(0.44, 0.44, 0.44), wood)
	_part("Bullseye", Vector3(0, 0.95, 0.26), Vector3(0.2, 0.36, 0.06), red)

## 人形敌人（流民/卡洛斯/教官/欧卡/护卫）：四肢+躯干+头的方块拼装。
## 右手持武器，_arm_weapon 是右手引用——前摇举刀、出手挥击都靠它旋转。
func _build_human(color: Color, trim: Color, weapon: String, tall: float) -> void:
	var cloth := _material(color, 0.9)
	var dark := _material(trim, 0.95)
	var skin := _material(Color("e0b48c"), 0.65)
	# 腿
	for sx in [-1.0, 1.0]:
		_part("Leg", Vector3(sx * 0.2, 0.36 * tall, 0), Vector3(0.2, 0.72 * tall, 0.22), dark)
	# 躯干
	_part("Hips", Vector3(0, 0.82 * tall, 0), Vector3(0.56, 0.3, 0.34), dark)
	_part("Torso", Vector3(0, 1.18 * tall, 0), Vector3(0.62, 0.66, 0.4), cloth)
	_part("Chest", Vector3(0, 1.5 * tall, -0.04), Vector3(0.66, 0.3, 0.44), cloth)
	# 头 + 兜帽/头发（暗部）
	_part("Head", Vector3(0, 1.84 * tall, 0.02), Vector3(0.4, 0.38, 0.4), skin)
	_part("Hood", Vector3(0, 1.98 * tall, 0), Vector3(0.46, 0.2, 0.46), dark)
	# 左手（垂在身侧）
	_part("ArmL", Vector3(-0.42, 1.34 * tall, 0), Vector3(0.18, 0.56 * tall, 0.2), cloth)
	# 右手：单独节点便于旋转，武器挂在它下面
	_arm_weapon = Node3D.new()
	_arm_weapon.name = "ArmWeapon"
	_arm_weapon.position = Vector3(0.42, 1.34 * tall, 0)
	body_root.add_child(_arm_weapon)
	var hand := MeshInstance3D.new()
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.18, 0.56 * tall, 0.2)
	hand.mesh = arm_mesh
	hand.material_override = cloth
	hand.position = Vector3(0, -0.28 * tall, 0)
	_arm_weapon.add_child(hand)
	_build_human_weapon(weapon, tall)
	# 初始举刀姿态：右手略抬，接近警戒位
	_arm_weapon.rotation_degrees.x = 18.0

## 右手上的武器：匕首 / 单手剑 / 长枪，挂在高举的前臂下。
func _build_human_weapon(weapon: String, tall: float) -> void:
	var steel := _material(Color("cdd6de"), 0.35)
	var grip := _material(Color("6a4a30"), 0.8)
	var blade: Vector3
	var grip_len: float
	match weapon:
		"dagger":
			blade = Vector3(0.1, 0.5, 0.08)
			grip_len = 0.16
		"spear":
			blade = Vector3(0.09, 1.5, 0.09)
			grip_len = 0.18
		_:
			blade = Vector3(0.12, 0.9, 0.1)
			grip_len = 0.18
	var blade_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = blade * Vector3(1, tall, 1)
	blade_mesh.mesh = bm
	blade_mesh.material_override = steel
	blade_mesh.position = Vector3(0, -0.42 * tall - blade.y * tall * 0.5, 0)
	_arm_weapon.add_child(blade_mesh)
	var grip_mesh := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.09, grip_len * tall, 0.09)
	grip_mesh.mesh = gm
	grip_mesh.material_override = grip
	grip_mesh.position = Vector3(0, -0.3 * tall, 0)
	_arm_weapon.add_child(grip_mesh)

## 前摇举刀：右手从警戒位抬高到头顶，同时身体微微后仰蓄力。
## 出手挥击：右手快速劈下再回警戒位——攻击动作跟红圈一起表达，不再只有红圈。
func _animate_arm(delta: float) -> void:
	if _arm_weapon == null:
		return
	if windup >= 0.0:
		var t := clampf(1.0 - windup / maxf(0.01, attack_windup), 0.0, 1.0)
		_arm_weapon.rotation_degrees.x = lerpf(18.0, -115.0, ease(t, 0.55))
		body_root.rotation_degrees.x = lerpf(body_root.rotation_degrees.x, -4.0, minf(1.0, delta * 8.0))
	elif _strike_timer > 0.0:
		_strike_timer -= delta
		var phase := 1.0 - _strike_timer / 0.22
		if phase < 0.5:
			# 前 0.11 秒：从头顶快速劈下到身前
			_arm_weapon.rotation_degrees.x = lerpf(-115.0, 55.0, phase * 2.0)
		else:
			# 后 0.11 秒：回摆到警戒位
			_arm_weapon.rotation_degrees.x = lerpf(55.0, 18.0, (phase - 0.5) * 2.0)
		body_root.rotation_degrees.x = lerpf(body_root.rotation_degrees.x, 0.0, minf(1.0, delta * 10.0))
	else:
		body_root.rotation_degrees.x = lerpf(body_root.rotation_degrees.x, 0.0, minf(1.0, delta * 6.0))

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.set_meta("base_color", color)  # 受击闪光要回到原色
	return mat

func _part(label_name: String, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	body_root.add_child(mesh)
	return mesh

## 受击闪光：模型敌人逐个网格改色，CUSTOM 占位敌人沿用胶囊自发光。
func _flash() -> void:
	if body_root == null:
		material.emission_enabled = true
		material.emission = Color(0.65, 0.4, 0.3)
		var flash := create_tween()
		flash.tween_property(material, "emission", Color.BLACK, 0.16)
		return
	_flash_timer = 0.16
	_apply_flash(true)

func _apply_flash(lit: bool) -> void:
	for child in body_root.get_children():
		if child is MeshInstance3D and child.material_override is StandardMaterial3D:
			var mat: StandardMaterial3D = child.material_override
			var base: Color = mat.get_meta("base_color", mat.albedo_color)
			mat.albedo_color = base.lightened(0.45) if lit else base

func is_alive() -> bool:
	return not dead

## 教程 / 训练用：直接设定血量上限并回满（覆盖 PROFILES 的档位血量）。
## 教程场需要敌人活到眩晕条打满，否则还没学会攒眩晕就被打死了。
func set_max_hp(value: float) -> void:
	max_hp = maxf(1.0, value)
	hp_ = max_hp
	dead = false
	_update_health()

## 是否为可拼刀目标：近战且在蓄力，剩余命中时刻不超过拼刀窗口（玩家此刻命中它即判定对拼）。
func is_strike_imminent() -> bool:
	return not ranged and windup > 0.0 and windup <= CLASH_WINDOW

func can_be_clashed() -> bool:
	return clash_immune_timer <= 0.0

## 拼刀刚触发后的一小段时间：本次双方都不结算伤害，也阻止玩家该段攻击后续帧补刀。
func is_clash_immune() -> bool:
	return clash_immune_timer > 0.0

## 拼刀命中：取消本次出手、被弹开并进入短硬直，预警圈提前收起。
func on_clash(repel_dir := Vector3.FORWARD) -> void:
	if dead:
		return
	windup = -1.0
	if marker != null:
		marker.visible = false
	stun_timer = CLASH_STUN
	clash_immune_timer = CLASH_IMMUNE
	knock = repel_dir.normalized() * CLASH_REPEL
	attack_cd = maxf(attack_cd, 1.4)

## 出手落地瞬间：玩家若正处在挥击窗口则双方对拼（本次都不结算伤害），返回是否已判拼刀。
func _resolve_strike() -> bool:
	if ranged or clash_immune_timer > 0.0 or not is_instance_valid(player):
		return false
	if player.has_method("can_clash_now") and player.can_clash_now():
		player.register_clash()
		on_clash(global_position - player.global_position)
		return true
	return false

## 游荡巡逻：绕出生点慢速转圈（练习场演示用）。
func _patrol(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if not _patrol_setup:
		_patrol_home = global_position
		_patrol_setup = true
	_patrol_angle += dt * 0.4
	var target := _patrol_home + Vector3(cos(_patrol_angle) * 1.6, 0, sin(_patrol_angle) * 1.6)
	global_position = global_position.move_toward(target, move_speed * 0.6 * dt)
	if body_root != null:
		body_root.rotation_degrees.y = lerpf(body_root.rotation_degrees.y, 0.0, dt * 4.0)

## 回合战步进（battle_controller 驱动）：决定并执行"接近 / 攻击"，返回意图文本供 AT 栏用。
func battle_advance(target_world: Vector3) -> String:
	if kind == Kind.DUMMY or dead:
		return "待机"
	var flat := target_world - global_position
	flat.y = 0.0
	var dist := flat.length()
	if dist <= attack_reach * 0.9:
		return "攻击"
	var step := move_speed * 1.0
	var dir: Vector3 = flat.normalized() if dist > 0.01 else Vector3.FORWARD
	global_position += dir * minf(step, dist - attack_reach * 0.9)
	if body_root != null:
		body_root.rotation_degrees.y = lerpf(body_root.rotation_degrees.y, rad_to_deg(atan2(dir.x, -dir.z)), 0.25)
	return "接近"

## ---------- 眩晕与处决 ----------

## 叠加眩晕。已满值时不再叠加（避免溢出后反复触发）。木桩 / 已死不吃。
## **眩晕不衰减**（作者 2026-09-22 定）：打满就一直保持，直到被直踹处决。
func add_stun(amount: float) -> void:
	if dead or kind == Kind.DUMMY or amount <= 0.0:
		return
	if is_stunned():
		return
	stun = minf(stun_max, stun + amount)
	_update_stun_gauge()

func is_stunned() -> bool:
	return not dead and stun >= stun_max

## 眩晕态即处决窗口（小怪适用；山之主是另一套实现，见 boss_colpo.gd）。
func executable() -> bool:
	return is_stunned()

## 处决：直接击杀，走正常的 take_damage 结算（掉落 / 扣耐久口径不变）。
func apply_execution() -> void:
	if not executable():
		return
	stun = 0.0
	_update_stun_gauge()
	take_damage(hp_ + 1.0, Vector3.ZERO, null)

## 眩晕**不衰减**（作者 2026-09-22 定）。早先实现的"每秒衰减 20"会让平A 的 +8
## 在 0.6 秒冷却里被扣掉 12（净亏 4），眩晕条永远打不满 —— 已废弃，这里不再做时间衰减。
func _update_stun_gauge() -> void:
	if stun <= 0.0:
		if _stun_gauge != null:
			_stun_gauge.set_ratio(0.0)
		return
	if _stun_gauge == null:
		var gauge: Node3D = StunGaugeScript.new()
		gauge.name = "StunGauge"
		add_child(gauge)
		gauge.setup(stun_max, 2.95)   # 血条标签在 y=2.25，黄条挂它上方避免叠字
		_stun_gauge = gauge
	_stun_gauge.set_ratio(_stun_gauge.ratio_of(stun))

func _physics_process(delta: float) -> void:
	# 纯靶子：不动、不攻击、不预警，只保留受击闪白。
	if kind == Kind.DUMMY:
		if _flash_timer > 0.0:
			_flash_timer -= delta
			if _flash_timer <= 0.0:
				_apply_flash(false)
		velocity = Vector3.ZERO
		return
	# 眩晕态：原地不动（等待被处决 / 自然回落），不推进 AI。
	if is_stunned():
		velocity = Vector3.ZERO
		move_and_slide()
		position.y = 0
		_animate_arm(delta)
		return
	if battle_driven:
		velocity = Vector3.ZERO
		return
	if dead or not is_instance_valid(player) or not player.alive:
		return
	# 游荡巡逻：白盒遭遇演示用，只绕出生点慢速转圈，不出手。
	if patrol_only:
		_patrol(delta)
		_animate_arm(delta)
		return
	attack_cd -= delta
	clash_immune_timer = maxf(0.0, clash_immune_timer - delta)
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_apply_flash(false)
	# 拼刀硬直：原地被弹开，期间不移动、不攻击
	if stun_timer > 0.0:
		stun_timer -= delta
		knock = knock.move_toward(Vector3.ZERO, 14.0 * delta)
		velocity = knock
		move_and_slide()
		position.y = 0
		_animate_arm(delta)
		return
	knock = knock.move_toward(Vector3.ZERO, 20 * delta)
	if windup >= 0:
		windup -= delta
		marker.scale = Vector3.ONE * (1.0 + 0.04 * sin(windup * 40))
		if windup <= 0:
			# 出手落地：若玩家正处在挥击窗口则判定拼刀，双方都不结算伤害
			var clashed := _resolve_strike()
			if not clashed and player.global_position.distance_to(target_point) <= 1.65:
				player.take_damage(attack_damage)
			_strike_timer = 0.22  # 人形敌人：挥击动作（劈下→回摆）只在出手后播放
			marker.visible = false
			windup = -1
			attack_cd = 1.4
		velocity = knock
	else:
		var offset := player.global_position - global_position
		offset.y = 0
		velocity = offset.normalized() * move_speed if offset.length() > keep_distance else Vector3.ZERO
		velocity += knock
		if offset.length() <= attack_reach and attack_cd <= 0:
			target_point = player.global_position
			windup = attack_windup
			marker.global_position = target_point + Vector3.UP * 0.045
			marker.visible = true
	_face_target(delta)
	_animate_arm(delta)
	move_and_slide()
	position.y = 0

## 有白盒模型的敌人朝目标转向；胶囊占位敌人是对称体，不需要朝向。
func _face_target(delta: float) -> void:
	if body_root == null or not is_instance_valid(player):
		return
	var offset := player.global_position - global_position
	offset.y = 0
	if offset.length() < 0.2:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(1.0, delta * 6.0))

func take_damage(amount: float, knock_dir := Vector3.ZERO, _attacker: Node = null, true_damage := 0.0) -> void:
	if dead:
		return
	var final := maxf(0.0, amount) * (1.0 - clampf(physical_reduction, 0.0, 0.9)) + maxf(0.0, true_damage)
	if kind == Kind.DUMMY:
		# 靶子打不坏：扣血只是留痕，最低保住 1 点，也不吃击退。
		hp_ = maxf(1, hp_ - final)
		_update_health()
		_flash()
		return
	hp_ = maxf(0, hp_ - final)
	knock = knock_dir
	_update_health()
	_flash()
	if hp_ <= 0:
		dead = true
		defeated.emit()
		marker.visible = false
		collision_layer = 0
		collision_mask = 0
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.18)
		tween.tween_callback(queue_free)

func _update_health() -> void:
	var tag := ""
	if kind != Kind.CUSTOM and kind != Kind.DUMMY:
		tag = "  [能量]" if has_energy else "  [无能量]"
	health_label.text = "%s%s  %.0f%%" % [enemy_name, tag, hp_ / max_hp * 100.0]
