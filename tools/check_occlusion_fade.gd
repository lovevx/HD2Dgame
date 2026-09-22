extends SceneTree
## 前景遮挡淡出回归检查：核对「镜头与玩家之间被大体量景物挡住 → 那件景物淡出」是否按预期工作。
## 只读场景与运行时状态，不渲染、不覆盖 docs 预览图。
## 用法：godot --headless --path . --script res://tools/check_occlusion_fade.gd
##
## 断言：
##   1) 藏在景物正北（镜头这一面被挡）的落点，能点亮对应的淡出单元；
##   2) 开阔主街 / 石板街不误淡；
##   3) 淡出真的落到材质上（可见网格拿到淡出材质、occl_fade < 1）；
##   4) 让开后单元收掉、材质还原，场景回到实体状态；
##   5) 单个淡出单元不吞掉整圈城墙（叠层合并不该退化成"一挡淡全部"）；
##   6) 同一处摆件成簇：只压到渔网时，紧挨着的竹棚要一起淡，
##      但不能把码头那种大平台拖进淡出单元（脚下的栈桥不该透明）。
##
## 落点是实测确认过的：港口是「相机固定偏移跟随玩家」的机位（俯角 16°、位于玩家正南约 43 米），
## 所以会挡人的永远是**玩家正南那条窄列里、够高**的景物 —— 城墙、临水矮墙、码头棚、招牌、船。
## 注意：相机是 lerp 跟随（约 1.7 秒收敛），落点后必须等够，否则射线整条偏掉、结论不可信。
func _initialize() -> void:
	call_deferred("run")

const SETTLE := 2.0

const PROBES := [
	{"name": "南岸临水矮墙后", "at": Vector3(-20, 0, 9.5), "expect_occluded": true},
	{"name": "客运码头竹棚后", "at": Vector3(-5.7, 0, 13.0), "expect_occluded": true},
	{"name": "货运码头装卸棚后", "at": Vector3(16.5, 0, 11.5), "expect_occluded": true},
	{"name": "主街开阔地", "at": Vector3(0, 0, -12), "expect_occluded": false},
	{"name": "石板街中段", "at": Vector3(-4, 0, -4), "expect_occluded": false},
	# 新区探针（2026-09-20 覆盖面诊断后固化：tools/probe_occlusion_coverage.gd 全图扫描）。
	{"name": "东侧民居坊后", "at": Vector3(24, 0, -18), "expect_occluded": true},
	{"name": "商店区走廊南侧遮挡", "at": Vector3(-30, 0, -18), "expect_occluded": true},
	{"name": "北门广场开阔地", "at": Vector3(0, 0, -24), "expect_occluded": false},
]

const WALL_NODE := "HarborWall"

func _fade_controller(scene: Node) -> Node:
	var player: Node = scene.get_node_or_null("Player")
	if player == null:
		return null
	return player.get_node_or_null("CameraOcclusionFade")

## 把玩家挪到指定落点，等相机跟随收敛、淡出爬到稳态。
func _settle(player: Node3D, at: Vector3) -> void:
	player.global_position = at
	await create_timer(SETTLE).timeout

## 当前真正挂着淡出材质、且已经比实体透明的网格。
func _faded_meshes(scene: Node) -> Array[String]:
	var out: Array[String] = []
	for kind in ["MeshInstance3D", "MultiMeshInstance3D"]:
		for node in scene.find_children("*", kind, true, false):
			var inst := node as GeometryInstance3D
			if inst == null:
				continue
			if inst.material_override is ShaderMaterial:
				var sm := inst.material_override as ShaderMaterial
				if sm.shader != null and sm.shader.resource_path.contains("occlusion_fade"):
					var a = inst.get_instance_shader_parameter("occl_fade")
					if a != null and float(a) < 0.999:
						out.append("%s=%.2f" % [inst.name, float(a)])
			elif inst.material_override is StandardMaterial3D \
					and (inst.material_override as StandardMaterial3D).resource_name == "occl_fade_clone":
				# 标准材质克隆路径（SCISSOR 材质转 ALPHA）：淡出值在 albedo_color.a 上。
				var a2 := (inst.material_override as StandardMaterial3D).albedo_color.a
				if a2 < 0.999:
					out.append("%s(clone=%.2f)" % [inst.name, a2])
			elif inst.transparency > 0.001:
				out.append("%s(transparency)=%.2f" % [inst.name, inst.transparency])
	return out

func run() -> void:
	var scene = load("res://scenes/world/harbor.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.4).timeout

	var wall = scene.get_node_or_null(WALL_NODE)
	var wall_meshes := 0
	if wall != null:
		for kind in ["MeshInstance3D", "MultiMeshInstance3D"]:
			wall_meshes += wall.find_children("*", kind, true, false).size()

	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var controller := _fade_controller(scene)
	if controller == null:
		print("FADE_CHECK: FAIL  玩家身上找不到 CameraOcclusionFade（player.gd 未接入？）")
		quit(1)
		return
	print("FADE_CHECK: 控制器就位；%s 下合计 %d 个网格（用于判断淡出单元粒度）" % [WALL_NODE, wall_meshes])

	var failures: Array[String] = []

	for probe in PROBES:
		await _settle(player, probe["at"])
		var units: Dictionary = controller.active_units()
		var occluded: bool = not units.is_empty()
		var tag := "PASS" if occluded == bool(probe["expect_occluded"]) else "FAIL"
		if tag == "FAIL":
			failures.append(probe["name"])
		print("FADE_CHECK: %s  %s  @%s  单元数=%d" % [tag, probe["name"], probe["at"], units.size()])
		for key in units:
			var entry: Dictionary = units[key]
			var parts: Array = entry["parts"]
			print("    └ 单元「%s」t=%.2f  含 %d 个网格  [%s]" % [key, float(entry["t"]), parts.size(), ", ".join(parts)])
			if wall_meshes > 0 and parts.size() >= wall_meshes:
				failures.append("%s 的淡出单元吞掉了整圈城墙（%d/%d）" % [probe["name"], parts.size(), wall_meshes])

	# --- 淡出是否真的落到材质上 ---
	await _settle(player, Vector3(-20, 0, 9.5))
	var faded := _faded_meshes(scene)
	if faded.is_empty():
		failures.append("遮挡位没有网格真正变透明")
		print("FADE_CHECK: FAIL  遮挡位检测到单元，但没有任何网格拿到淡出材质")
	else:
		print("FADE_CHECK: PASS  遮挡位实际变透明的网格 %d 个：%s" % [faded.size(), ", ".join(faded)])

	# --- 让开后恢复实体 ---
	await _settle(player, Vector3(0, 0, -12))
	await create_timer(0.5).timeout
	var left: Dictionary = controller.active_units()
	var still_invisible := _faded_meshes(scene)
	if left.is_empty() and still_invisible.is_empty():
		print("FADE_CHECK: PASS  离开遮挡位后单元收掉、材质已还原")
	else:
		failures.append("离开遮挡位后未完全恢复")
		print("FADE_CHECK: FAIL  离开遮挡位后仍残留 单元=%d 变透明网格=%s" % [left.size(), ", ".join(still_invisible)])

	# --- 同一处摆件成簇 ---
	# 码头东端竹棚与渔网是挨着摆的两件摆件。贴矮墙走到 x=-8 时只压到渔网，
	# 早先的版本只淡命中的那一件，看着就是"墙透明了、紧挨着的竹棚却没透明"。
	await _settle(player, Vector3(-8, 0, 9.5))
	var cluster: Dictionary = controller.active_units()
	var cluster_parts := 0
	var cluster_name := ""
	for key in cluster:
		if key.contains("ZhuPengzi") or key.contains("yuwang"):
			cluster_parts = (cluster[key]["parts"] as Array).size()
			cluster_name = key
	if cluster_parts >= 2:
		print("FADE_CHECK: PASS  同一处摆件成簇：单元「%s」含 %d 件（竹棚跟着渔网一起淡）" % [cluster_name, cluster_parts])
	else:
		failures.append("同一处摆件没成簇（竹棚没跟着渔网一起淡）")
		print("FADE_CHECK: FAIL  码头东端只淡了 %d 件，单元=%s" % [cluster_parts, str(cluster.keys())])

	# --- 混合材质单元：四条平行数组必须等长（越界回归）---
	# 同一个淡出单元里可能既有标准材质网格、也有自定义着色器网格（"预设摆件 + 程序化网格"
	# 并进同簇就是这样）。早先 originals 只在 shader 模式下 append，收尾按 originals[i] 取
	# 就会索引越界：_end_unit 报 Invalid access of index N（商店区落地后在实机里真的触发过）。
	var mixed := _mixed_unit_probe(scene, controller)
	var aligned: bool = int(mixed["instances"]) == int(mixed["modes"]) \
		and int(mixed["modes"]) == int(mixed["fades"]) \
		and int(mixed["fades"]) == int(mixed["originals"]) \
		and int(mixed["originals"]) == int(mixed["shadows"])
	if aligned and int(mixed["shader_parts"]) >= 1 and int(mixed["instances"]) >= 2:
		print("FADE_CHECK: PASS  混合材质单元的平行数组等长（%d 格，含 %d 个着色器网格）" % [
			int(mixed["instances"]), int(mixed["shader_parts"])])
	else:
		failures.append("混合材质单元平行数组不等长（收尾会索引越界）")
		print("FADE_CHECK: FAIL  混合单元 instances=%d modes=%d fades=%d originals=%d shadows=%d shader=%d" % [
			int(mixed["instances"]), int(mixed["modes"]), int(mixed["fades"]), int(mixed["originals"]),
			int(mixed["shadows"]), int(mixed["shader_parts"])])
	if not bool(mixed["restored"]):
		failures.append("混合材质单元收尾没有还原材质")
		print("FADE_CHECK: FAIL  混合材质单元收尾后材质没还原")

	print("OCCLUSION_FADE_CHECK: %s" % ("PASS" if failures.is_empty() else "FAIL  " + "; ".join(failures)))
	quit(0 if failures.is_empty() else 1)

## 人造一个"标准材质 + 自定义着色器"混在一起的淡出单元，验证平行数组等长、能收尾还原。
## 注意：**先比长度、再收尾** —— 万一将来又错位，这里要干净地记 FAIL，而不是在 _end_unit 里
## 抛越界错误把整个脚本中断（脚本不 quit 会表现为无头运行无限挂起）。
func _mixed_unit_probe(scene: Node, controller: Node) -> Dictionary:
	var holder := Node3D.new()
	holder.name = "MixedFadeProbe"
	scene.add_child(holder)
	holder.global_position = Vector3(0, 0, -12)
	holder.add_to_group("occlusion_ignore")
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 2.0, 1.4)
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://addons/hd2d_scene_tools/shaders/preset_normal.gdshader")
	for i in 4:
		var inst := MeshInstance3D.new()
		inst.name = "MixedFade%d" % i
		inst.mesh = box
		holder.add_child(inst)
		inst.global_position = Vector3(0, 1.0, 0)
		# 索引 3 就是旧代码越界的那一格：前面 3 个标准材质不占 originals。
		if i == 3:
			inst.material_override = shader_mat
	var entry: Dictionary = controller._begin_unit(holder, [holder.get_child(0)])
	var counts := {"instances": 0, "modes": 0, "fades": 0, "originals": 0, "shadows": 0}
	for field in counts:
		counts[field] = (entry[field] as Array).size()
	var shader_parts := 0
	for mode in entry["modes"]:
		if str(mode) == "shader":
			shader_parts += 1
	controller._apply(entry, 0.5)
	var restored := true
	if counts["instances"] == counts["modes"] and counts["modes"] == counts["fades"] \
			and counts["fades"] == counts["originals"] and counts["originals"] == counts["shadows"]:
		controller._end_unit(holder, entry)
		restored = (holder.get_child(3) as MeshInstance3D).material_override == shader_mat \
			and (holder.get_child(0) as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.free()
	return {"instances": counts["instances"], "modes": counts["modes"], "fades": counts["fades"],
		"originals": counts["originals"], "shadows": counts["shadows"],
		"shader_parts": shader_parts, "restored": restored}
