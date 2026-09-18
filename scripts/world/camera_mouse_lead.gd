extends RefCounted
## 相机随鼠标偏移取景：光标离屏幕中心越远，焦点在对应方向多让出一点地面，方便看清光标那一侧。
## 只在收到真实鼠标移动后才生效——无头校验、还没动过鼠标时保持 0，机位不会被拉到角落。
const RESPONSE := 6.0
const MAX_LEAN := 3.0
var max_lean := MAX_LEAN
var offset := Vector3.ZERO
var _seen_mouse := false

func _init(lean: float = MAX_LEAN) -> void:
	max_lean = lean

func note_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_seen_mouse = true

func update(camera: Camera3D, viewport: Viewport, delta: float) -> void:
	var target := Vector3.ZERO
	if camera != null and _seen_mouse:
		target = offset_for(camera, viewport.get_visible_rect().size, viewport.get_mouse_position())
	offset = offset.lerp(target, 1.0 - exp(-RESPONSE * delta))

## 光标所在方向让出的世界偏移，始终留在水平面上：右/下方向各取相机自身坐标系的屏幕右与屏幕下。
func offset_for(camera: Camera3D, size: Vector2, mouse: Vector2) -> Vector3:
	if size.x <= 0.0 or size.y <= 0.0:
		return Vector3.ZERO
	var ndc := mouse / size * 2.0 - Vector2.ONE
	var right := camera.global_transform.basis.x
	var down := -camera.global_transform.basis.y
	right.y = 0.0
	down.y = 0.0
	var direction := right.normalized() * ndc.x + down.normalized() * ndc.y
	return direction.limit_length(1.0) * max_lean
