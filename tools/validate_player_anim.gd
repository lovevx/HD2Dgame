extends SceneTree
## 玩家动画资源回归校验（2026-09-20 动画优化配套）。
##
## 三类历史问题，今后重打包/换素材后跑一遍即可防回退：
##   1. 斜向 idle/walk/run 不循环（旧 tres 手工产物只有 4 个正交方向 loop，
##      斜向移动每 0.8s 定格重启一次，肉眼看是周期性卡顿）；
##   2. 死亡动画斜向 15fps 与正交 12fps 不一致；
##   3. 图集坏帧（本体消失只剩刀尖）—— 由 tools/diagnose_anim_sheets.py 在
##      PNG 层把关，这里校验 SpriteFrames 层的结构。
##
## 运行：godot --headless --path . --script res://tools/validate_player_anim.gd

const FRAMES_PATH := "res://assets/characters/player_frames_video.tres"
const VISUAL_SCRIPT := "res://scripts/player/player_visual.gd"
const ACTIONS: Array[String] = ["attack", "death", "dodge", "hit", "idle", "kick", "run", "walk"]
const LOOP_ACTIONS: Array[String] = ["idle", "walk", "run"]
const DIRS: Array[String] = [
	"down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right",
]
## 待机放慢到 4fps（整圈 3 秒）：10fps 时抬头动作每 1.2 秒重复一次，太频繁（用户反馈）。
const FPS_IDLE := 4.0
## 待机逐帧时长：站立（安静）帧停更久，整圈约 5.3 秒（build_video_player_frames 按运动量分配）。
const IDLE_CYCLE_SECONDS := 5.25
const FPS_DEATH := 12.0
const FPS_DEFAULT := 15.0
## 2026-09-21 起全部 8 个动作都来自最新版 sheet 按块切出的 12 帧序列（6×2 格）。
const FRAMES_PER_ANIM := 12
## 格子尺寸：全部动作统一 224×192（给挥砍刀光弧/悬垂尾留余量，地面线在格底往上 16px）。
const CELL := Vector2i(224, 192)

var failures: Array[String] = []

func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)

func _init() -> void:
	var frames: SpriteFrames = load(FRAMES_PATH)
	if frames == null:
		push_error("加载失败: " + FRAMES_PATH)
		quit(1)
		return

	check(frames.get_animation_names().size() == ACTIONS.size() * DIRS.size(),
		"动画总数应为 %d，实际 %d" % [ACTIONS.size() * DIRS.size(), frames.get_animation_names().size()])

	for action in ACTIONS:
		for dir in DIRS:
			var anim := "%s_%s" % [action, dir]
			if not frames.has_animation(anim):
				failures.append("缺少动画 " + anim)
				continue
			var want_loop: bool = action in LOOP_ACTIONS
			check(frames.get_animation_loop(anim) == want_loop,
				"%s loop 应为 %s" % [anim, str(want_loop)])
			var want_fps := FPS_DEFAULT
			if action == "idle":
				want_fps = FPS_IDLE
			elif action == "death":
				want_fps = FPS_DEATH
			check(absf(frames.get_animation_speed(anim) - want_fps) < 0.01,
				"%s 帧率应为 %.0f，实际 %.1f" % [anim, want_fps, frames.get_animation_speed(anim)])
			var want_frames: int = FRAMES_PER_ANIM
			check(frames.get_frame_count(anim) == want_frames,
				"%s 帧数应为 %d，实际 %d" % [anim, want_frames, frames.get_frame_count(anim)])
			# 循环动作的相邻帧不得是同一块图源区域：复制格留在剪辑里会让循环定格一次（跑步踩过）
			for i in range(1, frames.get_frame_count(anim)):
				var prev_tex: Texture2D = frames.get_frame_texture(anim, i - 1)
				var cur_tex: Texture2D = frames.get_frame_texture(anim, i)
				if prev_tex is AtlasTexture and cur_tex is AtlasTexture:
					var pa := prev_tex as AtlasTexture
					var ca := cur_tex as AtlasTexture
					check(not want_loop or not (pa.atlas == ca.atlas and pa.region == ca.region),
						"%s 第 %d/%d 帧与前一帧完全相同（循环会定格）" % [anim, i, frames.get_frame_count(anim)])
			# 待机走逐帧时长：必须非均匀（站立帧停更久），整圈 ≈ IDLE_CYCLE_SECONDS
			if action == "idle":
				var ticks := 0.0
				var uniform := true
				var first_dur: float = frames.get_frame_duration(anim, 0)
				for i in frames.get_frame_count(anim):
					var dur: float = frames.get_frame_duration(anim, i)
					ticks += dur
					if absf(dur - first_dur) > 0.01:
						uniform = false
				check(not uniform, "%s 待机应使用逐帧时长（站立帧停更久），不能是均匀时长" % anim)
				var seconds := ticks / frames.get_animation_speed(anim)
				check(absf(seconds - IDLE_CYCLE_SECONDS) < 0.3,
					"%s 待机整圈应约 %.1f 秒，实际 %.2f 秒" % [anim, IDLE_CYCLE_SECONDS, seconds])
			var tex := frames.get_frame_texture(anim, 0)
			var cell := Vector2i.ZERO
			if tex is AtlasTexture:
				cell = Vector2i((tex as AtlasTexture).region.size)
			var want_cell: Vector2i = CELL
			check(cell == want_cell,
				"%s 格子尺寸应为 %s，实际 %s" % [anim, str(want_cell), str(cell)])

	# 播放层常量抽查：受击时长（0.22s 频闪问题）与移动循环。
	var visual: GDScript = load(VISUAL_SCRIPT)
	check(visual != null and visual.HIT_TIME == 0.35,
		"player_visual.HIT_TIME 应为 0.35（0.22s 会把 12 帧压成 55fps 频闪）")
	check(visual != null and visual.LOCOMOTION_CLIP == StringName("run"),
		"player_visual.LOCOMOTION_CLIP 应为 run（常驻移动模式即跑步）")

	if failures.is_empty():
		print("PASS: 动画资源校验全部通过（%d 个动画）" % (ACTIONS.size() * DIRS.size()))
		quit(0)
	else:
		for f in failures:
			push_error("FAIL: " + f)
		print("FAIL: %d 项不通过" % failures.size())
		quit(1)
