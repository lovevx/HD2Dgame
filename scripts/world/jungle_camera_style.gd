extends RefCounted
## Project-tuned HD-2D framing, not claimed to be Octopath's engine settings.
const PITCH := 24.0
const YAW := 8.0
const DISTANCE := 29.0
const COMPOSITION_OFFSET := Vector3(0, 1.0, -1.5)

static func configure(camera: Camera3D, arena: bool) -> void:
	camera.rotation_degrees = Vector3(-PITCH, YAW, 0)
	camera.position = camera.basis * Vector3(0, 0, DISTANCE)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = 33.0 if arena else 30.0
	camera.near = 0.15
	camera.far = 160.0
	camera.current = true
	var lens := CameraAttributesPractical.new()
	# 景深以港口模板同步：近场 26m、远场 47m，模糊权重走默认值。
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = 47.0
	lens.dof_blur_far_transition = 16.0
	lens.dof_blur_near_enabled = true
	lens.dof_blur_near_distance = 26.0
	lens.dof_blur_near_transition = 8.0
	camera.attributes = lens

static func focus_bounds(arena: bool) -> Rect2:
	return Rect2(-20, -20, 40, 40) if arena else Rect2(-17, -19, 34, 38)
