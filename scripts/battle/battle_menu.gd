class_name BattleMenu
extends Control
## 指令面板（P1 v1）：我方回合的 攻击/战技/防御/道具/逃跑 五选一。
## Control 挂到 HUD（CanvasLayer）；按钮走 SystemUI 面板风，确认时发 confirmed 信号。

const SystemUI := preload("res://scripts/ui/system_ui.gd")

## 回合指令集（作者 2026-09-23 定）：**五条** —— 攻击 / 战技 / 防御 / 道具 / 逃跑。
## 练习场与新手教学场都必须用这一个常量，别再各写一份
## （旧口径是教学场三条、练习场五条，两套并存过，作者已统一为五条）。
const COMMANDS: Array[String] = ["攻击", "战技", "防御", "道具", "逃跑"]

signal confirmed(idx: int)
signal canceled

var commands: Array[String] = []
var selected := 0
var _list: VBoxContainer

func _ready() -> void:
	_rebuild()

func open(commands_list: Array[String]) -> void:
	commands = commands_list
	selected = 0
	visible = true
	_rebuild()
	_highlight()

func close() -> void:
	visible = false

func _rebuild() -> void:
	if _list != null:
		_list.queue_free()
	_list = VBoxContainer.new()
	_list.name = "CommandList"
	_list.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_list.add_theme_constant_override("separation", 10)
	# 底板：SystemUI 卡片（深蓝灰底 + 发丝框）
	var backing := PanelContainer.new()
	backing.add_theme_stylebox_override("panel", SystemUI.card())
	var title := Label.new()
	title.text = "选择指令"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", SystemUI.ACCENT)
	backing.add_child(title)
	_list.add_child(backing)
	for text in commands:
		var btn := Button.new()
		btn.text = text
		btn.custom_minimum_size = Vector2(220, 44)
		SystemUI.style_button(btn)
		btn.pressed.connect(_on_pressed.bind(commands.find(text)))
		_list.add_child(btn)
	add_child(_list)

func _highlight() -> void:
	var idx := 0
	for child in _list.get_children():
		if child is Button:
			(child as Button).modulate = Color.WHITE if idx == selected else Color(1, 1, 1, 0.75)
			idx += 1

func _on_pressed(idx: int) -> void:
	selected = idx
	confirmed.emit(idx)