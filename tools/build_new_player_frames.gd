extends SceneTree
## 把 assets/characters/black_swordsman_new/ 下的图集打包成 SpriteFrames 资源。
##
## 图集口径（由 tools/package_new_moves.py 产出）：
##   文件名 <动作>_<方向>.png，每个文件 6 列 × 2 行 = 12 帧，
##   锚点恒在 (格宽/2, 格高-16)（16 = 地面留白），格宽/格高随动作不同。
##
## 运行：godot --headless --path . --script res://tools/build_new_player_frames.gd
## 产出：res://assets/characters/black_swordsman_new/player_frames_new.tres

const SRC_DIR := "res://assets/characters/black_swordsman_new"
const OUT_PATH := "res://assets/characters/black_swordsman_new/player_frames_new.tres"
const COLS := 6
const ROWS := 2
## 循环播放的动作（其余为一次性，播完停最后一帧）
const LOOPING := ["idle", "walk", "run"]
## 12 帧的播放帧率：15fps → 0.8s 一圈（与旧图集 8 帧@10fps 同长，但更顺）
const FPS_DEFAULT := 15.0
## idle 放慢到 4fps：整圈 3 秒。10fps 时一圈仅 1.2 秒，抬头/换姿势的动作每 1.2 秒
## 就来一次，看着像焦躁地反复动（用户反馈"站个几秒才会抬头才对"）。调更慢改这一个数。
const FPS_BY_ACTION := {"idle": 4.0, "death": 12.0}
const GROUND_SLACK := 16
## 待机一圈的目标时长（秒）与"安静帧加权下限"。
## 逐帧时长按运动量倒数分配：运动量小的帧停得久（站着的感觉），动作帧保持原速。
## 单位语义（实测 tools/probe_frame_duration.gd）：某帧秒数 = duration / 动画fps，
## 所以 duration 是「多少个 1/fps 的节拍」，不是秒。
## 2026-09-20 二调（用户"站立帧还要久一点"）：整圈 4→5 秒，FLOOR 0.35→0.15 拉大静/动对比，
## 单帧上限 4→6 节拍（fps=4 时 1.5 秒）。
const IDLE_CYCLE_SECONDS := 5.0
const IDLE_MOTION_FLOOR := 0.15
const IDLE_MAX_TICKS := 6.0
## 已知动作前缀：文件名 = <动作>_<方向>，方向可能含下划线（down_left 等），
## 因此必须按前缀匹配切分，不能用 rfind("_")——那会把 idle_down_left 切成
## 「idle_down + left」，导致所有斜向动画匹配不到循环白名单与专用帧率。
const KNOWN_ACTIONS: Array[String] = [
	"attack", "death", "dodge", "hit", "idle", "kick", "run", "walk",
]

## 待机逐帧时长的报告行（供打包日志核对）。
var idle_report := ""

func _init() -> void:
	var dir := DirAccess.open(SRC_DIR)
	if dir == null:
		push_error("找不到目录 " + SRC_DIR)
		quit(1)
		return
	var files: Array[String] = []
	for f in dir.get_files():
		if f.ends_with(".png"):
			files.append(f)
	files.sort()
	if files.is_empty():
		push_error("目录里没有图集 PNG")
		quit(1)
		return

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var anim_names: Array[String] = []
	var cells := 0
	var skipped_total := 0

	for f in files:
		var base := f.get_basename()                 # 去掉 .png
		var action := ""
		var dname := ""
		for a in KNOWN_ACTIONS:
			if base.begins_with(a + "_"):
				action = a
				dname = base.substr(a.length() + 1)
				break
		if action == "" or dname == "":
			push_warning("跳过命名不合规的文件：" + f)
			continue
		var tex: Texture2D = load(SRC_DIR + "/" + f)
		if tex == null:
			push_warning("加载失败：" + f)
			continue
		var fw := int(tex.get_width() / COLS)
		var fh := int(tex.get_height() / ROWS)
		var anim := "%s_%s" % [action, dname]
		frames.add_animation(anim)
		frames.set_animation_speed(anim, float(FPS_BY_ACTION.get(action, FPS_DEFAULT)))
		frames.set_animation_loop(anim, action in LOOPING)
		var atlas_img: Image = tex.get_image()
		var prev_data := PackedByteArray()
		var skipped := 0
		var kept_regions: Array[Rect2] = []
		var kept_lums: Array[Image] = []
		for i in COLS * ROWS:
			var col := i % COLS
			var row := i / COLS
			var region := Rect2(col * fw, row * fh, fw, fh)
			# 跳过"补数复制格"：源图姿势不足 12 个时，打包脚本会复制某一帧填满格子，
			# 复制格与前一格**像素完全相同**（格子区域当然不同，要比内容）。
			# 留在剪辑里就是循环中的一次定格（跑步源图第三块每方向只有 3 个姿势，踩过）。
			var cell_data := PackedByteArray()
			var cell_lum: Image = null
			if atlas_img != null and not atlas_img.is_empty():
				var cell_img := atlas_img.get_region(Rect2i(col * fw, row * fh, fw, fh))
				cell_data = cell_img.get_data()
				if action == "idle":
					# 降采样到 48x40 再算帧间运动量：逐帧时长只要运动趋势，不需要全分辨率。
					# 注意 Image.convert() 是原地修改、不返回值。
					cell_lum = cell_img
					cell_lum.convert(Image.FORMAT_L8)
					cell_lum.resize(48, 40, Image.INTERPOLATE_BILINEAR)
			if i > 0 and not cell_data.is_empty() and cell_data == prev_data:
				skipped += 1
				continue
			kept_regions.append(region)
			kept_lums.append(cell_lum)
			prev_data = cell_data
		var fps: float = float(FPS_BY_ACTION.get(action, FPS_DEFAULT))
		var durations: Array[float] = []
		if action == "idle" and kept_lums.size() >= 3:
			durations = _idle_durations(kept_lums, fps)
		else:
			for _k in kept_regions.size():
				durations.append(1.0)
		for k in kept_regions.size():
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = kept_regions[k]
			at.filter_clip = true                    # 必须：否则会溢出到相邻格
			frames.add_frame(anim, at, durations[k])
		if action == "idle" and dname == "down":
			var ticks := ""
			for d in durations:
				ticks += "%.0f " % (d * 1000.0 / fps)
			idle_report = "idle 逐帧时长(ms, %s fps): %s| 合计 %.2f s" % [str(fps), ticks,
				_sum(durations) / fps]
		if skipped > 0:
			skipped_total += skipped
		cells += 1
		anim_names.append("%s(%dx%d, %d帧)" % [anim, fw, fh, COLS * ROWS - skipped])

	var err := ResourceSaver.save(frames, OUT_PATH)
	if err != OK:
		push_error("保存失败 err=%d" % err)
		quit(1)
		return
	print("已打包 %d 个动画 → %s" % [cells, OUT_PATH])
	print("跳过重复格 %d 个（源姿势不足的动作剪辑更短，例如 run 11 帧）" % skipped_total)
	if idle_report != "":
		print(idle_report)
	print("动画列表：", ", ".join(anim_names))
	quit(0)

## 待机的逐帧时长（节拍数，见 IDLE_CYCLE_SECONDS 的单位说明）：
## 权重 = 1/(帧间运动量 + FLOOR)，安静的帧权重高（停得久），动作帧权重低（保持原速）；
## 再整体缩放到 IDLE_CYCLE_SECONDS，并夹在 [0.5, 4.0] 节拍内防止极端值。
func _idle_durations(lums: Array[Image], fps: float) -> Array[float]:
	var n := lums.size()
	var weights: Array[float] = []
	var total := 0.0
	for i in n:
		var a: Image = lums[i]
		var b: Image = lums[(i + 1) % n]
		var motion := _image_diff(a, b) if a != null and b != null else 0.0
		var w := 1.0 / (motion + IDLE_MOTION_FLOOR)
		weights.append(w)
		total += w
	var out: Array[float] = []
	for w in weights:
		out.append(clampf(IDLE_CYCLE_SECONDS * fps * w / maxf(total, 0.0001), 0.5, IDLE_MAX_TICKS))
	return out

## 两张 L8 图的平均绝对差（0~255）。
func _image_diff(a: Image, b: Image) -> float:
	var da := a.get_data()
	var db := b.get_data()
	if da.is_empty() or da.size() != db.size():
		return 0.0
	var total := 0
	for i in da.size():
		total += absi(int(da[i]) - int(db[i]))
	return float(total) / float(da.size())

func _sum(values: Array[float]) -> float:
	var s := 0.0
	for v in values:
		s += v
	return s
