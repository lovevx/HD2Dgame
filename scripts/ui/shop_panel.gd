extends CanvasLayer
const SystemUI := preload("res://scripts/ui/system_ui.gd")
## 「轮回商店」：分类页签 + 商品网格 + 详情购买。
##   购买走 GameState.buy_item（扣乐园币 / 入背包 / 落盘）；sold_out 商品只展示不出售。
##
## 打开方式：灰潮港 ShopService 的 panel_handler 由 harbor.gd 接线到 open()。
## 打开时冻结玩家移动、显示系统光标；Esc / 关闭按钮退出。加入 "shop_panel" 组，
## HUD 的 is_modal_open / 鼠标模式据此把它当成一块模态面板。

const QUALITY_COLORS := {
	"white": Color("c8d4dc"),
	"green": Color("7ed67e"),
	"blue": Color("6aa9ff"),
	"purple": Color("b98aff"),
	"gold": Color("ffd76e"),
}

## 商品表：id 对应 Campaign.ITEMS（无对应表的商品会提示"暂无货源"）；sold_out 只展示。
const GOODS := [
	{"id": "potion", "name": "恢复药剂", "cat": "消耗品", "price": 150, "quality": "green", "desc": "恢复 40% 生命的琥珀色药剂，出门在外的必备品。"},
	{"id": "trap", "name": "火药陷阱 · 投掷", "cat": "消耗品", "price": 220, "quality": "green", "desc": "可预埋的炼金炸弹，蹲守与引爆两用。"},
	{"id": "iron_sword", "name": "精铁刀", "cat": "武器", "price": 900, "quality": "white", "desc": "灰潮港铁匠打的制式直刀，结实耐用。"},
	{"id": "worn_blade", "name": "缺口刀", "cat": "武器", "price": 120, "quality": "white", "desc": "从旧战场流出的豁口弯刀，还能砍。"},
	{"id": "leather_cap", "name": "皮护额", "cat": "防具", "price": 260, "quality": "white", "desc": "硬化的皮革护额，挡得住流石。"},
	{"id": "ragged_vest", "name": "褴褛甲", "cat": "防具", "price": 340, "quality": "white", "desc": "层层叠叠的旧布甲，聊胜于无。"},
	{"id": "copper_ring", "name": "铜戒指", "cat": "饰品", "price": 480, "quality": "blue", "desc": "潮气里泡出来的绿斑，反而好看。"},
	{"id": "pendant", "name": "亡妻项坠", "cat": "饰品", "price": 1500, "quality": "purple", "desc": "不卖。摆在这里只是让它见见光。", "sold_out": true},
	{"id": "white_mat", "name": "白锻材", "cat": "材料", "price": 650, "quality": "green", "desc": "强化装备的基础锻材。"},
	{"id": "blue_mat", "name": "蓝锻材", "cat": "材料", "price": 1400, "quality": "blue", "desc": "泛着海光的锻材，工坊的老主顾都认。"},
	{"id": "tiger_tooth", "name": "虎齿", "cat": "宝藏", "price": 800, "quality": "green", "desc": "科尔波山巨虎的牙，猎户的战利品。"},
	{"id": "crystal", "name": "灵魂结晶", "cat": "宝藏", "price": 2400, "quality": "purple", "desc": "温热的结晶体，里面像有什么在呼吸。"},
	{"id": "letter", "name": "引荐信", "cat": "宝藏", "price": 500, "quality": "blue", "desc": "港务委托所的火漆信，别拆开看。"},
]

const CATEGORIES := ["全部", "武器", "防具", "饰品", "消耗品", "材料", "宝藏"]

var _current_cat := "全部"
var _selected_id := ""
var _cells: Array[PanelContainer] = []
var _cat_buttons: Dictionary = {}
var _grid: GridContainer
var _coins_label: Label
var _preview: PanelContainer
var _preview_label: Label
var _detail_name: Label
var _detail_quality: Label
var _detail_desc: Label
var _detail_price: Label
var _buy_button: Button

func _ready() -> void:
	add_to_group("shop_panel")
	layer = 30
	visible = false
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.03, 0.05, 0.78)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1160, 660)
	card.add_theme_stylebox_override("panel", _card_style())
	SystemUI.decor(card)
	center.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	card.add_child(page)

	# ---- 店名 ----
	var title := _label(page, "轮  回  商  店", 42, SystemUI.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var rule := HSeparator.new()
	page.add_child(rule)

	# ---- 三栏主体 ----
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	# 左：分类页签
	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 150
	nav.add_theme_constant_override("separation", 8)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(nav)
	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text = cat
		btn.custom_minimum_size = Vector2(140, 52)
		btn.add_theme_font_size_override("font_size", 22)
		SystemUI.style_button(btn)
		btn.pressed.connect(_set_category.bind(cat))
		nav.add_child(btn)
		_cat_buttons[cat] = btn

	# 中：商品网格
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	body.add_child(mid)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	# 右：详情面板
	var side := _panel_box(body)
	side.custom_minimum_size = Vector2(300, 0)
	var side_col := VBoxContainer.new()
	side_col.add_theme_constant_override("separation", 10)
	side.add_child(side_col)
	var side_title := _label(side_col, "详  情", 24, SystemUI.ACCENT)
	side_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview = PanelContainer.new()
	_preview.custom_minimum_size = Vector2(0, 190)
	_preview.add_theme_stylebox_override("panel", _slot_style())
	side_col.add_child(_preview)
	_preview_label = _label(_preview, "", 52, SystemUI.TEXT)
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_name = _label(side_col, "", 26, Color("ffd76e"))
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_quality = _label(side_col, "", 18, SystemUI.TEXT_DIM)
	_detail_quality.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_desc = _label(side_col, "", 17, SystemUI.TEXT_DIM)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(0, 110)
	_detail_price = _label(side_col, "", 24, Color("ffe58a"))
	_detail_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_buy_button = Button.new()
	_buy_button.text = "购 买"
	_buy_button.custom_minimum_size = Vector2(0, 56)
	_buy_button.add_theme_font_size_override("font_size", 24)
	SystemUI.style_button(_buy_button)
	_buy_button.pressed.connect(_purchase)
	side_col.add_child(_buy_button)

	# ---- 底栏：操作提示 + 乐园币 ----
	var footer := HBoxContainer.new()
	page.add_child(footer)
	# 注意：_label() 内部已经 add_child，这里不要再重复挂一遍。
	var hint := _label(footer, "Esc 关闭 · 点选商品查看详情", 16, SystemUI.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_coins_label = _label(footer, "", 22, Color("ffd76e"))
	_coins_label.size_flags_horizontal = Control.SIZE_SHRINK_END

	_refresh_categories()
	_rebuild_grid()

func open() -> void:
	visible = true
	_current_cat = "全部"
	_selected_id = ""
	_refresh_categories()
	_rebuild_grid()
	_refresh_coins()
	_refresh_detail()
	_freeze_player(true)

func close() -> void:
	visible = false
	_freeze_player(false)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("open_menu") or event.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()

func _set_category(cat: String) -> void:
	_current_cat = cat
	_selected_id = ""
	_refresh_categories()
	_rebuild_grid()
	_refresh_detail()

func _refresh_categories() -> void:
	for cat in _cat_buttons:
		var btn: Button = _cat_buttons[cat]
		if cat == _current_cat:
			btn.add_theme_color_override("font_color", Color("ffd76e"))
			btn.add_theme_color_override("font_hover_color", Color("ffd76e"))
		else:
			btn.add_theme_color_override("font_color", Color("9fb4c2"))
			btn.add_theme_color_override("font_hover_color", SystemUI.TEXT)

func _goods_for(cat: String) -> Array:
	if cat == "全部":
		return GOODS
	var result: Array = []
	for item in GOODS:
		if item["cat"] == cat:
			result.append(item)
	return result

func _rebuild_grid() -> void:
	for cell in _cells:
		cell.queue_free()
	_cells.clear()
	for item in _goods_for(_current_cat):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(0, 128)
		var st := _slot_style()
		cell.add_theme_stylebox_override("panel", st)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(col)
		var name_label := _label(col, str(item["name"]), 20, QUALITY_COLORS.get(item["quality"], SystemUI.TEXT))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var price_label := _label(col, "◇ %d" % int(item["price"]), 17, Color("ffe58a"))
		price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.gui_input.connect(_cell_input.bind(str(item["id"])))
		_grid.add_child(cell)
		_cells.append(cell)
		if str(item["id"]) == _selected_id:
			st.border_color = Color("ffd76e")

func _cell_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	_selected_id = id
	_rebuild_grid()
	_refresh_detail()

func _selected_goods() -> Dictionary:
	for item in GOODS:
		if item["id"] == _selected_id:
			return item
	return {}

func _refresh_detail() -> void:
	var item := _selected_goods()
	if item.is_empty():
		_preview_label.text = "？"
		_preview_label.add_theme_color_override("font_color", Color("5a6f7c"))
		_detail_name.text = "未选中商品"
		_detail_quality.text = ""
		_detail_desc.text = "点选左侧或中间的商品，这里会显示详情。"
		_detail_price.text = ""
		_buy_button.disabled = true
		_buy_button.text = "购 买"
		return
	_preview_label.text = str(item["name"]).left(1)
	_preview_label.add_theme_color_override("font_color", QUALITY_COLORS.get(item["quality"], SystemUI.TEXT))
	_detail_name.text = str(item["name"])
	_detail_quality.text = "%s · %s" % [str(item["cat"]), _quality_cn(str(item["quality"]))]
	_detail_quality.add_theme_color_override("font_color", QUALITY_COLORS.get(item["quality"], SystemUI.TEXT_DIM))
	_detail_desc.text = str(item["desc"])
	_detail_price.text = "单价  ◇ %d" % int(item["price"])
	var sold := bool(item.get("sold_out", false))
	_buy_button.disabled = sold
	_buy_button.text = "不 售 卖" if sold else "购 买"

## 购买：走 GameState.buy_item（扣乐园币 / 入背包 / 落盘），余额与详情即时刷新。
func _purchase() -> void:
	var item := _selected_goods()
	if item.is_empty() or bool(item.get("sold_out", false)):
		return
	if GameState.buy_item(str(item["id"]), int(item["price"])):
		_refresh_coins()
		_refresh_detail()

func _refresh_coins() -> void:
	_coins_label.text = "乐园币  %d" % GameState.coins

func _freeze_player(frozen: bool) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null:
		player.set_physics_process(not frozen)

func _quality_cn(quality: String) -> String:
	match quality:
		"green": return "优良"
		"blue": return "稀有"
		"purple": return "史诗"
		"gold": return "传说"
		_: return "普通"

func _panel_box(parent: Node) -> PanelContainer:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", _inner_style())
	parent.add_child(box)
	return box

func _card_style() -> StyleBoxFlat:
	return SystemUI.card()

func _inner_style() -> StyleBoxFlat:
	return SystemUI.sub()

func _slot_style() -> StyleBoxFlat:
	return SystemUI.slot()

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
