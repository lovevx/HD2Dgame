extends RefCounted
## 主城功能分区装配，b 为 build_harbor.gd 的素材与地面构件接口。
static func build(b) -> void:
	b.prop("SM_xgg_chengmen001", Vector3(0, 0, -30), 180.0)
	b.prop("SM_JN_fangzi001", Vector3(-22, 0, -25), 0, 0.9)
	b.prop("SM_JN_fangzi005", Vector3(20, 0, -25), 0, 0.9)
	for x in [-7.0, 7.0]:
		b.prop_with_box("SM_Licheng_shizhuzi001", Vector3(x, 0, -23))
		b.prop_with_box("SM_NJ_ShiDeng_001", Vector3(x, 0, -19))
	point(b, "DeparturePortal", Vector3(0, 0, -21), "城门传送 · 科尔波山", Color("79dfff"), "", "res://scenes/world/colpo_forest_outer.tscn")
	b.zone_marker("EntranceZone", Vector3(0, 0, -21), "entrance", "传送出入口", Color("79dfff"))

	b.prop("sm_gsc_kezhan001", Vector3(-20, 0, -17), 0, 0.8)
	b.prop("SM_gsc_tanzi001", Vector3(-11, 0, -13), 0, 0.9)
	b.prop("SM_NJ_ZhuPengzi001", Vector3(-11, 0, -14.3), 0, 1.1, {"static_collision": false})
	b.prop_with_box("SM_JN_yaogui001", Vector3(-15, 0, -12), 0, 0.8)
	b.prop_with_box("SM_Item_NJhuojia003", Vector3(-17, 0, -11), 90, 0.8)
	b.prop_with_box("SM_Box001Open", Vector3(-14, 0, -10))
	point(b, "ShopService", Vector3(-10, 0, -9), "商店 · 潮汐杂货", Color("ffe49a"), "港口补给与物资交易处\n\n药剂补给  /  旅行物资  /  装备交易\n\n场景交互入口已开放，商品与交易系统待接入。")
	b.zone_marker("ShopZone", Vector3(-10, 0, -9), "shop", "商店区", Color("ffe49a"))

	b.prop("SM_NJ_ZhuPengzi001", Vector3(13, 0, -15), 0, 1.0, {"static_collision": true, "collision_mode": 1, "collision_size": Vector3(3.6, 2.6, 2.6), "collision_offset": Vector3(0, 1.3, 0)})
	b.prop_with_box("SM_mjsz_shizhuozi001", Vector3(11, 0, -12))
	b.prop("SM_Item_damoshuijing001", Vector3(11, 1.05, -12), 0, 0.65, {"static_collision": false})
	b.prop_with_box("SM_Item_NJhuojia004", Vector3(16, 0, -12), 90, 0.8)
	for spot in [Vector3(14, 0, -13), Vector3(16, 0, -14), Vector3(14, 0, -11)]:
		b.prop("SM_Item_Hantiekuang001", spot, 20, 0.65, {"static_collision": false})
	b.prop("SM_ltem_Shuiche001", Vector3(22, 0, -16), -24, 0.8, {"static_collision": false})
	var glow := OmniLight3D.new()
	glow.name = "ForgeCrystalLight"
	glow.position = Vector3(11, 2, -12)
	glow.light_color = Color("ffaf66")
	glow.light_energy = 2.0
	glow.omni_range = 5.0
	b.map.add_child(glow)
	point(b, "ForgeService", Vector3(10, 0, -9), "装备强化 · 铸潮工坊", Color("ffb780"), "装备强化与材料加工处\n\n强化工作台  /  矿石材料  /  装备整备\n\n场景交互入口已开放，强化数值与消耗系统待接入。")
	b.zone_marker("ForgeZone", Vector3(10, 0, -9), "forge", "装备强化区", Color("ffb780"))

	b.prop("SM_NJ_ZhuPengzi001", Vector3(-16, 0, -1), 0, 0.85, {"static_collision": true, "collision_mode": 1, "collision_size": Vector3(3.6, 2.6, 2.6), "collision_offset": Vector3(0, 1.3, 0)})
	b.prop_with_box("SM_Item_pingfeng001", Vector3(-11, 0, -2.6), 0, 1.0)
	b.prop_with_box("SM_NJ_ZhuZhuozi001", Vector3(-15, 0, 0), 0, 0.9)
	b.prop_with_box("SM_Box001Close", Vector3(-18, 0, 1))
	point(b, "QuestService", Vector3(-10, 0, 0.5), "任务 · 港务委托所", Color("a4efc2"), "灰潮港任务与情报集散处\n\n港务委托  /  区域情报  /  任务交付\n\n北侧城门通往科尔波山，东侧码头通往战斗试炼。\n任务接取、进度与奖励系统待接入。")
	b.zone_marker("QuestZone", Vector3(-10, 0, 0.5), "quest", "任务功能区", Color("a4efc2"))

	# 演武区移到东南，避免武馆与强化工作台重叠。
	for x in [14.0, 20.0]:
		b.prop("SM_gsc_gu001", Vector3(x, 0, -1.5), 0, 0.9, {"static_collision": false})
		b.prop_with_box("SM_Licheng_shizhuzi001", Vector3(x, 0, -3.5), 0, 0.8)
	point(b, "TrialPortal", Vector3(17, 0, 1), "试炼传送 · 演武场", Color("f4a8ac"), "", "res://scenes/main/main.tscn")
	b.zone_marker("TrialZone", Vector3(17, 0, 1), "trial_entrance", "试炼入口", Color("f4a8ac"))

static func point(b, id: String, at: Vector3, title: String, tint: Color, description: String = "", target: String = "") -> void:
	var area := Area3D.new()
	area.name = id
	area.position = at
	if target.is_empty():
		area.set_script(load("res://scripts/world/harbor_service.gd"))
		area.set("title", title)
		area.set("description", description)
	else:
		area.set_script(load("res://scripts/world/scene_portal.gd"))
		area.set("target_scene", target)
		area.set("prompt_text", title)
	area.add_to_group("harbor_services", true)
	b.map.add_child(area)
	var collision := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 3.0
	collision.shape = shape
	collision.position.y = 1.0
	area.add_child(collision)
	var ring := MeshInstance3D.new()
	ring.name = id + "Ring"
	var torus := TorusMesh.new()
	torus.inner_radius = 1.70
	torus.outer_radius = 1.75
	ring.mesh = torus
	ring.scale.y = 0.22
	ring.position = at + Vector3(0, 0.06, 0)
	ring.material_override = b.material(tint.darkened(0.18), 0.15)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.map.add_child(ring)
	var label := Label3D.new()
	label.name = id + "Sign"
	label.text = title
	label.position = at + Vector3(0, 2.5, 0)
	label.font_size = 42
	label.pixel_size = 0.008
	label.outline_size = 12
	label.modulate = tint
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	b.map.add_child(label)
