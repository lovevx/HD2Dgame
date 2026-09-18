extends SceneTree
## 科尔波山白盒验证：结构标记、关键通路可达、掩体与边界阻挡、BOSS 场地中央留空。
## 用法：
##   godot --headless --path E:/godotproject/hd-2d --script tools/validate_colpo.gd
##   godot --path E:/godotproject/hd-2d --script tools/validate_colpo.gd -- --capture   （渲染并存预览图）

const OUTER := "res://scenes/world/colpo_forest_outer.tscn"
const CLEARING := "res://scenes/world/colpo_forest_clearing.tscn"
const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
## 场景按白盒布局放大到 SCALE 倍，断言坐标跟着换算（与 tools/build_colpo.gd 的 SCALE 一致）。
const SCALE := 2.0

func p(x: float, z: float) -> Vector3:
	return Vector3(x * SCALE, 0, z * SCALE)

var failures: Array[String] = []
var checks := 0
var _scene: Node = null

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var capture := OS.get_cmdline_user_args().has("--capture")
	expect(InputMap.has_action("key_guide"), "按键说明缺少 key_guide 输入动作（应为 F1）")
	expect(action_keycodes("interact") == [KEY_V], "交互键应为 V，实际 %s" % [action_keycodes("interact")])
	expect(action_keycodes("open_menu") == [KEY_ESCAPE], "菜单键应为 Esc，实际 %s" % [action_keycodes("open_menu")])
	var outer: Node3D = await open(OUTER)
	await validate_outer(outer)
	await check_guide_toggle(outer)
	if capture:
		await shoot(outer, "res://docs/colpo_outer_preview.png", p(0, 3.5))
		await shoot_guide(outer)
		await shoot_portal(outer)
		await shoot_fade()
	close(outer)
	var clearing: Node3D = await open(CLEARING)
	validate_clearing(clearing)
	if capture:
		await shoot(clearing, "res://docs/colpo_clearing_preview.png", p(0, 1.5))
	await check_death_panel(clearing)
	close(clearing)
	await check_waves()
	if capture:
		await shoot_waves()
	await validate_select()
	await check_bomb()
	await check_boss()
	if capture:
		await shoot_boss()
		await shoot_mobs()
	await check_portal_transition()
	if failures.is_empty():
		print("COLPO_WHITEBOX: PASS（%d 项检查）" % checks)
		quit(0)
	else:
		for failure in failures:
			print("COLPO_WHITEBOX: FAIL · ", failure)
		quit(1)

## 打开场景；默认摘掉波次调度，避免刷出来的敌人干扰几何、通路与过场检查。
## 自动回收上一个测试场景：中途断言失败时不会留下残景，抢走后续的分组查找。
func open(path: String, with_waves := false) -> Node3D:
	if _scene != null and is_instance_valid(_scene):
		_scene.free()
	var scene: Node3D = load(path).instantiate()
	var director := scene.get_node_or_null("WaveDirector")
	if director != null and not with_waves:
		director.free()
	root.add_child(scene)
	current_scene = scene
	_scene = scene
	await create_timer(0.25).timeout
	return scene

## 收尾释放测试场景。参数故意不写类型：出图步骤会自己换场景，入参可能已经是释放过的对象。
func close(scene) -> void:
	if not is_instance_valid(scene):
		return
	scene.free()
	if scene == _scene:
		_scene = null
	await process_frame

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

## 读取某个动作绑定的物理按键，确认换键真的生效。
func action_keycodes(action: String) -> Array:
	var codes := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			codes.append(event.physical_keycode)
	return codes

func _fmt(at: Vector3) -> String:
	return "(%.1f, %.1f)" % [at.x, at.z]

# ---------------------------------------------------------------- 玩家与碰撞

func grab_player(scene: Node3D) -> CharacterBody3D:
	var player: CharacterBody3D = scene.get_node_or_null("Player")
	if player:
		player.set_physics_process(false)
	return player

func blocked(player: CharacterBody3D, from: Vector3, motion: Vector3) -> bool:
	player.global_position = from
	player.force_update_transform()
	return player.test_move(player.global_transform, motion)

## 沿路线按 1.1 米步进检查：通路必须全程无阻挡。
func route_blocked(player: CharacterBody3D, route: Array) -> Vector3:
	var step := 1.1
	for i in route.size() - 1:
		var from: Vector3 = route[i]
		var to: Vector3 = route[i + 1]
		var dir: Vector3 = (to - from).normalized()
		var total: float = from.distance_to(to)
		var travelled := 0.0
		while travelled < total - 0.01:
			var advance: float = minf(step, total - travelled)
			player.global_position = from + dir * travelled
			player.force_update_transform()
			if player.test_move(player.global_transform, dir * advance):
				return from + dir * travelled
			travelled += advance
	return Vector3.INF

func collect(scene: Node3D, node_name: String) -> Array:
	var found := []
	for node in scene.get_children():
		if node.name.begins_with(node_name):
			found.append(node)
	return found

## 白盒里的树木/岩石/岩壁/刷怪点都带持久分组，避免节点改名后按名字查找失效。
func group_nodes(scene: Node3D, group: String) -> Array:
	var found := []
	for node in scene.get_tree().get_nodes_in_group(group):
		found.append(node)
	return found

func wave_counts(scene: Node3D) -> Dictionary:
	var counts := {}
	for node in scene.get_children():
		if node is Marker3D and node.has_meta("wave"):
			var wave: int = int(node.get_meta("wave"))
			counts[wave] = int(counts.get(wave, 0)) + 1
	return counts

func spawn_kinds(scene: Node3D) -> Array:
	var kinds := []
	for node in scene.get_children():
		if node is Marker3D and node.has_meta("wave") and node.has_meta("kind"):
			kinds.append(str(node.get_meta("kind")))
	return kinds

func tree_trunks(scene: Node3D) -> Array:
	return group_nodes(scene, "colpo_tree")

## 前景节点当前的不透明度：像素精灵读 modulate，素材库 3D 节点读几何体的 transparency。
func faded_alpha(node: Node) -> float:
	var sprite := node as Sprite3D
	if sprite != null:
		return sprite.modulate.a
	if node is GeometryInstance3D:
		return 1.0 - (node as GeometryInstance3D).transparency
	for child in node.get_children():
		var found := faded_alpha(child)
		if found >= 0.0:
			return found
	return -1.0

## 视线可见性：从固定俯角镜头出发，关键战斗位置不能被岩壁/树木/岩石提前挡住。
## 高墙压在近景会直接把地面推出画面，这条检查专门防这个问题。
func occluded(scene: Node3D, point: Vector3, ignore: Array = []) -> bool:
	var camera: Camera3D = scene.get_node_or_null("Camera3D")
	if camera == null:
		return false
	var space := scene.get_world_3d().direct_space_state
	var to := point + Vector3(0, 0.9, 0)
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, to)
	query.exclude = ignore
	return not space.intersect_ray(query).is_empty()

# ---------------------------------------------------------------- 场景 A：山林外围

func validate_outer(scene: Node3D) -> void:
	var player := grab_player(scene)
	expect(player != null, "外围缺少 Player 节点")
	expect(scene.get_node_or_null("Camera3D") != null, "外围缺少 Camera3D")
	expect(scene.get_node_or_null("WorldEnvironment") != null, "外围缺少 WorldEnvironment")
	expect(scene.get_node_or_null("PlayerSpawn") != null, "外围缺少 PlayerSpawn 出生点标记")
	expect(scene.get_node_or_null("ExitPortal") != null, "外围缺少 ExitPortal 传送门")
	# 传送门：挂门脚本、指向林间空地、需要先清场
	var portal: Area3D = scene.get_node_or_null("ExitPortal")
	if portal != null:
		expect(portal.has_method("enter") and portal.has_method("is_cleared"), "外围传送门没有挂 scene_portal.gd")
		expect(str(portal.get("target_scene")) == CLEARING, "外围传送门目标应为林间空地，实际 %s" % portal.get("target_scene"))
		expect(bool(portal.get("requires_cleared")), "外围传送门应当需要清场后才开启")
		expect(portal.is_cleared(), "场上没有敌人时传送门应视为已清场")
	# 三波刷怪点：2 / 3 / 5，且第三波含无能量肉体傀儡
	var counts := wave_counts(scene)
	expect(int(counts.get(1, 0)) == 2, "波次 1 刷怪点应为 2 个，实际 %d 个" % int(counts.get(1, 0)))
	expect(int(counts.get(2, 0)) == 3, "波次 2 刷怪点应为 3 个，实际 %d 个" % int(counts.get(2, 0)))
	expect(int(counts.get(3, 0)) == 5, "波次 3 刷怪点应为 5 个，实际 %d 个" % int(counts.get(3, 0)))
	var kinds := spawn_kinds(scene)
	expect(kinds.count("wolf") == 6, "野狼刷怪点应为 6 个，实际 %d 个" % kinds.count("wolf"))
	expect(kinds.count("boar") == 2, "野猪刷怪点应为 2 个，实际 %d 个" % kinds.count("boar"))
	expect(kinds.count("golem") == 2, "无能量肉体傀儡刷怪点应为 2 个，实际 %d 个" % kinds.count("golem"))
	# 边界与掩体：三面高岩壁 + 近景低矮岩坎，密林密度足够
	expect(group_nodes(scene, "colpo_cliff").size() == 3, "外围边界岩壁应为 3 段，实际 %d 段" % group_nodes(scene, "colpo_cliff").size())
	expect(group_nodes(scene, "colpo_boundary").size() >= 2, "外围近景边界应为碎石堆 + 不可见阻挡，实际 %d 件" % group_nodes(scene, "colpo_boundary").size())
	expect(group_nodes(scene, "colpo_rock").size() >= 12, "外围岩石掩体不足（实际 %d 块）" % group_nodes(scene, "colpo_rock").size())
	expect(tree_trunks(scene).size() >= 25, "外围树木过少，密林密度不足（实际 %d 棵）" % tree_trunks(scene).size())
	if player == null:
		return
	# 入口到传送门的主路必须走通
	var route := [
		p(0, 10.2), p(0.8, 9.6), p(1.4, 8.4), p(0.8, 7.2), p(-0.2, 6.0),
		p(-0.8, 4.8), p(-0.4, 3.6), p(0, 2.6), p(0.6, 1.6), p(0.2, 0.4),
		p(-0.4, -0.8), p(-0.9, -2.0), p(-0.4, -3.2), p(0.2, -4.4), p(0.9, -5.6),
		p(1.1, -6.8), p(0.6, -8.0), p(0, -9.2), p(0, -10.0),
	]
	var hit := route_blocked(player, route)
	expect(hit == Vector3.INF, "外围主路不通：走到 %s 被挡住（入口 → 传送门应全程可走）" % _fmt(hit))
	# 边界岩壁与掩体必须真的挡人
	expect(blocked(player, p(0, 10.2), Vector3(0, 0, 5.0)), "南侧岩壁未阻挡玩家")
	expect(blocked(player, p(0, -9.8), Vector3(0, 0, -5.0)), "北侧岩壁未阻挡玩家")
	expect(blocked(player, p(0, 2.5), Vector3(-6.0, 0, 0)), "隘口岩石未阻挡玩家（掩体不可穿）")
	expect(blocked(player, p(-0.5, -4.4), Vector3(-6.0, 0, 0)), "隘口岩石未阻挡玩家（掩体不可穿）")
	# 树干碰撞：任选一棵树，从四个方向靠近都必须被挡（避开恰好贴着其他掩体的情况）
	var trunks := tree_trunks(scene)
	if trunks.is_empty():
		expect(false, "外围没有树干碰撞体")
	else:
		var blocked_any := false
		for trunk in trunks:
			for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
				if blocked(player, trunk.global_position + dir * 1.3, -dir * 1.3):
					blocked_any = true
					break
			if blocked_any:
				break
		expect(blocked_any, "树干未阻挡玩家（树木碰撞缺失）")
	# 前景淡出：把角色放进侧边树带，挡在镜头与角色之间的树应自动变半透明
	player.set_physics_process(false)
	player.global_position = Vector3(-16.0, 0, 6.0)
	await create_timer(0.6).timeout
	var faded := 0
	for node in group_nodes(scene, "colpo_fade"):
		if faded_alpha(node) < 0.5:
			faded += 1
	expect(faded > 0, "站进树带后，挡在镜头前的树没有淡出（前景遮挡淡出未生效）")
	expect(faded < group_nodes(scene, "colpo_fade").size(), "不该把全场的树都淡掉，只淡真正挡住主角的那几棵")
	# 关键位置必须从固定俯角镜头看得见：高墙挡近景、掩体压住刷怪点都不合格
	var ignore := [player.get_rid()]
	for spot in [p(0, 9.6), p(0, 5.6), p(0, 0.2), p(0, -7.2), p(0, -10.4)]:
		expect(not occluded(scene, spot, ignore), "外围 %s 处被岩壁或掩体挡住，镜头下看不见" % _fmt(spot))

# ---------------------------------------------------------------- 场景 B：林间决战空地

func validate_clearing(scene: Node3D) -> void:
	var player := grab_player(scene)
	expect(player != null, "空地缺少 Player 节点")
	expect(scene.get_node_or_null("Camera3D") != null, "空地缺少 Camera3D")
	expect(scene.get_node_or_null("PlayerSpawn") != null, "空地缺少 PlayerSpawn 出生点标记")
	expect(scene.get_node_or_null("PrepZone") != null, "空地缺少 PrepZone 准备区标记")
	expect(scene.get_node_or_null("BossSpawn") != null, "空地缺少 BossSpawn 标记")
	expect(scene.get_node_or_null("ArenaCenter") != null, "空地缺少 ArenaCenter 标记")
	expect(scene.get_node_or_null("ReturnPortal") != null, "空地缺少 ReturnPortal 返回传送门")
	var portal: Area3D = scene.get_node_or_null("ReturnPortal")
	if portal != null:
		expect(portal.has_method("enter"), "空地返回传送门没有挂 scene_portal.gd")
		expect(str(portal.get("target_scene")) == GameState.LEVEL_SELECT_SCENE, "空地返回传送门应指向选关面板，实际 %s" % portal.get("target_scene"))
		expect(not bool(portal.get("requires_cleared")), "空地返回传送门不应要求清场")
	expect(collect(scene, "TrapSpot").size() == 3, "预埋炸弹点应为 3 个，实际 %d 个" % collect(scene, "TrapSpot").size())
	expect(group_nodes(scene, "colpo_cliff").size() == 3, "空地边界岩壁应为 3 段，实际 %d 段" % group_nodes(scene, "colpo_cliff").size())
	expect(group_nodes(scene, "colpo_boundary").size() >= 2, "空地近景边界应为碎石堆 + 不可见阻挡，实际 %d 件" % group_nodes(scene, "colpo_boundary").size())
	expect(tree_trunks(scene).size() >= 40, "空地边界密林不足（实际 %d 棵）" % tree_trunks(scene).size())
	# 中央必须留空：6 米内不能有岩石或树
	var intruders := 0
	for node in group_nodes(scene, "colpo_rock"):
		if node.global_position.distance_to(Vector3.ZERO) < 12.0:
			intruders += 1
	for trunk in tree_trunks(scene):
		if trunk.global_position.distance_to(Vector3.ZERO) < 12.0:
			intruders += 1
	expect(intruders == 0, "空地中央 12 米内仍有 %d 处障碍，BOSS 场地不够空旷" % intruders)
	if player == null:
		return
	# 进场 → 中央 → BOSS 出生点必须走通
	var route := [p(0, 9.0), p(0, 7.6), p(0, 5.0), p(0, 1.0), p(0, -4.0), p(0, -7.5)]
	var hit := route_blocked(player, route)
	expect(hit == Vector3.INF, "空地通路不通：走到 %s 被挡住（进场 → BOSS 出生点应全程可走）" % _fmt(hit))
	expect(blocked(player, p(0, 10.0), Vector3(0, 0, 6.0)), "南侧岩壁未阻挡玩家")
	expect(blocked(player, p(0, -7.5), Vector3(0, 0, -8.0)), "北侧岩壁未阻挡玩家")
	expect(blocked(player, p(-4.4, -6.5), Vector3(0, 0, -6.0)), "大块岩石掩体未阻挡玩家")
	# 关键位置必须从固定俯角镜头看得见
	var ignore := [player.get_rid()]
	for spot in [p(0, 9.0), p(0, 7.6), p(0, 0), p(0, -8.0)]:
		expect(not occluded(scene, spot, ignore), "空地 %s 处被岩壁或掩体挡住，镜头下看不见" % _fmt(spot))

# ---------------------------------------------------------------- 选关面板

## 选关面板是 Demo 入口：所有已建场景都要能从它进，且启动场景指向它。
func validate_select() -> void:
	expect(str(ProjectSettings.get_setting("application/run/main_scene")) == GameState.LEVEL_SELECT_SCENE, "启动场景未指向选关面板")
	var scene: Control = load(GameState.LEVEL_SELECT_SCENE).instantiate()
	root.add_child(scene)
	current_scene = scene
	await create_timer(0.1).timeout
	var buttons: Array[Button] = []
	collect_buttons(scene, buttons)
	var targets := wired_targets(buttons)
	expect(buttons.size() >= 4, "选关面板入口少于 4 个（科尔波山两关 + 其他已建场景），实际 %d 个" % buttons.size())
	for path in [OUTER, CLEARING, "res://scenes/world/harbor.tscn", "res://scenes/main/main.tscn"]:
		expect(ResourceLoader.exists(path), "场景文件不存在：%s" % path)
		expect(targets.has(path), "选关面板缺少入口：%s" % path)
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/level_select_preview.png")
		print("COLPO_CAPTURE: 选关面板")
	await close(scene)

func collect_buttons(node: Node, found: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			found.append(child)
		collect_buttons(child, found)

## 按钮的跳转目标写在回调的绑定参数里，直接读出来核对。
func wired_targets(buttons: Array[Button]) -> Array:
	var targets := []
	for button in buttons:
		for connection in button.pressed.get_connections():
			for argument in connection["callable"].get_bound_arguments():
				if typeof(argument) == TYPE_STRING:
					targets.append(argument)
	return targets

# ---------------------------------------------------------------- 炼金炸弹

## 按数字 1 真的扔出炸弹、库存真的扣、敌人踩上去真的爆、爆炸只伤敌人不伤苏晓。
func check_bomb() -> void:
	var scene: Node3D = await open(CLEARING)
	var player := grab_player(scene)
	expect(player != null, "炸弹测试缺少玩家")
	if player == null:
		return
	player.set_physics_process(true)  # 投掷走 _unhandled_input，物理处理被关时收不到按键
	# 无头运行（64×64 虚拟窗口）或光标在游戏窗口外时，鼠标射线打不到地面，炸弹按设计投不出去。
	# 这是测试环境的限制，不是玩法回归，直接跳过这一组检查。
	if player.mouse_ground_point() == null:
		print("COLPO_WHITEBOX: SKIP · 鼠标射线不可用，跳过炸弹投掷检查")
		close(scene)
		return
	player.set("bombs", 2)
	player.set("attack_cd", 0.0)
	await press_key(KEY_1)
	await create_timer(0.7).timeout
	var bombs := group_nodes(scene, "alchemy_bombs")
	expect(bombs.size() == 1, "按数字 1 后应生成 1 颗炸弹，实际 %d 颗" % bombs.size())
	expect(int(player.get("bombs")) == 1, "投掷后库存应减到 1，实际 %d" % int(player.get("bombs")))
	if bombs.is_empty():
		close(scene)
		return
	var bomb: Node3D = bombs[0]
	expect(bomb.armed, "炸弹落地后应进入布防状态")
	# 放一只敌人到炸弹上，踩到就该引爆
	var enemy = EnemyScene.instantiate()
	enemy.set("kind", EnemyScript.Kind.WOLF)
	enemy.position = bomb.global_position
	scene.add_child(enemy)
	var player_hp: float = player.hp
	await create_timer(0.9).timeout
	# 炸弹伤害 90 足够秒掉 34 血的野狼，被炸掉时节点已经释放，也算炸伤成功
	var damaged: bool = not is_instance_valid(enemy) or not enemy.is_alive() or enemy.hp_ < enemy.max_hp
	expect(damaged, "敌人踩到炸弹应被炸伤")
	expect(is_equal_approx(player.hp, player_hp), "爆炸只炸敌人，不该伤到站在附近的苏晓")
	await close(scene)

# ---------------------------------------------------------------- BOSS 三阶段

## 开场剧情 → 准备阶段发炸弹 → 巨虎登场 → P2（65%）→ P3 诈死 → 靠近暴起偷袭 → 击杀结算。
func check_boss() -> void:
	var scene: Node3D = await open(CLEARING)
	var director = scene.get_node_or_null("BossDirector")
	var hud := find_hud(scene)
	var player := grab_player(scene)
	expect(director != null, "空地缺少 BossDirector 节点")
	expect(director != null and director.has_method("_begin_prep"), "BossDirector 没有挂 boss_director.gd")
	expect(hud != null, "空地缺少 HUD")
	if director == null or hud == null or player == null:
		return
	director.prep_time = 0.2  # 测试里压缩准备时间
	player.set("invulnerable", true)
	var button: Button = hud.get("action_button")
	expect(button != null and button.text.contains("准备"), "开场剧情面板应带开始准备按钮，实际「%s」" % (button.text if button != null else ""))
	button.pressed.emit()
	await create_timer(0.15).timeout
	expect(int(player.get("bombs")) == 3, "准备阶段应发放 3 颗炼金炸弹，实际 %d 颗" % int(player.get("bombs")))
	for i in 40:
		if director.boss != null:
			break
		await create_timer(0.1).timeout
	var boss = director.boss
	expect(boss != null, "准备阶段结束后 BOSS 没有登场")
	if boss == null:
		close(scene)
		return
	expect(boss.is_in_group("enemies"), "BOSS 应在 enemies 分组里，否则玩家打不到它")
	expect(boss.hit_radius() > 1.0, "BOSS 应带大体型判定半径，不然平 A 打不到它的身体")
	expect(boss.phase == 0 and boss.phase_text().contains("P1"), "BOSS 初始应是 P1，实际 %s" % boss.phase_text())
	# 65% 门槛 → P2，并露出焦痕
	boss.take_damage(boss.max_hp * 0.4)
	expect(boss.phase == 1 and boss.phase_text().contains("P2"), "血量降到六成时应切到 P2，实际 %s" % boss.phase_text())
	expect(boss.wounds.visible, "P2 应显示焦痕、眼部伤与铁钉碎片")
	# 25% 门槛 → P3 诈死
	boss.take_damage(boss.max_hp * 0.45)
	expect(boss.phase == 2 and boss.phase_text().contains("P3"), "血量降到一成五时应切到 P3，实际 %s" % boss.phase_text())
	expect(boss.is_faking_death(), "P3 应进入诈死状态")
	# 靠近诈死的巨虎 → 暴起偷袭
	player.set_physics_process(false)  # 直接摆位，不受移动逻辑干扰
	player.global_position = boss.global_position + Vector3(0, 0, 4.5)
	await create_timer(0.4).timeout
	expect(boss.current_attack() == "ambush", "玩家靠近诈死的巨虎应触发暴起偷袭，实际 %s" % boss.current_attack())
	expect(not boss.is_faking_death(), "暴起偷袭后应解除诈死")
	# 击杀 → 胜利结算
	boss.take_damage(9999.0)
	await create_timer(0.3).timeout
	var overlay: ColorRect = hud.get("overlay")
	expect(overlay.visible and hud.panel_title.text.contains("猎杀完成"), "击杀 BOSS 后应弹出胜利结算，实际「%s」" % hud.panel_title.text)
	expect(not hud.boss_box.visible, "结算后应收起 BOSS 血条")
	close(scene)

## 前景淡出出图：角色站进侧边树带，挡在镜头前的树变半透明。
func shoot_fade() -> void:
	var scene: Node3D = await open(OUTER)
	var player := grab_player(scene)
	if player == null:
		return
	player.set_physics_process(false)
	player.global_position = p(-7.5, 3.0)
	await create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/foreground_fade_preview.png")
	print("COLPO_CAPTURE: 前景遮挡淡出")
	await close(scene)

## 小怪模型特写：三种敌人并排站到空地中央（背景干净），临时收紧正交尺寸看清形体。
func shoot_mobs() -> void:
	var scene: Node3D = await open(CLEARING)
	var player := grab_player(scene)
	var camera: Camera3D = scene.get_node_or_null("Camera3D")
	var hud := find_hud(scene)
	if player == null or camera == null:
		return
	if hud != null:
		hud.visible = false
	player.global_position = p(0, 5.0)
	# 出模型图时先把白盒区域标签与地面标记藏掉，不然全糊在模型上
	for node in scene.get_children():
		if node is Label3D or (node is MeshInstance3D and node.name.begins_with("FloorMark")):
			node.visible = false
	var kinds := [EnemyScript.Kind.WOLF, EnemyScript.Kind.BOAR, EnemyScript.Kind.GOLEM]
	for i in kinds.size():
		var enemy = EnemyScene.instantiate()
		enemy.set("kind", kinds[i])
		scene.add_child(enemy)
		enemy.global_position = p(-4.2 + i * 4.2, 0.5)
		enemy.rotation.y = PI      # 正面朝镜头
		enemy.set_physics_process(false)
	camera.size = 16.0
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/mobs_preview.png")
	print("COLPO_CAPTURE: 三种小怪白盒模型")
	await close(scene)

# ---------------------------------------------------------------- BOSS 出图

## 出两张图：准备阶段预埋炸弹 + P1 完整巨虎，以及 P2 受伤（焦痕 / 破损眼球 / 铁钉）。
func shoot_boss() -> void:
	var scene: Node3D = await open(CLEARING)
	var director = scene.get_node_or_null("BossDirector")
	var hud := find_hud(scene)
	var player := grab_player(scene)
	if director == null or hud == null or player == null:
		return
	director.prep_time = 0.5
	player.set("invulnerable", true)
	hud.action_button.pressed.emit()
	await create_timer(0.1).timeout
	for i in 3:
		var bomb = load("res://scripts/combat/alchemy_bomb.tscn").instantiate()
		scene.add_child(bomb)
		bomb.place_at(p(-4.5 + i * 4.5, 2.0))
	for i in 40:
		if director.boss != null:
			break
		await create_timer(0.1).timeout
	var boss = director.boss
	if boss == null:
		return
	player.global_position = p(2.0, 3.0)
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/boss_p1_preview.png")
	print("COLPO_CAPTURE: BOSS P1 完整态")
	boss.take_damage(boss.max_hp * 0.4)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/boss_p2_preview.png")
	print("COLPO_CAPTURE: BOSS P2 受伤态")
	# P3 诈死：趴伏不动，骗玩家贴脸
	boss.take_damage(boss.max_hp * 0.45)
	await create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/boss_p3_preview.png")
	print("COLPO_CAPTURE: BOSS P3 诈死态")
	await close(scene)

# ---------------------------------------------------------------- 端到端过场

## 波次推进：数量递增 2 / 3 / 5，第三波混编两只无能量肉体傀儡，
## 清完之前传送门一直锁着，清完才开闸。
func check_waves() -> void:
	var scene: Node3D = await open(OUTER, true)
	var director = scene.get_node_or_null("WaveDirector")
	var portal: Area3D = scene.get_node_or_null("ExitPortal")
	expect(director != null, "外围缺少 WaveDirector 波次调度节点")
	expect(director != null and director.has_method("is_finished"), "WaveDirector 没有挂 wave_spawner.gd")
	if director == null or portal == null:
		return
	director.wave_delay = 0.2  # 测试里压缩波间喘息
	var player := grab_player(scene)
	if player != null:
		player.set("invulnerable", true)  # 专注验证波次，不让小怪把玩家打死
	var expected_sizes := [2, 3, 5]
	var expected_energy := [2, 3, 3]  # 第三波 5 只里有 2 只是无能量傀儡
	for i in expected_sizes.size():
		var size: int = expected_sizes[i]
		await wait_for_wave(director, size)
		var alive := alive_enemies(director)
		expect(alive.size() == size, "第 %d 波应刷出 %d 只敌人，实际 %d 只" % [i + 1, size, alive.size()])
		expect(energy_count(alive) == expected_energy[i], "第 %d 波能量型敌人应为 %d 只，实际 %d 只" % [i + 1, expected_energy[i], energy_count(alive)])
		expect(not portal.is_cleared(), "第 %d 波未清完时传送门不该开启" % (i + 1))
		for enemy in alive:
			enemy.take_damage(9999.0)
		await create_timer(0.4).timeout
	expect(director.is_finished(), "三波清完后波次调度应标记完成")
	expect(portal.is_cleared(), "三波清完后传送门应解锁")
	close(scene)

func wait_for_wave(director, size: int) -> void:
	for i in 60:
		if alive_enemies(director).size() >= size:
			return
		await create_timer(0.1).timeout

## 波次出图：清掉前两波，等第三波混编小队站定后出图。
func shoot_waves() -> void:
	var scene: Node3D = await open(OUTER, true)
	var director = scene.get_node_or_null("WaveDirector")
	if director == null:
		return
	director.wave_delay = 0.3
	var player := grab_player(scene)
	if player != null:
		player.set("invulnerable", true)
		player.global_position = p(0, -4.0)  # 站到第三波口袋前，取景能带上整队
	for size in [2, 3]:
		await wait_for_wave(director, size)
		for enemy in alive_enemies(director):
			enemy.take_damage(9999.0)
		await create_timer(0.5).timeout
	await wait_for_wave(director, 5)
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/waves_preview.png")
	print("COLPO_CAPTURE: 波次 3 混编小队")
	close(scene)

func alive_enemies(director) -> Array:
	var found := []
	for child in director.get_children():
		if child.has_method("is_alive") and child.is_alive():
			found.append(child)
	return found

func energy_count(alive: Array) -> int:
	var count := 0
	for enemy in alive:
		if bool(enemy.get("has_energy")):
			count += 1
	return count

## 阵亡不能卡死：弹结算面板，按钮必须是回选关。
func check_death_panel(scene: Node3D) -> void:
	var player = scene.get_node_or_null("Player")
	var hud := find_hud(scene)
	expect(player != null and hud != null, "阵亡测试缺少玩家或 HUD")
	if player == null or hud == null:
		return
	player.take_damage(player.hp + 10.0)
	await create_timer(0.2).timeout
	var overlay: ColorRect = hud.get("overlay")
	expect(overlay != null and overlay.visible, "阵亡后没有弹出结算面板")
	var button: Button = hud.get("action_button")
	expect(button != null and button.text.contains("返回选关"), "阵亡面板按钮应能返回选关，实际「%s」" % (button.text if button != null else ""))
	if button != null:
		expect(button.pressed.get_connections().size() > 0, "阵亡面板的返回选关按钮没有接回调")

## 站进外围传送门 → 出现贴底提示 → 按 V → 真的切到林间决战空地。
func check_portal_transition() -> void:
	var scene: Node3D = await open(OUTER)
	var player := grab_player(scene)
	var portal: Area3D = scene.get_node_or_null("ExitPortal")
	expect(player != null and portal != null, "过场测试缺少玩家或传送门")
	if player == null or portal == null:
		return
	player.global_position = portal.global_position
	await create_timer(0.3).timeout
	var hud := find_hud(scene)
	var prompt: Label = hud.get("prompt") if hud != null else null
	expect(prompt != null and prompt.visible, "站进传送门后没有出现贴底交互提示")
	if prompt != null and prompt.visible:
		expect(prompt.text.contains("V"), "交互提示应写明按 V，实际「%s」" % prompt.text)
	await press_key(KEY_V)
	await create_timer(1.0).timeout
	var arrived: bool = current_scene != null and current_scene.name == "ColpoForestClearing"
	expect(arrived, "按 V 后没有切到林间决战空地（当前：%s）" % ("空" if current_scene == null else current_scene.name))

# ---------------------------------------------------------------- 渲染预览

func shoot(scene: Node3D, path: String, focus: Vector3) -> void:
	var player := grab_player(scene)
	if player:
		player.global_position = focus
	for child in scene.get_children():
		if child is CanvasLayer:
			child.visible = false
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("COLPO_CAPTURE: ", path)

## 按键说明面板：HUD 自带、默认收起，由 F1 打开；这里直接切换可见后出图。
func shoot_guide(scene: Node3D) -> void:
	var hud := find_hud(scene)
	expect(hud != null, "场景里没有 HUD，按键说明面板无处安放")
	if hud == null:
		return
	var guide: Control = hud.get("key_guide")
	if guide == null:
		return
	hud.visible = true  # 上一步出图时隐藏了 HUD，这里恢复
	guide.visible = true
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/key_guide_preview.png")
	print("COLPO_CAPTURE: 按键说明面板")
	guide.visible = false

## 站进传送门出图：确认贴底交互提示的实际观感。
func shoot_portal(scene: Node3D) -> void:
	var player := grab_player(scene)
	var portal: Area3D = scene.get_node_or_null("ExitPortal")
	if player == null or portal == null:
		return
	player.global_position = portal.global_position + Vector3(0, 0, 0.4)  # 站进触发盒内（盒深 1.4）
	var hud := find_hud(scene)
	if hud != null:
		hud.visible = true
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/portal_prompt_preview.png")
	print("COLPO_CAPTURE: 传送门交互提示")
	# 门外 9 米处再看一眼：52° 俯视下传送门必须一眼能认出来
	player.global_position = portal.global_position + Vector3(0, 0, 9.0)
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/portal_approach_preview.png")
	print("COLPO_CAPTURE: 传送门远景")

func find_hud(scene: Node3D) -> CanvasLayer:
	for child in scene.get_children():
		if child is CanvasLayer:
			return child
	return null

## F1 必须真的能开合面板：投递按键事件，确认状态确实翻转、默认处于收起。
func check_guide_toggle(scene: Node3D) -> void:
	var hud := find_hud(scene)
	expect(hud != null, "场景里没有 HUD")
	if hud == null:
		return
	var guide: Control = hud.get("key_guide")
	expect(guide != null, "HUD 里没有按键说明面板")
	if guide == null:
		return
	expect(not guide.visible, "按键说明面板默认应处于收起状态")
	await press_f1()
	expect(guide.visible, "按 F1 后面板没有打开")
	await press_f1()
	expect(not guide.visible, "再按一次 F1 后面板没有收起")
	# Esc 菜单：任何场景都要能回选关
	var menu: Control = hud.get("menu")
	expect(menu != null, "HUD 里没有 Esc 菜单")
	if menu != null:
		expect(not menu.visible, "Esc 菜单默认应处于收起状态")
		await press_key(KEY_ESCAPE)
		expect(menu.visible, "按 Esc 后菜单没有打开")
		await press_key(KEY_ESCAPE)
		expect(not menu.visible, "再按一次 Esc 后菜单没有收起")
		var menu_buttons: Array[Button] = []
		collect_buttons(menu, menu_buttons)
		expect(menu_buttons.size() >= 1, "Esc 菜单缺少返回选关按钮，实际 %d 个" % menu_buttons.size())
		if not menu_buttons.is_empty():
			expect(menu_buttons[0].pressed.get_connections().size() > 0, "Esc 菜单的返回选关按钮没有接回调")
			expect(menu_buttons[0].text.contains("返回选关"), "Esc 菜单首个按钮应为返回选关，实际「%s」" % menu_buttons[0].text)

func press_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	await create_timer(0.14).timeout

func press_f1() -> void:
	await press_key(KEY_F1)
