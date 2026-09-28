extends AnimatedSprite3D
## 八方向移动 + 竖斩/横斩交替普攻 + 独立技能/受击/闪避/死亡动画。
## 优先级：死亡 > 攻击 > 受击 > 闪避 > 待机/移动。
## 图集：每动作 8 个朝向**全部真实绘制**（新版动作 sheet，见 assets/characters/black_swordsman/ANIMATION_SPEC.md），
## 因此不再水平镜像、也不做斜向尺寸补偿；各动作的方向比例已烘焙进图集。
## 格子尺寸全动作统一（224×192，地面线在格底往上 GROUND_SLACK），offset 由当前帧区域高度推出（见 _sync_offset）。

const CLIP_LEN := 0.8  # 单个动作动画全长（12 帧 @ 15fps）
## 闪避收尾余量：12 帧动画（0.8s）压缩到「闪避时长 − DODGE_SETTLE」内播完，
## 提前约 0.05s 停在末帧（直立），避免动画与闪避结束边界竞态重播而"最后一跳"。
const DODGE_SETTLE := 0.05
## 受击动画展示时长：12 帧 @15fps 的原始全长是 0.8s，压进 0.22s 相当于 55fps 频闪
## （一闪就没，看不出受击姿态）；0.35s ≈ 2.3 倍速，既保持受击的急促感又读得清动作。
const HIT_TIME := 0.35
const BASE_PIXEL_SIZE := 0.016
const BASE_OFFSET := Vector2(0, 64)
## 帧内锚点：地面线在格子底边往上这么多像素（打包脚本同口径）。
const GROUND_SLACK := 16
## 常驻移动模式 = 跑步（2026-09-21：walk 图集斜向帧序列有复用问题，直接停用，
## 移动一律播 run；run 的 8 向图集都是真实绘制，无斜向复用）。
const LOCOMOTION_CLIP := "run"
## 连段仍是单段；普攻在原竖斩与新横斩间交替，直踹继续使用独立动作。
const COMBO_CLIPS: Array[String] = ["attack"]

## 跑步剪辑（12 帧 @15fps = 0.8s，= **一个**步态周期）覆盖的地面位移（米）。
## 2026-09-21 最新版 sheet：每周期步幅 = 1.75 × 最大脚距 68px × 0.016 ≈ 1.90m
## （1.75 系数与旧图集标定互相印证：1.75×53×0.016=1.47、1.75×66×0.016=1.85）。
## 用它把步频绑到实际移速，避免位移与步频脱节造成脚底打滑。
const RUN_STRIDE_PER_CYCLE := 1.86
## 步频衰减系数（2026-09-22）：仅放慢动画、不动移速。当前常驻移速 3.12 m/s 会催出
## 1.34 倍速（≈201 步/分钟）的"小碎步"，用户反馈过快；×0.82 降到 ≈1.10 倍（≈165 步/分钟），
## 步伐更沉稳。保留 <1 的轻微脚下滑动感以换取移速不变，不作为后续无脑拉大跨步的借口。
const RUN_CADENCE_FACTOR := 0.82
## 步频倍率上下限：低于下限像定帧，高于上限会糊成一片。
const WALK_SPEED_SCALE := Vector2(0.6, 3.0)

## 斜向尺寸补偿：新版图集打包时已统一缩放（本体高 104px），不再需要补偿，
## 保留结构与 DIAGONAL_DIRS 以便将来某套动作真的画大了再填。
const DIAGONAL_SCALE := {}
## 需要套用尺寸补偿的朝向：左斜两向与右斜共用同一张图集，同样要缩。
const DIAGONAL_DIRS := {"up_right": true, "down_right": true, "up_left": true, "down_left": true}

## 8 个朝向的 clip 后缀，按 atan2(x,z) 角度四十五度分格顺序排列。
const DIR_NAMES: Array[String] = [
	"down", "down_right", "right", "up_right",
	"up", "up_left", "left", "down_left",
]
## 镜像朝向：新版图集 8 个朝向都是真实绘制，**不能再镜像**——
## 镜像会让左手持刀（素材是面朝左画的），所以这里保持空表。
const MIRRORED_DIRS := {}

@onready var player: CharacterBody3D = get_parent().get_parent()
var attack_time_left: float = 0.0
var hit_timer: float = 0.0
var guard_timer: float = 0.0
var display_direction: String = "up"

func _ready() -> void:
	player.attacked.connect(_on_attacked)
	player.skill_animation_requested.connect(_on_skill_animation_requested)
	player.kicked.connect(_on_kicked)
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
	if player.dodging:
		attack_time_left = 0.0
	hit_timer = maxf(0.0, hit_timer - delta)
	guard_timer = maxf(0.0, guard_timer - delta)

	# 攻击 > 受击 > 闪避
	if attack_time_left > 0.0:
		return
	if guard_timer > 0.0:
		return
	if hit_timer > 0.0:
		_play_action("hit", player.facing, false)
		speed_scale = _clip_seconds(animation) / HIT_TIME  # 压缩到受击展示时长内播完
		return
	if player.dodging:
		# 动画方向跟随实际闪避位移方向，并压缩到闪避时长内播完
		var dir: Vector3 = player.dodge_dir if player.dodge_dir.length_squared() > 0.001 else player.facing
		var clip := StringName("dodge_" + _to_dir_name(dir))
		# 非循环 12 帧播完即停帧收尾，不再从头重播
		# （闪避动画全长恰等于闪避时长，边界抖动时《played 完 + 状态未结束》会闪回起手帧，造成"最后跳一下"）
		if animation != clip or is_playing():
			_play_action("dodge", dir, false)
		# 压到「闪避时长 − DODGE_SETTLE」内播完：提前收尾停在末帧（直立），
		# 切回待机/移动时姿态连续，杜绝与闪避结束的竞态重播。
		speed_scale = _clip_seconds(clip) / maxf(player.dodge_duration - DODGE_SETTLE, 0.05)
		return
	_update_locomotion()

## 把面向向量量化到 8 方向之一：atan2(x,z) 每 45° 一档。
## 入参是世界方向，先经 player.view_dir() 转回"以机位为北"的视角系再量化——
## 动作跟按键走：W 永远播背面（往画面深处走），不管机位转到世界哪个朝向。
func _to_dir_name(direction: Vector3) -> String:
	var view: Vector3 = player.view_dir(direction)
	var index := int(round(atan2(view.x, view.z) / (PI / 4.0))) % 8
	if index < 0:
		index += 8
	return DIR_NAMES[index]

## 该动作 + 该朝向下应使用的 pixel_size：斜向补偿表为空，恒为基准值。
## 动作素材的尺寸校正在图集中完成；运行时 pixel_size 始终使用基准值，不缩放角色节点。
## 斜向补偿表为空，所有朝向都使用同一像素尺寸。
func _pixel_size_for(action: String, direction: String) -> float:
	if direction in DIAGONAL_DIRS:
		return BASE_PIXEL_SIZE * float(DIAGONAL_SCALE.get(action, 1.0))
	return BASE_PIXEL_SIZE

## 剪辑实际时长：逐帧时长求和 / 帧率。逐帧时长（frame duration）的单位是"1/帧率 的节拍数"
## （实测确认，默认 1.0 → 均匀剪辑等价于 帧数/帧率）。待机用的是逐帧时长（站立帧停更久），
## 动作压缩与步频同步都要按实际时长算，否则脚底打滑 / 展示时长不足。
func _clip_seconds(clip: StringName) -> float:
	if sprite_frames == null or not sprite_frames.has_animation(clip):
		return CLIP_LEN
	var fps := sprite_frames.get_animation_speed(clip)
	var n := sprite_frames.get_frame_count(clip)
	if fps <= 0.0 or n <= 0:
		return CLIP_LEN
	var ticks := 0.0
	for i in n:
		ticks += sprite_frames.get_frame_duration(clip, i)
	if ticks > 0.0:
		return ticks / fps
	return float(n) / fps

## 片段名解析：动作缺失时退回待机，避免 play() 拿到不存在的动画而卡住上一帧。
## （新版图集没有 guard，傲歌的防御姿态因此退回待机。）
func _resolve_action(action: String, direction: String) -> String:
	if sprite_frames != null and sprite_frames.has_animation(action + "_" + direction):
		return action
	return "idle"

## offset 由当前帧的区域高度推出：锚点恒在「区域底边往上 GROUND_SLACK」。
## 攻击帧 208x176、其余 192x160，所以必须逐动画算；192x160 时正好等于 BASE_OFFSET。
func _sync_offset() -> void:
	if sprite_frames == null or not sprite_frames.has_animation(animation):
		offset = BASE_OFFSET
		return
	var tex := sprite_frames.get_frame_texture(animation, 0)
	if tex is AtlasTexture:
		var h: float = (tex as AtlasTexture).region.size.y
		offset = Vector2(0, h / 2.0 - GROUND_SLACK)
	else:
		offset = BASE_OFFSET

## 播放某个动作动画；loop 为 true 时若同一片段已在播放则不再重启。
func _play_action(action: String, direction: Vector3, loop: bool) -> void:
	display_direction = _to_dir_name(direction)
	action = _resolve_action(action, display_direction)
	var clip := StringName(action + "_" + display_direction)
	pixel_size = _pixel_size_for(action, display_direction)
	set_flip_for(action, display_direction)
	speed_scale = 1.0
	if animation == clip and is_playing():
		return
	play(clip)
	_sync_offset()

## 镜像：新版图集 8 向都是真实绘制，MIRRORED_DIRS 为空表 → 始终不镜像。
func set_flip_for(_action: String, direction: String) -> void:
	flip_h = direction in MIRRORED_DIRS

func _update_locomotion() -> void:
	display_direction = _to_dir_name(player.facing)
	var moving: bool = player.input_dir.length_squared() > 0.001
	var action: String = LOCOMOTION_CLIP if moving else "idle"
	action = _resolve_action(action, display_direction)
	var clip: StringName = StringName(action + "_" + display_direction)
	pixel_size = _pixel_size_for(action, display_direction)
	flip_h = display_direction in MIRRORED_DIRS
	# 步频跟随实际移速：一圈耗时 = CLIP_LEN / speed_scale，令其等于"步幅 / 移速"，
	# 即 speed_scale = 移速 × CLIP_LEN / 步幅。减速（如攻击中）时步频自动放慢。
	# 待机是呼吸循环，不参与同步。移动一律用 run 自己的步幅，否则脚底打滑。
	# RUN_CADENCE_FACTOR 只把动画播慢一档，移速与步幅同步本身不动。
	if moving:
		var ground_speed := Vector2(player.velocity.x, player.velocity.z).length()
		speed_scale = clampf(ground_speed * _clip_seconds(clip) / RUN_STRIDE_PER_CYCLE * RUN_CADENCE_FACTOR,
			WALK_SPEED_SCALE.x, WALK_SPEED_SCALE.y)
	else:
		speed_scale = 1.0
	if animation != clip or not is_playing():
		play(clip)
	_sync_offset()

func _on_attacked(stage: int) -> void:
	var action: String = player.current_attack_animation if stage == 0 else COMBO_CLIPS[clampi(stage, 0, COMBO_CLIPS.size() - 1)]
	_play_combat_action(action)

func _on_skill_animation_requested(action: String) -> void:
	_play_combat_action(action)

func _play_combat_action(action: String) -> void:
	display_direction = _to_dir_name(player.facing)
	attack_time_left = player.attack_cd
	action = _resolve_action(action, display_direction)
	var clip := StringName(action + "_" + display_direction)
	pixel_size = _pixel_size_for(action, display_direction)
	set_flip_for(action, display_direction)
	speed_scale = _clip_seconds(clip) / maxf(player.attack_cd, 0.01)
	stop()
	play(clip)
	_sync_offset()

## 直踢（K 键）：动画时长按 kick 冷却压缩，与攻击同优先级（攻击 > 受击 > …）。
func _on_kicked() -> void:
	display_direction = _to_dir_name(player.facing)
	attack_time_left = maxf(player.attack_cd, 0.35)
	var action: String = _resolve_action("kick", display_direction)
	var clip := StringName(action + "_" + display_direction)
	pixel_size = _pixel_size_for(action, display_direction)
	set_flip_for(action, display_direction)
	speed_scale = _clip_seconds(clip) / maxf(player.attack_cd, 0.01)
	stop()
	play(clip)
	_sync_offset()

func _on_hit() -> void:
	hit_timer = HIT_TIME  # 受击动画展示时长

func _on_guarded() -> void:
	guard_timer = 0.35
	# 新版图集未画格挡：_resolve_action 会退回待机；将来补了 guard 图集即自动生效。
	_play_action("guard", player.facing, false)
	speed_scale = _clip_seconds(animation) / guard_timer

func reset_visual() -> void:
	attack_time_left = 0.0
	hit_timer = 0.0
	guard_timer = 0.0
	_update_locomotion()
