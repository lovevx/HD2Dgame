class_name Cinematic
extends Node2D
## 开场过场·第一幕：2.5D 电影镜头。环境底图结合程序化运镜、雨线、冲击与契约粒子。
## 两大场景（夜城路口 → 契约空间），子镜头由 shot_t 驱动运镜与演出（第二幕走 3D opening_boat）。
## 色相遵循工程约定：蓝=乐园系统，金=契约/高价值，红=危险/死亡。

enum SceneId { CITY, CONTRACT }
enum SubId { ESTABLISH, PHONE, TRUCK, IMPACT, DYING }

## 设置项按路径读（见 data/prefs.gd）：本类带 class_name，可能被校验脚本在
## 自动加载注册之前就编译到，直接写 `GameSettings.` 有编译失败的风险。
const Prefs := preload("res://data/prefs.gd")

const W := 1920.0
const H := 1080.0
const CITY_BACKDROP := preload("res://assets/cutscenes/opening_city_night.png")
const CONTRACT_BACKDROP := preload("res://assets/cutscenes/contract_void.png")
const TRUCK_FRONT := preload("res://assets/cutscenes/opening_truck_front.png")

var scene_id := SceneId.CITY
var sub := SubId.ESTABLISH
var shot_t := 0.0       # 当前子镜头已播放时间（驱动关键帧）
var scene_t := 0.0      # 当前场景已播放时间
var paused := false

var _glow: GradientTexture2D
var _phone_shell: StyleBoxFlat
var _phone_screen: StyleBoxFlat
var _phone_notice: StyleBoxFlat

func _ready() -> void:
	_glow = _make_glow()
	_phone_shell = _make_phone_style(Color("090e15"), Color("8392a1"), 34, 3)
	_phone_screen = _make_phone_style(Color("081523"), Color("638096"), 26, 1)
	_phone_notice = _make_phone_style(Color("132537"), Color("b58b43"), 14, 1)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_process(true)

func _make_phone_style(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(0)
	return style

func _process(delta: float) -> void:
	if paused:
		return
	scene_t += delta
	shot_t += delta
	queue_redraw()

## 切换子镜头（重置计时并重绘）。
func shot(sid: int, subid: int) -> void:
	scene_id = sid
	sub = subid
	scene_t = 0.0
	shot_t = 0.0
	queue_redraw()

## 截屏验收：摆到指定帧时刻。
func set_sim_time(tt: float) -> void:
	shot_t = tt
	scene_t += tt
	queue_redraw()

func _make_glow() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.28), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.width = 128
	tex.height = 128
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex

# ---------------------------------------------------------------- 主入口

func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	match scene_id:
		SceneId.CITY:
			_draw_city()
		SceneId.CONTRACT:
			_draw_contract()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ---------------------------------------------------------------- 基础工具

static func _h(x: float, y: float) -> float:
	var s := sin(x * 12.9898 + y * 78.233) * 43758.5453
	return s - floor(s)

func _glow_at(pos: Vector2, r: float, color: Color) -> void:
	draw_texture_rect(_glow, Rect2(pos.x - r, pos.y - r, r * 2.0, r * 2.0), false, color)

func _vgrad(rect: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.end,
		Vector2(rect.position.x, rect.end.y)])
	draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))

# ---------------------------------------------------------------- 夜城路口

func _draw_city() -> void:
	var tt := shot_t
	var zoom := 1.0
	var shake := Vector2.ZERO
	match sub:
		SubId.PHONE:
			zoom = 1.14
		SubId.TRUCK:
			shake = Vector2(sin(tt * 58.0), cos(tt * 46.0)) * 10.0 * clampf(tt / 1.8, 0.0, 1.0)
		SubId.IMPACT:
			zoom = 1.05
			shake = Vector2(sin(tt * 70.0), cos(tt * 53.0)) * 36.0 * exp(-tt * 2.4)
		SubId.DYING:
			shake = Vector2(sin(tt * 11.0), cos(tt * 9.0)) * 3.0 * exp(-tt * 0.6)
	# 运镜震动可在设置页关掉（晕动症友好）。只掐震动，推近与缩放照旧。
	if not bool(Prefs.value("cinematic_shake", true)):
		shake = Vector2.ZERO
	var zoom_origin := Vector2((W - W * zoom) * 0.5, (H - H * zoom) * 0.5)
	draw_set_transform(shake + zoom_origin, 0.0, Vector2(zoom, zoom))
	draw_texture_rect(CITY_BACKDROP, Rect2(0.0, 0.0, W, H), false)
	_draw_city_rain()

	match sub:
		SubId.PHONE: _phone(tt)
		SubId.TRUCK: _truck(tt)
		SubId.IMPACT: _impact_fx(tt)
		SubId.DYING: _dying_fx(tt)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_city_rain() -> void:
	var density := 72
	for i in range(density):
		var seed := float(i)
		var x := fposmod(seed * 271.3 + shot_t * (90.0 + _h(seed, 2.0) * 48.0), W)
		var y := fposmod(seed * 173.7 + shot_t * (170.0 + _h(seed, 4.0) * 95.0), H)
		var length := 10.0 + _h(seed, 7.0) * 22.0
		var alpha := 0.06 + _h(seed, 9.0) * 0.08
		draw_line(Vector2(x, y), Vector2(x - 4.0, y + length), Color(0.58, 0.72, 0.88, alpha), 1.1)

func _phone(tt: float) -> void:
	var pulse := 0.5 + 0.5 * sin(tt * 2.4)
	_glow_at(Vector2(960.0, 785.0), 470.0, Color(0.48, 0.68, 0.95, 0.10 + 0.04 * pulse))
	var bob := sin(tt * 1.3) * 3.0
	draw_set_transform(Vector2(960.0, 890.0 + bob), -0.035, Vector2.ONE)
	draw_style_box(_phone_shell, Rect2(-188.0, -342.0, 376.0, 684.0))
	var screen := Rect2(-165.0, -320.0, 330.0, 638.0)
	draw_style_box(_phone_screen, screen)
	_vgrad(Rect2(-160.0, -315.0, 320.0, 628.0), Color("122438"), Color("07121d"))
	# Speaker notch, front camera and reflected glass edge.
	var notch := Color("03070c")
	draw_rect(Rect2(-42.0, -304.0, 84.0, 13.0), notch)
	draw_circle(Vector2(-42.0, -297.5), 6.5, notch)
	draw_circle(Vector2(42.0, -297.5), 6.5, notch)
	draw_circle(Vector2(68.0, -297.0), 4.0, Color("253d53"))
	draw_line(Vector2(-145.0, -268.0), Vector2(145.0, -268.0), Color(0.6, 0.78, 0.92, 0.16), 1.0)
	# Message header and interview notice.
	draw_circle(Vector2(-124.0, -226.0), 19.0, Color("314e67"))
	draw_circle(Vector2(-124.0, -234.0), 6.0, Color("d4e5ef", 0.72))
	draw_rect(Rect2(-137.0, -224.0, 26.0, 15.0), Color("b9cbd8", 0.6))
	draw_rect(Rect2(-91.0, -238.0, 132.0, 8.0), Color("d9e8f1", 0.76))
	draw_rect(Rect2(-91.0, -222.0, 94.0, 5.0), Color("91a8ba", 0.48))
	for i in range(3):
		var line_y := -182.0 + i * 19.0
		var line_w := 214.0 - _h(float(i), 2.0) * 68.0
		draw_rect(Rect2(-137.0, line_y, line_w, 5.0), Color("b4c5d1", 0.22))
	# 面试提醒卡片：金色通知条是这一镜的视觉焦点。
	draw_style_box(_phone_notice, Rect2(-143.0, -104.0, 286.0, 194.0))
	draw_rect(Rect2(-143.0, -104.0, 5.0, 194.0), Color("f4c365", 0.92))
	draw_circle(Vector2(-110.0, -71.0), 15.0, Color("e6b656", 0.9))
	draw_rect(Rect2(-116.0, -77.0, 12.0, 12.0), Color("312516"))
	draw_rect(Rect2(-82.0, -79.0, 154.0, 8.0), Color("f4dfb0", 0.9))
	draw_rect(Rect2(-82.0, -62.0, 106.0, 5.0), Color("b3a486", 0.66))
	var notify := 0.52 + 0.48 * pulse
	draw_rect(Rect2(-122.0, -28.0, 238.0, 30.0), Color(0.84, 0.47, 0.12, 0.14 + 0.12 * notify))
	draw_rect(Rect2(-108.0, -19.0, 160.0, 7.0), Color("ffdc94", 0.88))
	draw_rect(Rect2(-108.0, -3.0, 196.0, 5.0), Color("dbc69b", 0.62))
	draw_rect(Rect2(-108.0, 13.0, 174.0, 5.0), Color("dbc69b", 0.48))
	# Lower message rows and the phone's home indicator.
	for i in range(4):
		var row_y := 112.0 + i * 28.0
		draw_circle(Vector2(-126.0, row_y + 4.0), 5.0, Color("68a8ce", 0.56 - i * 0.08))
		draw_rect(Rect2(-112.0, row_y, 215.0 - _h(float(i + 3), 1.0) * 64.0, 5.0), Color("aebfcb", 0.28 - i * 0.035))
	draw_rect(Rect2(-43.0, 285.0, 86.0, 5.0), Color("d6e1e8", 0.62))
	# A narrow glass reflection makes the screen feel like a held object.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-154.0, -256.0), Vector2(-72.0, -256.0),
		Vector2(95.0, 300.0), Vector2(35.0, 300.0),
	]), Color(0.75, 0.88, 1.0, 0.035 + 0.025 * pulse))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _truck(tt: float) -> void:
	var u := clampf(tt / 2.6, 0.0, 1.0)
	if u < 0.02:
		return
	var approach := u * u * (3.0 - 2.0 * u)
	var truck_h := lerpf(330.0, 1580.0, approach)
	var truck_w := truck_h * 0.973
	var top := lerpf(270.0, -185.0, approach)
	var truck_rect := Rect2((W - truck_w) * 0.5, top, truck_w, truck_h)
	# 近景卡车以真实体积压向镜头，远近尺寸由同一透视动画连续驱动。
	draw_texture_rect(TRUCK_FRONT, truck_rect, false)
	var left_headlight := Vector2(W * 0.5 - truck_w * 0.285, top + truck_h * 0.63)
	var right_headlight := Vector2(W * 0.5 + truck_w * 0.285, top + truck_h * 0.63)
	var bright := 0.22 + 0.78 * approach
	var glow_radius := lerpf(52.0, 330.0, approach)
	_glow_at(left_headlight, glow_radius, Color(0.76, 0.88, 1.0, 0.16 * bright))
	_glow_at(right_headlight, glow_radius, Color(0.76, 0.88, 1.0, 0.16 * bright))
	# 头灯光池沿湿路面快速推近。
	draw_colored_polygon(PackedVector2Array([
		Vector2(W * 0.5 + truck_w * 0.12, top + truck_h * 0.62),
		Vector2(W * 0.5 - truck_w * 0.12, top + truck_h * 0.62),
		Vector2(W * 0.5 - truck_w * 0.58, H),
		Vector2(W * 0.5 + truck_w * 0.58, H),
	]), Color(0.88, 0.94, 1.0, 0.035 + 0.11 * approach))
	# 眩光拉长，撞击前压满画面。
	if u > 0.3:
		var sr := 220.0 + 680.0 * (u - 0.3)
		var glint := Color(0.97, 0.99, 1.0, 0.32 * bright)
		for lx: Vector2 in [left_headlight, right_headlight]:
			draw_line(lx - Vector2(sr, 0), lx + Vector2(sr, 0), glint, 3.0)
			draw_line(lx - Vector2(0, sr * 0.6), lx + Vector2(0, sr * 0.6), glint, 3.0)

func _impact_fx(tt: float) -> void:
	if tt < 1.1:
		var a := 1.0 - tt
		draw_arc(Vector2(960.0, 470.0), 60.0 + tt * 2700.0, 0.0, TAU, 80, Color(1, 1, 1, a * 0.85), 8.0 + 24.0 * a, true)
		for i in range(12):
			var ang := TAU * i / 12.0 + tt * 0.18
			var r1 := 60.0 + tt * (700.0 + 600.0 * _h(float(i), 7.0))
			var r2 := r1 + 300.0 * a
			draw_line(
				Vector2(960.0, 470.0) + Vector2.from_angle(ang) * r1,
				Vector2(960.0, 470.0) + Vector2.from_angle(ang) * r2,
				Color(1, 1, 1, a * 0.5), 7.0)
	# 底部溅影（血液）
	_vgrad(Rect2(0, 760.0, W, H - 760.0), Color(0.28, 0.02, 0.03, 0), Color(0.22, 0.015, 0.02, 0.5))

func _dying_fx(tt: float) -> void:
	var fade := clampf(tt / 1.2, 0.0, 1.0)
	draw_rect(Rect2(-40.0, -40.0, W + 80.0, H + 80.0), Color(0.006, 0.001, 0.003, 0.42 + 0.4 * fade))
	_vgrad(Rect2(0, 640.0, W, H - 640.0), Color(0.1, 0.01, 0.015, 0), Color(0.11, 0.01, 0.016, 0.55 * fade))

# ---------------------------------------------------------------- 契约空间

func _draw_contract() -> void:
	draw_texture_rect(CONTRACT_BACKDROP, Rect2(0.0, 0.0, W, H), false)
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.015, 0.026, 0.055, 0.12))
	# 数据网格
	for x in range(-1, 25):
		draw_line(Vector2(x * 84.0, 0), Vector2(x * 84.0, H), Color(0.35, 0.6, 0.85, 0.025), 1)
	# 中心契约圆环（金色 = 高价值）
	var c := Vector2(960.0, 455.0)
	var R := 300.0 + 7.0 * sin(scene_t * 1.6)
	_glow_at(c, R * 1.75, Color(0.9, 0.75, 0.35, 0.15))
	var da: float = TAU / 46.0
	for i in range(46):
		var a0 := i * da + scene_t * 0.12
		var alp := 0.35 + 0.5 * (0.5 + 0.5 * sin(a0 * 4.0 + scene_t * 2.0))
		draw_arc(c, R, a0, a0 + da * 0.55, 3, Color(0.93, 0.8, 0.45, alp), 5.0, true)
	# 外圈（反向虚点，蓝 = 乐园系统）
	var R2 := R + 56.0
	var d2: float = TAU / 90.0
	for i in range(90):
		var a0 := i * d2 - scene_t * 0.2
		draw_arc(c, R2, a0, a0 + d2 * 0.38, 3, Color(0.5, 0.82, 1.0, 0.22), 2.0, true)
	# 轨道粒子
	for i in range(3):
		var ang := scene_t * (0.7 + 0.16 * i) + TAU * i / 3.0
		var pr := R2 + 26.0 * sin(scene_t * 0.5 + i * 2.0)
		_glow_at(c + Vector2.from_angle(ang) * pr, 11.0, Color(0.6, 0.92, 1.0, 0.75))
	# 上升数据流
	for i in range(10):
		var y := fposmod(930.0 - scene_t * 42.0 - i * 130.0, 930.0)
		var x := 560.0 + _h(float(i), 3.0) * 800.0
		var tw := 0.3 + 0.7 * absf(sin(scene_t * 2.0 + i * 2.7))
		draw_rect(Rect2(x, y, 2.0, 9.0), Color(0.6, 0.9, 1.0, 0.24 * tw))
		draw_rect(Rect2(x + 18.0, fposmod(y + 50.0, 930.0), 2.0, 6.0), Color(0.95, 0.8, 0.4, 0.2 * tw))

