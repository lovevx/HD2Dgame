extends Control
## 选关面板（方案 2）：直接进入科尔波山两个白盒关卡。
## 开发测试可跳过小怪直打 BOSS，也支持先走外围再传送进空地的线性流程。
## 白盒阶段只负责场景跳转，不读写任何正式货币、任务或存档。

## 操作说明里的键名现读（改键后这行不会还在喊旧键）。
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")
const SystemUI := preload("res://scripts/ui/system_ui.gd")

const LEVELS := [
	{
		"title": "① 科尔波山 · 山林外围",
		"desc": "小怪热身关：3 波递进（2 野狼 → 野猪 + 2 野狼 → 野兽 + 2 无能量肉体傀儡）。清场后走传送门前往林间空地。",
		"path": "res://scenes/world/colpo_forest_outer.tscn",
	},
	{
		"title": "② 科尔波山 · 林间决战空地",
		"desc": "BOSS 关：直达科尔波山之主（巨型变异巨虎），15 秒准备后开战。",
		"path": "res://scenes/world/colpo_forest_clearing.tscn",
	},
]

## 其他已建场景（调试入口）：从任意场景按 Esc 都能回到这里。
const OTHER_SCENES := [
	{"title": "灰潮港口（主城）", "path": "res://scenes/world/harbor.tscn"},
	{"title": "灰潮 · 战斗试炼（P0）", "path": "res://scenes/main/main.tscn"},
]

func _ready() -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = SystemUI.SCREEN_BG
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var tint := TextureRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.texture = _background_gradient()
	tint.stretch_mode = TextureRect.STRETCH_SCALE
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1120, 900)
	card.add_theme_stylebox_override("panel", SystemUI.card())
	SystemUI.decor(card)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 1060
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	_text(column, "科尔波山 · 关卡选择", 38, SystemUI.GOLD)
	_text(column, "白盒流程验证 · 直接进入指定区域", 18, SystemUI.TEXT_DIM)
	column.add_child(HSeparator.new())
	_text(column, "核心试炼", 20, SystemUI.CRYSTAL)
	for level in LEVELS:
		_level_row(column, level)
	column.add_child(HSeparator.new())
	_text(column, "其他场景 · 调试入口", 20, SystemUI.CRYSTAL)
	var other_scenes := HBoxContainer.new()
	other_scenes.add_theme_constant_override("separation", 12)
	column.add_child(other_scenes)
	for scene in OTHER_SCENES:
		_button(other_scenes, scene["title"], scene["path"], 19, Vector2(0, 52))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var controls := _text(column, "WASD 移动 · %s 斩击（朝鼠标单段） · %s 剃 · 鼠标中键拖动取景 · 滚轮推拉镜头 · %s 炸弹 · %s 药剂 · %s 交互 · %s 按键说明 · 数字键 1 / 2 直接进关" % [
		KeyBindings.key_text("attack"), KeyBindings.key_text("dodge"), KeyBindings.key_text("bomb"),
		KeyBindings.key_text("potion"), KeyBindings.key_text("interact"), KeyBindings.key_text("key_guide"),
	], 16, SystemUI.TEXT_DIM)
	controls.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _background_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("252d35"), Color("161c23")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	return texture

func _level_row(parent: Control, level: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 132
	panel.add_theme_stylebox_override("panel", SystemUI.sub())
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	_text(info, str(level["title"]), 23, SystemUI.GOLD)
	var desc := _text(info, str(level["desc"]), 17, SystemUI.TEXT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var enter := _button(row, "进 入", level["path"], 21, Vector2(160, 58))
	enter.size_flags_horizontal = Control.SIZE_SHRINK_END

func _button(parent: Node, title: String, path: String, font_size: int, min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = min_size
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", font_size)
	SystemUI.style_button(button)
	button.pressed.connect(_enter.bind(path))
	parent.add_child(button)
	return button

func _text(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ESCAPE:
		get_tree().quit()
	elif event.physical_keycode == KEY_1:
		_enter(LEVELS[0]["path"])
	elif event.physical_keycode == KEY_2:
		_enter(LEVELS[1]["path"])

func _enter(path: String) -> void:
	GameState.change_scene(path)
