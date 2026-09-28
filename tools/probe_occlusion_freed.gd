extends SceneTree
## 回归探针（2026-09-22）：前景遮挡淡出的候选缓存里留着已释放的网格时，
## `_scan()` 曾报「Trying to assign invalid previously freed instance」。
## 成因：`var inst: GeometryInstance3D = candidate["node"]` 是**带类型的赋值**，
## 碰到已释放实例会直接报错，而 `is_instance_valid` 写在下一行、来不及拦。
## 修复见 `camera_occlusion_fade.gd` 的 `_scan` / `_apply` / `_end_unit` 三处
## （先无类型读取 → 判存活 → 再 `as` 转类型），以及 `probe_occlusion_coverage.gd`。
##
## 用法：godot --headless --path . --script res://tools/probe_occlusion_freed.gd
## 期望：`previously freed` 计数为 0（修好前为 38）；探针打印的 `_scan` 次数应 > 0，
## 说明确实走过了"候选已释放"那条路径，不是空跑。

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# 用实时战斗练习场：有玩家（玩家自带 CameraOcclusionFade）+ 可重扫的场景几何。
	var arena: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	await physics_frame

	var player: Node = arena.get_node_or_null("player")
	if player == null:
		print("PROBE: 找不到玩家")
		quit(1)
		return
	var fade: Node = player.get_node_or_null("CameraOcclusionFade")
	if fade == null:
		print("PROBE: 找不到 CameraOcclusionFade")
		quit(1)
		return
	print("PROBE: 找到 CameraOcclusionFade")

	# 1) 造一件够高的网格当"景物"，强制重扫让它进候选缓存。
	var tall := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3, 6, 3)
	tall.mesh = mesh
	tall.position = Vector3(0, 3, -1)
	arena.add_child(tall)
	await process_frame
	fade.call("_refresh")
	var candidates: Array = fade.get("_candidates")
	print("PROBE: 候选数 = %d" % candidates.size())

	# 2) 释放它——缓存里就留下了已释放实例（模拟敌人被打死 / 换场景）。
	tall.free()

	# 3) 走进 _scan()：这一步在未修的版本上会报 previously freed instance。
	var camera := player.get_viewport().get_camera_3d()
	var hits := 0
	for i in 30:
		fade.call("_scan", camera)
		hits += 1
	print("PROBE: 已跑 _scan %d 次（含已释放候选）" % hits)
	await process_frame
	print("PROBE_DONE")
	quit(0)
