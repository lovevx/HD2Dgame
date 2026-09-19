extends AnimatedSprite3D
## 八方向移动 + 三段独立攻击 + 受击/闪避/死亡动画。
## 优先级：死亡 > 攻击 > 受击 > 闪避 > 待机/移动。
## 八方向画法：每动作只画 up/down/right/up_right/down_right 五张图集，
## left/up_left/down_left 由 flip_h 水平镜像生成（MIRRORED_DIRS）。

const CLIP_LEN := 0.8  # 单个动作动画全长（8 帧 @ 10fps）
const HIT_TIME := 0.22  # 受击动画展示时长
const BASE_PIXEL_SIZE := 0.016
const BASE_OFFSET := Vector2(0, 64)

## 行走一圈（8 帧 = 2 步）覆盖的地面位移（米）：2 × 约 0.74 米/步。
## 步长按 walk_right 接触帧两腿中心间距 46px × 0.016 量得。
## 用它把步频绑到实际移速，避免位移与步频脱节造成脚底打滑。
const WALK_STRIDE_PER_CYCLE := 1.47
## 步频倍率上下限：低于下限像定帧，高于上限会糊成一片。
const WALK_SPEED_SCALE := Vector2(0.6, 3.0)

## 45° 斜向图集的尺寸补偿：这批图在生成时被画大了，按实测身高比缩回正交视角的大小。
## 缩放 pixel_size 不会让脚离地——格子里的脚底锚点 (96,144) 正好对应节点原点。
## 键为动作名，值为斜向视角的补偿系数；正交视角恒为 1.0。
## walk 已于 2026-09-19 重画对齐（实测 1.02x / 0.99x），故不再需要补偿。
## idle 仍是旧图（斜向 113.3px vs 正交 106.8px），重新出图对齐后删掉本条即可。
const DIAGONAL_SCALE := {
	"idle": 0.94,
}
## 需要套用尺寸补偿的朝向：左斜两向与右斜共用同一张图集，同样要缩。
const DIAGONAL_DIRS := {"up_right": true, "down_right": true, "up_left": true, "down_left": true}

## 8 个朝向的 clip 后缀，按 atan2(x,z) 角度四十五度分格顺序排列。
const DIR_NAMES: Array[String] = [
	"down", "down_right", "right", "up_right",
	"up", "up_left", "left", "down_left",
]
## 这 3 个朝向的图集复用右侧系并水平镜像（所有侧面/斜向图集统一面朝右）。
const MIRRORED_DIRS := {"left": true, "up_left": true, "down_left": true}

@onready var player: CharacterBody3D = get_parent().get_parent()
var attack_time_left: float = 0.0
var hit_timer: float = 0.0
var guard_timer: float = 0.0
var display_direction: String = "up"

func _ready() -> void:
	player.attacked.connect(_on_attacked)
	player.received_hit.connect(_on_hit)
	player.guarded.connect(_on_guarded)
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
	guard_timer = maxf(0.0, guard_timer - delta)

	# 攻击 > 受击 > 闪避
	if attack_time_left > 0.0:
		return
	if guard_timer > 0.0:
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

## 把面向向量量化到 8 方向之一：atan2(x,z) 每 45° 一档。
func _to_dir_name(direction: Vector3) -> String:
	var index := int(round(atan2(direction.x, direction.z) / (PI / 4.0))) % 8
	if index < 0:
		index += 8
	return DIR_NAMES[index]

## 该动作 + 该朝向下应使用的 pixel_size：只对 45° 斜向做尺寸补偿，其余保持基准。
func _pixel_size_for(action: String, direction: String) -> float:
	if direction in DIAGONAL_DIRS:
		return BASE_PIXEL_SIZE * float(DIAGONAL_SCALE.get(action, 1.0))
	return BASE_PIXEL_SIZE

## 播放某个动作动画；loop 为 true 时若同一片段已在播放则不再重启。
func _play_action(action: String, direction: Vector3, loop: bool) -> void:
	display_direction = _to_dir_name(direction)
	var clip := StringName(action + "_" + display_direction)
	pixel_size = _pixel_size_for(action, display_direction)
	offset = BASE_OFFSET
	set_flip_for(action, display_direction)
	speed_scale = 1.0
	if animation == clip and is_playing():
		return
	play(clip)

## 镜像：所有侧面/斜向图集统一面朝右，左侧三向（left/up_left/down_left）水平镜像。
func set_flip_for(_action: String, direction: String) -> void:
	flip_h = direction in MIRRORED_DIRS

func _update_locomotion() -> void:
	offset = BASE_OFFSET
	display_direction = _to_dir_name(player.facing)
	var moving: bool = player.input_dir.length_squared() > 0.001
	var action: String = "walk" if moving else "idle"
	var clip: StringName = StringName(action + "_" + display_direction)
	pixel_size = _pixel_size_for(action, display_direction)
	# 侧面/斜向源图统一面朝右，仅左侧三向镜像。
	flip_h = display_direction in MIRRORED_DIRS
	# 步频跟随实际移速：一圈耗时 = CLIP_LEN / speed_scale，令其等于"步幅 / 移速"，
	# 即 speed_scale = 移速 × CLIP_LEN / 步幅。减速（如攻击中）时步频自动放慢。
	# 待机是呼吸循环，不参与同步。
	if moving:
		var ground_speed := Vector2(player.velocity.x, player.velocity.z).length()
		speed_scale = clampf(ground_speed * CLIP_LEN / WALK_STRIDE_PER_CYCLE,
			WALK_SPEED_SCALE.x, WALK_SPEED_SCALE.y)
	else:
		speed_scale = 1.0
	if animation != clip or not is_playing():
		play(clip)

func _on_attacked(stage: int) -> void:
	display_direction = _to_dir_name(player.facing)
	attack_time_left = player.attack_cd
	var action: String = ["attack", "stab", "heavy"][clampi(stage, 0, 2)]
	var clip := StringName(action + "_" + display_direction)
	# 三段攻击图集均为统一的 192x160 网格，共用一个 offset；45° 斜向另有尺寸补偿。
	pixel_size = _pixel_size_for(action, display_direction)
	offset = BASE_OFFSET
	# 侧面/斜向源图统一面朝右，仅左侧三向镜像。
	flip_h = display_direction in MIRRORED_DIRS
	speed_scale = CLIP_LEN / maxf(player.attack_cd, 0.01)
	stop()
	play(clip)

func _on_hit() -> void:
	hit_timer = HIT_TIME  # 受击动画展示时长

func _on_guarded() -> void:
	guard_timer = 0.35
	_play_action("guard", player.facing, false)
	speed_scale = CLIP_LEN / guard_timer

func reset_visual() -> void:
	attack_time_left = 0.0
	hit_timer = 0.0
	guard_timer = 0.0
	_update_locomotion()
