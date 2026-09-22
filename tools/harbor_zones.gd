extends RefCounted
## 主城功能分区装配，b 为 build_harbor.gd 的素材与地面构件接口。
## 2026-09-19：地面摆件与建筑全部清空，本文件只保留五个功能区的位置、光圈与招牌；
## 重新布景时再往对应分区里加 b.prop(...)。城门已改由 tools/harbor_gate.gd 随城墙砌筑。
static func build(b) -> void:
	var HarborShop := preload("res://tools/harbor_shop.gd")
	var HarborForge := preload("res://tools/harbor_forge.gd")
	var HarborQuest := preload("res://tools/harbor_quest.gd")
	point(b, "DeparturePortal", Vector3(0, 0, -21), "世界入口 · 阶段试炼", Color("79dfff"), "", "res://scenes/main/campaign.tscn")
	b.zone_marker("EntranceZone", Vector3(0, 0, -21), "entrance", "传送出入口", Color("79dfff"))

	point(b, "ShopService", HarborShop.SERVICE_AT, "商店 · 轮回商店", Color("8ee8f7"), "左上街角的轮回商店\n\n药剂补给  /  武具防具  /  消耗与材料\n\n商店交易框架已就绪，商品与经济系统待接入。")
	b.zone_marker("ShopZone", HarborShop.SERVICE_AT, "shop", "商店区", Color("8ee8f7"))
	# 左上商店区陈设：店面小楼、门面货架招牌、集市角与青色灯带（tools/harbor_shop.gd）。
	b.map.add_child(HarborShop.make_node())

	point(b, "ForgeService", HarborForge.SERVICE_AT, "装备强化 · 铸潮工坊", Color("ffb780"), "装备强化与材料加工处\n\n强化工作台  /  矿石材料  /  装备整备\n\n场景交互入口已开放，强化数值与消耗系统待接入。")
	b.zone_marker("ForgeZone", HarborForge.SERVICE_AT, "forge", "装备强化区", Color("ffb780"))
	# 强化区陈设：强化巷北侧一排锻造铺面、门前熔炉与锻造台、街南侧石料与魔晶（tools/harbor_forge.gd）。
	b.map.add_child(HarborForge.make_node())
	# 强化区的暖色灯保留：机能区需要一个照明锚点。
	var glow := OmniLight3D.new()
	glow.name = "ForgeCrystalLight"
	glow.position = Vector3(11, 2, -12)
	glow.light_color = Color("ffaf66")
	glow.light_energy = 2.0
	glow.omni_range = 5.0
	b.map.add_child(glow)

	point(b, "QuestService", HarborQuest.SERVICE_AT, "任务 · 港务委托所", Color("a4efc2"), "灰潮港任务与情报集散处\n\n港务委托  /  区域情报  /  任务交付\n\n北侧城门通往阶段试炼（世界入口），东侧码头通往演武场（新手教学）。\n任务接取、进度与奖励系统待接入。")
	b.zone_marker("QuestZone", HarborQuest.SERVICE_AT, "quest", "任务功能区", Color("a4efc2"))
	# 任务区陈设：任务巷北侧的委托所主楼与副楼、门前公告板与柜台、前院、巷南侧坐具与招幌（tools/harbor_quest.gd）。
	b.map.add_child(HarborQuest.make_node())

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
