extends CanvasLayer
const SystemUI := preload("res://scripts/ui/system_ui.gd")
const QuestLog := preload("res://data/quest_log.gd")
## 「任务档案」面板：左侧任务名列表（分章、带状态方块），右侧选中任务的详情
## （状态 / 委托方与地点 / 目标清单 / 说明 / 奖励 / 记录）。
##
## 数据只读，全部来自 data/quest_log.gd —— 那里把存档进度映射成任务表，本面板不写任何状态。
## 打开方式：HUD 里按 J（或在 Esc 菜单点「任务档案」）→ hud.open_quest_log()；
## Esc / J 再按一次退出。加入 "quest_panel" 组，HUD 的 is_modal_open 据此把它当模态面板
## （战役模式随之冻结玩家与敌人，主城无战役控制器时由本面板自己冻结玩家）。

var _selected_id := ""
var _entries: Array = []
var _list: VBoxContainer
var _detail_body: VBoxContainer
var _detail_title: Label
var _detail_status: Label
var _detail_meta: Label
var _detail_brief: Label
var _header_info: Label
var _summary: Label
var _action_button: Button
var _action := Callable()
var _action_text := ""

func _ready() -> void:
	add_to_group("quest_panel")
	layer = 40
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.03, 0.05, 0.8)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1280, 860)
	card.add_theme_stylebox_override("panel", SystemUI.card())
	SystemUI.decor(card)
	center.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	card.add_child(page)

	# ---- 标题条 ----
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	page.add_child(head)
	var title := _label(head, "任 务 档 案", 40, SystemUI.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_info = _label(head, "", 20, SystemUI.GOLD)
	_header_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page.add_child(HSeparator.new())

	# ---- 左右两栏：左 = 任务列表，右 = 任务详情 ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_stylebox_override("panel", SystemUI.sub())
	body.add_child(left)
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left.add_child(left_col)
	var list_title := _label(left_col, "任 务 列 表", 20, SystemUI.GOLD)
	list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(scroll)
	_style_scrollbar(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 5)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	var detail_head := HBoxContainer.new()
	detail_head.add_theme_constant_override("separation", 14)
	right.add_child(detail_head)
	_detail_title = _label(detail_head, "", 30, Color("ffd76e"))
	_detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_status = _label(detail_head, "", 22)
	_detail_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_brief = _label(right, "", 19, SystemUI.GOLD)
	_detail_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_meta = _label(right, "", 17, SystemUI.TEXT_DIM)
	right.add_child(HSeparator.new())
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(detail_scroll)
	_style_scrollbar(detail_scroll)
	_detail_body = VBoxContainer.new()
	_detail_body.add_theme_constant_override("separation", 12)
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail_body)

	# ---- 底栏：操作提示 + 全局进度 + （可选）动作按钮 ----
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	page.add_child(footer)
	var hint := _label(footer, "J / Esc 关闭 · 点选左侧任务查看详情 · ↑↓ 切换任务", 16, SystemUI.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary = _label(footer, "", 18, SystemUI.GOLD)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_action_button = Button.new()
	_action_button.custom_minimum_size = Vector2(300, 52)
	_action_button.add_theme_font_size_override("font_size", 22)
	_action_button.visible = false
	SystemUI.style_button(_action_button)
	_action_button.pressed.connect(_run_action)
	footer.add_child(_action_button)

## 打开时重刷整份档案；上次选中的任务还在就保留（读任务时来回开关不跳位），
## 否则回落到「进行中 → 待交接」的第一条 —— 打开就看得到当前该做什么。
##
## action_text / action：可选底栏动作（例如委托所的「接取任务」）。文本为空 = 纯只读面板；
## 动作由开门方给（战役里是 campaign.show_tasks），面板本身不认识任何流程。
func open(action_text: String = "", action: Callable = Callable()) -> void:
	_action_text = action_text
	_action = action
	visible = true
	_refresh()
	_sync_pause()

func close() -> void:
	visible = false
	_action_text = ""
	_action = Callable()
	_sync_pause()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

## 按下底栏动作：先收起面板（让提示能露出来），再执行 —— 动作通常会把流程往前推一步。
func _run_action() -> void:
	var action := _action
	close()
	if action.is_valid():
		action.call()

## 战役模式交给控制器统一冻结（它按 is_modal_open 一并停敌人与炸弹）；无控制器时自己冻结玩家，
## 否则主城里读面板时 Space 剃、左键斩击仍会被输入映射吃掉。
func _sync_pause() -> void:
	var ctl: Node = get_tree().get_first_node_in_group("campaign_controller")
	if ctl != null and ctl.has_method("sync_pause"):
		ctl.sync_pause()
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		player.set_physics_process(not visible)
		player.set_process_unhandled_input(not visible)

func _refresh() -> void:
	var campaign: Dictionary = GameState.campaign
	_entries = QuestLog.entries(campaign)
	if _selected_id == "" or QuestLog.find(_selected_id, campaign).is_empty():
		_selected_id = QuestLog.default_id(campaign)
	var run := int(campaign.get("run", 1))
	var who := GameState.player_name
	_header_info.text = "轮回 第 %d 轮" % run
	if who != "":
		_header_info.text += " · 契约者 %s" % who
	_refresh_list()
	_refresh_detail()
	_refresh_footer()

func _refresh_list() -> void:
	_clear(_list)
	for group in QuestLog.groups(GameState.campaign):
		var head := _label(_list, str(group["title"]), 19, SystemUI.GOLD)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		for entry in group["entries"]:
			var id := str(entry["id"])
			var status := str(entry["status"])
			var row := Button.new()
			row.text = "%s %s" % [QuestLog.status_mark(status), str(entry["name"])]
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.custom_minimum_size = Vector2(0, 44)
			row.add_theme_font_size_override("font_size", 19)
			_style_row(row, status, id == _selected_id)
			row.pressed.connect(_select.bind(id))
			_list.add_child(row)
			var tag := Label.new()
			tag.text = QuestLog.status_cn(status)
			tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tag.anchor_left = 1.0
			tag.anchor_right = 1.0
			tag.anchor_top = 0.0
			tag.anchor_bottom = 1.0
			tag.offset_left = -92
			tag.offset_right = -12
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tag.add_theme_font_size_override("font_size", 16)
			tag.add_theme_color_override("font_color", QuestLog.status_color(status))
			row.add_child(tag)
			if id == _selected_id:
				row.grab_focus()

func _refresh_detail() -> void:
	var entry := QuestLog.find(_selected_id, GameState.campaign)
	_clear(_detail_body)
	if entry.is_empty():
		_detail_title.text = "未选中任务"
		_detail_status.text = ""
		_detail_meta.text = ""
		_detail_brief.text = ""
		return
	var status := str(entry["status"])
	_detail_title.text = str(entry["name"])
	_detail_status.text = QuestLog.status_cn(status)
	_detail_status.add_theme_color_override("font_color", QuestLog.status_color(status))
	_detail_meta.text = "%s · 委托方 %s · 地点 %s" % [str(entry["kind"]), str(entry["giver"]), str(entry["place"])]
	_detail_brief.text = str(entry["brief"])
	var objectives: Array = entry["objectives"]
	if not objectives.is_empty():
		var col := _section("目 标")
		for obj in objectives:
			var done := bool(obj["done"])
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 8)
			col.add_child(line)
			_label(line, "■" if done else "□", 18, Color("6fdc9a") if done else Color("7f949b"))
			var text := _label(line, str(obj["text"]), 18, SystemUI.TEXT if done else SystemUI.TEXT_DIM)
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var story := str(entry["story"])
	if story != "":
		var col := _section("说 明")
		var body := _label(col, story, 18, SystemUI.TEXT)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rewards: Array = entry["rewards"]
	if not rewards.is_empty():
		var col := _section("奖 励")
		for reward in rewards:
			_label(col, "◇ %s" % str(reward), 18, Color("ffe58a"))
	var records: Array = entry["records"]
	if not records.is_empty():
		var col := _section("记 录")
		for line in records:
			var text := _label(col, "· %s" % str(line), 18, SystemUI.TEXT_DIM)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## 底栏：全局进度 + 可选动作按钮（只有开门方给了动作才出现）。
func _refresh_footer() -> void:
	var done := 0
	for entry in _entries:
		if str(entry["status"]) == QuestLog.DONE:
			done += 1
	_summary.text = "任务 %d / %d 已完成 · 世界之源 %.1f%% · 噬灵者法力 %d · 乐园币 %d" % [
		done, _entries.size(), float(GameState.campaign.get("source", 0.0)),
		int(GameState.campaign.get("world_mana", 0)), GameState.coins]
	_action_button.text = _action_text
	_action_button.visible = _action.is_valid() and _action_text != ""

func _select(id: String) -> void:
	_selected_id = id
	_refresh_list()
	_refresh_detail()

## 行样式：按任务状态着色（已完成绿 / 待交接金 / 进行中蓝 / 未解锁灰），选中行加幽蓝描边。
func _style_row(row: Button, status: String, selected: bool) -> void:
	var bg := Color(SystemUI.BG_BLOCK, 0.35 if status == QuestLog.LOCKED else 0.95)
	var border := Color(SystemUI.BORDER, 0.5 if status == QuestLog.LOCKED else 0.8)
	if selected:
		bg = Color(SystemUI.ACCENT_DIM, 0.30)
		border = Color(SystemUI.ACCENT, 0.95)
	row.add_theme_stylebox_override("normal", SystemUI.flat(bg, border, 2, SystemUI.RADIUS, 10))
	row.add_theme_stylebox_override("hover", SystemUI.flat(bg.lightened(0.12), Color(SystemUI.ACCENT, 0.7), 2, SystemUI.RADIUS, 10))
	row.add_theme_stylebox_override("pressed", SystemUI.flat(bg.darkened(0.15), Color(SystemUI.ACCENT, 0.95), 2, SystemUI.RADIUS, 10))
	row.add_theme_stylebox_override("focus", SystemUI.flat(bg, Color(SystemUI.ACCENT, 0.5), 2, SystemUI.RADIUS, 10))
	var color := QuestLog.status_color(status)
	row.add_theme_color_override("font_color", color.lightened(0.25) if selected else color)
	row.add_theme_color_override("font_hover_color", Color("dceeff"))
	row.add_theme_color_override("font_pressed_color", Color("b9dcff"))
	row.add_theme_color_override("font_focus_color", Color("dceeff"))

## 详情可能长过一屏（目标 + 说明 + 奖励），默认滚动条在深色面板上几乎看不见，
## 会让人以为内容被截断 —— 样式统一放在 SystemUI.style_scrollbar（设置页的按键表共用同一套）。
func _style_scrollbar(scroll: ScrollContainer) -> void:
	SystemUI.style_scrollbar(scroll)

## 详情小节：分块底衬 + 标题，返回可继续追加内容的列。
func _section(title: String) -> VBoxContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", SystemUI.sub())
	_detail_body.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	_label(col, title, 20, SystemUI.ACCENT)
	return col

## 立刻摘除并释放子节点：queue_free 会拖到帧末，重建前必须先把旧内容摘出树，否则重复叠加。
func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _label(parent: Node, text: String, font_size: int, color := SystemUI.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.92))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label
