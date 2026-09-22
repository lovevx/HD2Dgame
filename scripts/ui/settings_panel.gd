extends CanvasLayer
const SystemUI := preload("res://scripts/ui/system_ui.gd")
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")
const Prefs := preload("res://data/prefs.gd")
## 常量（分辨率档位、滑条区间）走脚本本身：不依赖自动加载实例，纯静态读取。
const SettingsScript := preload("res://autoload/game_settings.gd")
## 「设置」面板：左侧分页导航（画面 / 声音 / 游玩 / 按键），右侧改这一页的项。
##
## 开关方式：主菜单点「设置」按钮，或游戏内 Esc 菜单点「设置」→ open()；Esc 或「返回」close()。
## 加入 "settings_panel" 组，HUD 的 is_modal_open() 据此把它当模态面板（战役模式随之冻结
## 玩家与敌人、相机让出滚轮、系统光标交还）。
##
## 与其它面板的输入约定不同，本面板**自己吃两种输入**（各自的理由写在那两处）：
##   1. 改键捕获（_capturing）：只在这期间拦，拦的是「按下的任意键」本身；
##   2. Esc（_input 里的兜底）：玩家把 open_menu 改走之后，Esc 仍必须关得掉这个面板。
## 其余情况一律不消费输入，交给 HUD 统一路由（与 quest_panel 同一约定）。
##
## 设置在 GameSettings（自动加载，落盘 user://settings.cfg）；本面板只负责界面与改键捕获，
## 不持有任何设置值 —— 每行显示的当前状态都是从 GameSettings / InputMap 现读的。

signal closed

const NAV := [
	{"id": "display", "title": "画 面", "desc": "窗口模式、分辨率、垂直同步与帧率上限"},
	{"id": "audio", "title": "声 音", "desc": "主音量与音效音量"},
	{"id": "gameplay", "title": "游 玩", "desc": "镜头手感、过场震动与光标样式"},
	{"id": "keys", "title": "按 键", "desc": "重绑战斗与界面按键；鼠标中键/滚轮取景为固定手势"},
]

var _page := "display"
var _content: VBoxContainer
var _scroll: ScrollContainer
var _nav_buttons: Dictionary = {}
var _back: Button
var _status: Label
var _capturing := false
var _capture_action := ""
var _capture_button: Button

func _ready() -> void:
	add_to_group("settings_panel")
	layer = 45
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.03, 0.05, 0.84)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1280, 840)
	card.mouse_filter = Control.MOUSE_FILTER_STOP  # 点面板本身不该穿到世界里去打一刀
	card.add_theme_stylebox_override("panel", SystemUI.card())
	SystemUI.decor(card)
	center.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	card.add_child(page)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	page.add_child(head)
	var title := _label(head, "设 置", 40, SystemUI.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status = _label(head, "", 18, SystemUI.TEXT_DIM)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page.add_child(HSeparator.new())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_nav())
	# 内容放进滚动区：按键页有 20 行，比一屏高。不滚动的话 VBox 的最小高度会把卡片撑过窗口，
	# 居中之后上下都被切掉，「返回」按钮就点不到了。滚动条样式沿用任务档案那一套。
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	SystemUI.style_scrollbar(scroll)
	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 8)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	_scroll = scroll

	page.add_child(HSeparator.new())
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 16)
	page.add_child(foot)
	_back = Button.new()
	_back.text = "返 回"
	_back.custom_minimum_size = Vector2(240, 54)
	_back.add_theme_font_size_override("font_size", 24)
	SystemUI.style_button(_back)
	_back.pressed.connect(close)
	foot.add_child(_back)
	_label(foot, "Esc 关闭 · 按键改动立刻对全部场景生效", 18, SystemUI.TEXT_DIM)

## 左侧分页导航。按钮只切页，不关面板；当前页那一格置灰当「你在这里」标记。
func _build_nav() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", SystemUI.sub())
	panel.custom_minimum_size.x = 250
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	for entry in NAV:
		var button := Button.new()
		button.text = entry["title"]
		button.custom_minimum_size = Vector2(210, 58)
		button.add_theme_font_size_override("font_size", 25)
		SystemUI.style_button(button)
		button.pressed.connect(_select_page.bind(str(entry["id"])))
		column.add_child(button)
		_nav_buttons[entry["id"]] = button
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	return panel

func open(page_id := "") -> void:
	if _settings() == null:
		return  # 没有设置自动加载（纯数据工具）时不开面板，别把空引用传下去
	if page_id != "":
		_page = page_id
	_build_page()
	visible = true
	if _back != null:
		_back.grab_focus()

func close() -> void:
	_cancel_capture()
	visible = false
	closed.emit()

func _select_page(page_id: String) -> void:
	_page = page_id
	_build_page()

# ---------------------------------------------------------------- 各页内容

func _build_page() -> void:
	_cancel_capture()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	# 换页回到顶部：从滚到一半的按键页切到画面页，位置不该跟着过去。
	if _scroll != null:
		_scroll.scroll_vertical = 0
	for id in _nav_buttons.keys():
		var button: Button = _nav_buttons[id]
		# 当前页置灰（禁用态样式更暗，一眼看出位置）。保留可点也没意义，点了只是重画同一页。
		button.disabled = str(id) == _page
	var desc := ""
	for entry in NAV:
		if entry["id"] == _page:
			desc = str(entry["desc"])
	match _page:
		"display":
			_build_display_page(desc)
		"audio":
			_build_audio_page(desc)
		"gameplay":
			_build_gameplay_page(desc)
		_:
			_build_keys_page(desc)
	_refresh_status()

## 页头：标题 + 这一页管什么。
func _page_header(title: String, desc: String) -> void:
	_label(_content, title, 30, SystemUI.ACCENT)
	_label(_content, desc, 18, SystemUI.TEXT_DIM)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	_content.add_child(gap)

func _build_display_page(desc: String) -> void:
	_page_header("画 面", desc)
	var settings := _settings()
	var windowed := int(settings.window_mode) == SettingsScript.WindowMode.WINDOWED
	_choice_row("窗口模式", ["窗口", "全屏（独占）", "无边框全屏"], int(settings.window_mode), func(index: int):
		settings.set_window_mode(index))
	# 全屏下分辨率由系统决定，这一行点了不会有反应 —— 索性置灰，别让玩家以为是坏的。
	_choice_row("分辨率", SettingsScript.RESOLUTION_LABELS, SettingsScript.RESOLUTIONS.find(settings.resolution), func(index: int):
		settings.set_resolution(SettingsScript.RESOLUTIONS[index]), windowed)
	_choice_row("垂直同步", ["开", "关"], 0 if settings.vsync else 1, func(index: int):
		settings.set_vsync(index == 0))
	_choice_row("帧率上限", SettingsScript.FPS_LABELS, SettingsScript.FPS_OPTIONS.find(settings.fps_limit), func(index: int):
		settings.set_fps_limit(SettingsScript.FPS_OPTIONS[index]))
	_label(_content, "分辨率只在窗口模式下生效，切回窗口会自动居中；全屏模式按显示器原生分辨率输出。", 17, SystemUI.TEXT_DIM)

func _build_audio_page(desc: String) -> void:
	_page_header("声 音", desc)
	var settings := _settings()
	_slider_row("主音量", settings.master_volume, 0, 100, "%.0f%%", func(value: float):
		settings.set_master_volume(int(value)))
	_slider_row("音效音量", settings.sfx_volume, 0, 100, "%.0f%%", func(value: float):
		settings.set_sfx_volume(int(value)))
	_label(_content, "音效走 SFX 总线（res://default_bus_layout.tres），剃的破空声等战斗音都归它管；", 17, SystemUI.TEXT_DIM)
	_label(_content, "当前版本还没有背景音乐，主音量实际管的是整体输出。", 17, SystemUI.TEXT_DIM)

func _build_gameplay_page(desc: String) -> void:
	_page_header("游 玩", desc)
	var settings := _settings()
	_slider_row("镜头灵敏度", settings.camera_sensitivity, SettingsScript.MIN_SENSITIVITY, SettingsScript.MAX_SENSITIVITY, "%.2f×", func(value: float):
		settings.set_camera_sensitivity(value))
	_choice_row("镜头上下反转", ["关（上推＝抬高机位）", "开（上推＝压低机位）"], 1 if settings.camera_invert_y else 0, func(index: int):
		settings.set_camera_invert_y(index == 1))
	_choice_row("过场镜头震动", ["开", "关"], 0 if settings.cinematic_shake else 1, func(index: int):
		settings.set_cinematic_shake(index == 0))
	_choice_row("鼠标光标", ["游戏内剑刃光标", "系统光标"], 0 if settings.game_cursor else 1, func(index: int):
		settings.set_game_cursor(index == 0))
	_label(_content, "灵敏度只改中键拖动转视角的速度，滚轮推拉的步长不变；上下反转只作用于拖动，不改出生机位。", 17, SystemUI.TEXT_DIM)
	_label(_content, "面板打开时一律交还系统光标，与上面选哪种光标无关 —— 否则点不到面板上的按钮。", 17, SystemUI.TEXT_DIM)

func _build_keys_page(desc: String) -> void:
	_page_header("按 键", desc)
	var group := ""
	for entry in KeyBindings.REBINDABLE:
		if str(entry["group"]) != group:
			group = str(entry["group"])
			var gap := Control.new()
			gap.custom_minimum_size.y = 4
			_content.add_child(gap)
			_label(_content, group, 22, SystemUI.GOLD)
		_rebind_row(str(entry["bind"]), str(entry["label"]))
	var note := HBoxContainer.new()
	note.add_theme_constant_override("separation", 16)
	_content.add_child(note)
	var reset := Button.new()
	reset.text = "恢复默认键位"
	reset.custom_minimum_size = Vector2(240, 48)
	reset.add_theme_font_size_override("font_size", 21)
	SystemUI.style_button(reset)
	reset.pressed.connect(func():
		_settings().reset_keys()
		_build_page())
	note.add_child(reset)
	_label(note, "会把全部按键还原成工程默认值（project.godot 的 [input]）。", 17, SystemUI.TEXT_DIM)
	_label(_content, "「鼠标中键拖动取景」「滚轮推拉」不是 InputMap 动作（相机代码里硬判的按钮），暂不支持改键。", 17, SystemUI.TEXT_DIM)

# ---------------------------------------------------------------- 行构造

## 单选行：一行选项按钮，当前项置灰当选中标记。
func _choice_row(title: String, labels: Array, current: int, apply: Callable, enabled := true) -> void:
	var row := _row_base(title)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 8)
	row.add_child(options)
	for index in labels.size():
		var button := Button.new()
		button.text = str(labels[index])
		button.custom_minimum_size = Vector2(0, 46)
		button.add_theme_font_size_override("font_size", 21)
		SystemUI.style_button(button)
		button.disabled = index == current or not enabled
		button.pressed.connect(func():
			apply.call(index)
			_build_page())
		options.add_child(button)

## 滑条行：拖动即时生效（每次变化都落盘 —— 设置档很小，图的是「所见即所存」，
## 不用再维护一套「脏了没」的状态机）；右侧实时显示数值。
func _slider_row(title: String, value: float, minimum: float, maximum: float, fmt: String, apply: Callable) -> void:
	var row := _row_base(title)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1.0 if maximum > 10.0 else 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(430, 40)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	SystemUI.style_slider(slider)
	row.add_child(slider)
	var readout := _label(row, fmt % value, 21, SystemUI.ACCENT)
	readout.custom_minimum_size.x = 96
	slider.value_changed.connect(func(changed: float):
		readout.text = fmt % changed
		apply.call(changed))

## 改键行：右侧一格显示当前键，点它进入捕获态。
func _rebind_row(action: String, label: String) -> void:
	var row := _row_base(label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(240, 46)
	button.add_theme_font_size_override("font_size", 21)
	SystemUI.style_button(button)
	button.text = KeyBindings.key_text(action)
	button.pressed.connect(_begin_capture.bind(action, button))
	row.add_child(button)

## 行的公共骨架：左标题定宽，右侧留给控件。
func _row_base(title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.custom_minimum_size.y = 54
	_content.add_child(row)
	var head := _label(row, title, 21)
	head.custom_minimum_size.x = 240
	head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row

func _label(parent: Node, text: String, font_size: int, color := SystemUI.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.92))
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	return label

## 设置自动加载实例。按节点路径取（见 data/prefs.gd），这样本文件即使被
## --script 校验脚本在编译期带进来也不会因自动加载名未注册而编译失败。
func _settings() -> Node:
	return Prefs.node()

# ---------------------------------------------------------------- 改键捕获

func _begin_capture(action: String, button: Button) -> void:
	_cancel_capture()
	_capturing = true
	_capture_action = action
	_capture_button = button
	button.text = "请按新键…（Esc 取消）"
	button.disabled = true
	_status.text = "等待按键 · %s" % action
	_status.add_theme_color_override("font_color", SystemUI.ACCENT)

func _cancel_capture() -> void:
	if not _capturing:
		return
	_capturing = false
	if _capture_button != null and is_instance_valid(_capture_button):
		_capture_button.text = KeyBindings.key_text(_capture_action)
		_capture_button.disabled = false
	_capture_button = null
	_capture_action = ""
	_refresh_status()

## 输入消费点之一：改键捕获期间拦下「按下的任意键」，包括 Esc（＝取消）。
## 用 _input 而不是 _unhandled_input：回调顺序上 _input 先跑，在这里标记 handled
## 才抢得在 HUD 与 GUI 之前，否则按空格会顺手把聚焦的按钮也按下去。
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _capturing:
		if not (event is InputEventKey or event is InputEventMouseButton) or not event.is_pressed():
			return
		get_viewport().set_input_as_handled()
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			_cancel_capture()
			return
		var binding := KeyBindings.binding_of(event)
		if binding.is_empty():
			return  # 滚轮之类不可绑定的，忽略这一次
		var action := _capture_action
		_cancel_capture()
		_settings().rebind(action, str(binding["kind"]), int(binding["code"]))
		_build_page()  # 重画：本行新键名、被对调的那一行也跟着变
		return
	# 输入消费点之二：Esc 兜底关闭。玩家一旦把 open_menu 改到别的键上，
	# HUD 那条 open_menu 路由就管不到这里了，Esc 必须仍然关得掉设置面板。
	if event is InputEventKey and event.is_pressed() and not (event as InputEventKey).is_echo() \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

func _refresh_status() -> void:
	_status.text = "改动即时生效 · 自动保存到 user://settings.cfg"
	_status.add_theme_color_override("font_color", SystemUI.TEXT_DIM)
