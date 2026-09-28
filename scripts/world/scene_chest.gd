extends Area3D
## 场景宝箱：每个场景一个，靠近按 V 开启，固定产出 1 炸弹 + 1 血药 + 1 随机装备。
## 开启记录在 GameState.campaign.opened_chests（按 chest_key），重进同一关不再刷新。
## 白盒外观：木箱 + 金色包边 + 地面光圈 + 名称标签；开启后箱盖翻起、标签改为已开启。

const Campaign := preload("res://data/campaign.gd")
const GameAudio := preload("res://data/game_audio.gd")
## 贴底提示里的键名现读，改键后不会还写着旧键。
const KeyBindings := preload("res://scripts/ui/key_bindings.gd")

## 消耗品短名：正文里带上物品表的长名（含「· 2使用」）读起来别扭，这里单独给简称。
const SHORT_LABEL := {"trap": "火药陷阱", "potion": "恢复药剂"}

@export var chest_key := ""
var visitor: Node3D
var opened := false
var _lid: Node3D
var _label: Label3D

func _ready() -> void:
	add_to_group("scene_chest")
	_build()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _process(_delta: float) -> void:
	if visitor == null or opened or GameState.is_transitioning():
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or hud.is_modal_open():
		return
	hud.show_prompt("%s  开启场景宝箱" % KeyBindings.key_text("interact"))

## 进圈：登记玩家并加入焦点组，让 campaign 控制器把 V 让给宝箱，避免同时触发关卡流程。
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		visitor = body
		add_to_group("scene_chest_focus")

func _on_body_exited(body: Node3D) -> void:
	if body == visitor:
		visitor = null
		remove_from_group("scene_chest_focus")
		_hide_prompt()

func _unhandled_input(event: InputEvent) -> void:
	if visitor == null or opened or GameState.is_transitioning():
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or hud.is_modal_open():
		return
	if event.is_action_pressed("interact"):
		_open()
		get_viewport().set_input_as_handled()

func _open() -> void:
	if opened:
		return
	var rewards: Array = GameState.open_scene_chest(chest_key)
	opened = true
	remove_from_group("scene_chest_focus")
	_hide_prompt()
	GameAudio.play_sfx("chest", global_position, -2.0)
	_play_open()
	if rewards.is_empty():
		return
	_sync_player_supplies()
	var parts: Array[String] = []
	for id in rewards:
		var def: Dictionary = GameState.item_def(str(id))
		parts.append("%s ×1" % SHORT_LABEL.get(str(id), def.get("name", id)))
	GameState.push_message("[乐园] 开启场景宝箱 · %s" % " · ".join(parts))

## 宝箱产出的药剂/炸弹要立刻反映到玩家库存，否则关卡结算 _copy_supplies 会用旧值覆盖背包。
func _sync_player_supplies() -> void:
	var target: Node = visitor if visitor != null else get_tree().get_first_node_in_group("player")
	if target == null:
		return
	target.set("potions", GameState.item_count("potion"))
	target.set("bombs", GameState.item_count("trap"))

func _play_open() -> void:
	if _lid != null:
		var tween := create_tween()
		tween.tween_property(_lid, "rotation_degrees:x", 105.0, 0.36).set_trans(Tween.TRANS_BACK)
	if _label != null:
		_label.text = "已开启"

func _hide_prompt() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.hide_prompt()

# ---------------------------------------------------------------- 白盒外观

func _build() -> void:
	var wood := _mat(Color("6b4a2b"), 0.85, false)
	var dark := _mat(Color("3f2a17"), 0.9, false)
	var gold := _mat(Color("d9a94e"), 0.35, true)
	# 箱体
	_part("Base", Vector3(0, 0.28, 0), Vector3(1.0, 0.52, 0.7), wood)
	_part("BaseTrim", Vector3(0, 0.06, 0), Vector3(1.06, 0.12, 0.76), dark)
	# 箱盖：挂在后沿铰链上，开启时绕 X 轴翻起
	_lid = Node3D.new()
	_lid.name = "Lid"
	_lid.position = Vector3(0, 0.54, 0.35)
	add_child(_lid)
	var lid_mesh := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.04, 0.24, 0.72)
	lid_mesh.mesh = lm
	lid_mesh.material_override = wood
	lid_mesh.position = Vector3(0, 0.12, -0.35)
	_lid.add_child(lid_mesh)
	var lid_trim := MeshInstance3D.new()
	var ltm := BoxMesh.new()
	ltm.size = Vector3(1.08, 0.1, 0.76)
	lid_trim.mesh = ltm
	lid_trim.material_override = gold
	lid_trim.position = Vector3(0, 0.06, -0.35)
	_lid.add_child(lid_trim)
	# 正面锁扣
	_part("Lock", Vector3(0, 0.36, -0.37), Vector3(0.16, 0.18, 0.06), gold)
	# 地面光圈：金色，远看就知道是可交互物
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.95
	cyl.bottom_radius = 0.95
	cyl.height = 0.02
	ring.mesh = cyl
	var rm := _mat(Color(0.85, 0.66, 0.3), 0.0, true)
	rm.albedo_color = Color(0.85, 0.66, 0.3, 0.26)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = rm
	ring.position = Vector3(0, 0.03, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	# 名称标签
	_label = Label3D.new()
	_label.text = "场景宝箱"
	_label.position = Vector3(0, 1.35, 0)
	_label.font_size = 36
	_label.pixel_size = 0.008
	_label.outline_size = 12
	_label.modulate = Color("ffd76e")
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(_label)
	# 触发范围：比箱体略大，靠近即可交互
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.8, 2.6, 2.8)
	shape.shape = box
	shape.position = Vector3(0, 0.9, 0)
	add_child(shape)

func _part(label_name: String, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = at
	add_child(mesh)
	return mesh

func _mat(color: Color, roughness: float, emission: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	if emission:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.6
	return mat
