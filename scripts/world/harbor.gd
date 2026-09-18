extends Node3D
## 灰潮港主城：城门传送、商店、强化、任务委托与码头试炼。
## 港口独立 HD2D 机位，复用角色移动。
const HudScene := preload("res://scripts/ui/hud.tscn")
const MouseLead := preload("res://scripts/world/camera_mouse_lead.gd")
## 机位参数与 tools/build_harbor.gd 保持一致：俯角 / 侧转 / 焦点距离 / 活动范围收边。
## 24° 俯角、正面视角、38 米距离与 26° FOV。
const CAM_PITCH := 24.0
const CAM_YAW := 0.0
const CAM_DISTANCE := 38.0
const CAM_FOV := 26.0
const FOCUS_LIMIT_X := 18.0
const FOCUS_LIMIT_Z := Vector2(-19.0, 16.0)
## 港口景物集中在北侧街市：街市段把取景中心往北偏一点，走上码头时收回偏移，免得出画。
const LOOK_AHEAD_Z := -3.0
@export var show_layout_markers: bool = false
var campaign_managed := false
@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Camera3D
var cam_offset := Vector3.ZERO
var _mouse_lead := MouseLead.new()

func _input(event: InputEvent) -> void:
	_mouse_lead.note_input(event)

func _ready() -> void:
	# 允许玩家处理未消费输入，港口内可正常攻击/剃/用药
	player.set_process_unhandled_input(true)
	# 运行时机位与构建脚本保持一致。
	camera.rotation_degrees = Vector3(-CAM_PITCH, CAM_YAW, 0)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAM_FOV
	cam_offset = Basis.from_euler(Vector3(deg_to_rad(-CAM_PITCH), deg_to_rad(CAM_YAW), 0.0)) * Vector3(0, 0, CAM_DISTANCE)
	# 复用试炼同一套 HUD：港口同样有 HP/MP、剃与斩击冷却和操作提示
	var hud: CanvasLayer
	if not campaign_managed:
		hud = HudScene.instantiate()
		add_child(hud)
	var title := "灰潮港 · 主城"
	if GameState.player_name != "":
		title += "　契约者 %s" % GameState.player_name
	if hud:
		hud.configure(title, "北：传送广场\n西：商店 / 任务    东：工坊 / 试炼\n靠近功能点按 V")
	camera.position = player.position + Vector3(0, 0, LOOK_AHEAD_Z) + cam_offset
	# 分区标记（Label3D + 地面光圈）默认隐藏，开发审阅布局时打开
	for node in get_tree().get_nodes_in_group("harbor_zone_marker"):
		if node is Node3D:
			node.visible = show_layout_markers

func _process(delta: float) -> void:
	# 镜头跟随玩家，只在场边做收边；正交投影下偏移只决定取景中心。
	_mouse_lead.update(camera, get_viewport(), delta)
	var anchor := Vector3(clampf(player.position.x, -FOCUS_LIMIT_X, FOCUS_LIMIT_X), 0, clampf(player.position.z, FOCUS_LIMIT_Z.x, FOCUS_LIMIT_Z.y))
	var look_ahead := LOOK_AHEAD_Z * (1.0 - smoothstep(8.0, 14.0, player.position.z))
	camera.position = camera.position.lerp(anchor + Vector3(0, 0, look_ahead) + cam_offset + _mouse_lead.offset, minf(1, delta * 4))


