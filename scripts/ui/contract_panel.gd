class_name ContractPanel
extends CanvasLayer

signal accepted

const SystemUI := preload("res://scripts/ui/system_ui.gd")
const BLOOD_SHADER := preload("res://shaders/contract_blood.gdshader")
const PAPER_TEXTURE := preload("res://assets/ui/contract_parchment.png")
const HAND_TEXTURE := preload("res://assets/cutscenes/contract_hand_pixel.png")
const HAND_SIZE := Vector2(320.0, 308.0)
const HAND_CONTACT := Vector2(0.45, 0.87)

const PAPER := Color("2b2116")
const PAPER_INNER := Color("3d2f1d")
const PAPER_EDGE := Color("c9a35c")
const PAPER_LIGHT := Color("ffd98a")
const BLOOD := Color(0.72, 0.12, 0.10, 0.85)

var _root: Control
var _dim: ColorRect
var _card: PanelContainer
var _yes_button: Button
var _no_button: Button
var _warning: Label
var _hint: Label
var _death_countdown: Label
var _name_edit: LineEdit
var _blood_overlay: ColorRect
var _blood_material: ShaderMaterial
var _hand_layer: Control
var _hand_sprite: TextureRect
var _selected_yes := true
var _locked := false
var _warning_tween: Tween
var _shake_tween: Tween

func _ready() -> void:
	layer = 50
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.005, 0.008, 0.012, 0.68)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var paper_backdrop := TextureRect.new()
	paper_backdrop.texture = PAPER_TEXTURE
	paper_backdrop.custom_minimum_size = Vector2(760, 560)
	paper_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	paper_backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	paper_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(paper_backdrop)
	_card = PanelContainer.new()
	_card.custom_minimum_size = Vector2(760, 560)
	_card.pivot_offset = Vector2(380, 280)
	_card.add_theme_stylebox_override("panel", SystemUI.flat(Color(PAPER, 0.16), PAPER_EDGE, 2, 8, 26))
	center.add_child(_card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	_card.add_child(page)
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 12)
	page.add_child(title_row)
	_label(title_row, "◆", 23, PAPER_LIGHT)
	_label(title_row, "轮回乐园 · 契约", 34, PAPER_LIGHT)
	_label(title_row, "◆", 23, PAPER_LIGHT)
	var rune_row := HBoxContainer.new()
	rune_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rune_row.add_theme_constant_override("separation", 10)
	page.add_child(rune_row)
	_label(rune_row, "◇   ◆   ▚", 18, Color("b58b43"))
	_death_countdown = _label(rune_row, "距离死亡  --:--:--", 16, Color("ff5b52"))
	_death_countdown.custom_minimum_size.x = 230
	_death_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(rune_row, "◈   ▞   ◆   ◇", 18, Color("b58b43"))
	var section_title := _label(page, "【条款 · 节选】", 20, PAPER_LIGHT)
	section_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var terms_frame := PanelContainer.new()
	terms_frame.custom_minimum_size.y = 190
	terms_frame.add_theme_stylebox_override("panel", SystemUI.flat(Color(PAPER_INNER, 0.84), Color(PAPER_EDGE, 0.78), 1, 5, 18))
	page.add_child(terms_frame)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terms_frame.add_child(scroll)
	SystemUI.style_scrollbar(scroll)
	var terms := VBoxContainer.new()
	terms.add_theme_constant_override("separation", 14)
	terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(terms)
	_label(terms, "· 契约者将进入衍生位面，完成乐园发布的任务。", 19, SystemUI.TEXT)
	_label(terms, "· 任务结束后，乐园将依据「世界之源」结算奖励。", 19, SystemUI.TEXT)
	_label(terms, "· 契约成立后，猎杀者天赋【噬灵者】将强制觉醒。", 19, SystemUI.TEXT)
	_label(terms, "· 乐园条例：一切都将等价交换。", 19, SystemUI.TEXT)
	var signature_area := PanelContainer.new()
	signature_area.custom_minimum_size.y = 82
	signature_area.add_theme_stylebox_override("panel", SystemUI.flat(Color(PAPER_INNER, 0.34), Color(PAPER_EDGE, 0.48), 1, 4, 12))
	page.add_child(signature_area)
	var signature_content := VBoxContainer.new()
	signature_content.add_theme_constant_override("separation", 3)
	signature_area.add_child(signature_content)
	var signature_hint := _label(signature_content, "契约者姓名", 14, Color(0.84, 0.72, 0.52, 0.78))
	signature_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "请输入姓名"
	_name_edit.custom_minimum_size.y = 38
	_name_edit.max_length = 12
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_edit.add_theme_stylebox_override("normal", SystemUI.flat(Color(PAPER_INNER, 0.42), Color(PAPER_EDGE, 0.45), 1, 4, 8))
	_name_edit.add_theme_stylebox_override("focus", SystemUI.flat(Color(PAPER_INNER, 0.72), PAPER_LIGHT, 1, 4, 8))
	_name_edit.add_theme_color_override("font_color", PAPER_LIGHT)
	_name_edit.add_theme_color_override("font_placeholder_color", Color(PAPER_LIGHT, 0.45))
	_name_edit.add_theme_color_override("caret_color", PAPER_LIGHT)
	_name_edit.text_changed.connect(_on_name_changed)
	_name_edit.text_submitted.connect(_focus_sign_button)
	signature_content.add_child(_name_edit)
	var choices := HBoxContainer.new()
	choices.alignment = BoxContainer.ALIGNMENT_CENTER
	choices.add_theme_constant_override("separation", 24)
	page.add_child(choices)
	_no_button = _choice_button("◀  暂不签约", _decline)
	choices.add_child(_no_button)
	_yes_button = _choice_button("按手印签约  ▶", _accept)
	choices.add_child(_yes_button)
	_warning = _label(page, "", 18, Color("ff5b52"))
	_warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning.custom_minimum_size.y = 26
	_warning.hide()
	_hint = _label(page, "先填写姓名，再按手印签约", 16, SystemUI.TEXT_DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blood_overlay = ColorRect.new()
	_blood_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blood_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blood_overlay.color = Color.WHITE
	_blood_overlay.z_index = 8
	_blood_material = ShaderMaterial.new()
	_blood_material.shader = BLOOD_SHADER
	_blood_material.set_shader_parameter("blood_color", BLOOD)
	_blood_overlay.material = _blood_material
	_blood_overlay.hide()
	_card.add_child(_blood_overlay)
	_hand_layer = Control.new()
	_hand_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_layer.z_index = 9
	_hand_layer.hide()
	_hand_sprite = TextureRect.new()
	_hand_sprite.texture = HAND_TEXTURE
	_hand_sprite.size = HAND_SIZE
	_hand_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hand_sprite.stretch_mode = TextureRect.STRETCH_SCALE
	_hand_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hand_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_layer.add_child(_hand_sprite)
	_card.add_child(_hand_layer)
	SystemUI.decor(_card, PAPER_EDGE)
	_apply_choice_style()

func open() -> void:
	_locked = false
	_selected_yes = true
	_hint.text = "先填写姓名，再按手印签约"
	_name_edit.text = ""
	_name_edit.editable = true
	_yes_button.disabled = false
	_no_button.disabled = false
	_card.modulate.a = 0.0
	_card.scale = Vector2(0.88, 0.88)
	_card.rotation = 0.0
	_dim.color.a = 0.0
	_warning.hide()
	_blood_material.set_shader_parameter("progress", 0.0)
	_blood_overlay.hide()
	_hand_layer.hide()
	_apply_choice_style()
	visible = true
	_name_edit.grab_focus()
	var pop := create_tween().set_parallel(true)
	pop.tween_property(_card, "modulate:a", 1.0, 0.38)
	pop.tween_property(_card, "scale", Vector2.ONE, 0.58).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(_dim, "color:a", 0.68, 0.36)

func close() -> void:
	visible = false

func get_signer_name() -> String:
	return _name_edit.text.strip_edges()

func set_death_countdown(seconds: int) -> void:
	var remaining := maxi(0, seconds)
	var hours := int(remaining / 3600)
	var minutes := int((remaining % 3600) / 60)
	var rest_seconds := remaining % 60
	_death_countdown.text = "距离死亡  %d:%02d:%02d" % [hours, minutes, rest_seconds]

func _accept() -> void:
	if _locked:
		return
	_selected_yes = true
	_apply_choice_style()
	if get_signer_name().is_empty():
		_warning.text = "请先输入契约者姓名。"
		_warning.show()
		return
	_locked = true
	_stop_warning()
	_warning.hide()
	_hint.text = "契约已确认 · 血印即将显现"
	_name_edit.text = get_signer_name()
	_name_edit.editable = false
	_yes_button.disabled = true
	_no_button.disabled = true
	accepted.emit()

func _decline() -> void:
	if _locked:
		return
	_selected_yes = false
	_apply_choice_style()
	_warning.text = "警告：契约未成立。灵魂消散倒计时仍在继续。"
	_warning.show()
	_stop_warning()
	_warning.modulate.a = 1.0
	_warning_tween = create_tween().set_loops()
	_warning_tween.tween_property(_warning, "modulate:a", 0.35, 0.36)
	_warning_tween.tween_property(_warning, "modulate:a", 1.0, 0.36)
	if _shake_tween != null and _shake_tween.is_running():
		_shake_tween.kill()
	_card.rotation = 0.0
	_shake_tween = create_tween()
	for angle in [0.018, -0.018, 0.012, -0.012, 0.0]:
		_shake_tween.tween_property(_card, "rotation", angle, 0.045)

func _focus_sign_button(_submitted: String = "") -> void:
	_yes_button.call_deferred("grab_focus")

func _on_name_changed(_text: String) -> void:
	if _warning.text == "请先输入契约者姓名。":
		_warning.hide()

func _set_selection(yes_selected: bool) -> void:
	_selected_yes = yes_selected
	if yes_selected and not _locked:
		_warning.hide()
		_stop_warning()
	_apply_choice_style()
	(_yes_button if yes_selected else _no_button).grab_focus()

func _apply_choice_style() -> void:
	_style_choice(_no_button, not _selected_yes)
	_style_choice(_yes_button, _selected_yes)

func _style_choice(button: Button, selected: bool) -> void:
	var fill := Color(PAPER_LIGHT, 0.18) if selected else Color(PAPER_INNER, 0.92)
	var edge := PAPER_LIGHT if selected else Color(PAPER_EDGE, 0.76)
	button.add_theme_stylebox_override("normal", SystemUI.flat(fill, edge, 2, 5, 18))
	button.add_theme_stylebox_override("hover", SystemUI.flat(Color(PAPER_LIGHT, 0.28), PAPER_LIGHT, 2, 5, 18))
	button.add_theme_stylebox_override("pressed", SystemUI.flat(Color(PAPER_EDGE, 0.55), PAPER_LIGHT, 2, 5, 18))
	button.add_theme_stylebox_override("focus", SystemUI.flat(fill, SystemUI.CRYSTAL, 2, 5, 18))
	button.add_theme_stylebox_override("disabled", SystemUI.flat(fill, edge, 2, 5, 18))
	button.add_theme_color_override("font_color", PAPER_LIGHT if selected else SystemUI.TEXT)
	button.add_theme_color_override("font_hover_color", PAPER_LIGHT)
	button.add_theme_color_override("font_focus_color", Color("e7fbff"))
	button.add_theme_color_override("font_disabled_color", SystemUI.TEXT_DIM)

func _choice_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(230, 58)
	button.add_theme_font_size_override("font_size", 23)
	SystemUI.style_button(button)
	button.pressed.connect(callback)
	return button

func play_blood_animation(duration: float = 5.5) -> void:
	_locked = true
	_yes_button.disabled = true
	_no_button.disabled = true
	_warning.hide()
	_hand_layer.show()
	_blood_overlay.show()
	_blood_material.set_shader_parameter("progress", 0.0)
	await get_tree().process_frame
	var start := Vector2(_hand_layer.size.x - HAND_SIZE.x * 0.35, -HAND_SIZE.y * 0.68)
	var print_center_global := _name_edit.get_global_transform_with_canvas() * (_name_edit.size * 0.5)
	var contact: Vector2 = _hand_layer.get_global_transform_with_canvas().affine_inverse() * print_center_global
	var target: Vector2 = contact - Vector2(HAND_SIZE.x * HAND_CONTACT.x, HAND_SIZE.y * HAND_CONTACT.y)
	var print_center: Vector2 = _blood_overlay.get_global_transform_with_canvas().affine_inverse() * print_center_global
	_blood_material.set_shader_parameter("origin", Vector2(print_center.x / _blood_overlay.size.x, print_center.y / _blood_overlay.size.y))
	var hand_time := minf(1.35, duration * 0.28)
	var hand_tween := create_tween()
	hand_tween.tween_method(_set_hand_position, start, target, hand_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await hand_tween.finished
	await get_tree().create_timer(0.15).timeout
	var stain_time := maxf(0.1, duration - hand_time - 0.4)
	var stain_tween := create_tween()
	stain_tween.tween_method(_set_blood_progress, 0.0, 1.0, stain_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await stain_tween.finished
	await get_tree().create_timer(0.25).timeout
	_hand_layer.hide()

func fade_out_and_close(duration: float = 0.5) -> void:
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_card, "modulate:a", 0.0, duration)
	tween.tween_property(_dim, "color:a", 0.0, duration)
	await tween.finished
	visible = false
	_card.modulate = Color.WHITE
	_card.scale = Vector2.ONE
	_dim.color.a = 0.68

func _set_blood_progress(value: float) -> void:
	_blood_material.set_shader_parameter("progress", value)

func _set_hand_position(value: Vector2) -> void:
	_hand_sprite.position = value

func _stop_warning() -> void:
	if _warning_tween != null and _warning_tween.is_running():
		_warning_tween.kill()
	_warning.modulate.a = 1.0

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _locked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_LEFT or key == KEY_A:
			_set_selection(false)
			get_viewport().set_input_as_handled()
		elif key == KEY_RIGHT or key == KEY_D:
			_set_selection(true)
			get_viewport().set_input_as_handled()
		elif key == KEY_ENTER or key == KEY_KP_ENTER:
			if _name_edit.has_focus():
				_focus_sign_button()
			elif _selected_yes:
				_accept()
			else:
				_decline()
			get_viewport().set_input_as_handled()
		elif key == KEY_SPACE and not _name_edit.has_focus():
			if _selected_yes:
				_accept()
			else:
				_decline()
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		var button := (event as InputEventJoypadButton).button_index
		if button == JOY_BUTTON_DPAD_LEFT:
			_set_selection(false)
			get_viewport().set_input_as_handled()
		elif button == JOY_BUTTON_DPAD_RIGHT:
			_set_selection(true)
			get_viewport().set_input_as_handled()
		elif button == JOY_BUTTON_A:
			if _name_edit.has_focus():
				_yes_button.grab_focus()
			elif _selected_yes:
				_accept()
			else:
				_decline()
			get_viewport().set_input_as_handled()

func _label(parent: Node, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.025, 0.03, 0.9))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label
