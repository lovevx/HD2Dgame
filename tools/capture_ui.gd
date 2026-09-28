extends SceneTree
## 系统面板风格改版验收：主菜单 / 开场取名卡片 / 角色属性面板 / 轮回商店 四连拍。
## 带渲染窗口跑（不要 --headless）：
##   godot --path . --script res://tools/capture_ui.gd

func _initialize() -> void:
	call_deferred("run")

func _shot(name: String) -> void:
	await create_timer(0.55).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/ui/%s.png" % name)
	print("UI_CAP ", name)

func run() -> void:
	await process_frame
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("res://docs/ui"):
		dir.make_dir_recursive("res://docs/ui")
	# 1. 主菜单
	var menu = load("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await _shot("menu")
	menu.free()
	# 2. 开场取名卡片
	var open = load("res://scenes/main/opening.tscn").instantiate()
	root.add_child(open)
	current_scene = open
	await process_frame
	await process_frame
	open.capture_pose(5)
	open._show_name_panel()
	await _shot("opening_name")
	open.free()
	# 3. 灰潮港角色面板
	var harbor = load("res://scenes/world/harbor.tscn").instantiate()
	root.add_child(harbor)
	current_scene = harbor
	await create_timer(1.4).timeout
	var hud: Node = null
	for n in get_nodes_in_group("hud"):
		hud = n
		break
	if hud != null and hud.has_method("show_character"):
		hud.call("show_character")
		await _shot("char_panel")
	else:
		print("UI_SKIP char_panel")
	# 4. 轮回商店
	var shop: Node = null
	for n in get_nodes_in_group("shop_panel"):
		shop = n
		break
	if shop != null:
		shop.call("open")
		await _shot("shop")
	else:
		print("UI_SKIP shop")
	quit(0)
