extends CanvasLayer
const SystemUI := preload("res://scripts/ui/system_ui.gd")
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")
const QuestPanelScript := preload("res://scripts/ui/quest_panel.gd")
const SettingsPanelScript := preload("res://scripts/ui/settings_panel.gd")
const TestPanelScript := preload("res://scripts/ui/test_panel.gd")
const DialogueBoxScript := preload("res://scripts/ui/dialogue_box.gd")
const Attributes := preload("res://data/attributes.gd")
const PlayerStatusHud := preload("res://scripts/ui/player_status_hud.gd")
const PlayerFrames := preload("res://assets/characters/player_frames_video.tres")
const CursorTexture := preload("res://assets/ui/cursor.png")
## 光标图里剑尖所在的像素位置：贴图按这个点对准鼠标，指针才不会跑偏。
const CURSOR_TIP := Vector2(8, 8)
var player: Node
var header: Label
## 资源条 / 状态标签 / 快捷栏 / 低血红晕都在这个子控件里（player_status_hud.gd）。
var status_hud: Control
var objective_name: Label
var objective: Label
var objective_shortcut: Label
var message: Label
var overlay: ColorRect
var panel_title: Label
var panel_body: Label
var action_button: Button
var dialogue_box: Control
var _dialogue_pages: Array[String] = []
var _dialogue_speaker := ""
var _dialogue_page_index := 0
var _dialogue_callback := Callable()
var _dialogue_restore_prompt := false
var _dialogue_restore_hint_bar := false
var message_tween: Tween
var key_guide: Control
var prompt: Label
var hint_bar: Label                     # 底部键位提示条：文案由 KeyBindings 现读，改键后重算
var story_banner: PanelContainer  # 进关剧情条：上方横幅、小字、按任意操作自动收起
var story_body: Label
var menu: Control
var boss_box: VBoxContainer
var boss_name: Label
var boss_bar: ProgressBar
var boss_title := ""
var cursor: TextureRect
var char_panel: Control                 # C 键角色面板：左形象+装备环，右属性
var quest_panel: CanvasLayer            # J 键任务面板：左任务列表，右任务详情（脚本自建，见 quest_panel.gd）
var settings_panel: CanvasLayer         # 设置面板：主菜单与 Esc 菜单都能开（脚本自建，见 settings_panel.gd）
var test_panel: CanvasLayer
## F1 说明里会随改键变化的两类行：整行（键+短语）与只有键名那一列。改键后按同一份数据重算文字。
var _guide_lines: Array = []            # [{label, items}] → KeyBindings.line(items)
var _guide_keys: Array = []             # [{label, item}] → KeyBindings.keys_of(item)
var char_portrait: TextureRect
var char_attr_labels: Dictionary = {}   # 六维键 → 数值 Label（面板右侧）
var char_derived_label: Label
var char_points_label: Label
var _selected_bag: PanelContainer = null  # 背包当前点选格（高亮），再点取消
var campaign_controller: Node
var bag_cells: Array[PanelContainer] = []
var equipment_slots: Dictionary = {}
var item_detail: Label
var item_action: Button
var _selected_item := ""
var _selected_slot := ""   # 穿戴栏选中槽（有值时详情显示已穿戴物品，可卸下）
## 穿戴栏槽位标题 → 槽位 key（与 Campaign.SLOTS 对应）
const SLOT_TITLE_MAP := {
	"主武器": "main_weapon", "副武器": "offhand", "头部": "head", "躯干": "body",
	"护臂 · 左": "left_arm", "护臂 · 右": "right_arm", "足部": "boots", "披风": "cloak",
	"项链": "necklace", "戒指": "ring", "戒指Ⅱ": "ring_sub",
}
var _choice_buttons: Array[Button] = []

func _ready() -> void:
	_ensure_test_panel_action()
	add_to_group("hud")  # 传送门等场景元素靠它找到 HUD 显示贴底提示
	player = get_tree().get_first_node_in_group("player")
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# 状态层最先加：它自带的低血红晕铺满全屏，要压在其它 HUD 框下面。
	status_hud = PlayerStatusHud.new()
	status_hud.name = "PlayerStatus"
	status_hud.player = player
	status_hud.show_world_stats = campaign_controller != null
	root.add_child(status_hud)
	_build_player_badge(root)
	_build_objective(root)
	var hint := _label(root, _hud_hint_text(), 15, SystemUI.TEXT_DIM)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 32
	hint.offset_right = -32
	hint.offset_top = -45
	hint.offset_bottom = -12
	hint_bar = hint
	# 乐园提示：屏幕正中偏下，高过左下状态框与右下快捷栏，不与两者抢位置。
	message = _label(root, "", 24, SystemUI.ACCENT)
	message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	message.offset_left = 560
	message.offset_right = -560
	message.offset_top = -262
	message.offset_bottom = -214
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# 交互提示：贴底、夹在状态框与快捷栏之间，只在进圈时出现，离开或按下操作就消失
	prompt = _label(root, "", 22, Color("ffe58a"))
	prompt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_left = 440
	prompt.offset_right = -900
	prompt.offset_top = -96
	prompt.offset_bottom = -56
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.hide()
	_build_story_banner(root)
	GameState.message.connect(_on_message)
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.025, 0.05, 0.09, 0.9)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(850, 0)
	panel.add_theme_constant_override("separation", 30)
	center.add_child(panel)
	panel_title = _label(panel, "", 46, SystemUI.ACCENT)
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_body = _label(panel, "", 24)
	panel_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action_button = Button.new()
	action_button.custom_minimum_size.y = 64
	action_button.add_theme_font_size_override("font_size", 26)
	SystemUI.style_button(action_button)
	panel.add_child(action_button)
	overlay.hide()  # 默认收起，由 show_panel 打开；港口等无面板场景直接复用 HUD
	_build_dialogue_box(root)
	_build_key_guide(root)
	_build_menu(root)
	_build_char_panel(root)
	_build_quest_panel()
	_build_settings_panel()
	_build_test_panel()
	_build_boss_bar(root)
	_build_cursor(root)
	GameSettings.changed.connect(_on_settings_changed)
	if campaign_controller:
		hint_bar.text = _hud_hint_text()
		for control in [overlay, dialogue_box, menu, char_panel, key_guide, settings_panel, test_panel]:
			control.visibility_changed.connect(campaign_controller.sync_pause)

## 玩家身份独立放在左上，资源、目标与快捷动作各占固定区域，战斗时扫视路线更稳定。
func _build_player_badge(root: Control) -> void:
	var frame := PanelContainer.new()
	frame.position = Vector2(32, 20)
	frame.custom_minimum_size = Vector2(372, 56)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", SystemUI.flat(Color(SystemUI.BG, 0.88), Color(SystemUI.BORDER, 0.62), 1, SystemUI.RADIUS, 14))
	root.add_child(frame)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(row)
	header = _label(row, "契约者 / 独立试炼", 21, SystemUI.ACCENT)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	SystemUI.decor(frame)

## 当前任务固定在右上，按名称、简要内容、快捷键分层呈现。
func _build_objective(root: Control) -> void:
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_left = -452
	frame.offset_right = -32
	frame.offset_top = 20
	frame.offset_bottom = 230
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", SystemUI.flat(Color(SystemUI.BG, 0.88), Color(SystemUI.BORDER, 0.62), 1, SystemUI.RADIUS, 14))
	root.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)
	_label(box, "任务名称", 12, SystemUI.TEXT_DIM)
	objective_name = _label(box, "战斗试炼 / 等待开始", 20, SystemUI.GOLD)
	objective_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(box, "任务简要内容", 12, SystemUI.TEXT_DIM)
	objective = _label(box, "", 15, Color("ebd6a2"))
	objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective.size_flags_vertical = Control.SIZE_EXPAND_FILL
	objective.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_shortcut = _label(box, _task_shortcut_text(), 14, SystemUI.TEXT_DIM)
	SystemUI.decor(frame)

func _hud_hint_text() -> String:
	return KeyBindings.line([
		{"binds": ["move_up", "move_left", "move_down", "move_right"], "desc": "移动"},
		{"bind": "interact", "desc": "交互"},
		{"bind": "quest_log", "desc": "任务"},
		{"bind": "open_menu", "desc": "菜单"},
		{"bind": "key_guide", "desc": "操作说明"},
	])

func _ensure_test_panel_action() -> void:
	if not InputMap.has_action("test_panel"):
		InputMap.add_action("test_panel")
	if InputMap.action_get_events("test_panel").is_empty():
		var event := InputEventKey.new()
		event.physical_keycode = KEY_F2
		InputMap.action_add_event("test_panel", event)

## 设置改动后要同步的地方：底部提示、快捷栏和 F1 说明的键名都要跟着改键刷新，
## 改键后必须重算，否则玩家看到的是旧键（设置页自己会重画，不用管）。
## 画面/声音/游玩三项由 GameSettings 自己即时套用，HUD 无需再做什么。
func _on_settings_changed(section: String) -> void:
	if section != "keys":
		return
	hint_bar.text = _hud_hint_text()
	objective_shortcut.text = _task_shortcut_text()
	for row in _guide_lines:
		row["label"].text = KeyBindings.line(row["items"])
	for row in _guide_keys:
		row["label"].text = KeyBindings.keys_of(row["item"])
	status_hud.refresh_keys()

func _process(_delta: float) -> void:
	# 按下操作键就自动收起说明与剧情条，避免长时间挡住视野
	if key_guide.visible and _player_action_pressed():
		key_guide.hide()
	if story_banner.visible and _player_action_pressed():
		story_banner.hide()
	_sync_mouse_mode()

## 当前是否该用游戏内光标：设置里选了系统光标、或有任何模态面板开着时都不是。
func wants_game_cursor() -> bool:
	return bool(GameSettings.game_cursor) and not is_modal_open()

## 战斗中用游戏内光标，隐藏系统光标；结算面板 / Esc 菜单 / C 角色面板 / 商店 / 任务面板 / 设置
## 打开时交还系统光标。设置里选了「系统光标」的玩家一律不隐藏 —— 那是他明确要的手感。
func _sync_mouse_mode() -> void:
	var wanted := Input.MOUSE_MODE_HIDDEN if wants_game_cursor() else Input.MOUSE_MODE_VISIBLE
	if Input.get_mouse_mode() != wanted:
		Input.set_mouse_mode(wanted)
	_update_cursor()

## 游戏内光标：一枚剑刃指针贴图，剑尖对准鼠标位置；用系统光标时同步收起。
func _build_cursor(parent: Control) -> void:
	cursor = TextureRect.new()
	cursor.texture = CursorTexture
	# 像素素材按最近邻采样，换分辨率也保持硬边
	cursor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.hide()
	parent.add_child(cursor)

func _update_cursor() -> void:
	var shown := Input.get_mouse_mode() == Input.MOUSE_MODE_HIDDEN
	cursor.visible = shown
	if shown:
		cursor.position = get_viewport().get_mouse_position() - CURSOR_TIP

func _exit_tree() -> void:
	# 离开关卡（回选关面板等）时恢复系统光标，别把它留在隐藏状态
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## F1 开关按键说明面板，F2 开测试面板，Esc 开关菜单，C 开角色面板，J 开任务面板。
func _unhandled_input(event: InputEvent) -> void:
	# 设置面板是最上一层模态：开着时独占 open_menu（Esc），先关它而不是顺手翻下面的菜单。
	# 面板自己的 Esc 兜底在 settings_panel._input 里（改键把 open_menu 移走时用那条）。
	if _settings_open():
		if event.is_action_pressed("open_menu"):
			settings_panel.close()
			get_viewport().set_input_as_handled()
		return
	if test_panel.visible:
		if event.is_action_pressed("test_panel") or event.is_action_pressed("open_menu"):
			test_panel.hide()
			get_viewport().set_input_as_handled()
		return
	if dialogue_box.visible:
		if event.is_action_pressed("open_menu") or event.is_action_pressed("ui_cancel"):
			close_dialogue()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
				or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
			_advance_dialogue()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("test_panel"):
		open_test_panel()
		get_viewport().set_input_as_handled()
		return
	if campaign_controller and event.is_action_pressed("open_menu") and (overlay.visible or char_panel.visible or key_guide.visible):
		hide_panel()
		char_panel.hide()
		key_guide.hide()
		get_viewport().set_input_as_handled()
		return
	if campaign_controller and overlay.visible:
		return
	# 任务面板的开关与退出都收在这一处：面板自己不消费输入，避免和下面的 elif 链抢同一个按键。
	# 轮回商店有自己的 Esc/V 关法与玩家冻结，它开着时不叠面板（否则两个模态抢同一只鼠标）。
	if event.is_action_pressed("quest_log"):
		if not _shop_open():
			toggle_quest_log()
		get_viewport().set_input_as_handled()
		return
	if quest_panel.visible and event.is_action_pressed("open_menu"):
		close_quest_log()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("key_guide"):
		key_guide.visible = not key_guide.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_menu"):
		menu.visible = not menu.visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("character_panel"):
		menu.hide()
		char_panel.visible = not char_panel.visible
		if char_panel.visible:
			_refresh_char_panel()
		get_viewport().set_input_as_handled()

## 贴底交互提示：由传送门等场景元素驱动，离开触发区就收起。
func show_prompt(text: String, locked := false) -> void:
	prompt.text = text
	prompt.add_theme_color_override("font_color", Color("ff9a6a") if locked else Color("ffe58a"))
	prompt.show()

func hide_prompt() -> void:
	prompt.hide()

## 进关剧情条：置于上方两块角落 HUD 之间，按任意操作键自动收起。
## 代替旧的全屏剧情弹窗——弹窗会冻结玩家且遮住战斗画面。
func _build_story_banner(root: Control) -> void:
	story_banner = PanelContainer.new()
	story_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	story_banner.offset_top = 194
	story_banner.offset_bottom = 304
	story_banner.offset_left = 32
	story_banner.offset_right = -32
	story_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := SystemUI.flat(Color(SystemUI.BG_BLOCK, 0.8), Color(SystemUI.BORDER, 0.4), 1, SystemUI.RADIUS, 16)
	story_banner.add_theme_stylebox_override("panel", st)
	story_banner.hide()
	root.add_child(story_banner)
	story_body = _label(story_banner, "", 17, SystemUI.TEXT)
	story_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func show_story(title: String, text: String) -> void:
	story_body.text = "[%s]\n%s" % [title, text]
	story_banner.show()

func hide_story() -> void:
	story_banner.hide()

## 是否按下了任一操作键（自动收起按键说明用）。
func _player_action_pressed() -> bool:
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "dodge", "kick", "interact", "open_menu", "bomb", "potion", "hunter_toggle", "aoge", "huanduan", "sword_wave", "shadow_stab"]:
		if InputMap.has_action(action) and Input.is_action_just_pressed(action):
			return true
	return false

## 按键说明面板：挂在 HUD 上，试炼、港口与科尔波山两关共用同一份键位表。
func _build_key_guide(root: Control) -> void:
	key_guide = Control.new()
	key_guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	key_guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(key_guide)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key_guide.add_child(center)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP  # 点面板本身不触发攻击，面板外仍可正常操作
	card.add_theme_stylebox_override("panel", _card_style())
	SystemUI.decor(card)
	center.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	card.add_child(page)
	_label(page, "按键映射 / 苏晓", 30, SystemUI.ACCENT)
	if campaign_controller:
		# 四行键位都由 KeyBindings 现读，改键后 _on_settings_changed 会重算这些 Label。
		for items in KeyBindings.CAMPAIGN_GUIDE_LINES:
			_guide_lines.append({"label": _label(page, KeyBindings.line(items), 23), "items": items})
		_label(page, "刀芒沿鼠标方向发射；普通斩击标记目标后，%s 影刺可突进至 4 米内目标。" % KeyBindings.key_text("shadow_stab"), 21)
		_label(page, "山之主眩晕时陷入短暂硬直；小怪眩晕后按 %s 直踹处决。" % KeyBindings.key_text("kick"), 21)
		_label(page, "%s 关闭说明。科尔波山保留原外围三波和决战15秒准备。" % KeyBindings.key_text("key_guide"), 20)
		key_guide.hide()
		return
	_label(page, "按键显示名随设置同步；标「%s」的功能尚未接入，底部提示条只列当前可用操作。" % KeyBindings.status_text(KeyBindings.PLANNED), 17, SystemUI.TEXT_DIM)
	var halves := HBoxContainer.new()
	halves.add_theme_constant_override("separation", 52)
	page.add_child(halves)
	var left := VBoxContainer.new()
	var right := VBoxContainer.new()
	for column in [left, right]:
		column.add_theme_constant_override("separation", 4)
		halves.add_child(column)
	var split := int(ceil(KeyBindings.GROUPS.size() / 2.0))
	for i in KeyBindings.GROUPS.size():
		_guide_group(left if i < split else right, KeyBindings.GROUPS[i])
	_label(page, "F1 开关本说明 · 按下移动或攻击会自动收起", 17, SystemUI.TEXT_DIM)
	key_guide.hide()

func _guide_group(column: Node, group: Dictionary) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	column.add_child(spacer)
	_label(column, group["title"], 21, Color("ebd6a2"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for entry in group["entries"]:
		var keys := _label(grid, KeyBindings.keys_of(entry), 19, Color("ffd9a0"))
		keys.custom_minimum_size.x = 118
		_guide_keys.append({"label": keys, "item": entry})
		var action := _label(grid, entry["desc"], 19)
		action.custom_minimum_size.x = 452
		var status := _label(grid, KeyBindings.status_text(entry["status"]), 17, KeyBindings.status_color(entry["status"]))
		status.custom_minimum_size.x = 56
		# 现状提示：键位与新表不一致时，说明当前按出来是什么
		if entry.has("now"):
			_label(grid, "", 16)
			_label(grid, entry["now"], 16, Color("b08a5a"))
			_label(grid, "", 16)

## Esc 菜单：任何关卡里都能一键回选关面板，避免进了场景出不来。
func _build_menu(root: Control) -> void:
	menu = Control.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_STOP if campaign_controller else Control.MOUSE_FILTER_IGNORE
	root.add_child(menu)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(center)
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _card_style())
	SystemUI.decor(card)
	center.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	card.add_child(page)
	_label(page, "[轮回乐园] · 行动菜单", 30, SystemUI.ACCENT)
	var back := Button.new()
	back.text = "保存检查点并返回主菜单" if campaign_controller else "返回选关"
	back.custom_minimum_size = Vector2(420, 58)
	back.add_theme_font_size_override("font_size", 24)
	SystemUI.style_button(back)
	back.pressed.connect(_back_to_select)
	page.add_child(back)
	# 设置对两种场景都在同一位置（战斗关卡与只看地图的场景），所以不进上面的分支。
	var settings_button := Button.new()
	settings_button.text = "设 置 · 画面 / 声音 / 按键"
	settings_button.custom_minimum_size = Vector2(420, 54)
	settings_button.add_theme_font_size_override("font_size", 24)
	SystemUI.style_button(settings_button)
	settings_button.pressed.connect(_open_settings)
	page.add_child(settings_button)
	var test_button := Button.new()
	test_button.text = "开发者测试面板 · F2"
	test_button.custom_minimum_size = Vector2(420, 50)
	test_button.add_theme_font_size_override("font_size", 21)
	SystemUI.style_button(test_button)
	test_button.pressed.connect(open_test_panel)
	page.add_child(test_button)
	if campaign_controller:
		var tasks := Button.new()
		tasks.text = "任务档案 · 阶段进度"
		tasks.custom_minimum_size.y = 50
		SystemUI.style_button(tasks)
		tasks.pressed.connect(open_quest_log)
		page.add_child(tasks)
		if campaign_controller.state == "practice":
			var back_hub := Button.new()
			back_hub.text = "结束练习 · 返回灰潮港"
			back_hub.custom_minimum_size.y = 50
			SystemUI.style_button(back_hub)
			back_hub.pressed.connect(campaign_controller.return_from_practice)
			page.add_child(back_hub)
	elif get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://scenes/world/harbor.tscn":
		var harbor_button := Button.new()
		harbor_button.text = "返回灰潮港口"
		harbor_button.custom_minimum_size = Vector2(420, 58)
		harbor_button.add_theme_font_size_override("font_size", 24)
		SystemUI.style_button(harbor_button)
		harbor_button.pressed.connect(func(): GameState.change_scene("res://scenes/world/harbor.tscn"))
		page.add_child(harbor_button)
	_label(page, "Esc 关闭菜单 · 检查点自动保存", 17, SystemUI.TEXT_DIM)
	menu.hide()

## Esc 菜单里的「设置」入口。设置面板是独立的一层 CanvasLayer（layer 45），
## 开在菜单之上；关掉设置后菜单保持收起，再按一次 Esc 才回到菜单。
func _open_settings() -> void:
	menu.hide()
	settings_panel.open()

## 设置面板：脚本自建（见 settings_panel.gd），与任务面板同一套做法 ——
## 面板自己管显隐，HUD 只负责「谁算模态」与按键路由。
func _build_settings_panel() -> void:
	settings_panel = SettingsPanelScript.new()
	settings_panel.name = "SettingsPanel"
	add_child(settings_panel)

func _build_test_panel() -> void:
	test_panel = TestPanelScript.new()
	test_panel.player = player
	test_panel.managed_pause = campaign_controller != null
	add_child(test_panel)

func open_test_panel() -> void:
	if test_panel == null or _settings_open() or overlay.visible or quest_panel.visible or _shop_open():
		return
	# 先打开测试层再收菜单，战役里的暂停状态不会闪一下恢复。
	test_panel.open()
	menu.hide()
	char_panel.hide()
	key_guide.hide()

func _settings_open() -> bool:
	return settings_panel != null and settings_panel.visible

## C 键角色面板：左右两大块 —— 左侧为 DNF 参考图排版（穿戴栏 + 8×8 背包，
## 背包格支持悬停高亮与点选），右侧为属性面板（六维 + 派生值 + 可用属性点）。
## 加点列为「主城加点装置」后置功能，此处只展示数值，不做分配。
func _build_char_panel(root: Control) -> void:
	char_panel = Control.new()
	char_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	char_panel.mouse_filter = Control.MOUSE_FILTER_STOP if campaign_controller else Control.MOUSE_FILTER_IGNORE
	root.add_child(char_panel)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	char_panel.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1010, 900)
	card.mouse_filter = Control.MOUSE_FILTER_STOP  # 点面板本身不触发攻击
	card.add_theme_stylebox_override("panel", _card_style())
	SystemUI.decor(card)
	center.add_child(card)
	var halves := HBoxContainer.new()
	halves.add_theme_constant_override("separation", 44)
	halves.alignment = BoxContainer.ALIGNMENT_CENTER
	halves.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(halves)

	# ---- 左大块（底衬面板）：DNF 排版 穿戴栏 + 背包 ----
	var left_panel := PanelContainer.new()
	left_panel.add_theme_stylebox_override("panel", _panel_style())
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	halves.add_child(left_panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.alignment = BoxContainer.ALIGNMENT_CENTER
	left_panel.add_child(left)
	var wear_title := _label(left, "穿 戴 栏", 18, Color("e8c87a"))
	wear_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var wear := HBoxContainer.new()
	wear.add_theme_constant_override("separation", 28)
	wear.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(wear)
	# 左翼（防具系 6 槽）：头部 / 躯干 / 护臂·左 / 护臂·右 / 足部 / 披风
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 16)
	left_col.alignment = BoxContainer.ALIGNMENT_CENTER
	wear.add_child(left_col)
	for name in ["头部", "躯干", "护臂 · 左", "护臂 · 右", "足部", "披风"]:
		_make_slot(left_col, name, 50.0)
	char_portrait = TextureRect.new()
	char_portrait.texture = PlayerFrames.get_frame_texture("idle_down", 0)
	char_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # 像素风放大保持硬边
	char_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	char_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	char_portrait.custom_minimum_size = Vector2(160, 280)
	wear.add_child(char_portrait)
	# 右翼（武器与首饰 5 槽）：主武器 / 副武器 / 项链 / 戒指 / 戒指Ⅱ
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 16)
	right_col.alignment = BoxContainer.ALIGNMENT_CENTER
	wear.add_child(right_col)
	for name in ["主武器", "副武器", "项链", "戒指", "戒指Ⅱ"]:
		_make_slot(right_col, name, 50.0)
	_build_bag_section(left)

	# ---- 右大块（底衬面板）：属性 ----
	var right_panel := PanelContainer.new()
	right_panel.add_theme_stylebox_override("panel", _panel_style())
	right_panel.custom_minimum_size.x = 356
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	halves.add_child(right_panel)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 320
	right.add_theme_constant_override("separation", 8)
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_child(right)
	var aname := _label(right, "契约者 · %s" % GameState.player_name, 17, SystemUI.TEXT)
	aname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var atitle := _label(right, "角色属性 / 六维", 24, SystemUI.ACCENT)
	atitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rule := HSeparator.new()
	rule.custom_minimum_size = Vector2(240, 2)
	right.add_child(rule)
	for key in Attributes.ALL_KEYS:
		var line := _label(right, "", 21)
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		char_attr_labels[key] = line
	char_derived_label = _label(right, "", 15, SystemUI.TEXT_DIM)
	char_derived_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_derived_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	right.add_child(spacer)
	char_points_label = _label(right, "", 22, Color("ffe58a"))
	char_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var note := _label(right, "属性加点需前往主城 · 加点装置", 13, SystemUI.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if campaign_controller:
		note.text = "强化请前往灰潮港 · 铸潮工坊\nC / Esc 关闭角色面板"
		item_detail = _label(right, "点击物品格查看详情", 18, Color("ebd6a2"))
		item_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item_detail.custom_minimum_size = Vector2(300, 150)
		item_action = Button.new()
		item_action.text = "选择物品"
		item_action.custom_minimum_size.y = 48
		SystemUI.style_button(item_action)
		item_action.pressed.connect(func():
			if _selected_slot != "":
				GameState.unequip_item(_selected_slot)
				_selected_slot = ""
				_selected_item = ""
				campaign_controller._refresh_objective()
			else:
				campaign_controller.use_item(_selected_item)
			_refresh_char_panel())
		right.add_child(item_action)
	GameState.attributes_changed.connect(_refresh_char_panel)
	_refresh_char_panel()

	char_panel.hide()

## 刷新角色面板：六维数值、派生值、可用属性点。
func _refresh_char_panel() -> void:
	var a: Dictionary = GameState.effective_attributes() if campaign_controller else GameState.debug_attributes()
	for key in Attributes.ALL_KEYS:
		char_attr_labels[key].text = "%s    %d" % [Attributes.CN_NAMES[key], int(a.get(key, Attributes.BASE))]
	char_derived_label.text = "攻击 %d  ·  最大HP %d  ·  最大MP %d  ·  移速 %.1f" % [
		int(Attributes.attack(a)), int(Attributes.max_hp(a)),
		int(Attributes.max_mp(a)), Attributes.move_speed(a)]
	char_points_label.text = "可用属性点  %d" % GameState.get_attr_points()
	if campaign_controller:
		char_derived_label.text = "攻击 %.0f · 最大生命 %.0f\n最大法力 %.0f · 刀术训练 Lv.%d\n乐园币 %d" % [player.attack_damage, player.max_hp, player.max_mp, GameState.campaign.training, GameState.coins]
		_refresh_inventory()

## 生成一个装备空槽：深底描边面板 + 部位名，追加到容器并返回以便装备系统填充。
## size 控制槽边长；穿戴栏用紧凑尺寸（44），背包格另建小格。
func _make_slot(parent: Node, slot_name: String, size := 92.0) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(size, size)
	slot.add_theme_stylebox_override("panel", _slot_style())
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.set_meta("slot_key", SLOT_TITLE_MAP.get(slot_name, ""))
	slot.set_meta("slot_title", slot_name)
	var slot_label := Label.new()
	slot_label.text = slot_name
	slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	slot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slot_label.add_theme_font_size_override("font_size", int(minf(14, size * 0.3)))
	slot_label.add_theme_color_override("font_color", SystemUI.TEXT_DIM)
	slot.add_child(slot_label)
	slot.gui_input.connect(_slot_input.bind(slot))
	parent.add_child(slot)
	equipment_slots[slot_name] = slot
	return slot

## 点击穿戴槽：选中已穿戴物品 → 详情切换为「卸下」操作。
func _slot_input(event: InputEvent, slot: PanelContainer) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var key := str(slot.get_meta("slot_key", ""))
	_selected_slot = key if key != "" and str(GameState.campaign.equipment.get(key, "")) != "" else ""
	_selected_item = str(GameState.campaign.equipment.get(key, "")) if _selected_slot != "" else ""
	_refresh_item_detail()

## 下段背包网格（DNF 式）：标题 + 8 列 × 8 行 = 64 格，装备系统接入后填充。
## 交互：悬停亮边提示、左键点选高亮（再点取消），为后续拾取/装卸做准备。
const BAG_BORDER := Color(SystemUI.BORDER, 0.42)
const BAG_HOVER := Color("f3c452")
const BAG_SELECTED := SystemUI.GOLD

func _build_bag_section(parent: Node) -> void:
	var title := _label(parent, "物品栏 · 装备", 18, SystemUI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(grid)
	for i in 64:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(55, 55)  # 物品栏为主体（2/3 占比），背包装备大格
		var st := _slot_style()
		st.set_corner_radius_all(SystemUI.RADIUS)
		st.set_content_margin_all(0)
		st.set_border_width_all(1)
		cell.add_theme_stylebox_override("panel", st)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP  # 可交互：不吃透传给战斗输入
		cell.mouse_entered.connect(_bag_cell_hover.bind(cell, true))
		cell.mouse_exited.connect(_bag_cell_hover.bind(cell, false))
		cell.gui_input.connect(_bag_cell_input.bind(cell))
		grid.add_child(cell)
		bag_cells.append(cell)
		if campaign_controller:
			var text := _label(cell, "", 12)
			text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

## 悬停：非选中格亮金边；选中格保持选中色，不受悬停影响。
func _bag_cell_hover(cell: PanelContainer, entered: bool) -> void:
	if cell == _selected_bag:
		return
	_set_bag_border(cell, BAG_HOVER if entered else BAG_BORDER)

## 左键点选/取消背包格：单选高亮，再点同一格取消。
func _bag_cell_input(event: InputEvent, cell: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if campaign_controller:
			_selected_item = str(cell.get_meta("item_id", ""))
			_refresh_item_detail()
		if _selected_bag == cell:
			_selected_bag = null
			_set_bag_border(cell, BAG_BORDER)
		else:
			if _selected_bag != null:
				_set_bag_border(_selected_bag, BAG_BORDER)
			_selected_bag = cell
			_set_bag_border(cell, BAG_SELECTED)

func _set_bag_border(cell: PanelContainer, color: Color) -> void:
	var st := cell.get_theme_stylebox("panel")
	if st is StyleBoxFlat:
		st.border_color = color

## 分块底衬样式：左右两大块的深色面板区，制造面板的板块感。
func _panel_style() -> StyleBoxFlat:
	return SystemUI.sub()

## 装备槽样式：深底 + 细描边 + 圆角，空槽只显示部位名。
func _slot_style() -> StyleBoxFlat:
	return SystemUI.slot()

func _back_to_select() -> void:
	if campaign_controller:
		campaign_controller.leave()
		return
	GameState.change_scene(GameState.LEVEL_SELECT_SCENE)

## BOSS 血条：挂在屏幕顶部中间，同时显示阶段（P1 / P2 / P3），方便读阶段门槛。
func _build_boss_bar(root: Control) -> void:
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	boss_box.offset_top = 24
	boss_box.offset_bottom = 92
	boss_box.add_theme_constant_override("separation", 6)
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boss_box)
	boss_name = _label(boss_box, "", 22, Color("ffd0a0"))
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(760, 20)
	boss_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	boss_bar.show_percentage = false
	boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := SystemUI.track()
	boss_bar.add_theme_stylebox_override("background", back)
	boss_bar.add_theme_stylebox_override("fill", SystemUI.fill(Color("c04b36")))
	boss_box.add_child(boss_bar)
	boss_box.hide()

func show_boss(title: String, maximum: float) -> void:
	boss_title = title
	boss_bar.max_value = maximum
	boss_bar.value = maximum
	boss_name.text = title
	boss_box.show()

func set_boss_state(current: float, phase_text: String) -> void:
	boss_bar.value = current
	boss_name.text = "%s · %s" % [boss_title, phase_text]

func hide_boss() -> void:
	boss_box.hide()

func _card_style() -> StyleBoxFlat:
	return SystemUI.card()

func _label(parent: Node, text: String, font_size: int, color := SystemUI.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# 深色描边，保证文字在港口明亮石板与试炼暗地面上都读得清
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.92))
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	return label

## 复用 HUD 到其他场景时替换文案；task_name 留空时沿用场景标题。
func configure(header_text: String, objective_text: String = "", task_name: String = "") -> void:
	header.text = header_text
	objective_name.text = task_name if task_name != "" else header_text
	objective.text = objective_text

func _task_shortcut_text() -> String:
	return "快捷键  %s  打开任务档案" % KeyBindings.key_text("quest_log")

## 右上任务栏的动态简要内容：波次推进、剩余目标数等都由它更新。
func set_objective(text: String) -> void:
	objective.text = text

func show_panel(title: String, body: String, button: String, callback: Callable) -> void:
	if dialogue_box != null and dialogue_box.visible:
		close_dialogue(false)
	for extra in _choice_buttons:
		if is_instance_valid(extra):
			extra.get_parent().remove_child(extra)
			extra.queue_free()
	_choice_buttons.clear()
	panel_title.text = title
	panel_body.text = body
	action_button.text = button
	for connection in action_button.pressed.get_connections():
		action_button.pressed.disconnect(connection.callable)
	action_button.pressed.connect(callback)
	overlay.show()
	action_button.grab_focus()

func _build_dialogue_box(root: Control) -> void:
	dialogue_box = DialogueBoxScript.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialogue_box.z_index = 20
	dialogue_box.hide()
	root.add_child(dialogue_box)

func show_dialogue(speaker: String, pages: Array, callback: Callable = Callable()) -> void:
	if pages.is_empty():
		if callback.is_valid():
			callback.call()
		return
	if dialogue_box.visible:
		close_dialogue(false)
	hide_panel()
	menu.hide()
	key_guide.hide()
	char_panel.hide()
	_dialogue_restore_prompt = prompt.visible
	_dialogue_restore_hint_bar = hint_bar.visible
	prompt.hide()
	hint_bar.hide()
	_dialogue_pages.clear()
	for page in pages:
		_dialogue_pages.append(str(page))
	_dialogue_speaker = speaker
	_dialogue_page_index = 0
	_dialogue_callback = callback
	_update_dialogue_page()
	dialogue_box.show()
	if campaign_controller:
		campaign_controller.sync_pause()

func _update_dialogue_page() -> void:
	var hint := "%s / 空格 / 点击 继续" % KeyBindings.key_text("interact")
	dialogue_box.call("set_dialogue", _dialogue_speaker, _dialogue_pages[_dialogue_page_index], hint)

func _advance_dialogue() -> void:
	_dialogue_page_index += 1
	if _dialogue_page_index < _dialogue_pages.size():
		_update_dialogue_page()
		return
	close_dialogue()

func close_dialogue(run_callback := true) -> void:
	if dialogue_box == null or not dialogue_box.visible:
		return
	dialogue_box.hide()
	_dialogue_pages.clear()
	_dialogue_page_index = 0
	if _dialogue_restore_prompt:
		prompt.show()
	if _dialogue_restore_hint_bar:
		hint_bar.show()
	_dialogue_restore_prompt = false
	_dialogue_restore_hint_bar = false
	var callback := _dialogue_callback
	_dialogue_callback = Callable()
	if campaign_controller:
		campaign_controller.sync_pause()
	if run_callback and callback.is_valid():
		callback.call()

func hide_panel() -> void:
	action_button.release_focus()
	overlay.hide()

## 轮回商店面板打开中（面板自己管理显隐与输入）。
func _shop_open() -> bool:
	var panel: Node = get_tree().get_first_node_in_group("shop_panel")
	return panel != null and panel.visible

func is_modal_open() -> bool:
	return overlay.visible or dialogue_box.visible or menu.visible or char_panel.visible or key_guide.visible or test_panel.visible or _shop_open() or quest_panel.visible or _settings_open()

func show_character() -> void:
	menu.hide()
	hide_panel()
	_refresh_char_panel()
	char_panel.show()

## J 键任务面板：数据只读（data/quest_log.gd），这里只管开关与「开它之前先收起别的面板」。
func _build_quest_panel() -> void:
	quest_panel = QuestPanelScript.new()
	quest_panel.name = "QuestPanel"
	add_child(quest_panel)

func open_quest_log() -> void:
	open_quest_log_with("", Callable())

## 带底栏动作的版本：灰潮港「港务委托所」这类入口用它 —— 打开档案的同时还能把任务接下来。
func open_quest_log_with(action_text: String, action: Callable) -> void:
	menu.hide()
	char_panel.hide()
	key_guide.hide()
	hide_panel()
	quest_panel.open(action_text, action)

func close_quest_log() -> void:
	quest_panel.close()

func toggle_quest_log() -> void:
	if quest_panel.visible:
		close_quest_log()
	else:
		open_quest_log()

func add_choice(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", 22)
	SystemUI.style_button(button)
	button.pressed.connect(action)
	var column := action_button.get_parent()
	column.add_child(button)
	column.move_child(button, action_button.get_index())
	_choice_buttons.append(button)
	return button

const SHORT_ITEMS := {"knife": "匕首", "flintlock": "燧发枪", "letter": "引荐信", "guard_badge": "侍卫证", "dragon": "斩龙闪", "pendant": "亡妻\n项坠", "potion": "药剂", "trap": "火药\n陷阱", "catnip": "木天芷", "tiger_tooth": "虎齿", "claw": "虎爪", "crystal": "灵魂\n结晶", "white_mat": "白锻材", "green_mat": "绿锻材", "blue_mat": "蓝锻材", "purple_mat": "紫锻材", "gold_mat": "淡金\n锻材", "carlos_chest": "商人\n白箱", "oka_chest": "欧卡\n白箱", "tiger_chest": "巨虎\n绿箱", "worn_blade": "缺口刀", "iron_sword": "精铁刀", "leather_cap": "皮护额", "hunter_hat": "猎户帽", "ragged_vest": "褴褛甲", "leather_bracer": "皮护臂", "worn_boots": "旧皮靴", "tattered_cloak": "破披风", "copper_ring": "铜戒指"}

## 词条摘要文本（详情与 tooltip 复用）。
func _stats_text(def: Dictionary) -> String:
	var parts: Array[String] = []
	for key in def.get("stats", {}):
		parts.append("%s+%d" % [Attributes.CN_NAMES.get(key, key), int(def["stats"][key])])
	var pct := float(def.get("def_pct", 0.0))
	if pct > 0.0:
		parts.append("减免+%d%%" % int(pct * 100))
	if def.has("attack_min"):
		parts.append("攻击%.0f~%.0f" % [def.attack_min, def.attack_max])
	return " · ".join(parts) if not parts.is_empty() else ""

func _refresh_inventory() -> void:
	var ids: Array = []
	for id in GameState.campaign.bag:
		if GameState.item_count(id) > 0: ids.append(id)
	for i in bag_cells.size():
		var cell := bag_cells[i]
		var id: String = ids[i] if i < ids.size() else ""
		cell.set_meta("item_id", id)
		var label: Label = cell.get_child(0)
		if id == "":
			cell.tooltip_text = "空格"
			label.text = ""
			_set_cell_quality(cell, BAG_BORDER)
		else:
			var def := GameState.item_def(id)
			cell.tooltip_text = _item_tooltip(id, def)
			label.text = "%s\n×%d" % [SHORT_ITEMS.get(id, id), GameState.item_count(id)]
			_set_cell_quality(cell, GameState.Equip.quality_color(def.get("quality", "white")))
	for title in equipment_slots:
		var slot: PanelContainer = equipment_slots[title]
		var key: String = SLOT_TITLE_MAP[title]
		var id: String = str(GameState.campaign.equipment.get(key, ""))
		var label: Label = slot.get_child(0)
		if id == "":
			label.text = title
			label.add_theme_color_override("font_color", SystemUI.TEXT_DIM)
			slot.tooltip_text = title
			_set_slot_quality(slot, Color(0.30, 0.45, 0.55, 0.45))
		else:
			var def := GameState.item_def(id)
			label.text = SHORT_ITEMS.get(id, id)
			label.add_theme_color_override("font_color", GameState.Equip.quality_color(def.get("quality", "white")))
			slot.tooltip_text = _item_tooltip(id, def)
			_set_slot_quality(slot, GameState.Equip.quality_color(def.get("quality", "white")))
	_refresh_item_detail()

func _item_tooltip(id: String, def: Dictionary) -> String:
	var st: Dictionary = GameState.Campaign.dura_state(GameState.campaign, id)
	var lvl := GameState.Campaign.enhance_level(GameState.campaign, id)
	var dur := ("耐久 %d/%d" % [int(st["cur"]), int(st["max"])]) if int(st["max"]) > 0 else "无耐久"
	var reset := "" if GameState.item_count(id) > 0 else "[待补充]"
	return "%s\n%s · 评分 %d · 强化 +%d%s\n%s\n%s" % [
		def.get("name", id), GameState.Equip.quality_cn(def.get("quality", "white")),
		int(def.get("score", 0)), lvl, reset, _stats_text(def), dur]

## 品质配色：设置背包格/穿戴槽描边颜色（悬停/选中逻辑保持互斥）。
func _set_cell_quality(cell: PanelContainer, color: Color) -> void:
	var st := cell.get_theme_stylebox("panel")
	if st is StyleBoxFlat:
		st.border_color = color

func _set_slot_quality(slot: PanelContainer, color: Color) -> void:
	var st := slot.get_theme_stylebox("panel")
	if st is StyleBoxFlat:
		st.border_color = color

func _refresh_item_detail() -> void:
	if item_detail == null: return
	if _selected_item == "" or GameState.item_count(_selected_item) <= 0:
		item_detail.text = "点击背包格查看物品\n点击穿戴栏可卸下装备\n清场或备战时可开箱、换装"
		item_action.disabled = true
		item_action.text = "选择物品"
		return
	var def: Dictionary = GameState.item_def(_selected_item)
	var st: Dictionary = GameState.Campaign.dura_state(GameState.campaign, _selected_item)
	var lvl := GameState.Campaign.enhance_level(GameState.campaign, _selected_item)
	var dur := ("耐久 %d / %d" % [int(st["cur"]), int(st["max"])]) if int(st["max"]) > 0 else "无耐久属性"
	var exit_txt: String = "可带出世界" if def.get("export", false) else "本世界限定（结束清除）"
	item_detail.text = "%s\n%s · 评分 %d · 强化 +%d\n%s\n%s\n%s" % [
		def.get("name", _selected_item), GameState.Equip.quality_cn(def.get("quality", "white")),
		int(def.get("score", 0)), lvl, _stats_text(def), dur, exit_txt]
	if _selected_slot != "":
		item_action.text = "卸下（回背包）"
		item_action.disabled = not campaign_controller.can_manage_items()
		return
	var chest := GameState.Campaign.CHESTS.has(_selected_item)
	item_action.text = "开启宝箱" if chest else ("装备" if def.has("slot") else "任务 / 材料 / 消耗品")
	item_action.disabled = not campaign_controller.can_manage_items() or (not chest and not def.has("slot"))

func _on_message(text: String) -> void:
	message.text = text
	message.modulate.a = 1
	if message_tween:
		message_tween.kill()
	message_tween = create_tween()
	message_tween.tween_interval(3)
	message_tween.tween_property(message, "modulate:a", 0, 0.5)
