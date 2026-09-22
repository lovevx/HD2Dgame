extends SceneTree
## 把东侧「铸潮工坊」与西侧「港务委托所」两处功能区陈设增量装进已生成的
## scenes/world/harbor.tscn，不改动其它既有内容。
## 布局分别在 tools/harbor_forge.gd 与 tools/harbor_quest.gd；改布局后重跑本脚本即可
## （幂等：先删旧 ForgeDistrict / QuestDistrict 再重建）。
##
## 做三件事：
##   1. 在根节点下增删 ForgeDistrict：锻造铺面两栋、熔炉烟囱、锻造台、武器架、淬火缸、矿石标本与炉火灯。
##   2. 在根节点下增删 QuestDistrict：委托所主楼与副楼、门前公告板与柜台、前院、巷南侧坐具与招幌。
##   3. 回写 scenes/world/harbor.tscn（先备份到 tools/backups/，已存在则不覆盖），
##      并自检两个服务点是否仍落在布局模块声明的 SERVICE_AT 上（防止将来"服务点搬了家、布局没跟"）。
##
## 用法：godot --headless --path . --script res://tools/apply_harbor_hub_districts.gd

const HarborForge := preload("res://tools/harbor_forge.gd")
const HarborQuest := preload("res://tools/harbor_quest.gd")
const SCENE_PATH := "res://scenes/world/harbor.tscn"
const BACKUP_PATH := "res://tools/backups/harbor_before_hub_districts.tscn.bak"

## 布局模块与对应服务点：装完后核对服务点是否还在布局声明的圆心。
const DISTRICTS := [
	{"module": HarborForge, "node": HarborForge.NODE_NAME, "service": "ForgeService", "at": HarborForge.SERVICE_AT},
	{"module": HarborQuest, "node": HarborQuest.NODE_NAME, "service": "QuestService", "at": HarborQuest.SERVICE_AT},
]

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
	for entry in DISTRICTS:
		var district: Node3D = entry["module"].make_node()
		_remove(root, district.name)
		root.add_child(district)
		print("HUB_APPLY: %s 子节点 %d" % [district.name, district.get_child_count()])
	# 新增节点必须把 owner 指回场景根，否则 pack 时会静默丢掉。
	_own(root, root)
	var missing := _check_services(root)
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
	var ok := true
	for entry in DISTRICTS:
		var marker := "name=\"%s\"" % entry["node"]
		if not written.contains(marker):
			ok = false
			push_error("落盘内容缺少 " + marker)
	print("HUB_APPLY: %s  节点 %d → %d（新增 %d）  字节 %d" % [
		error_string(result), before, generated, generated - before, written.length()])
	print("HUB_SERVICES: %s" % ("全部就位" if missing.is_empty() else "位置不符 " + str(missing)))
	root.free()
	quit(0 if (result == OK and ok and missing.is_empty()) else 1)


## 核对服务点是否仍落在布局模块声明的圆心（只报告，不改动位置）。
func _check_services(root: Node) -> Array:
	var bad: Array[String] = []
	for entry in DISTRICTS:
		var service := root.get_node_or_null(NodePath(entry["service"]))
		if service == null:
			bad.append("%s 缺失" % entry["service"])
			continue
		var at: Vector3 = entry["at"]
		var delta: Vector3 = service.position - at
		var flat := Vector2(delta.x, delta.z).length()
		print("HUB_APPLY: %-14s (%.1f, %.1f, %.1f)  与声明的位置差 %.2f m" % [
			entry["service"], service.position.x, service.position.y, service.position.z, flat])
		if flat > 0.25:
			bad.append("%s（差 %.2f m）" % [entry["service"], flat])
	return bad


func _remove(root: Node, node_name: StringName) -> void:
	var old := root.get_node_or_null(NodePath(node_name))
	if old:
		root.remove_child(old)
		old.free()
		print("HUB_APPLY: 清除旧 %s" % node_name)

## 递归把新加节点的 owner 指回场景根，只处理 owner 为空的节点。
func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = scene_root
			_own(child, scene_root)

## 备份场景文本。已存在则不覆盖：幂等重跑时不能拿"改后"的场景盖掉真正的"改造前"快照。
func _backup() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		print("HUB_BACKUP: 已存在，保留不动 %s" % BACKUP_PATH)
		return
	var source := FileAccess.open(SCENE_PATH, FileAccess.READ)
	if source == null:
		return
	var text := source.get_as_text()
	source.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/backups"))
	var out := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if out == null:
		print("HUB_BACKUP: 备份失败（%s）" % BACKUP_PATH)
		return
	out.store_string(text)
	out.close()
	print("HUB_BACKUP: %s" % BACKUP_PATH)

func _count(node: Node) -> int:
	var total := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		total += 1
		for child in current.get_children():
			stack.append(child)
	return total
