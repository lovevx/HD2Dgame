extends RefCounted
## 港口专用黄昏光照；共享素材原文件不变。
static func build(b) -> void:
	var fill := DirectionalLight3D.new()
	fill.name = "CoolSkyFill"
	fill.rotation_degrees = Vector3(-50, 145, 0)
	fill.light_color = Color("94badc")
	fill.light_energy = 0.35
	fill.light_specular = 0.25
	fill.light_volumetric_fog_energy = 0.0
	b.map.add_child(fill)
	var hero_fill := OmniLight3D.new()
	hero_fill.name = "CharacterFill"
	hero_fill.position = Vector3(0, 2, 1.5)
	hero_fill.light_color = Color("bbd7ef")
	hero_fill.light_energy = 1.0
	hero_fill.omni_range = 3.5
	hero_fill.light_volumetric_fog_energy = 0.0
	b.map.get_node("Player").add_child(hero_fill)
	# 低密度漂浮尘光提供缓慢的空气运动，不遮住招牌与角色。
	var motes := GPUParticles3D.new()
	motes.name = "HarborDust"
	motes.position = Vector3(0, 2.5, -6)
	motes.amount = 64
	motes.lifetime = 16.0
	motes.preprocess = 16.0
	motes.visibility_aabb = AABB(Vector3(-26, -4, -24), Vector3(52, 12, 48))
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(22, 2.5, 19)
	motion.direction = Vector3(1, 0.2, 0.1)
	motion.spread = 25.0
	motion.initial_velocity_min = 0.08
	motion.initial_velocity_max = 0.18
	motion.gravity = Vector3.ZERO
	motion.scale_min = 0.4
	motion.scale_max = 0.9
	motes.process_material = motion
	var fleck := QuadMesh.new()
	fleck.size = Vector2(0.065, 0.065)
	var dust := StandardMaterial3D.new()
	dust.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust.albedo_color = Color("d8b879")
	dust.emission_enabled = true
	dust.emission = Color("d8b879")
	dust.emission_energy_multiplier = 0.6
	fleck.material = dust
	motes.draw_pass_1 = fleck
	b.map.add_child(motes)
	for node in b.map.get_children():
		if node is HD2DProp and node.asset.title == "SM_NJ_ShiDeng_001":
			lamp(b, node.position + Vector3(0, 1.75, 0), 3.5, 5.5, false)
	# 门、摊位与工坊是主要光照焦点。
	for pos in [Vector3(-11, 2.5, -12.8), Vector3(11, 2.7, -12), Vector3(-14, 2.4, -1), Vector3(17, 2.5, -1)]:
		lamp(b, pos, 7.0, 7.5, true, true)
	for pos in [Vector3(-3.6, 2.1, 18), Vector3(18.4, 2.1, 18)]:
		b.prop_with_box("SM_NJ_ShiDeng_001", pos - Vector3(0, 1.75, 0), 0, 0.8)
		lamp(b, pos, 5.0, 7.0, false)
	var post := CanvasLayer.new()
	post.name = "HarborColorGrade"
	post.layer = 0 # HUD 的 CanvasLayer 为 1，不参与调色。
	b.map.add_child(post)
	var rect := ColorRect.new()
	rect.name = "ColorGrade"
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/harbor_grade.gdshader")
	rect.material = mat
	post.add_child(rect)

static func lamp(b, at: Vector3, energy: float, radius: float, shadows: bool, post: bool = false) -> void:
	if post:
		var timber: Material = b.material(Color("4c3b2e"))
		b.slab("LanternPost", Vector3(at.x + 0.3, at.y * 0.5, at.z), Vector3(0.12, at.y + 0.3, 0.12), timber, true)
		b.slab("LanternBracket", at + Vector3(0.12, 0.23, 0), Vector3(0.5, 0.08, 0.10), timber)
	var light := OmniLight3D.new()
	light.name = "WarmLantern"
	light.position = at
	light.light_color = Color("ffc17b")
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.5
	light.shadow_enabled = shadows
	light.shadow_bias = 0.05
	light.light_size = 0.2
	light.light_volumetric_fog_energy = 0.45
	b.map.add_child(light)
	var core: MeshInstance3D = b.slab("LanternGlow", at, Vector3(0.16, 0.24, 0.16), b.material(Color("ffd59a"), 5.0))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for y in [-0.15, 0.15]:
		b.slab("LanternCap", at + Vector3(0, y, 0), Vector3(0.28, 0.055, 0.28), b.material(Color("3d342b")))
