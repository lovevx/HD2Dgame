extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var packed = load("res://scenes/world/harbor.tscn")
	var root = packed.instantiate()
	print("HAS_SOUTHDOCK: ", root.get_node_or_null("SouthDock") != null)
	print("HAS_OLD_SHORE: ", root.get_node_or_null("ShoreBoundaryWest") != null)
	print("HAS_NEW_SHORE: ", root.get_node_or_null("ShoreBoundaryWestOuter") != null)
	quit(0)
