extends Control
## 开场剧情：乐园契约与本次试炼范围（纯文本）。
## 文本逐句打字机浮现，点击/空格加速，结束后进入登记姓名面板，随后过场进废品终点站。
## 配色沿用色彩语言：蓝=乐园系统，金=高价值/契约。

const HARBOR_SCENE := "res://scenes/world/harbor.tscn"

## 每行格式："说话人：台词"。说话人为空 = 叙述旁白。
const LINES: Array[String] = [
 "「轮回乐园 · 猎杀者试炼」",
 "伤势已修复。签订契约，开启半数据化与天赋噬灵者。",
 "目标世界：海贼王 · 哥亚王国 · Lv.6。",
 "每次猎杀带来成长；宝箱、装备与世界之源决定这次冒险的收获。",
 "本次试炼截止科尔波山巨虎。完成后返回乐园强化与补给。",
]

const NAME_PROMPT := "契约者，报上你的名字"
const CHAR_INTERVAL := 0.045

var _line_index := -1
var _char_index := 0
var _type_timer := 0.0
var _finished := false

var speaker_label: Label
var text_label: Label
var hint_label: Label
var name_panel: Control
var name_edit: LineEdit

func _ready() -> void:
	_build_background()
	_build_dialogue()
	_build_name_panel()
	text_label.text = ""
	_advance_line()

func _build_background() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	grad.gradient.colors = PackedColorArray([Color("05080c"), Color("0a0e14"), Color("121a22")])
	grad.fill_from = Vector2(0.5, 0)
	grad.fill_to = Vector2(0.5, 1)
	bg.texture = grad
	add_child(bg)

func _build_dialogue() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(260, 0)
	box.size = Vector2(1400, 1080)
	box.add_theme_constant_override("separation", 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var top := Control.new()
	top.custom_minimum_size.y = 300
	box.add_child(top)
	speaker_label = _label(box, "", 30, Color("ebd6a2"))
	text_label = _label(box, "", 38, Color("dbe7ee"))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(1400, 320)
	text_label.size_flags_vertical = Control.SIZE_SHRINK_END
	hint_label = _label(box, "", 20, Color("5f7a8a"))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_name_panel() -> void:
	name_panel = Control.new()
	name_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(name_panel)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.03, 0.05, 0.62)
	name_panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_panel.add_child(center)
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.10, 0.96)
	style.border_color = Color(0.45, 0.65, 0.75, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(44)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 640
	column.add_theme_constant_override("separation", 20)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	var title := _label(column, "契约签订", 44, Color("ebd6a2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var prompt := _label(column, NAME_PROMPT, 26, Color("a5dfff"))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit = LineEdit.new()
	name_edit.text = GameState.DEFAULT_PLAYER_NAME
	name_edit.placeholder_text = GameState.DEFAULT_PLAYER_NAME
	name_edit.custom_minimum_size = Vector2(520, 62)
	name_edit.add_theme_font_size_override("font_size", 30)
	name_edit.add_theme_stylebox_override("normal", _edit_style(Color(0.10, 0.17, 0.22)))
	name_edit.add_theme_stylebox_override("focus", _edit_style(Color("0f2232")))
	name_edit.add_theme_color_override("font_color", Color("dbe7ee"))
	name_edit.add_theme_color_override("caret_color", Color("ebd6a2"))
	name_edit.max_length = 12
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.text_submitted.connect(_on_name_submitted)
	column.add_child(name_edit)
	var confirm := Button.new()
	confirm.text = "签订契约 · 前往废品终点站"
	confirm.custom_minimum_size = Vector2(520, 66)
	confirm.add_theme_font_size_override("font_size", 26)
	confirm.add_theme_color_override("font_color", Color("dbe7ee"))
	confirm.add_theme_color_override("font_hover_color", Color("ebd6a2"))
	confirm.pressed.connect(_on_name_submitted)
	column.add_child(confirm)
	var tip := _label(column, "回车或点击按钮确认 · 将写入本机存档", 18, Color("5f7a8a"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_panel.hide()

func _edit_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.35, 0.55, 0.68, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style

func _process(delta: float) -> void:
	if not name_panel.visible:
		_type_step(delta)

## 打字机推进：逐字浮出当前行，播完显示“点击继续”。
func _type_step(delta: float) -> void:
	if _finished:
		return
	_type_timer += delta
	var step := int(_type_timer / CHAR_INTERVAL)
	if step <= 0:
		return
	var current := LINES[_line_index]
	var speaker := _speaker_of(current)
	var body := _body_of(current)
	if speaker != "":
		speaker_label.text = speaker
		speaker_label.show()
	else:
		speaker_label.text = ""
		speaker_label.hide()
	var target := _char_index + step
	if target >= body.length():
		text_label.text = body
		_finished = true
		hint_label.text = "点击 / 空格 继续"
		return
	text_label.text = body.substr(0, target)
	_char_index = target

func _advance_line() -> void:
	_line_index += 1
	if _line_index >= LINES.size():
		_show_name_panel()
		return
	_char_index = 0
	_type_timer = 0.0
	_finished = false
	hint_label.text = ""
	text_label.text = ""

func _show_name_panel() -> void:
	name_panel.show()
	name_edit.grab_focus()
	name_edit.select_all()

func _on_name_submitted(_ignored: String = "") -> void:
	GameState.complete_contract(name_edit.text)
	hint_label.text = ""
	GameState.change_scene(GameState.Campaign.SCENE)

func _unhandled_input(event: InputEvent) -> void:
	if name_panel.visible:
		return
	var press := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		press = true
	if not press:
		return
	if _finished:
		_advance_line()
	else:
		_skip_line()

## 跳过打字：把当前行一次放完，再按一次才进下一行。
func _skip_line() -> void:
	_finished = true
	var body := _body_of(LINES[_line_index])
	text_label.text = body
	hint_label.text = "点击 / 空格 继续"

func _speaker_of(line: String) -> String:
	if line.begins_with("："):
		return "？？？"
	return ""

func _body_of(line: String) -> String:
	return line.trim_prefix("：")

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
