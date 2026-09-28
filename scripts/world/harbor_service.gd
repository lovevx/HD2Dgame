extends Area3D
## 主城服务入口；经济与任务系统接入前只展示功能说明。
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")
const GameAudio := preload("res://data/game_audio.gd")
@export var title := ""
@export_multiline var description := ""
var visitor: Node3D
var opened := false
var campaign_action: Callable
## 自定义打开方式（如轮回商店的完整 UI）：V 触发时优先于默认说明面板与 campaign_action。
## 打开/关闭（含冻结玩家、Esc 关闭）由接线的面板自己负责。
var panel_handler: Callable

func _ready() -> void:
	body_entered.connect(func(body: Node3D):
		if body.is_in_group("player"):
			visitor = body)
	body_exited.connect(func(body: Node3D):
		if body == visitor:
			visitor = null
			var hud = get_tree().get_first_node_in_group("hud")
			if hud:
				hud.hide_prompt())

func _process(_delta: float) -> void:
	if visitor == null or opened or GameState.is_transitioning():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null or hud.is_modal_open():
		return
	hud.show_prompt("%s  查看%s" % [KeyBindings.key_text("interact"), title])

func _unhandled_input(event: InputEvent) -> void:
	if visitor == null or opened or GameState.is_transitioning():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null or hud.is_modal_open():
		return
	if event.is_action_pressed("interact"):
		GameAudio.play_sfx("ui_confirm", global_position, -9.0)
		# 战役模式的服务面板（campaign_action）最具体，优先；其次轮回商店等自定义 UI；
		# 都没有才走默认的说明面板。
		if campaign_action.is_valid():
			campaign_action.call()
			get_viewport().set_input_as_handled()
			return
		if panel_handler.is_valid():
			hud.hide_prompt()
			panel_handler.call()
			get_viewport().set_input_as_handled()
			return
			campaign_action.call()
			get_viewport().set_input_as_handled()
			return
		opened = true
		visitor.set_physics_process(false)
		hud.hide_prompt()
		var pages: Array[String] = []
		for paragraph: String in description.split("\n\n", false):
			pages.append(paragraph)
		if pages.is_empty():
			pages.append("")
		hud.show_dialogue(title, pages, close)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if opened and event.is_action_pressed("open_menu"):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.close_dialogue(false)
	if visitor:
		visitor.set_physics_process(true)
	opened = false
