extends SceneTree
## 双形态战斗回归：回合核心（AT/轮转/回蓝/门闩/敌人步进/遭遇圈）+ 直踢常量
## + **眩晕与处决链**（平A/直踹叠眩晕、打满停移动、直踹处决）+ **科尔波山之主回合接口**
## + 战斗验证场（小怪 + 山之主）可装载
## + 指令集统一为五条 / 防御存活期 / 回合内耗蓝不被退回 / 侧背击按目标朝向判定
##   （后四项是 2026-09-23 修的，作者报的 5 处状态缺陷 —— 逐条都有回归断言钉住）。
## 运行：godot --headless --path . --script res://tools/validate_battle.gd
## 走 tools/test_env.gd 的隔离存档 + 固定六维：派生上限（HP/MP/体力）不再随本机存档漂移。
const TestEnv := preload("res://tools/test_env.gd")
const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
const Skills := preload("res://data/combat_skills.gd")
const AttributesScript := preload("res://data/attributes.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func unit_stub(agi := 5) -> BattleUnit:
	var u := BattleUnit.new()
	u.hp = 100.0
	u.max_hp = 100.0
	u.mp = 30.0
	u.max_mp = 60.0
	u.agility = agi
	return u

func run() -> void:
	await process_frame
	# 先钉住全局状态，再碰任何派生值（六维 → max_hp/max_mp/max_stamina）。
	var gs_env: Node = root.get_node("GameState")
	TestEnv.isolate(gs_env, "battle")
	# 1) battle_unit 回蓝
	var u := unit_stub()
	check(u.hp_ratio() == 1.0, "battle_unit 初始血量满")
	check(is_equal_approx(u.round_mp_regen(), 3.0), "回合回蓝 = 5% 最大 MP")
	u.take_regen_mp()
	check(is_equal_approx(u.mp, 33.0), "回合回蓝入账")

	# 2) battle_controller 状态机与 AT 顺序
	var ctl := BattleController.new()
	ctl.set_units([unit_stub(6), unit_stub(4)])
	ctl.begin_battle()
	check(ctl.order[0].agility == 6 and ctl.order[1].agility == 4, "AT 敏捷降序")
	ctl.finish_turn()
	check(ctl.current().agility == 4, "轮转进入下一单位")
	ctl.finish_turn()
	check(ctl.round == 1 and ctl.order.size() == 2, "整轮重排并回蓝")
	ctl.force_win()
	check(ctl.phase == BattleController.Phase.VICTORY, "胜负结算进入胜利")

	# 2b) 指令集：两套场景共用 BattleMenu.COMMANDS（作者 2026-09-23 定：统一为五条）。
	# 教学场曾自己写死三条，与练习场的五条并存过 —— 这条断言钉住"只有一个来源"。
	var cmds: Array[String] = BattleMenu.COMMANDS
	check(cmds.size() == 5, "指令集五条")
	check(cmds[0] == "攻击" and cmds[1] == "战技" and cmds[2] == "防御"
		and cmds[3] == "道具" and cmds[4] == "逃跑", "指令集内容：攻击 / 战技 / 防御 / 道具 / 逃跑")

	# 2c) 防御存活期：到**该单位自己**下次行动开始为止。
	# 旧实现在整轮重排时对全体 clear_defend()，本轮最后行动者（防御完紧接着敌人回击）
	# 的防御会在自己回合结束的瞬间被抹掉 —— 下面第一条断言就是那个回归点。
	var slow := unit_stub(3)
	slow.is_player = true
	ctl.set_units([unit_stub(9), slow])
	ctl.begin_battle()
	check(ctl.current().agility == 9, "敏捷高的一方先攻")
	ctl.finish_turn()                      # 敌方先动 → 轮到玩家（本轮最后行动者）
	check(ctl.current() == slow, "轮到玩家（本轮最后）")
	slow.set_defend(true)                  # 玩家在本轮末尾选防御
	ctl.finish_turn()                      # 玩家行动结束 → 整轮 wrap 并重排
	check(ctl.round == 1, "整轮已重排")
	check(slow.is_defending(), "整轮重排不清防御（旧实现会在这里把防御抹掉）")
	ctl.finish_turn()                      # 敌方动完 → 又轮到玩家
	check(not slow.is_defending(), "玩家自己回合开始 → 防御失效")

	# 3) 玩家回合门闩（真实练习场场景）
	var scene: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_practice()
	scene.set_process(false)
	var player: Node = scene.player
	player.set_physics_process(false)
	player.campaign_mode = true
	player.reset()
	player.global_position = Vector3.ZERO
	player.battle_mode = true
	player.battle_turn_dir = Vector3.FORWARD
	player.battle_execute_move(1.5)
	check(player.global_position.z < -1.0, "回合移动按步进执行")
	player.battle_execute_skill("ring")
	player.battle_execute_attack()
	player.battle_mode = false

	# 3b) 白盒遭遇开战 / 收尾冒烟（回合循环在首屏即挂起等指令）
	scene.start_battle()
	await process_frame
	check(player.battle_mode == true and scene._battle_running == true, "白盒遭遇开战门闩生效")
	scene._end_battle(true)
	await process_frame
	check(player.battle_mode == false and scene._battle_running == false, "战后门闩与循环还原")

	# 3c) 回合内耗蓝不被退回（作者 09-23 报的 bug）：旧实现收尾时把开战快照 pu.mp 写回
	# player.mp，回合内花掉的蓝整笔退回；环断更彻底 —— battle_execute_skill 直调
	# _resolve_ring()，根本不扣蓝。这里不启战斗循环（免得和挂起的 _run_battle 抢状态），
	# 直接用一份作战单位验证「扣了就扣了、回蓝确实到账」。
	# 环断是范围技，命中会按 MP_ON_HIT_RATIO 回 1% 最大 MP —— 先把场上敌人挪远，
	# 否则回蓝混进账目，断言只能写成区间。测完原位放回。
	# 注意：**不要动 player.max_mp**，它会一直留在玩家身上，把后面 5b 的 mp 断言压掉。
	var parked: Array = []
	for e in root.find_children("*", "", true, false):
		if e is Node3D and (e.is_in_group("enemies") or e.is_in_group("targets")):
			parked.append([e, (e as Node3D).global_position])
			(e as Node3D).global_position = Vector3(0, 0, -400)
	player.mp = player.max_mp
	var mp_full: float = float(player.mp)
	# 环断要花 24 点蓝：max_mp 不够时这条链的断言会以「环断可以出手」失败，指不到根因
	# （智力 5 的新档 max_mp = 50 —— 够；但换套属性/装备就可能不够）。先把前提钉住。
	check(player.max_mp >= Skills.RING_MP_COST,
		"前提：max_mp %.0f 够放环断（需 %.0f）" % [player.max_mp, Skills.RING_MP_COST])
	var ctl_mp := BattleController.new()
	var p_unit := BattleUnit.from_player(player, 5)
	ctl_mp.set_units([p_unit])
	ctl_mp.begin_battle()
	var cast_ok: bool = player.battle_execute_skill("ring")
	check(cast_ok, "回合环断可以出手")
	check(is_equal_approx(float(player.mp), mp_full - Skills.RING_MP_COST), "回合环断扣蓝 24")
	check(is_equal_approx(p_unit.mp, mp_full), "作战单位不会自己扣蓝（权威在玩家实体上）")
	ctl_mp.pull_player_stats()
	check(is_equal_approx(p_unit.mp, float(player.mp)), "出手后作战单位抄到玩家当前蓝量")
	ctl_mp.finish_turn()          # 单单位 → 立即整轮 wrap，回蓝 5% 最大 MP
	ctl_mp.flush_player_mp()
	check(is_equal_approx(float(player.mp), mp_full - Skills.RING_MP_COST + p_unit.round_mp_regen()),
		"整轮回蓝 5% 落到玩家身上")
	# 收尾不再覆盖玩家蓝/血（旧实现正在这里写回快照 MP）
	player.hp = 40.0
	scene._battle_running = false
	player.battle_mode = true
	scene._end_battle(true)
	await process_frame
	check(is_equal_approx(float(player.mp), mp_full - Skills.RING_MP_COST + p_unit.round_mp_regen()),
		"收尾不退回回合内花掉的蓝")
	check(is_equal_approx(float(player.hp), 40.0), "收尾不覆盖玩家 HP")
	player.battle_mode = false
	for pair in parked:
		if is_instance_valid(pair[0]):
			(pair[0] as Node3D).global_position = pair[1]

	# 3d) 侧击/背击看**目标朝向**。旧实现拿攻击者朝向点乘 to_target（出手前刚被 _face()
	# 拧向目标），两者同向、点乘恒为 1 → 永远落进"正面"分支，侧/背击加成根本不可达。
	var attacker := Node3D.new()
	attacker.position = Vector3.ZERO
	root.add_child(attacker)
	var dummy := Node3D.new()
	dummy.position = Vector3(0, 0, -2.0)
	root.add_child(dummy)
	await process_frame
	var ua := BattleUnit.new()
	ua.node = attacker
	var ut := BattleUnit.new()
	ut.node = dummy
	dummy.rotation.y = PI            # 目标正对攻击者（forward = +Z）
	check(is_equal_approx(ctl.attack_bonus(ua, ut), 1.0), "目标正对我 → 正面无加成")
	dummy.rotation.y = PI * 0.5      # 目标侧对（forward = −X）
	check(is_equal_approx(ctl.attack_bonus(ua, ut), 1.1), "目标侧对 → 侧击 +10%")
	dummy.rotation.y = 0.0           # 目标背对（forward = −Z）
	check(is_equal_approx(ctl.attack_bonus(ua, ut), 1.25), "目标背对 → 背击 +25%")
	var pf: Vector3 = BattleController.forward_of(player)
	check(pf.length() > 0.9 and absf(pf.y) < 0.001, "forward_of 读玩家 facing 字段并拍平归一")
	attacker.queue_free()
	dummy.queue_free()

	# 4) 敌人回合步进
	var wolf := EnemyScene.instantiate()
	wolf.kind = EnemyScript.Kind.WOLF
	wolf.position = Vector3(0, 0, -5.0)
	root.add_child(wolf)
	await process_frame
	wolf.battle_driven = true
	var intent: String = wolf.battle_advance(Vector3.ZERO)
	check(intent == "接近" and wolf.global_position.z > -5.0, "敌人回合接近步进")

	# 5) 直踢 / 体力常量
	check(Skills.KICK_STAMINA_COST == 25.0 and Skills.KICK_STUN == 25.0, "KICK 常量（体力25/眩晕25）")
	check(Skills.KICK_MULTIPLIER == 1.0 and Skills.KICK_COOLDOWN == 0.9, "KICK 常量（倍率1.0/冷却0.9）")
	check(Skills.DODGE_STAMINA_COST == 30.0 and Skills.STAMINA_REGEN_PER_SECOND == 20.0, "体力常量（闪避30 / 每秒回20）")

	# 5b) 体力条：派生上限 + 直踹消耗（闪避走输入路径，靠手测）
	# 上限 = 60 + 体力×12，这里**不写死 120**（那等于假设体力=5）：本机运行时六维并非默认值
	# （这条断言原先断言 120，实测 144 → 体力 7，是条陈旧的硬编码假设）。改成与派生公式一致。
	# GameState 不能在本文件里按标识符引用（--script 模式自动加载未注册 → 编译失败），
	# 只能运行时按路径取。
	var gs: Node = root.get_node_or_null("/root/GameState")
	var attrs: Dictionary = {}
	if gs != null and gs.get("attributes") is Dictionary:
		attrs = gs.get("attributes")
	# _refresh_derived_stats 在 campaign_mode 下走 effective_attributes()（含装备/成长加成），
	# 基础属性表会低 2 点 —— 这里必须用同一条口径，否则又变成"公式对不上"的假失败。
	if bool(player.campaign_mode) and gs != null and gs.has_method("effective_attributes"):
		attrs = gs.call("effective_attributes")
	check(is_equal_approx(float(player.max_stamina), AttributesScript.max_stamina(attrs)),
		"体力上限 = 派生公式（当前体力 %d → %.0f）" % [int(attrs.get("con", 5)), float(player.max_stamina)])
	player.kick_cd = 0.0
	player.attack_cd = 0.0
	player.dodging = false
	player.battle_mode = false
	player.stamina = 100.0
	# 蓝量按 max_mp 取：写死 60 在智力 5 的新档上会超过上限（max_mp = 智力×10 = 50），
	# 造出一个游戏里不可能出现的状态。
	var mp_at_kick: float = player.max_mp
	player.mp = mp_at_kick
	player._start_kick()
	check(is_equal_approx(float(player.stamina), 75.0), "直踹消耗 25 点体力")
	# 断"没扣蓝"而不是"正好等于某个数"：命中会按 MP_ON_HIT_RATIO 回 1% 最大 MP，
	# 只要这一脚踢到人，mp 就会比设置值**高**一点。取满蓝做基准则只有"不掉"能成立。
	check(float(player.mp) >= mp_at_kick, "直踹不再消耗 MP（只涨不跌）")
	player.kick_cd = 0.0
	player.attack_cd = 0.0
	player.stamina = 10.0
	player._start_kick()
	check(is_equal_approx(float(player.stamina), 10.0), "体力不足时直踹放不出（体力未被扣）")
	player.stamina = player.max_stamina

	# 6) 遭遇圈判定（⚠️ encounter_zone 已按设计作废，这组断言待 P2 收敛时一并移除）
	var zone := EncounterZone.new()
	zone.position = Vector3.ZERO
	root.add_child(zone)
	await process_frame
	check(zone.in_radius(Vector3(7.9, 0, 0)), "圈内 7.9m 判定进入")
	check(not zone.in_radius(Vector3(8.1, 0, 0)), "圈外 8.1m 判定禁出")

	# 7) 眩晕链：平A +8 → 打满 → 停止移动 → 直踹处决
	var mob := EnemyScene.instantiate()
	mob.set("kind", EnemyScript.Kind.WOLF)
	mob.position = Vector3(0, 0, -6.0)
	root.add_child(mob)
	await process_frame
	check(not mob.is_stunned(), "小怪初始不在眩晕态")
	mob.add_stun(Skills.STUN_ON_ATTACK)
	check(is_equal_approx(float(mob.get("stun")), Skills.STUN_ON_ATTACK), "平A 命中叠 8 点眩晕")
	# 眩晕**不衰减**（作者 2026-09-22 定）：旧实现每秒衰减 20，平A 的 +8 会在 0.6 秒冷却里
	# 被扣掉 12（净亏 4），眩晕条永远打不满。这里跑 1 秒物理，值必须纹丝不动。
	for i in 20:
		mob._physics_process(0.05)
	check(is_equal_approx(float(mob.get("stun")), Skills.STUN_ON_ATTACK), "眩晕不随时间衰减（1 秒后仍是 8）")
	check(not mob.is_stunned(), "未满值不进入眩晕态")
	# 打满可行性：平A +8，13 下正好过 100。旧衰减实现下每下净亏 4，永远到不了。
	for i in 12:
		mob.add_stun(Skills.STUN_ON_ATTACK)
	check(mob.is_stunned(), "13 次平A 能把眩晕条打满")
	check(float(mob.get("stun")) <= Skills.STUN_MAX, "眩晕值被上限钳制")
	check(mob.executable(), "眩晕态即是处决窗口")
	var at_before: Vector3 = mob.global_position
	mob._physics_process(0.016)
	check(mob.global_position.distance_to(at_before) < 0.001, "眩晕态停止移动")
	mob.apply_execution()
	check(not mob.is_alive(), "直踹处决 = 击杀")

	# 8) 科尔波山之主：眩晕与回合内「接近 → 出手」
	# 注意：山之主脚本里用了 GameState 自动加载，不能在文件顶层 preload
	# （--script 模式下自动加载尚未注册），必须运行时 load。
	var boss_scene: PackedScene = load("res://scripts/combat/boss_colpo.tscn")
	var lord := boss_scene.instantiate()
	lord.position = Vector3(0, 0, -12.0)
	root.add_child(lord)
	await process_frame
	check(lord.is_alive(), "山之主初始存活")
	lord.add_stun(Skills.KICK_STUN)
	check(not lord.is_stunned(), "单次直踹不足以致晕")
	lord.add_stun(Skills.STUN_MAX)
	check(lord.is_stunned(), "山之主也会被打进眩晕态")
	lord.clear_stun()
	check(not lord.is_stunned(), "clear_stun 后恢复（进入回合制时调用）")
	lord.set("battle_driven", true)
	check(lord.battle_advance(Vector3(0, 0, 40.0)) == "接近", "回合内远离时步进接近")
	check(lord.battle_advance(lord.global_position) == "攻击", "回合内进入射程即出手")
	check(float(lord.get("battle_damage")) > 0.0, "出手伤害按阶段取招式表")

	# 9) BattleUnit 兼容两种敌人字段名（enemy.gd 的 hp_ / 山之主 的 hp）
	var u_lord := BattleUnit.from_enemy(lord)
	check(u_lord.max_hp > 0.0 and u_lord.attack_power > 0.0, "山之主也能被 BattleUnit 封装")

	# 10) 进入回合制的首轮先手权
	var ctl_first := BattleController.new()
	var me := unit_stub(3)
	me.is_player = true
	ctl_first.set_units([unit_stub(9), me])
	ctl_first.begin_battle()
	check(ctl_first.order[0].agility == 9, "常规排序按敏捷降序")
	ctl_first.begin_battle_with_player_first()
	check(ctl_first.current() == me, "进入回合制时我方先手")

	# 11) 战斗验证场：一只小怪 + 一只山之主都能生成
	var lab: Node = load("res://scenes/main/battle_lab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	await process_frame
	var lab_mob: Node = lab.get("_mob")
	var lab_boss: Node = lab.get("_boss")
	check(lab.get_node_or_null("player") != null, "验证场装了玩家")
	check(lab_mob != null and lab_mob.is_alive(), "验证场生成了小怪")
	check(lab_boss != null and lab_boss.is_alive(), "验证场生成了山之主")
	# 新手教程配置：两个训练靶都不还手、血量调高到够打满眩晕条。
	# 注意 enemy.gd 的 _ready 会按 PROFILES 覆盖 max_hp / move_speed，
	# 所以这几项必须由场景在入树之后再设 —— 这几条断言就是钉住这个顺序的。
	check(is_equal_approx(float(lab_mob.get("max_hp")), 260.0), "训练靶小怪血量 260")
	check(bool(lab_mob.get("patrol_only")), "训练靶小怪不主动攻击")
	check(is_equal_approx(float(lab_mob.get("move_speed")), 0.0), "训练靶小怪站原地（移速未被档位覆盖）")
	check(is_equal_approx(float(lab_boss.get("max_hp")), 1200.0), "训练靶山之主血量 1200")
	check(bool(lab_boss.get("passive")), "训练靶山之主不主动攻击")
	# 11b) 教学场的指令面板必须与练习场同源（原先这里自己写死"三条"，两套口径并存）。
	# 开战后玩家（进入回合制时被置顶）会停在菜单上等选择，这里读面板实际拿到的指令集。
	lab.start_battle()
	await process_frame
	await process_frame
	var lab_menu = lab.get("_battle_menu")
	var lab_cmds: Array = lab_menu.get("commands") if lab_menu != null else []
	check(lab_cmds.size() == 5 and lab_cmds.has("防御") and lab_cmds.has("逃跑"),
		"教学场指令面板含防御 / 逃跑（五条同源，实际 %d 条）" % lab_cmds.size())

	# 11c) 集成回归：**走真实回合循环**花一次蓝，钉住「整轮收尾不把花掉的蓝补回快照值」。
	# 3c) 只到单元层 —— 它自己调 pull_player_stats()，所以哪怕 _player_command 里那句同步
	# 被删掉，3c 依然全绿（它断言的是"已删掉的旧写法不再出现"，删对了就永远过，覆盖不到
	# 真正的同步点）。会退回蓝量的完整路径是：
	#   _run_battle → _player_command（出手后 pull）→ finish_turn（整轮回蓝结算在单位上）
	#   → flush_player_mp（把单位蓝抄回实体）
	# 这里用真实菜单驱动一轮，那句 pull 一被删就会看到蓝量被开战快照顶回去。
	var lab_player = lab.get_node("player")
	if lab_menu != null and lab_player != null:
		var mp_before_round: float = float(lab_player.mp)
		check(mp_before_round >= Skills.RING_MP_COST, "前提：教学场玩家开场蓝量够放环断")
		lab_menu.confirmed.emit(1)   # 指令「战技」→ 打开技能子页
		await process_frame
		lab_menu.confirmed.emit(1)   # 技能「环断」→ 扣蓝
		# 这一次 emit 里同步跑完一个完整回合（出手 → pull → finish_turn → flush），
		# 所以 mp 已经结算完毕。环断是范围技：命中的每个目标按 1% 最大 MP 回蓝（靶子最多 2 个），
		# 另外整轮 wrap 时还有 5% 回蓝 —— 两者都只加不减，故下界恰好是"扣满 24 点"。
		var mp_after_round: float = float(lab_player.mp)
		var regen_cap: float = maxf(float(lab_player.max_mp) * 0.05, 1.0) \
			+ float(lab_player.max_mp) * Skills.MP_ON_HIT_RATIO * 2.0
		check(mp_after_round >= mp_before_round - Skills.RING_MP_COST,
			"回合末蓝量不低于开战值 − 24（没有超扣/重复扣蓝）")
		check(mp_after_round <= mp_before_round - Skills.RING_MP_COST + regen_cap + 0.01,
			"回合末蓝量只由回蓝补回（上限 %.1f，实测 %.1f）" % [regen_cap, mp_after_round - (mp_before_round - Skills.RING_MP_COST)])
		# 旧缺陷的表现：收尾用开战快照覆盖 player.mp，花掉的蓝整笔退回 —— 回合末仍等于开战值。
		check(mp_after_round < mp_before_round,
			"整轮收尾没把花掉的蓝补回快照值（开战 %.1f / 回合末 %.1f）" % [mp_before_round, mp_after_round])
		# 让循环自己退出再 free：它此刻停在敌人回合的 0.55s 计时器上，
		# 直接 queue_free 会在实例已释放之后恢复那条协程。
		lab._end_battle(false, true)
		await create_timer(0.8).timeout
	lab.queue_free()

	TestEnv.cleanup(gs_env)
	print("BATTLE_FAILURES=%d" % failures)
	quit(failures)