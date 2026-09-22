extends Area3D
## 装备掉落物：前期小关击杀概率掉落，携带一件随机装备。
## 表现与 coin.gd 同套：品质色发光晶体 + 地面光圈 + 名称标签，靠近磁吸入背包。
## 纯距离判定，不依赖物理碰撞；spawn 方负责设置 item_id。

const Campaign := preload("res://data/campaign.gd")
const Equip := preload("res://data/equip_tables.gd")

var item_id := ""
var magnet_radius: float = 4.5
var collected: bool = false
var player: Node3D
var _spin := 0.0
var _mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("equipment_drop")
	player = get_tree().get_first_node_in_group("player")
	_build()

func _build() -> void:
	var def: Dictionary = Campaign.ITEMS.get(item_id, {})
	var color: Color = Equip.quality_color(def.get("quality", "white"))
	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.26, 0.26, 0.26)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.8
	_mesh.material_override = mat
	_mesh.rotation_degrees = Vector3(45, 0, 45)
	_mesh.position = Vector3(0, 0.55, 0)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	# 地面光圈：品质色描出掉落位置，俯视角下也容易看见
	var ring := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.55
	cyl.height = 0.02
	ring.mesh = cyl
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(color.r, color.g, color.b, 0.32)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position = Vector3(0, 0.03, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var label := Label3D.new()
	label.text = str(def.get("name", item_id))
	label.position = Vector3(0, 1.15, 0)
	label.font_size = 34
	label.pixel_size = 0.007
	label.outline_size = 10
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _physics_process(delta: float) -> void:
	if collected or not is_instance_valid(player):
		return
	_spin += delta
	if _mesh != null:
		_mesh.rotation_degrees.y = _spin * 90.0
		_mesh.position.y = 0.55 + sin(_spin * 2.4) * 0.08
	var to := player.global_position - global_position
	to.y = 0.0
	if to.length() <= magnet_radius:
		global_position = global_position.move_toward(player.global_position, 6.0 * delta)
	if to.length() <= 0.9:
		_collect()

func _collect() -> void:
	if collected:
		return
	collected = true
	if item_id == "":
		queue_free()
		return
	GameState.give_item(item_id, 1)
	# 不落盘：途中拾取属于「本局未提交收益」，死亡重试要跟着回滚。
	# 提交点是领取战利品 / 开箱 / 检查点等显式 save_game()（见 GameState 出击事务）。
	var def: Dictionary = Campaign.ITEMS.get(item_id, {})
	GameState.push_message("[乐园] 拾取装备 · %s（%s）· 领取战利品前阵亡则失去" % [def.get("name", item_id), Equip.quality_cn(def.get("quality", "white"))])
	var tween := create_tween()
	tween.set_parallel(true)
	if _mesh != null:
		tween.tween_property(_mesh, "position:y", 1.5, 0.16)
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, 0.16)
	tween.chain().tween_callback(queue_free)
