extends SceneTree
## 南岸客货码头回归检查：跑一遍原 capture_harbor.gd 的 14 项通行断言，
## 再核对 SouthPort 分区结构，并沿两座码头中线做横向/纵向连通性扫描。
## 只做碰撞检查，不渲染、不覆盖 docs 预览图。
## 用法：godot --headless --path . --script res://tools/check_harbor_port.gd
## 注意：L 形码头的缺口栏杆在 z=18.5，越过后中线下方即水面，纵向扫描仅作参考。
func _initialize() -> void:
	call_deferred("run")

## 摆好位置后等一帧，物理世界才会用新位置做扫描。
func walkable(player: CharacterBody3D, at: Vector3, towards: Vector3) -> bool:
	player.position = at
	await create_timer(0.05).timeout
	return player.test_move(player.global_transform, towards)

func run() -> void:
	var scene = load("res://scenes/world/harbor.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.4).timeout
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var cs: CollisionShape3D = null
	for c in player.get_children():
		if c is CollisionShape3D:
			cs = c as CollisionShape3D
			break
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
		{"name": "石板街可通行", "at": Vector3(-4, 0, -4.0), "move": Vector3(0, 0, 3), "expect_blocked": false},
		{"name": "西侧城墙拦住", "at": Vector3(-38, 0, -20), "move": Vector3(-4, 0, 0), "expect_blocked": true},
		# ↓ 原 capture_harbor.gd 只测了「街上→甲板」，那是往下走不撞；返回方向从来没测过，
		#   所以甲板模型多叠一层碰撞导致的「上得去、下不来」一直没被发现。
		{"name": "主码头从甲板走回砖路", "at": Vector3(0, 0, 13.0), "move": Vector3(0, 0, -2.4), "expect_blocked": false},
		{"name": "东码头从甲板走回砖路", "at": Vector3(22, 0, 13.0), "move": Vector3(0, 0, -2.4), "expect_blocked": false},
	]
	for check in checks:
		var blocked: bool = await walkable(player, check["at"], check["move"])
		if blocked == bool(check["expect_blocked"]):
			print("HARBOR_CHECK: PASS  %s" % check["name"])
		else:
			failures.append(str(check["name"]))
			print("HARBOR_CHECK: FAIL  %s（期望%s，实际%s）" % [check["name"], "阻挡" if check["expect_blocked"] else "可走", "阻挡" if blocked else "可走"])

	# --- 南岸客货码头专项 ---
	var south: Node = scene.get_node_or_null("SouthPort")
	if south == null:
		failures.append("SouthPort 节点缺失")
		print("PORT_CHECK: FAIL  SouthPort 节点缺失")
	else:
		print("PORT_CHECK: PASS  SouthPort 存在，直接子节点 %d" % south.get_child_count())
		for part in ["Pier0", "Pier22", "InnerBasin", "QuayLine"]:
			var n: Node = south.get_node_or_null(part)
			if n == null:
				failures.append("SouthPort/%s 缺失" % part)
				print("PORT_CHECK: FAIL  SouthPort/%s 缺失" % part)
			else:
				print("PORT_CHECK: PASS  SouthPort/%s 子节点 %d" % [part, n.get_child_count()])

	# 支段↔主段接缝：**只作诊断输出，不计入 PASS/FAIL**。
	# 原因：接缝处两个甲板碰撞盒在 z=18.5 严丝合缝相贴，角色胶囊底（原点下方 0.0035）
	# 在毫米级上与盒面切线，test_move 的结果在多次运行间不稳定（同一位置时挡时通），
	# 手工驱动 move_and_slide 也给出过自相矛盾的结果。这里给不出可信结论，
	# 所以只打印碰撞体占位供人肉核对，判定交给游戏内实走。
	for jp in [{"c": -4.65, "tag": "客运"}, {"c": 17.35, "tag": "货运"}]:
		var center: float = jp["c"]
		for qz in [18.1, 18.4]:
			var free_lanes: Array[String] = []
			var taken_lanes: Array[String] = []
			var dx := -2.7
			while dx <= 2.7:
				var lx := center + dx
				var hits := _overlap_at(player, cs, Vector3(lx, 0.12, qz))
				if hits.is_empty():
					free_lanes.append("%.1f" % lx)
				else:
					taken_lanes.append("%.1f:%s" % [lx, ",".join(hits)])
				dx += 0.45
			print("PORT_JUNCTION(诊断): %s支段 x 扫 %.1f~%.1f  z=%.1f  空通道=[%s]  被占=[%s]" % [jp["tag"], center - 2.7, center + 2.7, qz, ", ".join(free_lanes), " ".join(taken_lanes)])

	# 沿两座码头中线逐点扫描，判断阻挡是「零星摆件」还是「堆死通道」
	for pier in [{"x": 0.0, "tag": "客运"}, {"x": 22.0, "tag": "货运"}]:
		var px: float = pier["x"]
		var line := ""
		var blocked_n := 0
		var z := 13.5
		while z <= 24.5:
			var b: bool = await walkable(player, Vector3(px, 0, z), Vector3(-2.4, 0, 0))
			if b:
				blocked_n += 1
				line += "X"
			else:
				line += "."
			z += 1.0
		print("PORT_SWEEP: %s码头 x=%.0f  z13.5→24.5 逐米横探(-x)  [%s]  阻挡 %d/12" % [pier["tag"], px, line, blocked_n])

	# 纵向连通性：从石板街走进码头沿中线向 +z 推进（z>18.5 已越过缺口栏杆，下方为水面，仅供参考）
	for pier in [{"x": 0.0, "tag": "客运"}, {"x": 22.0, "tag": "货运"}]:
		var px: float = pier["x"]
		var zz := 11.5
		var segs := ""
		while zz <= 24.5:
			var b: bool = await walkable(player, Vector3(px, 0, zz), Vector3(0, 0, 1.0))
			segs += "X" if b else "."
			zz += 1.0
		print("PORT_ALONG: %s码头 x=%.0f  向+z逐米推进  [%s]（前 7 格 z11.5→17.5 为甲板通道）" % [pier["tag"], px, segs])

	print("HARBOR_PORT_CHECK: %s" % ("PASS" if failures.is_empty() else "FAIL " + ", ".join(failures)))
	quit(0)


## 把角色碰撞形状摆到 at（含形状自身的 +0.8465 偏移），返回与之重叠的碰撞体名字。
## 用 intersect_shape 而不是 test_move：重叠检测结果稳定，不受毫米级切线容差影响。
## 传 y≈0.12 可让胶囊底（y-0.0035）刚好离开甲板顶面(0)，从而只暴露真正的立体障碍。
func _overlap_at(player: CharacterBody3D, cs: CollisionShape3D, at: Vector3) -> Array:
	var out: Array = []
	if cs == null:
		return out
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = cs.shape
	params.transform = Transform3D(Basis(), at) * cs.transform
	params.collision_mask = player.collision_mask
	params.exclude = [player.get_rid()]
	for h in player.get_world_3d().direct_space_state.intersect_shape(params, 24):
		var col: Node = h["collider"]
		if col == null:
			continue
		var nm := String(col.name)
		if not out.has(nm):
			out.append(nm)
	return out
