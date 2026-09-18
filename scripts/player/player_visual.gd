extends AnimatedSprite3D
## 四方向移动/攻击 + 受击/闪避/死亡动画。
## 优先级：死亡 > 攻击 > 受击 > 闪避 > 待机/移动。

const CLIP_LEN := 0.8  # 单个动作动画全长（8 帧 @ 10fps）
const HIT_TIME := 0.22  # 受击动画展示时长

@onready var player: CharacterBody3D = get_parent().get_parent()
var attack_time_left: float = 0.0
var hit_timer: float = 0.0
var display_direction: String = "up"

func _ready() -> void:
	player.attacked.connect(_on_attacked)
	player.received_hit.connect(_on_hit)
	_update_locomotion()

func _process(delta: float) -> void:
	# 死亡：只在未播放时启动，播完停在最后一帧（不循环重播）
	if not player.alive:
		var death_clip := StringName("death_" + _to_dir_name(player.facing))
		if animation != death_clip:
			_play_action("death", player.facing, false)
		return

	attack_time_left = maxf(0.0, attack_time_left - delta)
	hit_timer = maxf(0.0, hit_timer - delta)

	# 攻击 > 受击 > 闪避
	if attack_time_left > 0.0:
		return
	if hit_timer > 0.0:
		_play_action("hit", player.facing, false)
		speed_scale = CLIP_LEN / HIT_TIME  # 压缩到受击展示时长内播完
		return
	if player.dodging:
		# 动画方向跟随实际闪避位移方向，并压缩到闪避时长内播完
		var dir: Vector3 = player.dodge_dir if player.dodge_dir.length_squared() > 0.001 else player.facing
		_play_action("dodge", dir, false)
		speed_scale = CLIP_LEN / maxf(player.dodge_duration, 0.05)
		return
	_update_locomotion()

func _to_dir_name(direction: Vector3) -> String:
	if absf(direction.x) >= absf(direction.z):
		return "right" if direction.x > 0.0 else "left"
	return "down" if direction.z > 0.0 else "up"

## 播放某个动作动画；loop 为 true 时若同一片段已在播放则不再重启。
func _play_action(action: String, direction: Vector3, loop: bool) -> void:
	display_direction = _to_dir_name(direction)
	var clip := StringName(action + "_" + display_direction)
	set_flip_for(action, display_direction)
	speed_scale = 1.0
	if animation == clip and is_playing():
		return
	play(clip)

## 方向与镜像：受击/死亡源图面朝右，仅左侧镜像。
## 剃的左右两个片段按美术要求与它们对调，因此镜像规则相反（左不镜像、右镜像）。
func set_flip_for(action: String, direction: String) -> void:
	if action == "dodge":
		flip_h = direction == "right"
	else:
		flip_h = direction == "left"

func _update_locomotion() -> void:
	display_direction = _to_dir_name(player.facing)
	var moving: bool = player.input_dir.length_squared() > 0.001
	var clip: StringName = StringName(("walk_" if moving else "idle_") + display_direction)
	# 侧向移动/待机源面朝右，仅左侧镜像。
	flip_h = display_direction == "left"
	speed_scale = 1.0
	if animation != clip or not is_playing():
		play(clip)

func _on_attacked(_stage: int) -> void:
	display_direction = _to_dir_name(player.facing)
	attack_time_left = player.base_attack_cooldown
	var clip := StringName("attack_" + display_direction)
	flip_h = display_direction == "right"
	speed_scale = CLIP_LEN / maxf(player.base_attack_cooldown, 0.01)
	stop()
	play(clip)

func _on_hit() -> void:
	hit_timer = HIT_TIME  # 受击动画展示时长

func reset_visual() -> void:
	attack_time_left = 0.0
	hit_timer = 0.0
	_update_locomotion()