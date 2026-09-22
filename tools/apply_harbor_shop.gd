extends SceneTree
## 把左上商店区「轮回商店」增量装进已生成的 scenes/world/harbor.tscn，不改动其它既有内容。
## 布局集中在 tools/harbor_shop.gd；改布局后重跑本脚本即可（幂等：先删旧 ShopDistrict 再重建）。
##
## 做三件事：
##   1. 在根节点下增删 ShopDistrict：店面小楼、门面陈设、集市角、青色灯带。
##   2. 把商店服务点从主街西段旧位（-10, 0, -9）搬到店面正前方（HarborShop.SERVICE_AT）：
##      ShopService / ShopServiceRing / ShopServiceSign 与 ShopZone 三个分区标记节点一起搬家。
##   3. 回写 scenes/world/harbor.tscn（先备份到 tools/backups/，已存在则不覆盖）。
##
## 用法：godot --headless --path . --script res://tools/apply_harbor_shop.gd

const HarborShop := preload("res://tools/harbor_shop.gd")
const SCENE_PATH := "res://scenes/world/harbor.tscn"
const BACKUP_PATH := "res://tools/backups/harbor_before_shop.tscn.bak"

## 服务点相关节点名 → 相对服务点的偏移（与 build_harbor.gd / harbor_zones.gd 的装配口径一致）。
const SERVICE_PARTS := {
	"ShopService": Vector3.ZERO,
	"ShopServiceRing": Vector3(0, 0.06, 0),
	"ShopServiceSign": Vector3(0, 2.5, 0),
	"ShopZone": Vector3.ZERO,
	"ShopZone_Disc": Vector3(0, 0.045, 0),
	"ShopZone_Label": Vector3(0, 2.6, 0),
}

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
	_remove(root, HarborShop.NODE_NAME)
	root.add_child(HarborShop.make_node())
	var moved := _relocate_service(root)
	var district := root.get_node_or_null(NodePath(HarborShop.NODE_NAME))
	if district == null:
		push_error("ShopDistrict 未生成")
		quit(1)
		return
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
	var ok := written.contains("name=\"%s\"" % HarborShop.NODE_NAME)
	print("SHOP_APPLY: %s  节点 %d → %d（新增 %d）  服务点搬家 %d 处" % [
		error_string(result), before, generated, generated - before, moved])
	print("SHOP_NODE: %s  子节点 %d  落盘=%s  字节=%d" % [HarborShop.NODE_NAME, district.get_child_count(), ok, written.length()])
	root.free()
	quit(0 if (result == OK and ok) else 1)


## 把服务点与分区标记挪到店面正前方，并把招牌与文案改成「轮回商店」。
## 直接写绝对坐标/文案（幂等：重跑结果一致）。
func _relocate_service(root: Node) -> int:
	var moved := 0
	for part in SERVICE_PARTS:
		var node := root.get_node_or_null(NodePath(part))
		if node == null:
			print("SHOP_APPLY: 缺少节点 %s，跳过" % part)
			continue
		var offset: Vector3 = SERVICE_PARTS[part]
		node.position = HarborShop.SERVICE_AT + offset
		moved += 1
		print("SHOP_APPLY: %-16s → (%.1f, %.1f, %.1f)" % [part, node.position.x, node.position.y, node.position.z])
	# 服务点文案：交互提示、面板标题与说明、悬浮招牌全部对齐「轮回商店」。
	var service := root.get_node_or_null(NodePath("ShopService"))
	if service != null:
		service.set("title", "商店 · 轮回商店")
		service.set("description", "左上街角的轮回商店\n\n药剂补给  /  武具防具  /  消耗与材料\n\n商店交易框架已就绪，商品与经济系统待接入。")
	var sign := root.get_node_or_null(NodePath("ShopServiceSign"))
	if sign != null:
		sign.text = "商店 · 轮回商店"
		sign.modulate = Color("8ee8f7")
	return moved


func _remove(root: Node, node_name: String) -> void:
	var old := root.get_node_or_null(NodePath(node_name))
	if old:
		root.remove_child(old)
		old.free()
		print("SHOP_APPLY: 清除旧 %s" % node_name)

## 递归把新加节点的 owner 指回场景根，只处理 owner 为空的节点。
func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		if child.owner == null:
			child.owner = scene_root
			_own(child, scene_root)

## 备份场景文本。已存在则不覆盖：幂等重跑时不能拿"改后"的场景盖掉真正的"改造前"快照。
func _backup() -> void:
	if FileAccess.file_exists(BACKUP_PATH):
		print("SHOP_BACKUP: 已存在，保留不动 %s" % BACKUP_PATH)
		return
	var source := FileAccess.open(SCENE_PATH, FileAccess.READ)
	if source == null:
		return
	var text := source.get_as_text()
	source.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/backups"))
	var out := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
	if out == null:
		print("SHOP_BACKUP: 备份失败（%s）" % BACKUP_PATH)
		return
	out.store_string(text)
	out.close()
	print("SHOP_BACKUP: %s" % BACKUP_PATH)

func _count(node: Node) -> int:
	var total := 0
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		total += 1
		for child in current.get_children():
			stack.append(child)
	return total
