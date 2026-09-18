@tool
class_name HD2DProp
extends Node3D
var _face_player := false
var _spin_prepared := false
var _authored_yaw := 0.0
## 碰撞体 -> 它相对道具作者朝向的偏航，用来在外观转向时把碰撞体转回去。
var _collision_yaws: Dictionary = {}
@export var asset_overrides: Dictionary = {}:
	set(value):
		asset_overrides=value.duplicate(true)
		if is_inside_tree(): rebuild()

func effective_asset() -> HD2DAsset:
	return asset.with_overrides(asset_overrides) if asset else null

@export var skin_id: StringName = &"":
	set(value):
		skin_id=value
		if is_inside_tree(): refresh_skin()
@export var material_override: Material:
	set(value):
		material_override=value
		if is_inside_tree(): rebuild()
@export_enum("保持素材:-1", "Off:0", "On:1", "Double-sided:2", "Shadows only:3") var cast_shadow: int = -1:
	set(value):
		cast_shadow=value
		if is_inside_tree(): rebuild()
## The asset reference is authored; render/collision children are regenerated, not saved.
@export var asset: HD2DAsset:
	set(value):
		if asset and asset.changed.is_connected(rebuild): asset.changed.disconnect(rebuild)
		asset=value
		if asset: asset.changed.connect(rebuild)
		if is_inside_tree(): rebuild()

func _ready() -> void: rebuild()

func rebuild() -> void:
	if not is_inside_tree(): return
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var settings := effective_asset()
	_face_player = settings != null and settings.facing == 2
	set_process(_face_player and not Engine.is_editor_hint())
	if asset==null or asset.source==null: return
	add_child(effective_asset().make_node(skin_id))
	if Engine.is_editor_hint(): update_gizmos()
	_apply_visual_overrides(self)
	if _face_player: _prepare_turning()
	var ancestor := get_parent()
	while ancestor:
		if ancestor is HD2DStage:
			ancestor.apply_card_environment(self)
			break
		ancestor=ancestor.get_parent()

## 朝向=始终朝向镜头：素材保持竖直，只绕 Y 轴逐帧对准当前相机位置。
## 素材基准正面为 +Z，因此 yaw 0 就是构建脚本里“朝向默认机位”的那一面。
func _process(_delta: float) -> void:
	if Engine.is_editor_hint(): return
	var camera := get_viewport().get_camera_3d() as Node3D
	if camera == null: return
	var parent := get_parent() as Node3D
	var origin := global_position
	var target := camera.global_position
	if parent:
		var inverse := parent.global_transform.affine_inverse()
		origin = inverse * origin
		target = inverse * target
	var yaw := atan2(target.x - origin.x, target.z - origin.z)
	transform = Transform3D(Basis(Vector3.UP, yaw).scaled(transform.basis.get_scale()), transform.origin)
	# 碰撞体不跟着外观转：盒体扫过会把玩家挤开，这里把它反向转回作者朝向。
	for body in _collision_yaws:
		if is_instance_valid(body):
			body.rotation.y = _authored_yaw + float(_collision_yaws[body]) - yaw

## 记下作者朝向与碰撞体的作者局部偏航。重建会换掉碰撞体，所以每次重建都要重新记录。
func _prepare_turning() -> void:
	if not _spin_prepared:
		_authored_yaw = rotation.y
		_spin_prepared = true
	_collision_yaws.clear()
	for node in find_children("*","StaticBody3D",true,false):
		_collision_yaws[node] = (node as Node3D).rotation.y

func refresh_skin() -> void:
	# Appearance changes must not recreate physics or alter the authored transform.
	if asset and get_child_count()>0:
		var effective := skin_id if asset.supports_skin(skin_id) else &""
		effective_asset().apply_skin(get_child(0),effective)
		_apply_visual_overrides(self)

func _apply_visual_overrides(node: Node) -> void:
	if node is GeometryInstance3D:
		if material_override: node.material_override=material_override
		if cast_shadow>=0: node.cast_shadow=cast_shadow
	for child in node.get_children(): _apply_visual_overrides(child)
