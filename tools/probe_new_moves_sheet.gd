extends SceneTree
## 分析 assets/characters/black_swordsman/新版动作 三张 sheet 的网格结构：
## alpha 投影找空隙分界（列分段=帧、行分段=方向），导出缩略网格对照图到 .tmp_preview/new_moves/。
## 用法：godot --headless --path <proj> --script res://tools/probe_new_moves_sheet.gd

const SRC_DIR := "res://assets/characters/black_swordsman/新版动作/"
const OUT_DIR := "res://.tmp_preview/new_moves/"
const FILES := ["跑步动画.png", "闪避动画.png", "受击动画.png"]

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for file: String in FILES:
		var bytes := FileAccess.get_file_as_bytes(SRC_DIR + file)
		if bytes.is_empty():
			push_error("读不到 " + SRC_DIR + file)
			continue
		var img := Image.new()
		var err := img.load_png_from_buffer(bytes)
		if err != OK:
			push_error(file + " PNG 解码失败")
			continue
		_analyze(img, file)
	quit(0)

func _analyze(img: Image, file: String) -> void:
	var w := img.get_width()
	var h := img.get_height()
	print("== ", file, "  ", w, "x", h, "  格式 ", img.get_format())
	var data := img.get_data()
	var col_seg := _segments(_project(data, w, h, true))
	var row_seg := _segments(_project(data, w, h, false))
	print("列分段 %d 个:" % col_seg.size())
	for b: Vector2i in col_seg:
		print("  x %d-%d (宽 %d)" % [b.x, b.y, b.y - b.x + 1])
	print("行分段 %d 个:" % row_seg.size())
	for b: Vector2i in row_seg:
		print("  y %d-%d (高 %d)" % [b.x, b.y, b.y - b.x + 1])
	_export_grid(img, col_seg, row_seg, file)

## alpha 投影：vertical=true 按列统计（返回每 x 列是否有不透明像素），否则按行。
## 内层步长 4 采样 + 计满即停，千万级像素下秒级完成。
func _project(data: PackedByteArray, w: int, h: int, vertical: bool) -> PackedByteArray:
	var outer := w if vertical else h
	var inner := h if vertical else w
	var occupied := PackedByteArray()
	occupied.resize(outer)
	for o in outer:
		var i := 0
		while i < inner:
			var idx: int = (i * w + o) * 4 + 3 if vertical else (o * w + i) * 4 + 3
			if data[idx] > 8:
				occupied[o] = 1
				break
			i += 4
	return occupied

## 连续占用段；孤立 <5px 的段忽略（抗噪）。
func _segments(occupied: PackedByteArray) -> Array[Vector2i]:
	var segs: Array[Vector2i] = []
	var start := -1
	for i in occupied.size():
		if occupied[i] > 0 and start < 0:
			start = i
		elif occupied[i] == 0 and start >= 0:
			if i - start >= 5:
				segs.append(Vector2i(start, i - 1))
			start = -1
	if start >= 0:
		segs.append(Vector2i(start, occupied.size() - 1))
	return segs

## 行段×列段切块，等比缩进 80px 格子，拼总览图。
func _export_grid(img: Image, col_seg: Array[Vector2i], row_seg: Array[Vector2i], file: String) -> void:
	var cell := 80
	var out := Image.create(cell * col_seg.size(), cell * row_seg.size(), false, Image.FORMAT_RGBA8)
	out.fill(Color(0.09, 0.1, 0.12, 1.0))
	for r in row_seg.size():
		for c in col_seg.size():
			var rb: Vector2i = row_seg[r]
			var cb: Vector2i = col_seg[c]
			var crop := img.get_region(Rect2i(cb.x, rb.x, cb.y - cb.x + 1, rb.y - rb.x + 1))
			var s := minf(float(cell) / crop.get_width(), float(cell) / crop.get_height())
			crop.resize(maxi(1, int(crop.get_width() * s)), maxi(1, int(crop.get_height() * s)))
			out.blit_rect(crop, Rect2i(0, 0, crop.get_width(), crop.get_height()),
				Vector2i(c * cell + (cell - crop.get_width()) / 2, r * cell + (cell - crop.get_height()) / 2))
	var out_path := OUT_DIR + file.get_basename() + "_grid.png"
	var save_err := out.save_png(ProjectSettings.globalize_path(out_path))
	if save_err == OK:
		print("已导出 ", out_path, "  ", col_seg.size(), " 列 x ", row_seg.size(), " 行")
	else:
		print("导出失败 ", out_path)
