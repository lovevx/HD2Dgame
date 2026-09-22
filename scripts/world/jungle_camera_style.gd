extends RefCounted
## Project-tuned HD-2D framing, not claimed to be Octopath's engine settings.
## 16° 温和俯角 + 18° 长焦：机位沿视线等比后退，地面被压成一块平铺的舞台板，
## 角色在画面里的占比与旧机位（25 米 / FOV 30°·33°）一致，只是观看角度更平。
const PITCH := 16.0
const YAW := 0.0
const FOV := 18.0
const DISTANCE := 42.3
const ARENA_DISTANCE := 46.8
const COMPOSITION_OFFSET := Vector3(0, 1.0, -1.5)
## 景深按旧机位（25 米）的数值等比放大，保持"主体清晰、前后景化开"的景深关系。
const DOF_REFERENCE_DISTANCE := 25.0

## 构图偏移按机位朝向给：竖直 1 m + 画面深处 1.5 m（COMPOSITION_OFFSET 的世界口径＝正北取景）。
## 不按世界方向给的缘故：转到 180° 后角色会从"下三分之一"翻到"上三分之一"，
## 而且转视角过程中取景会横向滑动。按画面深处给，任何朝向的取景关系都一样。
static func composition(forward_flat: Vector3) -> Vector3:
	return Vector3.UP * COMPOSITION_OFFSET.y + forward_flat * (-COMPOSITION_OFFSET.z)

static func distance(arena: bool) -> float:
	return ARENA_DISTANCE if arena else DISTANCE

static func configure(camera: Camera3D, arena: bool) -> void:
	var offset := distance(arena)
	camera.rotation_degrees = Vector3(-PITCH, YAW, 0)
	camera.position = camera.basis * Vector3(0, 0, offset)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = FOV
	camera.near = 0.15
	camera.far = 160.0
	camera.current = true
	var scale := offset / DOF_REFERENCE_DISTANCE
	var lens := CameraAttributesPractical.new()
	# 景深以港口模板同步：近场 22m、远场 43m，模糊权重走默认值。
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = 43.0 * scale
	lens.dof_blur_far_transition = 16.0 * scale
	lens.dof_blur_near_enabled = true
	lens.dof_blur_near_distance = 22.0 * scale
	lens.dof_blur_near_transition = 8.0 * scale
	camera.attributes = lens

static func focus_bounds(arena: bool) -> Rect2:
	return Rect2(-20, -20, 40, 40) if arena else Rect2(-17, -19, 34, 38)
