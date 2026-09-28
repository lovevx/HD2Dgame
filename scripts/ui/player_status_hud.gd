extends Control
## 玩家战斗 HUD：左下资源条 + 状态标签，右下分组快捷栏，低血时屏幕边缘红晕。
## 只读 player 的公开字段、从不改玩家状态。每帧只在显示内容变化时才写 UI ——
## 写 text / 主题覆盖都会触发重排，11 个格子每帧全量重写是白花的开销。
const SystemUI := preload("res://scripts/ui/system_ui.gd")
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")
const CombatSkills := preload("res://data/combat_skills.gd")

const HP_COLOR := Color("e07770")
const HP_LOW_COLOR := Color("ff4a3d")
const HP_GHOST_COLOR := Color("f6d7a8")
const STAMINA_COLOR := Color("a8d977")
const STAMINA_SHORT_COLOR := Color("d9a441")
const WARN := Color("ff8a7a")
## 低于这个生命比例开始红晕与数值脉动；战役里 <10% 还会减速（player.gd），标签单独提示。
const LOW_HP_RATIO := 0.3
const WOUNDED_RATIO := 0.1
## 受击残影：先停一拍让玩家看清掉了多少，再以每秒 GHOST_SPEED×上限 的速度追上。
const GHOST_DELAY := 0.45
const GHOST_SPEED := 0.8

## 快捷栏按用途分组：身法 / 刀术 / 状态 / 道具。[action, 名称]
const GROUPS := [
	{"title": "身法", "items": [["dodge", "剃"], ["attack", "斩击"], ["kick", "直踹"]]},
	{"title": "刀术", "items": [["huanduan", "环断"], ["sword_wave", "刀芒"], ["shadow_stab", "影刺"]]},
	{"title": "状态", "items": [["hunter_toggle", "猎魔"], ["aoge", "护盾"]]},
	{"title": "道具", "items": [["shoot", "枪"], ["bomb", "陷阱"], ["potion", "药剂"]]},
]

## 格子的五种显示态：可用 / 冷却 / 条件不足 / 生效中 / 常驻或无关。
enum Mode { READY, COOLDOWN, BLOCKED, ACTIVE, IDLE }

var player: Node
var show_world_stats := false

var hp_bar: ProgressBar
var hp_ghost: ProgressBar
var shield_strip: ProgressBar
var mp_bar: ProgressBar
var stamina_bar: ProgressBar
var hp_value_label: Label
var mp_value_label: Label
var stamina_value_label: Label
var world_label: Label
var buff_row: HBoxContainer
var vignette: ColorRect
var slots: Array[Dictionary] = []

var _chips: Dictionary = {}          # id → {panel, label, text}
var _ghost_value := -1.0
var _ghost_wait := 0.0
var _last_hp := -1.0
var _hp_flash := 0.0
var _pulse := 0.0
var _cache: Dictionary = {}          # 控件 → 上次写入的值，避免重复写

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_build_vignette()
	_build_status()
	_build_hotbar()

# ---------------------------------------------------------------- 构建

func _build_vignette() -> void:
	vignette = ColorRect.new()
	vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float intensity = 0.0;
uniform vec4 tint : source_color = vec4(0.72, 0.04, 0.03, 1.0);
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.72);
	float edge = smoothstep(0.28, 0.62, length(d));
	COLOR = vec4(tint.rgb, edge * intensity);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	vignette.material = material
	vignette.hide()
	add_child(vignette)

## 左下状态框：自下而上长高（标签行出现时不会盖住底部提示条）。
func _build_status() -> void:
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	frame.offset_left = 32
	frame.offset_right = 426
	frame.offset_top = -50
	frame.offset_bottom = -50
	frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", SystemUI.flat(Color(SystemUI.BG, 0.9), Color(SystemUI.BORDER, 0.62), 1, SystemUI.RADIUS, 14))
	add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(box)
	buff_row = HBoxContainer.new()
	buff_row.add_theme_constant_override("separation", 6)
	buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(buff_row)
	for id in ["hunter", "shield", "healing", "mark", "wounded"]:
		_make_chip(id)
	buff_row.hide()

	var hp_row := _row(box, "生命")
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(170, 16)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_row.add_child(stack)
	hp_ghost = _bar(stack, HP_GHOST_COLOR, SystemUI.track())
	hp_bar = _bar(stack, HP_COLOR, StyleBoxEmpty.new())
	shield_strip = _bar(stack, SystemUI.CRYSTAL, StyleBoxEmpty.new())
	shield_strip.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	shield_strip.offset_bottom = 5
	shield_strip.hide()
	hp_value_label = _value(hp_row)

	var mp_row := _row(box, "法力")
	mp_bar = _bar(_bar_holder(mp_row), SystemUI.CRYSTAL, SystemUI.track())
	mp_value_label = _value(mp_row)
	var st_row := _row(box, "体力")
	stamina_bar = _bar(_bar_holder(st_row), STAMINA_COLOR, SystemUI.track())
	stamina_value_label = _value(st_row)

	world_label = _label(box, "", 13, SystemUI.TEXT_DIM)
	world_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	world_label.hide()
	SystemUI.decor(frame)

func _row(parent: Node, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var name_label := _label(row, title, 14, SystemUI.TEXT_DIM)
	name_label.custom_minimum_size.x = 36
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return row

func _bar_holder(row: HBoxContainer) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(170, 12)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(holder)
	return holder

func _bar(parent: Control, color: Color, background: StyleBox) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", SystemUI.fill(color))
	parent.add_child(bar)
	return bar

func _value(row: HBoxContainer) -> Label:
	var label := _label(row, "0 / 0", 13, SystemUI.TEXT)
	label.custom_minimum_size.x = 78
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _make_chip(id: String) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var accent: Color = {"hunter": SystemUI.GOLD, "shield": SystemUI.CRYSTAL, "healing": STAMINA_COLOR, "mark": Color("c9a0ff"), "wounded": WARN}[id]
	panel.add_theme_stylebox_override("panel", SystemUI.flat(Color(accent, 0.16), Color(accent, 0.7), 1, SystemUI.RADIUS, 4))
	var label := _label(panel, "", 13, accent)
	panel.hide()
	buff_row.add_child(panel)
	_chips[id] = {"panel": panel, "label": label, "text": ""}

## 右下快捷栏：每组上方一行小字组名，格子内显示名称 / 键位 / 状态，冷却时自下而上盖一层暗幕。
func _build_hotbar() -> void:
	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	frame.offset_right = -24
	frame.offset_left = -24
	frame.offset_bottom = -48
	frame.offset_top = -48
	frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	frame.grow_vertical = Control.GROW_DIRECTION_BEGIN
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", SystemUI.flat(Color(SystemUI.BG, 0.9), Color(SystemUI.BORDER, 0.62), 1, SystemUI.RADIUS, 10))
	add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(row)
	for group in GROUPS:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(column)
		_label(column, group["title"], 12, SystemUI.GOLD)
		var cells := HBoxContainer.new()
		cells.add_theme_constant_override("separation", 4)
		cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(cells)
		for item in group["items"]:
			_make_slot(cells, item[0], item[1])
	SystemUI.decor(frame)

func _make_slot(parent: Node, action: String, title: String) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(70, 70)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := SystemUI.flat(Color("111820", 0.96), Color(SystemUI.BORDER, 0.5), 1, 4, 0)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	# PanelContainer 会把直接子节点铺满，暗幕要靠锚点定高，所以多套一层普通 Control。
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.clip_contents = true
	card.add_child(layer)
	var cd_rect := ColorRect.new()
	cd_rect.color = Color(0.0, 0.0, 0.0, 0.58)
	cd_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cd_rect.anchor_top = 1.0
	cd_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cd_rect)
	var flash := ColorRect.new()
	flash.color = Color(SystemUI.CRYSTAL, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash)
	var contents := VBoxContainer.new()
	contents.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	contents.alignment = BoxContainer.ALIGNMENT_CENTER
	contents.add_theme_constant_override("separation", 0)
	contents.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(contents)
	var name_label := _label(contents, title, 16, SystemUI.TEXT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var key := _label(contents, KeyBindings.key_text(action), 12, SystemUI.CRYSTAL)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var state := _label(contents, "", 12, SystemUI.TEXT_DIM)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slots.append({
		"action": action, "card": card, "style": style, "contents": contents,
		"key": key, "state": state, "cd_rect": cd_rect, "flash": flash,
		"cd_total": 0.0, "mode": -1, "text": "", "fill": -1.0,
	})

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

# ---------------------------------------------------------------- 刷新

## 改键后重算格子里的键名（设置页触发，HUD 转发）。
func refresh_keys() -> void:
	for slot in slots:
		slot["key"].text = KeyBindings.key_text(str(slot["action"]))

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	_pulse = fmod(_pulse + delta, TAU)
	_update_vitals(delta)
	_update_buffs()
	_update_hotbar()

func _update_vitals(delta: float) -> void:
	var max_hp: float = maxf(1.0, player.max_hp)
	var hp: float = clampf(player.hp, 0.0, max_hp)
	# 先写上限再写数值：反过来的话上限变大那一帧数值会被旧上限截断。
	_set_range(hp_bar, hp, max_hp)
	_set_range(mp_bar, player.mp, maxf(1.0, player.max_mp))
	_set_range(stamina_bar, player.stamina, maxf(1.0, player.max_stamina))
	_set_text(hp_value_label, "%d / %d" % [ceili(hp), roundi(max_hp)])
	_set_text(mp_value_label, "%d / %d" % [floori(player.mp), roundi(player.max_mp)])
	_set_text(stamina_value_label, "%d / %d" % [floori(player.stamina), roundi(player.max_stamina)])

	# 受击残影：掉血时残影先停住，GHOST_DELAY 后追上；回血直接跟上。
	if _ghost_value < 0.0 or hp >= _ghost_value:
		_ghost_value = hp
	if _last_hp >= 0.0 and hp < _last_hp - 0.01:
		_ghost_wait = GHOST_DELAY
		_hp_flash = 1.0
	_last_hp = hp
	if _ghost_wait > 0.0:
		_ghost_wait -= delta
	elif _ghost_value > hp:
		_ghost_value = maxf(hp, _ghost_value - max_hp * GHOST_SPEED * delta)
	_set_range(hp_ghost, _ghost_value, max_hp)

	var shield: float = player.shield_hp
	shield_strip.visible = shield > 0.0
	if shield > 0.0:
		_set_range(shield_strip, minf(shield, max_hp), max_hp)

	var ratio := hp / max_hp
	var low: bool = ratio < LOW_HP_RATIO and player.alive
	_hp_flash = maxf(0.0, _hp_flash - delta * 4.0)
	var beat := 0.5 + 0.5 * sin(_pulse * 5.0)
	var fill_color := HP_LOW_COLOR if low else HP_COLOR
	_set_fill(hp_bar, fill_color.lerp(Color.WHITE, _hp_flash * 0.6))
	hp_value_label.modulate = Color(1, 1, 1).lerp(WARN, beat) if low else Color.WHITE
	var short: bool = player.stamina < CombatSkills.DODGE_STAMINA_COST
	_set_fill(stamina_bar, STAMINA_SHORT_COLOR if short else STAMINA_COLOR)

	var intensity := 0.0
	if not player.alive:
		intensity = 0.7
	elif low:
		# 刚跌破阈值就要看得见，越低越浓；心跳只做 ±15% 的起伏，不至于晃眼。
		intensity = (0.3 + 0.45 * (1.0 - ratio / LOW_HP_RATIO)) * (0.85 + 0.15 * beat)
	intensity = maxf(intensity, _hp_flash * 0.28)
	vignette.visible = intensity > 0.01
	if vignette.visible:
		(vignette.material as ShaderMaterial).set_shader_parameter("intensity", intensity)

	world_label.visible = show_world_stats
	if show_world_stats:
		_set_text(world_label, "世界之源 %.1f%%  ·  噬灵 %d / 100  ·  乐园币 %d" % [GameState.campaign.source, GameState.campaign.world_mana, GameState.coins])

func _update_buffs() -> void:
	var any := false
	any = _chip("hunter", "猎魔 · 耗蓝中" if player.hunter_active else "") or any
	any = _chip("shield", "护盾 %d · %.1fs" % [ceili(player.shield_hp), maxf(0.0, player.shield_timer)] if player.shield_hp > 0.0 else "") or any
	any = _chip("healing", "饮药 %.1fs" % player.healing_time if player.healing_time > 0.0 else "") or any
	var marked: bool = player.pierce_timer > 0.0 and is_instance_valid(player.pierced_target)
	any = _chip("mark", "影缝 %.1fs" % player.pierce_timer if marked else "") or any
	var wounded: bool = player.alive and player.campaign_mode and player.hp / maxf(1.0, player.max_hp) < WOUNDED_RATIO
	any = _chip("wounded", "重伤 · 移速-40%" if wounded else "") or any
	buff_row.visible = any

func _chip(id: String, text: String) -> bool:
	var chip: Dictionary = _chips[id]
	if chip["text"] != text:
		chip["text"] = text
		chip["label"].text = text
		chip["panel"].visible = text != ""
	return text != ""

func _update_hotbar() -> void:
	for slot in slots:
		var info: Dictionary = _status(str(slot["action"]))
		var mode: int = info["mode"]
		var remaining: float = info.get("cd", 0.0)
		# 冷却总长取这轮冷却出现过的最大剩余值：不用在 HUD 里重抄每个技能的冷却常数，
		# 改了 player.dodge_cooldown 之类的导出值也不会对不上。
		if remaining > 0.0:
			slot["cd_total"] = maxf(float(slot["cd_total"]), remaining)
		var fill: float = remaining / float(slot["cd_total"]) if remaining > 0.0 and float(slot["cd_total"]) > 0.0 else 0.0
		if absf(fill - float(slot["fill"])) > 0.004:
			slot["fill"] = fill
			slot["cd_rect"].anchor_top = 1.0 - fill
		if remaining <= 0.0:
			slot["cd_total"] = 0.0
		if slot["text"] != info["text"]:
			slot["text"] = info["text"]
			slot["state"].text = info["text"]
		if slot["mode"] != mode:
			if slot["mode"] == Mode.COOLDOWN and mode == Mode.READY:
				_flash(slot)
			slot["mode"] = mode
			_apply_mode(slot, mode)

func _apply_mode(slot: Dictionary, mode: int) -> void:
	var style: StyleBoxFlat = slot["style"]
	var state: Label = slot["state"]
	var contents: Control = slot["contents"]
	match mode:
		Mode.READY:
			style.border_color = Color(SystemUI.CRYSTAL, 0.75)
			style.bg_color = Color("111820", 0.96)
			state.add_theme_color_override("font_color", SystemUI.CRYSTAL)
			contents.modulate = Color.WHITE
		Mode.COOLDOWN:
			style.border_color = Color(SystemUI.BORDER, 0.35)
			style.bg_color = Color("111820", 0.96)
			state.add_theme_color_override("font_color", SystemUI.TEXT)
			contents.modulate = Color(1, 1, 1, 0.85)
		Mode.BLOCKED:
			style.border_color = Color(WARN, 0.6)
			style.bg_color = Color("1a1214", 0.96)
			state.add_theme_color_override("font_color", WARN)
			contents.modulate = Color(1, 1, 1, 0.7)
		Mode.ACTIVE:
			style.border_color = Color(SystemUI.GOLD, 0.95)
			style.bg_color = Color("2a2412", 0.96)
			state.add_theme_color_override("font_color", SystemUI.GOLD)
			contents.modulate = Color.WHITE
		_:
			style.border_color = Color(SystemUI.BORDER, 0.35)
			style.bg_color = Color("111820", 0.96)
			state.add_theme_color_override("font_color", SystemUI.TEXT_DIM)
			contents.modulate = Color(1, 1, 1, 0.6)

## 冷却转好的那一下闪一次冰蓝，余光就能察觉技能回来了。
func _flash(slot: Dictionary) -> void:
	var flash: ColorRect = slot["flash"]
	var tween := flash.create_tween()
	flash.color.a = 0.5
	tween.tween_property(flash, "color:a", 0.0, 0.35)

## 各格状态：先看是否生效中，再看冷却（能给出精确秒数），最后才是资源 / 条件不足。
## 条件与 player.gd 里对应技能的起手判定保持一致，否则 HUD 会显示「就绪」但按了没反应。
func _status(action: String) -> Dictionary:
	match action:
		"dodge":
			if player.dodging:
				return _s("位移中", Mode.ACTIVE)
			if player.dodge_cd > 0.0:
				return _cd(player.dodge_cd)
			if player.stamina < CombatSkills.DODGE_STAMINA_COST:
				return _s("体力不足", Mode.BLOCKED)
			return _s("就绪", Mode.READY)
		"attack":
			return _s("常驻", Mode.IDLE)
		"kick":
			if player.kick_cd > 0.0:
				return _cd(player.kick_cd)
			if player.stamina < CombatSkills.KICK_STAMINA_COST:
				return _s("体力不足", Mode.BLOCKED)
			return _s("就绪", Mode.READY)
		"huanduan":
			if player.ring_windup > 0.0:
				return _s("释放中", Mode.ACTIVE)
			if player.ring_cd > 0.0:
				return _cd(player.ring_cd)
			if player.mp < CombatSkills.RING_MP_COST:
				return _s("法力不足", Mode.BLOCKED)
			return _s("就绪", Mode.READY)
		"sword_wave":
			if player.wave_windup > 0.0:
				return _s("释放中", Mode.ACTIVE)
			if player.wave_cd > 0.0:
				return _cd(player.wave_cd)
			if player.mp < CombatSkills.WAVE_MP_COST:
				return _s("法力不足", Mode.BLOCKED)
			return _s("就绪", Mode.READY)
		"shadow_stab":
			if player.shadow_windup > 0.0:
				return _s("突刺中", Mode.ACTIVE)
			if player.shadow_cd > 0.0:
				return _cd(player.shadow_cd)
			if not is_instance_valid(player.pierced_target) or player.pierce_timer <= 0.0:
				return _s("需标记", Mode.IDLE)
			if player.global_position.distance_to(player.pierced_target.global_position) > CombatSkills.SHADOW_MAX_DISTANCE:
				return _s("超出距离", Mode.BLOCKED)
			if player.mp < CombatSkills.SHADOW_MP_COST:
				return _s("法力不足", Mode.BLOCKED)
			return _s("就绪", Mode.READY)
		"hunter_toggle":
			if player.hunter_active:
				return _s("猎魔中", Mode.ACTIVE)
			if player.mp <= player.max_mp * 0.01:
				return _s("法力不足", Mode.BLOCKED)
			return _s("可开启", Mode.READY)
		"aoge":
			if player.shield_hp > 0.0:
				return _s("护盾 %d" % ceili(player.shield_hp), Mode.ACTIVE)
			if player.shield_cd > 0.0:
				return _cd(player.shield_cd)
			if player.mp < CombatSkills.SHIELD_MP_COST:
				return _s("法力不足", Mode.BLOCKED)
			return _s("可开启", Mode.READY)
		"shoot":
			if str(GameState.campaign.equipment.get("offhand", "")) != "flintlock":
				return _s("未装备", Mode.IDLE)
			if player.bullets <= 0:
				return _s("无弹药", Mode.BLOCKED)
			if player.shot_cd > 0.0:
				return _cd(player.shot_cd)
			return _s("弹药 %d" % player.bullets, Mode.READY)
		"bomb":
			if player.bombs <= 0:
				return _s("无存量", Mode.IDLE)
			return _s("× %d" % player.bombs, Mode.READY)
		"potion":
			if player.healing_time > 0.0:
				return _s("饮用中", Mode.ACTIVE)
			if player.potions <= 0:
				return _s("无存量", Mode.IDLE)
			if player.hp >= player.max_hp:
				return _s("满血 × %d" % player.potions, Mode.IDLE)
			return _s("× %d" % player.potions, Mode.READY)
	return _s("—", Mode.IDLE)

func _s(text: String, mode: int) -> Dictionary:
	return {"text": text, "mode": mode}

func _cd(remaining: float) -> Dictionary:
	return {"text": "%.1fs" % remaining, "mode": Mode.COOLDOWN, "cd": remaining}

# ---------------------------------------------------------------- 写入去重

func _set_range(bar: ProgressBar, value: float, maximum: float) -> void:
	if bar.max_value != maximum:
		bar.max_value = maximum
	if absf(bar.value - value) > 0.001:
		bar.value = value

func _set_text(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text

func _set_fill(bar: ProgressBar, color: Color) -> void:
	if _cache.get(bar) == color:
		return
	_cache[bar] = color
	var style := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if style:
		style.bg_color = color
