extends Control
## HD-2D 角色对白框：纸色底板、姓名签、下指箭头。

const PANEL_WIDTH_RATIO := 0.78
const PANEL_TOP_RATIO := 0.22
const PANEL_HEIGHT := 385.0
const TAIL_HEIGHT := 46.0
var panel_top_ratio := PANEL_TOP_RATIO

var speaker_label: Label
var text_label: Label
var hint_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	speaker_label = _make_label(28, Color("514632"))
	speaker_label.add_theme_constant_override("outline_size", 0)
	add_child(speaker_label)
	text_label = _make_label(32, Color("352f25"))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text_label.add_theme_constant_override("line_spacing", 6)
	add_child(text_label)
	hint_label = _make_label(18, Color("756a56"))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(hint_label)
	_layout_labels()
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_instance_valid(speaker_label):
		_layout_labels()
		queue_redraw()

func set_dialogue(speaker: String, body: String, hint: String) -> void:
	speaker_label.text = speaker
	speaker_label.visible = not speaker.is_empty()
	text_label.text = body
	hint_label.text = hint
	queue_redraw()

func set_panel_top_ratio(ratio: float) -> void:
	panel_top_ratio = clampf(ratio, 0.0, 0.8)
	_layout_labels()
	queue_redraw()

func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _layout_labels() -> void:
	var rect := _panel_rect()
	speaker_label.position = rect.position + Vector2(74, 4)
	speaker_label.size = Vector2(330, 42)
	text_label.position = rect.position + Vector2(66, 78)
	text_label.size = Vector2(rect.size.x - 132, rect.size.y - 194)
	hint_label.position = rect.position + Vector2(rect.size.x - 430, rect.size.y - 96)
	hint_label.size = Vector2(340, 30)

func _panel_rect() -> Rect2:
	var panel_width := size.x * PANEL_WIDTH_RATIO
	var panel_height := minf(PANEL_HEIGHT, size.y * 0.44)
	return Rect2((size.x - panel_width) * 0.5, size.y * panel_top_ratio, panel_width, panel_height)

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var rect := _panel_rect()
	var outer := _shape(rect, 0.0)
	draw_colored_polygon(_offset_points(outer, Vector2(0, 8)), Color(0.02, 0.02, 0.015, 0.52))
	draw_colored_polygon(outer, Color("302b22"))
	draw_polyline(_closed_points(outer), Color("201d18"), 3.0, false)
	var rim := _shape(rect, 5.0)
	draw_colored_polygon(rim, Color("a5967c"))
	var paper := _shape(rect, 10.0)
	draw_colored_polygon(paper, Color("d8d0c1"))
	draw_polyline(_closed_points(paper), Color("86785f"), 2.0, false)
	# 柔和的纸面高光与底边暗线，保留参考图的厚纸片层次。
	draw_line(Vector2(rect.position.x + 40, rect.position.y + 28), Vector2(rect.position.x + rect.size.x - 42, rect.position.y + 28), Color(0.93, 0.9, 0.83, 0.55), 2.0, false)
	draw_line(Vector2(rect.position.x + 30, rect.position.y + rect.size.y - TAIL_HEIGHT - 16), Vector2(rect.position.x + 54, rect.position.y + rect.size.y - TAIL_HEIGHT - 8), Color(0.43, 0.38, 0.29, 0.45), 2.0, false)
	if speaker_label.visible:
		_draw_name_tag(rect)
	_draw_next_arrow(rect)

func _shape(rect: Rect2, inset: float) -> PackedVector2Array:
	var left := rect.position.x + inset
	var right := rect.position.x + rect.size.x - inset
	var top := rect.position.y + 18 + inset
	var bottom := rect.position.y + rect.size.y - TAIL_HEIGHT - inset
	var cut := 27.0
	var tail_x := rect.position.x + rect.size.x * 0.5
	var tail_half := 36.0 - inset * 0.25
	var tail_tip_y := rect.position.y + rect.size.y - inset * 0.4
	return PackedVector2Array([
		Vector2(left + cut, top),
		Vector2(right - cut, top),
		Vector2(right, top + cut),
		Vector2(right, bottom - cut),
		Vector2(right - cut, bottom),
		Vector2(tail_x + tail_half, bottom),
		Vector2(tail_x, tail_tip_y),
		Vector2(tail_x - tail_half, bottom),
		Vector2(left + cut, bottom),
		Vector2(left, bottom - cut),
		Vector2(left, top + cut),
	])

func _draw_name_tag(rect: Rect2) -> void:
	var x := rect.position.x + 42
	var y := rect.position.y + 3
	var points := PackedVector2Array([
		Vector2(x + 13, y), Vector2(x + 147, y), Vector2(x + 168, y + 15),
		Vector2(x + 152, y + 42), Vector2(x + 18, y + 42), Vector2(x, y + 23),
	])
	draw_colored_polygon(points, Color("c6bba6"))
	draw_polyline(_closed_points(points), Color("514735"), 2.0, false)
	draw_line(Vector2(x + 20, y + 37), Vector2(x + 147, y + 37), Color(0.93, 0.89, 0.81, 0.72), 2.0, false)

func _draw_next_arrow(rect: Rect2) -> void:
	var center := Vector2(rect.position.x + rect.size.x - 70, rect.position.y + rect.size.y - 79)
	var diamond := PackedVector2Array([
		center + Vector2(0, -16), center + Vector2(16, 0),
		center + Vector2(0, 16), center + Vector2(-16, 0),
	])
	draw_colored_polygon(diamond, Color("463d2d"))
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-6, -3), center + Vector2(6, -3),
		center + Vector2(0, 5),
	]), Color("e5ddce"))

func _closed_points(points: PackedVector2Array) -> PackedVector2Array:
	var closed := points.duplicate()
	closed.append(points[0])
	return closed

func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var shifted := PackedVector2Array()
	for point in points:
		shifted.append(point + offset)
	return shifted
