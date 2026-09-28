class_name StunGauge
extends Node3D
## 敌人头顶眩晕条（黄条）：0~100 按比例显示，满值常亮加亮。
## 即时眩晕表现，纯程序化网格，不新增美术。
## 纯程序化网格（不新增美术），挂在敌人 / 山之主身上，由它们调 set_ratio()。

const BAR_WIDTH := 1.10
const BAR_HEIGHT := 0.075
const COLOR_LOW := Color("ffd76e")    # 未满：暖黄
const COLOR_FULL := Color("ffefb4")   # 满值：更亮，提示"现在可以处决 / 补刀"

var _max := 100.0
var _width := BAR_WIDTH
var _fill: MeshInstance3D
var _low_mat: StandardMaterial3D
var _full_mat: StandardMaterial3D

## 建立底板与填充条。at_y 是相对敌人原点的头顶高度；bar_width 让人物体型大的
## 目标（科尔波山之主肩高 4.2）也能看清这条黄条。
func setup(max_value: float, at_y := 2.62, bar_width := BAR_WIDTH) -> void:
	_max = maxf(1.0, max_value)
	_width = maxf(0.2, bar_width)
	position.y = at_y
	var back := MeshInstance3D.new()
	back.name = "Back"
	var back_mesh := BoxMesh.new()
	back_mesh.size = Vector3(_width + 0.05, BAR_HEIGHT + 0.03, 0.02)
	back.mesh = back_mesh
	back.material_override = _mat(Color(0, 0, 0, 0.5))
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(back)
	_low_mat = _mat(COLOR_LOW)
	_full_mat = _mat(COLOR_FULL)
	_fill = MeshInstance3D.new()
	_fill.name = "Fill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(_width, BAR_HEIGHT, 0.03)
	_fill.mesh = fill_mesh
	_fill.material_override = _low_mat
	_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fill)
	set_ratio(0.0)

## 0~1 的比例；从左侧生长，0 时隐藏。
func set_ratio(r: float) -> void:
	if _fill == null:
		return
	var ratio := clampf(r, 0.0, 1.0)
	_fill.visible = ratio > 0.01
	_fill.scale = Vector3(maxf(ratio, 0.001), 1.0, 1.0)
	_fill.position.x = -_width * (1.0 - ratio) * 0.5
	_fill.material_override = _full_mat if ratio >= 1.0 else _low_mat

func ratio_of(value: float) -> float:
	return clampf(value / maxf(_max, 0.001), 0.0, 1.0)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = c
	return m
