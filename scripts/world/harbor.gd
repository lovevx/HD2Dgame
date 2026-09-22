extends Node3D
## 灰潮港主城：城门传送、商店、强化、任务委托与码头试炼。
## 港口独立 HD2D 机位，复用角色移动。
## 机位由玩家显式控制：按住鼠标中键拖动绕角色转视角（左右改朝向、上下改俯角），滚轮推拉距离。
## 光标移到哪都不再带动镜头。
const HudScene := preload("res://scripts/ui/hud.tscn")
const Orbit := preload("res://scripts/world/camera_orbit_controls.gd")
## 默认机位参数与 tools/build_harbor.gd 保持一致：俯角 / 侧转 / 焦点距离 / 活动范围收边。
## 16° 俯角、正面视角、48 米距离与 18° FOV，长焦压缩透视形成平铺舞台感；
## 机位比 24°/33m 时更远，是为了在收窄焦距后保持角色在画面里的占比不变。
## 运行起来后这三个值都能被中键拖动与滚轮改掉，这里只作为出生时的默认。
const CAM_PITCH := 16.0
const CAM_YAW := 0.0
const CAM_DISTANCE := 48.1
const CAM_FOV := 18.0
## 活动区扩到整块地基（x ±41 / z -31~12）后，焦点也放开到贴近城墙，只在最后几米收边。
const FOCUS_LIMIT_X := 36.0
const FOCUS_LIMIT_Z := Vector2(-27.0, 16.0)
## 港口景物集中在北侧街市：街市段把取景中心往北偏一点，走上码头时收回偏移，免得出画。
## 偏移按「画面深处」的世界方向给，转了视角也不会把角色挤出取景中心。
const LOOK_AHEAD_Z := -3.0
## 跟随响应：锚点按这个收敛率平滑跟随（每秒收敛率，帧率无关）。
## 转视角不需要额外加速——相机刚性挂在朝向上，转动不经过平滑，本来就不会有拖尾。
const FOLLOW_SPEED := 4.0
@export var show_layout_markers: bool = false
var campaign_managed := false
## 非战役模式（直接开港调试）自建的 HUD：委托所的服务点要接线到它身上的任务档案面板。
var ui_hud: CanvasLayer = null
@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $Camera3D
var _orbit := Orbit.new()

func _input(event: InputEvent) -> void:
	if _orbit.handle_input(event):
		get_viewport().set_input_as_handled()

func _ready() -> void:
	# 允许玩家处理未消费输入，港口内可正常攻击/剃/用药
	player.set_process_unhandled_input(true)
	# 运行时机位与构建脚本保持一致：朝向由轨道控制按同一套参数给出。
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAM_FOV
	_orbit.configure(camera, CAM_PITCH, CAM_YAW, CAM_DISTANCE)
	# 码头港口向导先立起来（campaign 接线/直接打开调试都依赖它存在）。
	_build_guide_npc()
	# 编辑器直接打开场景调试：套一层与正式流程同源的 campaign 控制器，
	# 向导/试炼传送阵/商店/任务/出发门控全部按存档状态对齐，所见即所玩。
	if get_tree().current_scene == self:
		var ctl: Node = preload("res://scripts/main/campaign.gd").new()
		ctl.set("adopt_world", self)
		add_child(ctl)
	elif not campaign_managed:
		# 复用试炼同一套 HUD：港口同样有 HP/MP、剃与斩击冷却和操作提示
		var hud := HudScene.instantiate()
		add_child(hud)
		ui_hud = hud
		var title := "灰潮港 · 主城"
		if GameState.player_name != "":
			title += "　契约者 %s" % GameState.player_name
		hud.configure(title, "北：传送广场    西北：轮回商店\n西：任务    东：工坊 / 试炼\n靠近功能点按 V · J 任务档案")
	# 轮回商店：左上街角的店面，V 打开完整商店 UI（购买走 GameState.buy_item）；
	# 战役模式不会再覆盖 campaign_action，所有商品统一由店内购买。
	var shop_panel_script := preload("res://scripts/ui/shop_panel.gd")
	var shop_panel: CanvasLayer = shop_panel_script.new()
	shop_panel.name = "ShopPanel"
	add_child(shop_panel)
	var shop_service := get_node_or_null("ShopService")
	if shop_service != null:
		shop_service.panel_handler = shop_panel.open
	# 港务委托所：非战役模式（直接开港调试）V 也开同一块任务档案面板。
	# 战役模式里 campaign_action（campaign.show_tasks）优先，走的是同一块面板 + 接取按钮。
	var quest_service := get_node_or_null("QuestService")
	if quest_service != null and ui_hud != null:
		quest_service.panel_handler = ui_hud.open_quest_log
	_orbit.snap(camera, _focus_anchor(), _look_ahead_offset())
	# 分区标记（Label3D + 地面光圈）默认隐藏，开发审阅布局时打开
	for node in get_tree().get_nodes_in_group("harbor_zone_marker"):
		if node is Node3D:
			node.visible = show_layout_markers

func _process(delta: float) -> void:
	_update_camera(delta)

## 镜头跟随玩家，只在场边做收边；机位朝向与距离由轨道控制给出。
## 跟上来的只有"收边后的玩家位置"这一段（锚点），构图偏移与轨道偏移挂在朝向上、转动即时生效。
func _update_camera(delta: float) -> void:
	_orbit.place(camera, _focus_anchor(), _look_ahead_offset(), delta, FOLLOW_SPEED)

## 锚点：玩家位置在场边收边。y 钉在 0——玩家脚下就是地面，机位不该跟着小起伏动。
func _focus_anchor() -> Vector3:
	return Vector3(
		clampf(player.position.x, -FOCUS_LIMIT_X, FOCUS_LIMIT_X),
		0,
		clampf(player.position.z, FOCUS_LIMIT_Z.x, FOCUS_LIMIT_Z.y))

## 街市段把取景中心往画面深处（北）推 3 米，走上码头时收回；方向跟着机位朝向走。
func _look_ahead_offset() -> Vector3:
	var look_ahead := LOOK_AHEAD_Z * (1.0 - smoothstep(8.0, 14.0, player.position.z))
	return _orbit.forward_flat() * (-look_ahead)

## 码头港口向导：站在船靠岸的跳板边，引导新人去东侧试炼场。
## 复用 harbor_service 的 V 交互（靠近提示 / 面板）；战役新手流程由 campaign.gd 注入
## campaign_action 推进流程（对话 → flow=training），独立调试模式只展示说明。
func _build_guide_npc() -> void:
	var npc := Area3D.new()
	npc.name = "GuideNpc"
	npc.position = Vector3(4.0, 0, 9.0)
	npc.set_script(preload("res://scripts/world/harbor_service.gd"))
	npc.set("title", "港口向导")
	npc.set("description", "「新人，快去东侧的试炼场地熟悉一下身手吧！」\n\n东侧码头旁的试炼传送阵会送你去练武场。\n\n打三下木桩、用一次剃（Shift），就能领到整套基础装备。")
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.7
	shape.height = 3.4
	collision.shape = shape
	collision.position.y = 1.1
	npc.add_child(collision)
	# 白盒人形：躯干 + 头 + 头顶名牌，配色偏任务区青绿（绿=任务，与港务委托所一致）
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.34
	capsule.height = 1.35
	body.mesh = capsule
	body.position.y = 0.75
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color("6e7f6e")
	body.material_override = cloth
	npc.add_child(body)
	var head := MeshInstance3D.new()
	var hbox := BoxMesh.new()
	hbox.size = Vector3(0.44, 0.44, 0.44)
	head.mesh = hbox
	head.position.y = 1.66
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color("e0b48c")
	head.material_override = skin
	npc.add_child(head)
	var label := Label3D.new()
	label.text = "港口向导"
	label.position = Vector3(0, 2.6, 0)
	label.font_size = 42
	label.pixel_size = 0.008
	label.outline_size = 12
	label.modulate = Color("a4efc2")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	npc.add_child(label)
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.15
	disc.bottom_radius = 1.15
	disc.height = 0.02
	ring.mesh = disc
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.64, 0.94, 0.76, 0.18)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position = Vector3(0, 0.02, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	npc.add_child(ring)
	add_child(npc)
