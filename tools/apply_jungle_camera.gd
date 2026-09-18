extends SceneTree
## Update camera resources only, preserving hand-authored scenery and gameplay.
const Style := preload("res://scripts/world/jungle_camera_style.gd")

func _initialize() -> void:
	for level in ["outer", "clearing"]:
		var path := "res://scenes/world/colpo_forest_%s.tscn" % level
		var scene: Node3D = load(path).instantiate()
		Style.configure(scene.get_node("Camera3D"), level == "clearing")
		scene.set("camera_focus_bounds", Style.focus_bounds(level == "clearing"))
		var packed := PackedScene.new()
		var error := packed.pack(scene)
		if error == OK:
			error = ResourceSaver.save(packed, path)
		scene.free()
		if error != OK:
			push_error("Camera save failed: " + path)
			quit(1)
			return
	print("JUNGLE_CAMERA_APPLY: PASS")
	quit()
