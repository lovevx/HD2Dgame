extends Node3D
## 第二幕 3D 过场播片：船上醒来 → 破晓海面 → 靠近灰潮港码头停靠 → 黑场进港口场景。
## 复用港口同款素材（水面 shader / 预置 3D 库 / 辉光+雾+电影色调），运行时实例化不生成 .tscn。
## 节奏与第一幕一致：打字机 + 停留自动进下一镜；点击/空格跳过。

const AssetCatalog := preload("res://tools/preset_catalog.gd")
const WATER_SHADER := preload("res://shaders/harbor_water.gdshader")
const PAVING_SHADER := preload("res://shaders/harbor_paving.gdshader")
const SKY_SHADER := preload("res://shaders/boat_sky.gdshader")
const PLAYER_FRAMES := preload("res://assets/characters/player_frames_video.tres")
const DialogueBoxScript := preload("res://scripts/ui/dialogue_box.gd")
const CHAR_INTERVAL := 0.045
const SUN_DIR := Vector3(0.38, 0.34, -0.86)   # 与太阳光/天空盘一致（近单位长度）

const SHIP_LINES: Array[String] = [
 "「契约已签订 · 欢迎来到轮回乐园」",
 "意识在黑暗中沉浮。不知过了多久，身下传来微微的起伏——",
 "你睁开眼，正躺在一艘船的甲板上，海风裹着咸腥味灌进鼻腔。",
 "船身缓缓靠上灰潮港的码头，缆绳落定，水手吆喝着搭好跳板。",
	"一名穿着旧皮甲的向导迎了上来。",
 "港口向导：「新人，快去东侧的试炼场地熟悉一下身手吧！」",
]

## 每行 → {phase:0..3 镜头相位, hold:停留秒, cap:截屏时间点(绝对时间轴), title:中心摆字}。
const BEATS: Array[Dictionary] = [
 {"phase": 0, "hold": 3.0, "cap": 1.6, "title": "「契约已签订 · 欢迎来到轮回乐园」"},
 {"phase": 0, "hold": 2.6, "cap": 3.4},
 {"phase": 1, "hold": 2.6, "cap": 5.8},
 {"phase": 2, "hold": 2.8, "cap": 8.9},
 {"phase": 3, "hold": 2.2, "cap": 12.4},
 {"phase": 3, "hold": 3.2, "cap": 14.6},
]

const WATER_TOP := -0.72        # 水面高度（与港口同口径：船吃水 -0.72）
const BOAT_START := Vector3(6.0, WATER_TOP, 56.0)
const BOAT_DOCK := Vector3(-4.0, WATER_TOP, 22.0)
const DOCK_Z := 18.0            # 码头栈桥轴线
const DAWN_START := 0.08        # 相位0起始破晓度
const DAWN_END := 0.96

var _t := 0.0
var _line_index := -1
var _char_index := 0
var _type_timer := 0.0
var _finished := false
var _hold := 1.0
var _hold_t := 0.0
var _fading := false
var _capture_static := false

var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var boat: Node3D
var hero: AnimatedSprite3D
var layer: CanvasLayer
var glow_ui: Control
var _port_pts: Array[Vector3] = []
var speaker_label: Label
var text_label: Label
var hint_label: Label
var subtitle_speaker_label: Label
var subtitle_text_label: Label
var subtitle_hint_label: Label
var subtitle_band: ColorRect
var subtitle_box: VBoxContainer
var dialogue_box
var title_label: Label
var fade_rect: ColorRect

func _ready() -> void:
	_build_environment()
	_build_water()
	_build_boat()
	_build_player()
	_build_dock()
	_build_shore()
	_build_ui()
	_build_camera()
	_build_skyball()
	_update_dawn(DAWN_START)
	_advance_line()

# ---------------------------------------------------------------- 世界搭建

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("02040a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.58, 0.72)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.3
	# 指数雾关掉：会糊掉天空盒；岸雾用 FogVolume 局部替代
	env.fog_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 0.5
	sun.light_specular = 0.3
	add_child(sun)
	sun.look_at(sun.global_position + SUN_DIR, Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.55, 0.7, 0.88)
	fill.light_energy = 0.22
	fill.light_specular = 0.05
	fill.rotation_degrees = Vector3(-18, -120, 0)
	add_child(fill)

## 相机子节点的天空盒大球（跟着镜头，半径在 far 之内）。
func _build_skyball() -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 4800.0
	sphere.height = 9600.0
	sphere.radial_segments = 48
	sphere.rings = 24
	ball.mesh = sphere
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	ball.material_override = sky_mat
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(ball)

func _fog_volume(pos: Vector3, extents: Vector3, density: float) -> void:
	var vol := FogVolume.new()
	vol.size = extents
	var mat := FogMaterial.new()
	mat.albedo = Color(0.72, 0.78, 0.83)
	mat.density = density
	vol.material = mat
	vol.position = pos
	add_child(vol)

func _build_water() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(560, 0.3, 560)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	body.material_override = mat
	body.position = Vector3(0, WATER_TOP - 0.15, 0)
	add_child(body)

func _spawn_prop(title: String, pos: Vector3, yaw: float = 0.0) -> Node3D:
	var asset: HD2DAsset = AssetCatalog.asset(title)
	if asset == null:
		return null
	var node := HD2DProp.new()
	node.asset_overrides = {"static_collision": false}
	node.asset = asset
	node.position = pos
	node.rotation.y = yaw
	add_child(node)
	return node

## 递归求节点网格 AABB 的最高点（世界坐标），用于把角色放到船顶。
func _mesh_top(node: Node3D) -> float:
	var top := -INF
	var stack: Array[Node3D] = [node]
	while not stack.is_empty():
		var n: Node3D = stack.pop_back()
		if n is MeshInstance3D:
			var b := (n as MeshInstance3D).get_aabb()
			for i in 8:
				var corner := Vector3(
					b.position.x + b.size.x * float(i & 1),
					b.position.y + b.size.y * float((i >> 1) & 1),
					b.position.z + b.size.z * float((i >> 2) & 1))
				var w: Vector3 = (n as MeshInstance3D).global_transform * corner
				top = maxf(top, w.y)
		for child in n.get_children():
			if child is Node3D:
				stack.append(child)
	return top

func _build_boat() -> void:
	boat = _spawn_prop("SM_JN_xiaochuan001", BOAT_START)
	# 默认朝向：船艏朝 -Z（码头方向）；不要在构造里翻转 yaw

## 甲板上的契约者：独立 AnimatedSprite3D（同游戏参数），待机背对镜头。
func _build_player() -> void:
	hero = AnimatedSprite3D.new()
	hero.sprite_frames = PLAYER_FRAMES
	hero.offset = Vector2(0, 64)
	hero.pixel_size = 0.016
	hero.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hero.shaded = true
	hero.alpha_cut = 1
	hero.texture_filter = 0
	hero.modulate = Color(1, 1, 1)
	var clip := &"idle_up"
	if PLAYER_FRAMES.has_animation(clip):
		hero.animation = clip
		hero.play()
	(boat if boat else self).add_child(hero)
	call_deferred("_place_hero")

func _place_hero() -> void:
	if boat == null:
		return
	# 甲板顶部以船体局部坐标计算一次，作为船的子树随船起伏；略偏号位让背后镜头看清轮廓
	var top_local := _mesh_top(boat) - boat.global_position.y
	hero.position = Vector3(0.3, top_local + 0.03, 0.1)

func _paving_mat() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PAVING_SHADER
	mat.set_shader_parameter("stone_color", Color(0.38, 0.43, 0.45))
	mat.set_shader_parameter("tile_scale", 1.0)
	return mat

func _box(pos: Vector3, size: Vector3, mat: Material) -> Node3D:
	var body := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	body.mesh = mesh
	body.material_override = mat
	body.position = pos
	add_child(body)
	return body

func _build_dock() -> void:
	var paving := _paving_mat()
	# 栈桥主面（沿 X 轴，DOCK_Z 靠海一侧）
	_box(Vector3(0, -0.16, 16.5), Vector3(44, 0.3, 6.5), paving)
	_box(Vector3(6, 1.15, 20.5), Vector3(20, 0.16, 1.6), paving)
	_box(Vector3(-12, 1.15, 20.5), Vector3(22, 0.16, 1.6), paving)
	# 桥下支柱
	for i in range(7):
		_box(Vector3(-18.0 + i * 7.0, -2.4, 16.5), Vector3(0.5, 4.6, 0.5), paving)
	# 岸沿木桩 + 系缆
	_spawn_prop("SM_mjsz_Mudunzi001", Vector3(-13.0, 0.0, 17.6))
	_spawn_prop("SM_mjsz_Mudunzi001", Vector3(10.0, 0.0, 17.8), 0.4)
	_spawn_prop("SM_gsc_shengzi001", Vector3(8.0, 1.0, 17.4), 0.6)
	_spawn_prop("SM_JN_matou", Vector3(2.0, -4.31, 18.0))
	# 沿岸灯笼
	_spawn_prop("SM_NJ_ShiDeng_001", Vector3(-20.0, 0.0, 17.0))
	_spawn_prop("SM_NJ_ShiDeng_001", Vector3(20.0, 0.0, 17.0), PI)
	# 停靠摆渡船
	_spawn_prop("SM_JN_xiaochuan002", Vector3(-14.0, WATER_TOP, 13.5), 0.6)
	_spawn_prop("SM_JN_xiaochuan003", Vector3(12.0, WATER_TOP, 12.5), -0.7)
	_spawn_prop("SM_JN_xiaochuan004", Vector3(16.5, WATER_TOP, 24.5), 0.3)
	_spawn_prop("SM_JN_yuchuan003", Vector3(-21.0, WATER_TOP, 24.0), -0.4)
	_spawn_prop("SM_JN_yuchuan004", Vector3(22.0, WATER_TOP, 19.0), 0.9)
	# 岸雾（局部 FogVolume，不糊天空盒；近岸轻一些以免遮住港口）
	_fog_volume(Vector3(-2.0, 1.4, 13.0), Vector3(64, 7, 20), 0.032)
	_fog_volume(Vector3(6.0, 1.0, 54.0), Vector3(56, 7, 40), 0.1)
	# 沿岸暖灯（OmniLight 光晕 + 2D 投影光点，远处也可见）
	_lamp(Vector3(-15.0, 2.2, 16.5))
	_lamp(Vector3(-5.0, 2.2, 16.5))
	_lamp(Vector3(6.0, 2.2, 16.5))
	_lamp(Vector3(15.0, 2.2, 16.5))
	_lamp(Vector3(0.0, 4.0, 16.0), 2.6, 70.0)   # 港区主灯，远望可见
	for px4 in [-15.0, -5.0, 6.0, 15.0]:
		_port_pts.append(Vector3(px4, 2.2, 16.5))
	_port_pts.append(Vector3(0.0, 4.0, 16.0))

func _lamp(pos: Vector3, energy: float = 1.4, rangez: float = 26.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.42)
	l.light_energy = energy
	l.omni_range = rangez
	l.position = pos
	add_child(l)

func _build_shore() -> void:
	# 远景北岸：石堤链条（压低些，给天空留呼吸）
	for i in range(9):
		var x := -40.0 + i * 10.5
		var sx := lerpf(1.0, 1.6, _randh(i, 3.0))
		var sy := lerpf(1.0, 1.7, _randh(i, 4.0))
		var sz := lerpf(1.0, 1.5, _randh(i, 5.0))
		var title: String = "SM_Jiangnan_xuanya00%d" % (1 + int(_randh(i, 2.0) * 7.0))
		var p := _spawn_prop(title, Vector3(x, WATER_TOP - 0.2, -6.0 + _randh(i, 6.0) * 4.0), _randh(i, 7.0) * TAU)
		if p:
			p.scale = Vector3(sx, 1.0, sz)
	# 房屋剪影带
	var houses := ["SM_JN_fangzi001", "SM_JN_fangzi002", "SM_JN_fangzi003", "SM_JN_fangzi005", "SM_JN_fangzi006", "SM_JN_fangzi007"]
	for i in range(6):
		var x := -26.0 + i * 10.0
		var p := _spawn_prop(houses[i % houses.size()], Vector3(x, WATER_TOP - 0.1, -14.0 - _randh(i, 8.0) * 3.0), _randh(i, 9.0) * 0.5 - 0.25)
		if p:
			p.scale = Vector3.ONE * lerpf(1.0, 1.6, _randh(i, 4.0))
	# 树
	_spawn_prop("SM_1songbaiB01_LODs", Vector3(-8.0, WATER_TOP - 0.2, -10.0), 0.5)
	_spawn_prop("SM_1songbaiA01_LODs", Vector3(6.0, WATER_TOP - 0.2, -12.0), -0.4)
	_spawn_prop("SM_1yuanbai01_LODs", Vector3(18.0, WATER_TOP - 0.2, -9.0), 0.9)
	_spawn_prop("SM_1yuanbai02_LODs", Vector3(-20.0, WATER_TOP - 0.2, -8.5), -0.8)
	# 礁石散点
	for i in range(6):
		var x := -32.0 + i * 13.0
		_spawn_prop("SM_DM_Zudangshitou001", Vector3(x, WATER_TOP - 0.5, 6.0 + _randh(i, 1.0) * 6.0), _randh(i, 2.0) * TAU)

func _randh(i: float, seedv: float) -> float:
	var s := sin(i * 12.9898 + seedv * 78.233) * 43758.5453
	return s - floor(s)

# ---------------------------------------------------------------- 摄像机

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 33.0
	cam.near = 0.05
	cam.far = 6000.0
	cam.current = true
	add_child(cam)

# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	# 港口光点 2D 投影层（最底，字幕之上盖住也 OK——光点本身就不该被 UI 挡住）
	glow_ui = Control.new()
	glow_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow_ui.draw.connect(_draw_port_glow)
	layer.add_child(glow_ui)
	# 顶部细黑边（电影感）
	var band := ColorRect.new()
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 96
	band.color = Color(0, 0, 0, 0.9)
	layer.add_child(band)
	subtitle_band = ColorRect.new()
	subtitle_band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle_band.offset_top = -172
	subtitle_band.color = Color(0, 0, 0, 0.42)
	layer.add_child(subtitle_band)
	subtitle_box = VBoxContainer.new()
	subtitle_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	subtitle_box.offset_left = 240
	subtitle_box.offset_right = -240
	subtitle_box.offset_top = -150
	subtitle_box.offset_bottom = -34
	subtitle_box.alignment = BoxContainer.ALIGNMENT_END
	subtitle_box.add_theme_constant_override("separation", 8)
	layer.add_child(subtitle_box)
	subtitle_speaker_label = _label(subtitle_box, "", 26, Color("ebd6a2"))
	subtitle_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_text_label = _label(subtitle_box, "", 31, Color("e8f1f6"))
	subtitle_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_hint_label = _label(subtitle_box, "", 18, Color("7d94a8"))
	subtitle_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_box = DialogueBoxScript.new()
	dialogue_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dialogue_box)
	dialogue_box.call("set_panel_top_ratio", 0.56)
	_set_dialogue_mode(false)
	title_label = _label(layer, "", 48, Color("f2dc9b"))
	title_label.position = Vector2(0, 268)
	title_label.size = Vector2(1920, 90)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_constant_override("outline_size", 10)
	title_label.hide()
	fade_rect = ColorRect.new()
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.hide()
	layer.add_child(fade_rect)

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.04, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label

func _set_dialogue_mode(show_dialogue: bool) -> void:
	dialogue_box.visible = show_dialogue
	subtitle_band.visible = not show_dialogue
	subtitle_box.visible = not show_dialogue
	if show_dialogue:
		speaker_label = dialogue_box.get("speaker_label") as Label
		text_label = dialogue_box.get("text_label") as Label
		hint_label = dialogue_box.get("hint_label") as Label
	else:
		speaker_label = subtitle_speaker_label
		text_label = subtitle_text_label
		hint_label = subtitle_hint_label

# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	if _capture_static:
		return
	_t += delta
	if sky_mat:
		sky_mat.set_shader_parameter("u_t", _t)
	_update_dawn(_dawn())
	_camera_and_boat()
	glow_ui.queue_redraw()
	if _fading:
		return
	_type_step(delta)
	if _finished:
		_hold_t += delta
		if _hold_t >= _hold:
			_advance_line()

## 破晓推进：整体时间轴线性驱动（0→14s 从夜到昼）。
func _dawn() -> float:
	return clampf(DAWN_START + (_t / 14.0) * (DAWN_END - DAWN_START), DAWN_START, DAWN_END)

## 破晓推进：天空盒色带 + 主光 + 环境光同步变化。
func _update_dawn(p: float) -> void:
	if sky_mat == null or not is_instance_valid(sky_mat):
		return
	sky_mat.set_shader_parameter("u_amber", p)
	sky_mat.set_shader_parameter("u_stars", 1.0 - p)
	sky_mat.set_shader_parameter("u_top_col", Color("05070c").lerp(Color("24364b"), p * 0.85))
	sky_mat.set_shader_parameter("u_hor_col", Color("0d1a28").lerp(Color("f2b36a"), p * 0.9))
	sky_mat.set_shader_parameter("u_ground_col", Color("02040a").lerp(Color("3a2a1c"), p * 0.5))
	sky_mat.set_shader_parameter("u_sun_col", Color(1.0, 0.72, 0.42).lerp(Color(1.0, 0.97, 0.9), p))
	env.ambient_light_energy = lerpf(0.16, 0.55, p)
	env.ambient_light_color = Color(0.35, 0.48, 0.62).lerp(Color(0.6, 0.66, 0.75), p)
	sun.light_energy = lerpf(0.3, 1.05, p)
	sun.light_color = Color(1.0, 0.72, 0.5).lerp(Color(1.0, 0.92, 0.78), p)

## 船体 + 玩家 + 摄影机的相位演出。
func _camera_and_boat() -> void:
	if boat == null:
		return
	var ph := _phase()
	var u := _phase_u()
	# 船位：相位2开始从远海向码头推进，相位3减速靠定
	var start_z := BOAT_START.z
	var target_z := BOAT_DOCK.z
	var travel := 0.0
	if ph >= 2:
		travel = u if ph == 2 else 1.0
	var z := lerpf(start_z, target_z, _ease_in_out(travel))
	var x := lerpf(BOAT_START.x, BOAT_DOCK.x, _ease_in_out(travel))
	var settle := clampf(travel * 2.0, 0.0, 1.0) if ph >= 3 else 0.0
	var heave := 1.0 - 0.7 * settle
	boat.position = Vector3(x, WATER_TOP + sin(_t * 0.9) * 0.06 * heave, z)
	boat.rotation.x = sin(_t * 0.7) * 0.012 * heave
	boat.rotation.z = sin(_t * 0.55) * 0.016 * heave
	boat.rotation.y = -0.06 * settle   # 靠泊时轻微摆正对齐
	# 相机
	var dock_look := Vector3(0.0, -0.4, 11.0)
	var look := boat.global_transform * Vector3(0, 1.2, -8.0)
	var pos := Vector3.ZERO
	match ph:
		0:
			pos = boat.global_transform * Vector3(0, 2.3, 3.4)
		1:
			pos = boat.global_transform * Vector3(0, 4.6, -1.0)
		2:
			# 摄影机贴着船右侧前推，船保持入画在下缘
			var base := boat.global_transform * Vector3(2.6, 4.6, 4.4)
			pos = base.lerp(Vector3(4.5, 3.6, 28.0), minf(_phase_u() * 0.85, 1.0))
			look = dock_look
		_:
			pos = lerp(boat.global_transform * Vector3(3.0, 4.0, 3.6), Vector3(9.0, 2.0, 15.0), u)
			look = dock_look
	pos.y = maxf(pos.y, WATER_TOP + 0.5)
	cam.global_position = pos
	if ph >= 3:
		look = Vector3(boat.global_position.x, -0.2, boat.global_position.z)
		look += Vector3(sin(_t * 0.9) * 0.3, 0, cos(_t * 1.1) * 0.3)
	cam.look_at(look, Vector3.UP)

func _phase() -> int:
	if _t < 4.6:
		return 0
	if _t < 7.4:
		return 1
	if _t < 10.8:
		return 2
	return 3

## 相位u：当前相位内已播比例。
func _phase_u() -> float:
	var ph := _phase()
	var start: float = [0.0, 4.6, 7.4, 10.8][ph]
	var end: float = [4.6, 7.4, 10.8, 15.6][ph]
	return clampf((_t - start) / (end - start), 0.0, 1.0)

func _ease_in_out(v: float) -> float:
	if v <= 0.0:
		return 0.0
	if v >= 1.0:
		return 1.0
	return v * v * (3.0 - 2.0 * v)

# ---------------------------------------------------------------- 台词推进

## 把码头灯位投影到屏幕画暖色光点（不依赖 3D 光照衰减/雾，远望即有港感）。
func _draw_port_glow() -> void:
	if cam == null:
		return
	for p: Vector3 in _port_pts:
		if cam.is_position_behind(p):
			continue
		var sp: Vector2 = cam.unproject_position(p)
		var dist := cam.global_position.distance_to(p)
		var r := clampf(13000.0 / dist, 8.0, 150.0)
		var a := clampf(1900.0 / dist, 0.18, 0.85)
		glow_ui.draw_circle(sp, r, Color(1.0, 0.8, 0.45, a * 0.15))
		glow_ui.draw_circle(sp, r * 0.5, Color(1.0, 0.82, 0.48, a * 0.38))
		glow_ui.draw_circle(sp, r * 0.22, Color(1.0, 0.88, 0.6, a * 0.8))

func _advance_line() -> void:
	_line_index += 1
	if _line_index >= SHIP_LINES.size():
		_finish()
		return
	var b: Dictionary = BEATS[_line_index]
	_hold = float(b.get("hold", 2.5))
	_hold_t = 0.0
	_char_index = 0
	_type_timer = 0.0
	_finished = false
	_set_dialogue_mode(_speaker_of(SHIP_LINES[_line_index]) != "")
	text_label.text = ""
	speaker_label.text = ""
	speaker_label.hide()
	var title := str(b.get("title", ""))
	if title == "":
		title_label.hide()
	else:
		title_label.text = title
		title_label.show()
		title_label.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(title_label, "modulate:a", 1.0, 0.7)
	_update_dawn(_dawn())

func _type_step(delta: float) -> void:
	if _finished:
		return
	_type_timer += delta
	var step := int(_type_timer / CHAR_INTERVAL)
	if step <= 0:
		return
	var body := _body_of(SHIP_LINES[_line_index])
	var sp := _speaker_of(SHIP_LINES[_line_index])
	if sp != "":
		speaker_label.text = sp
		speaker_label.show()
	var target := _char_index + step
	if target >= body.length():
		text_label.text = body
		_finished = true
		hint_label.text = "点击 / 空格 继续 · 稍候自动播放"
		return
	text_label.text = body.substr(0, target)
	_char_index = target

func _on_skip() -> void:
	if _fading:
		return
	if _finished:
		_advance_line()
	else:
		_finished = true
		text_label.text = _body_of(SHIP_LINES[_line_index])
		hint_label.text = "点击 / 空格 继续 · 稍候自动播放"

func _finish() -> void:
	_fading = true
	hint_label.text = ""
	fade_rect.show()
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", 1.0, 1.0)
	await tw.finished
	GameState.change_scene(GameState.Campaign.SCENE)

func _speaker_of(line: String) -> String:
	var idx := line.find("：")
	if idx > 0 and not line.begins_with("「"):
		return line.substr(0, idx)
	return ""

func _body_of(line: String) -> String:
	var idx := line.find("：")
	if idx > 0 and not line.begins_with("「"):
		return line.substr(idx + 1)
	return line

func _unhandled_input(event: InputEvent) -> void:
	if _fading:
		return
	var press := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		press = true
	if press:
		_on_skip()

## 截屏验收：摆到指定台词的自定义时刻，锁死推进。
func capture_pose(i: int) -> void:
	_capture_static = true
	_line_index = i
	_set_dialogue_mode(_speaker_of(SHIP_LINES[i]) != "")
	var b: Dictionary = BEATS[i]
	_t = float(b["cap"])
	_hold_t = 0.0
	_finished = true
	text_label.text = _body_of(SHIP_LINES[i])
	var sp := _speaker_of(SHIP_LINES[i])
	speaker_label.text = sp
	speaker_label.visible = sp != ""
	hint_label.text = ""
	var title := str(b.get("title", ""))
	if title == "":
		title_label.hide()
	else:
		title_label.text = title
		title_label.show()
		title_label.modulate.a = 1.0
	_update_dawn(_dawn())
	_camera_and_boat()
	if glow_ui:
		glow_ui.queue_redraw()

func line_count() -> int:
	return SHIP_LINES.size()
