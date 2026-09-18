extends SceneTree
## 临时：截图主菜单与开场剧情（含取名面板），供视觉检查。
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var menu = load("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/menu_preview.png")
	menu.queue_free()
	await create_timer(0.3).timeout
	var opening = load("res://scenes/main/opening.tscn").instantiate()
	root.add_child(opening)
	current_scene = opening
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/opening_preview.png")
	# 直接跳到取名面板
	opening._show_name_panel()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/opening_name_preview.png")
	print("CAPTURE_DONE")
	quit(0)
