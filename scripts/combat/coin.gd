extends Area3D
## 乐园币掉落物：靠近自动磁吸，接触玩家后入账
const GameAudio := preload("res://data/game_audio.gd")

@export var value: int = 3
var magnet_radius: float = 4.0
var collected: bool = false
var player: Node3D
var tween: Tween

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	if collected or not player:
		return
	var to := global_position - player.global_position
	var dist := to.length()
	if dist <= magnet_radius:
		# 磁吸
		global_position = global_position.move_toward(player.global_position, 6.0 * delta)
	if dist <= 0.9:
		_collect()

func _collect() -> void:
	if collected:
		return
	collected = true
	GameState.add_coins(value)
	GameAudio.play_sfx("coin", global_position, -2.0, randf_range(0.96, 1.05))
	tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
