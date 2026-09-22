extends SceneTree
## 预览：科尔波山远景层的两张预览图（不覆盖任何既有 docs 图）。
##   · docs/harbor_mountain_aerial_preview.png —— 高空俯瞰：整条北向峰林全貌
##   · docs/harbor_mountain_gate_preview.png —— 北门广场机位：门洞取景框里的垭口树
## 带渲染窗口跑（不要 --headless）：
##   godot --path . --script res://tools/capture_mountain_preview.gd

const SCENE_PATH := "res://scenes/world/harbor.tscn"

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var scene = load(SCENE_PATH).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.4).timeout
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	# 机位一：自由相机高空俯瞰全山。
	var cam := Camera3D.new()
	cam.name = "FreeCam"
	scene.add_child(cam)
	cam.position = Vector3(0, 38, 22)
	cam.look_at(Vector3(0, 6, -52))
	cam.make_current()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/harbor_mountain_aerial_preview.png")
	print("MOUNT_CAPTURE: aerial 已存 docs/harbor_mountain_aerial_preview.png")
	cam.queue_free()
	await create_timer(0.2).timeout
	# 机位二：北门广场（z=-24，传送环旁），看门洞取景框里的垭口树。
	player.position = Vector3(0, 0, -24.0)
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/harbor_mountain_gate_preview.png")
	print("MOUNT_CAPTURE: gate 已存 docs/harbor_mountain_gate_preview.png")
	quit(0)
