class_name Cinematic
extends Node2D
## 开场过场·第一幕：程序化 2D 电影镜头。所有画面由 GDScript 绘制原语现场生成，无外部美术。
## 两大场景（夜城路口 → 契约空间），子镜头由 shot_t 驱动运镜与演出（第二幕走 3D opening_boat）。
## 色相遵循工程约定：蓝=乐园系统，金=契约/高价值，红=危险/死亡。

enum SceneId { CITY, CONTRACT }
enum SubId { ESTABLISH, PHONE, TRUCK, IMPACT, DYING }

const W := 1920.0
const H := 1080.0
const HORIZON_CITY := 560.0

var scene_id := SceneId.CITY
var sub := SubId.ESTABLISH
var shot_t := 0.0       # 当前子镜头已播放时间（驱动关键帧）
var scene_t := 0.0      # 当前场景已播放时间
var paused := false

var _glow: GradientTexture2D

func _ready() -> void:
	_glow = _make_glow()
	set_process(true)

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
	draw_set_transform(shake, 0.0, Vector2(zoom, zoom))

	_sky_city()
	_draw_buildings(HORIZON_CITY, 220.0, Color("18202c"), Color("cfd8e2"), 11.0, 0.16, 90.0, 210.0)
	_draw_buildings(HORIZON_CITY, 300.0, Color("0b0f15"), Color("ffd98a"), 47.0, 0.34, 120.0, 260.0)
	_street_city()
	_city_life()
	_storefronts()

	match sub:
		SubId.PHONE: _phone(tt)
		SubId.TRUCK: _truck(tt)
		SubId.IMPACT: _impact_fx(tt)
		SubId.DYING: _dying_fx(tt)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _sky_city() -> void:
	var top := Color("05080e")
	var mid := Color("131c2b")
	var low := Color("26303f")
	_vgrad(Rect2(0, 0, W, HORIZON_CITY * 0.62), top, mid)
	_vgrad(Rect2(0, HORIZON_CITY * 0.62, W, HORIZON_CITY), mid, low)
	_glow_at(Vector2(W * 0.5, HORIZON_CITY), 760.0, Color(0.45, 0.52, 0.6, 0.16))

func _draw_buildings(base_y: float, max_h: float, color: Color, lit: Color, seed0: float, lit_chance: float, minw: float, maxw: float) -> void:
	var x := -60.0
	var i := 0
	while x < W + 60:
		var w := lerpf(minw, maxw, _h(seed0 + i * 1.7, 1.0))
		var h := lerpf(70.0, max_h, _h(seed0 + i * 1.7, 2.0))
		if x > -30.0 and x < W - 30.0:
			draw_rect(Rect2(x, base_y - h, w, h), color)
			var cols := int(w / 26.0)
			var rows := int(h / 32.0)
			for cx in range(cols):
				for cy in range(rows):
					var seedv := _h(seed0 + i * 7.0 + cx * 0.4, cy * 1.3 + 5.0)
					if seedv > lit_chance:
						continue
					var bright := lerpf(0.45, 1.0, _h(seedv + 11.0, 9.0))
					if float(int(seedv * 90.0)) == 0.0:
						bright = lerpf(bright, 0.2, 0.5 + 0.5 * sin(shot_t * 6.0 + seedv * 45.0))
					draw_rect(Rect2(x + 7 + cx * 26, base_y - h + 9 + cy * 32, 6, 7), Color(lit.r * bright, lit.g * bright, lit.b * bright, 0.85))
			if _h(seed0 + i, 3.0) > 0.62:
				var ax := x + w * 0.4
				draw_line(Vector2(ax, base_y - h), Vector2(ax, base_y - h - 52.0), color, 3)
				draw_line(Vector2(ax, base_y - h - 44.0), Vector2(ax + 16.0, base_y - h - 44.0), color, 2)
		i += 1
		x += w + lerpf(4.0, 18.0, _h(seed0 + i, 4.0))

func _street_city() -> void:
	# 路面（透视梯形）
	draw_colored_polygon(PackedVector2Array([
		Vector2(806, HORIZON_CITY), Vector2(1114, HORIZON_CITY), Vector2(1540, H), Vector2(380, H)]), Color("101417"))
	# 路缘
	draw_line(Vector2(806, HORIZON_CITY), Vector2(380, H), Color(0.42, 0.46, 0.48, 0.5), 5)
	draw_line(Vector2(1114, HORIZON_CITY), Vector2(1540, H), Color(0.42, 0.46, 0.48, 0.5), 5)
	# 车道虚线（透视）
	for lane: float in [-0.5, 0.5]:
		var prev := Vector2.INF
		for k in range(1, 14):
			var u := k / 13.0
			var y := lerpf(HORIZON_CITY, H, pow(u, 2.2))
			var dx := lerpf(95.0, 480.0, u) * lane
			var wd := lerpf(2.5, 11.0, u)
			var p := Vector2(960.0 + dx, y)
			if prev != Vector2.INF and (k % 2) == 0:
				draw_line(prev, p, Color(0.78, 0.8, 0.76, 0.5), wd)
			prev = p
	# 人行横道（路面近端）
	for i in range(9):
		var y0 := 872.0 + i * 12.0
		var hw := lerpf(28.0, 330.0, i / 9.0) * 0.88
		draw_rect(Rect2(960.0 - hw, y0, hw * 2.0, 4.0), Color(0.7, 0.74, 0.7, 0.38))
	# 人行道
	draw_rect(Rect2(0, 690, 380, H - 690), Color("171b20"))
	draw_rect(Rect2(1540, 690, W - 1540, H - 690), Color("171b20"))
	# 路灯
	_lamp(240.0)
	_lamp(948.0)
	_lamp(1720.0)

func _lamp(x: float) -> void:
	var flick := 0.9 + 0.1 * sin(shot_t * 7.0 + x * 0.05)
	draw_line(Vector2(x, 655.0), Vector2(x, 470.0), Color(0.09, 0.1, 0.11), 5)
	draw_line(Vector2(x, 470.0), Vector2(x + 66.0, 470.0), Color(0.09, 0.1, 0.11), 5)
	var head := Vector2(x + 68.0, 466.0)
	_glow_at(head, 250.0 * flick, Color(1.0, 0.86, 0.6, 0.13))
	_glow_at(head, 96.0 * flick, Color(1.0, 0.88, 0.64, 0.4))
	draw_rect(Rect2(x + 56.0, 462.0, 20.0, 10.0), Color(0.96, 0.87, 0.62))
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + 62.0, 472.0), Vector2(x - 150.0, 720.0), Vector2(x + 280.0, 720.0)]), Color(1.0, 0.86, 0.62, 0.028))

func _traffic_light() -> void:
	var x := 1210.0
	draw_line(Vector2(x, 660.0), Vector2(x, 428.0), Color(0.07, 0.08, 0.09), 5)
	draw_rect(Rect2(x - 20.0, 398.0, 40.0, 96.0), Color("0a0c0e"))
	draw_rect(Rect2(x - 20.0, 398.0, 40.0, 96.0), Color(0.5, 0.55, 0.6, 0.35), false)
	var on := int(shot_t / 4.0) % 3
	var red := Vector2(x, 420.0)
	var yel := Vector2(x, 446.0)
	var grn := Vector2(x, 472.0)
	_dot(red, true, on == 0, Color(1.0, 0.28, 0.2))
	_dot(yel, false, on == 1, Color(1.0, 0.75, 0.25))
	_dot(grn, false, on == 2, Color(0.35, 1.0, 0.5))

func _dot(pos: Vector2, red: bool, lit: bool, c: Color) -> void:
	draw_circle(pos, 7.0, Color(0.14, 0.16, 0.18))
	if lit:
		_glow_at(pos, 46.0, Color(c.r, c.g, c.b, 0.5))
		draw_circle(pos, 5.5, c)
	elif red:
		draw_circle(pos, 5.5, Color(c.r * 0.18, c.g * 0.05, c.b * 0.05))

func _city_life() -> void:
	_traffic_light()
	# 斑马线前等红灯的车（尾灯发光 + 微微怠速起伏）
	for i in 3:
		var lx: float = [700.0, 1160.0, 430.0][i]
		var ly := 918.0
		var idle := sin(shot_t * 2.0 + i * 2.1) * 1.2
		draw_rect(Rect2(lx - 17.0, ly - 8.0 + idle, 34.0, 15.0), Color(0.13, 0.11, 0.1))
		_glow_at(Vector2(lx - 12.0, ly - 8.0 + idle), 22.0, Color(1.0, 0.2, 0.15, 0.5))
		_glow_at(Vector2(lx + 12.0, ly - 8.0 + idle), 22.0, Color(1.0, 0.2, 0.15, 0.5))
		draw_circle(Vector2(lx - 12.0, ly - 8.0 + idle), 2.4, Color(0.95, 0.26, 0.2))
		draw_circle(Vector2(lx + 12.0, ly - 8.0 + idle), 2.4, Color(0.95, 0.26, 0.2))
	# 晚高峰行人：近处放大、斑马线两侧成群
	for i in range(16):
		var lane := i % 2
		var basex := 40.0 + i * 165.0 if lane == 0 else 1260.0 + (i % 5) * 130.0
		var y := lerpf(700.0, 1035.0, _h(i, 3.0))
		var near := y > 900.0
		var dir := 1.0 if lane == 0 else -1.0
		var x := wrapf(basex + dir * (26.0 * shot_t + 52.0 * _h(i, 5.0)), -30.0, W + 30.0)
		_person(x, y, dir, 1.35 if near else 1.0)
	# 远车（同向尾灯 + 一束对向车灯）
	for i in range(2):
		var y := 940.0 - fposmod(shot_t * 46.0 + i * 380.0, 420.0)
		var x := 900.0 + i * 120.0 - fposmod(shot_t * 30.0 + i * 130.0, 160.0)
		draw_rect(Rect2(x - 18.0, y - 8.0, 36.0, 16.0), Color(0.13, 0.11, 0.1))
		draw_circle(Vector2(x - 14.0, y - 8.0), 2.0, Color(0.9, 0.16, 0.12, 0.9))
		draw_circle(Vector2(x + 14.0, y - 8.0), 2.0, Color(0.9, 0.16, 0.12, 0.9))
	var ony := HORIZON_CITY + fposmod(shot_t * 170.0, 300.0)
	var onx := 1000.0 - fposmod(shot_t * 130.0, 120.0)
	draw_rect(Rect2(onx - 14.0, ony - 7.0, 28.0, 13.0), Color(0.16, 0.14, 0.13))
	_glow_at(Vector2(onx - 10.0, ony - 4.0), 14.0, Color(0.95, 0.97, 1.0, 0.5))
	_glow_at(Vector2(onx + 10.0, ony - 4.0), 14.0, Color(0.95, 0.97, 1.0, 0.5))

func _person(x: float, y: float, dir: float, k: float = 1.0) -> void:
	var stride := sin(shot_t * 6.0 + x * 0.3) * 3.0 * k
	draw_circle(Vector2(x, y - 26.0 * k), 5.5 * k, Color(0.09, 0.11, 0.13))
	draw_rect(Rect2(x - 5.5 * k, y - 19.0 * k, 11.0 * k, 19.0 * k), Color(0.10, 0.12, 0.14))
	# 手机/物品微光，提升近景辨识
	if k > 1.2:
		_glow_at(Vector2(x + dir * 8.0 * k, y - 14.0 * k), 16.0 * k, Color(0.7, 0.85, 1.0, 0.28))
	draw_line(Vector2(x - dir * 4.0 * k, y - 2.0 * k), Vector2(x - dir * 4.0 * k - stride, y + 8.0 * k), Color(0.09, 0.11, 0.13), 4.0 * k)
	draw_line(Vector2(x + dir * 4.0 * k, y - 2.0 * k), Vector2(x + dir * 4.0 * k + stride, y + 8.0 * k), Color(0.09, 0.11, 0.13), 4.0 * k)

func _storefronts() -> void:
	# 左右沿街店面暖光
	for side: float in [-1.0, 1.0]:
		for i in range(4):
			var x0 := 30.0 + i * 88.0 if side < 0 else 1530.0 + i * 88.0
			var w := 76.0
			var h := 240.0
			var y0 := H - h - 6.0
			draw_rect(Rect2(x0, y0, w, h), Color("181a1d"))
			var warm := 0.5 + 0.5 * _h(side * 7.0 + i, 6.0)
			draw_rect(Rect2(x0 + 8.0, y0 + 14.0, w - 16.0, 90.0), Color(1.0, 0.82, 0.5, 0.12 + 0.2 * warm))
			_glow_at(Vector2(x0 + w * 0.5, y0 + 60.0), 90.0, Color(1.0, 0.78, 0.45, 0.10))
			draw_rect(Rect2(x0, y0 + 118.0, w, 122.0), Color(0.6, 0.4, 0.26, 0.18))

func _phone(tt: float) -> void:
	_glow_at(Vector2(960.0, 920.0), 620.0, Color(0.6, 0.75, 0.95, 0.13))
	var body := Rect2(690.0, 822.0, 540.0, 198.0)
	draw_rect(body, Color("12161b"))
	var scr := Rect2(704.0, 830.0, 512.0, 182.0)
	draw_rect(scr, Color(0.028, 0.09, 0.15, 0.94))
	# 顶部状态行
	draw_rect(Rect2(718.0, 842.0, 40.0, 6.0), Color(0.85, 0.9, 1.0, 0.4))
	draw_rect(Rect2(1160.0, 842.0, 42.0, 6.0), Color(0.85, 0.9, 1.0, 0.4))
	# 消息列表
	for i in range(4):
		draw_rect(Rect2(718.0, 868.0 + i * 30.0, 484.0 - _h(i + 1.0, 2.0) * 200.0, 10.0), Color(0.75, 0.82, 0.9, 0.2))
	# 面试提醒高亮条
	var pulse := 0.5 + 0.5 * sin(tt * 2.4)
	draw_rect(Rect2(718.0, 990.0, 484.0, 24.0), Color(0.95, 0.72, 0.28, 0.10 + 0.10 * pulse))
	draw_rect(Rect2(718.0, 990.0, 10.0, 24.0), Color(0.95, 0.72, 0.28, 0.85))
	draw_rect(Rect2(734.0, 997.0, 200.0, 9.0), Color(0.95, 0.82, 0.5, 0.75))
	# 屏幕呼吸反光
	draw_rect(scr, Color(0.4, 0.6, 0.9, 0.03 + 0.05 * pulse))

func _truck(tt: float) -> void:
	var u := clampf(tt / 2.6, 0.0, 1.0)
	if u < 0.02:
		return
	# 行人被撞视角：头灯从地平线上方被“拔高”到眼位，车头巨影压向镜头
	var hl_y := lerpf(556.0, 462.0, u)
	var spread := lerpf(26.0, 320.0, u)
	var l1 := Vector2(960.0 - spread, hl_y)
	var l2 := Vector2(960.0 + spread, hl_y)
	var bright := 0.25 + 0.9 * u
	# 车道光池铺向镜头
	draw_colored_polygon(PackedVector2Array([
		Vector2(1120.0, HORIZON_CITY), Vector2(800.0, HORIZON_CITY),
		Vector2(560.0, H), Vector2(1360.0, H)]), Color(0.92, 0.96, 1.0, 0.05 + 0.2 * u))
	# 头灯宽泛光暴 + 白核
	var big_r := lerpf(70.0, 780.0, u)
	_glow_at(l1, big_r, Color(0.9, 0.95, 1.0, 0.62 * bright))
	_glow_at(l2, big_r, Color(0.9, 0.95, 1.0, 0.62 * bright))
	_glow_at(Vector2(960.0, hl_y), big_r * 1.3, Color(0.95, 0.97, 1.0, 0.2 * bright))
	_glow_at(l1, lerpf(22.0, 110.0, u), Color(1.0, 1.0, 1.0, 0.95 * bright))
	_glow_at(l2, lerpf(22.0, 110.0, u), Color(1.0, 1.0, 1.0, 0.95 * bright))
	# 镜头眩光十字线
	if u > 0.3:
		var sr := 240.0 + 620.0 * (u - 0.3)
		var glint := Color(0.97, 0.99, 1.0, 0.4 * (0.4 + 0.6 * u))
		for lx: Vector2 in [l1, l2]:
			draw_line(lx - Vector2(sr, 0), lx + Vector2(sr, 0), glint, 3.0)
			draw_line(lx - Vector2(0, sr * 0.6), lx + Vector2(0, sr * 0.6), glint, 3.0)
	# 挡风玻璃/车顶剪影（头灯上方，露出两侧天空）
	var cab_w := spread * 2.0 + 150.0 * u
	draw_colored_polygon(PackedVector2Array([
		Vector2(960.0 - cab_w, hl_y - 6.0), Vector2(960.0 + cab_w, hl_y - 6.0),
		Vector2(960.0 + cab_w * 0.82, hl_y - 210.0 - 90.0 * u), Vector2(960.0 - cab_w * 0.82, hl_y - 210.0 - 90.0 * u)]),
		Color(0.025, 0.032, 0.04))
	# 车头巨影（头灯向下压向镜头）
	draw_colored_polygon(PackedVector2Array([
		Vector2(l1.x - 30.0, hl_y + 8.0), Vector2(l2.x + 30.0, hl_y + 8.0),
		Vector2(1180.0, H), Vector2(740.0, H)]), Color(0.014, 0.018, 0.022))
	# 保险杠 + 中网
	draw_rect(Rect2(l1.x - 36.0, hl_y + 16.0, spread * 2.0 + 72.0, 16.0 + 10.0 * u), Color(0.055, 0.065, 0.075))
	for g in range(7):
		var gx := l1.x + spread * g / 3.0
		draw_line(Vector2(gx, hl_y + 26.0), Vector2(gx, hl_y + 26.0 + 34.0 * u), Color(0.09, 0.11, 0.13), 4.0)
	# 车灯本体
	draw_circle(l1, 13.0 + 9.0 * u, Color(0.98, 0.995, 1.0))
	draw_circle(l2, 13.0 + 9.0 * u, Color(0.98, 0.995, 1.0))

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
	_vgrad(Rect2(0, 0, W, H), Color("02040a"), Color("0a1222"))
	_vgrad(Rect2(0, H * 0.6, W, H * 0.4), Color("0a1222"), Color("04060c"))
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

