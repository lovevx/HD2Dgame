extends CharacterBody3D
const GameAudio := preload("res://data/game_audio.gd")
signal defeated
const CombatSkills := preload("res://data/combat_skills.gd")
const WOLF_SPRITE_SHEET := preload("res://assets/enemies/directions/runtime/wolf_8dir.png")
const BOAR_SPRITE_SHEET := preload("res://assets/enemies/directions/runtime/boar_8dir.png")
const GOLEM_SPRITE_SHEET := preload("res://assets/enemies/directions/runtime/flesh_golem_8dir.png")
const MONSTER_DIRECTIONS: Array[String] = [
	"down", "down_right", "right", "up_right", "up", "up_left", "left", "down_left",
]
## 3×3 atlas: down-left/down/down-right, left/empty/right, up-left/up/up-right.
const MONSTER_DIRECTION_CELLS := {
	"down_left": Vector2i(0, 0), "down": Vector2i(1, 0), "down_right": Vector2i(2, 0),
	"left": Vector2i(0, 1), "right": Vector2i(2, 1),
	"up_left": Vector2i(0, 2), "up": Vector2i(1, 2), "up_right": Vector2i(2, 2),
}
## 每张 3×3 图集按 MONSTER_DIRECTIONS 顺序记录脚底锚点（像素）。
const WOLF_GROUND_OFFSETS: Array[float] = [177.0, 177.0, 130.0, 111.0, 120.0, 111.0, 130.0, 177.0]
const BOAR_GROUND_OFFSETS: Array[float] = [174.0, 175.0, 130.0, 112.0, 104.0, 112.0, 130.0, 175.0]
const GOLEM_GROUND_OFFSETS: Array[float] = [187.0, 187.0, 162.0, 141.0, 141.0, 141.0, 162.0, 187.0]
## 头顶眩晕条（scripts/combat/stun_gauge.gd）。用显式 preload 而不是全局类名，
## 这样不依赖编辑器的全局类缓存，命令行跑回归也能解析。
const StunGaugeScript := preload("res://scripts/combat/stun_gauge.gd")
## 敌人：红色预警圈锁定位置，前摇结束后才结算。
## kind 为 CUSTOM 时使用通用近战数值；
## 其余 kind 走 PROFILES：野狼、野猪为能量型，肉体傀儡为无能量实验体
## —— 青钢影的真实伤害对它无效，白盒阶段靠这个区分来验证苏晓的弱点。

enum Kind { CUSTOM, WOLF, BOAR, GOLEM, DUMMY, HUMAN }

## 人形敌人（HUMAN）外观、战斗风格与眩晕阈值查表：按 model key 取配置。
## 血量与攻击数值由关卡（campaign.gd）写入；stun_max 为处决眩晕阈值。
const HUMAN_PROFILES := {
	"vagrant": {"name": "持械流民", "color": Color("8a7662"), "trim": Color("574a3c"),
		"weapon": "dagger", "sidearm": true, "energy": true, "tall": 1.0, "stun_max": 25.0,
		"attack_style": "vagrant", "reach": 8.0, "keep": 2.6},
	"carlos": {"name": "黑市商人·卡洛斯", "color": Color("4a4a58"), "trim": Color("2b2b34"),
		"weapon": "dagger", "energy": true, "tall": 1.05, "stun_max": 45.0},
	"instructor": {"name": "考核教官", "color": Color("5d6a86"), "trim": Color("3a4255"),
		"weapon": "sword", "energy": true, "tall": 1.08, "stun_max": 55.0},
	"oka": {"name": "布兰登·欧卡", "color": Color("6b3f3a"), "trim": Color("3a2320"),
		"weapon": "axe", "energy": true, "tall": 1.1, "stun_max": 80.0,
		"attack_style": "oka", "reach": 8.0, "keep": 1.8},
	"guard": {"name": "欧卡护卫", "color": Color("6e7262"), "trim": Color("40423a"),
		"weapon": "spear", "sidearm": true, "energy": true, "tall": 1.03, "stun_max": 40.0,
		"attack_style": "guard", "reach": 9.0, "keep": 6.5},
}

## color 是主体毛色，trim 是四肢/头部等暗部；energy 决定头顶有没有能量核。
## 2026-09-19 整体降速：玩家移速 5.0→2.6，敌人速度同比例下调（约 0.52 倍）以保持相对快慢。
## reach / keep 是距离不是速度，保持不变。
const PROFILES := {
	Kind.WOLF: {
		"name": "野狼", "hp": 34.0, "speed": 1.7, "damage": 10.0, "reach": 4.4,
		"windup": 0.5, "keep": 1.6, "color": Color("8fa0bb"), "trim": Color("59647a"), "energy": true, "stun_max": 25.0,
		"attack_style": "wolf_pounce",
	},
	Kind.BOAR: {
		"name": "野猪", "hp": 72.0, "speed": 1.25, "damage": 16.0, "reach": 7.0,
		"windup": 0.75, "keep": 1.6, "color": Color("a9643c"), "trim": Color("67381f"), "energy": true, "stun_max": 45.0,
		"attack_style": "boar_charge",
	},
	Kind.GOLEM: {
		"name": "肉体傀儡", "hp": 90.0, "speed": 0.95, "damage": 18.0, "reach": 3.0,
		"windup": 1.1, "keep": 1.7, "color": Color("9a8fb5"), "trim": Color("5d5670"), "energy": false, "stun_max": 40.0,
		"attack_style": "golem_slam",
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
## 覆盖敌种 / 人形档位的预设值；0 表示使用档位配置。
@export_range(0.0, 200.0, 1.0) var stun_threshold_override := 0.0
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
var body_root: Node3D          # 怪物精灵或人形白盒容器；CUSTOM 占位敌人沿用胶囊
var monster_sprite: Sprite3D
var _monster_direction_textures: Dictionary = {}
var _monster_ground_offsets: Array[float] = []
var _monster_direction := "down"
var enemy_name := "近战守卫"
var attack_damage := 14.0
var kill_tier: int = 1   # 击杀武器耐久档：普通 1 / 精英 3 / BOSS 8（策划案 §6.3.1）
var attack_reach := 2.5
var attack_windup := 0.65
var keep_distance := 1.6
var attack_style := "melee"
var _attack_kind := "melee"
var _attack_windup_duration := 0.65
var _attack_radius := 1.65
var _attack_recovery := 1.4
var _marker_base_scale := Vector3.ONE
var _rush_timer := 0.0
var _rush_direction := Vector3.ZERO
var _rush_speed := 0.0
var _rush_damage := 0.0
var _rush_radius := 1.3
var _rush_recovery := 1.4
var _rush_hit := false
var _guard_retreat_timer := 0.0
var _oka_alerted := false
var _flash_timer := 0.0
var _arm_weapon: Node3D              # 人形敌人右臂（含武器），前摇举刀/出手挥击靠它
var _strike_timer := 0.0             # 挥击动作计时：出手后 0.22 秒内完成劈下-回摆
## 游荡巡逻（练习场演示用）：只绕出生点慢速转圈，永不攻击。
var patrol_only := false
var _patrol_home := Vector3.ZERO
var _patrol_setup := false
var _patrol_angle := 0.0
## ---------- 眩晕条（即时战斗的破绽资源，见 docs/REALTIME_COMBAT_EXTRACTION.md） ----------
## 打满 → 停止移动；此时用直踹命中即处决。木桩不吃眩晕。
var stun := 0.0
var stun_max := CombatSkills.STUN_MAX
var _stun_gauge: Node3D = null

func _ready() -> void:
	# 纯靶子不进 enemies 组，避免被试炼/波次的“清怪”逻辑算作存活敌人。
	if kind == Kind.DUMMY:
		add_to_group("targets")
	else:
		add_to_group("enemies")
	var body_color := Color("ce6654")
	var trim_color := Color("7a3a30")
	var profile: Dictionary = PROFILES.get(kind, {})
	if not profile.is_empty():
		enemy_name = profile["name"]
		max_hp = profile["hp"]
		move_speed = profile["speed"]
		attack_damage = profile["damage"]
		attack_reach = profile["reach"]
		attack_windup = profile["windup"]
		keep_distance = profile["keep"]
		attack_style = str(profile.get("attack_style", "melee"))
		stun_max = float(profile.get("stun_max", CombatSkills.STUN_MAX))
		has_energy = profile["energy"]
		body_color = profile["color"]
		trim_color = profile["trim"]
	# 人形敌人：血量与伤害由关卡写入；model 决定外观、战斗风格与眩晕阈值。
	var human: Dictionary = HUMAN_PROFILES.get(model, {}) if kind == Kind.HUMAN else {}
	if not human.is_empty():
		enemy_name = human["name"]
		body_color = human["color"]
		trim_color = human["trim"]
		has_energy = human["energy"]
		attack_style = str(human.get("attack_style", attack_style))
		attack_reach = float(human.get("reach", attack_reach))
		keep_distance = float(human.get("keep", keep_distance))
		stun_max = float(human.get("stun_max", stun_max))
	if stun_threshold_override > 0.0:
		stun_max = stun_threshold_override
	hp_ = max_hp
	player = get_tree().get_first_node_in_group("player")
	material = StandardMaterial3D.new()
	material.albedo_color = body_color
	$MeshInstance3D.material_override = material
	if kind != Kind.CUSTOM:
		# 有白盒模型的敌人把占位胶囊藏起来，只留它当碰撞参考
		$MeshInstance3D.visible = false
		_build_body(body_color, trim_color)
	if kind != Kind.CUSTOM and has_energy and kind != Kind.WOLF and kind != Kind.BOAR:
		_add_energy_core()  # 狼、野猪把能量晶体画在精灵里；人形能量敌人保留悬浮核
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

## 人形能量敌人头顶挂发光能量核；狼、野猪的能量特征画在精灵中。
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

# ---------------------------------------------------------------- 怪物精灵 / 白盒模型

## 野狼、野猪与肉体傀儡使用 2D 像素精灵；碰撞体和实时 AI 仍由本 CharacterBody3D 负责。
func _build_body(color: Color, trim: Color) -> void:
	body_root = Node3D.new()
	body_root.name = "Body"
	add_child(body_root)
	match kind:
		Kind.WOLF:
			_build_pixel_monster(WOLF_SPRITE_SHEET, 0.0052, WOLF_GROUND_OFFSETS)
		Kind.BOAR:
			_build_pixel_monster(BOAR_SPRITE_SHEET, 0.0044, BOAR_GROUND_OFFSETS)
		Kind.GOLEM:
			_build_pixel_monster(GOLEM_SPRITE_SHEET, 0.0054, GOLEM_GROUND_OFFSETS)
		Kind.DUMMY:
			_build_dummy(color, trim)
		Kind.HUMAN:
			var human: Dictionary = HUMAN_PROFILES.get(model, {})
			_build_human(color, trim, str(human.get("weapon", "dagger")), float(human.get("tall", 1.0)), bool(human.get("sidearm", false)))

func _build_pixel_monster(sheet: Texture2D, sprite_pixel_size: float, ground_offsets: Array[float]) -> void:
	_monster_direction_textures = _build_directional_textures(sheet)
	_monster_ground_offsets = ground_offsets
	monster_sprite = Sprite3D.new()
	monster_sprite.name = "MonsterSprite"
	monster_sprite.texture = _monster_direction_textures["down"]
	monster_sprite.pixel_size = sprite_pixel_size
	monster_sprite.offset = Vector2(0, _monster_ground_offsets[0])
	monster_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	monster_sprite.shaded = true
	monster_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	monster_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	body_root.add_child(monster_sprite)
	_update_monster_sprite_direction()

func _build_directional_textures(sheet: Texture2D) -> Dictionary:
	var cell_width := int(sheet.get_width() / 3.0)
	var cell_height := int(sheet.get_height() / 3.0)
	var textures: Dictionary = {}
	for direction in MONSTER_DIRECTIONS:
		var cell: Vector2i = MONSTER_DIRECTION_CELLS[direction]
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(cell.x * cell_width, cell.y * cell_height, cell_width, cell_height)
		textures[direction] = atlas
	return textures

func _update_monster_sprite_direction() -> void:
	if monster_sprite == null or _monster_direction_textures.is_empty():
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
	var direction := MONSTER_DIRECTIONS[index]
	if direction == _monster_direction:
		return
	_monster_direction = direction
	monster_sprite.texture = _monster_direction_textures[direction]
	monster_sprite.offset.y = _monster_ground_offsets[index]

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
func _build_human(color: Color, trim: Color, weapon: String, tall: float, has_sidearm := false) -> void:
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
	if has_sidearm:
		_build_sidearm(tall)
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

func _build_sidearm(tall: float) -> void:
	var metal := _material(Color("34363b"), 0.48)
	var wood := _material(Color("5b4533"), 0.75)
	_part("Sidearm", Vector3(-0.42, 1.24 * tall, -0.12), Vector3(0.16, 0.13, 0.38), metal)
	_part("SidearmBarrel", Vector3(-0.42, 1.24 * tall, -0.38), Vector3(0.07, 0.07, 0.22), metal)
	_part("SidearmGrip", Vector3(-0.42, 1.12 * tall, -0.02), Vector3(0.09, 0.2 * tall, 0.1), wood)

## 右手上的武器：匕首 / 单手剑 / 长枪 / 重斧，挂在高举的前臂下。
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
		"axe":
			blade = Vector3(0.48, 0.58, 0.13)
			grip_len = 0.72
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
	var ranged_pose := _attack_kind == "vagrant_spray" or _attack_kind == "guard_shot"
	var windup_pose := -24.0 if ranged_pose else -115.0
	var strike_pose := 16.0 if ranged_pose else 55.0
	if windup >= 0.0:
		var t := clampf(1.0 - windup / maxf(0.01, _attack_windup_duration), 0.0, 1.0)
		_arm_weapon.rotation_degrees.x = lerpf(18.0, windup_pose, ease(t, 0.55))
		body_root.rotation_degrees.x = lerpf(body_root.rotation_degrees.x, -4.0, minf(1.0, delta * 8.0))
	elif _strike_timer > 0.0:
		_strike_timer -= delta
		var phase := 1.0 - _strike_timer / 0.22
		if phase < 0.5:
			_arm_weapon.rotation_degrees.x = lerpf(windup_pose, strike_pose, phase * 2.0)
		else:
			_arm_weapon.rotation_degrees.x = lerpf(strike_pose, 18.0, (phase - 0.5) * 2.0)
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
		if child is Sprite3D:
			child.modulate = Color(1.8, 1.8, 1.8) if lit else Color.WHITE
		elif child is MeshInstance3D and child.material_override is StandardMaterial3D:
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
	if dead or not is_instance_valid(player) or not player.alive:
		return
	# 游荡巡逻：白盒遭遇演示用，只绕出生点慢速转圈，不出手。
	if patrol_only:
		_patrol(delta)
		_animate_arm(delta)
		return
	attack_cd -= delta
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_apply_flash(false)
	knock = knock.move_toward(Vector3.ZERO, 20 * delta)
	if _rush_timer > 0.0:
		_tick_rush(delta)
		_face_target(delta)
		_animate_arm(delta)
		return
	if windup >= 0:
		windup -= delta
		marker.scale = _marker_base_scale * (1.0 + 0.04 * sin(windup * 40))
		if windup <= 0:
			_resolve_attack()
			if kind == Kind.HUMAN:
				_strike_timer = 0.22
			marker.visible = false
			windup = -1
		velocity = knock
	else:
		var offset := player.global_position - global_position
		offset.y = 0
		if attack_style == "oka" and not _oka_alerted:
			if _oka_spots_player(offset):
				_oka_alerted = true
			else:
				_patrol(delta)
				_animate_arm(delta)
				return
		_tick_attack_style(offset, offset.length(), delta)
		velocity += knock
	_face_target(delta)
	_animate_arm(delta)
	move_and_slide()
	position.y = 0

func _tick_attack_style(offset: Vector3, dist: float, delta: float) -> void:
	match attack_style:
		"vagrant":
			if dist > 8.0:
				velocity = offset.normalized() * move_speed * 0.8
			elif dist >= 4.0:
				velocity = Vector3.ZERO
				if attack_cd <= 0.0:
					_begin_attack("vagrant_spray", player.global_position, 0.7, 1.0, 1.2)
			elif dist > 2.6:
				velocity = offset.normalized() * move_speed * 0.6
				if attack_cd <= 0.0:
					_begin_attack("slow_rush", player.global_position, 0.55, 1.25, 1.2, true)
			else:
				velocity = Vector3.ZERO
				if attack_cd <= 0.0:
					_begin_attack("melee", player.global_position, 0.55, 1.65, 1.2)
		"guard":
			_tick_guard(offset, dist, delta)
		"oka":
			if dist > 8.0:
				velocity = offset.normalized() * move_speed
			elif dist <= 3.0:
				velocity = Vector3.ZERO
				if attack_cd <= 0.0:
					_begin_attack("heavy_chop", player.global_position, 0.9, 2.25, 1.5)
			else:
				velocity = offset.normalized() * move_speed * 0.45 if attack_cd > 0.0 else Vector3.ZERO
				if attack_cd <= 0.0:
					_begin_attack("oka_leap", player.global_position, 0.5, 1.5, 1.5, true)
		"wolf_pounce":
			if dist > attack_reach:
				velocity = offset.normalized() * move_speed
			elif attack_cd <= 0.0:
				velocity = Vector3.ZERO
				_begin_attack("wolf_pounce", player.global_position, attack_windup, 1.35, 1.45, true)
			else:
				velocity = offset.normalized() * move_speed * 0.55 if dist > keep_distance else Vector3.ZERO
		"boar_charge":
			if dist > attack_reach:
				velocity = offset.normalized() * move_speed
			elif attack_cd <= 0.0:
				velocity = Vector3.ZERO
				_begin_attack("boar_charge", player.global_position, attack_windup, 1.6, 1.8, true)
			else:
				velocity = offset.normalized() * move_speed * 0.35 if dist > 2.5 else Vector3.ZERO
		"golem_slam":
			if dist > attack_reach:
				velocity = offset.normalized() * move_speed
			else:
				velocity = Vector3.ZERO
				if attack_cd <= 0.0:
					_begin_attack("golem_slam", player.global_position, attack_windup, 2.6, 1.9)
		_:
			velocity = offset.normalized() * move_speed if dist > keep_distance else Vector3.ZERO
			if dist <= attack_reach and attack_cd <= 0.0:
				_begin_attack("melee", player.global_position, attack_windup, 1.65, 1.4)

func _tick_guard(offset: Vector3, dist: float, delta: float) -> void:
	if _guard_retreat_timer > 0.0:
		_guard_retreat_timer = maxf(0.0, _guard_retreat_timer - delta)
		velocity = -offset.normalized() * move_speed
	elif dist > 9.0:
		velocity = offset.normalized() * move_speed * 0.75
	elif dist >= 4.0:
		velocity = Vector3.ZERO
		if attack_cd <= 0.0:
			_begin_attack("guard_shot", player.global_position, 0.95, 0.9, 1.25)
	elif dist <= 2.8:
		velocity = Vector3.ZERO
		if attack_cd <= 0.0:
			_begin_attack("guard_stab", player.global_position, 0.5, 1.3, 1.1)
		else:
			velocity = -offset.normalized() * move_speed
	else:
		velocity = -offset.normalized() * move_speed

func _begin_attack(kind_name: String, point: Vector3, windup_time: float, radius: float, recovery: float, corridor := false) -> void:
	_attack_kind = kind_name
	_attack_windup_duration = windup_time
	_attack_radius = radius
	_attack_recovery = recovery
	target_point = point
	target_point.y = 0.0
	windup = windup_time
	GameAudio.play_sfx("enemy_attack", global_position, -8.0, randf_range(0.94, 1.04))
	_marker_base_scale = Vector3.ONE * (radius / 1.65)
	marker.rotation.y = 0.0
	marker.global_position = target_point + Vector3.UP * 0.045
	if corridor:
		var direction := target_point - global_position
		direction.y = 0.0
		var length := maxf(2.0, _flat_distance(target_point, global_position))
		marker.global_position = (global_position + target_point) * 0.5 + Vector3.UP * 0.045
		marker.rotation.y = atan2(-direction.x, -direction.z)
		_marker_base_scale = Vector3(0.58 / 1.65, 1.0, length / 3.3)
	marker.scale = _marker_base_scale
	marker.visible = true

func _resolve_attack() -> void:
	match _attack_kind:
		"vagrant_spray":
			_fire_vagrant_spray()
			attack_cd = _attack_recovery
		"guard_shot":
			if _player_near_point(target_point, 0.7) and _has_line_of_fire():
				player.take_damage(attack_damage)
			attack_cd = _attack_recovery
		"slow_rush", "wolf_pounce", "boar_charge", "oka_leap":
			_start_rush()
		"guard_stab":
			if _player_near_point(target_point, _attack_radius):
				player.take_damage(attack_damage)
			_guard_retreat_timer = 0.7
			attack_cd = _attack_recovery
		"heavy_chop", "golem_slam", "melee":
			if _player_near_point(target_point, _attack_radius):
				player.take_damage(attack_damage)
			attack_cd = _attack_recovery

func _fire_vagrant_spray() -> void:
	if not _has_line_of_fire():
		return
	var distance_ratio := clampf(_flat_distance(global_position, target_point) / 8.0, 0.0, 1.0)
	var spread := lerpf(0.55, 1.45, distance_ratio)
	var hits := 0
	for _shot in 3:
		var impact := target_point + Vector3(randf_range(-spread, spread), 0.0, randf_range(-spread, spread))
		if _player_near_point(impact, 0.65):
			hits += 1
	if hits > 0:
		player.take_damage(attack_damage * float(hits) / 3.0)

func _has_line_of_fire() -> bool:
	if not is_instance_valid(player):
		return false
	var start := global_position + Vector3.UP * 1.0
	var end := player.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == player

func _start_rush() -> void:
	var flat_to_target := target_point - global_position
	flat_to_target.y = 0.0
	_rush_direction = flat_to_target.normalized() if flat_to_target.length_squared() > 0.001 else Vector3.FORWARD
	var rush_distance := 3.0
	match _attack_kind:
		"slow_rush":
			_rush_speed = 2.4
			_rush_radius = 1.2
			_rush_damage = attack_damage * 0.8
			_rush_recovery = 1.2
			rush_distance = 3.3
		"wolf_pounce":
			_rush_speed = 5.2
			_rush_radius = 1.4
			_rush_damage = attack_damage
			_rush_recovery = 1.45
			rush_distance = 4.4
		"boar_charge":
			_rush_speed = 6.0
			_rush_radius = 1.6
			_rush_damage = attack_damage
			_rush_recovery = 1.8
			rush_distance = 7.0
		"oka_leap":
			_rush_speed = 6.2
			_rush_radius = 1.6
			_rush_damage = attack_damage * 1.2
			_rush_recovery = 1.5
			rush_distance = 5.5
	var travel := minf(rush_distance, maxf(1.5, _flat_distance(target_point, global_position) + 0.7))
	_rush_timer = travel / _rush_speed
	_rush_hit = false
	marker.visible = false

func _tick_rush(delta: float) -> void:
	_rush_timer = maxf(0.0, _rush_timer - delta)
	velocity = _rush_direction * _rush_speed + knock
	move_and_slide()
	position.y = 0.0
	if not _rush_hit and _flat_distance(player.global_position, global_position) <= _rush_radius:
		player.take_damage(_rush_damage)
		_rush_hit = true
		_rush_timer = 0.0
	if is_on_wall() or _rush_timer <= 0.0:
		velocity = Vector3.ZERO
		_rush_timer = 0.0
		attack_cd = _rush_recovery

func _player_near_point(point: Vector3, radius: float) -> bool:
	return is_instance_valid(player) and _flat_distance(player.global_position, point) <= radius

func _flat_distance(a: Vector3, b: Vector3) -> float:
	var offset := a - b
	offset.y = 0.0
	return offset.length()

func _oka_spots_player(offset: Vector3) -> bool:
	if offset.length() > 8.0 or offset.length_squared() < 0.001:
		return false
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized().dot(offset.normalized()) > 0.25

## 人形白盒与怪物精灵朝目标转向；胶囊占位敌人是对称体，不需要朝向。
func _face_target(delta: float) -> void:
	if body_root == null or not is_instance_valid(player):
		return
	var offset := player.global_position - global_position
	offset.y = 0
	if offset.length() < 0.2:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-offset.x, -offset.z), minf(1.0, delta * 6.0))
	_update_monster_sprite_direction()

func take_damage(amount: float, knock_dir := Vector3.ZERO, _attacker: Node = null, true_damage := 0.0) -> void:
	if dead:
		return
	var physical := maxf(0.0, amount)
	if attack_style == "oka":
		if not _oka_alerted and _attacker is Node3D:
			var from_attacker: Vector3 = (_attacker.global_position - global_position)
			from_attacker.y = 0.0
			var back := global_basis.z
			back.y = 0.0
			if from_attacker.length_squared() > 0.001 and back.normalized().dot(from_attacker.normalized()) > 0.45:
				physical *= 2.0
				GameState.push_message("背刺命中 · 欧卡进入战斗")
		_oka_alerted = true
	var final := physical * (1.0 - clampf(physical_reduction, 0.0, 0.9)) + maxf(0.0, true_damage)
	if kind == Kind.DUMMY:
		# 靶子打不坏：扣血只是留痕，最低保住 1 点，也不吃击退。
		hp_ = maxf(1, hp_ - final)
		_update_health()
		_flash()
		GameAudio.play_sfx("enemy_hit", global_position, -5.0, randf_range(0.94, 1.06))
		return
	hp_ = maxf(0, hp_ - final)
	knock = knock_dir
	_update_health()
	_flash()
	if hp_ <= 0:
		GameAudio.play_sfx("enemy_death", global_position, -2.0)
		dead = true
		defeated.emit()
		marker.visible = false
		collision_layer = 0
		collision_mask = 0
		var tween := create_tween()
		tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.18)
		tween.tween_callback(queue_free)
	else:
		GameAudio.play_sfx("enemy_hit", global_position, -5.0, randf_range(0.94, 1.06))

func _update_health() -> void:
	var tag := ""
	if kind != Kind.CUSTOM and kind != Kind.DUMMY:
		tag = "  [能量]" if has_energy else "  [无能量]"
	health_label.text = "%s%s  %.0f%%" % [enemy_name, tag, hp_ / max_hp * 100.0]
