extends Control
## 游戏主菜单：有存档时显示「继续游戏」（恢复阶段试炼检查点），否则「开始新游戏」
## 走「开场剧情 + 登记姓名」（会覆盖旧档）。「关卡调试」保留给白盒阶段开发用。
## 配色沿用系统面板风：深蓝灰底 + 电光青系统色（蓝=系统），金色仅保留高价值（标题/悬停）。

const SystemUI := preload("res://scripts/ui/system_ui.gd")
const SettingsPanelScript := preload("res://scripts/ui/settings_panel.gd")
const OPENING_SCENE := "res://scenes/main/opening.tscn"
const LEVEL_SELECT_SCENE := "res://scenes/main/level_select.tscn"
const HARBOR_SCENE := "res://scenes/world/harbor.tscn"
const VERSION_HINT := "海贼王 · 核心循环原型  /  截止科尔波山猎虎"

var settings_panel: CanvasLayer
var settings_button: Button

func _ready() -> void:
	_build_background()
	var first := _build_center()
	_build_settings()
	first.grab_focus()

## 设置面板：与游戏内是同一个面板脚本，只是这里挂在主菜单自己身上（主菜单没有 HUD）。
func _build_settings() -> void:
	settings_panel = SettingsPanelScript.new()
	settings_panel.name = "SettingsPanel"
	add_child(settings_panel)
	settings_panel.closed.connect(func(): settings_button.grab_focus())

## 深蓝夜色渐变底 + 顶部细金线，按下菜单后过场进入开场剧情。
func _build_background() -> void:
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.gradient.colors = PackedColorArray([Color("08111c"), Color("0c1e2e"), Color("122c3d")])
	grad.fill_from = Vector2(0.5, 0)
	grad.fill_to = Vector2(0.5, 1)
	bg.texture = grad
	add_child(bg)
	# 菜单标题下方的金色分隔线（金色 = 高价值）
	var gold_line := ColorRect.new()
	gold_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	gold_line.position = Vector2(-460, 330)
	gold_line.size = Vector2(920, 3)
	gold_line.color = Color("ebd6a2")
	gold_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gold_line)
	# 两侧青色系统导轨（蓝 = 系统）
	for side in [-1.0, 1.0]:
		var rail := ColorRect.new()
		rail.position = Vector2(320 if side < 0 else 1596, 268)
		rail.size = Vector2(3, 232)
		rail.color = Color(SystemUI.ACCENT_DIM, 0.5)
		rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rail)
	var version := _label(self, VERSION_HINT, 17, SystemUI.TEXT_DIM)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	version.position = Vector2(26, 1036)
	version.size = Vector2(900, 30)

func _build_center() -> Button:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 18)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(column)
	var title := _label(column, "轮回乐园", 76, Color("ebd6a2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := _label(column, "海贼王 · 阶段试炼　　截止科尔波山猎虎", 26, SystemUI.ACCENT)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 48
	column.add_child(spacer)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 20)
	column.add_child(buttons)
	var first: Button
	if GameState.has_progress():
		first = _button(buttons, "继续游戏 · %s" % GameState.player_name, func(): GameState.change_scene(GameState.Campaign.SCENE), 460, 66, 30)
	var start_button := _button(buttons, "开始新游戏", func():
		GameState.reset_progress()
		GameState.change_scene(OPENING_SCENE), 460, 66, 30)
	if first == null:
		first = start_button
	_button(buttons, "关卡调试 · 选关", func(): GameState.change_scene(LEVEL_SELECT_SCENE), 460, 58, 24)
	settings_button = _button(buttons, "设 置", func(): settings_panel.open(), 460, 58, 24)
	_button(buttons, "退出游戏", func(): get_tree().quit(), 460, 58, 24)
	return first

func _button(parent: Control, text: String, action: Callable, width: int, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, height)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", SystemUI.TEXT)
	button.add_theme_color_override("font_hover_color", Color("ebd6a2"))
	button.add_theme_color_override("font_focus_color", Color("ebd6a2"))
	button.add_theme_stylebox_override("normal", _button_style(Color("0d1526"), Color(SystemUI.BORDER, 0.6)))
	button.add_theme_stylebox_override("hover", _button_style(Color("14233c"), SystemUI.ACCENT))
	button.add_theme_stylebox_override("pressed", _button_style(Color("0a1120"), SystemUI.ACCENT))
	button.add_theme_stylebox_override("focus", _button_style(Color("14233c"), SystemUI.ACCENT))
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	return SystemUI.flat(bg, border, 2, SystemUI.RADIUS, 14)

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
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()