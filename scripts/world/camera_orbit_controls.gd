extends RefCounted
## 轨道机位：按住鼠标中键拖动绕角色转镜头（左右改朝向、上下改俯角），滚轮推拉相机与角色的距离。
## 取代旧的「鼠标让出」——光标移到哪都不再带动镜头，机位只由玩家显式操作改变。
## 俯角与距离都有限位；距离变化时景深按同比例缩放，拉近后角色不会掉进近景模糊里。
##
## 机位分解（2026-09-19 修「转视角甩镜头 / 走动不跟手」）：
##   position = 平滑锚点 + 构图偏移 + 轨道偏移
##   · **平滑只加在锚点上**（锚点＝玩家那一侧的世界点，走路由它负责跟手）。
##   · 构图偏移与轨道偏移都挂在机位朝向上，随转动**即时**生效、不过平滑。
##     所以转视角时角色在画面里的位置完全不变：不会先被甩出中心、再慢慢追回来。
##   · 相机到锚点的距离恒为 distance（轨道是刚性的），景深基准不随加速漂移。
##
## 反面做法（旧版）：把平滑加在 camera.position 上，让相机去"追"一个已经转过角度的目标。
## 拖动越快，相机离轨道球越远——实测角色最多被甩出 800~1300 px，就是玩家看到的"转视角屏幕抖"。

## 设置项按路径读（见 data/prefs.gd：本文件在校验脚本里被文件顶层 preload，不能直接写自动加载名）。
const Prefs := preload("res://data/prefs.gd")

## 中键拖动的灵敏度（度 / 像素）。这是 1.0 倍率下的基准值，
## 玩家在设置页调的是倍率（GameSettings.camera_sensitivity，0.4~2.0），两者相乘才是实际灵敏度。
const ORBIT_SENSITIVITY := 0.22
## 每格滚轮的等比步长：距离乘 (1 + ZOOM_STEP) 为拉远，乘倒数即拉近，远近手感一致。
const ZOOM_STEP := 0.12
## 俯角限位：太平会贴着地面看穿布景；太陡则立绘被俯视压扁，看着像"趴在地上"。
## 上限 45° 是按观感定的——再往上，人物贴片的正面细节全部让位给头顶，舞台感也没了。
const MIN_PITCH := 6.0
const MAX_PITCH := 45.0
## 距离限位：太近角色占满画面，太远会露出布景边界。
const MIN_DISTANCE := 12.0
const MAX_DISTANCE := 96.0

var yaw_deg := 0.0
var pitch_deg := 16.0
var distance := 48.1
var enabled := true
## 中键是否按住：调用方可据此加快跟随，拖动时更跟手。
var dragging := false
## 平滑后的锚点（世界坐标）：跟手由它负责，机位再刚性挂在它上面。
var anchor := Vector3.ZERO
var _camera: Camera3D
var _base_distance := 1.0
var _lens: CameraAttributesPractical
## 景深基准：far / far_transition / near / near_transition，取自配置时的相机。
var _lens_base := Vector4.ZERO
var _rig_ready := false

## 以给定的机位参数起步，并记下景深基准（缩放时按距离等比缩放它）。
func configure(camera: Camera3D, pitch: float, yaw: float, dist: float) -> void:
	_camera = camera
	pitch_deg = clampf(pitch, MIN_PITCH, MAX_PITCH)
	yaw_deg = yaw
	distance = clampf(dist, MIN_DISTANCE, MAX_DISTANCE)
	_base_distance = maxf(distance, 0.001)
	_lens = camera.attributes as CameraAttributesPractical
	if _lens != null:
		_lens_base = Vector4(
			_lens.dof_blur_far_distance,
			_lens.dof_blur_far_transition,
			_lens.dof_blur_near_distance,
			_lens.dof_blur_near_transition)

## 机位朝向：与相机 rotation_degrees = (-pitch, yaw, 0) 一致。
func basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), deg_to_rad(yaw_deg), 0.0))

## 相机相对锚点的轨道偏移；俯角越大，相机越高（"上下拖动调高度"就是这个分量）。
func offset() -> Vector3:
	return basis() * Vector3(0, 0, distance)

## 画面深处的水平方向：构图偏移跟着它走，转到任何朝向取景关系都一致。
func forward_flat() -> Vector3:
	var dir := -basis().z
	dir.y = 0.0
	return dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD

## 出生时一次到位：不平滑，直接把机位放到给定锚点上（免得从编辑器机位飞过去）。
func snap(camera: Camera3D, target_anchor: Vector3, composition: Vector3) -> void:
	anchor = target_anchor
	_rig_ready = true
	_place(camera, composition)

## 每帧调用：锚点按 follow（每秒收敛率，帧率无关）平滑跟随，机位刚性挂在锚点上。
func place(camera: Camera3D, target_anchor: Vector3, composition: Vector3, delta: float, follow: float) -> void:
	if _rig_ready:
		anchor = anchor.lerp(target_anchor, 1.0 - exp(-follow * delta))
	else:
		anchor = target_anchor
		_rig_ready = true
	_place(camera, composition)

## 朝向即时生效、位置刚性（锚点 + 构图 + 轨道）：转动不经过任何平滑，画面不会跟着甩。
func _place(camera: Camera3D, composition: Vector3) -> void:
	camera.rotation_degrees = Vector3(-pitch_deg, yaw_deg, 0.0)
	camera.position = anchor + composition + offset()

## 输入入口：中键按下/拖动与滚轮归机位消费，返回 true 表示事件已被吃掉。
## 有模态面板（任务档案 / 角色面板 / 商店 / Esc 菜单 / F1 说明）时一律不接：
## 面板开着还让滚轮推拉、中键转视角，等于在玩家已经离手的时候把镜头拽走。
## 不吃事件的附带好处：滚轮会穿到面板自己的滚动区，能滚任务列表与详情。
func handle_input(event: InputEvent) -> bool:
	if not enabled:
		return false
	if _modal_open():
		# 不吃事件，但要把中键状态跟上：面板开着的这段时间里松开中键没人告诉我们，
		# 关掉面板后鼠标一动镜头就会跟着转（dragging 卡在 true）。
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE:
			dragging = (event as InputEventMouseButton).pressed
		return false
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_MIDDLE:
				dragging = button.pressed
				return true
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					zoom(-1)
					return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					zoom(1)
					return true
	elif event is InputEventMouseMotion and dragging:
		var motion := event as InputEventMouseMotion
		var sensitivity := ORBIT_SENSITIVITY * _sensitivity_scale()
		# 向右拖＝视线向右转（相机绕到左侧），向上拖＝抬高机位。
		# 上下反转只翻 pitch 的方向：想「推上去＝往下看」的玩家按设置页的开关即可。
		var pitch_step := motion.relative.y * sensitivity
		if _invert_y():
			pitch_step = -pitch_step
		yaw_deg = wrapf(yaw_deg - motion.relative.x * sensitivity, -180.0, 180.0)
		pitch_deg = clampf(pitch_deg - pitch_step, MIN_PITCH, MAX_PITCH)
		return true
	return false

## 设置页的镜头灵敏度倍率。
## 这里按节点路径取而不是直接写 `GameSettings.` —— 本文件被 tools/validate_camera_orbit.gd
## 在文件顶层 preload，那种上下文里自动加载名还没注册，直接引用会编译失败（见 data/prefs.gd）。
func _sensitivity_scale() -> float:
	return float(Prefs.value("camera_sensitivity", 1.0))

func _invert_y() -> bool:
	return bool(Prefs.value("camera_invert_y", false))

## 是否有模态面板打开。HUD 是唯一权威（各面板自己加进 "hud" 组并由 is_modal_open 汇总），
## 没有 HUD 的场景（纯机位回归脚本等）按"无面板"处理，不影响原行为。
func _modal_open() -> bool:
	if _camera == null or not _camera.is_inside_tree():
		return false
	var hud = _camera.get_tree().get_first_node_in_group("hud")
	return hud != null and hud.has_method("is_modal_open") and hud.is_modal_open()

## 滚轮推拉：steps 为负是拉近、正是拉远。
func zoom(steps: int) -> void:
	distance = clampf(distance * pow(1.0 + ZOOM_STEP, float(steps)), MIN_DISTANCE, MAX_DISTANCE)
	_sync_lens()

## 景深随距离等比缩放：不缩放的话拉近后角色会落到近景模糊区里（相机到角色就是 distance）。
func _sync_lens() -> void:
	if _lens == null:
		return
	var scale := distance / _base_distance
	_lens.dof_blur_far_distance = _lens_base.x * scale
	_lens.dof_blur_far_transition = _lens_base.y * scale
	_lens.dof_blur_near_distance = _lens_base.z * scale
	_lens.dof_blur_near_transition = _lens_base.w * scale
