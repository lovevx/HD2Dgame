extends SceneTree
## 把「科尔波山」远景层增量装进已生成的 scenes/world/harbor.tscn，不改动其它既有内容。
## 布局集中在 tools/harbor_mountain.gd；改布局后重跑本脚本即可
## （幂等：先删旧 HarborMountain 再重建）。
##
## 做两件事：
##   1. 在根节点下增删 HarborMountain：北墙外的前排山脊、后排群峰、垭口示意、
##      前沿孤岩、山脚林带。
##   2. 回写 scenes/world/harbor.tscn（先备份到 tools/backups/，已存在则不覆盖）。
##
## 用法：godot --headless --path . --script res://tools/apply_harbor_mountain.gd

const HarborMountain := preload("res://tools/harbor_mountain.gd")
const SCENE_PATH := "res://scenes/world/harbor.tscn"
const BACKUP_PATH := "res://tools/backups/harbor_before_mountain.tscn.bak"

func _initialize() -> void:
	call_deferred("apply")

func apply() -> void:
	var packed: PackedScene = load(SCENE_PATH)
	if packed == null:
		push_error("场景不存在：" + SCENE_PATH)
		quit(1)
		return
	_backup()
	var root: Node = packed.instantiate()
	var before := _count(root)
	var district: Node3D = HarborMountain.make_node()
	_remove(root, district.name)
	root.add_child(district)
	print("MOUNT_APPLY: %s 子节点 %d" % [district.name, district.get_child_count()])
	# 新增节点必须把 owner 指回场景根，否则 pack 时会静默丢掉。
	_own(root, root)
	var generated := _count(root)
	# 必须用变量接住新建的 PackedScene：链式 pack 会把新场景丢掉，存回的是旧场景。
	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result != OK:
		push_error("打包失败：%s" % error_string(result))
		quit(1)
		return
	result = ResourceSaver.save(scene, SCENE_PATH)
	var written := FileAccess.get_file_as_string(SCENE_PATH)
	var ok := written.contains("name=\"%s\"" % HarborMountain.NODE_NAME)
	print("MOUNT_APPLY: %s  节点 %d → %d（新增 %d）  字节 %d" % [
		error_string(result), before, generated, generated - before, written.length()])
	print("MOUNT_NODE: %s  子节点 %d  落盘=%s" % [HarborMountain.NODE_NAME, district.get_child_count(), ok])
	root.free()
	quit(0 if (result == OK and ok) else 1)


func _remove(root: Node, node_name: StringName) -> void:
	var old := root.get_node_or_null(NodePath(node_name))
	if old:
		root.remove_child(old)
		old.free()
		print("MOUNT_APPLY: 清除旧 %s" % node_name)

## 递归把新加节点的 owner 指回场景根，只处理 owner 为空的节点。
func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = scene_root
			_own(child, scene_root)

## 备份场景文本。已存在则不覆盖：幂等重跑时不能拿"改后"的场景盖掉真正的"改造前"快照。
func _backup() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		print("MOUNT_BACKUP: 已存在，保留不动 %s" % BACKUP_PATH)
		return
	var source := FileAccess.open(SCENE_PATH, FileAccess.READ)
	if source == null:
		return
	var text := source.get_as_text()
	source.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/backups"))
	var out := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if out == null:
		print("MOUNT_BACKUP: 备份失败（%s）" % BACKUP_PATH)
		return
	out.store_string(text)
	out.close()
	print("MOUNT_BACKUP: %s" % BACKUP_PATH)

func _count(node: Node) -> int:
	var total := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		total += 1
		for child in current.get_children():
			stack.append(child)
	return total
