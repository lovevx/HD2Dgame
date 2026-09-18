extends Control
## 选关面板（方案 2）：直接进入科尔波山两个白盒关卡。
## 开发测试可跳过小怪直打 BOSS，也支持先走外围再传送进空地的线性流程。
## 白盒阶段只负责场景跳转，不读写任何正式货币、任务或存档。

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
	background.color = Color("0b1410")
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 860
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	_text(column, "科尔波山 · 白盒关卡", 42, Color("a5dfff"))
	_text(column, "当前为纯空间白盒：只验证空间、掩体与流程标记，尚未接入敌人、波次与陷阱逻辑", 20, Color("8fa6ad"))
	for level in LEVELS:
		_button(column, level["title"], level["path"], 26, Vector2(860, 62))
		_text(column, level["desc"], 19, Color("c6d3d8"))
	_text(column, "其他已建场景（调试入口，关卡内按 Esc 可回到本面板）", 19, Color("8fa6ad"))
	for scene in OTHER_SCENES:
		_button(column, scene["title"], scene["path"], 21, Vector2(860, 46))
	_text(column, "WASD 移动 · 左键朝鼠标连击 · Shift 剃 · 数字 1 炸弹 · 数字 2 药剂 · 鼠标移动调整镜头 · V 交互 · F1 按键说明 · 数字键 1 / 2 直接进关", 19, Color("7f949b"))

func _button(parent: Node, title: String, path: String, font_size: int, min_size: Vector2) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", font_size)
	button.pressed.connect(_enter.bind(path))
	parent.add_child(button)

func _text(parent: Node, text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)

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
