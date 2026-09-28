extends Node
## 自由练习场：不写正式货币、任务或存档。场上只有一根打不坏的练功木桩，
## 用来练习攻击与剃；没有敌人波次，也没有清场结算。
## 机位与港口/科波山统一：低俯角透视 HD2D 镜头，移动前瞻 + 焦点收边；
## 视角与远近由玩家自己操作（中键拖动转视角、滚轮推拉距离），光标不再带动镜头。
const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
const HudScene := preload("res://scripts/ui/hud.tscn")
const AssetCatalog := preload("res://tools/preset_catalog.gd")
const CameraStyle := preload("res://scripts/world/jungle_camera_style.gd")
const Orbit := preload("res://scripts/world/camera_orbit_controls.gd")
const PortalScript := preload("res://scripts/world/scene_portal.gd")
## 提示文案里的键名现读（改键后不会还写着旧键）。
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")
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
	hud.show_panel("灰潮 · 自由练习场", ("轻松练习场地 / 不影响正式资源\n\n木桩用于练习斩击与闪避；野狼会缓慢巡逻，可练习追击和攻击方向。\n\n"
		+ "WASD 移动 · 左键斩击 · %s 剃 · %s 直踹\n%s 炸弹 · %s 药剂 · %s 按键说明。") % [
			KeyBindings.key_text("dodge"), KeyBindings.key_text("kick"), KeyBindings.key_text("bomb"),
			KeyBindings.key_text("potion"), KeyBindings.key_text("key_guide"),
		], "开始练习", start_practice)
	_build_encounter_demo()

func start_practice() -> void:
	player.position = Vector3.ZERO
	player.reset()
	player.set_physics_process(true)
	practice = true
	hud.hide_panel()
	hud.set_objective("自由练习  /  练习斩击、闪避和移动目标追击")

func _on_player_died() -> void:
	practice = false
	player.set_physics_process(false)
	player.input_dir = Vector2.ZERO
	hud.show_panel("倒下了", "在自由练习场倒下，随时可以重新开始。\n\n本模式不消耗逃脱币，不造成永久死亡。", "重新开始", start_practice)

func _process(delta: float) -> void:
	_update_camera(delta)

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
	var practice_field := GameState.campaign_practice
	var stage: int = -1 if practice_field else int(GameState.campaign.stage)
	var floor_cfg: Dictionary = _floor_config(stage)
	paving.set_shader_parameter("stone_color", floor_cfg.get("stone_color", Color("3a4a52")))
	paving.set_shader_parameter("detail_color", floor_cfg.get("detail_color", Color("202a31")))
	paving.set_shader_parameter("surface_kind", floor_cfg.get("surface_kind", 2))
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
	env.ambient_light_color = floor_cfg.get("ambient_color", Color("7798bd"))
	env.ambient_light_energy = floor_cfg.get("ambient_energy", 0.45)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.ssil_enabled = true
	env.ssil_intensity = 0.65
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.fog_enabled = true
	env.fog_light_color = floor_cfg.get("fog_color", Color("778f9d"))
	env.fog_density = floor_cfg.get("fog_density", 0.0015)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = floor_cfg.get("volumetric_density", 0.005)
	env.volumetric_fog_albedo = floor_cfg.get("fog_albedo", Color("aebfce"))
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_ambient_inject = 0.25
	add_child(world)
	_apply_stage_lighting(floor_cfg)
	# 补光（CoolSkyFill）已在场景里配好，与港口同一套参数。
	_build_boundary(stage)
	_backdrop_ring(stage)
	# 正式关卡按 stage 换布景；演武场练习保留中性场地，不摆地区门面与出口门。
	_dress_stage(stage)
	if practice_field:
		player.position = Vector3.ZERO
	else:
		_build_portals(stage)
		_build_route_cues(stage)
	if not campaign_managed:
		_spawn_dummy()

## 按战役阶段装配四种空间：废品场、城门检查坪、侍卫总部前院和夜间欢乐街。
## 建筑主要压在两翼，少数围墙/楼体启用素材碰撞，保证中央战斗与出入口畅通。
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

## 地面、雾色和主辅光共同区分四区：废土黄绿、城门冷灰、总部中性石色、欢乐街暖红夜色。
func _floor_config(stage: int) -> Dictionary:
	match stage:
		0:
			return {"stone_color": Color("705843"), "detail_color": Color("393b33"), "surface_kind": 0, "tile_scale": 0.32, "grout": 0.09,
				"bg_color": Color("514b40"), "ambient_color": Color("82917a"), "ambient_energy": 0.38,
				"fog_color": Color("8b9b79"), "fog_albedo": Color("a1aa8d"), "volumetric_density": 0.007,
				"sun_color": Color("e3b985"), "sun_energy": 0.88,
				"fill_color": Color("a8c0ad"), "fill_energy": 0.3}
		1:
			return {"stone_color": Color("77838d"), "detail_color": Color("39434c"), "surface_kind": 1, "tile_scale": 0.72, "grout": 0.035,
				"bg_color": Color("55636e"), "ambient_color": Color("8093aa"), "ambient_energy": 0.43,
				"fog_color": Color("7f91a0"), "fog_albedo": Color("aebbc2"), "volumetric_density": 0.004,
				"sun_color": Color("f0d4ad"), "sun_energy": 1.0,
				"fill_color": Color("9bb9d7"), "fill_energy": 0.32}
		2:
			return {"stone_color": Color("626f75"), "detail_color": Color("35424b"), "surface_kind": 2, "tile_scale": 0.67, "grout": 0.026,
				"bg_color": Color("4e626d"), "ambient_color": Color("91a5b9"), "ambient_energy": 0.48,
				"fog_color": Color("8496a0"), "fog_albedo": Color("b6c0c3"), "volumetric_density": 0.0035,
				"sun_color": Color("ffe0b8"), "sun_energy": 1.08,
				"fill_color": Color("a8c5e0"), "fill_energy": 0.36}
		3:
			return {"stone_color": Color("744d43"), "detail_color": Color("392b31"), "surface_kind": 3, "tile_scale": 0.78, "grout": 0.035,
				"bg_color": Color("3e3540"), "ambient_color": Color("93757f"), "ambient_energy": 0.36,
				"fog_color": Color("76555e"), "fog_albedo": Color("765861"), "volumetric_density": 0.0045,
				"sun_color": Color("ffb27e"), "sun_energy": 0.62,
				"fill_color": Color("7080a3"), "fill_energy": 0.26}
		_:
			return {}

func _apply_stage_lighting(floor_cfg: Dictionary) -> void:
	var sun := get_node_or_null("EveningSun") as DirectionalLight3D
	if sun:
		sun.light_color = floor_cfg.get("sun_color", sun.light_color)
		sun.light_energy = float(floor_cfg.get("sun_energy", sun.light_energy))
	var fill := get_node_or_null("CoolSkyFill") as DirectionalLight3D
	if fill:
		fill.light_color = floor_cfg.get("fill_color", fill.light_color)
		fill.light_energy = float(floor_cfg.get("fill_energy", fill.light_energy))

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
	_portal_visual("ExitPortalVisual", exit_at, Color("8b9498"), "出口 · 待解锁")

## 地面光圈把交战位置和北侧出口连成一条可读路线；战斗开始后收起中央提示。
func _build_route_cues(stage: int) -> void:
	var colors := [Color("d8b980"), Color("9bc3d5"), Color("e6c485"), Color("eab193")]
	var tint: Color = colors[clampi(stage, 0, 3)]
	_ground_disc("EncounterCue", Vector3(0, 0.035, -3.5), 2.5,
		Color(tint.r, tint.g, tint.b, 0.18))
	for z in [4.7, 2.2, -0.3, -6.3]:
		_ground_disc("RouteStep", Vector3(0, 0.038, z), 0.24,
			Color(tint.r, tint.g, tint.b, 0.34))
	var label := Label3D.new()
	label.name = "EncounterCueLabel"
	label.text = "交战区 · %s 开始" % KeyBindings.key_text("interact")
	label.position = Vector3(0, 0.42, -3.5)
	label.font_size = 32
	label.pixel_size = 0.009
	label.outline_size = 12
	label.modulate = tint
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func set_route_phase(phase: String, can_advance: bool) -> void:
	var cue := get_node_or_null("EncounterCue") as MeshInstance3D
	var cue_label := get_node_or_null("EncounterCueLabel") as Label3D
	if cue == null or cue_label == null:
		return
	var preparing := phase == "prepare"
	cue.visible = preparing
	cue_label.visible = preparing
	var gate := get_node_or_null("ExitPortalVisual") as Node3D
	if gate == null:
		return
	var label := gate.get_node("Label") as Label3D
	var ring := gate.get_node("Ring") as MeshInstance3D
	var open := phase == "cleared" and can_advance
	var destinations := ["王都入口", "侍卫总部", "欢乐街", "科尔波山外围"]
	label.text = "前往 · %s" % destinations[clampi(GameState.campaign.stage, 0, 3)] if open else ("出口 · 完成当前目标" if phase == "cleared" else "出口 · 待解锁")
	label.modulate = Color("ffe3a0") if open else Color("aab5b9")
	var material := ring.material_override as StandardMaterial3D
	material.albedo_color = Color(1.0, 0.72, 0.28, 0.48) if open else Color(0.43, 0.51, 0.55, 0.17)

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

## 1.2 废品终点站：南北入口与出口之间留出中央战斗场，废墟沿两翼错位排布。
func _dress_junk_station() -> void:
	_ground_patch("ScrapTrack", Vector3(0, 0.014, 0), Vector2(6.5, 21.0), Color(0.25, 0.19, 0.13, 0.34))
	for at in [Vector3(-8.2, 0.02, -3.0), Vector3(8.0, 0.02, 2.0), Vector3(-7.5, 0.02, 8.0)]:
		_ground_disc("MudPool", at, 1.8, Color(0.13, 0.17, 0.16, 0.24))
	# 破棚错开压在两翼，保留一条从南入口直望城门的战斗通道。
	_prop("SM_kushuicun_pofangzi002", Vector3(-10.8, 0, -7.6), 24, 0.85, true)
	_prop("SM_kushuicun_pofangzi002", Vector3(11.0, 0, 5.5), 198, 0.72, true)
	_prop("SM_kushuicun_pofangzi002", Vector3(-11.0, 0, 7.3), -12, 0.48, true)
	# 垃圾堆、木箱和枯草贴边形成松散掩体；玩家与流民的主要交战区保持开阔。
	_prop("SM_NJ_Shitoudui001", Vector3(-7.4, 0, 4.3), 26, 1.15)
	_prop("SM_NJ_Shitoudui001", Vector3(-6.5, 0, -0.8), -18, 1.0)
	_prop("SM_NJ_Shitoudui001", Vector3(-8.0, 0, -5.1), 42, 1.2)
	_prop("SM_NJ_Shitoudui001", Vector3(8.2, 0, 3.8), -32, 1.1)
	_prop("SM_NJ_Shitoudui001", Vector3(6.7, 0, -1.6), 14, 0.95)
	_prop("SM_NJ_Shitoudui001", Vector3(8.5, 0, -6.2), -48, 1.0)
	_prop("SM_Box001Close", Vector3(-9.4, 0, 1.4), 18, 0.85)
	_prop("SM_Box001Open", Vector3(-6.6, 0, -7.2), -22, 0.78)
	_prop("SM_Box001Open", Vector3(9.6, 0, -2.8), 31, 0.8)
	_prop("SM_Box001Close", Vector3(6.2, 0, 6.7), -16, 0.86)
	_prop("SM_changzacao001", Vector3(-6.0, 0, 6.6), 12, 1.35)
	_prop("SM_changzacao001", Vector3(-6.4, 0, -3.5), -24, 1.5)
	_prop("SM_changzacao001", Vector3(6.3, 0, 1.4), 36, 1.25)
	_prop("SM_changzacao001", Vector3(7.1, 0, -8.0), -12, 1.4)
	_prop("SM_Item_luzi001", Vector3(9.1, 0, -4.2), -18, 0.65)
	_prop("SM_NJ_Shitoudui001", Vector3(-10.5, 0, 1.4), 12, 1.25)
	# 拾荒营地的柴堆、矿渣与包裹贴着路边摆放，中央留给斩击和闪避。
	for at in [Vector3(-5.9, 0, -7.6), Vector3(6.0, 0, 6.0), Vector3(-6.1, 0, 1.0)]:
		_prop("SM_Item_muchai001", at, 20, 1.0)
	for at in [Vector3(-7.5, 0, 2.8), Vector3(7.4, 0, -6.6), Vector3(8.3, 0, 8.1)]:
		_prop("SM_Item_Tiekuang001", at, -12, 0.65)
	for at in [Vector3(-5.9, 0, 5.4), Vector3(6.3, 0, -3.6)]:
		_prop("SM_Item_zhuzibaoguo001", at, 12, 0.75)

## 1.3 王都入口：城门 + 两侧高墙 + 石灯石柱，形成一条准入通道。
func _dress_city_gate() -> void:
	_ground_patch("GateInspectionYard", Vector3(0, 0.016, -4.8), Vector2(13.5, 8.0), Color(0.56, 0.64, 0.69, 0.24))
	_prop("SM_xgg_chengmen001", Vector3(0, 0, -11.0), 0, 0.65)          # 北侧城门
	# 黑石城墙连接城门两翼，远景构成完整的王都边界。
	for side in [-1.0, 1.0]:
		_masonry_box("OuterCityWall", Vector3(side * 12.3, 2.0, -13.0),
			Vector3(19.0, 4.0, 1.4), Color("48545b"))
		for i in range(7):
			_masonry_box("CityBattlement", Vector3(side * (3.3 + float(i) * 2.4), 4.4, -13.0),
				Vector3(1.25, 0.8, 1.55), Color("48545b"))
	for sx in [-1.0, 1.0]:
		_prop("SM_JN_Weiqiang001", Vector3(sx * 8.0, 0, -7.5), 90 if sx > 0 else -90, 1.2, true)
		_prop("SM_JN_Weiqiang001", Vector3(sx * 8.0, 0, -4.0), 90 if sx > 0 else -90, 1.2, true)
		_prop("SM_Licheng_shizhuzi001", Vector3(sx * 6.5, 0, -2.5), 0, 1.1)
		_prop("SM_NJ_ShiDeng_001", Vector3(sx * 9.5, 0, -0.5), 0, 1.0)
		_prop("SM_xgg_fangzi001", Vector3(sx * 10.1, 0, -8.5), 90 if sx > 0 else -90, 0.42)
	# 南侧出口两柱夹道
	for sx in [-1.0, 1.0]:
		_prop("SM_Licheng_shizhuzi001", Vector3(sx * 7.0, 0, 7.5), 0, 1.1)
	_prop("SM_Box001Close", Vector3(-6.6, 0, -1.0), 12, 0.7)
	_prop("SM_Box001Close", Vector3(6.5, 0, -1.2), -12, 0.7)
	for side in [-1.0, 1.0]:
		_prop("SM_Box001Close", Vector3(side * 7.8, 0, 3.8), 20, 0.88)
		_prop("SM_Item_muchai001", Vector3(side * 9.0, 0, -6.8), 0, 0.86)
		_prop("SM_Item_luzi003", Vector3(side * 6.9, 0, -5.8), 0, 0.8)

## 1.4 侍卫总部：办公楼压在后景，前院留出报到、切磋与领取军械的空间。
func _dress_guard_hq() -> void:
	_ground_patch("GuardCourtyard", Vector3(0, 0.016, 0.0), Vector2(15.0, 14.0), Color(0.40, 0.48, 0.52, 0.2))
	_ground_disc("SparringRing", Vector3(0, 0.035, -2.8), 4.3, Color(0.75, 0.56, 0.29, 0.24))
	for side in [-1.0, 1.0]:
		_masonry_box("CourtyardWall", Vector3(side * 14.0, 1.35, -1.0),
			Vector3(1.0, 2.7, 26.0), Color("4d6069"))
	_prop("SM_NJ_WuGuan001", Vector3(0, 0, -11.4), 0, 0.9)  # 北侧总部正门
	_prop("SM_NJ_Fangzi011", Vector3(-9.4, 0, -10.8), 90, 0.58) # 办公侧翼
	_prop("SM_NJ_Fangzi012", Vector3(9.4, 0, -10.8), -90, 0.58) # 军械侧翼
	for sx in [-1.0, 1.0]:
		for z in [-5.0, 2.5, 9.5]:
			_prop("SM_NJ_Zhuziweilan001", Vector3(sx * 10.8, 0, z), 90 if sx > 0 else -90, 0.68, true)
		_prop("SM_Licheng_shizhuzi001", Vector3(sx * 9.5, 0, 9.0), 0, 1.0)
		_prop("SM_NJ_ShiDeng_001", Vector3(sx * 7.0, 0, -5.0), 0, 0.9)
		_prop("SM_Item_NJhuojia001", Vector3(sx * 7.0, 0, -1.8), 0, 0.82)
	# 低木牌提示操练区域，不切断院心的闪避路线。
	for at in [Vector3(-6.2, 0, 4.0), Vector3(6.2, 0, 4.0)]:
		_prop("SM_NJ_ZhuPai002", at, 0, 0.84)
	for side in [-1.0, 1.0]:
		_prop("SM_Item_Nwuqi001", Vector3(side * 8.3, 0, -7.4), 0, 0.83)
		_prop("SM_Item_muchai001", Vector3(side * 8.7, 0, 3.3), 0, 0.7)

## 1.5 欢乐街：两列楼阁围出长街，目标客栈落在北侧一翼，战斗留在中央。
func _dress_pleasure_street() -> void:
	_ground_patch("PleasureStreetRunner", Vector3(0, 0.017, 0), Vector2(6.0, 22.0), Color(0.38, 0.20, 0.18, 0.24))
	for side in [-1.0, 1.0]:
		_ground_patch("StreetGutter", Vector3(side * 5.3, 0.018, 0), Vector2(0.8, 22.0), Color(0.08, 0.07, 0.09, 0.38))
	var west: Array[String] = ["SM_NJ_JiuGuan001", "SM_JN_fangzi001", "SM_JN_fangzi002"]
	var east: Array[String] = ["SM_JN_fangzi002", "SM_JN_fangzi001", "SM_NJ_Fangzi011"]
	for i in range(3):
		var z := -6.5 + float(i) * 7.0
		_prop(west[i], Vector3(-10.0, 0, z), 90, 0.68, true)
		_prop(east[i], Vector3(10.0, 0, z), -90, 0.68, true)
	# 屋顶与檐廊只形成纵深，不作为可走路线；灯笼落在街沿，不挡欧卡与护卫。
	for z in [-6.0, 0.5, 7.0]:
		for side in [-1.0, 1.0]:
			var at := Vector3(side * 7.2, 3.1, z)
			_prop("SM_Item_taidenglong001", at, 0, 0.66)
			_add_warm_lamp(at + Vector3(0, 0.2, 0), 1.05, 7.5)
	for z in [-1.5, 4.0]:
		_prop("SM_Item_NJtanwei001", Vector3(-6.6, 0, z), 90, 0.74)
		_prop("SM_Item_NJtanwei002", Vector3(6.6, 0, z + 1.0), -90, 0.74)
	_prop("SM_Item_pingfeng001", Vector3(-8.2, 0, 2.0), 20, 0.78)
	_prop("SM_Item_pingfeng001", Vector3(8.2, 0, -2.5), -20, 0.78)
	_prop("SM_NJ_ZhuZhuozi001", Vector3(-6.1, 0, -5.0), 15, 0.75)
	_prop("SM_NJ_ZhuZhuozi001", Vector3(6.1, 0, -4.6), -10, 0.75)
	for side in [-1.0, 1.0]:
		_prop("SM_Item_jiutanzi04", Vector3(side * 6.8, 0, 5.8), 0, 0.72)

## 远景按地区变化：练习场用密林，废品场用棚屋与垃圾坡，王都关卡用屋脊和城墙。
func _backdrop_ring(stage: int) -> void:
	if stage == 0:
		_backdrop_junk_station()
		return
	if stage in [1, 2, 3]:
		_backdrop_city(stage)
		return
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

func _backdrop_junk_station() -> void:
	# 北侧远景露出下一关的王都城门，让废品场出口有明确的地理方向。
	_prop("SM_xgg_chengmen001", Vector3(0, 0, -19.0), 0, 0.38)
	for side in [-1.0, 1.0]:
		_prop("SM_kushuicun_pofangzi002", Vector3(side * 20.5, 0, -18.0), -90.0 * side, 0.5)
		_prop("SM_kushuicun_pofangzi002", Vector3(side * 19.0, 0, 18.5), 90.0 * side, 0.42)
		for z in [-20.0, -11.0, 0.0, 11.0, 20.0]:
			var x: float = side * (17.0 + rng.randf_range(0.0, 2.0))
			_prop("SM_NJ_Shitoudui001", Vector3(x, 0, z + rng.randf_range(-1.3, 1.3)), rng.randf_range(-40, 40), rng.randf_range(0.75, 1.05))
			if rng.randf() < 0.6:
				_prop("SM_changzacao001", Vector3(x + side * 1.4, 0, z + 2.0), rng.randf_range(-35, 35), 0.8)

func _backdrop_city(stage: int) -> void:
	var buildings: Array[String] = []
	match stage:
		1:
			buildings = ["SM_xgg_fangzi001", "SM_xgg_fangzi004"]
		2:
			buildings = ["SM_NJ_Fangzi011", "SM_NJ_Fangzi012"]
		3:
			buildings = ["SM_JN_fangzi001", "SM_NJ_JiuGuan001"]
	for side in [-1.0, 1.0]:
		for i in range(4):
			var at := Vector3(side * 21.0, 0, -20.0 + float(i) * 13.2)
			var side_offset := 1 if side > 0.0 else 0
			var title: String = buildings[(i + side_offset) % buildings.size()]
			_prop(title, at, 90.0 if side < 0.0 else -90.0, 0.58 if i % 2 == 0 else 0.48)
	for i in range(3):
		var title: String = buildings[i % buildings.size()]
		_prop(title, Vector3(-14.5 + float(i) * 14.5, 0, -23.0), 0, 0.52)

## 各区边界保持进出口可见；城市侧墙与店面可碰撞，玩家活动范围仍由 bounds 收边。
func _build_boundary(stage: int) -> void:
	match stage:
		0:
			_build_junk_station_boundary()
			return
		1:
			_build_gate_boundary()
			return
		2:
			_build_hq_boundary()
			return
		3:
			_build_street_boundary()
			return
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

func _build_gate_boundary() -> void:
	for side in [-1.0, 1.0]:
		for z in [-8.0, -2.0, 4.0, 10.0]:
			_prop("SM_JN_Weiqiang001", Vector3(side * 12.6, 0, z), 90 if side > 0 else -90, 0.92, true)
		_prop("SM_Licheng_shizhuzi001", Vector3(side * 11.7, 0, -10.5), 0, 1.0)
		_prop("SM_NJ_ShiDeng_001", Vector3(side * 11.7, 0, 8.7), 0, 0.9)
	for x in [-6.0, 6.0]:
		_prop("SM_xgg_jiangjunfupaizi001", Vector3(x, 0, -11.0), 0, 0.58)

func _build_hq_boundary() -> void:
	for side in [-1.0, 1.0]:
		for z in [-4.0, 3.0, 9.0]:
			_prop("SM_NJ_Zhuziweilan001", Vector3(side * 11.2, 0, z), 90 if side > 0 else -90, 0.82, true)
		for z in [-8.5, 10.5]:
			_prop("SM_Licheng_shizhuzi001", Vector3(side * 11.0, 0, z), 0, 0.95)
	for side in [-1.0, 1.0]:
		_prop("SM_NJ_ShiDeng_001", Vector3(side * 7.5, 0, 7.8), 0, 0.86)

func _build_street_boundary() -> void:
	for side in [-1.0, 1.0]:
		for z in [-9.0, 0.0, 9.0]:
			_prop("SM_Item_taidenglong001", Vector3(side * 10.9, 3.1, z), 0, 0.72)
			_prop("SM_NJ_ShiDeng_001", Vector3(side * 11.7, 0, z), 0, 0.76)

## 废品站边缘用残石、木箱与杂草收住画面，避免误读成规整的演武场。
## 入口和出口正前方不放大型装饰，所有元素仍是无碰撞景物。
func _build_junk_station_boundary() -> void:
	_prop("SM_NJ_Shitoudui001", Vector3(-12.8, 0, -11.2), 18, 1.2)
	_prop("SM_NJ_Shitoudui001", Vector3(12.7, 0, -10.8), -28, 1.0)
	_prop("SM_NJ_Shitoudui001", Vector3(-13.0, 0, 10.8), -16, 1.05)
	_prop("SM_Box001Close", Vector3(12.5, 0, 10.7), 24, 0.85)
	_prop("SM_changzacao001", Vector3(-13.5, 0, -3.8), 14, 1.5)
	_prop("SM_changzacao001", Vector3(-13.4, 0, 4.0), -18, 1.25)
	_prop("SM_changzacao001", Vector3(13.4, 0, -4.5), 32, 1.35)
	_prop("SM_changzacao001", Vector3(13.5, 0, 3.6), -24, 1.5)

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

func _ground_patch(title: String, at: Vector3, size: Vector2, tint: Color) -> void:
	var patch := MeshInstance3D.new()
	patch.name = title
	var plane := PlaneMesh.new()
	plane.size = size
	patch.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	patch.material_override = material
	patch.position = at
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(patch)

func _ground_disc(title: String, at: Vector3, radius: float, tint: Color) -> void:
	var disc := MeshInstance3D.new()
	disc.name = title
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.025
	disc.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = material
	disc.position = at
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)

func _masonry_box(title: String, at: Vector3, size: Vector3, tint: Color) -> void:
	var wall := MeshInstance3D.new()
	wall.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	wall.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/trial_wall.gdshader")
	material.set_shader_parameter("stone_color", tint)
	wall.material_override = material
	wall.position = at
	add_child(wall)

func _add_warm_lamp(at: Vector3, energy: float, light_range: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.name = "WarmStreetLamp_%d" % get_child_count()
	lamp.position = at
	lamp.light_color = Color("ff8055")
	lamp.light_energy = energy
	lamp.omni_range = light_range
	lamp.omni_attenuation = 1.35
	lamp.shadow_enabled = false
	add_child(lamp)

## 放一个共享库预置素材；大型楼体和墙段可启用素材碰撞，保持道路畅通。
## size 是整体缩放倍数。
func _prop(title: String, at: Vector3, yaw := 0.0, size := 1.0, with_collision := false) -> void:
	var asset: HD2DAsset = AssetCatalog.asset(title)
	if asset == null:
		return
	var node := HD2DProp.new()
	node.name = title
	node.asset = asset
	node.asset_overrides = {"static_collision": with_collision}
	node.position = at
	node.rotation_degrees = Vector3(0, yaw, 0)
	node.scale = Vector3.ONE * size
	add_child(node)

var rng := RandomNumberGenerator.new()

## ---------- 实时战斗练习敌人 ----------
func _build_encounter_demo() -> void:
	_spawn_training_wolf()

func _spawn_training_wolf() -> void:
	var wolf: Node = EnemyScene.instantiate()
	wolf.name = "TrainingWolf"
	wolf.set("kind", EnemyScript.Kind.WOLF)
	wolf.set("move_speed", 0.8)
	wolf.set("patrol_only", true)
	wolf.position = Vector3(3.0, 0, -2.0)
	add_child(wolf)
