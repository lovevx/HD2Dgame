extends SceneTree
## 战斗验证场实机截图：三张——开场全景 / 小怪被打进眩晕 / 山之主被打进眩晕。
## 用法（需要渲染，不要加 --headless）：
##   godot --path . --script res://tools/capture_battle_lab.gd

func _initialize() -> void:
	call_deferred("capture")

func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func capture() -> void:
	var lab = load("res://scenes/main/battle_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene = lab
	await create_timer(1.2).timeout
	await _shoot("res://docs/battle_lab.png")
	# 把摄像机推近一点，让"小怪 + 山之主"同框更清楚
	var camera: Camera3D = lab.get_node("Camera3D")
	camera.fov = 24.0
	# 小怪打满眩晕：头顶黄条 + 停止移动
	var mob: Node = lab.get("_mob")
	if mob != null and mob.is_alive():
		mob.add_stun(Skills().STUN_MAX)
	await create_timer(0.6).timeout
	await _shoot("res://docs/battle_lab_mob_stun.png")
	# 山之主打满眩晕：进入回合制的触发条件就是"再补一刀"
	var boss: Node = lab.get("_boss")
	if boss != null and boss.is_alive():
		boss.add_stun(Skills().STUN_MAX)
	await create_timer(0.6).timeout
	await _shoot("res://docs/battle_lab_boss_stun.png")
	print("BATTLE_LAB_CAPTURE_DONE")
	quit(0)

func Skills() -> GDScript:
	return load("res://data/combat_skills.gd")
