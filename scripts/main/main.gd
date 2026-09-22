extends Node
## 自由练习场：不写正式货币、任务或存档。场上只有一根打不坏的练功木桩，
## 用来练习攻击、剃与拼刀格挡；没有敌人波次，也没有清场结算。
## 机位与港口/科波山统一：低俯角透视 HD2D 镜头，移动前瞻 + 焦点收边；
## 视角与远近由玩家自己操作（中键拖动转视角、滚轮推拉距离），光标不再带动镜头。
const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
const HudScene := preload("res://scripts/ui/hud.tscn")
const AssetCatalog := preload("res://tools/preset_catalog.gd")
const CameraStyle := preload("res://scripts/world/jungle_camera_style.gd")
const Orbit := preload("res://scripts/world/camera_orbit_controls.gd")
const PortalScript := preload("res://scripts/world/scene_portal.gd")
## 双形态战斗（P1 v1）：白盒遭遇演示——练习场里放一只游荡野狼，
## 玩家踏入 8m 遭遇圈即切回合战（AT 顺序 + 走位/指令 + 敌人回合）。
const Attributes := preload("res://data/attributes.gd")
const CombatSkills := preload("res://data/combat_skills.gd")
## 取景正对（与相机同偏航）：石板行条横平竖直，外圈取景树也按这个基准摆放。
const CAM_YAW := CameraStyle.YAW
const CAMERA_LEAD := 0.75
## 锚点的跟随收敛率（每秒，帧率无关）：转视角不需要加速，相机刚性挂在朝向上。
const FOLLOW_SPEED := 5.5
var campaign_managed := false
## 练武场 25 米见方、玩家活动范围 ±12：焦点收边略大于场地，边缘贴图不出画。
const FOCUS_BOUNDS := Rect2(-13, -13, 26, 26)
var practice := false
@onready var player: CharacterBody3D = $player
@onready var camera: Camera3D = $Camera3D
var hud: CanvasLayer
var _orbit := Orbit.new()
var _camera_lead := Vector3.ZERO
## 白盒遭遇战场地（P1 v1）：练习场专属，不进正式关卡。
var _wolf: Node = null
var _encounter: EncounterZone = null
var _battle_running := false
var _battle_controller := BattleController.new()
var _order_bar: OrderBar = null
var _battle_menu: BattleMenu = null

func _input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		get_viewport().set_input_as_handled()

func _ready() -> void:
	if not campaign_managed:
		player.died.connect(_on_player_died)
		player.set_physics_process(false)
	# 机位用装修两关的同一套参数：先按风格就位，再交给轨道控制（中键/滚轮可改）。
	CameraStyle.configure(camera, true)
	_orbit.configure(camera, CameraStyle.PITCH, CameraStyle.YAW, CameraStyle.distance(true))
	_orbit.snap(camera, _camera_target(), CameraStyle.composition(_orbit.forward_flat()))
	_build_arena()
	if campaign_managed:
		return
	hud = HudScene.instantiate()
	add_child(hud)
	hud.configure("灰潮 · 自由练习场", "自由练习  /  打木桩练手")
	hud.show_panel("灰潮 · 自由练习场", "轻松练习场地 / 不影响正式资源\n\n场上练功木桩不会移动、不会反击，用来练习攻击、剃与拼刀格挡。\n\nWASD 移动 · 左键朝鼠标斩击 · Space 剃 · K 直踢\n数字 1 炸弹 · 数字 2 药剂 · V 交互 · F1 按键说明\n\n靠近练习场里的野狼会触发回合制遭遇战。", "开始练习", start_practice)
	_build_encounter_demo()

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
	_try_trigger_battle()

## 白盒遭遇触发：练习中且圈内野狼存活 → 切回合战。
func _try_trigger_battle() -> void:
	if not practice or _battle_running:
		return
	if _wolf == null or not is_instance_valid(_wolf):
		return
	if not _wolf.is_alive():
		return
	if _encounter == null or not _encounter.in_radius(player.position):
		return
	start_battle()

## 移动前瞻 + 焦点收边：与科波山/港口同一套运镜，保证玩家在画面里。
## 平滑只作用在锚点上，构图偏移挂在机位朝向上——转视角时取景关系完全不变。
func _update_camera(delta: float) -> void:
	var movement := Vector3(player.velocity.x, 0, player.velocity.z)
	var lead_target := movement.limit_length(4.0) * (CAMERA_LEAD / 4.0)
	_camera_lead = _camera_lead.lerp(lead_target, 1.0 - exp(-3.0 * delta))
	_orbit.place(camera, _camera_target(), CameraStyle.composition(_orbit.forward_flat()), delta, FOLLOW_SPEED)

## 锚点：玩家位置 + 移动前瞻，只做收边；构图偏移由轨道控制按朝向加上去。
func _camera_target() -> Vector3:
	var focus := player.position + _camera_lead
	focus.x = clampf(focus.x, FOCUS_BOUNDS.position.x, FOCUS_BOUNDS.end.x)
	focus.z = clampf(focus.z, FOCUS_BOUNDS.position.y, FOCUS_BOUNDS.end.y)
	return focus

func _build_arena() -> void:
	# 石砌比武场地面：规整方形石板（无砖砌错缝），低俯角透视下不会觉得地面是斜的。
	# 正式关卡按 stage 换砖色/砖块尺寸/砖缝宽度，避免四关共用同一块地面。
	var paving := ShaderMaterial.new()
	paving.shader = preload("res://shaders/trial_floor.gdshader")
	# 地板/背景按 stage 取色，直接打开场景（campaign_managed=false）也与正式流程一致，方便调试。
	var floor_cfg: Dictionary = _floor_config(GameState.campaign.stage)
	paving.set_shader_parameter("stone_color", floor_cfg.get("stone_color", Color("3a4a52")))
	paving.set_shader_parameter("tile_scale", floor_cfg.get("tile_scale", 0.5))
	paving.set_shader_parameter("grout", floor_cfg.get("grout", 0.06))
	$ground/MeshInstance3D.material_override = paving
	# 环境以港口模板同步：纯色远景底 + 电影色调 + SSAO/SSIL + 辉光 + 雾与体积雾。
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	var env := world.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = floor_cfg.get("bg_color", Color("516975"))
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
	# 关卡环境差异化：按 stage 摆放专属布景与传送门；直接打开场景也一致呈现，方便调试。
	_dress_stage(GameState.campaign.stage)
	_build_portals(GameState.campaign.stage)
	if not campaign_managed:
		_spawn_dummy()

## 按阶段给试炼场换布景：1.2 废品站 / 1.3 王都入口 / 1.4 侍卫总部 / 1.5 欢乐街。
## 素材全部来自共享预置库，纯装饰无碰撞（玩家活动范围由 bounds 负责）。
func _dress_stage(stage: int) -> void:
	match stage:
		0:
			_dress_junk_station()
		1:
			_dress_city_gate()
		2:
			_dress_guard_hq()
		3:
			_dress_pleasure_street()

## 地面与背景差异化：每关换砖色/砖块尺寸/砖缝宽度和远景底色。
## 1.2 暗土灰乱石地 / 1.3 规整青灰石板 / 1.4 演武场大块石板 / 1.5 暖红砖街。
func _floor_config(stage: int) -> Dictionary:
	match stage:
		0:
			return {"stone_color": Color("6d6157"), "tile_scale": 0.32, "grout": 0.09, "bg_color": Color("5d5248")}
		1:
			return {"stone_color": Color("77838d"), "tile_scale": 0.5, "grout": 0.05, "bg_color": Color("62707c")}
		2:
			return {"stone_color": Color("5d6a72"), "tile_scale": 0.42, "grout": 0.07, "bg_color": Color("56636d")}
		3:
			return {"stone_color": Color("7d4f3a"), "tile_scale": 0.55, "grout": 0.06, "bg_color": Color("6d5345")}
		_:
			return {}

## 入口 / 出口传送门：照科尔波山逻辑，南侧入口出生、北侧出口切下一关。
## 入口是纯视觉（标出"你从哪里进来"）；出口挂 scene_portal.gd，由 campaign.gd 配置推进。
func _build_portals(stage: int) -> void:
	# 南侧入口：玩家出生在这里，表示从上一关走进来
	var entrance_at := Vector3(0, 0, 8.0)
	_portal_visual("EntrancePortal", entrance_at, Color("63d6ff"), "", false)
	if player != null:
		player.position = entrance_at + Vector3(0, 0, -1.0)
	# 北侧出口：清场后走进即切下一关，门控由 campaign.gd 注入
	var exit_at := Vector3(0, 0, -9.0)
	var exit := Area3D.new()
	exit.name = "ExitPortal"
	exit.position = exit_at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 2.6, 1.4)
	shape.shape = box
	exit.add_child(shape)
	exit.set_script(PortalScript)
	add_child(exit)
	_portal_visual("ExitPortalVisual", exit_at, Color("e8b45a"), "出口 · 前往下一地区")

## 入口仅保留地面标记；出口保留立柱与标签，避免近景门面遮住主角和敌人。
func _portal_visual(label_name: String, at: Vector3, color: Color, label_text: String, show_frame := true) -> void:
	var holder := Node3D.new()
	holder.name = label_name
	holder.position = at
	add_child(holder)
	if show_frame:
		for side in [-1, 1]:
			var pillar := MeshInstance3D.new()
			pillar.name = "Pillar%s" % side
			var pm := BoxMesh.new()
			pm.size = Vector3(0.5, 3.6, 0.5)
			pillar.mesh = pm
			pillar.material_override = _portal_mat(Color("25323a"), 0.25, false)
			pillar.position = Vector3(side * 2.4, 1.8, 0)
			holder.add_child(pillar)
	# 地面光圈
	var disc := MeshInstance3D.new()
	disc.name = "Ring"
	var cm := CylinderMesh.new()
	cm.top_radius = 2.4 if show_frame else 1.6
	cm.bottom_radius = 2.4 if show_frame else 1.6
	cm.height = 0.02
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(color.r, color.g, color.b, 0.3 if show_frame else 0.14)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0, 0.02, 0)
	holder.add_child(disc)
	if show_frame:
		var label := Label3D.new()
		label.name = "Label"
		label.text = label_text
		label.position = Vector3(0, 2.8, 0)
		label.font_size = 36
		label.pixel_size = 0.011
		label.outline_size = 12
		label.modulate = color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		holder.add_child(label)

func _portal_mat(color: Color, emission: float, unshaded: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

## 1.2 废品终点站：破屋残墙 + 垃圾堆 + 木箱瓦罐，视野零散、无对称感。
func _dress_junk_station() -> void:
	# 中远景两栋破屋当剪影
	_prop("SM_kushuicun_pofangzi002", Vector3(-10.5, 0, -6.5), 30, 0.85)
	_prop("SM_kushuicun_pofangzi002", Vector3(11.0, 0, 2.0), 200, 0.7)
	# 场地内散落垃圾：石头堆 / 木箱 / 长草，不挡路只做障碍感
	for at in [Vector3(-6, 0, 3), Vector3(5, 0, -5), Vector3(7, 0, 6), Vector3(-4, 0, -7)]:
		_prop("SM_NJ_Shitoudui001", at, rng.randf_range(0, 360), rng.randf_range(0.9, 1.3))
	for at in [Vector3(-8, 0, 6), Vector3(2, 0, 7), Vector3(9, 0, -4)]:
		_prop("SM_Box001Close" if rng.randf() < 0.5 else "SM_Box001Open", at, rng.randf_range(0, 360), rng.randf_range(0.8, 1.1))
	for at in [Vector3(-2, 0, -4), Vector3(6, 0, 1), Vector3(-9, 0, -2)]:
		_prop("SM_changzacao001", at, rng.randf_range(0, 360), rng.randf_range(1.2, 1.8))

## 1.3 王都入口：城门 + 两侧高墙 + 石灯石柱，形成一条准入通道。
func _dress_city_gate() -> void:
	_prop("SM_xgg_chengmen001", Vector3(0, 0, -10.5), 0, 1.15)          # 北侧城门
	for sx in [-1.0, 1.0]:
		_prop("SM_JN_Weiqiang001", Vector3(sx * 8.0, 0, -7.5), 90 if sx > 0 else -90, 1.2)
		_prop("SM_JN_Weiqiang001", Vector3(sx * 8.0, 0, -4.0), 90 if sx > 0 else -90, 1.2)
		_prop("SM_Licheng_shizhuzi001", Vector3(sx * 6.5, 0, -2.5), 0, 1.1)
		_prop("SM_NJ_ShiDeng_001", Vector3(sx * 9.5, 0, -0.5), 0, 1.0)
	# 南侧出口两柱夹道
	for sx in [-1.0, 1.0]:
		_prop("SM_Licheng_shizhuzi001", Vector3(sx * 7.0, 0, 7.5), 0, 1.1)

## 1.4 侍卫总部：武馆立面 + 对称石柱灯 + 演武场木桩，秩序感强。
func _dress_guard_hq() -> void:
	_prop("SM_JN_wuguan001", Vector3(0, 0, -10.5), 0, 1.05)  # 北侧武馆正门
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_prop("SM_Licheng_shizhuzi001", Vector3(sx * 9.5, 0, sz * 7.5), 0, 1.1)
		_prop("SM_NJ_ShiDeng_001", Vector3(sx * 6.0, 0, -5.0), 0, 1.0)
	# 演武场中央两侧木桩：挂盾感
	for at in [Vector3(-4.5, 0, 2.0), Vector3(4.5, 0, 2.0)]:
		_prop("SM_NJ_ZhuPai002", at, 0, 1.0)

## 1.5 欢乐街：两侧店面 + 灯笼火架 + 摊位屏风，一条暖色夜市街。
func _dress_pleasure_street() -> void:
	for sx in [-1.0, 1.0]:
		_prop("SM_JN_fangzi001", Vector3(sx * 10.5, 0, -6.0), -90 if sx > 0 else 90, 0.95)
		_prop("SM_JN_fangzi002", Vector3(sx * 10.5, 0, 5.0), 90 if sx > 0 else -90, 0.95)
	for i in 3:
		_prop("SM_Item_NJhuojia001", Vector3(-5.0 + i * 5.0, 0, -1.5), 0, 1.0)
		_prop("SM_Item_NJtanwei001", Vector3(-5.0 + i * 5.0, 0, 3.0), 0, 1.0)
	_prop("SM_Item_pingfeng001", Vector3(-8.5, 0, 1.5), 20, 1.0)
	_prop("SM_Item_pingfeng001", Vector3(8.5, 0, 1.5), -20, 1.0)
	_prop("SM_NJ_ZhuZhuozi001", Vector3(-2.5, 0, -5.5), 15, 1.0)
	_prop("SM_NJ_ZhuZhuozi001", Vector3(3.0, 0, -5.0), -10, 1.0)

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

## ---------- 白盒遭遇战（P1 v1） ----------

## 练习场布置：遭遇圈（圆心在场地中央）+ 一只游荡野狼 + AT 顺序条 + 指令面板。
func _build_encounter_demo() -> void:
	_encounter = EncounterZone.new()
	_encounter.position = Vector3.ZERO
	add_child(_encounter)
	_spawn_training_wolf()
	_order_bar = OrderBar.new()
	_order_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_order_bar.offset_top = 96.0
	_order_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_order_bar.visible = false
	hud.add_child(_order_bar)
	_battle_menu = BattleMenu.new()
	_battle_menu.visible = false
	hud.add_child(_battle_menu)

## 练习场野狼：慢速绕圈游荡、永不主动攻击，只等玩家踏入遭遇圈。
func _spawn_training_wolf() -> void:
	var wolf: Node = EnemyScene.instantiate()
	wolf.name = "TrainingWolf"
	wolf.set("kind", EnemyScript.Kind.WOLF)
	wolf.set("move_speed", 0.8)
	wolf.set("patrol_only", true)
	wolf.position = Vector3(3.0, 0, -2.0)
	add_child(wolf)
	_wolf = wolf

func start_battle() -> void:
	_battle_running = true
	player.battle_mode = true
	player.velocity = Vector3.ZERO
	if is_instance_valid(_wolf):
		_wolf.set("battle_driven", true)
	var agi := int(GameState.effective_attributes().get("agi", Attributes.BASE))
	_battle_controller.set_units([
		BattleUnit.from_player(player, agi),
		BattleUnit.from_enemy(_wolf),
	])
	_battle_controller.begin_battle()
	_order_bar.visible = true
	_run_battle()

## 回合主循环：按 AT 顺序轮流行动，直到全歼 / 逃跑 / 玩家阵亡。
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
		else:
			await _enemy_command(unit)
		if _battle_running and not _battle_controller.all_enemies_dead() and player.alive:
			_battle_controller.finish_turn()
			# 每整轮回蓝结算在作战单位上，wrap 后抄回玩家实体（玩家才是权威）。
			_battle_controller.flush_player_mp()
		await get_tree().process_frame

## 玩家回合：自动走位到攻击距离 → 五选一指令（指令集见 BattleMenu.COMMANDS，两套场景共用）。
func _player_command(unit: BattleUnit) -> void:
	_auto_approach(unit)
	_battle_menu.open(BattleMenu.COMMANDS)
	var idx: int = await _battle_menu.confirmed
	_battle_menu.close()
	if not _battle_running:
		return
	var foe := _battle_controller.nearest_foe_to(unit)
	_face(foe)
	match idx:
		0:  # 攻击
			if foe != null and _in_attack_range(foe):
				player.battle_execute_attack(_battle_controller.attack_bonus(unit, foe))
			else:
				GameState.push_message("攻击落空 · 距离不够")
		1:  # 战技
			await _player_skill(unit)
		2:  # 防御
			unit.set_defend(true)
			GameState.push_message("防御姿态 · 本回合受伤大幅降低")
		3:  # 道具
			await _player_item()
		4:  # 逃跑
			if _battle_controller.flee(unit):
				GameState.push_message("成功脱离战斗")
				_end_battle(true, true)
			else:
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

## 把 _face 用到的"看向敌方/朝向目标"统一。
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

func _player_skill(unit: BattleUnit) -> void:
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

## 敌人回合：一步接近或攻击；玩家处于防御态时可弹反。
func _enemy_command(unit: BattleUnit) -> void:
	await get_tree().create_timer(0.55).timeout
	if not _battle_running or not player.alive:
		return
	var intent: String = unit.node.battle_advance(player.global_position)
	if intent != "攻击":
		return
	var dmg := float(unit.attack_power)
	var pu := _battle_controller.player_unit()
	if pu != null and pu.is_defending():
		if randf() < 0.3:
			GameState.push_message("弹反！攻势被荡开")
			return
		dmg *= 0.25
	player.take_damage(dmg)
	await get_tree().process_frame

func _end_battle(won: bool, fled := false) -> void:
	_battle_running = false
	player.battle_mode = false
	_order_bar.visible = false
	_battle_menu.visible = false
	if is_instance_valid(_wolf):
		_wolf.set("battle_driven", false)
	# 不再把快照 MP 写回玩家 —— 玩家的蓝由实体自己持有，收尾时单位只是镜像。
	# 旧实现正是在这里用开战快照覆盖 player.mp，把回合内花掉的蓝整笔退了回来。
	_battle_controller.force_win() if won else _battle_controller.force_lose()
	if won and not fled:
		GameState.push_message("练习战胜利 · 敌人全灭")
