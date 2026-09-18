extends SceneTree
## 港口外观与通行检查：截图存 docs/harbor_preview.png，并断言…
##   · 两座码头的入口都能从石板街直接走上（开口无遮挡）
##   · 码头两侧/缺口/端头拦水，水岸线其余区间拦住下海
##   · 客栈、武馆、民居、竹棚等素材建筑是实心的
##   · 石板街本身可以通行
func _initialize() -> void:
	call_deferred("capture")

## 摆好位置后等一帧，物理世界才会用新位置做扫描。
func walkable(player: CharacterBody3D, at: Vector3, towards: Vector3) -> bool:
	player.position = at
	await create_timer(0.05).timeout
	return player.test_move(player.global_transform, towards)

func capture() -> void:
	var scene = load("res://scenes/world/harbor.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.4).timeout
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var failures: Array[String] = []
	var checks := [
		{"name": "主码头入口可通行", "at": Vector3(0, 0, 10.0), "move": Vector3(0, 0, 2.4), "expect_blocked": false},
		{"name": "东码头入口可通行", "at": Vector3(22, 0, 10.0), "move": Vector3(0, 0, 2.4), "expect_blocked": false},
		{"name": "主码头东侧拦水", "at": Vector3(4, 0, 15.0), "move": Vector3(4, 0, 0), "expect_blocked": true},
		{"name": "主码头缺口拦水", "at": Vector3(3.0, 0, 16.5), "move": Vector3(0, 0, 2.4), "expect_blocked": true},
		{"name": "主码头支段端头拦水", "at": Vector3(-4.6, 0, 23.0), "move": Vector3(0, 0, 2.4), "expect_blocked": true},
		{"name": "东码头东侧拦水", "at": Vector3(26, 0, 15.0), "move": Vector3(4, 0, 0), "expect_blocked": true},
		{"name": "水岸拦水下海（西）", "at": Vector3(-20, 0, 10.0), "move": Vector3(0, 0, 2.4), "expect_blocked": true},
		{"name": "水岸拦水下海（两码头之间）", "at": Vector3(11, 0, 10.0), "move": Vector3(0, 0, 2.4), "expect_blocked": true},
		{"name": "水岸拦水下海（东）", "at": Vector3(31, 0, 6.0), "move": Vector3(0, 0, 6.0), "expect_blocked": true},
		{"name": "客栈是带院落的屋舍，正面可走入", "at": Vector3(-20, 0, -7.0), "move": Vector3(0, 0, -2.4), "expect_blocked": false},
		{"name": "强化台实心", "at": Vector3(11, 0, -10.5), "move": Vector3(0, 0, -2), "expect_blocked": true},
		{"name": "城门中央主路可通行", "at": Vector3(0, 0, -14.0), "move": Vector3(0, 0, -7), "expect_blocked": false},
		{"name": "竹棚实心", "at": Vector3(-9, 0, 10.4), "move": Vector3(0, 0, -2.8), "expect_blocked": true},
		{"name": "石板街可通行", "at": Vector3(-4, 0, -4.0), "move": Vector3(0, 0, 3), "expect_blocked": false},
		{"name": "城门以北拦住", "at": Vector3(-28, 0, -26.0), "move": Vector3(0, 0, -4), "expect_blocked": true},
	]
	for check in checks:
		var blocked: bool = await walkable(player, check["at"], check["move"])
		if blocked == bool(check["expect_blocked"]):
			print("HARBOR_CHECK: PASS  %s" % check["name"])
		else:
			failures.append(str(check["name"]))
			print("HARBOR_CHECK: FAIL  %s（期望%s，实际%s）" % [check["name"], "阻挡" if check["expect_blocked"] else "可走", "阻挡" if blocked else "可走"])
	player.position = Vector3(0, 0, -9.0)
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/harbor_preview.png")
	# 第二张：站在主码头支段上，确认甲板可见、与石板街齐平。
	player.position = Vector3(-4.6, 0, 21.0)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/harbor_pier_preview.png")
	print("HARBOR_CAPTURE: %s" % ("PASS" if failures.is_empty() else "FAIL " + ", ".join(failures)))
	quit(0 if failures.is_empty() else 1)

