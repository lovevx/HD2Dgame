extends Control
## 开场过场播片·第一幕：现实车祸 → 死亡 → 输入姓名并按手印签订契约。
## 契约完成后切到第二幕 3D 过场（opening_boat.tscn：船上醒来 → 靠灰潮港）。
## 画面 = 2.5D 环境底图 + 程序化镜头效果（cinematic.gd）+ 全屏片场特效（cinematic_overlay.gdshader）。
## 节奏 = 打字机推进，播完镜头停留片刻自动进下一镜；点击/空格可跳过当前文字或立刻前进。

const Cinematic := preload("res://scripts/main/cinematic.gd")
const SystemUI := preload("res://scripts/ui/system_ui.gd")
const ContractPanelScript := preload("res://scripts/ui/contract_panel.gd")
const OVERLAY_SHADER := preload("res://shaders/cinematic_overlay.gdshader")
const OPENING_BOAT_SCENE := "res://scenes/main/opening_boat.tscn"

const LINES: Array[String] = [
 "晚高峰的十字路口，路灯刺得人睁不开眼。",
 "你低头看了一眼手机——再过三分钟，就是那场等了很久的面试。",
 "刺耳的喇叭声由远及近，雪亮的车灯瞬间吞没视野。",
 "——砰！",
 "身体被巨力抛起，重重砸在柏油路面上。",
 "剧痛与黑暗一同涌来。意识沉没的最后一刻，你只听见自己的心跳——",
]

## 契约过场分镜共约 32 秒；填写姓名和按手印由玩家推进，不限时。
const CONTRACT_SHOTS: Array[Dictionary] = [
	{"id": "B1", "duration": 4.0},
	{"id": "B2", "duration": 5.0},
	{"id": "B3", "duration": 7.0},
	{"id": "B4"}, # 姓名输入与按手印
	{"id": "B5", "duration": 6.0},
	{"id": "B6", "duration": 6.0},
	{"id": "B7", "duration": 4.0},
]

const CHAR_INTERVAL := 0.045
const CONTRACT_COUNTDOWN_START := 5710 # 1:35:10

## 每行台词 → {scene, sub, hold 停留秒, cap 截屏验收帧, title/tag 中心摆字}。
const SHOTS_0: Array[Dictionary] = [
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.ESTABLISH, "hold": 1.8, "cap": 1.35},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.PHONE, "hold": 1.9, "cap": 1.1},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.TRUCK, "hold": 3.2, "cap": 2.2},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.IMPACT, "hold": 1.9, "cap": 0.34},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.DYING, "hold": 2.7, "cap": 1.5},
 {"scene": Cinematic.SceneId.CITY, "sub": Cinematic.SubId.DYING, "hold": 2.3, "cap": 2.2},
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
var _contract_started := false
var _contract_active := false
var _contract_accepted := false
var _contract_stage := -1
var _contract_elapsed := 0.0
var _countdown_start_elapsed := 0.0
var _countdown_active := false
var _contract_caption_tween: Tween

var cinematic: Cinematic
var overlay: ColorRect
var fade_rect: ColorRect
var speaker_label: Label
var text_label: Label
var hint_label: Label
var title_label: Label
var tag_label: Label
var countdown_label: Label
var contract_hud: Control
var contract_health_bar: ProgressBar
var contract_stamina_bar: ProgressBar
var contract_panel: ContractPanel

func _ready() -> void:
	_build_cinematic()
	_build_overlay()
	_build_subtitles()
	_build_flourish()
	_build_contract_hud()
	_build_contract_panel()
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
	countdown_label = _label(self, "", 22, Color("ff4d4d"))
	countdown_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	countdown_label.position = Vector2(42, -84)
	countdown_label.size = Vector2(440, 40)
	countdown_label.add_theme_constant_override("outline_size", 7)
	countdown_label.hide()

func _build_flourish() -> void:
	title_label = _label(self, "", 48, Color("f2dc9b"))
	title_label.z_index = 2
	title_label.position = Vector2(0, 288)
	title_label.size = Vector2(1920, 90)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_constant_override("outline_size", 10)
	tag_label = _label(self, "", 27, SystemUI.ACCENT)
	tag_label.z_index = 2
	tag_label.position = Vector2(0, 392)
	tag_label.size = Vector2(1920, 60)
	tag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag_label.add_theme_constant_override("outline_size", 7)

func _build_fade_rect() -> void:
	fade_rect = ColorRect.new()
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.z_index = 1
	fade_rect.color = Color(0, 0, 0, 0)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.hide()
	add_child(fade_rect)

func _build_contract_panel() -> void:
	contract_panel = ContractPanelScript.new()
	contract_panel.name = "ContractPanel"
	contract_panel.accepted.connect(_on_contract_accepted)
	add_child(contract_panel)

func _build_contract_hud() -> void:
	contract_hud = Control.new()
	contract_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contract_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	contract_hud.modulate.a = 0.0
	add_child(contract_hud)
	var frame := PanelContainer.new()
	frame.position = Vector2(34, 32)
	frame.custom_minimum_size = Vector2(390, 142)
	frame.add_theme_stylebox_override("panel", SystemUI.flat(Color(SystemUI.BG, 0.82), Color(SystemUI.BORDER, 0.78), 1, SystemUI.RADIUS, 14))
	contract_hud.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	frame.add_child(column)
	_label(column, "半数据化状态", 18, SystemUI.GOLD)
	var health_row := HBoxContainer.new()
	health_row.add_theme_constant_override("separation", 10)
	column.add_child(health_row)
	_label(health_row, "生命", 16, SystemUI.TEXT)
	contract_health_bar = _contract_bar(health_row, Color("c95449"))
	var stamina_row := HBoxContainer.new()
	stamina_row.add_theme_constant_override("separation", 10)
	column.add_child(stamina_row)
	_label(stamina_row, "体力", 16, SystemUI.TEXT)
	contract_stamina_bar = _contract_bar(stamina_row, SystemUI.GOLD)
	SystemUI.decor(frame, SystemUI.CRYSTAL)
	contract_hud.hide()

func _contract_bar(parent: Node, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(270, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100.0
	bar.value = 0.0
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", SystemUI.track())
	bar.add_theme_stylebox_override("fill", SystemUI.fill(color))
	parent.add_child(bar)
	return bar

# ---------------------------------------------------------------- 主循环

func _process(delta: float) -> void:
	_update_overlay()
	if _capture_static:
		return
	if _contract_active:
		_contract_elapsed += delta
		_update_contract_countdown()
		return
	_type_step(delta)
	if _finished:
		_hold_t += delta
		if _hold_t >= _hold and not _fading:
			_advance_line()

func _update_overlay() -> void:
	var mat := overlay.material as ShaderMaterial
	if _contract_active:
		_update_contract_overlay(mat)
		return
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

func _update_contract_overlay(mat: ShaderMaterial) -> void:
	var vig := 0.78
	var dark := 0.22
	var heart := 0.0
	var flash_amt := 0.0
	var flash_col := Color(0.68, 0.86, 1.0)
	match _contract_stage:
		0:
			dark = 0.82
			heart = 0.22
		1:
			dark = 0.66
			heart = 0.35
		2:
			dark = 0.38
			vig = 0.62
		3:
			dark = 0.16
			vig = 0.48
		4:
			dark = 0.10
			vig = 0.42
		5:
			dark = 0.04
			vig = 0.36
			flash_col = Color("9cffb3")
			flash_amt = 0.08 + 0.035 * (0.5 + 0.5 * sin(_contract_elapsed * 3.0))
		6:
			dark = 0.12
			vig = 0.44
	mat.set_shader_parameter("u_vignette", vig)
	mat.set_shader_parameter("u_dark", dark)
	mat.set_shader_parameter("u_heart", heart)
	mat.set_shader_parameter("u_heart_hue", 0.0)
	mat.set_shader_parameter("u_flash", flash_col)
	mat.set_shader_parameter("u_flash_amt", flash_amt)
	mat.set_shader_parameter("u_grain", 0.055)
	mat.set_shader_parameter("u_t", cinematic.scene_t)

func _update_contract_countdown() -> void:
	if not _countdown_active:
		return
	var remaining := maxi(0, CONTRACT_COUNTDOWN_START - int(_contract_elapsed - _countdown_start_elapsed))
	var hours := int(remaining / 3600)
	var minutes := int((remaining % 3600) / 60)
	var seconds := remaining % 60
	countdown_label.text = "灵魂消散倒计时  %d:%02d:%02d" % [hours, minutes, seconds]
	if contract_panel.visible:
		contract_panel.set_death_countdown(remaining)

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
		_start_contract_scene()
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

func _start_contract_scene() -> void:
	if _contract_started:
		return
	_contract_started = true
	_contract_active = true
	_contract_stage = 0
	_contract_elapsed = 0.0
	_contract_accepted = false
	_countdown_active = false
	countdown_label.hide()
	contract_hud.hide()
	contract_panel.close()
	hint_label.text = ""
	speaker_label.hide()
	_clear_flourish()
	_kill_fade()
	fade_rect.hide()
	cinematic.shot(Cinematic.SceneId.CITY, Cinematic.SubId.DYING)
	_run_contract_scenes()

func _run_contract_scenes() -> void:
	var b1 := float(CONTRACT_SHOTS[0]["duration"])
	_show_contract_caption("【检测到适格灵魂。】", 1.45)
	await _wait_contract(b1 * 0.5)
	_show_contract_caption("【「轮回乐园」契约邀请已送达。】", 1.0)
	await _wait_contract(b1 * 0.5)

	_contract_stage = 1
	_countdown_active = true
	_countdown_start_elapsed = _contract_elapsed
	countdown_label.show()
	_update_contract_countdown()
	_show_contract_caption("【灵魂稳定度持续下降。请于倒计时结束前完成签约。】", 1.4)
	await _wait_contract(float(CONTRACT_SHOTS[1]["duration"]))
	countdown_label.hide()

	_contract_stage = 2
	_apply_shot({"scene": Cinematic.SceneId.CONTRACT, "sub": 0})
	_show_contract_caption("【签约后，你将进入衍生位面，完成乐园发布的任务。】\n【任务奖励将依据获得的「世界之源」结算。】", 2.8)
	await _wait_contract(4.5)
	_show_contract_caption("【详细规则以契约条款为准。】", 0.8)
	await _wait_contract(float(CONTRACT_SHOTS[2]["duration"]) - 4.5)

	_contract_stage = 3
	contract_panel.open()
	_update_contract_countdown()
	_show_contract_caption("【先输入姓名，再按下手印。】", 0.8)
	while not _contract_accepted:
		await get_tree().process_frame

	_contract_stage = 4
	_show_contract_caption("指尖刺痛。艳红的血浸入羊皮纸……", 1.25)
	await contract_panel.play_blood_animation(float(CONTRACT_SHOTS[4]["duration"]) - 0.5)
	_countdown_active = false
	await contract_panel.fade_out_and_close(0.5)

	_contract_stage = 5
	title_label.text = "【契约成立！】"
	title_label.modulate.a = 1.0
	title_label.add_theme_color_override("font_color", Color("a8ffb6"))
	title_label.show()
	_show_contract_caption("【伤势修复启动。】", 0.9)
	await _wait_contract(2.0)
	title_label.text = "【强制觉醒猎杀者天赋·噬灵者】"
	_show_contract_caption("剧痛袭来，血管暴起。\n身体不受控制地跪倒在地。", 1.2)
	await _wait_contract(float(CONTRACT_SHOTS[5]["duration"]) - 2.0)

	_contract_stage = 6
	title_label.text = "【半数据化开启】"
	title_label.add_theme_color_override("font_color", SystemUI.GOLD)
	_show_contract_caption("【半数据化开启】", 0.65)
	_reveal_contract_hud()
	await _wait_contract(1.2)
	title_label.text = "【警告】"
	_show_contract_caption("【警告：心脏、大脑等关键组织仍严重受损。】\n【猎杀者仍会死亡。】\n【乐园条例：一切都将等价交换。】", 1.25)
	await _wait_contract(float(CONTRACT_SHOTS[6]["duration"]) - 1.2)
	await _finish_contract_scene()

func _wait_contract(seconds: float) -> void:
	await get_tree().create_timer(maxf(seconds, 0.0)).timeout

func _show_contract_caption(text: String, reveal_seconds: float) -> void:
	if _contract_caption_tween != null and _contract_caption_tween.is_running():
		_contract_caption_tween.kill()
	text_label.text = text
	text_label.visible_characters = 0
	_contract_caption_tween = create_tween()
	_contract_caption_tween.tween_property(text_label, "visible_characters", text.length(), maxf(reveal_seconds, 0.05)).set_trans(Tween.TRANS_LINEAR)

func _on_contract_accepted() -> void:
	_contract_accepted = true

func _reveal_contract_hud() -> void:
	contract_hud.show()
	contract_hud.modulate.a = 0.0
	contract_health_bar.value = 0.0
	contract_stamina_bar.value = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(contract_hud, "modulate:a", 1.0, 0.8)
	tween.tween_property(contract_health_bar, "value", 62.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(contract_stamina_bar, "value", 38.0, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _finish_contract_scene() -> void:
	_countdown_active = false
	countdown_label.hide()
	contract_hud.hide()
	_fading = true
	fade_rect.show()
	fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	var darken := create_tween()
	darken.tween_property(fade_rect, "color:a", 1.0, 0.65)
	await darken.finished
	title_label.text = "传送开始……"
	title_label.modulate.a = 0.0
	title_label.show()
	var transfer := create_tween()
	transfer.tween_property(title_label, "modulate:a", 1.0, 0.32)
	await transfer.finished
	await _wait_contract(0.35)
	_clear_flourish()
	var reveal := create_tween()
	reveal.tween_property(fade_rect, "color:a", 0.0, 0.85)
	await reveal.finished
	fade_rect.hide()
	_fading = false
	text_label.visible_characters = -1
	GameState.complete_contract(contract_panel.get_signer_name())
	GameState.begin_onboarding()
	_contract_active = false
	GameState.change_scene(OPENING_BOAT_SCENE)

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
	if _fading or _contract_active:
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

func _clear_flourish() -> void:
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	title_label.visible = false
	tag_label.visible = false

# ---------------------------------------------------------------- 输入

func _gui_input(event: InputEvent) -> void:
	if _fading or _contract_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_skip()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _fading or _contract_active:
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
