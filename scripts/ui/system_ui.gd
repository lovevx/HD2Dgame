class_name SystemUI
## 系统面板设计语言：石墨暗底 + 暖金金属边 + 冰蓝水晶交互高亮。
## 用法：面板 StyleBox 走 card()/sub()/slot()，按钮走 style_button()，边框装饰走 decor()。

const SCREEN_BG := Color("3a4045")   # 石板灰底色（关卡选择等菜单）
const BG := Color("171d24")          # 面板主底
const BG_BLOCK := Color("222a32")    # 分块底板
const BG_TRACK := Color("0c1117")    # 进度条轨道
const ACCENT := Color("e6b448")      # 暖金主交互色
const ACCENT_DIM := Color("79551f")  # 暗金
const CRYSTAL := Color("53d9ff")     # 冰蓝水晶高亮
const BORDER := Color("b58b43")      # 金属描边
const BORDER_SOFT := Color(0.68, 0.53, 0.31, 0.62)
const TEXT := Color("f4efe4")        # 暖白正文
const TEXT_DIM := Color("b6ad9b")    # 柔和说明文字
const GOLD := Color("ffda68")        # 标题与奖励金色
const RADIUS := 6                    # 轻微倒角，保留利落轮廓

static func flat(bg: Color, border: Color, rw: int = 2, radius: int = RADIUS, margin: int = 18) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(rw)
	st.set_corner_radius_all(radius)
	st.set_content_margin_all(margin)
	return st

## 主面板（卡片）：近黑石墨底 + 2px 暖金描边 + 柔和落影。
static func card() -> StyleBoxFlat:
	var st := flat(Color(BG, 0.97), Color(BORDER, 0.72), 2, RADIUS, 26)
	st.shadow_size = 12
	st.shadow_color = Color(0.0, 0.0, 0.0, 0.48)
	st.shadow_offset = Vector2(0, 5)
	return st

## 分块底衬（角色面板左/右大块）：更深、细线。
static func sub() -> StyleBoxFlat:
	return flat(Color(BG_BLOCK, 0.92), Color(BORDER_SOFT, 0.7), 1, RADIUS, 14)

## 格子（装备槽 / 背包格 / 商品格）：实底 + 2px 边。
static func slot() -> StyleBoxFlat:
	return flat(Color("121820", 0.98), Color(BORDER_SOFT, 0.88), 2, RADIUS, 4)

## 进度条轨道（带描边）与填充。
static func track() -> StyleBoxFlat:
	return flat(Color(BG_TRACK, 0.98), Color(BORDER, 0.42), 1, RADIUS, 0)

static func fill(col: Color) -> StyleBoxFlat:
	return flat(col, Color(0, 0, 0, 0), 0, RADIUS, 0)

## 按钮状态：金色响应鼠标，冰蓝提示键盘焦点。
static func style_button(btn: Button) -> void:
	var base := Color(BG_BLOCK)
	var hover := Color("303943")
	var down := Color("11171d")
	btn.add_theme_stylebox_override("normal", flat(base, Color(BORDER, 0.72), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("hover", flat(hover, Color(GOLD, 0.98), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("pressed", flat(down, Color(ACCENT, 0.98), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("focus", flat(hover, Color(CRYSTAL, 0.96), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("disabled", flat(Color(BG_BLOCK).darkened(0.3), Color(BORDER, 0.28), 2, RADIUS, 14))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", GOLD)
	btn.add_theme_color_override("font_pressed_color", Color("fff0bc"))
	btn.add_theme_color_override("font_focus_color", Color("dff8ff"))
	btn.add_theme_color_override("font_disabled_color", Color(TEXT_DIM, 0.55))

## 当前页签保持金色填充，让分页位置清楚可见。
static func style_selected_button(btn: Button) -> void:
	var selected := flat(Color(ACCENT_DIM, 0.58), Color(GOLD, 0.98), 2, RADIUS, 14)
	btn.add_theme_stylebox_override("normal", selected)
	btn.add_theme_stylebox_override("hover", flat(Color(ACCENT_DIM, 0.82), Color(GOLD, 1.0), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("pressed", flat(Color(ACCENT_DIM, 0.38), Color(GOLD, 0.9), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("focus", flat(Color(ACCENT_DIM, 0.82), Color(CRYSTAL, 0.98), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("disabled", flat(Color(ACCENT_DIM, 0.72), Color(GOLD, 0.98), 2, RADIUS, 14))
	btn.add_theme_color_override("font_color", GOLD)
	btn.add_theme_color_override("font_hover_color", Color("fff0bc"))
	btn.add_theme_color_override("font_focus_color", Color("dff8ff"))
	btn.add_theme_color_override("font_disabled_color", GOLD)

## 四角金属装饰点 + 内发丝描边：任意 PanelContainer 扣上即得框架装饰。
static func decor(parent: Control, rivet: Color = ACCENT) -> Control:
	var d := Control.new()
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.draw.connect(func():
		var s := d.size
		var inset := 10.0
		var px := 3.0  # 像素点边长
		for c: Vector2 in [Vector2(inset, inset), Vector2(s.x - inset, inset), Vector2(inset, s.y - inset), Vector2(s.x - inset, s.y - inset)]:
			d.draw_rect(Rect2(c.x - px / 2, c.y - px / 2, px, px), Color(rivet, 0.95))
			d.draw_rect(Rect2(c.x - px / 2 - 3, c.y - px / 2 - 3, px, px), Color(rivet, 0.22))
		d.draw_rect(Rect2(3, 3, s.x - 6, s.y - 6), Color(BORDER, 0.2), false, 1.0))
	parent.add_child(d)
	return d

## 滚动条：长内容（任务详情、按键表）会超出面板，使用金属轨道和亮色滑块提示可继续滚动。
static func style_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 12
	bar.add_theme_stylebox_override("scroll", track())
	bar.add_theme_stylebox_override("scroll_focus", track())
	bar.add_theme_stylebox_override("grabber", flat(Color(BORDER, 0.75), Color(0, 0, 0, 0), 0, RADIUS, 0))
	bar.add_theme_stylebox_override("grabber_highlight", flat(ACCENT, Color(0, 0, 0, 0), 0, RADIUS, 0))
	bar.add_theme_stylebox_override("grabber_pressed", flat(ACCENT, Color(0, 0, 0, 0), 0, RADIUS, 0))

## 滑条（主音量 / 音效 / 镜头灵敏度）：自行绘制轨道和填充段，并生成金属方形拖块。
## Slider 用样式盒的最小高度作条厚；内容边距为 0 时只会画成 2px 细线，因此这里显式补上下边距。
static func style_slider(slider: Slider) -> void:
	slider.add_theme_stylebox_override("slider", bar(Color(BG_TRACK, 0.95), Color(BORDER, 0.45)))
	slider.add_theme_stylebox_override("grabber_area", bar(Color(ACCENT, 0.5), Color(0, 0, 0, 0)))
	slider.add_theme_stylebox_override("grabber_area_highlight", bar(Color(ACCENT, 0.75), Color(0, 0, 0, 0)))
	slider.add_theme_icon_override("grabber", pixel_block(12, 22, GOLD, ACCENT_DIM))
	slider.add_theme_icon_override("grabber_disabled", pixel_block(12, 22, GOLD, ACCENT_DIM))
	slider.add_theme_icon_override("grabber_highlight", pixel_block(12, 22, CRYSTAL, Color("dff8ff")))

## 滑条用的横条样式：1px 描边 + 8px 厚（border 1 + 上下内容边距 3）。
static func bar(bg: Color, border: Color, thickness := 8) -> StyleBoxFlat:
	var st := flat(bg, border, 1 if border.a > 0.0 else 0, RADIUS, 0)
	st.content_margin_top = maxi(0, thickness / 2 - 1)
	st.content_margin_bottom = maxi(0, thickness / 2 - 1)
	return st

## 生成硬边方形拖块：1px 描边色 + 实心填充色。
static func pixel_block(w: int, h: int, border: Color, body: Color) -> ImageTexture:
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var on_edge := x == 0 or y == 0 or x == w - 1 or y == h - 1
			image.set_pixel(x, y, border if on_edge else body)
	return ImageTexture.create_from_image(image)

## 状态徽记：左侧金色标记 + 文字。
static func chip(parent: Node, text: String, accent: Color = ACCENT) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", flat(Color(BG_BLOCK, 0.9), Color(BORDER, 0.5), 1, RADIUS, 6))
	tag.add_theme_constant_override("separation", 0)
	parent.add_child(tag)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	tag.add_child(row)
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(8, 8)
	row.add_child(dot)
	dot.draw.connect(func(): dot.draw_rect(Rect2(2, 2, 4, 4), accent))
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", TEXT)
	row.add_child(label)
	return tag
