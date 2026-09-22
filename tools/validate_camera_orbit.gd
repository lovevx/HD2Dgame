extends SceneTree
## 轨道机位回归检查：中键拖动转视角（改朝向 / 抬高机位）、滚轮推拉距离、限位、景深同步，
## 以及"光标不再带动镜头"、"拖动转视角不甩镜头"、"走路不抖"、"W 永远朝画面上方走"。
## 只读状态、不渲染、不覆盖 docs 预览图。
## 用法：godot --headless --path . --script res://tools/validate_camera_orbit.gd
##
## 覆盖四张用同一套 HD-2D 机位的图：灰潮港、丛林外围、丛林空地、自由练习场。
const Orbit := preload("res://scripts/world/camera_orbit_controls.gd")

const SCENES := [
	{"label": "harbor", "path": "res://scenes/world/harbor.tscn", "player": "Player"},
	{"label": "outer", "path": "res://scenes/world/colpo_forest_outer.tscn", "player": "Player"},
	{"label": "clearing", "path": "res://scenes/world/colpo_forest_clearing.tscn", "player": "Player"},
	{"label": "practice", "path": "res://scenes/main/main.tscn", "player": "player"},
]
const DEFAULT_PITCH := 16.0
const WHEEL_UP := MOUSE_BUTTON_WHEEL_UP
const WHEEL_DOWN := MOUSE_BUTTON_WHEEL_DOWN
const MIDDLE := MOUSE_BUTTON_MIDDLE

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)

func _button(index: int, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	return event

func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	return event

## 驱动若干帧让跟随收敛（用脚本自己的 _update_camera，与运行时同一套逻辑）。
func settle(scene: Node, steps := 180, dt := 1.0 / 60.0) -> void:
	for i in steps:
		scene._update_camera(dt)

func onscreen(camera: Camera3D, at: Vector3, margin: float) -> bool:
	var uv := camera.unproject_position(at) / camera.get_viewport().get_visible_rect().size
	return not camera.is_position_behind(at) and uv.x > margin and uv.x < 1.0 - margin and uv.y > margin and uv.y < 1.0 - margin

## 把玩家放回场景出生点，机位也回到默认档，作为每段检查的共同起点。
func reset(scene: Node, orbit, player: CharacterBody3D, camera: Camera3D) -> void:
	player.velocity = Vector3.ZERO
	orbit.yaw_deg = 0.0
	orbit.pitch_deg = DEFAULT_PITCH
	orbit.distance = orbit._base_distance
	orbit.zoom(0)   # 距离回到默认档时把景深也拉回基准
	settle(scene)

## 拖动转视角：角色在画面里的位置必须钉住，相机也不许脱离轨道球。
## 旧版把平滑加在 camera.position 上、让相机去追一个已经转过角度的目标：拖得越快离轨道球越远，
## 实测角色最多被甩出 800~1300 px——就是玩家说的"转视角时屏幕抖"。
## 允许的残余漂移来自"焦点收边"：锚点被夹在机位边界上时，角色本来就不在轨道圆心上（外圈场景约 17 px）。
func check_drag_holds(scene: Node, camera: Camera3D, orbit, player: CharacterBody3D, label: String) -> void:
	reset(scene, orbit, player, camera)
	var anchor_before: Vector3 = orbit.anchor
	var watch := player.position + Vector3.UP
	var base := camera.unproject_position(watch)
	var drift := 0.0
	var dist_min := 1.0e9
	var dist_max := 0.0
	scene._input(_button(MIDDLE, true))
	for i in 90:
		scene._input(_motion(Vector2(20, 0)))
		scene._update_camera(1.0 / 60.0)
		drift = maxf(drift, camera.unproject_position(watch).distance_to(base))
		var dist := camera.position.distance_to(orbit.anchor)
		dist_min = minf(dist_min, dist)
		dist_max = maxf(dist_max, dist)
	scene._input(_button(MIDDLE, false))
	check(drift <= 40.0, "%s: 拖动转视角时角色被甩出画面中心 %s px（相机应当刚性挂在朝向上）" % [label, drift])
	check(dist_max - dist_min <= 0.01, "%s: 拖动时相机脱离了轨道球（%s~%s m）" % [label, dist_min, dist_max])
	check(orbit.anchor.distance_to(anchor_before) < 0.001, "%s: 玩家没动，锚点却漂了 %s m" % [label, orbit.anchor.distance_to(anchor_before)])
	orbit.yaw_deg = 0.0
	settle(scene)

## 走路：W 永远朝画面深处走（视角转到哪都不变），而且角色在屏幕上不许抖。
## 无头口径：手动调 _physics_process 时 move_and_slide 用的是"空闲帧"delta、不是物理步长，
## 位移会被放大十倍以上（实测 0.16 m/次）——所以位置按真实物理步长自己推进，
## 只有"物理步进 vs 渲染帧率"的时序才是真的。渲染帧率按 3 倍物理帧率喂。
func check_walk(scene: Node, camera: Camera3D, orbit, player: CharacterBody3D, label: String) -> void:
	# 真链路：按 W 必须真的走起来（位移方向对就行，距离受上面那条无头口径影响，只做下限）
	var spawn := player.position
	var speed: float = player.move_speed
	Input.action_press("move_up")
	for i in 45:
		player._physics_process(1.0 / 60.0)
	Input.action_release("move_up")
	var real_step := player.position - spawn
	real_step.y = 0.0
	check(real_step.length() > 0.1 and real_step.normalized().dot(Vector3(0, 0, -1)) > 0.9,
		"%s: 默认朝向下按 W 没有往画面上方走（%s）" % [label, real_step])

	var cases := [
		{"yaw": 0.0, "expect": Vector3(0, 0, -1)},
		{"yaw": 90.0, "expect": Vector3(-1, 0, 0)},
		{"yaw": 180.0, "expect": Vector3(0, 0, 1)},
		{"yaw": -90.0, "expect": Vector3(1, 0, 0)},
	]
	for item in cases:
		player.position = spawn
		player.velocity = Vector3.ZERO
		orbit.yaw_deg = item["yaw"]
		settle(scene)
		var start := player.position
		var samples: Array[float] = []
		var travelled := Vector3.ZERO
		Input.action_press("move_up")
		for i in 90:
			player._physics_process(1.0 / 60.0)
			var intent: Vector3 = player.facing
			var ramp := minf(1.0, float(i + 1) / 15.0)
			travelled += intent * speed * ramp * (1.0 / 60.0)
			player.velocity = intent * speed * ramp
			player.position = start + travelled
			for k in 3:
				scene._update_camera(1.0 / 180.0)
				samples.append(camera.unproject_position(player.position + Vector3.UP).y)
		Input.action_release("move_up")
		var expect: Vector3 = item["expect"]
		check(player.facing.dot(expect) > 0.99, "%s: 偏航 %s° 时按 W 的角色朝向不对（%s，期望 %s）" % [label, item["yaw"], player.facing, expect])
		check(player.position.distance_to(start) > 1.5, "%s: 偏航 %s° 时按 W 没有走出去（%s）" % [label, item["yaw"], player.position.distance_to(start)])
		# 动作跟按键走：八方向图集按"以机位为北"取图，任何偏航下按 W 都必须播背面 walk_up。
		# 旧口径按世界朝向取图，机位转 180° 后按 W 会播正面 walk_down，看起来像倒着走。
		var sprite := player.get_node("pivot/CharacterSprite")
		sprite._update_locomotion()
		check(sprite.display_direction == "up",
			"%s: 偏航 %s° 时按 W 应播背面（up），实际 %s（动作要跟按键走，不能跟世界朝向走）" % [label, item["yaw"], sprite.display_direction])
		check(onscreen(camera, player.position + Vector3.UP, 0.05),
			"%s: 偏航 %s° 时走动把角色挤出了取景（焦点收边夹在边界上时角色本来就会偏）" % [label, item["yaw"]])
		# 抖动：稳态段的逐帧位移相对 9 帧滑动均值的偏差。
		# 下限 1 px 是按实测定的：角色位置按物理步长跳，画面上会留约 0.6 px 的锯齿（四张图一致），
		# 这是"物理步进 + 未插值渲染"的固有量；跟随数学出问题会远大于它（旧版转动时是 800+ px）。
		var deltas: Array[float] = []
		for i in range(120, samples.size()):
			deltas.append(samples[i] - samples[i - 1])
		var ripple := 0.0
		for i in range(4, deltas.size() - 4):
			var kernel := 0.0
			for k in range(i - 4, i + 5):
				kernel += deltas[k]
			ripple = maxf(ripple, absf(deltas[i] - kernel / 9.0))
		check(ripple <= 1.0, "%s: 走路时角色屏幕坐标抖动 ±%s px（偏航 %s°）" % [label, ripple, item["yaw"]])
	# 横向键同理：机位转 180° 后按 D，画面上要向右跑、播 right 图（旧口径会播 left）。
	player.position = spawn
	player.velocity = Vector3.ZERO
	orbit.yaw_deg = 180.0
	settle(scene)
	Input.action_press("move_right")
	player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	var sprite_side := player.get_node("pivot/CharacterSprite")
	sprite_side._update_locomotion()
	check(sprite_side.display_direction == "right",
		"%s: 偏航 180° 时按 D 应播 right 图，实际 %s" % [label, sprite_side.display_direction])
	player.position = spawn
	player.velocity = Vector3.ZERO
	orbit.yaw_deg = 0.0
	settle(scene)

func check_scene(entry: Dictionary) -> void:
	var label: String = entry["label"]
	var scene: Node = load(entry["path"]).instantiate()
	for name in ["WaveDirector", "BossDirector"]:
		var director: Node = scene.get_node_or_null(name)
		if director != null:
			director.free()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player: CharacterBody3D = scene.get_node(entry["player"])
	var camera: Camera3D = scene.get_node("Camera3D")
	player.set_physics_process(false)
	var orbit = scene.get("_orbit")

	check(orbit != null, "%s: 机位没有接上轨道控制" % label)
	check(scene.get("_mouse_lead") == null, "%s: 旧的「鼠标让出」没有从场景脚本里移除" % label)
	if orbit == null:
		scene.free()
		return

	# --- 出生机位：还是原来那套默认参数 ---
	check(orbit.enabled, "%s: 轨道控制默认应当是启用的" % label)
	check(is_equal_approx(orbit.pitch_deg, DEFAULT_PITCH), "%s: 出生俯角应为 %s°，实为 %s" % [label, DEFAULT_PITCH, orbit.pitch_deg])
	check(orbit.distance >= 40.0 and orbit.distance <= 50.0, "%s: 出生距离 %s 不在默认档位（42~48 米）" % [label, orbit.distance])
	check(orbit.yaw_deg == 0.0, "%s: 出生偏航应为 0（正北取景）" % label)
	check(onscreen(camera, player.position + Vector3.UP, 0.08), "%s: 出生取景里看不到角色" % label)

	# --- 模态面板开着时不接机位输入（滚轮 / 中键都不许动镜头）---
	# 练习场开局自带说明面板，正好借它验这条；后面所有机位检查都在收起面板后进行。
	var hud = get_first_node_in_group("hud")
	if hud != null and hud.has_method("is_modal_open"):
		if not hud.is_modal_open():
			hud.char_panel.show()
		var modal_distance: float = orbit.distance
		var modal_yaw: float = orbit.yaw_deg
		scene._input(_button(WHEEL_UP, true))
		scene._input(_button(MIDDLE, true))
		scene._input(_motion(Vector2(50, 0)))
		check(is_equal_approx(orbit.distance, modal_distance), "%s: 面板开着时滚轮仍推拉了镜头" % label)
		check(is_equal_approx(orbit.yaw_deg, modal_yaw), "%s: 面板开着时中键仍转了视角" % label)
		scene._input(_button(MIDDLE, false))
		# 收起全部面板：练习场那张开局说明面板也是模态，不收起后面每一项机位检查都会被拦。
		hud.hide_panel()
		hud.call("close_quest_log")
		hud.char_panel.hide()
		hud.menu.hide()
		hud.key_guide.hide()
		check(not hud.is_modal_open(), "%s: 面板没全部收起，后续机位检查会被模态拦住" % label)
	else:
		check(false, "%s: 场景里没有 HUD，无法验证模态拦截" % label)

	# --- 光标位置不再影响镜头：四角都试一遍，相机必须一动不动 ---
	root.size = Vector2i(1280, 720)
	await process_frame
	reset(scene, orbit, player, camera)
	var baseline := camera.position
	for corner in [Vector2(4, 4), Vector2(1276, 4), Vector2(4, 716), Vector2(1276, 716), Vector2(640, 360)]:
		root.warp_mouse(corner)
		settle(scene, 60)
		check(camera.position.distance_to(baseline) < 0.001, "%s: 光标在 %s 时镜头仍被带动（鼠标让出应已取消）" % [label, corner])

	# --- 中键拖动：向右拖＝相机绕到焦点西侧、视线朝东（画面左为北）---
	reset(scene, orbit, player, camera)
	scene._input(_button(MIDDLE, true))
	check(orbit.dragging, "%s: 中键按下没有进入拖动状态" % label)
	scene._input(_motion(Vector2(180, 0)))
	var expected_yaw: float = -180.0 * Orbit.ORBIT_SENSITIVITY
	check(is_equal_approx(orbit.yaw_deg, expected_yaw), "%s: 向右拖动 %s 像素后偏航应为 %s°，实为 %s°" % [label, 180, expected_yaw, orbit.yaw_deg])
	scene._input(_motion(Vector2(220, 0)))
	settle(scene)
	var west: Vector3 = orbit.offset()
	check(west.x < -8.0, "%s: 向右拖动后相机应绕到焦点西侧，实测 x=%s" % [label, west.x])
	check(onscreen(camera, player.position + Vector3.UP, 0.08), "%s: 转到侧向后角色跑出画面" % label)

	# --- 中键上下拖：抬高机位（相机变高、水平距离变短）---
	reset(scene, orbit, player, camera)
	var low_height := camera.position.y
	var low_planar := Vector2(camera.position.x - player.position.x, camera.position.z - player.position.z).length()
	scene._input(_button(MIDDLE, true))
	scene._input(_motion(Vector2(0, -20)))
	check(orbit.pitch_deg > DEFAULT_PITCH, "%s: 向上拖动应抬高俯角，实为 %s°" % [label, orbit.pitch_deg])
	scene._input(_motion(Vector2(0, 40)))
	check(orbit.pitch_deg < DEFAULT_PITCH, "%s: 向下拖动应压低俯角，实为 %s°" % [label, orbit.pitch_deg])
	check(is_equal_approx(orbit.pitch_deg, DEFAULT_PITCH - 20.0 * Orbit.ORBIT_SENSITIVITY), "%s: 上下拖动的灵敏度不对（%s°）" % [label, orbit.pitch_deg])
	scene._input(_button(MIDDLE, false))
	check(not orbit.dragging, "%s: 松开中键后仍在拖动状态" % label)
	var after_release: float = orbit.yaw_deg
	scene._input(_motion(Vector2(400, 0)))
	check(is_equal_approx(orbit.yaw_deg, after_release), "%s: 松开中键后移动鼠标仍改机位" % label)
	orbit.pitch_deg = Orbit.MAX_PITCH - 1.0
	settle(scene)
	var high_height := camera.position.y
	var high_planar := Vector2(camera.position.x - player.position.x, camera.position.z - player.position.z).length()
	check(high_height > low_height + 5.0, "%s: 抬高俯角没有把相机抬起来（%s → %s）" % [label, low_height, high_height])
	check(high_planar < low_planar - 3.0, "%s: 抬高俯角后水平距离应变短（%s → %s）" % [label, low_planar, high_planar])

	# --- 俯角限位：再怎么拖也不会穿过地面或翻到天上 ---
	scene._input(_button(MIDDLE, true))
	for i in 20:
		scene._input(_motion(Vector2(0, -200)))
	check(is_equal_approx(orbit.pitch_deg, Orbit.MAX_PITCH), "%s: 俯角上限没有夹住（%s）" % [label, orbit.pitch_deg])
	for i in 40:
		scene._input(_motion(Vector2(0, 200)))
	check(is_equal_approx(orbit.pitch_deg, Orbit.MIN_PITCH), "%s: 俯角下限没有夹住（%s）" % [label, orbit.pitch_deg])
	# 上限数值本身也锁住：超过 45° 立绘会被俯视压扁，玩家反馈"像趴在地上"。
	check(Orbit.MAX_PITCH <= 45.0, "%s: 俯角上限 %s° 超过 45°（立绘会被俯视看成趴在地上）" % [label, Orbit.MAX_PITCH])
	scene._input(_button(MIDDLE, false))

	# --- 滚轮：上滚拉近、下滚拉远，并在两端夹住 ---
	reset(scene, orbit, player, camera)
	var near_distance: float = orbit.distance
	scene._input(_button(WHEEL_UP, true))
	check(orbit.distance < near_distance, "%s: 滚轮上滚应拉近（%s → %s）" % [label, near_distance, orbit.distance])
	scene._input(_button(WHEEL_DOWN, true))
	check(orbit.distance > near_distance - 0.0001, "%s: 滚轮下滚应拉远" % label)
	# 拉近后相机跟着靠近：角色在画面里变大但仍完整
	for i in 20:
		scene._input(_button(WHEEL_UP, true))
	settle(scene)
	check(is_equal_approx(orbit.distance, Orbit.MIN_DISTANCE), "%s: 拉近下限没有夹住（%s）" % [label, orbit.distance])
	check(onscreen(camera, player.position + Vector3.UP, 0.02), "%s: 拉到最近时角色跑出画面" % label)
	for i in 40:
		scene._input(_button(WHEEL_DOWN, true))
	settle(scene)
	check(is_equal_approx(orbit.distance, Orbit.MAX_DISTANCE), "%s: 拉远上限没有夹住（%s）" % [label, orbit.distance])
	check(onscreen(camera, player.position + Vector3.UP, 0.02), "%s: 拉到最远时角色跑出画面" % label)
	check(Vector2(camera.position.x - player.position.x, camera.position.z - player.position.z).length() > 40.0, "%s: 拉远后相机没有真的退开" % label)

	# --- 景深跟着距离等比缩放：不然拉近后角色会掉进近景模糊区 ---
	var lens := camera.attributes as CameraAttributesPractical
	if lens != null:
		scene._input(_button(WHEEL_UP, true))
		var ratio_near: float = lens.dof_blur_near_distance / float(orbit.distance)
		var ratio_far: float = lens.dof_blur_far_distance / float(orbit.distance)
		for i in 5:
			scene._input(_button(WHEEL_UP, true))
		check(is_equal_approx(lens.dof_blur_near_distance / orbit.distance, ratio_near), "%s: 近景景深没有跟着距离等比缩放" % label)
		check(is_equal_approx(lens.dof_blur_far_distance / orbit.distance, ratio_far), "%s: 远景景深没有跟着距离等比缩放" % label)
	else:
		check(false, "%s: 相机没有 CameraAttributesPractical，景深无法同步" % label)

	# --- 四个朝向都要看得到角色（转视角不能把主角挤出取景）---
	reset(scene, orbit, player, camera)
	for yaw in [0.0, 90.0, -90.0, 180.0]:
		orbit.yaw_deg = yaw
		settle(scene)
		check(onscreen(camera, player.position + Vector3.UP, 0.08), "%s: 偏航 %s° 时角色跑出画面" % [label, yaw])
		var uv := camera.unproject_position(player.position) / camera.get_viewport().get_visible_rect().size
		check(uv.x > 0.2 and uv.x < 0.8 and uv.y > 0.2 and uv.y < 0.8, "%s: 偏航 %s° 时取景中心偏了（uv=%s）" % [label, yaw, uv])

	# --- 转动不甩镜头、走路不抖、W 跟着视角走 ---
	check_drag_holds(scene, camera, orbit, player, label)
	check_walk(scene, camera, orbit, player, label)

	print("ORBIT: %s 项检查完成（%s）" % [checks, label])
	scene.free()
	await process_frame

func run() -> void:
	check(not FileAccess.file_exists("res://scripts/world/camera_mouse_lead.gd"), "mouse_lead 组件已删除")
	for entry in SCENES:
		await check_scene(entry)
	for failure in failures:
		push_error(failure)
	print("CAMERA_ORBIT: %s (%d checks)" % ["PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)
