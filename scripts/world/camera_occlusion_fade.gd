## 前景遮挡淡出：镜头与玩家之间被大体量景物挡住时，把那件景物调成半透明；让开后平滑恢复。
##
## 挂法：player.gd 在 _ready() 里挂到玩家身上——换关卡不用改场景，四张关卡图一起生效。
## 相机与关卡树都自己找（先用视口当前相机，找不到再退回到关卡里的第一台）。
##
## 为什么用「包围盒与视线相交」而不是物理射线：
## 港口的城墙、城门只砌几何、不生成碰撞（碰撞由 build_actors() 的隐形屏障负责），
## 射线会整个漏掉它们——而它们恰恰是最常挡住人的东西。
##
## 为什么用「临时换材质」而不是逐实例 GeometryInstance3D.transparency（2026-09-19 像素回读实测）：
##   · 标准材质：transparency 有效，直接用它（不动材质，最省）。
##   · 自定义着色器：transparency 完全没有反应（城墙、预设模型都是这一类），
##     只能换成「淡出版本材质」（shaders/occlusion_fade_*.gdshader）。
##   换成淡出版本材质**只在淡出期间存在**：静止时场景与改动前逐像素一致（已用像素回读对照过）。
##
## 淡出材质刻意不写深度：写深度的半透明墙会把身后的玩家深度剔除掉，只剩背景透出来，
## 那样就完全失去「露出玩家」的意义。
extends Node3D

const FADE_VARIANTS := {
	"res://shaders/harbor_wall.gdshader":
		preload("res://shaders/occlusion_fade_harbor_wall.gdshader"),
	"res://addons/hd2d_scene_tools/shaders/preset_normal.gdshader":
		preload("res://shaders/occlusion_fade_preset.gdshader"),
}
const FADE_UNIFORM := "occl_fade"
const IGNORE_GROUP := &"occlusion_ignore"

## 遮挡高亮描边：楼淡成深色剪影后，黑衣玩家在剪影里依旧难认（暗上暗没对比）。
## 有单元淡出时，在玩家贴片背后垫一圈放大的亮色剪影（同 dash 残影的取法：
## 取角色图 alpha 涂色、unshaded），像描边一样把玩家从剪影里"勾"出来。
## modulate 提亮无效——乘算对黑衣仍是黑（dash_fx.gd 踩过），所以走剪影贴片。
const HIGHLIGHT_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;
uniform sampler2D highlight_texture : hint_default_white, filter_nearest;
uniform vec4 highlight_tint : source_color = vec4(1.0, 0.0, 0.0, 0.0);
void fragment() {
	ALBEDO = highlight_tint.rgb;
	ALPHA = texture(highlight_texture, UV).a * highlight_tint.a;
}
"""
const HIGHLIGHT_COLOR := Color(1.0, 0.93, 0.72, 0.85)  # 暖白描边：对深蓝楼影对比最强
const HIGHLIGHT_SCALE := 1.22
## 描边淡入淡出速度（每秒变化量）。
const HIGHLIGHT_SPEED := 10.0

## 关掉就完全不介入渲染，方便 A/B 对照。
@export var enabled := true
## 只看够高的东西：地皮、海面、驳岸这类扁平体不进候选，避免脚下地面被当成遮挡。
@export var min_height := 1.2
## 被挡时的透明程度：0 = 不变，1 = 全透。0.80 + 淡出着色器的轮廓勾边。
## 调参史（2026-09-20 用户三轮反馈）：0.62/0.60 主体太实——玩家被楼压住看不清；
## 0.85~0.70 纯透明——楼整个消失。最终方案：**主体 0.80 + 边缘 Fresnel 勾边**，
## 玩家清晰透出的同时，楼的形状由轮廓线承担（occl_tint 青调染色辅助）。
@export_range(0.0, 1.0, 0.01) var fade_amount := 0.65
## 淡出与恢复的速度（每秒变化量）：淡出快一点，让开时收得利落。
@export var fade_in_speed := 9.0
@export var fade_out_speed := 6.0
## 玩家身上的采样高度（相对脚底）：头顶 / 胸口 / 小腿，任一被挡就算遮挡。
@export var sample_heights := PackedFloat32Array([1.72, 1.10, 0.45])
## 胸口两侧的横向采样，用来兜住"只挡住半边身子"的情况。
@export var side_reach := 0.35
## 候选包围盒的重扫间隔：场景里会动态增删景物（道具重建、特效生成），定期刷新即可。
## 候选重扫间隔（秒）：只影响"场景里新增/移除够高网格"的发现速度；
## 逐帧的视线判定（_scan）不受它影响，淡出响应依旧是即时的。
@export var refresh_interval := 2.0
## 同一次砌筑的叠层（勒脚 / 墙身 / 瓦檐 / 瓦脊）合并成一个淡出单元，避免只淡一层、
## 留下"墙身透明、顶上瓦檐还是实心"的割裂观感。判据是俯视投影的重合度：叠层脚底一致，
## 重合度接近 1；沿墙相邻的两段只擦一条缝，重合度接近 0，不会被并进来。
@export_range(0.0, 1.0, 0.05) var cluster_overlap := 0.6
## 摆件成簇的范围：挨着摆的两件（竹棚与它旁边的渔网）水平中心距在这个数内才算同一处。
## 用距离而不是单纯的重合度，是因为码头那种大平台会把整个 Pier0 都罩进投影里——
## 只看重合度，竹棚一命中就会把脚下的栈桥一起拖淡。
@export var cluster_radius := 2.5
## 同一处的两件个头要相当（高度比）。这条把"大平台 / 地面"和"立件"彻底分开。
@export_range(0.0, 1.0, 0.05) var cluster_height_ratio := 0.45
## 包围盒内缩，避免视线擦着边就算遮挡。
@export var hit_skin := 0.06
## 视线至少要穿过这么厚才算遮挡：长条景物（船、崖壁）的包围盒是包出来的，
## 视线从角落擦过去并不真的挡住人，不给这个下限会到处误淡。
@export var min_cross := 0.15

var _player: Node3D
var _root: Node
var _candidates: Array = []
var _active := {}
var _refresh_timer := 0.0
var _warned := {}
## 摆件成簇的缓存（每次重扫候选时清掉，场景里的景物是会动态增删的）。
var _cluster_cache := {}
var _cluster_boxes := {}
## 遮挡高亮描边（见 HIGHLIGHT_SHADER 注释）。
var _highlight: Sprite3D
var _highlight_mat: ShaderMaterial
var _highlight_source: Sprite3D
var _highlight_alpha := 0.0

func _ready() -> void:
	_player = get_parent() as Node3D
	_root = _resolve_root()
	_setup_highlight()
	set_physics_process(true)
	_refresh()

## 玩家贴片背后垫一圈放大的亮色剪影：平时全透，遮挡淡出时亮起当描边。
func _setup_highlight() -> void:
	if _player == null:
		return
	_highlight_source = _player.get_node_or_null("pivot/CharacterSprite") as Sprite3D
	if _highlight_source == null:
		return
	_highlight = Sprite3D.new()
	_highlight.name = "OcclusionHighlight"
	_highlight.texture_filter = _highlight_source.texture_filter
	_highlight.pixel_size = _highlight_source.pixel_size
	_highlight.offset = _highlight_source.offset
	_highlight.billboard = _highlight_source.billboard
	_highlight.shaded = false
	_highlight.scale = Vector3.ONE * HIGHLIGHT_SCALE
	_highlight_mat = ShaderMaterial.new()
	_highlight_mat.shader = Shader.new()
	_highlight_mat.shader.code = HIGHLIGHT_SHADER
	_highlight.material_override = _highlight_mat
	# 描边贴片是发光的表现层，不该反过来当遮挡候选，也不投影。
	_highlight.add_to_group(IGNORE_GROUP)
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_player.add_child(_highlight)

## 每帧同步描边：贴在角色贴片正后（背对镜头 4 厘米），淡出越深描边越亮。
func _update_highlight(delta: float, camera: Camera3D) -> void:
	if _highlight == null or _highlight_source == null:
		return
	if not is_instance_valid(_highlight_source):
		return
	var sprite := _highlight_source
	_highlight.flip_h = sprite.flip_h
	_highlight.texture = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var target := sprite.global_position
	if camera != null:
		# 往背对镜头的方向垫 4 厘米（机位可以转到任何朝向，按相机方向算）。
		var away := sprite.global_position - camera.global_position
		away.y = 0.0
		if away.length_squared() > 0.0001:
			target -= away.normalized() * 0.04
	_highlight.global_position = target
	var wanted := 0.0
	for key in _active:
		wanted = maxf(wanted, float(_active[key]["t"]))
	var goal := wanted * HIGHLIGHT_COLOR.a
	_highlight_alpha = move_toward(_highlight_alpha, goal, HIGHLIGHT_SPEED * delta)
	if _highlight_alpha < 0.004 and goal <= 0.0:
		_highlight.visible = false
		return
	_highlight.visible = true
	var tint: Color = HIGHLIGHT_COLOR
	tint.a = _highlight_alpha
	_highlight_mat.set_shader_parameter("highlight_tint", tint)

## 关卡根：优先用运行中的场景根，其次是玩家的父节点（四张关卡图里玩家都直接挂在根上）。
func _resolve_root() -> Node:
	var scene := get_tree().current_scene
	if scene != null and _player != null and scene.is_ancestor_of(_player):
		return scene
	var parent := _player.get_parent() if _player != null else null
	return parent if parent != null else _player

func _physics_process(delta: float) -> void:
	var camera := _camera()
	if not enabled or _player == null or not is_instance_valid(_player) or camera == null:
		_fade_all_out(delta)
		_update_highlight(delta, camera)
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh()
	_scan(camera)
	_update(delta)
	_update_highlight(delta, camera)

func _camera() -> Camera3D:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return camera
	# 无头校验等场合：视口没有当前相机时，退回关卡里的第一台。
	if _root == null:
		return null
	for node in _root.find_children("*", "Camera3D", true, false):
		return node as Camera3D
	return null

## 重扫候选：够高的网格实例（墙、房、船、棚、杆），排除玩家自己与显式忽略的。
## 注意：**簇缓存（_cluster_cache / _cluster_boxes）不在这里清**。簇是静态结构
## （摆件位置、同层兄弟关系不变），而算一次全场景簇包围盒要 ~80ms——每秒清一次
## 就是每秒一次掉帧（跑步时尤其明显，用户反馈"跑着跑着卡一下"）。
## 候选列表本身仍每轮重建：节点可能增删，新 prop 走缓存 miss 的路径现算。
## 实测（tools/probe_occlusion_cost.gd）：重建帧 85ms → 4ms，掉帧帧数 15/900 → 0。
func _refresh() -> void:
	_refresh_timer = refresh_interval
	_candidates.clear()
	if _root == null:
		return
	for kind in ["MeshInstance3D", "MultiMeshInstance3D"]:
		for node in _root.find_children("*", kind, true, false):
			var inst := node as GeometryInstance3D
			if inst == null or not inst.is_visible_in_tree():
				continue
			if _player != null and (_player == inst or _player.is_ancestor_of(inst)):
				continue
			if inst.is_in_group(IGNORE_GROUP):
				continue
			var box := _world_aabb(inst)
			if box.size.y < min_height:
				continue
			# 判定用的是「这一处景观」的整体包围盒：同簇的几件（竹棚 + 渔网）算一个整体，
			# 视线的列擦到其中任何一件，整堆都淡。只按单件判定会卡在边界上——
			# 渔网比竹棚往西探出半米，视线正好从那半米里穿过，竹棚就漏了。
			var prop := _prop_ancestor(inst)
			if prop != null:
				_candidates.append({"node": inst, "box": _shrink(_cluster_box(prop))})
			else:
				_candidates.append({"node": inst, "box": _shrink(box)})

## 视线检测：相机 → 玩家身上的采样点，撞到哪件景物就把它的淡出单元点亮。
func _scan(camera: Camera3D) -> void:
	var base := _player.global_position
	var eye := camera.global_position
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.0001 else Vector3.RIGHT
	var middle: float = sample_heights[sample_heights.size() / 2] if sample_heights.size() > 0 else 1.1
	var targets: Array[Vector3] = []
	for height in sample_heights:
		targets.append(base + Vector3.UP * height)
	targets.append(base + Vector3.UP * middle + right * side_reach)
	targets.append(base + Vector3.UP * middle - right * side_reach)
	# 粗筛用：相机与所有采样点合起来的那一小块空间，先一刀排掉远处的大多数候选。
	var sight := AABB(eye, Vector3.ZERO)
	for target in targets:
		sight = sight.expand(target)
	sight = sight.grow(0.5)

	var units := {}
	for candidate in _candidates:
		# 先无类型读取、判存活，再转类型：候选缓存每 refresh_interval 秒才重建，
		# 期间节点可能已被释放（敌人死亡 / 换场景）。带类型的赋值碰已释放实例会直接报
		# 「Trying to assign invalid previously freed instance」——判存活必须在赋值之前。
		var node_ref = candidate["node"]
		if not is_instance_valid(node_ref):
			continue
		var inst := node_ref as GeometryInstance3D
		if inst == null or not inst.is_visible_in_tree():
			continue
		var box: AABB = candidate["box"]
		if not box.intersects(sight):
			continue
		# 玩家或镜头本身就在这件景物里（门洞、脚下栈道、城墙内侧贴边）→ 不算遮挡。
		if box.has_point(base) or box.has_point(eye):
			continue
		for target in targets:
			if _segment_hits_box(eye, target, box):
				var key := _unit_key(inst)
				if not units.has(key):
					units[key] = []
				units[key].append(inst)
				break

	for key in units:
		if not _active.has(key):
			_active[key] = _begin_unit(key, units[key])
		_active[key]["wanted"] = true

func _update(delta: float) -> void:
	for key in _active.keys():
		var entry: Dictionary = _active[key]
		var wanted: bool = entry["wanted"]
		entry["wanted"] = false
		var goal := 1.0 if wanted else 0.0
		var speed := fade_in_speed if wanted else fade_out_speed
		var t := move_toward(float(entry["t"]), goal, speed * delta)
		if absf(t - float(entry["t"])) > 0.0005:
			entry["t"] = t
			_apply(entry, t)
		if t <= 0.0 and not wanted:
			_end_unit(key, entry)

## 关掉功能或没有相机时，让所有已淡出的景物平滑回到实体。
func _fade_all_out(delta: float) -> void:
	if _active.is_empty():
		return
	for key in _active.keys():
		var entry: Dictionary = _active[key]
		var t := move_toward(float(entry["t"]), 0.0, fade_out_speed * delta)
		entry["t"] = t
		_apply(entry, t)
		if t <= 0.0:
			_end_unit(key, entry)

## 淡出单元的身份：道具按整簇道具（挨着摆的竹棚/渔网/货架一起），砌体按父节点。
func _unit_key(inst: GeometryInstance3D) -> Node:
	var prop := _prop_ancestor(inst)
	if prop != null:
		return _cluster_of(prop)[0]
	var parent: Node = inst.get_parent()
	return parent if parent != null else inst

## 同一处摆件常常是分开的几件 HD2DProp（竹棚、渔网、竹牌……），挨着摆、投影互相压着。
## 只淡命中的那一件，会看着像"漏了一块"——码头东端就出过这事：渔网淡了、紧挨着的竹棚没淡。
## 所以把同簇的兄弟摆件并进同一个淡出单元。只在同一父节点下成簇，不跨区域连片。
func _cluster_of(prop: Node) -> Array:
	if _cluster_cache.has(prop):
		return _cluster_cache[prop]
	var siblings: Array = []
	var parent: Node = prop.get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is HD2DProp:
				siblings.append(child)
	var boxes := {}
	for sibling in siblings:
		boxes[sibling] = _prop_aabb(sibling)
	# 连通分量：同一处的几件归为一簇。
	var members: Array = []
	var seen := {}
	var stack: Array = [prop]
	seen[prop] = true
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		members.append(current)
		for sibling in siblings:
			if seen.has(sibling):
				continue
			if _same_cluster(boxes[current], boxes[sibling]):
				seen[sibling] = true
				stack.append(sibling)
	members.sort_custom(func(a, b): return siblings.find(a) < siblings.find(b))
	for member in members:
		_cluster_cache[member] = members
	return members

## 两件摆件是不是"同一处的一堆东西"：投影压在一起、水平中心离得近、个头也相当。
## 不能只看投影重合度——码头是一块 16x13 米的大平台，竹棚整个落在它投影里，
## 只看重合度会把脚下的栈桥拖进淡出单元。
func _same_cluster(a: AABB, b: AABB) -> bool:
	var ra := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
	var rb := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
	if not ra.intersects(rb):
		return false
	if ra.get_center().distance_to(rb.get_center()) > cluster_radius:
		return false
	var short := minf(a.size.y, b.size.y)
	var tall := maxf(a.size.y, b.size.y)
	return tall > 0.0 and short / tall >= cluster_height_ratio

## 一件摆件整体的世界包围盒（合并它名下所有网格）。
func _prop_aabb(prop: Node) -> AABB:
	var box := AABB()
	var first := true
	for kind in ["MeshInstance3D", "MultiMeshInstance3D"]:
		for node in prop.find_children("*", kind, true, false):
			var inst := node as GeometryInstance3D
			if inst == null or not inst.is_visible_in_tree():
				continue
			var inst_box := _world_aabb(inst)
			if first:
				box = inst_box
				first = false
			else:
				box = box.merge(inst_box)
	return box

## 整簇景观的世界包围盒（竹棚 + 挨着的渔网并成一块）。
func _cluster_box(prop: Node) -> AABB:
	if _cluster_boxes.has(prop):
		return _cluster_boxes[prop]
	var members := _cluster_of(prop)
	var box := AABB()
	var first := true
	for member in members:
		var member_box := _prop_aabb(member)
		if first:
			box = member_box
			first = false
		else:
			box = box.merge(member_box)
	for member in members:
		_cluster_boxes[member] = box
	return box

## 单元内要一起淡的实例：道具整簇一起淡；砌体按父节点下包围盒相接的兄弟件合并。
func _unit_instances(blockers: Array) -> Array:
	var wanted := {}
	for blocker in blockers:
		var prop := _prop_ancestor(blocker)
		if prop != null:
			for member in _cluster_of(prop):
				for node in member.find_children("*", "MeshInstance3D", true, false):
					wanted[node] = true
				for node in member.find_children("*", "MultiMeshInstance3D", true, false):
					wanted[node] = true
			continue
		var parent: Node = blocker.get_parent()
		if parent == null:
			wanted[blocker] = true
			continue
		var base: AABB = _world_aabb(blocker)
		for sibling in parent.get_children():
			var inst := sibling as GeometryInstance3D
			if inst == null or not inst.is_visible_in_tree():
				continue
			if _same_structure(base, _world_aabb(inst)):
				wanted[inst] = true
		wanted[blocker] = true
	return wanted.keys()

## 两件砌体是不是同一次砌筑的叠层：俯视投影重合于较小者的比例达到 cluster_overlap。
## 用"脚底重合"而不是"包围盒相交"，是因为叠层在竖向上首尾相接、并不真的相交，
## 而沿墙相邻的两段会在转角处相接——只看相交会把整圈墙连成一片。
func _same_structure(a: AABB, b: AABB) -> bool:
	var ra := Rect2(a.position.x, a.position.z, a.size.x, a.size.z)
	var rb := Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
	var smaller := minf(ra.get_area(), rb.get_area())
	if smaller <= 0.0:
		return false
	var inter := ra.intersection(rb)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return false
	return (inter.size.x * inter.size.y) / smaller >= cluster_overlap

func _begin_unit(key: Node, blockers: Array) -> Dictionary:
	var entry := {"key": key, "instances": [], "modes": [], "fades": [], "originals": [], "shadows": [], "t": 0.0, "wanted": true}
	for inst in _unit_instances(blockers):
		var mesh := inst as GeometryInstance3D
		if mesh == null:
			continue
		var mode := _fade_mode(mesh)
		if mode == "":
			continue
		var fade_mat: Material = null
		var original: Material = null
		if mode == "shader":
			fade_mat = _make_fade_material(mesh)
			if fade_mat == null:
				continue
			original = mesh.material_override
			mesh.material_override = fade_mat
		elif mode == "clone":
			var existing := mesh.material_override as StandardMaterial3D
			if existing != null and existing.resource_name == "occl_fade_clone":
				# 淡出中重扫候选（refresh 周期到、场景重扫）：复用现存克隆。
				# originals 记成它自己，收尾据此"不还原"——克隆留在 override 上、
				# alpha 已回到 1，渲染结果与原材质一致，下一轮直接复用。
				fade_mat = existing
				original = existing
			else:
				fade_mat = _make_clone_material(mesh)
				if fade_mat == null:
					continue
				original = mesh.material_override
				mesh.material_override = fade_mat
		# 五条数组必须逐位对齐：同一个单元里可能既有标准材质网格、也有自定义着色器网格
		# （"预设摆件 + 程序化网格"并进同簇时就是这样）。曾经 originals 只在 shader 模式下 append，
		# 收尾时按 originals[i] 取就会索引越界（表现为 _end_unit 报 Invalid access of index N）——
		# 非 shader 模式也占一位，值补 null。
		entry["instances"].append(mesh)
		entry["modes"].append(mode)
		entry["fades"].append(fade_mat)
		entry["originals"].append(original)
		# 半透明的楼还投着实心影子，画面立刻穿帮——淡出期间连影子一起收掉，
		# 原值记进 shadows，收尾按位还原（有的实例本来就关着影子，不能一律设回 ON）。
		entry["shadows"].append(mesh.cast_shadow)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return entry

## 一个实例怎么淡：
##   "shader"  —— 登记过淡出变体的自定义着色器，换变体材质 + instance uniform；
##   "clone"   —— StandardMaterial3D 一律克隆转真 ALPHA 混合、用 albedo_color.a 驱动。
##     ※ 逐实例 transparency 对 ALPHA_SCISSOR/HASH 材质**无效**：scissor 流水线没有
##       alpha 混合，实例透明度只参与 discard 阈值比较——0.65 > 贴图阈值 0.333 时
##       所有像素照常通过，画面纹丝不动（工坊铺面就是这批，曾从头到尾没淡过）。
##     ※ "本来就看透"的（ALPHA/HASH 且颜色已带透明）依旧跳过：光柱、水花淡了反而怪。
func _fade_mode(inst: GeometryInstance3D) -> String:
	var material := _material_of(inst)
	if material is ShaderMaterial:
		var path := _shader_path(material as ShaderMaterial)
		if FADE_VARIANTS.has(path):
			return "shader"
		_note_unsupported(path)
		return ""
	if material is StandardMaterial3D:
		# 我们自己克隆出来的淡出材质（淡出中重扫会再遇到它）：维持 clone 模式。
		if material.resource_name == "occl_fade_clone":
			return "clone"
		var std := material as StandardMaterial3D
		var see_through := std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA \
			or std.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		if see_through and std.albedo_color.a < 0.9:
			return ""
		return "clone"
	if material == null:
		return "standard"
	return ""

## 标准材质的淡出克隆：复制原材质（贴图/uv/裁剪全保留），透明模式转真 ALPHA，
## 淡出值走 albedo_color.a（最终 alpha = albedo_color.a × 贴图 alpha）。
## resource_name 打上标记，校验脚本靠它识别"这个 override 是淡出克隆"。
func _make_clone_material(inst: GeometryInstance3D) -> StandardMaterial3D:
	var source := _material_of(inst) as StandardMaterial3D
	if source == null:
		return null
	var dup: StandardMaterial3D = source.duplicate()
	dup.resource_name = "occl_fade_clone"
	dup.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dup.albedo_color = Color(source.albedo_color.r, source.albedo_color.g, source.albedo_color.b, 1.0)
	return dup

## 淡出版本材质：同一个着色器 + 抄过来的可调参数 + 逐实例的 occl_fade。
func _make_fade_material(inst: GeometryInstance3D) -> ShaderMaterial:
	var source := _material_of(inst) as ShaderMaterial
	if source == null or source.shader == null:
		return null
	var variant: Shader = FADE_VARIANTS.get(_shader_path(source), null)
	if variant == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = variant
	for uniform in variant.get_shader_uniform_list():
		var name := String(uniform["name"])
		if name == FADE_UNIFORM:
			continue
		var value = source.get_shader_parameter(name)
		if value != null:
			material.set_shader_parameter(name, value)
	return material

func _apply(entry: Dictionary, t: float) -> void:
	var alpha := clampf(1.0 - t * fade_amount, 0.0, 1.0)
	var instances: Array = entry["instances"]
	for i in instances.size():
		# 同 _scan：淡出单元登记后，成员网格可能已被释放，判存活要在转类型之前。
		var node_ref = instances[i]
		if not is_instance_valid(node_ref):
			continue
		var inst := node_ref as GeometryInstance3D
		if inst == null:
			continue
		if entry["modes"][i] == "shader":
			inst.set_instance_shader_parameter(FADE_UNIFORM, alpha)
		elif entry["modes"][i] == "clone":
			var mat := entry["fades"][i] as StandardMaterial3D
			if mat != null:
				# Color 是值类型：改 .a 分量只改了临时拷贝，必须整体赋值才写回材质。
				mat.albedo_color = Color(mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, alpha)
		else:
			inst.transparency = t * fade_amount

func _end_unit(key: Node, entry: Dictionary) -> void:
	var instances: Array = entry["instances"]
	for i in instances.size():
		var node_ref = instances[i]
		if not is_instance_valid(node_ref):
			continue
		var inst := node_ref as GeometryInstance3D
		if inst == null:
			continue
		if entry["modes"][i] == "shader" or entry["modes"][i] == "clone":
			# 只在还挂着我们的淡出材质时还原；克隆复用位（originals==fades）不还原——
			# 克隆留在 override 上、alpha 已回到 1，渲染等同原材质。
			if inst.material_override == entry["fades"][i] \
					and entry["originals"][i] != entry["fades"][i]:
				inst.material_override = entry["originals"][i]
		else:
			inst.transparency = 0.0
		inst.cast_shadow = entry["shadows"][i]
	_active.erase(key)

## 供校验脚本读取：当前正在淡出的单元、进度与参与淡出的网格名。
func active_units() -> Dictionary:
	var out := {}
	for key in _active:
		var entry: Dictionary = _active[key]
		if float(entry["t"]) <= 0.001:
			continue
		var parts: Array[String] = []
		for inst in entry["instances"]:
			if is_instance_valid(inst):
				parts.append(str(inst.name))
		out[str(key.name)] = {"t": float(entry["t"]), "parts": parts}
	return out

func _material_of(inst: GeometryInstance3D) -> Material:
	if inst.material_override != null:
		return inst.material_override
	if not _is_mesh(inst):
		return null
	if inst is MeshInstance3D:
		return inst.get_active_material(0)
	# MultiMeshInstance3D 没有 get_active_material：材质在底层 mesh 的表面材质里，
	# 取不到就退回 standard（透明度淡出）。
	var mm := (inst as MultiMeshInstance3D).multimesh
	if mm == null or mm.mesh == null or mm.mesh.get_surface_count() <= 0:
		return null
	return mm.mesh.surface_get_material(0)

func _shader_path(material: ShaderMaterial) -> String:
	return material.shader.resource_path if material.shader != null else ""

func _world_aabb(inst: GeometryInstance3D) -> AABB:
	return inst.global_transform * inst.get_aabb()

## 网格实例才算景物：Label3D、粒子、精灵也派生自 GeometryInstance3D，但它们不该淡。
func _is_mesh(node: Node) -> bool:
	return node is MeshInstance3D or node is MultiMeshInstance3D

## 内缩一圈用来判断"擦到边"，但要逐轴收住，薄片（栏杆、立牌）内缩过头会变成负尺寸。
func _shrink(box: AABB) -> AABB:
	var inset := Vector3(
		minf(hit_skin, box.size.x * 0.25),
		minf(hit_skin, box.size.y * 0.25),
		minf(hit_skin, box.size.z * 0.25))
	return AABB(box.position + inset, box.size - inset * 2.0)

func _prop_ancestor(node: Node) -> Node:
	var current := node
	while current != null and current != _root:
		if current is HD2DProp:
			return current
		current = current.get_parent()
	return null

## 线段与轴对齐包围盒相交（slab 法），并要求穿透厚度达到 min_cross。
func _segment_hits_box(from: Vector3, to: Vector3, box: AABB) -> bool:
	if box.size.x <= 0.0 or box.size.y <= 0.0 or box.size.z <= 0.0:
		return false
	var dir := to - from
	var span := Vector2(0.0, 1.0)
	span = _slab(from.x, dir.x, box.position.x, box.position.x + box.size.x, span)
	if span.x > span.y:
		return false
	span = _slab(from.y, dir.y, box.position.y, box.position.y + box.size.y, span)
	if span.x > span.y:
		return false
	span = _slab(from.z, dir.z, box.position.z, box.position.z + box.size.z, span)
	if span.x > span.y:
		return false
	return (span.y - span.x) * dir.length() >= min_cross

func _slab(origin: float, dir: float, lo: float, hi: float, span: Vector2) -> Vector2:
	if absf(dir) < 0.000001:
		# 与该轴平行：只要起点在这条轴之外就永远打不到。
		return span if origin >= lo and origin <= hi else Vector2(1.0, 0.0)
	var a := (lo - origin) / dir
	var b := (hi - origin) / dir
	return Vector2(maxf(span.x, minf(a, b)), minf(span.y, maxf(a, b)))

func _note_unsupported(path: String) -> void:
	var label := path if path != "" else "（内联着色器）"
	if _warned.has(label) or _warned.size() >= 8:
		return
	_warned[label] = true
	print("[前景遮挡] 这类材质还没有淡出版本，先不处理：%s" % label)
