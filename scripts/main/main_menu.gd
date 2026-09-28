extends Control
## 游戏主菜单：有存档时显示「继续游戏」（恢复阶段试炼检查点），否则「开始新游戏」
## 走「开场剧情 + 登记姓名」（会覆盖旧档）。「关卡调试」保留给白盒阶段开发用。
## 以衬线文字标题叠在雨夜场景上；菜单使用无底板文字选项与方向箭头。

const SystemUI := preload("res://scripts/ui/system_ui.gd")
const SettingsPanelScript := preload("res://scripts/ui/settings_panel.gd")
const BackgroundTexture := preload("res://assets/ui/main_menu_background.png")
const TitleCharacterSheet := preload("res://assets/characters/black_swordsman_video/待机_up_right_12.png")
const OPENING_SCENE := "res://scenes/main/opening.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/main/level_select.tscn"
const HARBOR_SCENE := "res://scenes/world/harbor.tscn"
const VERSION_HINT := "海贼王 · 核心循环原型  /  截止科尔波山猎虎"

var settings_panel: CanvasLayer
var settings_button: Button
var title_group: Control
var backdrop: TextureRect
var bottom_shade: TextureRect
var menu_center: CenterContainer
var menu_column: VBoxContainer
var menu_buttons_container: VBoxContainer
var ambient_layer: Control
var title_character: Sprite2D
var prompt_label: Label
var version_label: Label
var menu_buttons: Array[Button] = []
var menu_item_roots: Array[Control] = []
var menu_button_enabled: Array[bool] = []
var menu_focus_button: Button
var prompt_intro_tween: Tween
var prompt_pulse_tween: Tween
var _splash_active := true
var title_time := 0.0
var _title_frame_timer := 0.0
var _title_character_anchor := Vector2.ZERO
var _menu_view_size := Vector2.ZERO
var _backdrop_layout_size := Vector2.ZERO

func _ready() -> void:
	_build_background()
	menu_focus_button = _build_center()
	_build_settings()
	_play_title_intro()

func _process(delta: float) -> void:
	title_time += delta
	if is_instance_valid(ambient_layer):
		ambient_layer.queue_redraw()
	var view := get_viewport_rect().size
	if is_instance_valid(backdrop):
		if backdrop.size != _backdrop_layout_size and backdrop.size.x > 0.0:
			_backdrop_layout_size = backdrop.size
			backdrop.pivot_offset = backdrop.size * 0.5
			backdrop.scale = Vector2.ONE * 1.04
	if view != _menu_view_size:
		_menu_view_size = view
		var ui_scale := minf(view.x / 1920.0, view.y / 1080.0)
		if is_instance_valid(title_group):
			title_group.offset_top = view.y * 0.06
			title_group.offset_bottom = title_group.offset_top + 370.0
			title_group.pivot_offset = Vector2(820.0, 0.0)
			title_group.scale = Vector2.ONE * ui_scale
		if is_instance_valid(bottom_shade):
			bottom_shade.offset_top = -minf(500.0, view.y * 0.46)
		if is_instance_valid(menu_center):
			var compact := clampf((view.y - 275.0) / (1080.0 - 275.0), 0.0, 1.0)
			var menu_center_ratio := lerpf(0.70, 0.57, compact)
			menu_center.offset_top = view.y * (menu_center_ratio * 2.0 - 1.0) + 64.0
		_layout_menu_items(view)
		if is_instance_valid(prompt_label):
			prompt_label.offset_top = view.y * 0.60
			prompt_label.offset_bottom = prompt_label.offset_top + 38.0
		_title_character_anchor = Vector2(view.x * 0.18, view.y * 0.72)
		if is_instance_valid(title_character):
			title_character.scale = Vector2.ONE * clampf(view.y / 1080.0 * 2.4, 0.6, 2.4)
	if is_instance_valid(title_character):
		_title_frame_timer += delta
		if _title_frame_timer >= 0.46:
			_title_frame_timer = fposmod(_title_frame_timer, 0.46)
			title_character.frame = (title_character.frame + 1) % 12
		title_character.position = _title_character_anchor + Vector2(0.0, sin(title_time * 1.25) * 1.25)

## 设置面板：与游戏内是同一个面板脚本，只是这里挂在主菜单自己身上（主菜单没有 HUD）。
func _build_settings() -> void:
	settings_panel = SettingsPanelScript.new()
	settings_panel.name = "SettingsPanel"
	add_child(settings_panel)
	settings_panel.closed.connect(func(): settings_button.grab_focus())

## 衬线字标悬于雨夜与虚空门户之上；暗色渐变为标题和菜单留出可读区域。
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("101922")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	backdrop = TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = BackgroundTexture
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.offset_left = -36.0
	backdrop.offset_top = -28.0
	backdrop.offset_right = 36.0
	backdrop.offset_bottom = 28.0
	add_child(backdrop)
	var tone := TextureRect.new()
	tone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tone.texture = _background_gradient()
	tone.stretch_mode = TextureRect.STRETCH_SCALE
	tone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tone)
	ambient_layer = Control.new()
	ambient_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ambient_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ambient_layer.draw.connect(_draw_title_ambience)
	add_child(ambient_layer)
	_build_text_title()
	bottom_shade = TextureRect.new()
	bottom_shade.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_shade.offset_top = -500
	bottom_shade.texture = _bottom_gradient()
	bottom_shade.stretch_mode = TextureRect.STRETCH_SCALE
	bottom_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_shade)
	_build_title_character()
	version_label = _label(self, VERSION_HINT, 16, SystemUI.TEXT_DIM)
	version_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version_label.position = Vector2(26, -38)
	version_label.size = Vector2(900, 30)
	version_label.modulate.a = 0

func _build_title_character() -> void:
	title_character = Sprite2D.new()
	title_character.name = "TitleCharacter"
	title_character.texture = TitleCharacterSheet
	title_character.hframes = 6
	title_character.vframes = 2
	title_character.frame = 0
	title_character.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	title_character.z_index = 1
	var view := get_viewport_rect().size
	_title_character_anchor = Vector2(view.x * 0.18, view.y * 0.72)
	title_character.scale = Vector2.ONE * clampf(view.y / 1080.0 * 2.4, 0.6, 2.4)
	title_character.position = _title_character_anchor
	add_child(title_character)

func _layout_menu_items(view: Vector2) -> void:
	var compact_scale := clampf(view.y / 260.0, 0.72, 1.0)
	var row_width := minf(460.0, view.x * 0.90)
	var row_height := 52.0 * compact_scale
	if is_instance_valid(menu_column):
		menu_column.custom_minimum_size.x = minf(520.0, view.x * 0.96)
	if is_instance_valid(menu_buttons_container):
		menu_buttons_container.add_theme_constant_override("separation", roundi(8.0 * compact_scale))
	for index in range(menu_buttons.size()):
		var item := menu_item_roots[index]
		var button := menu_buttons[index]
		item.custom_minimum_size = Vector2(row_width, row_height)
		var font_size := maxi(16, roundi(float(button.get_meta("menu_font_size", 25)) * compact_scale))
		button.add_theme_font_size_override("font_size", font_size)
		var arrow := button.get_meta("menu_arrow") as Label
		if is_instance_valid(arrow):
			var label := String(button.get_meta("menu_label", button.text))
			var label_width := minf(row_width * 0.65, float(label.length() * font_size))
			arrow.position = Vector2((row_width - label_width) * 0.5 - 42.0 * compact_scale, 0.0)
			arrow.size = Vector2(32.0 * compact_scale, row_height)
			arrow.add_theme_font_size_override("font_size", maxi(14, font_size - 2))

func _build_text_title() -> void:
	title_group = Control.new()
	title_group.name = "TextTitle"
	title_group.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title_group.offset_left = -820.0
	title_group.offset_right = 820.0
	title_group.offset_top = 100.0
	title_group.offset_bottom = 470.0
	title_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_group.modulate.a = 0.0
	add_child(title_group)
	var title_decoration := Control.new()
	title_decoration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_decoration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_decoration.draw.connect(func(): _draw_text_title_rules(title_decoration))
	title_group.add_child(title_decoration)
	var title_font := SystemFont.new()
	title_font.font_names = PackedStringArray(["Georgia", "Times New Roman"])
	title_font.font_weight = 700
	title_font.allow_system_fallback = true
	var title_label := Label.new()
	title_label.text = "PARADISE"
	title_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	title_label.offset_left = -810.0
	title_label.offset_right = 810.0
	title_label.offset_top = 48.0
	title_label.offset_bottom = 316.0
	title_label.add_theme_font_override("font", title_font)
	title_label.add_theme_font_size_override("font_size", 230)
	title_label.add_theme_color_override("font_color", Color("fffaf2"))
	title_label.add_theme_color_override("font_outline_color", Color(0.015, 0.022, 0.035, 0.86))
	title_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.62))
	title_label.add_theme_constant_override("outline_size", 3)
	title_label.add_theme_constant_override("shadow_offset_x", 0)
	title_label.add_theme_constant_override("shadow_offset_y", 5)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_group.add_child(title_label)

func _draw_text_title_rules(canvas: Control) -> void:
	var width := canvas.size.x
	var center_x := width * 0.5
	var ivory := Color(0.96, 0.95, 0.89, 0.84)
	var gold := Color(SystemUI.GOLD, 0.88)
	var top_y := 30.0
	var bottom_y := 326.0
	canvas.draw_line(Vector2(170, top_y), Vector2(center_x - 22, top_y), ivory, 2.0, true)
	canvas.draw_line(Vector2(center_x + 22, top_y), Vector2(width - 170, top_y), ivory, 2.0, true)
	canvas.draw_line(Vector2(95, bottom_y), Vector2(center_x - 26, bottom_y), ivory, 2.0, true)
	canvas.draw_line(Vector2(center_x + 26, bottom_y), Vector2(width - 95, bottom_y), ivory, 2.0, true)
	canvas.draw_line(Vector2(width * 0.22, bottom_y + 8.0), Vector2(width * 0.78, bottom_y + 8.0), Color(ivory, 0.32), 1.0, true)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(center_x, top_y - 5.0), Vector2(center_x + 5.0, top_y),
		Vector2(center_x, top_y + 5.0), Vector2(center_x - 5.0, top_y),
	]), SystemUI.CRYSTAL)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(center_x, bottom_y - 6.0), Vector2(center_x + 6.0, bottom_y),
		Vector2(center_x, bottom_y + 6.0), Vector2(center_x - 6.0, bottom_y),
	]), gold)

func _background_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.53, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.015, 0.025, 0.04, 0.2),
		Color(0.02, 0.03, 0.045, 0.32),
		Color(0.008, 0.014, 0.025, 0.56),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture

func _bottom_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0.035, 0.047, 0.058, 0.0), Color(0.035, 0.047, 0.058, 0.94)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture

func _draw_title_ambience() -> void:
	var canvas := ambient_layer
	var view := canvas.size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	var pulse := 0.78 + 0.22 * sin(title_time * 0.52)
	_draw_soft_glow(canvas, Vector2(view.x * 0.5, view.y * 0.30), 330.0, SystemUI.GOLD, 0.028 * pulse)
	_draw_soft_glow(canvas, Vector2(view.x * 0.51, view.y * 0.23), 190.0, SystemUI.CRYSTAL, 0.018 * pulse)
	_draw_soft_glow(canvas, Vector2(view.x * 0.515, view.y * 0.31), 112.0, SystemUI.CRYSTAL, 0.045 * pulse)
	_draw_soft_glow(canvas, Vector2(view.x * 0.76, view.y * 0.64), 240.0, SystemUI.CRYSTAL, 0.012)
	var gate_center := Vector2(view.x * 0.77, view.y * 0.41)
	_draw_soft_glow(canvas, gate_center, 210.0, SystemUI.CRYSTAL, 0.045 * pulse)
	_draw_soft_glow(canvas, gate_center + Vector2(0.0, view.y * 0.18), 150.0, SystemUI.GOLD, 0.026 * pulse)
	var hero_shadow := Vector2(view.x * 0.18, view.y * 0.902)
	var ui_scale := minf(view.x / 1920.0, view.y / 1080.0)
	canvas.draw_set_transform(hero_shadow, 0.0, Vector2(1.9, 0.38) * ui_scale)
	canvas.draw_circle(Vector2.ZERO, 28.0, Color(0.005, 0.012, 0.025, 0.32))
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var cx := view.x * 0.5
	var rule_y := 548.0
	canvas.draw_line(Vector2(cx - 94.0, rule_y), Vector2(cx - 18.0, rule_y), Color(SystemUI.GOLD, 0.35), 1.0)
	canvas.draw_line(Vector2(cx + 18.0, rule_y), Vector2(cx + 94.0, rule_y), Color(SystemUI.GOLD, 0.35), 1.0)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(cx, rule_y - 5.0), Vector2(cx + 5.0, rule_y),
		Vector2(cx, rule_y + 5.0), Vector2(cx - 5.0, rule_y),
	]), Color(SystemUI.CRYSTAL, 0.88))
	for index in range(24):
		var i := float(index)
		var x := fposmod(i * 181.7 + title_time * (5.0 + float(index % 5) * 1.7), view.x)
		var y := fposmod(i * 97.3 - title_time * (7.0 + float(index % 4) * 1.9), view.y)
		var twinkle := 0.35 + 0.65 * (0.5 + 0.5 * sin(title_time * 1.1 + i * 3.7))
		var tint := SystemUI.CRYSTAL if index % 7 == 0 else SystemUI.GOLD
		var radius := 0.8 + float(index % 3) * 0.38
		canvas.draw_circle(Vector2(x, y), radius * 3.4, Color(tint.r, tint.g, tint.b, 0.025 * twinkle))
		canvas.draw_circle(Vector2(x, y), radius, Color(tint.r, tint.g, tint.b, 0.25 * twinkle))
	for index in range(12):
		var i := float(index)
		var x := fposmod(i * 131.0 + title_time * 17.0, view.x)
		if x > view.x * 0.34 and x < view.x * 0.66:
			continue
		var y := fposmod(i * 89.0 + title_time * 92.0, view.y)
		var rain_alpha := 0.045 + 0.025 * (0.5 + 0.5 * sin(title_time + i))
		canvas.draw_line(Vector2(x, y), Vector2(x - 3.0, y + 14.0), Color(0.58, 0.73, 0.89, rain_alpha), 1.0)

func _draw_soft_glow(canvas: Control, center: Vector2, radius: float, tint: Color, strength: float) -> void:
	for index in range(6):
		var progress := float(index + 1) / 6.0
		var layer_radius := radius * (1.0 - progress * 0.82)
		var layer_alpha := strength * progress * 0.55
		canvas.draw_circle(center, layer_radius, Color(tint.r, tint.g, tint.b, layer_alpha))

func _build_center() -> Button:
	prompt_label = _label(self, "按下任意键", 21, SystemUI.TEXT)
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	prompt_label.offset_left = -240
	prompt_label.offset_right = 240
	prompt_label.offset_top = 650
	prompt_label.offset_bottom = 688
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.modulate.a = 0
	menu_center = CenterContainer.new()
	menu_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_center.offset_top = 100
	menu_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(menu_center)
	menu_column = VBoxContainer.new()
	menu_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_column.add_theme_constant_override("separation", 8)
	menu_column.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_column.custom_minimum_size.x = 520
	menu_center.add_child(menu_column)
	menu_buttons_container = VBoxContainer.new()
	menu_buttons_container.add_theme_constant_override("separation", 8)
	menu_column.add_child(menu_buttons_container)
	var has_save := GameState.has_progress()
	var start_button := _button(menu_buttons_container, "新游戏", func():
		GameState.reset_progress()
		GameState.change_scene(OPENING_SCENE), 460, 52, 25)
	var continue_button := _button(menu_buttons_container, "继续游戏", func(): GameState.change_scene(GameState.Campaign.SCENE), 460, 52, 25)
	continue_button.disabled = not has_save
	settings_button = _button(menu_buttons_container, "设置选项", func(): settings_panel.open(), 460, 52, 25)
	menu_focus_button = continue_button if has_save else start_button
	for button in menu_buttons:
		menu_button_enabled.append(not button.disabled)
		button.disabled = true
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return menu_focus_button

func _play_title_intro() -> void:
	await get_tree().process_frame
	title_group.modulate.a = 0.0
	for item in menu_item_roots:
		item.pivot_offset = item.size * 0.5
		item.modulate.a = 0.0
		item.scale = Vector2(0.96, 0.96)
	var title_tween := create_tween().set_parallel(true)
	title_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	title_tween.tween_property(title_group, "modulate:a", 1.0, 1.25)
	var version_tween := create_tween()
	version_tween.tween_interval(1.4)
	version_tween.tween_property(version_label, "modulate:a", 1.0, 0.65)
	prompt_intro_tween = create_tween()
	prompt_intro_tween.tween_interval(1.0)
	prompt_intro_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.55)
	await title_tween.finished
	if not _splash_active:
		return
	prompt_pulse_tween = create_tween().set_loops()
	prompt_pulse_tween.tween_property(prompt_label, "modulate:a", 0.42, 0.8).set_trans(Tween.TRANS_SINE)
	prompt_pulse_tween.tween_property(prompt_label, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

func _show_options() -> void:
	if not _splash_active:
		return
	_splash_active = false
	_apply_menu_selection(menu_focus_button)
	if prompt_intro_tween != null and prompt_intro_tween.is_running():
		prompt_intro_tween.kill()
	if prompt_pulse_tween != null and prompt_pulse_tween.is_running():
		prompt_pulse_tween.kill()
	var prompt_out := create_tween()
	prompt_out.tween_property(prompt_label, "modulate:a", 0.0, 0.2)
	for index in range(menu_buttons.size()):
		var button := menu_buttons[index]
		var item := menu_item_roots[index]
		button.disabled = true
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var item_tween := create_tween()
		var delay := float(index) * 0.12
		item_tween.tween_interval(delay)
		item_tween.set_parallel(true)
		item_tween.tween_property(item, "modulate:a", 1.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		item_tween.tween_property(item, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var enable_tween := create_tween()
		enable_tween.tween_interval(delay + 0.42)
		enable_tween.tween_callback(_enable_menu_option.bind(button, menu_button_enabled[index], button == menu_focus_button))

func _enable_menu_option(button: Button, enabled: bool, grab_focus: bool) -> void:
	button.disabled = not enabled
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	if grab_focus:
		button.grab_focus()

func _on_menu_button_selected(button: Button) -> void:
	if _splash_active or button.disabled:
		return
	_apply_menu_selection(button)

func _apply_menu_selection(selected: Button) -> void:
	for button in menu_buttons:
		var is_selected := button == selected
		var label := String(button.get_meta("menu_label", button.text))
		button.text = label
		var arrow := button.get_meta("menu_arrow") as Label
		if is_instance_valid(arrow):
			arrow.visible = is_selected
		button.add_theme_color_override("font_color", SystemUI.TEXT if is_selected else Color("c4c7cb"))

func _input(event: InputEvent) -> void:
	if not _splash_active or not _is_start_input(event):
		return
	_show_options()
	get_viewport().set_input_as_handled()

func _is_start_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventJoypadButton:
		return event.pressed
	if event is InputEventJoypadMotion:
		return absf((event as InputEventJoypadMotion).axis_value) > 0.6
	if event is InputEventScreenTouch:
		return event.pressed
	return false

func _button(parent: Control, text: String, action: Callable, width: int, height: int, font_size: int) -> Button:
	var item := Control.new()
	item.custom_minimum_size = Vector2(width, height)
	item.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.modulate.a = 0.0
	item.scale = Vector2(0.96, 0.96)
	parent.add_child(item)
	var button := Button.new()
	button.text = text
	button.set_meta("menu_label", text)
	button.set_meta("menu_font_size", font_size)
	button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.custom_minimum_size = Vector2.ZERO
	button.add_theme_font_size_override("font_size", font_size)
	SystemUI.style_button(button)
	var clear_style := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", clear_style)
	button.add_theme_stylebox_override("hover", clear_style)
	button.add_theme_stylebox_override("pressed", clear_style)
	button.add_theme_stylebox_override("focus", clear_style)
	button.add_theme_stylebox_override("disabled", clear_style)
	button.add_theme_color_override("font_color", Color("c4c7cb"))
	button.add_theme_color_override("font_hover_color", SystemUI.TEXT)
	button.add_theme_color_override("font_pressed_color", SystemUI.GOLD)
	button.add_theme_color_override("font_focus_color", SystemUI.TEXT)
	button.add_theme_color_override("font_disabled_color", Color("85898d"))
	button.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.025, 0.8))
	button.add_theme_constant_override("outline_size", 2)
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.pressed.connect(action)
	button.focus_entered.connect(_on_menu_button_selected.bind(button))
	button.mouse_entered.connect(_on_menu_button_selected.bind(button))
	item.add_child(button)
	var arrow := Label.new()
	arrow.text = "▶"
	arrow.position = Vector2((float(width - text.length() * font_size) * 0.5) - 42.0, 0.0)
	arrow.size = Vector2(32.0, height)
	arrow.add_theme_font_size_override("font_size", font_size - 2)
	arrow.add_theme_color_override("font_color", SystemUI.TEXT)
	arrow.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.025, 0.8))
	arrow.add_theme_constant_override("outline_size", 2)
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.hide()
	item.add_child(arrow)
	button.set_meta("menu_arrow", arrow)
	menu_buttons.append(button)
	menu_item_roots.append(item)
	return button

func _label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.92))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_F3:
		GameState.change_scene(LEVEL_SELECT_SCENE)
		get_viewport().set_input_as_handled()
