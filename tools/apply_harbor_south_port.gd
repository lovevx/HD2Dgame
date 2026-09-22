extends SceneTree
## 把南岸客货码头增量装进已生成的 scenes/world/harbor.tscn，不改动其它既有内容。
## 布局集中在 tools/harbor_port_layout.gd；改布局后重跑本脚本即可（幂等：先删旧 SouthPort 再重建）。
##
## 做三件事：
##   1. 在根节点下增删 SouthPort：两座 L 形码头的木作外观、客/货运陈设、中间内港、南岸沿线系泊石作。
##   2. 拆掉 HarborWall 砌在内港喉口上的那段旧南岸矮墙（3.64 米高，正好把泊位封死）。
##      当前 tools/harbor_walls.gd 的南面本就「不砌墙，临水一面交给石砌驳岸与码头」，
##      场景里的这段墙是上一版生成物；拆开后内港才看得见，与当前管线意图一致。
##   3. 回写 scenes/world/harbor.tscn（先备份到 tools/backups/）。
##
## 不动的东西：Pier0Deck / Pier0LegDeck / Pier*Rail* 等甲板碰撞盒体、水域屏障（含 ShoreBoundaryMiddle）、
## 玩家活动范围，全部沿用 build_harbor.gd 已生成的样子——本脚本只补外观。
##
## 用法：godot --headless --path . --script res://tools/apply_harbor_south_port.gd

const Layout := preload("res://tools/harbor_port_layout.gd")
const SCENE_PATH := "res://scenes/world/harbor.tscn"
const BACKUP_PATH := "res://tools/backups/harbor_before_south_port.tscn.bak"

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
	_remove(root, Layout.NODE_NAME)
	var mats := _materials(root)
	if mats.is_empty():
		push_error("找不到 HarborWall 的石作材质，无法取到驳岸材质")
		quit(1)
		return
	_open_basin_mouth(root)
	root.add_child(Layout.make_node(mats))
	var port := root.get_node_or_null(NodePath(Layout.NODE_NAME))
	if port == null:
		push_error("SouthPort 未生成")
		quit(1)
		return
	# 新增节点必须把 owner 指回场景根，否则 pack 时会静默丢掉。
	_own(root, root)
	var generated := _count(root)
	# 注意：必须用变量接住新建的 PackedScene。写成 PackedScene.new().pack(root) 会把新场景丢掉，
	# 后面 ResourceSaver.save 保存的仍是 load() 进来的旧场景，新增节点静默消失。
	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result != OK:
		push_error("打包失败：%s" % error_string(result))
		quit(1)
		return
	result = ResourceSaver.save(scene, SCENE_PATH)
	# 落盘校验：重新从文件读回文本，确认新增节点确实写进去了。
	var written := FileAccess.get_file_as_string(SCENE_PATH)
	var ok := written.contains("name=\"%s\"" % Layout.NODE_NAME)
	print("PORT_APPLY: %s  节点 %d → %d（新增 %d）" % [error_string(result), before, generated, generated - before])
	print("PORT_NODE: %s  子节点 %d  落盘=%s  字节=%d" % [Layout.NODE_NAME, port.get_child_count(), ok, written.length()])
	print("PORT_DETAIL: %s" % _report(port))
	root.free()
	quit(0 if (result == OK and ok) else 1)


## 分层统计新节点，便于核对陈设确实落进来了。
func _report(port: Node) -> String:
	var parts: Array[String] = []
	for group in port.get_children():
		parts.append("%s=%d" % [group.name, _count(group) - 1])
	return "  ".join(parts)


## 递归把新加节点的 owner 指回场景根，只处理 owner 为空的节点。
func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = scene_root
			_own(child, scene_root)


## 备份场景文本，便于回滚。
## 已存在则不覆盖：本脚本是幂等的、会反复重跑，若无条件覆盖，第二次运行就会用「改后」的场景
## 盖掉真正的「改造前」快照，失去回滚点。
func _backup() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		print("PORT_BACKUP: 已存在，保留不动 %s" % BACKUP_PATH)
		return
	var source := FileAccess.open(SCENE_PATH, FileAccess.READ)
	if source == null:
		return
	var text := source.get_as_text()
	source.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/backups"))
	var out := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if out == null:
		print("PORT_BACKUP: 备份失败（%s）" % BACKUP_PATH)
		return
	out.store_string(text)
	out.close()
	print("PORT_BACKUP: %s" % BACKUP_PATH)

func _remove(root: Node, node_name: String) -> void:
	var old := root.get_node_or_null(NodePath(node_name))
	if old:
		root.remove_child(old)
		old.free()
		print("PORT_APPLY: 清除旧 %s" % node_name)

## 拆掉 HarborWall 砌在内港喉口上的旧南岸矮墙。
## 这些片段是上一版 harbor_walls.gd 生成的（当前版本的南面已不砌墙），名字被 Godot 自动改成了
## @MeshInstance3D@N，无法靠名字识别，所以按落点坐标筛：喉口 x 区间内、且贴在水岸线上。
func _open_basin_mouth(root: Node) -> void:
	var wall := root.get_node_or_null(NodePath("HarborWall"))
	if wall == null:
		print("PORT_APPLY: 未找到 HarborWall，跳过拆墙")
		return
	var span: Vector2 = Layout.BASIN_MOUTH
	var doomed: Array[Node] = []
	for child in wall.get_children():
		if not child is MeshInstance3D:
			continue
		var at := (child as Node3D).position
		if at.x >= span.x - 1.0 and at.x <= span.y + 1.0 and at.z >= 10.0 and at.z <= 13.0:
			doomed.append(child)
	for node in doomed:
		print("PORT_APPLY: 拆内港喉口墙段 %-22s (%.2f, %.2f, %.2f)" % [node.name, node.position.x, node.position.y, node.position.z])
		wall.remove_child(node)
		node.free()
	print("PORT_APPLY: 内港喉口打开 x %.3f ~ %.3f，拆除 %d 段" % [span.x, span.y, doomed.size()])

## 驳岸与码头用城墙同一套石作材质，直接取场景里 HarborWall 已经序列化的材质，避免重复定义。
func _materials(root: Node) -> Dictionary:
	var wall := root.get_node_or_null(NodePath("HarborWall"))
	if wall == null:
		return {}
	var base: Material = null
	var eave: Material = null
	for child in wall.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh := child as MeshInstance3D
		if mesh.name.ends_with("_base") and base == null:
			base = mesh.material_override
		elif mesh.name.ends_with("_eave") and eave == null:
			eave = mesh.material_override
		if base and eave:
			break
	if base == null or eave == null:
		return {}
	return {"base": base, "eave": eave, "body": base, "ridge": eave}

func _count(node: Node) -> int:
	var total := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		total += 1
		for child in current.get_children():
			stack.append(child)
	return total
