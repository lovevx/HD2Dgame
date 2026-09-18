extends Area3D
## 场景传送门：玩家进圈后贴底提示，按 V（interact）交互切场景。
## 白盒阶段只负责「进圈 → 提示 → 按 V → 过场切场景」；清场门控读全局 enemies 组，
## 现在没有敌人时视为已清空，等波次系统接进来后自动开始生效。

@export_file("*.tscn") var target_scene: String = ""
@export var prompt_text: String = "前往下一区域"
@export var requires_cleared: bool = false
@export var locked_text: String = "传送未开启：先清除区域内威胁"

var _player: Node3D = null
var _prompt := ""
var campaign_action: Callable
var campaign_can_enter: Callable

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if _player == null or not _player.get("alive"):
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if GameState.is_transitioning() or (hud != null and hud.is_modal_open()):
		return
	if campaign_can_enter.is_valid() and not campaign_can_enter.call():
		_set_prompt(locked_text, true)
		return
	if requires_cleared and not is_cleared():
		_set_prompt(locked_text, true)
		return
	_set_prompt("V  " + prompt_text, false)
	if Input.is_action_just_pressed("interact"):
		enter()

## 场上是否已清空：既要没有存活敌人，也要波次调度已经打完（波与波之间的空隙不算清场）。
func is_cleared() -> bool:
	for director in get_tree().get_nodes_in_group("wave_director"):
		if director.has_method("is_finished") and not director.is_finished():
			return false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("is_alive") and enemy.is_alive():
			return false
	return true

## 开门：交给 GameState 做过场，避免硬切。
func enter() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if GameState.is_transitioning() or (hud != null and hud.is_modal_open()):
		return
	if campaign_can_enter.is_valid() and not campaign_can_enter.call():
		return
	if requires_cleared and not is_cleared():
		return
	if campaign_action.is_valid():
		campaign_action.call()
		return
	if target_scene == "":
		push_warning("传送门 %s 没有设置目标场景" % name)
		return
	_set_prompt("")
	GameState.change_scene(target_scene)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player = body

func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_set_prompt("")

## 提示只在内容变化时推给 HUD，避免每帧刷新打断底部的淡出动画。
func _set_prompt(text: String, locked := false) -> void:
	if _prompt == text:
		return
	_prompt = text
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if text == "":
		hud.hide_prompt()
	else:
		hud.show_prompt(text, locked)
