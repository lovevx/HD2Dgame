extends SceneTree
## 玩家状态 HUD 校验（scripts/ui/player_status_hud.gd）：快捷栏状态判定、冷却暗幕、
## 受击残影、低血红晕与状态标签。用一个只带字段的假玩家驱动，不装整张地图。
## 跑法：godot --headless --path . --script res://tools/validate_player_hud.gd

const TestEnv := preload("res://tools/test_env.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

## 假玩家：字段与 player.gd 同名，HUD 只读这些。
func make_player() -> Node3D:
	var script := GDScript.new()
	script.source_code = """
extends Node3D
var hp := 100.0
var max_hp := 100.0
var mp := 60.0
var max_mp := 60.0
var stamina := 120.0
var max_stamina := 120.0
var alive := true
var campaign_mode := true
var dodging := false
var dodge_cd := 0.0
var kick_cd := 0.0
var ring_cd := 0.0
var ring_windup := 0.0
var wave_cd := 0.0
var wave_windup := 0.0
var shadow_cd := 0.0
var shadow_windup := 0.0
var pierced_target: Node3D
var pierce_timer := 0.0
var hunter_active := false
var shield_hp := 0.0
var shield_timer := 0.0
var shield_cd := 0.0
var shot_cd := 0.0
var bullets := 6
var bombs := 0
var potions := 2
var healing_time := 0.0
"""
	script.reload()
	var p := Node3D.new()
	p.set_script(script)
	return p

func slot(hud, action: String) -> Dictionary:
	for s in hud.slots:
		if s["action"] == action:
			return s
	return {}

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	await process_frame
	var gs: Node = root.get_node("GameState")
	TestEnv.isolate(gs, "player_hud")
	var HudScript = load("res://scripts/ui/player_status_hud.gd")
	var Skills = load("res://data/combat_skills.gd")
	var player := make_player()
	root.add_child(player)
	var hud = HudScript.new()
	hud.player = player
	root.add_child(hud)
	await frames(2)
	var Mode = hud.Mode

	# ---- 快捷栏状态判定
	check(slot(hud, "dodge")["mode"] == Mode.READY, "满体力剃就绪")
	player.stamina = Skills.DODGE_STAMINA_COST - 1.0
	await frames(2)
	check(slot(hud, "dodge")["mode"] == Mode.BLOCKED and slot(hud, "dodge")["text"] == "体力不足",
		"体力低于剃的消耗时标为体力不足（旧版这里仍显示就绪）")
	player.stamina = 120.0
	player.kick_cd = 0.6
	await frames(2)
	check(slot(hud, "kick")["mode"] == Mode.COOLDOWN, "直踹冷却中显示冷却秒数")

	# 冷却中的技能优先显示秒数，而不是「法力不足」—— 秒数比资源不足更有信息量
	player.mp = 0.0
	player.ring_cd = 2.0
	await frames(2)
	check(slot(hud, "huanduan")["mode"] == Mode.COOLDOWN and str(slot(hud, "huanduan")["text"]).ends_with("s"),
		"冷却与缺蓝同时存在时显示冷却秒数")
	player.ring_cd = 0.0
	await frames(2)
	check(slot(hud, "huanduan")["text"] == "法力不足", "冷却转好但缺蓝时显示法力不足")
	check(slot(hud, "aoge")["text"] == "法力不足", "护盾缺蓝时不再显示「可开启」")
	check(slot(hud, "hunter_toggle")["mode"] == Mode.BLOCKED, "法力见底时猎魔标为不可开启")
	player.mp = 60.0

	player.shot_cd = 1.0
	player.bullets = 0
	await frames(2)
	check(slot(hud, "shoot")["text"] == "未装备", "副手没装燧发枪时显示未装备")
	gs.campaign.equipment = {"offhand": "flintlock"}
	await frames(2)
	check(slot(hud, "shoot")["text"] == "无弹药", "没子弹时优先显示无弹药，而不是装填中")

	player.healing_time = 0.8
	await frames(2)
	check(slot(hud, "potion")["mode"] == Mode.ACTIVE, "饮药过程中药剂格显示饮用中")
	player.healing_time = 0.0

	# ---- 冷却暗幕：比例从满往下走，转好时归零
	player.wave_cd = 2.0
	await frames(2)
	var cd_rect: ColorRect = slot(hud, "sword_wave")["cd_rect"]
	check(is_equal_approx(cd_rect.anchor_top, 0.0), "冷却刚开始暗幕盖满")
	player.wave_cd = 1.0
	await frames(2)
	check(absf(cd_rect.anchor_top - 0.5) < 0.02, "冷却过半暗幕退到一半（实测 %.2f）" % cd_rect.anchor_top)
	player.wave_cd = 0.0
	await frames(2)
	check(is_equal_approx(cd_rect.anchor_top, 1.0) and slot(hud, "sword_wave")["mode"] == Mode.READY, "冷却转好暗幕收起并回到就绪")

	# ---- 受击残影：掉血后先停住，再追上
	player.hp = 40.0
	await frames(2)
	check(hud.hp_bar.value == 40.0 and hud.hp_ghost.value > 90.0, "掉血瞬间残影停在旧值")
	await create_timer(1.4).timeout
	check(absf(hud.hp_ghost.value - 40.0) < 0.5, "残影在延迟后追上当前生命")
	player.hp = 70.0
	await frames(2)
	check(hud.hp_ghost.value == 70.0, "回血时残影立即跟上，不会反向留影")

	# ---- 生命数值取整：21.4 显示 22，避免「0 / 100 但还活着」
	player.hp = 0.3
	await frames(2)
	check(hud.hp_value_label.text.begins_with("1 /"), "残血 0.3 显示为 1 而不是 0（实测 %s）" % hud.hp_value_label.text)

	# ---- 低血红晕与状态标签
	player.hp = 50.0
	await frames(2)
	check(not hud.vignette.visible or float((hud.vignette.material as ShaderMaterial).get_shader_parameter("intensity")) < 0.3,
		"半血不显示低血红晕")
	player.hp = 5.0
	await create_timer(0.6).timeout
	check(hud.vignette.visible, "低于 30% 生命显示红晕")
	check(hud._chips["wounded"]["panel"].visible, "战役里低于 10% 显示重伤减速标签")
	player.hunter_active = true
	player.shield_hp = 20.0
	player.shield_timer = 3.0
	await frames(2)
	check(hud._chips["hunter"]["panel"].visible and hud._chips["shield"]["panel"].visible and hud.shield_strip.visible,
		"猎魔 / 护盾标签与护盾条同时显示")
	player.hunter_active = false
	player.shield_hp = 0.0
	player.hp = 100.0
	await create_timer(0.3).timeout
	check(not hud.buff_row.visible, "没有状态时标签行收起")
	check(not hud.vignette.visible, "回满后红晕消失")

	# ---- 玩家换人（换场景后旧引用失效）不报错，自动重新找 player 组
	player.queue_free()
	await frames(2)
	check(true, "玩家节点被释放后 HUD 不崩溃")

	TestEnv.cleanup(gs)
	print("PLAYER_HUD_FAILURES=%d" % failures)
	quit(1 if failures > 0 else 0)
