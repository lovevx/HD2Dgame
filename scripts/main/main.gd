extends Node
## 自由练习场：不写正式货币、任务或存档。场上只有一根打不坏的练功木桩，
## 用来练习攻击、剃与拼刀格挡；没有敌人波次，也没有清场结算。
## 机位与港口/科波山统一：低俯角透视 HD2D 镜头，鼠标让出 + 移动前瞻 + 焦点收边。
const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
const HudScene := preload("res://scripts/ui/hud.tscn")
const AssetCatalog := preload("res://tools/preset_catalog.gd")
const CameraStyle := preload("res://scripts/world/jungle_camera_style.gd")
const MouseLead := preload("res://scripts/world/camera_mouse_lead.gd")
## 练武场是空旷对称场地，沿用 Port 的正面取景（yaw 0）：石板行条横平竖直，
## 不会像 8° 偏航那样把 60 米平板的网格带成斜向菱形。
const CAM_YAW := 0.0
const CAMERA_LEAD := 0.75
var campaign_managed := false
## 练武场 25 米见方、玩家活动范围 ±12：焦点收边略大于场地，边缘贴图不出画。
const FOCUS_BOUNDS := Rect2(-13, -13, 26, 26)
var practice := false
@onready var player: CharacterBody3D = $player
@onready var camera: Camera3D = $Camera3D
var hud: CanvasLayer
var _cam_offset := Vector3.ZERO
var _mouse_lead := MouseLead.new()
var _camera_lead := Vector3.ZERO

func _input(event: InputEvent) -> void:
	_mouse_lead.note_input(event)

func _ready() -> void:
	if not campaign_managed:
		player.died.connect(_on_player_died)
		player.set_physics_process(false)
	# 机位用装修两关的同一套参数：当前相机角度是生成好的，先记下视线偏移再原地就位。
	CameraStyle.configure(camera, true)
	# 练武场是空旷对称场地，正面取景（yaw 0）保持石板横平竖直
	camera.rotation_degrees = Vector3(-CameraStyle.PITCH, CAM_YAW, 0)
	_cam_offset = camera.basis * Vector3(0, 0, CameraStyle.DISTANCE)
	camera.position = _camera_target() + _cam_offset
	_build_arena()
	if campaign_managed:
		return
	hud = HudScene.instantiate()
	add_child(hud)
	hud.configure("灰潮 · 自由练习场", "自由练习  /  打木桩练手")
	hud.show_panel("灰潮 · 自由练习场", "轻松练习场地 / 不影响正式资源\n\n场上练功木桩不会移动、不会反击，用来练习攻击、剃与拼刀格挡。\n\nWASD 移动 · 左键朝鼠标三连击 · Shift 剃\n数字 1 炸弹 · 数字 2 药剂 · V 交互 · F1 按键说明", "开始练习", start_practice)

func start_practice() -> void:
	player.position = Vector3.ZERO
	player.reset()
	player.set_physics_process(true)
	practice = true
	hud.hide_panel()
	hud.set_objective("自由练习  /  打木桩练手")

func _on_player_died() -> void:
	practice = false
	player.set_physics_process(false)
	player.input_dir = Vector2.ZERO
	hud.show_panel("倒下了", "在自由练习场倒下，随时可以重新开始。\n\n本模式不消耗逃脱币，不造成永久死亡。", "重新开始", start_practice)

func _process(delta: float) -> void:
	_update_camera(delta)

## 移动前瞻 + 鼠标让出 + 焦点收边：与科波山/港口同一套运镜，保证玩家在画面里。
func _update_camera(delta: float) -> void:
	_mouse_lead.update(camera, get_viewport(), delta)
	var movement := Vector3(player.velocity.x, 0, player.velocity.z)
	var lead_target := movement.limit_length(4.0) * (CAMERA_LEAD / 4.0)
	_camera_lead = _camera_lead.lerp(lead_target, 1.0 - exp(-3.0 * delta))
	camera.position = camera.position.lerp(_camera_target() + _cam_offset, 1.0 - exp(-5.5 * delta))

func _camera_target() -> Vector3:
	var focus := player.position + CameraStyle.COMPOSITION_OFFSET + _camera_lead + _mouse_lead.offset
	focus.x = clampf(focus.x, FOCUS_BOUNDS.position.x, FOCUS_BOUNDS.end.x)
	focus.z = clampf(focus.z, FOCUS_BOUNDS.position.y, FOCUS_BOUNDS.end.y)
	return focus

func _build_arena() -> void:
	# 石砌比武场地面：规整方形石板（无砖砌错缝），低俯角透视下不会觉得地面是斜的。
	var paving := ShaderMaterial.new()
	paving.shader = preload("res://shaders/trial_floor.gdshader")
	paving.set_shader_parameter("stone_color", Color("3a4a52"))
	paving.set_shader_parameter("tile_scale", 0.5)
	paving.set_shader_parameter("grout", 0.06)
	$ground/MeshInstance3D.material_override = paving
	# 环境以港口模板同步：纯色远景底 + 电影色调 + SSAO/SSIL + 辉光 + 雾与体积雾。
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	var env := world.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("516975")
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
	env.fog_density = 0.0015
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color("aebfce")
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.25
	add_child(world)
	# 补光（CoolSkyFill）已在场景里配好，与港口同一套参数。
	_build_boundary()
	_backdrop_ring()
	if not campaign_managed:
		_spawn_dummy()

## 外围取景密林：在场地外圈铺一圈树/岩石，把 60 米地面的地平线剪掉，
## 视线远端和科波山一样落在树冠上，而不是看到石板一路铺到天边。
func _backdrop_ring() -> void:
	for i in 24:
		var angle := float(i) / 24.0 * TAU + rng.randf_range(-0.06, 0.06)
		var radius := rng.randf_range(20.0, 26.0)
		var at := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		var title: String = "SM_taoshu001" if rng.randf() < 0.5 else "SM_1dashu001_LODs"
		_prop(title, at, CAM_YAW + rng.randf_range(-12, 12), rng.randf_range(0.25, 0.4))
	for i in 16:
		var angle := float(i) / 16.0 * TAU + rng.randf_range(-0.08, 0.08)
		var radius := rng.randf_range(16.0, 21.0)
		var at := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		_prop("SM_XYNJiangnan006" if rng.randf() < 0.5 else "SM_XYNJiangnan012", at, rng.randf_range(0, 360), rng.randf_range(0.5, 0.8))

## 试炼场边界：四角石柱 + 檐下石灯 + 墙角苔岩，外围桃树与巨树收住取景边缘。
## 纯装饰、无碰撞（活动范围由玩家 bounds 负责），素材全部来自共享库预置。
func _build_boundary() -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_prop("SM_Licheng_shizhuzi001", Vector3(sx * 12.7, 0, sz * 12.7), 0.0, 1.4)
			_prop("SM_XYNJiangnan012", Vector3(sx * 13.6, 0, sz * 13.6), rng.randf_range(0, 360), 0.5)
			# 四角外圈的桃树取景（桃树是宽 10.7m 的贴片卡，压小后当背景树影）
			_prop("SM_taoshu001", Vector3(sx * 15.2, 0, sz * 15.2), CAM_YAW, 0.16)
			_prop("SM_XYNJiangnan016", Vector3(sx * 17.5, 0, sz * 17.5), rng.randf_range(0, 360), 0.4)
	for side in [-1.0, 1.0]:
		# 四条边中点各一盏石灯，把练武场边界压成规则四边形
		_prop("SM_NJ_ShiDeng_001", Vector3(side * 12.7, 0, 0), 0.0, 1.0)
		_prop("SM_NJ_ShiDeng_001", Vector3(0, 0, side * 12.7), 0.0, 1.0)
		for t in [-6.4, 6.4]:
			_prop("SM_XYNJiangnan006", Vector3(side * 12.9, 0, t), rng.randf_range(0, 360), 0.3)
			_prop("SM_1dashu001_LODs", Vector3(t, 0, side * 16.5), CAM_YAW + rng.randf_range(-8, 8), 0.45)

## 中央练功木桩：不移动、不攻击、打不坏；脚下加一块红色落点圈。
func _spawn_dummy() -> void:
	var at := Vector3(-3, 0, 3)
	var ring := MeshInstance3D.new()
	ring.name = "TargetRing"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.45
	cyl.bottom_radius = 1.45
	cyl.height = 0.02
	ring.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.55, 0.2, 0.26)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position = at + Vector3(0, 0.02, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var dummy := EnemyScene.instantiate()
	dummy.name = "PracticeDummy"
	dummy.set("kind", EnemyScript.Kind.DUMMY)
	dummy.position = at
	add_child(dummy)

## 放一个共享库预置素材（无碰撞、纯装饰）。size 是整体缩放倍数。
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

var rng := RandomNumberGenerator.new()
