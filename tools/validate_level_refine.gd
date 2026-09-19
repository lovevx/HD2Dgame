extends SceneTree
## 关卡细化验收：四关布景差异化 + HUMAN 人形敌人模型与攻击动作 + 底部剧情条。
## 无头模式跑逻辑；D3D12 实渲染模式额外输出四关布景与敌人截图。
const EnemyScript := preload("res://scripts/combat/enemy.gd")
var failures := 0
var gs: Node
var scene: Node

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value: print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func mount() -> void:
	if is_instance_valid(scene):
		scene.free()
	scene = load("res://scenes/main/campaign.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.tmp_preview/level-%s.png" % label)

func run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	gs.save_path = "user://level_refine_validation.cfg"
	gs.reset_progress()
	gs.complete_contract("细化验收")
	var stage_names := ["junk", "gate", "hq", "street"]
	for stage in 4:
		gs.campaign.stage = stage
		gs.campaign.cleared = false
		await mount()
		# 底部剧情条：进关即显示，不冻结玩家
		check(scene.hud.story_banner != null and scene.hud.story_banner.visible, "剧情条进关显示 stage%d" % stage)
		check(scene.hud.story_banner.visible and not scene.player.is_physics_processing() == false, "剧情条不冻结玩家 stage%d" % stage)
		check(scene.state == "prepare", "剧情条阶段仍处准备态 stage%d" % stage)
		# 布景：正式关卡的装饰 prop 比试炼场多（试炼场约 2 处装饰差异下限）
		var props := 0
		for child in scene.world.get_children():
			if child is HD2DProp: props += 1
		check(props >= 8, "布景道具已摆放（%d 个）stage%d" % [props, stage])
		# 传送门：入口视觉 + 出口 Area3D（走进切下一关）
		var exit_portal: Node = scene.world.get_node_or_null("ExitPortal")
		check(exit_portal != null, "北侧出口传送门已生成 stage%d" % stage)
		if exit_portal != null:
			check(exit_portal.campaign_action.is_valid(), "出口传送门已接推进逻辑 stage%d" % stage)
			var entrance: Node = scene.world.get_node_or_null("EntrancePortal")
			check(entrance != null, "南侧入口传送门已生成 stage%d" % stage)
		# 地面差异化：每关砖色不同，且不同于默认试炼石板
		var mat: ShaderMaterial = scene.world.get_node("ground/MeshInstance3D").material_override
		var ground_color: Color = mat.get_shader_parameter("stone_color")
		check(ground_color != Color("3a4a52"), "地面砖色已差异化（%s）stage%d" % [ground_color.to_html(false), stage])
		scene.start_encounter()
		check(scene.state == "combat", "V 开始遭遇后进入战斗 stage%d" % stage)
		# HUMAN 敌人：模型骨架 + 持武器右臂 + 能量核
		var first: Node = scene.enemies[0]
		check(first.kind == EnemyScript.Kind.HUMAN, "人形敌人类型 stage%d" % stage)
		check(first.body_root != null and first.body_root.get_child_count() >= 8, "人形白盒模型零件 ≥8 stage%d" % stage)
		check(first._arm_weapon != null and first._arm_weapon.get_child_count() >= 3, "持武器右臂（臂+刃+柄）stage%d" % stage)
		check(first.has_energy and first.get_node_or_null("EnergyCore") != null, "人形敌人带能量核 stage%d" % stage)
		# 攻击动作：前摇抬臂 / 出手挥臂，角度确实变化
		# 模拟 _physics_process 顺序：先减 windup 再 _animate_arm
		first.player = scene.player
		first.attack_windup = 0.6
		first.windup = 0.6
		first.windup -= 0.5   # 前摇推进到尾声
		first._animate_arm(0.01)
		var raised: float = first._arm_weapon.rotation_degrees.x
		check(raised < -20, "前摇举刀过头（%.0f°）stage%d" % [raised, stage])
		first.windup = -1
		first._strike_timer = 0.22
		first._animate_arm(0.15)  # 挥击前半程，手臂应劈向身前
		var swing: float = first._arm_weapon.rotation_degrees.x
		check(swing > raised + 30, "出手挥臂向下（%.0f°）stage%d" % [swing, stage])
		# 敌人命名与模型档位对应
		var model: String = str(first.model)
		var expected: String = [["vagrant"], ["carlos"], ["instructor"], ["oka", "guard"]][stage][0]
		check(model == expected, "模型档位正确 %s stage%d" % [model, stage])
		# 一键收剧情条（模拟按任意操作）
		scene.hud.story_banner.show()
		scene.player.set_physics_process(true)
		scene.hud.hide_story()
		check(not scene.hud.story_banner.visible, "剧情条可收起 stage%d" % stage)
		await capture(stage_names[stage])
	gs.campaign.stage = 4
	gs.campaign.cleared = false
	gs.campaign.colpo_outer_cleared = false
	await mount()
	check(scene.hud.story_banner.visible, "科尔波山外围进关剧情条")
	await capture("outer")
	print("LEVEL_REFINE_FAILURES=", failures)
	quit(1 if failures else 0)
