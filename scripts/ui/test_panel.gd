extends CanvasLayer
const SystemUI := preload("res://scripts/ui/system_ui.gd")
const Attributes := preload("res://data/attributes.gd")

## 仅本次运行有效的开发者测试面板；属性通过 GameState 的临时覆盖读取，不写存档。
var player: Node
var managed_pause := false
var _attribute_labels: Dictionary = {}
var _god_mode: CheckButton
var _saved_world_nodes: Array[Dictionary] = []
var _saved_player_physics := false
var _saved_player_input := false

func _ready() -> void:
	name = "TestPanel"
	layer = 55
	add_to_group("test_panel")
	visible = false
	_build_panel()
	GameState.attributes_changed.connect(_refresh)
	visibility_changed.connect(_on_visibility_changed)

func open() -> void:
	_refresh()
	show()

func close() -> void:
	hide()

func _on_visibility_changed() -> void:
	if visible:
		GameState.debug_mode_active = true
		if not managed_pause:
			_freeze_world()
		_refresh()
	else:
		_restore_world()

func _freeze_world() -> void:
	_saved_world_nodes.clear()
	if is_instance_valid(player):
		_saved_player_physics = player.is_physics_processing()
		_saved_player_input = player.is_processing_unhandled_input()
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
	for group_name in ["enemies", "targets", "alchemy_bombs"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			_saved_world_nodes.append({
				"node": node,
				"physics": node.is_physics_processing(),
				"process": node.is_processing(),
			})
			node.set_physics_process(false)
			node.set_process(false)

func _restore_world() -> void:
	if managed_pause:
		return
	if is_instance_valid(player):
		player.set_physics_process(_saved_player_physics)
		player.set_process_unhandled_input(_saved_player_input)
	for saved in _saved_world_nodes:
		var node: Node = saved["node"]
		if not is_instance_valid(node):
			continue
		node.set_physics_process(bool(saved["physics"]))
		node.set_process(bool(saved["process"]))
	_saved_world_nodes.clear()

func _build_panel() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.025, 0.04, 0.86)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(1050, 720)
	card.add_theme_stylebox_override("panel", SystemUI.card())
	SystemUI.decor(card)
	center.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	card.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	page.add_child(header)
	var title := _label(header, "开发者测试面板", 32, SystemUI.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button := _button(header, "关闭 · Esc", close, 130)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	page.add_child(HSeparator.new())
	_label(page, "仅当前运行有效 · 临时属性覆盖不扣属性点、不写入存档", 17, SystemUI.TEXT_DIM)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	var attributes_panel := PanelContainer.new()
	attributes_panel.custom_minimum_size.x = 590
	attributes_panel.add_theme_stylebox_override("panel", SystemUI.sub())
	columns.add_child(attributes_panel)
	var attributes_list := VBoxContainer.new()
	attributes_list.add_theme_constant_override("separation", 8)
	attributes_panel.add_child(attributes_list)
	_label(attributes_list, "六维属性", 23, SystemUI.GOLD)
	for key in Attributes.ALL_KEYS:
		_add_attribute_row(attributes_list, str(key))
	_button(attributes_list, "六维属性 +10", _boost_all_attributes.bind(10), 0)
	_button(attributes_list, "清除临时属性改动", _clear_attribute_overrides, 0)

	var actions_panel := PanelContainer.new()
	actions_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_panel.add_theme_stylebox_override("panel", SystemUI.sub())
	columns.add_child(actions_panel)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions_panel.add_child(actions)
	_label(actions, "快速测试", 23, SystemUI.GOLD)
	_button(actions, "回满 HP / MP / 体力", _fill_resources)
	_button(actions, "清除战斗冷却与前摇", _reset_cooldowns)
	_god_mode = CheckButton.new()
	_god_mode.text = "无敌模式"
	_god_mode.add_theme_font_size_override("font_size", 19)
	_god_mode.add_theme_color_override("font_color", SystemUI.TEXT)
	_god_mode.add_theme_color_override("font_hover_color", SystemUI.GOLD)
	_god_mode.add_theme_color_override("font_focus_color", SystemUI.CRYSTAL)
	_god_mode.toggled.connect(_set_god_mode)
	actions.add_child(_god_mode)
	var note := _label(actions,
		"调整属性会即时刷新派生数值。\n打开面板后，本次运行期间的 HP、MP、\n弹药与道具不会在离开战役时回写存档。",
		16, SystemUI.TEXT_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(HSeparator.new())
	_label(page, "F2 开关测试面板 · 面板打开时游戏暂停", 16, SystemUI.TEXT_DIM)

func _add_attribute_row(parent: Node, key: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var name_label := _label(row, Attributes.CN_NAMES[key], 18)
	name_label.custom_minimum_size.x = 72
	var value_label := _label(row, "", 17, SystemUI.TEXT_DIM)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attribute_labels[key] = value_label
	for delta in [-5, -1, 1, 5]:
		var caption := "+%d" % delta if delta > 0 else str(delta)
		_button(row, caption, _change_attribute.bind(key, delta), 48)

func _refresh() -> void:
	if not is_node_ready():
		return
	var values: Dictionary = GameState.debug_attributes()
	for key in _attribute_labels:
		_attribute_labels[key].text = "%d  (原值 %d)" % [int(values.get(key, Attributes.BASE)), int(GameState.attributes.get(key, Attributes.BASE))]
	if _god_mode != null and is_instance_valid(player):
		_god_mode.set_pressed_no_signal(bool(player.invulnerable))

func _change_attribute(key: String, delta: int) -> void:
	var values: Dictionary = GameState.debug_attributes()
	GameState.set_debug_attribute(key, int(values.get(key, Attributes.BASE)) + delta)

func _boost_all_attributes(amount: int) -> void:
	for key in Attributes.ALL_KEYS:
		var values: Dictionary = GameState.debug_attributes()
		GameState.set_debug_attribute(key, int(values.get(key, Attributes.BASE)) + amount)

func _clear_attribute_overrides() -> void:
	GameState.clear_debug_attribute_overrides()

func _fill_resources() -> void:
	if not is_instance_valid(player):
		return
	player.healing_time = 0.0
	player.hp = player.max_hp
	player.mp = player.max_mp
	player.stamina = player.max_stamina
	player.hp_changed.emit(player.hp, player.max_hp)

func _reset_cooldowns() -> void:
	if not is_instance_valid(player):
		return
	for property in ["attack_cd", "kick_cd", "dodge_cd", "shot_cd", "ring_cd", "wave_cd", "shadow_cd", "ring_lock"]:
		player.set(property, 0.0)
	player.ring_windup = 0.0
	player.wave_windup = 0.0
	player.shadow_windup = 0.0
	player.attack_elapsed = -1.0
	player.attack_hit = false
	player.kick_hit_pending = false
	player.buffer_time = 0.0

func _set_god_mode(enabled: bool) -> void:
	if is_instance_valid(player):
		player.invulnerable = enabled

func _button(parent: Node, text: String, callback: Callable, width := 0.0) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 44)
	button.add_theme_font_size_override("font_size", 17)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width == 0.0 else Control.SIZE_SHRINK_CENTER
	SystemUI.style_button(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(parent: Node, text: String, font_size: int, color := SystemUI.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.07, 0.92))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label
