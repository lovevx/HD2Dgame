extends SceneTree
## Render camera-only variants without rewriting either authored level.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/camera_study")
	var scene: Node3D = load("res://scenes/world/colpo_forest_outer.tscn").instantiate()
	scene.get_node("WaveDirector").free()
	root.add_child(scene)
	current_scene = scene
	scene.set_process(false)
	var player: CharacterBody3D = scene.get_node("Player")
	player.set_physics_process(false)
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	var camera: Camera3D = scene.get_node("Camera3D")
	var variants := [
		{"name": "original_43", "pitch": 43.0, "perspective": false, "size": 16.0, "distance": 27.0, "focus": Vector3.ZERO},
		{"name": "low_ortho_30", "pitch": 30.0, "perspective": false, "size": 14.0, "distance": 30.0, "focus": Vector3(0, 1.0, -1.5)},
		{"name": "low_perspective_30", "pitch": 30.0, "perspective": true, "size": 14.0, "distance": 29.0, "focus": Vector3(0, 1.0, -1.5)},
	]
	for view in {"trail": Vector3(0, 0, 7), "hut": Vector3(-7, 0, 17)}:
		player.position = Vector3(0, 0, 7) if view == "trail" else Vector3(-7, 0, 17)
		for variant in variants:
			camera.rotation_degrees = Vector3(-variant.pitch, 8, 0)
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE if variant.perspective else Camera3D.PROJECTION_ORTHOGONAL
			camera.size = variant.size
			camera.fov = 30.0
			camera.position = player.position + variant.focus + camera.basis * Vector3(0, 0, variant.distance)
			for i in 30:
				scene._update_foreground_fade(1.0 / 30.0)
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://docs/camera_study/%s_%s.png" % [view, variant.name])
			print("CAMERA_VARIANT: ", view, " / ", variant.name)
	scene.free()
	await create_timer(0.2).timeout
	quit()
