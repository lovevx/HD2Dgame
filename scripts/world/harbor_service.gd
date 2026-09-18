extends Area3D
## 主城服务入口；经济与任务系统接入前只展示功能说明。
@export var title := ""
@export_multiline var description := ""
var visitor: Node3D
var opened := false
var campaign_action: Callable

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
	hud.show_prompt("V  查看" + title)

func _unhandled_input(event: InputEvent) -> void:
	if visitor == null or opened or GameState.is_transitioning():
		return
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null or hud.is_modal_open():
		return
	if event.is_action_pressed("interact"):
		if campaign_action.is_valid():
			campaign_action.call()
			get_viewport().set_input_as_handled()
			return
		opened = true
		visitor.set_physics_process(false)
		hud.hide_prompt()
		hud.show_panel(title, description, "返回港口", close)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if opened and event.is_action_pressed("open_menu"):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	var hud = get_tree().get_first_node_in_group("hud")
	if hud:
		hud.hide_panel()
	if visitor:
		visitor.set_physics_process(true)
	opened = false
