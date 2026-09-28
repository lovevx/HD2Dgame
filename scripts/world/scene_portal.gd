extends Area3D
const GameAudio := preload("res://data/game_audio.gd")
## 场景传送门：玩家走进传送门区域即触发切场景，不再按 V 交互。
## 清场门控读全局 enemies 组与波次调度：未清场时走进只显示锁定提示，不会传送。

@export_file("*.tscn") var target_scene: String = ""
@export var prompt_text: String = "前往下一区域"
@export var requires_cleared: bool = false
@export var locked_text: String = "传送未开启：先清除区域内威胁"

var _player: Node3D = null
var _prompt := ""
var _was_locked := true  # 玩家在圈内时的锁定状态，解锁瞬间触发传送
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
	var locked := _locked()
	if locked:
		_was_locked = true
		_set_prompt(locked_text, true)
		return
	# 走进传送门且已解锁：直接传送（进圈即触发，或清场解锁瞬间触发）
	if _was_locked:
		enter()
	_was_locked = false

## 当前是否锁定：既要没清场/门控不放行。
func _locked() -> bool:
	if campaign_can_enter.is_valid() and not campaign_can_enter.call():
		return true
	if requires_cleared and not is_cleared():
		return true
	return false

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
	if _locked():
		return
	GameAudio.play_sfx("ui_confirm", Vector3.INF, -7.0)
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
		_was_locked = true  # 重新进圈：解锁与否由下一帧 _process 判定

func _on_body_exited(body: Node3D) -> void:
	if body == _player:
		_player = null
		_was_locked = true
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
