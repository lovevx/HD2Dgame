extends SceneTree
## 遮挡淡出系统的性能探针：定位"跑着跑着卡一下"的开销来源。
##
## 复刻 harbor 场景 + 常驻跑步速度（3.12 m/s）沿主街推进，逐物理帧给
## CameraOcclusionFade._physics_process 计时，并分别统计：
##   * 候选重建（_refresh，每 refresh_interval 秒一次）
##   * 视线扫描（_scan，每帧）
##   * 新建淡出单元（_begin_unit，运行时新建材质 / 着色器变体 → 真机编译尖峰）
##
## 用法：godot --headless --path . --script res://tools/probe_occlusion_cost.gd
## 注意：headless 没有渲染，材质真正的着色器/管线编译耗时量不到，
##       本脚本量的是 CPU 侧开销与「尖峰出现的频率」——频率才是跑步卡顿的关键。

const SCENE_PATH := "res://scenes/world/harbor.tscn"
const RUN_SPEED := 3.12          # 与 player.gd 常驻跑步后的实际速度一致（2.6 × 1.2）
const DT := 1.0 / 60.0
const STEPS := 900               # 15 秒

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load(SCENE_PATH).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.4).timeout
	scene.set_process(false)
	var player: Node3D = scene.get_node("Player")
	player.set_physics_process(false)
	var controller: Node = player.get_node_or_null("CameraOcclusionFade")
	if controller == null:
		print("COST: FAIL 找不到 CameraOcclusionFade")
		quit(1)
		return
	controller.set_physics_process(false)
	var camera: Camera3D = scene.get_node_or_null("Camera3D")
	if camera == null:
		print("COST: FAIL 场景里没有 Camera3D")
		quit(1)
		return

	# 相机相对玩家的固定偏移（harbor.gd 已把机位摆好），跑步时一起平移。
	player.position = Vector3(0, 0, -20.0)
	var cam_offset: Vector3 = camera.global_position - player.global_position
	var cam_rot := camera.global_transform.basis

	# ---- 重建细化计时：找出 _refresh 里哪一步最贵 ----
	var root_node: Node = controller._root
	var t_find := 0
	var t_visible := 0
	var t_aabb := 0
	var t_prop := 0
	var t_cluster := 0
	var count := 0
	for kind in ["MeshInstance3D", "MultiMeshInstance3D"]:
		var t0 := Time.get_ticks_usec()
		var nodes: Array = root_node.find_children("*", kind, true, false)
		t_find += Time.get_ticks_usec() - t0
		for node in nodes:
			var inst := node as GeometryInstance3D
			if inst == null:
				continue
			var t1 := Time.get_ticks_usec()
			var vis := inst.is_visible_in_tree()
			t_visible += Time.get_ticks_usec() - t1
			if not vis:
				continue
			var t2 := Time.get_ticks_usec()
			var box: AABB = controller._world_aabb(inst)
			t_aabb += Time.get_ticks_usec() - t2
			if box.size.y < controller.min_height:
				continue
			count += 1
			var t3 := Time.get_ticks_usec()
			var prop: Node = controller._prop_ancestor(inst)
			t_prop += Time.get_ticks_usec() - t3
			if prop != null:
				var t4 := Time.get_ticks_usec()
				controller._cluster_box(prop)
				t_cluster += Time.get_ticks_usec() - t4
	print("COST: 重建细分 | find_children %.1f ms | 可见性 %.1f ms | 世界AABB %.1f ms | 找祖先 %.1f ms | 簇包围盒 %.1f ms（候选 %d）" % [
		t_find / 1000.0, t_visible / 1000.0, t_aabb / 1000.0, t_prop / 1000.0, t_cluster / 1000.0, count])

	var refresh_flags := []
	var new_units := []
	var times := []
	var prev_keys := {}
	for i in STEPS:
		# 沿主街往 +z 跑：X 不变，Z 每帧推进
		player.position.z += RUN_SPEED * DT
		camera.global_transform = Transform3D(cam_rot, player.global_position + cam_offset)
		var before_timer: float = controller._refresh_timer
		var t0 := Time.get_ticks_usec()
		controller._physics_process(DT)
		var t1 := Time.get_ticks_usec()
		times.append(t1 - t0)
		refresh_flags.append(before_timer <= DT)      # 本帧发生了候选重建
		var keys: Array = controller.active_units().keys()
		var fresh := 0
		for k in keys:
			if not prev_keys.has(k):
				fresh += 1
		prev_keys = {}
		for k in keys:
			prev_keys[k] = true
		new_units.append(fresh)

	var total := 0
	var peak := 0
	var peak_i := -1
	for i in times.size():
		total += times[i]
		if times[i] > peak:
			peak = times[i]
			peak_i = i
	var avg := float(total) / times.size()
	var sorted_times := times.duplicate()
	sorted_times.sort()
	var p95: int = sorted_times[int(sorted_times.size() * 0.95)]
	var refresh_steps := 0
	var refresh_us := 0
	var spawn_steps := 0
	var spawn_us := 0
	var plain_us := 0
	var plain_steps := 0
	for i in times.size():
		if refresh_flags[i]:
			refresh_steps += 1
			refresh_us += times[i]
		elif new_units[i] > 0:
			spawn_steps += 1
			spawn_us += times[i]
		else:
			plain_steps += 1
			plain_us += times[i]
	print("COST: 候选 %d 个 | %d 帧内重建 %d 次、新建淡出单元 %d 次" % [
		controller._candidates.size(), STEPS, refresh_steps,
		_refresh_total(new_units)])
	print("COST: 单帧 _physics_process 平均 %.2f ms | p95 %.2f ms | 峰值 %.2f ms（第 %d 帧）" % [
		avg / 1000.0, p95 / 1000.0, peak / 1000.0, peak_i])
	if refresh_steps > 0:
		print("COST:   候选重建帧 %d 次，平均 %.2f ms" % [refresh_steps, float(refresh_us) / refresh_steps / 1000.0])
	if spawn_steps > 0:
		print("COST:   新建单元帧 %d 次，平均 %.2f ms" % [spawn_steps, float(spawn_us) / spawn_steps / 1000.0])
	if plain_steps > 0:
		print("COST:   普通帧     %d 次，平均 %.2f ms" % [plain_steps, float(plain_us) / plain_steps / 1000.0])
	var over_16 := 0
	for t in times:
		if t > 16000:
			over_16 += 1
	print("COST: 超过 16.6ms（掉帧线）的帧：%d / %d" % [over_16, times.size()])
	quit(0)

func _refresh_total(arr: Array) -> int:
	var s := 0
	for v in arr:
		s += v
	return s
