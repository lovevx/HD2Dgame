class_name SystemUI
## 系统面板设计语言（像素风 16-bit JRPG）：深蓝黑底 + 银灰硬边边框 + 幽蓝高亮 + 零圆角。
## 设计规范（docs 提示词通用前缀）：面板深蓝黑、边框银灰 #8a9bb5、高亮幽蓝 #4da6ff、
## 主文字白色、说明灰蓝；方块直角、无圆角无渐变无发光外描边；角落小像素装饰点。
## 用法：面板 StyleBox 走 card()/sub()/slot()，按钮走 style_button()，边框装饰走 decor()。

const BG := Color("1a2238")          # 面板主底（提示词深蓝黑）
const BG_BLOCK := Color("121a2c")    # 分块底板（略深一档）
const BG_TRACK := Color("0d1424")    # 进度条轨道
const ACCENT := Color("4da6ff")      # 高亮幽蓝（提示词）
const ACCENT_DIM := Color("2a5f9e")  # 幽蓝暗阶
const BORDER := Color("8a9bb5")      # 银灰边框（提示词）
const BORDER_SOFT := Color(0.54, 0.61, 0.71, 0.5)
const TEXT := Color("f2f5f9")        # 主文字白色（提示词）
const TEXT_DIM := Color("8fa0b5")    # 说明灰蓝（提示词）
const GOLD := Color("ebd6a2")        # 金色 = 高价值语言，保留
const RADIUS := 0                    # 方块直角：全局零圆角

static func flat(bg: Color, border: Color, rw: int = 2, radius: int = RADIUS, margin: int = 18) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(rw)
	st.set_corner_radius_all(radius)
	st.set_content_margin_all(margin)
	return st

## 主面板（卡片）：深底 + 2px 银灰描边 + 零圆角 + 大内边距。
static func card() -> StyleBoxFlat:
	return flat(Color(BG, 0.93), Color(BORDER, 0.6), 2, RADIUS, 26)

## 分块底衬（角色面板左/右大块）：更深、细线。
static func sub() -> StyleBoxFlat:
	return flat(Color(BG_BLOCK, 0.6), Color(BORDER_SOFT, 0.5), 1, RADIUS, 14)

## 格子（装备槽 / 背包格 / 商品格）：实底 + 2px 边。
static func slot() -> StyleBoxFlat:
	return flat(Color(BG_BLOCK, 0.95), Color(BORDER_SOFT, 0.8), 2, RADIUS, 4)

## 进度条轨道（带描边）与填充。
static func track() -> StyleBoxFlat:
	return flat(Color(BG_TRACK, 0.95), Color(BORDER, 0.35), 1, RADIUS, 0)

static func fill(col: Color) -> StyleBoxFlat:
	return flat(col, Color(0, 0, 0, 0), 0, RADIUS, 0)

## 按钮四态：普通 / 悬停 / 按下 / 聚焦 / 禁用，幽蓝描边在悬停时点亮。
static func style_button(btn: Button) -> void:
	var base := Color(BG_BLOCK)
	var hover := Color(BG_BLOCK).lightened(0.13)
	var down := Color(BG_BLOCK).darkened(0.16)
	btn.add_theme_stylebox_override("normal", flat(base, Color(BORDER, 0.6), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("hover", flat(hover, Color(ACCENT, 0.85), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("pressed", flat(down, Color(ACCENT, 0.95), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("focus", flat(hover, Color(ACCENT, 0.85), 2, RADIUS, 14))
	btn.add_theme_stylebox_override("disabled", flat(Color(BG_BLOCK).darkened(0.28), Color(BORDER, 0.22), 2, RADIUS, 14))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color("dceeff"))
	btn.add_theme_color_override("font_pressed_color", Color("b9dcff"))
	btn.add_theme_color_override("font_focus_color", Color("dceeff"))
	btn.add_theme_color_override("font_disabled_color", Color(TEXT_DIM, 0.55))

## 四角像素装饰点 + 内发丝描边：任意 PanelContainer 扣上即得「框架节点」装饰。
## 装饰点用小方块（像素风），而非圆形铆钉。
static func decor(parent: Control, rivet: Color = ACCENT) -> Control:
	var d := Control.new()
	d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.draw.connect(func():
		var s := d.size
		var inset := 10.0
		var px := 3.0  # 像素点边长
		for c: Vector2 in [Vector2(inset, inset), Vector2(s.x - inset, inset), Vector2(inset, s.y - inset), Vector2(s.x - inset, s.y - inset)]:
			d.draw_rect(Rect2(c.x - px / 2, c.y - px / 2, px, px), Color(rivet, 0.9))
			d.draw_rect(Rect2(c.x - px / 2 - 3, c.y - px / 2 - 3, px, px), Color(rivet, 0.25))
		d.draw_rect(Rect2(3, 3, s.x - 6, s.y - 6), Color(BORDER, 0.16), false, 1.0))
	parent.add_child(d)
	return d

## 滚动条：长内容（任务详情、按键表）会超出面板，默认滚动条在深色底上几乎看不见，
## 玩家会以为内容被截断 —— 换成银灰轨道 + 幽蓝滑块，明确「下面还有」。
static func style_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 12
	bar.add_theme_stylebox_override("scroll", track())
	bar.add_theme_stylebox_override("scroll_focus", track())
	bar.add_theme_stylebox_override("grabber", flat(Color(BORDER, 0.75), Color(0, 0, 0, 0), 0, RADIUS, 0))
	bar.add_theme_stylebox_override("grabber_highlight", flat(ACCENT, Color(0, 0, 0, 0), 0, RADIUS, 0))
	bar.add_theme_stylebox_override("grabber_pressed", flat(ACCENT, Color(0, 0, 0, 0), 0, RADIUS, 0))

## 滑条（主音量 / 音效 / 镜头灵敏度）：默认主题是圆头灰条，与「方块直角、无圆角」的设计语言冲突，
## 所以轨道与已填充段自己拼（Slider 拿样式盒的**最小高度**当条厚，内容边距为 0 会画成一条 2px 细线，
## 所以这里显式给上下内容边距），拖块用现场生成的硬边方块贴图（不落资源文件）。
static func style_slider(slider: Slider) -> void:
	slider.add_theme_stylebox_override("slider", bar(Color(BG_TRACK, 0.95), Color(BORDER, 0.45)))
	slider.add_theme_stylebox_override("grabber_area", bar(Color(ACCENT, 0.5), Color(0, 0, 0, 0)))
	slider.add_theme_stylebox_override("grabber_area_highlight", bar(Color(ACCENT, 0.75), Color(0, 0, 0, 0)))
	slider.add_theme_icon_override("grabber", pixel_block(12, 22, BORDER, ACCENT_DIM))
	slider.add_theme_icon_override("grabber_disabled", pixel_block(12, 22, BORDER, ACCENT_DIM))
	slider.add_theme_icon_override("grabber_highlight", pixel_block(12, 22, ACCENT, Color("dceeff")))

## 滑条用的横条样式：1px 描边 + 8px 厚（border 1 + 上下内容边距 3）。
static func bar(bg: Color, border: Color, thickness := 8) -> StyleBoxFlat:
	var st := flat(bg, border, 1 if border.a > 0.0 else 0, RADIUS, 0)
	st.content_margin_top = maxi(0, thickness / 2 - 1)
	st.content_margin_bottom = maxi(0, thickness / 2 - 1)
	return st

## 生成一枚硬边方块贴图：1px 描边色 + 实心填充色，无圆角无抗锯齿（像素风拖块用）。
static func pixel_block(w: int, h: int, border: Color, body: Color) -> ImageTexture:
	var image := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var on_edge := x == 0 or y == 0 or x == w - 1 or y == h - 1
			image.set_pixel(x, y, border if on_edge else body)
	return ImageTexture.create_from_image(image)

## 标签胶囊（职业/状态徽记）：左侧幽蓝像素点 + 文字。
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