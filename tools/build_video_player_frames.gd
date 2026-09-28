extends SceneTree
## 把「最新版动作 sheet 抽出的 12 帧序列」接入游戏：生成 SpriteFrames。
##
## 来源：assets/characters/black_swordsman_video/<中文动作>_<方向>_12.png
##   —— 原有 8 个动作由 tools/extract_latest_12.py 切出；横斩、环断、刀芒为逐方向补入的动作帧。
##      所有输入均为每方向 12 帧，统一 224×192 格、本体约 104px、地面线 y=176。
##
## 输出：res://assets/characters/player_frames_video.tres
## 运行：godot --headless --path . --script res://tools/build_video_player_frames.gd

const VIDEO_DIR := "res://assets/characters/black_swordsman_video"
const OUT_PATH := "res://assets/characters/player_frames_video.tres"

const DIRS: Array[String] = [
	"down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right",
]
## 中文动作名 → 英文 clip 前缀
const ACTION_MAP := {
	"待机": "idle",
	"行走": "walk",
	"跑步": "run",
	"攻击": "attack",
	"横斩": "attack_horizontal",
	"环断": "ring_break",
	"刀芒": "sword_wave",
	"直踹": "kick",
	"受击": "hit",
	"闪避": "dodge",
	"死亡": "death",
}
const LOOPING: Array[String] = ["idle", "walk", "run"]
## 帧率：idle 用 4fps 作基准（逐帧时长按运动量分配，站立帧停更久）；其余 15fps。
const FPS_DEFAULT := 15.0
const FPS_BY_ACTION := {"idle": 4.0, "death": 12.0}
## 待机整圈时长（秒）：站立/呼吸都慢，10fps 时抬头动作每 1.2 秒重复一次太频繁（用户反馈）。
## 与 validate_player_anim 的 IDLE_CYCLE_SECONDS 同口径。
const IDLE_CYCLE_SECONDS := 5.25
const IDLE_MOTION_FLOOR := 0.15
const IDLE_MAX_TICKS := 6.0
## 全部动作统一：12 帧 @ 6×2 格，格 224×192（地面线在格底往上 16px）
const FILE_SUFFIX := "_12"
const COLS := 6
const ROWS := 2
const CELL := Vector2i(224, 192)

var idle_report := ""


func _init() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var summary: Array[String] = []

	# ---- 12 帧序列（11 动作 × 8 方向）----
	for cn in ACTION_MAP.keys():
		var action: String = ACTION_MAP[cn]
		for dir in DIRS:
			var path := "%s/%s_%s%s.png" % [VIDEO_DIR, cn, dir, FILE_SUFFIX]
			var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
			if tex == null:
				push_warning("缺少 %s" % path)
				continue
			var anim := "%s_%s" % [action, dir]
			_add_clip(frames, anim, tex, COLS, ROWS, CELL, action, summary)

	var err := ResourceSaver.save(frames, OUT_PATH)
	if err != OK:
		push_error("保存失败 err=%d" % err)
		quit(1)
		return
	print("已生成 %d 个动画 → %s" % [frames.get_animation_names().size(), OUT_PATH])
	for line in summary:
		print(line)
	if idle_report != "":
		print(idle_report)
	quit(0)


## 把一张图集（cols × rows 格）切成一集动画。
## 逐帧时长只能在 add_frame 时给（SpriteFrames 没有 set_frame_duration），
## 所以先算好每格的时长再落帧：idle 按运动量分配（站立帧停更久），其余恒 1.0 节拍。
func _add_clip(frames: SpriteFrames, anim: String, tex: Texture2D, cols: int, rows: int,
		cell: Vector2i, action: String, summary: Array[String]) -> void:
	frames.add_animation(anim)
	var fps: float = float(FPS_BY_ACTION.get(action, FPS_DEFAULT))
	frames.set_animation_speed(anim, fps)
	frames.set_animation_loop(anim, action in LOOPING)
	var n := cols * rows
	var atlas_img: Image = tex.get_image()
	# ---- 逐格取图（保留原始格号，落帧要用它算 region）----
	var cells_img: Array[Image] = []
	for i in n:
		cells_img.append(atlas_img.get_region(
			Rect2i((i % cols) * cell.x, (i / cols) * cell.y, cell.x, cell.y)))
	var m := cells_img.size()
	var durations: Array[float] = []
	if action == "idle" and m >= 3:
		var lums: Array[Image] = []
		for img in cells_img:
			var l: Image = img.duplicate()
			l.convert(Image.FORMAT_L8)                 # duplicate 后转换，别改到原图
			l.resize(48, 40, Image.INTERPOLATE_BILINEAR)
			lums.append(l)
		durations = _idle_durations(lums, fps)
		if anim.ends_with("down"):
			var ticks := ""
			var total := 0.0
			for d in durations:
				ticks += "%.0f " % (d * 1000.0 / fps)
				total += d
			idle_report = "idle 逐帧时长(ms, %s fps): %s| 合计 %.2f s" % [str(fps), ticks, total / fps]
	else:
		for i in m:
			durations.append(1.0)
	for i in m:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((i % cols) * cell.x, (i / cols) * cell.y, cell.x, cell.y)
		at.filter_clip = true
		frames.add_frame(anim, at, durations[i])
	summary.append("  %-14s %d 帧  格 %dx%d  %s" % [anim, frames.get_frame_count(anim),
		cell.x, cell.y, "循环" if action in LOOPING else "一次性"])


func _idle_durations(lums: Array[Image], fps: float) -> Array[float]:
	var n := lums.size()
	var weights: Array[float] = []
	var total := 0.0
	for i in n:
		var a: Image = lums[i]
		var b: Image = lums[(i + 1) % n]
		var motion := _image_diff(a, b)
		var w := 1.0 / (motion + IDLE_MOTION_FLOOR)
		weights.append(w)
		total += w
	var out: Array[float] = []
	for w in weights:
		out.append(clampf(IDLE_CYCLE_SECONDS * fps * w / maxf(total, 0.0001), 0.5, IDLE_MAX_TICKS))
	# 上下限夹取会改变总时长（整圈被压短）→ 按当前总和再归一一次，保证整圈正好 IDLE_CYCLE_SECONDS。
	var ticks := 0.0
	for d in out:
		ticks += d
	var k := IDLE_CYCLE_SECONDS * fps / maxf(ticks, 0.0001)
	for i in out.size():
		out[i] = clampf(out[i] * k, 0.5, IDLE_MAX_TICKS)
	return out


func _image_diff(a: Image, b: Image) -> float:
	if a == null or b == null:
		return 0.0
	var da := a.get_data()
	var db := b.get_data()
	if da.is_empty() or da.size() != db.size():
		return 0.0
	var total := 0
	for i in da.size():
		total += absi(int(da[i]) - int(db[i]))
	return float(total) / float(da.size())
