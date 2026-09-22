extends SceneTree
## 增量应用港口围墙到现有 harbor.tscn：移除边界山石、重建 HarborWall 节点，其余内容原样保留。
## 不重跑 build_harbor.gd，避免覆盖工作区里手工调整过的场景内容。
## 布局与 build_harbor.gd 共用 tools/harbor_walls.gd。
## 用法：godot --headless --path . --script res://tools/apply_harbor_walls.gd

const Walls := preload("res://tools/harbor_walls.gd")
const SCENE_PATH := "res://scenes/world/harbor.tscn"
## 边界山石：体积 20~28 米宽、12~20 米高，紧贴墙线并与围墙穿模，围墙统一收口后移除。
const ROCK_PREFIX := "SM_Jiangnan_xuanya"
## 旧城门素材（暖黄石作）与新版砖石城墙风格不符，改由 tools/harbor_gate.gd 砌筑的城门取代。
const GATE_TITLE := "SM_xgg_chengmen001"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var root := load(SCENE_PATH).instantiate() as Node3D
	if root == null:
		push_error("港口场景加载失败：" + SCENE_PATH)
		quit(1)
		return
	var rocks := 0
	for child in root.get_children():
		if String(child.name).begins_with(ROCK_PREFIX):
			root.remove_child(child)
			child.free()
			rocks += 1
	var gates := 0
	for child in root.get_children():
		if child is HD2DProp and child.asset != null and String(child.asset.resource_path).contains(GATE_TITLE):
			root.remove_child(child)
			child.free()
			gates += 1
	var previous := root.get_node_or_null(NodePath(Walls.NODE_NAME))
	if previous:
		root.remove_child(previous)
		previous.free()
	var holder := Walls.make_node()
	if holder.get_child_count() == 0:
		push_error("围墙没有生成任何构件，未写入场景。")
		root.free()
		quit(1)
		return
	root.add_child(holder)
	holder.owner = root
	_own(holder, root)
	var error := OK
	var packed := PackedScene.new()
	error = packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, SCENE_PATH)
	print("HARBOR_WALLS_APPLY: rocks_removed=", rocks, " wall_parts=", holder.get_child_count(), " result=", error)
	root.free()
	quit(0 if error == OK else 1)

## 递归接管所有权：城门与壁柱都带子节点，漏掉一层就会在重存时丢掉。
func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_own(child, scene_root)
