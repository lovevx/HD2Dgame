extends Node3D
## 科尔波山白盒场景共用脚本：HD2D 固定俯角镜头 + 前景遮挡淡出 + 光柱呼吸 + 阵亡结算回选关。
## 白盒阶段未接入敌人、波次与陷阱；传送门由 scripts/world/scene_portal.gd 负责。
## 视角与远近由玩家自己操作（中键拖动转视角、滚轮推拉距离），光标不再带动镜头。
const HudScene := preload("res://scripts/ui/hud.tscn")
const CameraStyle := preload("res://scripts/world/jungle_camera_style.gd")
const Orbit := preload("res://scripts/world/camera_orbit_controls.gd")
const FADE_ALPHA := 0.26      # 挡住主角的前景树淡到多少
const FADE_RADIUS := 3.0      # 镜头到主角这条线多宽范围内的树算遮挡（树冠较宽，留 3 米）
const CAMERA_LEAD := 0.75
## 锚点的跟随收敛率（每秒，帧率无关）：转视角不需要加速，相机刚性挂在朝向上。
const FOLLOW_SPEED := 5.5
var campaign_managed := false
@export var header_text: String = "科尔波山"
@export var objective_text: String = ""
@export var show_layout_markers: bool = false
@export var camera_focus_bounds := Rect2(-17, -19, 34, 38)
## 空地（竞技场）比外围取景略宽：焦距收窄后对应更远的机位，与构建脚本保持一致。
@export var camera_arena: bool = false
@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Camera3D
var hud: CanvasLayer
var _fadeables: Array[Node3D] = []
var _shafts: Array[Node3D] = []
var _clock := 0.0
var _camera_lead := Vector3.ZERO
var _orbit := Orbit.new()

func _input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		get_viewport().set_input_as_handled()

func _ready() -> void:
	# 允许玩家处理未消费输入，白盒内可正常攻击/剃/用药
	player.set_process_unhandled_input(true)
	# 场景里相机姿势是生成好的：按同一套参数交给轨道控制，出生即正确取景。
	_orbit.configure(camera, CameraStyle.PITCH, CameraStyle.YAW, CameraStyle.distance(camera_arena))
	_orbit.snap(camera, _camera_target(), CameraStyle.composition(_orbit.forward_flat()))
	# 编辑器直接打开场景调试：套一层与正式流程同源的 campaign 控制器，
	# 波次/BOSS/传送门/HUD 全部按存档状态对齐，所见即所玩。
	if get_tree().current_scene == self:
		var ctl: Node = preload("res://scripts/main/campaign.gd").new()
		ctl.set("adopt_world", self)
		add_child(ctl)
	elif not campaign_managed:
		# 复用试炼同一套 HUD：HP/MP、剃与斩击冷却、底部操作提示与按键说明
		hud = HudScene.instantiate()
		add_child(hud)
		hud.configure(header_text, objective_text)
		player.died.connect(_on_player_died)
	for node in get_tree().get_nodes_in_group("colpo_layout_marker"):
		if is_ancestor_of(node):
			node.visible = show_layout_markers
	for node in get_tree().get_nodes_in_group("colpo_fade"):
		_fadeables.append(node)
	for node in get_tree().get_nodes_in_group("colpo_shaft"):
		_shafts.append(node)

func _process(delta: float) -> void:
	_clock += delta
	_update_camera(delta)
	_update_foreground_fade(delta)
	_update_shafts()

## 移动前瞻与帧率无关的跟随；原地转身/瞄准不再推动镜头。
## 平滑只作用在锚点上，构图偏移挂在机位朝向上——转视角时取景关系完全不变。
func _update_camera(delta: float) -> void:
	var movement := Vector3(player.velocity.x, 0, player.velocity.z)
	var lead_target := movement.limit_length(4.0) * (CAMERA_LEAD / 4.0)
	_camera_lead = _camera_lead.lerp(lead_target, 1.0 - exp(-3.0 * delta))
	_orbit.place(camera, _camera_target(), CameraStyle.composition(_orbit.forward_flat()), delta, FOLLOW_SPEED)

## 锚点：玩家位置 + 移动前瞻，只做收边；构图偏移由轨道控制按朝向加上去。
func _camera_target() -> Vector3:
	var focus := player.position + _camera_lead
	focus.x = clampf(focus.x, camera_focus_bounds.position.x, camera_focus_bounds.end.x)
	focus.z = clampf(focus.z, camera_focus_bounds.position.y, camera_focus_bounds.end.y)
	return focus

## 挡在镜头与角色之间的树淡出：HD-2D 里保证主角永远不被前景吃掉的常规做法。
## 判定放在俯视平面（XZ）上做：镜头与角色连成一条线段，靠得太近的树算遮挡。
## 前景里既有共享素材库的 3D 树（调透明度），也保留像素 Sprite3D 树（调 modulate）。
func _update_foreground_fade(delta: float) -> void:
	if _fadeables.is_empty():
		return
	var from := Vector2(camera.global_position.x, camera.global_position.z)
	var to := Vector2(player.global_position.x, player.global_position.z)
	var seg := to - from
	var seg_sq := seg.length_squared()
	if seg_sq < 0.01:
		return
	for node in _fadeables:
		if not is_instance_valid(node):
			continue
		var point := Vector2(node.global_position.x, node.global_position.z)
		var t := clampf((point - from).dot(seg) / seg_sq, 0.0, 1.0)
		# t 落在 0~1 之间说明这棵树在镜头与角色之间（含角色稍后方一点）
		var blocking := t > 0.02 and t < 0.98 and (point - (from + seg * t)).length() < FADE_RADIUS
		_fade(node, FADE_ALPHA if blocking else 1.0, delta)

func _fade(node: Node3D, target: float, delta: float) -> void:
	var sprite := node as Sprite3D
	if sprite != null:
		sprite.modulate.a = lerpf(sprite.modulate.a, target, minf(1.0, delta * 7.0))
		return
	_apply_transparency(node, lerpf(maxf(_fade_alpha(node), 0.0), target, minf(1.0, delta * 7.0)))

## 素材树的当前不透明度：透明度属性 0 为不透明，1 为全透明；找不到可渲染子节点时返回 -1。
func _fade_alpha(node: Node) -> float:
	if node is GeometryInstance3D:
		return 1.0 - (node as GeometryInstance3D).transparency
	for child in node.get_children():
		var found := _fade_alpha(child)
		if found >= 0.0:
			return found
	return -1.0

func _apply_transparency(node: Node, alpha: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = clampf(1.0 - alpha, 0.0, 1.0)
	for child in node.get_children():
		_apply_transparency(child, alpha)

## 光柱缓慢呼吸：明暗浮动一点，免得像插在地上的一排塑料条。
func _update_shafts() -> void:
	for node in _shafts:
		if not is_instance_valid(node):
			continue
		var mesh := node as MeshInstance3D
		var mat := mesh.material_override as StandardMaterial3D
		if mat == null:
			continue
		var phase: float = mesh.get_meta("phase", 0.0)
		var base: float = mesh.get_meta("base_alpha", 0.07)
		mat.albedo_color.a = base * (0.65 + 0.35 * sin(_clock * 0.7 + phase))

## 阵亡不写存档：给一个结算面板，一键回选关面板重来。
func _on_player_died() -> void:
	hud.hide_prompt()
	hud.show_panel("行动失败", "苏晓倒在了科尔波山。\n白盒阶段不消耗逃脱币，也不会永久死亡。", "返回选关", _back_to_select)

func _back_to_select() -> void:
	GameState.change_scene(GameState.LEVEL_SELECT_SCENE)
