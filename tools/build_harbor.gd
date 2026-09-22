extends SceneTree
## 灰潮港口（主城）重建脚本：地面/海面仍由程序化几何承担，建筑、码头、船只、道具、围墙全部改用
## HD-2D 共享素材库预设（res://assets/hd2d_presets，由 tools/import_presets.gd 入库）。
## 生成：scenes/world/harbor.tscn
## 布局（北 → 南）：围墙/城门 → 商店区(西) / 装备强化区(东) → 试炼场景入口 → 港务作业区 → 双码头/海面。
## 五个功能区：传送广场、商店、装备强化、港务任务、试炼入口。
## 传送接入 scene_portal，商店、强化和任务区提供可交互的服务入口。
## 分区用 zone_marker 登记（Label3D+地面光圈+Marker3D，默认隐藏，show_layout_markers 显示）。
## 尺度：活动区 64x40 米（x ±32 / z -28~12），水岸线 z=12，两座 L 形木码头伸入海中。
## 重新执行会整体覆盖 harbor.tscn；场景接口（根脚本、Player、Camera3D、harbor_ripples 组）保持不变。

const Catalog := preload("res://tools/preset_catalog.gd")
const OUT_PATH := "res://scenes/world/harbor.tscn"
const PLAYER_PATH := "res://player.tscn"
const LEVEL_SCRIPT := "res://scripts/world/harbor.gd"

const QUAY := Rect2(-42, -32, 84, 44)          # 港口陆地基座（x,z 平面）
const WALK := Rect2(-41, -31, 82, 43)          # 活动范围与地面基座对齐，只内收一个墙厚；屏障围在城墙内侧
const SHORE_Z := 12.0                          # 水岸线：陆地向海一侧的边界
## 港口机位：16° 俯角、正面视角、48 米距离与 18° FOV，长焦压缩透视形成平铺舞台感。
const CAM_PITCH := 16.0
const CAM_YAW := 0.0
const CAM_DISTANCE := 48.1
const CAM_FOV := 18.0
## 木码头是 L 形平台：甲板面在模型原点上方 3.10 米，下沉后甲板与石板街齐平。
## 实测平面以模型原点为界：北半幅是 16.29x6.5 的主段（贴岸），南半幅是 6.3x6.5 的支段（伸海，东侧留缺口）。
const PIER_SPAN := Vector2(16.29, 6.5)
const PIER_LEG := Vector2(6.3, 6.5)
const PIER_LEG_X := -7.8                       # 支段相对码头原点的西沿
const PIER_DROP := -3.10                       # 下沉量：甲板顶面落在 y=0
const PIER_CENTERS := [0.0, 22.0]              # 两座 L 形码头的中轴 x
const PIER_AT_Z_LIMIT := SHORE_Z + PIER_SPAN.y + PIER_LEG.y + 0.5   # 码头支段端头：玩家能走到的南界

var map: Node3D
var rng := RandomNumberGenerator.new()
var stone: ShaderMaterial
var sea_mat: ShaderMaterial

func _initialize() -> void:
	call_deferred("build")

# ---------------------------------------------------------------- 基础构件

func material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if emission > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

func slab(label: String, at: Vector3, size: Vector3, mat: Material, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = at
	map.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		mesh.add_child(body)
		var collision := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		collision.shape = bounds
		body.add_child(collision)
	return mesh

func barrier(at: Vector3, size: Vector3, label: String = "Boundary") -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = at
	map.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

## 不显示网格的实心台面；用于把素材甲板/台阶对齐成可站立高度。
func platform(label: String, at: Vector3, size: Vector3) -> void:
	barrier(at, size, label)

## 相机相对焦点的偏移：按俯角与侧转旋出，正交投影下决定取景中心。
func camera_offset() -> Vector3:
	return Basis.from_euler(Vector3(deg_to_rad(-CAM_PITCH), deg_to_rad(CAM_YAW), 0.0)) * Vector3(0, 0, CAM_DISTANCE)

# ---------------------------------------------------------------- 素材节点

## 放置一个共享库预设。overrides 直接写进 HD2DAsset 的覆盖字段（例如关掉/替换碰撞）。
func prop(title: String, at: Vector3, yaw_deg: float = 0.0, size: float = 1.0, overrides: Dictionary = {}) -> HD2DProp:
	var asset: HD2DAsset = Catalog.asset(title)
	if asset == null:
		return null
	var node := HD2DProp.new()
	node.name = title
	if not overrides.is_empty():
		node.asset_overrides = overrides
	node.asset = asset
	node.position = at
	node.rotation_degrees = Vector3(0, yaw_deg, 0)
	node.scale = Vector3.ONE * size
	map.add_child(node)
	return node

## 功能分区标记：Marker3D（登记 kind/位置）+ 地面光圈 + 头顶大字。与科波尔山一样，
## 默认隐藏，根节点打开 show_layout_markers 后显示，配合分工区审阅布局。
func zone_marker(marker_name: String, at: Vector3, kind: String, label: String, color: Color, disc_radius := 3.0) -> void:
	var marker := Marker3D.new()
	marker.name = marker_name
	marker.position = at
	marker.set_meta("kind", kind)
	marker.add_to_group("harbor_zone_marker", true)
	map.add_child(marker)
	var disc := MeshInstance3D.new()
	disc.name = marker_name + "_Disc"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = disc_radius
	cylinder.bottom_radius = disc_radius
	cylinder.height = 0.02
	disc.mesh = cylinder
	disc.material_override = mark_material(color, 0.24)
	disc.position = at + Vector3(0, 0.045, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.add_to_group("harbor_zone_marker", true)
	disc.visible = false
	map.add_child(disc)
	var text := Label3D.new()
	text.name = marker_name + "_Label"
	text.text = label
	text.position = at + Vector3(0, 2.6, 0)
	text.font_size = 64
	text.pixel_size = 0.011
	text.outline_size = 24
	text.modulate = color
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	text.no_depth_test = true
	text.add_to_group("harbor_zone_marker", true)
	text.visible = false
	map.add_child(text)

## 分区光圈/地面提示用的半透明无光材质。
func mark_material(color: Color, alpha := 0.24) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

## 用素材自带碰撞，但换成按包围盒生成的盒体，避免复杂三角网模型带来的开销。
func prop_with_box(title: String, at: Vector3, yaw_deg: float = 0.0, size_scale: float = 1.0, box: Vector3 = Vector3.ZERO) -> HD2DProp:
	var asset: HD2DAsset = Catalog.asset(title)
	if asset == null:
		return null
	var footprint := box
	if footprint == Vector3.ZERO:
		var parts := asset.mesh_parts()
		if parts.is_empty():
			return null
		footprint = parts[0].mesh.get_aabb().size
	footprint *= size_scale
	return prop(title, at, yaw_deg, size_scale, {
		"static_collision": true,
		"collision_mode": 1,
		"collision_size": footprint,
		"collision_offset": Vector3(0, footprint.y * 0.5, 0),
	})

func scatter(holder: HD2DFoliage, title: String, area: Rect2, count: int, scale_range: Vector2, lift: float = 0.02, avoid: Rect2 = Rect2()) -> void:
	var asset: HD2DAsset = Catalog.asset(title)
	if asset == null:
		return
	for i in count:
		var at := Vector3(rng.randf_range(area.position.x, area.end.x), lift, rng.randf_range(area.position.y, area.end.y))
		if avoid.has_area() and avoid.has_point(Vector2(at.x, at.z)):
			continue
		holder.records.append({
			"asset": asset,
			"position": at,
			"yaw": deg_to_rad(rng.randf_range(0, 360)),
			"scale": rng.randf_range(scale_range.x, scale_range.y),
			"asset_overrides": {"static_collision": false},
		})

func own(node: Node) -> void:
	for child in node.get_children():
		child.owner = map
		own(child)

# ---------------------------------------------------------------- 组装

func build() -> void:
	rng.seed = 617
	map = Node3D.new()
	map.name = "GreyTideHarbor"
	map.set_script(load(LEVEL_SCRIPT))
	stone = ShaderMaterial.new()
	stone.shader = preload("res://shaders/harbor_paving.gdshader")
	sea_mat = ShaderMaterial.new()
	sea_mat.shader = preload("res://shaders/harbor_water.gdshader")
	build_ground()
	build_piers()
	build_zones()
	build_street()
	build_walls()
	build_water()
	build_actors()
	preload("res://tools/harbor_lighting.gd").build(self)
	own(map)
	var packed := PackedScene.new()
	var result := packed.pack(map)
	if result == OK:
		result = ResourceSaver.save(packed, OUT_PATH)
	print("HARBOR_BUILD: ", result)
	map.free()
	quit(result)

func build_ground() -> void:
	slab("Sea", Vector3(QUAY.get_center().x, -0.72, 10), Vector3(280, 0.15, 280), sea_mat)
	# 陆地基座：南沿齐水，其余方向延伸出去做远处的山石与城门地基。
	slab("QuayFoundation", Vector3(QUAY.get_center().x, -0.34, QUAY.get_center().y), Vector3(QUAY.size.x, 0.68, QUAY.size.y), stone, true)
	# 地面碎石点缀已清空，只留程序化石板街。
	var road := stone.duplicate() as ShaderMaterial
	road.set_shader_parameter("stone_color", Color("56656c"))
	road.set_shader_parameter("tile_scale", 0.85)
	var border := material(Color("7f8580"))
	slab("MainStreet", Vector3(0, 0.012, -6), Vector3(6, 0.018, 36), road)
	for x in [-3.1, 3.1]:
		slab("StreetInlay", Vector3(x, 0.025, -6), Vector3(0.12, 0.015, 36), border)
	for z in [-9.0, 1.0]:
		slab("ServiceLane", Vector3(2, 0.03, z), Vector3(32, 0.018, 3.4), road)
		for dz in [-1.8, 1.8]:
			slab("LaneInlay", Vector3(2, 0.042, z + dz), Vector3(32, 0.012, 0.1), border)

## 两座 L 形木码头：主段贴岸、支段伸海；甲板与石板街齐平，三面拦水。
func build_piers() -> void:
	for center_x in PIER_CENTERS:
		make_pier(float(center_x))

func make_pier(center_x: float) -> void:
	var tag := "Pier%d" % int(center_x)
	var origin := Vector3(center_x, PIER_DROP, SHORE_Z + PIER_SPAN.y)
	prop("SM_JN_matou", origin, 0.0, 1.0, {"static_collision": false})
	var half_x := PIER_SPAN.x * 0.5
	var band_north := SHORE_Z
	var band_south := SHORE_Z + PIER_SPAN.y
	var sea_end := band_south + PIER_LEG.y
	platform("%sDeck" % tag, Vector3(center_x, -0.16, (band_north + band_south) * 0.5), Vector3(PIER_SPAN.x - 0.4, 0.32, PIER_SPAN.y))
	var leg_center_x := center_x + PIER_LEG_X + PIER_LEG.x * 0.5
	platform("%sLegDeck" % tag, Vector3(leg_center_x, -0.16, band_south + PIER_LEG.y * 0.5), Vector3(PIER_LEG.x, 0.32, PIER_LEG.y))
	# 沿甲板外沿拦水：靠岸那一边留口，玩家从石板街直接走上码头。
	var leg_east := center_x + PIER_LEG_X + PIER_LEG.x
	barrier(Vector3(center_x + PIER_LEG_X - 0.2, 1.2, (band_north + sea_end) * 0.5), Vector3(0.4, 3.6, sea_end - band_north), "%sRailWest" % tag)
	barrier(Vector3(center_x + half_x + 0.2, 1.2, (band_north + band_south) * 0.5), Vector3(0.4, 3.6, PIER_SPAN.y), "%sRailEast" % tag)
	barrier(Vector3((leg_east + center_x + half_x) * 0.5, 1.2, band_south), Vector3(center_x + half_x - leg_east, 3.6, 0.4), "%sNotchRail" % tag)
	barrier(Vector3(leg_east + 0.2, 1.2, band_south + PIER_LEG.y * 0.5), Vector3(0.4, 3.6, PIER_LEG.y), "%sLegRailEast" % tag)
	barrier(Vector3((center_x + PIER_LEG_X + leg_east) * 0.5, 1.2, sea_end), Vector3(PIER_LEG.x, 3.6, 0.4), "%sRailSouth" % tag)
	# 码头主段上的系船柱
	for offset in [Vector3(PIER_SPAN.x * 0.32, 0, 0), Vector3(-PIER_SPAN.x * 0.32, 0, 0)]:
		prop_with_box("SM_Licheng_shizhuzi001", Vector3(center_x + offset.x, 0, band_north + 2.2))
	# 泊船：小船分列码头两侧，渔船锚在外海。
	var moorings := [
		{"title": "SM_JN_xiaochuan001", "at": Vector3(center_x - 13.2, -0.72, band_north + 3.0), "yaw": 96.0},
		{"title": "SM_JN_xiaochuan002", "at": Vector3(center_x - 14.4, -0.72, band_north + 9.4), "yaw": 84.0},
		{"title": "SM_JN_xiaochuan003", "at": Vector3(center_x + 12.4, -0.72, band_north + 2.6), "yaw": -92.0},
		{"title": "SM_JN_xiaochuan004", "at": Vector3(center_x + 14.6, -0.72, band_north + 8.6), "yaw": -78.0},
	]
	for boat in moorings:
		prop(str(boat["title"]), boat["at"], float(boat["yaw"]))

func build_zones() -> void:
	preload("res://tools/harbor_zones.gd").build(self)

func build_street() -> void:
	# 地面摆件已清空（2026-09-19）：货箱、竹棚、渔网、系船柱、石灯与石灯笼全部移除，场地留空待重新布景。
	# 沿水岸的渔网、系船柱与石灯已清空。
	pass

func build_walls() -> void:
	# 一圈围墙收住场地边界，布局见 tools/harbor_walls.gd：内陆三面 6 米中墙、
	# 临水岸墙 3.26 米矮墙，北墙在城门处断开，南墙在两座码头贴岸段断开。
	# 墙体不生成碰撞，边界仍由 build_actors() 的隐形屏障负责。
	# 原压在边界外的山石已移除，围墙统一收口。
	# 2026-09-19：街道树、大树、松柏、树池与岸线草丛灌木全部移除，港口暂不设植被；
	# 重新植绿时补回，并同步更新 docs/HARBOR_MAP.md。
	map.add_child(preload("res://tools/harbor_walls.gd").make_node())

func build_water() -> void:
	# 波纹与闪光统一在海面 shader 内生成，避免 D3D12 实例闪光异常。
	var breakwater_mat := material(Color("354c59"))
	for i in 10:
		slab("DistantBreakwater", Vector3(-36 + i * 8, rng.randf_range(0.4, 1.8), 46), Vector3(6, 5, 4), breakwater_mat)

func build_actors() -> void:
	# 活动范围屏障：西/东/北三面不可见墙 + 水岸线（两个码头开口留空）。
	barrier(Vector3(WALK.position.x - 0.3, 1.0, WALK.get_center().y), Vector3(0.6, 4, WALK.size.y), "WestBoundary")
	barrier(Vector3(WALK.end.x + 0.3, 1.0, WALK.get_center().y), Vector3(0.6, 4, WALK.size.y), "EastBoundary")
	barrier(Vector3(0, 1.0, WALK.position.y - 0.3), Vector3(WALK.size.x, 4, 0.6), "NorthBoundary")
	# 水岸：主码头两侧 → 主码头与东码头之间 → 东码头以东，各拦一段。
	barrier(Vector3(-20.1, 1.0, SHORE_Z + 0.2), Vector3(23.8, 4, 0.6), "ShoreBoundaryWest")
	barrier(Vector3(11.0, 1.0, SHORE_Z + 0.2), Vector3(5.6, 4, 0.6), "ShoreBoundaryMiddle")
	barrier(Vector3(31.2, 1.0, SHORE_Z + 0.2), Vector3(2.0, 4, 0.6), "ShoreBoundaryEast")
	var player := load(PLAYER_PATH).instantiate() as CharacterBody3D
	player.name = "Player"
	# 出生在中央主街，左右可见商店与强化，北行传送，南行任务与码头。
	player.position = Vector3(0, 0, -12.0)
	# 玩家活动范围：与活动区一致，z 上限放到码头支段端头（z=25），否则走上码头会被拉回来。
	player.set("bounds_x", WALK.end.x)
	player.set("bounds_z", Vector2(WALK.position.y, PIER_AT_Z_LIMIT))
	map.add_child(player)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.position = camera_offset()
	camera.rotation_degrees = Vector3(-CAM_PITCH, CAM_YAW, 0)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = CAM_FOV
	camera.current = true
	var lens := CameraAttributesPractical.new()
	lens.dof_blur_far_enabled = true
	lens.dof_blur_far_distance = 68.5
	lens.dof_blur_far_transition = 23.3
	lens.dof_blur_amount = 0.10
	lens.dof_blur_near_enabled = true
	lens.dof_blur_near_distance = 37.9
	lens.dof_blur_near_transition = 11.7
	camera.attributes = lens
	map.add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.name = "EveningSun"
	sun.rotation_degrees = Vector3(-22, -48, 0)
	sun.light_color = Color("ffca94")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	map.add_child(sun)
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	var env := world.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("516975")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("7798bd")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.75
	env.fog_enabled = true
	env.fog_light_color = Color("778f9d")
	env.fog_density = 0.0015
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.5
	env.ssil_enabled = true
	env.ssil_intensity = 0.65
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.005
	env.volumetric_fog_albedo = Color("aebfce")
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.25
	map.add_child(world)







