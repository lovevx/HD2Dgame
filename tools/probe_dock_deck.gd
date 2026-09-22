extends SceneTree
## 临时量具：网格扫描 SM_JN_matou 的甲板顶面高度，确认下沉量与可行走台阶。
## 用一根竖向射线从上往下打，记录第一个命中的高度；没有命中记为 -。
## 用法：godot --headless --path . --script res://tools/probe_dock_deck.gd

const Catalog := preload("res://tools/preset_catalog.gd")
## 世界坐标下的采样点（原始模型坐标，yaw=0）。
const SAMPLES := [
	Vector2(-7, -6), Vector2(-5, -6), Vector2(0, -6), Vector2(5, -6), Vector2(7, -6),
	Vector2(-7, -3), Vector2(0, -3), Vector2(6, -3),
	Vector2(-7, -1), Vector2(0, -1), Vector2(6, -1),
	Vector2(-7, 1), Vector2(0, 1), Vector2(6, 1),
	Vector2(-7, 3), Vector2(0, 3), Vector2(6, 3),
	Vector2(-7, 5), Vector2(0, 5), Vector2(6, 5),
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var asset: HD2DAsset = Catalog.asset("SM_JN_matou")
	if asset == null:
		print("MISSING matou")
		quit(1)
		return
	var node := asset.make_node()
	root.add_child(node)
	for point in SAMPLES:
		var from := Vector3(point.x, 20.0, point.y)
		var to := Vector3(point.x, -4.0, point.y)
		var query := PhysicsRayQueryParameters3D.create(from, to)
		var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
		var height := "-"
		if not hit.is_empty():
			height = "%.3f" % (hit["position"] as Vector3).y
		print("DECK (%6.1f, %6.1f) -> %s" % [point.x, point.y, height])
	quit(0)
