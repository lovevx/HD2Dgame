extends SceneTree
## 六维属性无头校验：派生公式 + GameState 属性点接口 + 试炼场实例集成。
## 用法：godot --headless --path . --script res://tools/validate_six_attrs.gd
## 存档走 tools/test_env.gd 的隔离档（旧版是"备份 user://save.cfg → 改 → 还原"，
## 中途崩掉就会把真实存档留成默认六维，且临时 GameState 实例默认写的就是真实档）。
const TestEnv := preload("res://tools/test_env.gd")

var _failures := 0

func assert_eq(got, want, label: String) -> void:
	if got == want:
		print("PASS  ", label)
	else:
		_failures += 1
		push_error("FAIL  %s  (got %s, want %s)" % [label, got, want])

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# 等 autoload（GameState 等）就绪，其全局名才会对解析器可见
	await process_frame
	await process_frame
	# 全局状态先换成隔离档：第 3 段会直接改 autoload 的 attributes，
	# 第 2 段的临时 GameState 实例默认写盘目标也是真实档。
	var live: Node = root.get_node_or_null("GameState")
	if live == null:
		push_error("FAIL  autoload GameState 未就位")
		quit(1)
		return
	TestEnv.isolate(live, "six_attrs")

	# 0) 改动脚本全部可解析
	load("res://data/attributes.gd")
	load("res://autoload/game_state.gd")
	load("res://player.gd")
	load("res://scripts/ui/hud.gd")
	print("PASS  改动脚本全部可解析")

	# 1) Attributes 静态表：默认值 + 派生公式 + 可投维度
	var attr: GDScript = load("res://data/attributes.gd")
	var base: Dictionary = attr.defaults()
	assert_eq(base, {"str": 5, "agi": 5, "con": 5, "int": 5, "cha": 5, "luk": 5}, "六维默认全5")
	assert_eq(attr.attack(base), 12.0, "攻击 = 7+5 = 12")
	assert_eq(attr.max_hp(base), 100.0, "最大HP = 50+5×10 = 100")
	assert_eq(attr.max_mp(base), 50.0, "最大MP = 5×10 = 50")
	assert_eq(attr.move_speed(base), 2.6, "移速 = 2.6（敏捷5，整体降速后）")
	assert_eq(attr.attack({"str": 7}), 14.0, "力量7 → 攻击14")
	assert_eq(attr.max_hp({"con": 8}), 130.0, "体力8 → HP130")
	assert_eq(attr.max_mp({"int": 8}), 80.0, "智力8 → MP80")
	assert_eq(attr.is_spendable("str"), true, "力量可投")
	assert_eq(attr.is_spendable("agi"), true, "敏捷可投")
	assert_eq(attr.is_spendable("luk"), false, "幸运不可投")
	assert_eq(attr.is_spendable("cha"), false, "魅力不可投")
	assert_eq(attr.merged({"str": 9, "junk": 1}), {"str": 9, "agi": 5, "con": 5, "int": 5, "cha": 5, "luk": 5}, "旧档合并兜底")
	assert_eq(attr.CN_NAMES.size(), 6, "六维中文名齐全")

	# 2) GameState 属性点接口
	# 临时实例不在场景树里、_ready 不会跑，所以 save_path 仍是默认的真实档 ——
	# 必须显式指向隔离档并断写盘，否则 spend_attr_point 的 save_game() 会盖掉真实存档。
	var gs: Node = (load("res://autoload/game_state.gd") as GDScript).new()
	gs.save_path = TestEnv.path_for("six_attrs")
	gs.persistence_enabled = false
	gs.attributes = attr.defaults()
	gs.attr_points = 5
	assert_eq(gs.spend_attr_point("luk"), false, "幸运分配被拒")
	assert_eq(gs.spend_attr_point("nope"), false, "非法维度被拒")
	assert_eq(gs.spend_attr_point("str"), true, "力量分配成功")
	assert_eq(gs.get_attribute("str"), 6, "力量 5→6")
	assert_eq(gs.get_attr_points(), 4, "属性点 5→4")
	assert_eq(gs.spend_attr_point("int", 9), false, "点数不足被拒")
	assert_eq(gs.get_attribute("agi"), 5, "未投维度不变")
	gs.free()

	# 3) 试炼场集成：默认六维下玩家派生值与 HUD 就位
	if live != null:
		live.attributes = attr.defaults()
		live.attr_points = 0
		var scene = load("res://scenes/main/main.tscn").instantiate()
		root.add_child(scene)
		await process_frame
		await process_frame
		var player = scene.get_node_or_null("player") if scene.has_node("player") else null
		if player == null:
			for n in scene.find_children("*", "CharacterBody3D", true, false):
				if n.is_in_group("player"):
					player = n
					break
		assert_eq(player != null, true, "试炼场包含玩家")
		if player != null:
			assert_eq(player.max_hp, 100.0, "玩家 max_hp = 100")
			assert_eq(player.max_mp, 50.0, "玩家 max_mp = 50")
			assert_eq(player.attack_damage, 12.0, "玩家攻击 = 12")
			assert_eq(player.move_speed, 2.6, "玩家移速 = 2.6")
			assert_eq(player.hp, player.max_hp, "满血入场")
			assert_eq(player.mp, player.max_mp, "满蓝入场")
		var huds := get_nodes_in_group("hud")
		assert_eq(huds.size() > 0, true, "HUD 就位")
		if huds.size() > 0:
			var hud: Node = huds[0]
			assert_eq(hud.char_panel != null, true, "角色面板存在")
			assert_eq(hud.char_portrait != null and hud.char_portrait.texture != null, true, "人物形象图就位")
			assert_eq(hud.char_attr_labels.size(), 6, "右侧六维属性六行")
			assert_eq(hud.char_points_label.text.contains("可用属性点"), true, "可用属性点行就位")
			hud.char_panel.visible = true
			hud._refresh_char_panel()
			assert_eq(hud.char_attr_labels["str"].text.contains("力量"), true, "力量行刷新")

	print("----------------------------------------")
	TestEnv.cleanup(live)
	if _failures == 0:
		print("六维属性校验：全部 PASS")
		quit(0)
	else:
		push_error("六维属性校验：%d 项失败" % _failures)
		quit(1)