extends SceneTree
## 科尔波山场景重建脚本：地形、刷怪点、传送门、波次与 BOSS 流程沿用原白盒布局，
## 树木 / 岩石 / 边界山壁 / 地被改用 HD-2D 共享素材库预设（tools/import_presets.gd 入库）。
## 生成：scenes/world/colpo_forest_outer.tscn（山林外围）、scenes/world/colpo_forest_clearing.tscn（林间决战空地）
## 不含敌人实例、波次推进、陷阱与传送逻辑，只负责空间与美术。
## 重新执行会整体覆盖这两个 .tscn，手工改过场景后勿直接重跑。

const Catalog := preload("res://tools/preset_catalog.gd")
const CameraStyle := preload("res://scripts/world/jungle_camera_style.gd")
const LEVEL_SCRIPT := "res://scripts/world/colpo_level.gd"
const PORTAL_SCRIPT := "res://scripts/world/scene_portal.gd"
const WAVE_SCRIPT := "res://scripts/world/wave_spawner.gd"
const BOSS_SCRIPT := "res://scripts/world/boss_director.gd"
const LEVEL_SELECT_PATH := "res://scenes/main/level_select.tscn"
const OUTER_PATH := "res://scenes/world/colpo_forest_outer.tscn"
const CLEARING_PATH := "res://scenes/world/colpo_forest_clearing.tscn"

## 固定偏航与贴片朝向一致；镜头取景由 CameraStyle 统一配置。
const CAM_YAW := CameraStyle.YAW

## 空间放大系数：场景按白盒布局等比放大，掩体与树木尺寸保持不变，只拉开活动范围。
## 位置统一走 scaled()，尺寸参数由各自函数决定（墙体拉长、掩体不变、树不变）。
const SCALE := 2.0

func scaled(at: Vector3) -> Vector3:
	return Vector3(at.x * SCALE, at.y, at.z * SCALE)

func scaled_range(range_value: Vector2) -> Vector2:
	return range_value * SCALE

## 素材池：常用乔木 / 大乔木 / 掩体岩石 / 灌木 / 竹丛 / 地被。
const TREE_POOL := ["SM_1dashu001_LODs", "SM_1dashu002_LODs"]
const TREE_POOL_BIG := ["SM_1dashu002_LODs"]
const ROCK_POOL := ["SM_XYNJiangnan006", "SM_XYNJiangnan012", "SM_XYNJiangnan016"]
const CLIFF_POOL := ["SM_Jiangnan_xuanya001", "SM_Jiangnan_xuanya002", "SM_Jiangnan_xuanya003", "SM_Jiangnan_xuanya005", "SM_Jiangnan_xuanya007"]
const SHRUB_POOL := ["SM_NJ_Yvlinzhiwu001"]
const GROUND_POOL := ["SM_NJ_Yvlinzhiwu002", "SM_NJ_Yvlinzhiwu003"]
const ART_DIR := "res://assets/environments/jungle"
const ASSET_LABELS := {
	"SM_1dashu001_LODs": "阔叶乔木 A", "SM_1dashu002_LODs": "阔叶乔木 B",
	"SM_NJ_Jvqingshu001": "古树地标", "SM_NJ_Yvlinzhiwu001": "林下蕨丛（原始宽度 11m）",
	"SM_NJ_Yvlinzhiwu002": "低矮地被", "SM_NJ_Yvlinzhiwu003": "卷叶蕨",
	"SM_XYNJiangnan006": "苔岩 A", "SM_XYNJiangnan012": "苔岩 B", "SM_XYNJiangnan016": "苔岩 C",
	"SM_Jiangnan_xuanya001": "林缘山壁 A", "SM_Jiangnan_xuanya002": "林缘山壁 B",
	"SM_Jiangnan_xuanya003": "林缘山壁 C", "SM_Jiangnan_xuanya005": "林缘山壁 D",
	"SM_Jiangnan_xuanya007": "林缘山壁 E", "SM_kushuicun_pofangzi002": "废弃林间木屋",
	"SM_NJ_Shitoudui001": "碎石堆（备用）",
}
var curated: Dictionary = {}

var map: Node3D
var rng := RandomNumberGenerator.new()
var counters := {}
var ground_mat: ShaderMaterial
var bedrock_mat: StandardMaterial3D
var leaf_mat: StandardMaterial3D
var gravel_mat: StandardMaterial3D
var fade_materials: Dictionary = {}

## Scene-local art wrappers preserve the original workshop meshes and textures.
func prepare_library() -> void:
	DirAccess.make_dir_recursive_absolute(ART_DIR + "/props")
	var titles: Array = []
	for pool in [TREE_POOL, TREE_POOL_BIG, ROCK_POOL, CLIFF_POOL, SHRUB_POOL, GROUND_POOL, ["SM_NJ_Jvqingshu001", "SM_kushuicun_pofangzi002", "SM_NJ_Shitoudui001"]]:
		for title in pool:
			if not titles.has(title):
				titles.append(title)
	var library := HD2DAssetLibrary.new()
	for title in titles:
		var original: HD2DAsset = Catalog.asset(title)
		assert(original != null, "Missing jungle asset: " + title)
		var source: Node3D = original.source.instantiate()
		for child in source.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			for surface in mesh.mesh.get_surface_count():
				var original_mat := mesh.get_active_material(surface) as StandardMaterial3D
				if original_mat == null:
					continue
				var mat := original_mat.duplicate() as StandardMaterial3D
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
				mat.roughness = 0.95
				mat.metallic_specular = 0.08
				mat.albedo_color = Color("c4d5cc") if title in ROCK_POOL or title in CLIFF_POOL else Color("d5e2d6")
				mesh.set_surface_override_material(surface, mat)
		var packed := PackedScene.new()
		assert(packed.pack(source) == OK)
		var scene_path: String = ART_DIR + "/props/" + title + ".tscn"
		assert(ResourceSaver.save(packed, scene_path) == OK)
		source.free()
		var asset := original.duplicate() as HD2DAsset
		asset.title = ASSET_LABELS.get(title, title)
		asset.source = load(scene_path)
		asset.source_path = scene_path
		asset.category = "丛林 / " + ("乔木" if title in TREE_POOL or title == "SM_NJ_Jvqingshu001" else "地被" if title in GROUND_POOL or title in SHRUB_POOL else "建筑" if title == "SM_kushuicun_pofangzi002" else "山石")
		asset.library_entry_id = StringName("jungle-" + title)
		var asset_path: String = ART_DIR + "/props/" + title + ".tres"
		assert(ResourceSaver.save(asset, asset_path) == OK)
		curated[title] = load(asset_path)
		library.assets.append(curated[title])
	assert(ResourceSaver.save(library, ART_DIR + "/jungle_library.tres") == OK)

func jungle_asset(title: String) -> HD2DAsset:
	return curated[title] if curated.has(title) else Catalog.asset(title)

## A real HD2DStage exposes the curated categories to the workshop dock.
func build_palette() -> int:
	DirAccess.make_dir_recursive_absolute("res://scenes/workshop")
	var stage := HD2DStage.new()
	stage.name = "JunglePalette"
	stage.library = load(ART_DIR + "/jungle_library.tres")
	stage.sky_mode = 1
	stage.sky_color = Color("242f32")
	stage.ambient_color = Color("a6becb")
	stage.sun_color = Color("ffe8c7")
	stage.sun_energy = 1.1
	stage.fog_enabled = false
	map = stage
	var scenery := Node3D.new()
	scenery.name = "Scenery"
	stage.add_child(scenery)
	var foliage := HD2DFoliage.new()
	foliage.name = "Foliage"
	scenery.add_child(foliage)
	box("PaletteFloor", Vector3(10.5, -0.15, 10.5), Vector3(34, 0.3, 34), material(Color("424d45")))
	var i := 0
	for title in curated:
		var asset: HD2DAsset = curated[title]
		var parts := asset.mesh_parts()
		var bounds := AABB()
		var first := true
		for part in parts:
			var part_bounds: AABB = part.transform * part.mesh.get_aabb()
			bounds = part_bounds if first else bounds.merge(part_bounds)
			first = false
		var fit := minf(1.0, 5.5 / maxf(bounds.size.x, bounds.size.y))
		var prop := HD2DProp.new()
		prop.name = title
		prop.asset = asset
		prop.asset_overrides = {"static_collision": false}
		prop.position = Vector3((i % 4) * 7.0, 0, (i / 4) * 7.0)
		prop.rotation_degrees.y = CAM_YAW
		prop.scale = Vector3.ONE * fit
		scenery.add_child(prop)
		var label := Label3D.new()
		label.name = "AssetLabel_%02d" % i
		label.text = asset.title
		label.position = prop.position + Vector3(0, 0.3, 2.0)
		label.font_size = 36
		label.pixel_size = 0.014
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		stage.add_child(label)
		i += 1
	var camera := Camera3D.new()
	camera.name = "PaletteCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 32
	camera.rotation_degrees = Vector3(-43, 8, 0)
	camera.position = Vector3(10.5, 0, 10.5) + camera.basis * Vector3(0, 0, 45)
	camera.current = true
	stage.add_child(camera)
	return save_map("res://scenes/workshop/jungle_palette.tscn")

func forest_landmarks(clearing: bool) -> void:
	for side in [-1, 1]:
		tree(Vector3(side * 6.4, 0, 15.0), 0.11, false)
	if clearing:
		var ancient := preset_prop("SM_NJ_Jvqingshu001", Vector3(0, 0, -26), CAM_YAW, 1.55)
		ancient.name = "AncientTreeLandmark"
		for side in [-1, 1]:
			for z in [-8.0, -3.0, 2.5, 8.0]:
				tree(Vector3(side * 8.8, 0, z), 0.105)
			for x in [4.8, 7.2]:
				tree(Vector3(side * x, 0, -10.2), 0.11)
	else:
		var hut := preset_prop("SM_kushuicun_pofangzi002", Vector3(-16, 0, 14), 12, 0.65, {
			"static_collision": true, "collision_mode": 1,
			"collision_size": Vector3(7.4, 4.2, 5.5), "collision_offset": Vector3(0, 2.1, 0),
		})
		hut.name = "AbandonedForesterHut"
		for offset in [Vector3(-2.8, 0, 0.8), Vector3(2.6, 0, 1.5), Vector3(2.5, 0, -1.5)]:
			preset_prop("SM_NJ_Yvlinzhiwu001", hut.position + offset, CAM_YAW, 0.16)
	# Slow pollen above the playable lane, small enough to keep combat readable.
	var pollen := CPUParticles3D.new()
	pollen.name = "ForestPollen"
	pollen.amount = 36
	pollen.lifetime = 12.0
	pollen.preprocess = 12.0
	pollen.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	pollen.emission_box_extents = Vector3(12, 3, 22)
	pollen.position.y = 3
	pollen.direction = Vector3(1, -0.25, 0)
	pollen.spread = 30
	pollen.gravity = Vector3.ZERO
	pollen.initial_velocity_min = 0.10
	pollen.initial_velocity_max = 0.25
	pollen.scale_amount_min = 0.018
	pollen.scale_amount_max = 0.035
	var mote := SphereMesh.new()
	mote.radius = 0.5
	mote.height = 1.0
	mote.radial_segments = 4
	mote.rings = 2
	mote.material = material(Color("c9bd85"), 0.15)
	pollen.mesh = mote
	pollen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map.add_child(pollen)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	rng.seed = 517
	prepare_library()
	if build_palette() != OK:
		quit(1)
		return
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = load(ART_DIR + "/forest_floor.gdshader")
	bedrock_mat = material(Color("1b231a"))
	leaf_mat = material(Color("5c4a2c"))
	gravel_mat = material(Color("585e56"))
	var result := build_outer()
	result = maxi(result, build_clearing())
	if result != OK:
		quit(1)
		return
	print("COLPO_BUILD: PASS")
	quit(0)

# ---------------------------------------------------------------- 通用素材

func material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	if emission > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	return mat

## 同名节点在 Godot 里会被改写成 @Name@2，编辑器里不便阅读；这里统一加序号。
func _next(base: String) -> int:
	var count: int = int(counters.get(base, 0)) + 1
	counters[base] = count
	return count

func box(label: String, at: Vector3, size: Vector3, mat: Material, solid := false, group := "") -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = "%s_%03d" % [label, _next(label)]
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = at
	map.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.name = "Solid"
		mesh.add_child(body)
		var collision := CollisionShape3D.new()
		var bounds := BoxShape3D.new()
		bounds.size = size
		collision.shape = bounds
		body.add_child(collision)
		if group != "":
			body.add_to_group(group, true)
	return mesh

## 走不出去的地面基底：顶面固定在 y=0，与港口岸台一致。
func bedrock(size: Vector3) -> void:
	box("Bedrock", Vector3(0, -size.y * 0.5, 0), Vector3(size.x * SCALE, size.y, size.z * SCALE), bedrock_mat, true)

## 碎石枯叶地面：一整块地面板 + UV 重复，等效于 2.5 米一块贴图砖，但不产生上千个节点。
func tiled_floor(x_range: Vector2, z_range: Vector2, mat: ShaderMaterial) -> void:
	var width := maxf((x_range.y - x_range.x) * SCALE, 90.0)
	var depth := maxf((z_range.y - z_range.x) * SCALE, 102.0)
	var plane_mat := mat.duplicate() as ShaderMaterial
	plane_mat.set_shader_parameter("clearing", map.name == "ColpoForestClearing")
	box("ForestFloor", Vector3(0, 0.015, 0), Vector3(width, 0.03, depth), plane_mat)

## 边界山壁：视觉用共享库山石拼出连片山体，阻挡仍由不可见实体负责（保证挡人与挡弹可靠）。
func cliff(at: Vector3, size: Vector3) -> void:
	var spot := scaled(at)
	var span_size := Vector3(size.x * SCALE, size.y, size.z * SCALE)
	var body := StaticBody3D.new()
	body.name = "CliffBarrier_%03d" % _next("CliffBarrier")
	body.position = spot
	body.add_to_group("colpo_cliff", true)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = span_size
	collision.shape = shape
	collision.position = Vector3(0, size.y * 0.5, 0)
	body.add_child(collision)
	map.add_child(body)
	# 沿这一段边界铺山石：推到屏障之外，缩到 0.3~0.5 体量，形成场地背后的连片山体。
	var along_x := span_size.x >= span_size.z
	var span: float = span_size.x if along_x else span_size.z
	var outward := Vector3(spot.x, 0, spot.z).normalized()
	var blocks := maxi(2, roundi(span / 7.0))
	for i in blocks:
		var offset := -span * 0.5 + span * (float(i) + 0.5) / float(blocks) + rng.randf_range(-1.2, 1.2)
		var push := rng.randf_range(2.5, 5.5)
		var rock_spot := spot + outward * push + (Vector3(offset, 0, 0) if along_x else Vector3(0, 0, offset))
		placeholder_cliff(rock_spot)

func placeholder_cliff(at: Vector3) -> void:
	var title: String = CLIFF_POOL[rng.randi_range(0, CLIFF_POOL.size() - 1)]
	var node := preset_prop(title, at, rng.randf_range(0, 360), rng.randf_range(0.3, 0.5), {"static_collision": false})
	if node != null:
		node.add_to_group("colpo_cliff_visual", true)

## 不可见阻挡：边界需要挡人挡子弹，但不该在画面里遮住战斗区。
func barrier(at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Barrier_%03d" % _next("Barrier")
	body.position = at
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	body.add_to_group("colpo_boundary", true)
	map.add_child(body)

## 近景边界（镜头这一侧）：只用低矮碎石堆，高墙会把近处地面压到画面外。
## 阻挡高度取 1.8 米：足够挡住移动与子弹，又不会从镜头方向切断近处的视线。
func near_ledge(at: Vector3, size: Vector3) -> void:
	var spot := scaled(at)
	var length := size.x * SCALE
	barrier(spot + Vector3(0, 0.9, 0), Vector3(length, 1.8, size.z))
	var piles := maxi(2, roundi(length / 3.4))
	for i in piles:
		var offset := -length * 0.5 + length * (float(i) + 0.5) / float(piles)
		var node := preset_prop(ROCK_POOL[i % ROCK_POOL.size()], spot + Vector3(offset, -0.12, rng.randf_range(-0.7, 0.7)), rng.randf_range(0, 360), rng.randf_range(0.15, 0.28), {"static_collision": false})
		if node != null:
			node.add_to_group("colpo_boundary", true)

## 岩石掩体：实心可绕行，碰撞按白盒给定尺寸给盒体，保证战斗走位与原布局一致。
## 位置随场地放大，掩体尺寸保持不变，因此放大后场地更空、需要补掩体。
func rock(at: Vector3, size: Vector3, yaw := 0.0) -> void:
	var title: String = ROCK_POOL[rng.randi_range(0, ROCK_POOL.size() - 1)]
	var asset: HD2DAsset = jungle_asset(title)
	if asset == null:
		return
	var parts := asset.mesh_parts()
	var natural: Vector3 = parts[0].mesh.get_aabb().size if not parts.is_empty() else Vector3.ONE
	var fitted_scale := size / natural.max(Vector3.ONE * 0.2)
	var node := preset_prop(title, scaled(at), yaw + rng.randf_range(-22.0, 22.0), 1.0, {
		"static_collision": true,
		"collision_mode": 1,
		"collision_size": size / fitted_scale,
		"collision_offset": Vector3(0, size.y * 0.5, 0) / fitted_scale,
	})
	if node != null:
		node.scale = fitted_scale
		node.material_override = fade_material(title)
		node.add_to_group("colpo_rock", true)
		node.add_to_group("colpo_fade", true)

## 树木：用共享库乔木。树干给胶囊碰撞（挡人挡弹、可绕行），树冠不挡路。
func tree(at: Vector3, pixel_scale := 0.08, solid := true) -> void:
	if map.name == "ColpoForestOuter" and Vector2(at.x * SCALE + 16, at.z * SCALE - 14).length() < 4.5:
		return
	var title: String = TREE_POOL_BIG[rng.randi_range(0, TREE_POOL_BIG.size() - 1)] if rng.randf() < 0.3 else TREE_POOL[rng.randi_range(0, TREE_POOL.size() - 1)]
	var size := clampf(pixel_scale / 0.085, 0.78, 1.28)
	var overrides := {"static_collision": false}
	if solid:
		overrides = {
			"static_collision": true,
			"collision_mode": 2,
			"collision_size": Vector3(0.9, 3.0, 0.9) / size,
			"collision_offset": Vector3(0, 1.5 / size, 0),
		}
	var node := preset_prop(title, scaled(at), CAM_YAW + rng.randf_range(-7, 7), size, overrides)
	if node == null:
		return
	# 可混合材质：镜头与主角之间的树/灌木按透明度淡出，HD-2D 里主角永远不被前景吃掉。
	node.material_override = fade_material(title)
	node.add_to_group("colpo_fade", true)
	if solid:
		node.add_to_group("colpo_tree", true)

## 前景淡出要靠半透明：素材原本是 alpha scissor，这里复制一份可混合的材质给淡出用。
func fade_material(title: String) -> Material:
	if fade_materials.has(title):
		return fade_materials[title]
	var asset: HD2DAsset = jungle_asset(title)
	var probe: Node3D = asset.with_overrides({"static_collision": false}).make_node() if asset else null
	var source: Material = null
	if probe != null:
		for child in probe.find_children("*", "MeshInstance3D", true, false):
			var mesh_node := child as MeshInstance3D
			if mesh_node.mesh and mesh_node.mesh.get_surface_count() > 0 and mesh_node.get_active_material(0) != null:
				source = mesh_node.get_active_material(0)
				break
		probe.free()
	var mat: StandardMaterial3D = source.duplicate() as StandardMaterial3D if source is StandardMaterial3D else null
	if mat != null:
		# 深度预通道的 alpha 混合：淡出时叶子不会互相穿透，也不容易被排序插到主角前面。
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	fade_materials[title] = mat
	return mat

## 放置一个共享库预设节点。
func preset_prop(title: String, at: Vector3, yaw_deg := 0.0, size := 1.0, overrides: Dictionary = {}) -> HD2DProp:
	var asset: HD2DAsset = jungle_asset(title)
	if asset == null:
		return null
	var node := HD2DProp.new()
	node.name = "%s_%03d" % [title.trim_prefix("SM_"), _next(title)]
	if not overrides.is_empty():
		node.asset_overrides = overrides
	node.asset = asset
	node.position = at
	node.rotation_degrees = Vector3(0, yaw_deg, 0)
	node.scale = Vector3.ONE * size
	map.add_child(node)
	return node

## 地被散布：草、灌木、竹丛改成 MultiMesh，几百株也只有几个绘制批次。
func ground_cover(inner: Vector2, outer: Vector2, density: float) -> void:
	var holder := HD2DFoliage.new()
	holder.name = "GroundCover"
	holder.chunk_size = 14.0
	map.add_child(holder)
	var area := Rect2(-outer.x * SCALE, -outer.y * SCALE, outer.x * 2 * SCALE, outer.y * 2 * SCALE)
	scatter_cover(holder, GROUND_POOL, area, roundi(density * 170.0 * SCALE * SCALE), Vector2(0.85, 1.5), inner)
	# The fern source is 11 m wide: normalize it to 1.4–2.4 m clumps.
	scatter_cover(holder, SHRUB_POOL, area, roundi(density * 36.0 * SCALE * SCALE), Vector2(0.13, 0.22), inner)

func scatter_cover(holder: HD2DFoliage, pool: Array, area: Rect2, count: int, scale_range: Vector2, keep_clear: Vector2) -> void:
	var clear := scaled_range(keep_clear)
	for i in count:
		var at := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		# 战斗区中央留空：只铺外圈，免得地被糊住走位与镜头
		if absf(at.x) < clear.x and absf(at.y) < clear.y:
			continue
		if map.name == "ColpoForestOuter" and absf(at.x) < 3.4:
			continue
		if map.name == "ColpoForestClearing" and (at / Vector2(16.0, 19.5)).length() < 1.0:
			continue
		# Patchy understory, with gaps between clusters instead of uniform confetti.
		if sin(at.x * 0.65) + cos(at.y * 0.48) < -0.55:
			continue
		var title: String = pool[rng.randi_range(0, pool.size() - 1)]
		var asset: HD2DAsset = jungle_asset(title)
		if asset == null:
			continue
		holder.records.append({
			"asset": asset,
			"position": Vector3(at.x, 0.03, at.y),
			"yaw": deg_to_rad(CAM_YAW + rng.randf_range(-9, 9)),
			"scale": rng.randf_range(scale_range.x, scale_range.y),
			"asset_overrides": {"static_collision": false},
		})

## 外围背景密林：铺在边界山壁之外，让画面外侧仍是连片山林而不是空地。
## inner 为可玩区半宽（x, z），outer 为背景林外沿；近景中央留空，避免前景树挡住角色。
func backdrop_forest(inner: Vector2, outer: Vector2, step: float, keep_clear_x: float) -> void:
	var holder := HD2DFoliage.new()
	holder.name = "BackdropForest"
	holder.chunk_size = 16.0
	map.add_child(holder)
	var inner_scaled := scaled_range(inner)
	var outer_scaled := scaled_range(outer)
	var clear_scaled := keep_clear_x * SCALE
	var step_scaled := step * 1.5
	var x := -outer_scaled.x
	while x <= outer_scaled.x:
		var z := -outer_scaled.y
		while z <= outer_scaled.y:
			var at := Vector2(x + rng.randf_range(-0.9, 0.9), z + rng.randf_range(-0.9, 0.9))
			var inside: bool = absf(at.x) < inner_scaled.x and absf(at.y) < inner_scaled.y
			var foreground: bool = at.y > inner_scaled.y and absf(at.x) < clear_scaled
			if not inside and not foreground:
				var title: String = TREE_POOL_BIG[rng.randi_range(0, TREE_POOL_BIG.size() - 1)] if rng.randf() < 0.5 else TREE_POOL[rng.randi_range(0, TREE_POOL.size() - 1)]
				var asset: HD2DAsset = jungle_asset(title)
				if asset != null:
					holder.records.append({
						"asset": asset,
						"position": Vector3(at.x, 0, at.y),
						"yaw": deg_to_rad(CAM_YAW + rng.randf_range(-8, 8)),
						"scale": rng.randf_range(0.9, 1.5),
						"asset_overrides": {"static_collision": false},
					})
			z += step_scaled
		x += step_scaled

## 蜿蜒林间小路：按路径点插值密铺贴图砖，转向跟随每一段方向，放大后依然连贯。
func winding_path(points: Array) -> void:
	# Continuous dirt/moss transition is now rendered by forest_floor.gdshader.
	# Retain the route as authoring data for later path editing.
	map.set_meta("jungle_path", points)

## 碎石与枯叶：只做地面细节，无碰撞。
func scatter_debris(count: int, x_range: Vector2, z_range: Vector2) -> void:
	for i in roundi(count * SCALE):
		var mats := [leaf_mat, gravel_mat, leaf_mat]
		var at := Vector3(rng.randf_range(x_range.x * SCALE, x_range.y * SCALE), 0.043, rng.randf_range(z_range.x * SCALE, z_range.y * SCALE))
		var w := rng.randf_range(0.04, 0.13)
		var d := rng.randf_range(0.06, 0.19)
		box("Debris", at, Vector3(w, 0.025, d), mats[rng.randi_range(0, 2)]).rotation.y = rng.randf_range(0, PI)

func floor_disc(at: Vector3, radius: float, mat: Material) -> void:
	var disc := MeshInstance3D.new()
	disc.name = "FloorMark_%03d" % _next("FloorMark")
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 0.02
	disc.mesh = cylinder
	disc.material_override = mat
	disc.position = at + Vector3(0, 0.05, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.add_to_group("colpo_layout_marker", true)
	disc.visible = false
	map.add_child(disc)

func mark_material(color: Color, alpha := 0.34) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, alpha)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

## 刷怪点标记：空节点承载数据（kind / wave），地面色环 + 小字给白盒查看用。
func spawn_mark(node_name: String, at: Vector3, kind: String, wave: int, color: Color, text: String) -> void:
	var spot := scaled(at)
	var node := Marker3D.new()
	node.name = node_name
	node.position = spot
	node.set_meta("kind", kind)
	node.set_meta("wave", wave)
	node.add_to_group("colpo_spawn", true)
	map.add_child(node)
	floor_disc(spot, 0.85, mark_material(color))
	area_label(text, spot + Vector3(0, 2.3, 0), color.lightened(0.35), 34, 0.0072)

## 流程标记：传送门 / 准备区 / BOSS 出生点等，白盒阶段只登记位置与用途。
func flow_mark(node_name: String, at: Vector3, kind: String) -> Marker3D:
	var node := Marker3D.new()
	node.name = node_name
	node.position = scaled(at)
	node.set_meta("kind", kind)
	node.add_to_group("colpo_flow", true)
	map.add_child(node)
	return node

func area_label(text: String, at: Vector3, color: Color, font_size := 64, pixel_size := 0.011) -> void:
	var label := Label3D.new()
	label.name = "AreaLabel_%03d" % _next("AreaLabel")
	label.text = text
	label.position = at
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = 22
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.add_to_group("colpo_layout_marker", true)
	label.visible = false
	map.add_child(label)

## 传送门：两根立柱 + 一块发光门面，Area3D 挂 scene_portal.gd 负责「进圈提示 + V 交互切场景」。
func portal(node_name: String, at: Vector3, label_text: String, color: Color, target: String, prompt: String, requires_cleared: bool) -> void:
	var spot := scaled(at)
	var area := Area3D.new()
	area.name = node_name
	area.position = spot
	area.set_meta("kind", "portal")
	area.add_to_group("colpo_portal", true)
	map.add_child(area)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.6, 2.6, 1.4)
	collision.shape = shape
	area.add_child(collision)
	area.set_script(load(PORTAL_SCRIPT))
	area.set("target_scene", target)
	area.set("prompt_text", prompt)
	area.set("requires_cleared", requires_cleared)
	for side in [-1, 1]:
		box("PortalPillar", spot + Vector3(side * 2.4, 1.8, 0), Vector3(0.5, 3.6, 0.5), material(Color("25323a"), 0.25))
	var gate := box("PortalGate", spot + Vector3(0, 1.6, 0), Vector3(4.4, 3.2, 0.24), material(color, 2.2))
	gate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 52° 俯视下竖直门面只剩一条线：补地面光圈 + 竖直光柱，远处也能一眼看到
	floor_disc(spot, 2.4, mark_material(color, 0.3))
	var beam := box("PortalBeam", spot + Vector3(0, 4.5, 0), Vector3(1.5, 9.0, 1.5), beam_material(color))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.set_meta("phase", rng.randf_range(0.0, TAU))
	beam.set_meta("base_alpha", 0.12)
	beam.add_to_group("colpo_shaft", true)
	area_label(label_text, spot + Vector3(0, 2.8, 0), color, 52, 0.011)
	# Only destination labels belong in the normal game view.
	var destination := map.get_child(map.get_child_count() - 1) as Label3D
	destination.remove_from_group("colpo_layout_marker")
	destination.visible = true

## 传送门光柱材质：加色混合的低透明度柱体，跟场景光柱同一套呼吸逻辑。
func beam_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_color.a = 0.12
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_receive_shadows = true
	return mat

func camera_rig(arena := false) -> void:
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	CameraStyle.configure(camera, arena)
	map.set("camera_focus_bounds", CameraStyle.focus_bounds(arena))
	map.add_child(camera)

func sun_rig(direction: Vector3, color: Color, energy: float) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(direction.x, direction.y, 0)
	sun.light_color = color
	sun.light_energy = energy
	sun.shadow_enabled = true
	map.add_child(sun)

## 环境：渐变天空 + 体积雾 + 辉光 + 轻色调分级。
## 用 Sky 而不是纯色背景，远景才有地平线层次，不再是贴在后面的一块死色。
func environment(sky_top: Color, sky_horizon: Color, ambient: Color, fog: Color, fog_density: float) -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	var env := world.environment
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = sky_horizon
	sky_mat.ground_horizon_color = sky_horizon
	sky_mat.ground_bottom_color = fog.darkened(0.35)
	sky_mat.sun_angle_max = 26.0
	sky_mat.sun_curve = 0.08
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.22
	env.fog_enabled = true
	env.fog_light_color = fog
	env.fog_density = fog_density
	# 轻分级：HD-2D 的配色偏饱和偏硬，稍微推一点对比和饱和度更接近那种味道
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.88
	env.ssao_enabled = false
	env.ssao_radius = 1.2
	env.ssao_intensity = 0.8
	map.add_child(world)

## 丁达尔光柱：与太阳同向的细长半透明柱，加色混合，靠关卡脚本做缓慢呼吸。
## 教程里点名用的 LightRays 效果，这里是程序化版本，不引入额外美术资源。
func light_shafts(count: int, x_range: Vector2, z_range: Vector2, tint: Color, tilt: Vector3) -> void:
	for i in roundi(count * SCALE):
		var length := rng.randf_range(9.0, 15.0)
		var at := Vector3(rng.randf_range(x_range.x * SCALE, x_range.y * SCALE), 0, rng.randf_range(z_range.x * SCALE, z_range.y * SCALE))
		var shaft := MeshInstance3D.new()
		shaft.name = "LightShaft_%03d" % _next("LightShaft")
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(0.22, 0.5), length, rng.randf_range(0.22, 0.5))
		shaft.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.disable_receive_shadows = true
		# 加色混合很容易过曝：单根压到 3% 上下，叠起来才是"透进林间的光"
		mat.albedo_color.a = rng.randf_range(0.028, 0.055)
		shaft.material_override = mat
		shaft.rotation_degrees = tilt
		shaft.position = at + Vector3(0, length * 0.42, 0)
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		map.add_child(shaft)
		shaft.set_meta("base_alpha", mat.albedo_color.a)
		shaft.set_meta("phase", rng.randf_range(0.0, TAU))
		shaft.add_to_group("colpo_shaft", true)

func add_player(at: Vector3, bounds_x: float, bounds_z: Vector2) -> void:
	var spawn := flow_mark("PlayerSpawn", at, "player_spawn")
	area_label("出生点", spawn.position + Vector3(0, 2.3, 0), Color("a5dfff"), 40, 0.008)
	var player = load("res://player.tscn").instantiate()
	player.name = "Player"
	player.position = spawn.position
	# 玩家活动范围按放大后的场地写入，否则会被 P0 试炼的小场地限制拉回中央。
	player.set("bounds_x", bounds_x)
	player.set("bounds_z", bounds_z)
	map.add_child(player)

func new_level(scene_name: String, header: String, objective: String) -> void:
	counters.clear()
	map = Node3D.new()
	map.name = scene_name
	map.set_script(load(LEVEL_SCRIPT))
	map.set("header_text", header)
	map.set("objective_text", objective)

## 波次调度：读同层的刷怪点标记，逐波放怪并在清完后解锁传送门。
func wave_director() -> void:
	var node := Node3D.new()
	node.name = "WaveDirector"
	node.set_script(load(WAVE_SCRIPT))
	map.add_child(node)

## BOSS 关流程：开场剧情 → 准备阶段 → 巨虎登场 → 三阶段 → 结算。
func boss_director() -> void:
	var node := Node3D.new()
	node.name = "BossDirector"
	node.set_script(load(BOSS_SCRIPT))
	map.add_child(node)

func own(node: Node) -> void:
	for child in node.get_children():
		child.owner = map
		own(child)

func save_map(path: String) -> int:
	own(map)
	var packed := PackedScene.new()
	var result := packed.pack(map)
	if result == OK:
		result = ResourceSaver.save(packed, path)
	print("COLPO_BUILD: %s -> %d" % [path, result])
	map.free()
	return result

# ---------------------------------------------------------------- 场景 A：山林外围

func build_outer() -> int:
	rng.seed = 517
	new_level("ColpoForestOuter", "科尔波山 / 山林外围", "小怪热身 · 3 波递进 · 清场后传送至林间空地")
	# 空间比决战空地更窄：左右岩壁各推进到 ±10.3，中央只留一条蜿蜒通路
	bedrock(Vector3(46, 0.5, 52))
	tiled_floor(Vector2(-11.4, 11.4), Vector2(-13.0, 13.0), ground_mat)
	scatter_debris(80, Vector2(-9.2, 9.2), Vector2(-10.8, 10.8))
	winding_path([
		Vector2(0, 10.8), Vector2(0.8, 9.6), Vector2(1.4, 8.4), Vector2(0.8, 7.2), Vector2(-0.2, 6.0),
		Vector2(-0.8, 4.8), Vector2(-0.4, 3.6), Vector2(0, 2.6), Vector2(0.6, 1.6), Vector2(0.2, 0.4),
		Vector2(-0.4, -0.8), Vector2(-0.9, -2.0), Vector2(-0.4, -3.2), Vector2(0.2, -4.4), Vector2(0.9, -5.6),
		Vector2(1.1, -6.8), Vector2(0.6, -8.0), Vector2(0, -9.2), Vector2(-0.2, -9.9), Vector2(0, -10.4),
	])
	# 四周围合：远端与两侧用高岩壁，镜头近端（南）只用低矮岩坎，避免遮住近处战斗区
	cliff(Vector3(0, 0, -11.8), Vector3(24, 5.0, 1.8))
	cliff(Vector3(-10.3, 0, 0), Vector3(1.8, 5.0, 24))
	cliff(Vector3(10.3, 0, 0), Vector3(1.8, 5.0, 24))
	near_ledge(Vector3(0, 0, 11.8), Vector3(24, 0.7, 1.8))
	# 树木密集带：左右两侧连片密林，把空间切成一条零碎通道（步进同样按放大后的场地加密）
	for side in [-1.0, 1.0]:
		var z := -10.6
		while z <= 10.6:
			tree(Vector3(side * rng.randf_range(5.9, 9.1), 0, z + rng.randf_range(-0.5, 0.5)), rng.randf_range(0.065, 0.095))
			z += rng.randf_range(1.1, 1.6)
	# 场地放大后补的掩体：把口袋之间再度切开，保持绕行拉扯的密度（位置同样按 SCALE 换算）
	rock(Vector3(-4.2, 0, 3.2), Vector3(2.2, 1.6, 2.0), 0.4)
	rock(Vector3(4.6, 0, -0.6), Vector3(2.4, 1.7, 2.2), -0.3)
	rock(Vector3(-3.4, 0, -7.4), Vector3(2.0, 1.4, 1.8), 0.2)
	rock(Vector3(3.2, 0, 7.8), Vector3(1.8, 1.3, 1.7), -0.5)
	rock(Vector3(-6.4, 0, -3.0), Vector3(2.6, 1.9, 2.4), 0.15)
	rock(Vector3(6.2, 0, -10.2), Vector3(2.2, 1.6, 2.0), -0.2)
	# 入口段
	rock(Vector3(-6.2, 0, 9.4), Vector3(2.4, 1.8, 2.0), 0.3)
	rock(Vector3(6.4, 0, 9.6), Vector3(2.2, 1.6, 2.0), -0.4)
	tree(Vector3(-4.6, 0, 10.6), 0.088)
	tree(Vector3(4.4, 0, 10.4), 0.082)
	area_label("入口 · 进入科尔波山山林外围", Vector3(0, 4.3, 21.2), Color("a5dfff"), 46, 0.009)
	# 波次 1 口袋：2 只野狼（能量型）
	rock(Vector3(-4.8, 0, 6.0), Vector3(2.8, 1.7, 2.2), 0.2)
	rock(Vector3(4.4, 0, 5.2), Vector3(2.0, 1.5, 1.8), 0.5)
	rock(Vector3(-2.4, 0, 7.6), Vector3(1.5, 1.0, 1.4))
	tree(Vector3(-4.6, 0, 4.2), 0.075)
	spawn_mark("Wave1_Wolf_01", Vector3(-2.8, 0, 4.6), "wolf", 1, Color("e08a5a"), "狼1")
	spawn_mark("Wave1_Wolf_02", Vector3(3.0, 0, 6.6), "wolf", 1, Color("e08a5a"), "狼2")
	area_label("波次 1 · 2 只野狼（能量型）", Vector3(0, 3.2, 11.2), Color("ffd9a0"), 52, 0.009)
	# 隘口 1：两段岩体夹出约 3.6 米通路
	rock(Vector3(-3.8, 0, 2.5), Vector3(4.0, 2.2, 2.6))
	rock(Vector3(3.8, 0, 2.5), Vector3(4.0, 2.2, 2.6))
	# 波次 2 口袋：野猪 + 野狼，偏置立柱用来绕柱拉扯（不挡主路）
	rock(Vector3(-2.8, 0, -0.4), Vector3(2.4, 1.8, 2.4))
	rock(Vector3(-6.8, 0, 0.6), Vector3(2.4, 1.7, 2.0), -0.3)
	rock(Vector3(6.6, 0, -1.0), Vector3(2.4, 1.7, 2.0), 0.3)
	tree(Vector3(-5.4, 0, -1.6), 0.078)
	tree(Vector3(5.2, 0, 0.6), 0.07)
	spawn_mark("Wave2_Boar_01", Vector3(-4.8, 0, -1.2), "boar", 2, Color("c96f4a"), "猪")
	spawn_mark("Wave2_Wolf_01", Vector3(5.2, 0, 1.0), "wolf", 2, Color("e08a5a"), "狼1")
	spawn_mark("Wave2_Wolf_02", Vector3(3.2, 0, -1.8), "wolf", 2, Color("e08a5a"), "狼2")
	area_label("波次 2 · 野猪 + 野狼", Vector3(0, 3.2, 0.4), Color("ffd9a0"), 52, 0.009)
	# 隘口 2
	rock(Vector3(-4.6, 0, -4.4), Vector3(3.6, 2.2, 2.6), 0.2)
	rock(Vector3(4.8, 0, -4.4), Vector3(3.6, 2.2, 2.6), -0.2)
	# 波次 3 口袋：野兽 + 无能量肉体傀儡混合小队
	rock(Vector3(-6.6, 0, -8.0), Vector3(3.0, 2.2, 2.6), 0.1)
	rock(Vector3(6.4, 0, -8.8), Vector3(2.8, 2.0, 2.4), -0.1)
	rock(Vector3(-1.6, 0, -6.4), Vector3(1.8, 1.2, 1.6), 0.3)
	rock(Vector3(3.4, 0, -6.2), Vector3(1.7, 1.2, 1.6), -0.2)
	tree(Vector3(-8.4, 0, -5.6), 0.085)
	tree(Vector3(7.8, 0, -5.8), 0.09)
	spawn_mark("Wave3_Wolf_01", Vector3(-6.2, 0, -6.4), "wolf", 3, Color("e08a5a"), "狼1")
	spawn_mark("Wave3_Boar_01", Vector3(-2.8, 0, -9.4), "boar", 3, Color("c96f4a"), "猪")
	spawn_mark("Wave3_Wolf_02", Vector3(6.0, 0, -7.0), "wolf", 3, Color("e08a5a"), "狼2")
	spawn_mark("Wave3_Golem_01", Vector3(-4.6, 0, -10.2), "golem", 3, Color("9a8fb5"), "傀儡1")
	spawn_mark("Wave3_Golem_02", Vector3(4.4, 0, -10.4), "golem", 3, Color("9a8fb5"), "傀儡2")
	area_label("波次 3 · 野兽 + 无能量肉体傀儡（青钢影真实伤害无效）", Vector3(0, 3.4, -14.4), Color("c9b3ff"), 52, 0.009)
	# 清场出口：清光外围敌人后按 V 传送到林间决战空地
	portal("ExitPortal", Vector3(0, 0, -10.4), "传送 → 林间决战空地", Color("63d6ff"), CLEARING_PATH, "前往林间决战空地", true)
	wave_director()
	# 环境与镜头
	ground_cover(Vector2(2.6, 2.6), Vector2(13.0, 13.6), 0.7)
	backdrop_forest(Vector2(11.2, 12.7), Vector2(17.4, 17.4), 3.2, 9.0)
	forest_landmarks(false)
	sun_rig(Vector3(-48, -28, 0), Color("ffe8c7"), 1.45)
	light_shafts(2, Vector2(-8.0, 8.0), Vector2(-10.0, -4.0), Color(1.0, 0.94, 0.72), Vector3(-38, -28, 0))
	environment(Color("1b3039"), Color("7d9992"), Color("9cbbce"), Color("547e7b"), 0.0025)
	camera_rig(false)
	add_player(Vector3(0, 0, 9.6), 20.6, Vector2(-23.6, 23.6))
	return save_map(OUTER_PATH)

# ---------------------------------------------------------------- 场景 B：林间决战空地

func build_clearing() -> int:
	rng.seed = 923
	new_level("ColpoForestClearing", "科尔波山 / 林间决战空地", "BOSS 决战 · 15 秒准备 · 预埋炼金炸弹")
	# 更大的开阔空间，中间刻意留空，只靠四周边界与掩体构成战斗区
	bedrock(Vector3(56, 0.5, 56))
	tiled_floor(Vector2(-13.4, 13.4), Vector2(-13.4, 13.4), ground_mat)
	scatter_debris(90, Vector2(-11.6, 11.6), Vector2(-11.6, 11.6))
	cliff(Vector3(0, 0, -12.2), Vector3(28, 6.5, 1.8))
	cliff(Vector3(-12.4, 0, 0), Vector3(1.8, 6.5, 26))
	cliff(Vector3(12.4, 0, 0), Vector3(1.8, 6.5, 26))
	near_ledge(Vector3(0, 0, 12.2), Vector3(28, 0.7, 1.8))
	# 密林只集中在四周边界，两圈树围出中间的大片空地；南北各留一个 6 米宽的进出缺口
	for side in [-1.0, 1.0]:
		var t := -11.0
		while t <= 11.0:
			if absf(t) > 3.0:
				tree(Vector3(t, 0, side * 10.7), rng.randf_range(0.07, 0.098))
			tree(Vector3(side * 10.7, 0, t), rng.randf_range(0.07, 0.098))
			t += rng.randf_range(1.3, 1.8)
		t = -11.4
		while t <= 11.4:
			if absf(t) > 3.0:
				tree(Vector3(t, 0, side * 11.7), rng.randf_range(0.078, 0.108))
			tree(Vector3(side * 11.7, 0, t), rng.randf_range(0.078, 0.108))
			t += rng.randf_range(1.7, 2.3)
	# 大块岩石掩体：躲巨虎扑击用，全部在离中央 8 米以外
	rock(Vector3(-8.2, 0, 6.4), Vector3(3.4, 2.4, 3.0), 0.2)
	rock(Vector3(8.2, 0, 6.4), Vector3(3.4, 2.4, 3.0), -0.25)
	rock(Vector3(-8.6, 0, -4.8), Vector3(3.6, 2.6, 3.2), 0.15)
	rock(Vector3(8.6, 0, -4.8), Vector3(3.6, 2.6, 3.2), -0.15)
	rock(Vector3(-4.4, 0, -9.0), Vector3(2.8, 2.0, 2.6), 0.3)
	rock(Vector3(4.4, 0, -9.0), Vector3(2.8, 2.0, 2.6), -0.3)
	# 场地放大后补的第二圈掩体：保持"绕着石头躲扑击"的战术点密度
	rock(Vector3(-6.2, 0, 2.6), Vector3(2.4, 1.8, 2.2), 0.4)
	rock(Vector3(6.4, 0, -1.2), Vector3(2.6, 1.9, 2.4), -0.35)
	rock(Vector3(-3.4, 0, -7.0), Vector3(2.0, 1.4, 1.8), 0.2)
	rock(Vector3(3.6, 0, 6.8), Vector3(2.2, 1.6, 2.0), -0.2)
	# 进场与准备阶段：出生点与南侧返回传送门留出距离，避免进场就压到触发区
	add_player(Vector3(0, 0, 9.0), 24.8, Vector2(-24.4, 24.4))
	flow_mark("ArenaCenter", Vector3(0, 0, 0), "arena_center")
	flow_mark("PrepZone", Vector3(0, 0, 7.6), "prep_zone")
	floor_disc(scaled(Vector3(0, 0, 7.6)), 3.6, mark_material(Color("ffd76a"), 0.22))
	area_label("准备区 · 15 秒预埋炼金炸弹", scaled(Vector3(0, 3.4, 7.6)), Color("ffe58a"), 52, 0.0095)
	# 预埋炸弹点：沿巨虎最可能的扑击路线留三个位置参考
	var trap_points := [Vector3(-3.2, 0, 3.0), Vector3(0, 0, 1.0), Vector3(3.2, 0, 3.0)]
	for i in trap_points.size():
		var at: Vector3 = trap_points[i]
		flow_mark("TrapSpot_%02d" % (i + 1), at, "trap_spot")
		floor_disc(scaled(at), 0.75, mark_material(Color("63d6ff")))
		area_label("炸弹点 %d" % (i + 1), scaled(at) + Vector3(0, 2.2, 0), Color("9fe8ff"), 34, 0.0072)
	# BOSS 出生点：放在北侧树林前，留出与玩家的初始距离
	flow_mark("BossSpawn", Vector3(0, 0, -7.0), "boss_spawn")
	floor_disc(scaled(Vector3(0, 0, -7.0)), 2.2, mark_material(Color("e05555"), 0.3))
	area_label("BOSS 出生点 · 科尔波山之主（巨型变异巨虎）", scaled(Vector3(0, 3.6, -7.0)), Color("ff9a9a"), 52, 0.0100)
	# 结算返回：BOSS 战结束后按 V 回到选关面板
	portal("ReturnPortal", Vector3(0, 0, 11.2), "结算后返回选关", Color("63d6ff"), LEVEL_SELECT_PATH, "返回选关界面", false)
	boss_director()
	forest_landmarks(true)
	sun_rig(Vector3(-48, -28, 0), Color("ffebcf"), 1.6)
	light_shafts(2, Vector2(-11.0, 11.0), Vector2(-14.0, -10.0), Color(1.0, 0.96, 0.78), Vector3(-38, -28, 0))
	environment(Color("243b42"), Color("9fb6a1"), Color("a6becb"), Color("638a82"), 0.002)
	ground_cover(Vector2(3.2, 3.2), Vector2(14.6, 14.6), 0.8)
	backdrop_forest(Vector2(13.3, 13.1), Vector2(20.0, 20.0), 3.8, 8.0)
	camera_rig(true)
	return save_map(CLEARING_PATH)
