extends SceneTree
## 增量清空港口地面：移除外来道具、建筑与地面碎石，只留地面、码头、城墙、城门与水面船只；
## 同时把玩家活动范围与隐形屏障推到城墙内侧，让活动区与地面基座对齐。
## 用法：godot --headless --path . --script res://tools/apply_harbor_clear.gd

const SCENE_PATH := "res://scenes/world/harbor.tscn"
## 水面船只不在"地面"上，保留。
const KEEP_KEYS := ["xiaochuan"]
## 地基与墙内侧：活动区对齐到地基，屏障退到城墙内表面再内收 0.3 米。
const SPAWN_Z := Vector3(0.0, 0.0, -12.0)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var root := load(SCENE_PATH).instantiate() as Node3D
	if root == null:
		push_error("港口场景加载失败")
		quit(1)
		return
	var props := 0
	var foliage := 0
	var ships := 0
	for child in root.get_children():
		if child is HD2DProp:
			if _keeps(child):
				ships += 1
				continue
			root.remove_child(child)
			child.free()
			props += 1
		elif child is HD2DFoliage:
			root.remove_child(child)
			child.free()
			foliage += 1
	var bounds_x := 41.0
	var bounds_z := Vector2(-31.0, 25.5)
	_resize_barrier(root, "WestBoundary", Vector3(-bounds_x - 0.3, 1.0, -9.5), Vector3(0.6, 4.0, 43.0))
	_resize_barrier(root, "EastBoundary", Vector3(bounds_x + 0.3, 1.0, -9.5), Vector3(0.6, 4.0, 43.0))
	_resize_barrier(root, "NorthBoundary", Vector3(0.0, 1.0, bounds_z.x - 0.3), Vector3(82.0, 4.0, 0.6))
	var player := root.get_node_or_null("Player")
	if player:
		player.set("bounds_x", bounds_x)
		player.set("bounds_z", bounds_z)
	var error := OK
	var packed := PackedScene.new()
	error = packed.pack(root)
	if error == OK:
		error = ResourceSaver.save(packed, SCENE_PATH)
	print("HARBOR_CLEAR: props_removed=", props, " foliage_removed=", foliage, " ships_kept=", ships,
		" bounds_x=", bounds_x, " bounds_z=", bounds_z, " result=", error)
	root.free()
	quit(0 if error == OK else 1)

func _keeps(node: HD2DProp) -> bool:
	var asset: HD2DAsset = node.asset
	if asset == null:
		return false
	var path := String(asset.resource_path)
	for key in KEEP_KEYS:
		if path.contains(key):
			return true
	return false

## 屏障只改位置与盒体尺寸；这三个 BoxShape3D 各自只有一个使用者，直接改不会波及别处。
func _resize_barrier(root: Node3D, label: String, at: Vector3, size: Vector3) -> void:
	var body := root.get_node_or_null(NodePath(label)) as Node3D
	if body == null:
		push_warning("找不到屏障：" + label)
		return
	body.position = at
	var shape := body.get_child(0) as CollisionShape3D
	if shape and shape.shape is BoxShape3D:
		(shape.shape as BoxShape3D).size = size
