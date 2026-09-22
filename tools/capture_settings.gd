extends SceneTree
## 设置页视觉检查：把主菜单上的四个分页各截一张，输出到 .tmp_preview/settings/。
## 必须带渲染跑（不加 --headless，dummy 驱动截不出图）：
##   godot --path . --script res://tools/capture_settings.gd
## 截图是本地产物（.tmp_preview/ 不进仓库），改了布局后重跑本脚本再看。
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var menu = load("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var panel = menu.settings_panel
	panel.open()
	for page in ["display", "audio", "gameplay", "keys"]:
		panel._select_page(page)
		await create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.tmp_preview/settings/%s.png" % page)
	print("CAPTURE_DONE")
	quit(0)
