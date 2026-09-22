extends SceneTree
## 对照实验：同一机位截「实心参照」与「淡出生效」两张图，验证淡出真的落到了画面上。
##   docs/occlusion_fade_demo_off.png —— controller.enabled=false，全部实心
##   docs/occlusion_fade_demo_on.png  —— 淡出爬满（t=1.0，透明度 0.62）
## 带渲染窗口跑（不要 --headless）：
##   godot --path . --script res://tools/capture_occlusion_demo.gd

const SCENE_PATH := "res://scenes/world/harbor.tscn"
## 工坊街铺面（剑心亭/苏坊）后侧——用户实机截图的同一场景。
const PROBE_AT := Vector3(18, 0, -18.0)

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene = load(SCENE_PATH).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.4).timeout
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.position = PROBE_AT
	var controller = player.get_node_or_null("CameraOcclusionFade")
	if controller == null:
		print("OCCL_DEMO: FAIL 找不到控制器")
		quit(1)
		return
	# 第一张：关掉淡出 → 所有景物实心（参照）。
	controller.enabled = false
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/occlusion_fade_demo_off.png")
	print("OCCL_DEMO: off 已存")
	# 第二张：打开淡出 → 爬到稳态。
	controller.enabled = true
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/occlusion_fade_demo_on.png")
	print("OCCL_DEMO: on 已存")
	var units: Dictionary = controller.active_units()
	for key in units:
		print("OCCL_DEMO: 单元「%s」t=%.2f 含 %d 网格" % [key, float(units[key]["t"]), (units[key]["parts"] as Array).size()])
	# 材质状态实证：数一数场景里真挂着淡出材质/透明度的网格。
	var faded: Array[String] = []
	for kind in ["MeshInstance3D", "MultiMeshInstance3D"]:
		for node in scene.find_children("*", kind, true, false):
			var inst := node as GeometryInstance3D
			if inst == null:
				continue
			if inst.material_override is ShaderMaterial:
				var sm := inst.material_override as ShaderMaterial
				if sm.shader != null and sm.shader.resource_path.contains("occlusion_fade"):
					var a = inst.get_instance_shader_parameter("occl_fade")
					faded.append("%s(occl=%.2f)" % [inst.name, float(a) if a != null else -1.0])
			elif inst.material_override is StandardMaterial3D \
					and (inst.material_override as StandardMaterial3D).resource_name == "occl_fade_clone":
				var a2 := (inst.material_override as StandardMaterial3D).albedo_color.a
				if a2 < 0.999:
					faded.append("%s(clone=%.2f)" % [inst.name, a2])
			elif inst.transparency > 0.001:
				faded.append("%s(transp=%.2f)" % [inst.name, inst.transparency])
	print("OCCL_DEMO: 实际淡出网格 %d 个：%s" % [faded.size(), ", ".join(faded)])
	quit(0)
