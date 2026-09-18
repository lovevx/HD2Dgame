extends SceneTree
## 素材验看：把已导入的预设排成网格渲染一张图，用于确认比例、朝向与落地高度。
## 用法：godot --path <工程> --script tools/check_presets.gd -- [--assets=标题1,标题2] [--out=res://docs/preset_check.png]

const Catalog := preload("res://tools/preset_catalog.gd")
const DEFAULT_TITLES := "SM_JN_fangzi001,SM_JN_fangzi002,SM_JN_fangzi005,sm_gsc_kezhan001,SM_JN_wuguan001,SM_JN_kezhan001,SM_JN_matou,SM_JN_xiaochuan001,SM_JN_yuchuan004,SM_JN_Xiaoqiao001,SM_gsc_qiao001,SM_Shore,SM_JN_Weiqiang001,SM_JN_Damen001,SM_JN_Gongmen001,SM_JN_louti001,SM_ltem_Shuiche001,SM_gsc_tanzi001,SM_Item_NJhuojia001,SM_Item_NJtanwei001,SM_NJ_ZhuZhuozi001,SM_Item_pingfeng001,SM_Box001Open,SM_jzc_dengzi001,SM_gsc_gusuchengpaizi001,SM_JN_shineidiban001,SM_JN_shikuai002,SM_1songbaiA01_LODs,SM_1dashu001_LODs,SM_Dataoshu001,SM_NJ_Jvqingshu001,SM_changzacao001,SM_NJ_Yvlinzhiwu001,SM_Jiangnan_xuanya001,SM_Jiangnan_xuanya002,SM_Dataoshushuzhi001"

var titles := PackedStringArray()
var output := "res://docs/preset_check.png"
var spacing := 9.0
var columns := 6
var side_view := false
var plan := ""
var plan_band := Vector2(2.7, 3.2)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var measure := ""
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text.begins_with("--assets="):
			titles = text.trim_prefix("--assets=").split(",", false)
		elif text.begins_with("--measure="):
			measure = text.trim_prefix("--measure=")
		elif text.begins_with("--out="):
			output = text.trim_prefix("--out=")
		elif text.begins_with("--spacing="):
			spacing = float(text.trim_prefix("--spacing="))
		elif text.begins_with("--columns="):
			columns = int(text.trim_prefix("--columns="))
		elif text == "--side":
			side_view = true
		elif text.begins_with("--plan="):
			plan = text.trim_prefix("--plan=")
		elif text.begins_with("--plan-band="):
			var band := text.trim_prefix("--plan-band=").split(",", false)
			if band.size() == 2:
				plan_band = Vector2(float(band[0]), float(band[1]))
	if not measure.is_empty():
		for title in measure.split(",", false):
			measure_heights(title)
		quit(); return
	if not plan.is_empty():
		for title in plan.split(",", false):
			measure_plan(title, plan_band)
		quit(); return
	if titles.is_empty():
		titles = PackedStringArray(DEFAULT_TITLES.split(",", false))
	var root_node := Node3D.new()
	root_node.name = "PresetCheck"
	root.add_child(root_node)
	root_node.add_child(make_ground(float(count_slots()) * spacing))
	var count := 0
	for title in titles:
		var item: HD2DAsset = Catalog.asset(title)
		if item == null:
			continue
		var prop := HD2DProp.new()
		prop.name = title
		prop.asset = item
		prop.position = Vector3((count % columns) * spacing, 0, floori(float(count) / columns) * spacing)
		root_node.add_child(prop)
		var parts := item.mesh_parts()
		var box := parts_bounds(parts)
		print("CHECK_ASSET: %s  部件=%d  尺寸=%.2f x %.2f x %.2f  底部y=%.2f %s" % [title, parts.size(), box.size.x, box.size.y, box.size.z, box.position.y, "落地正常" if absf(box.position.y) < 0.6 else "注意：原点不在底部"])
		count += 1
	root_node.add_child(make_camera(count))
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output)
	print("CHECK_PRESETS: %d 项 -> %s" % [count, output])
	quit()

func count_slots() -> int:
	return titles.size()

## 统计模型顶点在高度上的聚集面，用来找码头甲板、桥面这类可行走平面。
## 同时单独统计“去掉外圈 1.2 米栏杆/立柱后的内区最高面”，那就是可站立高度。
func measure_heights(title: String) -> void:
	var item: HD2DAsset = Catalog.asset(title)
	if item == null:
		return
	var vertices_world: Array[Vector3] = []
	for part in item.mesh_parts():
		var mesh: Mesh = part.mesh
		var xform: Transform3D = part.transform
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				vertices_world.append(xform * vertex)
	var box := AABB(vertices_world[0], Vector3.ZERO)
	for vertex in vertices_world:
		box = box.expand(vertex)
	var buckets := {}
	var inner := {}
	for vertex in vertices_world:
		var key := snappedf(vertex.y, 0.05)
		buckets[key] = int(buckets.get(key, 0)) + 1
		# 去掉外圈 1.2 米：栏杆、立柱、屋檐不会被当成可站立面。
		if vertex.x > box.position.x + 1.2 and vertex.x < box.end.x - 1.2 and vertex.z > box.position.z + 1.2 and vertex.z < box.end.z - 1.2:
			inner[key] = int(inner.get(key, 0)) + 1
	var total := 0
	for key in buckets:
		total += buckets[key]
	var lines: Array[String] = []
	for key in buckets:
		if buckets[key] * 100.0 / maxf(1.0, total) >= 2.0:
			lines.append("%.2fm:%d" % [key, buckets[key]])
	var inner_best := 0.0
	var inner_best_count := 0
	for key in inner:
		if inner[key] > inner_best_count:
			inner_best_count = inner[key]
			inner_best = key
	print("MEASURE: %s  顶点=%d  尺寸=%.2fx%.2fx%.2f  主要高度面 -> %s" % [title, total, box.size.x, box.size.y, box.size.z, ", ".join(lines)])
	print("MEASURE_INNER: %s  内区主要平台=%.2fm(顶点%d)" % [title, inner_best, inner_best_count])

## 平面轮廓：只看指定高度带内的顶点，按 1 米 z 切片给出该片的 x 覆盖范围。
func measure_plan(title: String, band: Vector2) -> void:
	var item: HD2DAsset = Catalog.asset(title)
	if item == null:
		return
	var slices := {}
	for part in item.mesh_parts():
		var mesh: Mesh = part.mesh
		var xform: Transform3D = part.transform
		for surface in range(mesh.get_surface_count()):
			for vertex in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				var world: Vector3 = xform * vertex
				if world.y < band.x or world.y > band.y:
					continue
				var key := snappedf(world.z, 0.5)
				if not slices.has(key):
					slices[key] = {"min_x": world.x, "max_x": world.x, "count": 0}
				slices[key]["min_x"] = minf(slices[key]["min_x"], world.x)
				slices[key]["max_x"] = maxf(slices[key]["max_x"], world.x)
				slices[key]["count"] += 1
	var keys := slices.keys()
	keys.sort()
	print("MEASURE_PLAN: %s  高度带 %.2f~%.2f" % [title, band.x, band.y])
	for key in keys:
		var slice: Dictionary = slices[key]
		print("    切片 z=%6.1f  x %.2f ~ %.2f  顶点%d" % [key, slice["min_x"], slice["max_x"], slice["count"]])

func parts_bounds(parts: Array) -> AABB:
	var result := AABB()
	for i in range(parts.size()):
		var box := transformed_aabb(parts[i].mesh.get_aabb(), parts[i].transform)
		result = box if i == 0 else result.merge(box)
	return result

func transformed_aabb(box: AABB, xform: Transform3D) -> AABB:
	var basis := xform.basis
	var extent := Vector3(
		absf(basis.x.x) * box.size.x + absf(basis.y.x) * box.size.y + absf(basis.z.x) * box.size.z,
		absf(basis.x.y) * box.size.x + absf(basis.y.y) * box.size.y + absf(basis.z.y) * box.size.z,
		absf(basis.x.z) * box.size.x + absf(basis.y.z) * box.size.y + absf(basis.z.z) * box.size.z)
	return AABB(xform * box.get_center() - extent * 0.5, extent)

func make_ground(size: float) -> MeshInstance3D:
	var slab := BoxMesh.new()
	slab.size = Vector3(size + 40, 0.4, size + 40)
	var ground := MeshInstance3D.new()
	ground.mesh = slab
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("4a5348")
	mat.roughness = 0.95
	ground.material_override = mat
	ground.position.y = -0.2
	return ground

func make_camera(count: int) -> Camera3D:
	var rows := maxi(1, ceili(float(count) / columns))
	var depth := maxf(0.0, (rows - 1) * spacing)
	var width := maxf(0.0, (columns - 1) * spacing)
	var pitch := 52.0
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if side_view:
		# 侧视：只用来判断模型高度分布（甲板、桥面在哪个高度）。
		camera.size = 26.0
		camera.position = Vector3(width * 0.5, 6.0, depth * 0.5 + 60.0)
		camera.rotation_degrees = Vector3(0, 0, 0)
		camera.current = true
		camera.add_child(make_sun())
		camera.add_child(make_world())
		return camera
	# 俯角下地面纵深按 sin(pitch) 折算到屏幕纵向，另加 10 米余量给模型高度。
	camera.size = maxf(30.0, maxf(width / 1.7, depth * sin(deg_to_rad(pitch))) + 12.0)
	camera.rotation_degrees = Vector3(-pitch, 0, 0)
	var center := Vector3(width * 0.5, 0, depth * 0.5)
	var back := Vector3(0, sin(deg_to_rad(pitch)), cos(deg_to_rad(pitch)))
	camera.position = center + back * 120.0
	camera.current = true
	camera.add_child(make_sun())
	camera.add_child(make_world())
	return camera

func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	return sun

func make_world() -> WorldEnvironment:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("6f8794")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("9fb7c4")
	world.environment.ambient_light_energy = 1.5
	return world
