extends SceneTree
## Deterministic art review; keeps production gameplay scripts untouched.
var output := "res://docs/jungle_after"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(output)
	for level in ["outer", "clearing"]:
		var scene: Node3D = load("res://scenes/world/colpo_forest_%s.tscn" % level).instantiate()
		for name in ["WaveDirector", "BossDirector"]:
			var director := scene.get_node_or_null(name)
			if director:
				director.free()
		root.add_child(scene)
		current_scene = scene
		var player: CharacterBody3D = scene.get_node("Player")
		player.set_physics_process(false)
		for child in scene.get_children():
			if child is CanvasLayer:
				child.visible = false
		var views := {"entry": Vector3(0, 0, 18), "trail": Vector3(0, 0, 7), "exit": Vector3(0, 0, -16), "hut": Vector3(-7, 0, 17)} if level == "outer" else {"arena": Vector3(0, 0, 3), "north": Vector3(0, 0, -12)}
		for view in views:
			player.position = views[view]
			await create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			var path := output.path_join(level + "_" + view + ".png")
			root.get_texture().get_image().save_png(path)
			print("JUNGLE_CAPTURE: %s | draw_calls=%d objects=%d fps=%d" % [path, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Engine.get_frames_per_second()])
		# Let queued renderer/physics work finish before destroying a level.
		await process_frame
		scene.free()
		await process_frame
	var palette: Node3D = load("res://scenes/workshop/jungle_palette.tscn").instantiate()
	root.add_child(palette)
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("palette.png"))
	palette.free()
	await create_timer(0.25).timeout
	quit()
