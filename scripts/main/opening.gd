extends Control
## 开场过场播片·第一幕：现实车祸 → 死亡 → 轮回乐园契约 → 取名。
## 取名完成后切到第二幕 3D 过场（opening_boat.tscn：船上醒来 → 靠灰潮港）。
## 画面 = 程序化 2D 电影镜头（cinematic.gd）+ 全屏片场特效（cinematic_overlay.gdshader）。
## 节奏 = 打字机推进，播完镜头停留片刻自动进下一镜；点击/空格可跳过当前文字或立刻前进。

const Cinematic := preload("res://scripts/main/cinematic.gd")
const SystemUI := preload("res://scripts/ui/system_ui.gd")
const OVERLAY_SHADER := preload("res://shaders/cinematic_overlay.gdshader")
const OPENING_BOAT_SCENE := "res://scenes/main/opening_boat.tscn"

const LINES: Array[String] = [
 "晚高峰的十字路口，路灯刺得人睁不开眼。",
 "你低头看了一眼手机——再过三分钟，就是那场等了很久的面试。",
 "刺耳的喇叭声由远及近，雪亮的车灯瞬间吞没视野。",
 "——砰！",
 "身体被巨力抛起，重重砸在柏油路面上。",
 "剧痛与黑暗一同涌来。意识沉没的最后一刻，你只听见自己的心跳——",
 "「轮回乐园 · 猎杀者试炼」",
 "检测到契约者灵魂强度达标，伤势已修复。",
 "签订契约，开启半数据化与天赋【噬灵者】。",
 "从今天起，每一次猎杀都会带来成长。",
]

const NAME_PROMPT := "契约者，报上你的名字"
const CHAR_INTERVAL := 0.045

## 每行台词 → {scene, sub, hold 停留秒, cap 截屏验收帧, title/tag 中心摆字}。
const SHOTS_0: Array[Dictionary] = [
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.ESTABLISH, "hold": 1.8, "cap": 1.35},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.PHONE, "hold": 1.9, "cap": 1.1},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.TRUCK, "hold": 3.2, "cap": 2.2},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.IMPACT, "hold": 1.9, "cap": 0.34},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.DYING, "hold": 2.7, "cap": 1.5},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.DYING, "hold": 2.3, "cap": 2.2},
 {"scene": Cinematic.SceneId.CONTRACT, "sub": 0, "hold": 2.7, "cap": 1.7,
  "title": "「轮回乐园 · 猎杀者试炼」", "tag": "检测到契约者灵魂强度达标"},
 {"scene": Cinematic.SceneId.CONTRACT, "sub": 0, "hold": 2.3, "cap": 2.6,
  "tag": "伤势已修复 · 签订契约开启半数据化"},
 {"scene": Cinematic.SceneId.CONTRACT, "sub": 0, "hold": 2.4, "cap": 3.5,
  "tag": "天赋【噬灵者】已绑定"},
 {"scene": Cinematic.SceneId.CONTRACT, "sub": 0, "hold": 1.9, "cap": 4.4,
  "tag": "从今天起，每一次猎杀都会带来成长"},
]

var _line_index := -1
var _char_index := 0
var _type_timer := 0.0
var _finished := false
var _lines: Array[String] = LINES
var _hold := 1.0
var _hold_t := 0.0
var _fading := false
var _fade_tween: Tween
var _title_tween: Tween
var _capture_static := false

var cinematic: Cinematic
var overlay: ColorRect
var fade_rect: ColorRect
var speaker_label: Label
var text_label: Label
var hint_label: Label
var title_label: Label
var tag_label: Label
var name_panel: Control
var name_edit: LineEdit

func _ready() -> void:
	_build_cinematic()
	_build_overlay()
	_build_subtitles()
	_build_flourish()
	_build_name_panel()
	_build_fade_rect()
	text_label.text = ""
	_advance_line()

# ---------------------------------------------------------------- 节点构建

func _build_cinematic() -> void:
	cinematic = Cinematic.new()
	cinematic.z_index = -10
	add_child(cinematic)

func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.color = Color(1, 1, 1)
	var mat := ShaderMaterial.new()
	mat.shader = OVERLAY_SHADER
	overlay.material = mat
	add_child(overlay)

func _build_subtitles() -> void:
	var band := ColorRect.new()
	band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_left = 0
	band.offset_right = 0
	band.offset_top = -172
	band.offset_bottom = 0
	band.color = Color(0.01, 0.02, 0.035, 0.42)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_left = 240
	box.offset_right = -240
	box.offset_top = -150
	box.offset_bottom = -34
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	speaker_label = _label(box, "", 26, Color("ebd6a2"))
	speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_label = _label(box, "", 31, Color("e8f1f6"))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label = _label(box, "", 18, Color("7d94a8"))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_flourish() -> void:
	title_label = _label(self, "", 48, Color("f2dc9b"))
	title_label.position = Vector2(0, 288)
	title_label.size = Vector2(1920, 90)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_constant_override("outline_size", 10)
	tag_label = _label(self, "", 27, SystemUI.ACCENT)
	tag_label.position = Vector2(0, 392)
	tag_label.size = Vector2(1920, 60)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.add_theme_constant_override("outline_size", 7)

func _build_fade_rect() -> void:
	fade_rect = ColorRect.new()
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.hide()
	add_child(fade_rect)

func _build_name_panel() -> void:
	name_panel = Control.new()
	name_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(name_panel)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.01, 0.02, 0.04, 0.62)
	name_panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	name_panel.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", SystemUI.card())
	SystemUI.decor(card)
	center.add_child(card)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 640
	column.add_theme_constant_override("separation", 20)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)
	var title := _label(column, "契约签订", 44, Color("ebd6a2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var prompt := _label(column, NAME_PROMPT, 26, SystemUI.ACCENT)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit = LineEdit.new()
	name_edit.text = GameState.DEFAULT_PLAYER_NAME
	name_edit.placeholder_text = GameState.DEFAULT_PLAYER_NAME
	name_edit.custom_minimum_size = Vector2(520, 62)
	name_edit.add_theme_font_size_override("font_size", 30)
	name_edit.add_theme_stylebox_override("normal", _edit_style(Color(0.10, 0.17, 0.22)))
	name_edit.add_theme_stylebox_override("focus", _edit_style(Color("0f2232")))
	name_edit.add_theme_color_override("font_color", SystemUI.TEXT)
	name_edit.add_theme_color_override("caret_color", Color("ebd6a2"))
	name_edit.max_length = 12
	name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_edit.text_submitted.connect(_on_name_submitted)
	column.add_child(name_edit)
	var confirm := Button.new()
	confirm.text = "签订契约"
	confirm.custom_minimum_size = Vector2(520, 66)
	confirm.add_theme_font_size_override("font_size", 26)
	SystemUI.style_button(confirm)
	confirm.pressed.connect(_on_name_submitted)
	column.add_child(confirm)
	var tip := _label(column, "回车或点击按钮确认 · 将写入本机存档", 18, Color("5f7a8a"))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_panel.hide()

func _edit_style(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Color(0.35, 0.55, 0.68, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(SystemUI.RADIUS)
	return style

# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	_update_overlay()
	if _capture_static:
		return
	if name_panel.visible:
		return
	_type_step(delta)
	if _finished:
		_hold_t += delta
		if _hold_t >= _hold and not _fading:
			_advance_line()

func _update_overlay() -> void:
	var mat := overlay.material as ShaderMaterial
	var sid: int = cinematic.scene_id
	var s: int = cinematic.sub
	var tt: float = cinematic.shot_t
	var vig := 0.62
	var dark := 0.0
	var heart := 0.0
	var flash_amt := 0.0
	var flash_col := Color(0.92, 0.96, 1.0)
	if sid == Cinematic.SceneId.CITY:
		vig = 0.7
		match s:
			Cinematic.SubId.TRUCK:
				dark = 0.04 * tt
			Cinematic.SubId.IMPACT:
				if tt < 1.1:
					flash_amt = 1.7 * exp(-tt * 2.8)
					heart = 0.5 * exp(-tt * 1.4)
			Cinematic.SubId.DYING:
				dark = clampf(tt / 1.4, 0.0, 0.72)
				heart = maxf(heart, 0.35 + 0.3 * sin(cinematic.scene_t * 6.28 * 1.12))
	elif sid == Cinematic.SceneId.CONTRACT:
		vig = 0.5
		dark = 0.06
	mat.set_shader_parameter("u_vignette", vig)
	mat.set_shader_parameter("u_dark", dark)
	mat.set_shader_parameter("u_heart", heart)
	mat.set_shader_parameter("u_heart_hue", 0.0)
	mat.set_shader_parameter("u_flash", flash_col)
	mat.set_shader_parameter("u_flash_amt", flash_amt)
	mat.set_shader_parameter("u_grain", 0.075)
	mat.set_shader_parameter("u_t", cinematic.scene_t)

# ---------------------------------------------------------------- 打字机

func _type_step(delta: float) -> void:
	if _finished:
		return
	_type_timer += delta
	var step := int(_type_timer / CHAR_INTERVAL)
	if step <= 0:
		return
	var current := _lines[_line_index]
	var speaker := _speaker_of(current)
	var body := _body_of(current)
	if speaker != "":
		speaker_label.text = speaker
		speaker_label.show()
	else:
		speaker_label.text = ""
		speaker_label.hide()
	var target := _char_index + step
	if target >= body.length():
		text_label.text = body
		_finished = true
		hint_label.text = "点击 / 空格 继续 · 稍候自动播放"
		return
	text_label.text = body.substr(0, target)
	_char_index = target

func _advance_line() -> void:
	_line_index += 1
	if _line_index >= _lines.size():
		_show_name_panel()
		return
	var def := shot_def()
	_hold = float(def.get("hold", 1.8))
	_hold_t = 0.0
	_char_index = 0
	_type_timer = 0.0
	_finished = false
	hint_label.text = ""
	text_label.text = ""
	speaker_label.text = ""
	speaker_label.hide()
	_set_flourish(str(def.get("title", "")), str(def.get("tag", "")))
	_apply_shot(def)

func _apply_shot(def: Dictionary) -> void:
	var sid: int = int(def["scene"])
	var scene_changed: bool = sid != cinematic.scene_id
	cinematic.shot(sid, int(def["sub"]))
	if scene_changed:
		_kill_fade()
		fade_rect.show()
		fade_rect.color.a = 1.0
		_fade_tween = create_tween()
		_fade_tween.tween_property(fade_rect, "color:a", 0.0, 0.55)

func _kill_fade() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()

func _set_flourish(title: String, tag: String) -> void:
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	title_label.text = title
	title_label.visible = title != ""
	tag_label.text = tag
	tag_label.visible = tag != ""
	if title == "" and tag == "":
		return
	var target := 1.0
	if title == "":
		title_label.modulate.a = 0.0
	if tag == "":
		tag_label.modulate.a = 0.0
	_title_tween = create_tween().set_parallel(true)
	_title_tween.tween_property(title_label, "modulate:a", target, 0.7)
	_title_tween.tween_property(tag_label, "modulate:a", target, 0.9)

## 跳过：打字中→整句放完；已放完→立刻进下一镜。
func _on_skip() -> void:
	if name_panel.visible or _fading:
		return
	if _finished:
		_advance_line()
	else:
		_skip_line()

func _skip_line() -> void:
	_finished = true
	text_label.text = _body_of(_lines[_line_index])
	hint_label.text = "点击 / 空格 继续 · 稍候自动播放"

# ---------------------------------------------------------------- 阶段流转

func _show_name_panel() -> void:
	hint_label.text = ""
	name_panel.show()
	name_edit.grab_focus()
	name_edit.select_all()

func _on_name_submitted(_ignored: String = "") -> void:
	GameState.complete_contract(name_edit.text)
	GameState.begin_onboarding()
	name_panel.hide()
	_clear_flourish()
	# 契约签订完毕 → 第二幕 3D 过场（船上醒来 → 靠灰潮港），由它收尾进港口
	GameState.change_scene(OPENING_BOAT_SCENE)

func _clear_flourish() -> void:
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	title_label.visible = false
	tag_label.visible = false

# ---------------------------------------------------------------- 输入

func _gui_input(event: InputEvent) -> void:
	if name_panel.visible or _fading:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_skip()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if name_panel.visible or _fading:
		return
	var press := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		press = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		press = true
	if not press:
		return
	_on_skip()

# ---------------------------------------------------------------- 说话人解析

func _speaker_of(line: String) -> String:
	if line.begins_with("："):
		return "？？？"
	var idx := line.find("：")
	if idx > 0 and not line.begins_with("「"):
		return line.substr(0, idx)
	return ""

func _body_of(line: String) -> String:
	if line.begins_with("："):
		return line.substr(1)
	var idx := line.find("：")
	if idx > 0 and not line.begins_with("「"):
		return line.substr(idx + 1)
	return line

func shot_def() -> Dictionary:
	return SHOTS_0[_line_index]

func shot_count_phase(_phase: int) -> int:
	return SHOTS_0.size()

## 截屏验收：摆到指定台词的自定义帧，锁死后续自动推进。
func capture_pose(i: int, _phase: int = 0) -> void:
	_capture_static = true
	name_panel.hide()
	_line_index = i
	var def := shot_def()
	_apply_shot(def)
	cinematic.set_sim_time(float(def.get("cap", 1.2)))
	_finished = true
	text_label.text = _body_of(_lines[i])
	var sp := _speaker_of(_lines[i])
	speaker_label.text = sp
	speaker_label.visible = sp != ""
	hint_label.text = ""
	_set_flourish(str(def.get("title", "")), str(def.get("tag", "")))
	title_label.modulate.a = 1.0
	tag_label.modulate.a = 1.0
	_update_overlay()

func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.04, 0.95))
	label.add_theme_constant_override("outline_size", 6)
	parent.add_child(label)
	return label