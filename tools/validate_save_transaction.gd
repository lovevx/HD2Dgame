extends SceneTree
## 出击结算事务 + 存档可靠性回归。
##
## 覆盖的缺陷（2026-09-23）：死亡面板宣称「未提交的消耗与收益回滚」，但装备拾取、
## 场景宝箱与耐久损耗都即时 save_game()，于是死亡重试保留战利品却不还原耐久；
## 同时存档是单文件直接覆盖，没有版本号、备份档与原子替换。
##
## 三条不变量：
##   1. 本局未提交的拾取与耐久损耗，在任何非正常撤离路径下都不落盘、并整体回滚；
##   2. 显式 save_game()（检查点 / 领取战利品 / 开箱 / 换装 / 乐园消费）= 提交点，
##      提交过的内容之后回滚不动；
##   3. 正式档永远是完整的一代：写临时档 + rename 原子替换 + .bak 回退。
## 运行：godot --headless --path . --script res://tools/validate_save_transaction.gd
var failures := 0
var gs: Node
var scene: Node
var SAVE := "user://save_transaction_validation.cfg"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func _cleanup() -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var path := ProjectSettings.globalize_path(gs.save_path + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func mount() -> void:
	if is_instance_valid(scene):
		scene.free()
	scene = load("res://scenes/main/campaign.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame

## 玩家数值不变量：耐久当前值（走游戏内同一读取口径）。
func dura(id: String) -> float:
	return float(gs.Campaign.dura_state(gs.campaign, id)["cur"])

func dura_max(id: String) -> float:
	return float(gs.Campaign.dura_state(gs.campaign, id)["max"])

## 读一份存档文件的字段（不改变 GameState）。
func read_save(path: String, key: String, fallback) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return fallback
	return cfg.get_value("progress", key, fallback)

func run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	gs.save_path = SAVE
	_cleanup()

	# ---------------------------------------------------------------- 本局事务
	print("---- 出击事务 ----")
	gs.reset_progress()
	gs.complete_contract("验证事务")
	check(not gs.is_sortie_active(), "灰潮港等非战斗场景没有本局会话")
	check(not gs.rollback_sortie(), "无本局时回滚是空操作")

	gs.begin_sortie()
	check(gs.is_sortie_active() and not gs.is_sortie_dirty(), "开局基线干净")
	var knife_max := dura_max("knife")
	gs.damage_item_dura("knife", 2.0)
	gs.give_item("worn_blade", 1)
	check(gs.is_sortie_dirty(), "战斗中扣耐久与拾取都记为未提交")
	check(dura("knife") < knife_max, "耐久确实掉了")

	gs.settle_sortie(gs.Sortie.DEATH)
	check(is_equal_approx(dura("knife"), knife_max), "死亡回滚战斗中扣掉的耐久（原缺陷：耐久被即时落盘）")
	check(gs.item_count("worn_blade") == 0, "死亡回滚途中拾取（原缺陷：拾取被即时落盘）")
	check(not gs.is_sortie_dirty(), "回滚后回到干净基线")

	# 反复阵亡不能囤积：这是「未提交收益回滚」要挡住的刷装备循环。
	var loop_ok := true
	for i in 2:
		gs.begin_sortie()
		gs.give_item("worn_blade", 1)
		gs.settle_sortie(gs.Sortie.DEATH)
		if gs.item_count("worn_blade") != 0:
			loop_ok = false
	check(loop_ok, "连续阵亡重试不累积途中拾取")

	# 提交过的内容回滚不动：显式落盘就是提交点。
	gs.begin_sortie()
	gs.damage_item_dura("knife", 3.0)
	gs.save_game()  # 检查点提交
	check(not gs.is_sortie_dirty(), "显式落盘清空未提交标记")
	var committed_dura := dura("knife")
	gs.settle_sortie(gs.Sortie.DEATH)
	check(is_equal_approx(dura("knife"), committed_dura), "已提交的耐久损耗在之后阵亡时保留")
	# 主动放弃（退主菜单/关窗）与战死同口径，不能靠退出蒙混提交。
	gs.begin_sortie()
	gs.give_item("worn_blade", 1)
	gs.settle_sortie(gs.Sortie.ABANDON)
	check(gs.item_count("worn_blade") == 0, "放弃出击同样回滚未提交拾取")
	check(gs.settle_sortie(gs.Sortie.NORMAL) == true, "正常撤离走同一条事务")
	gs.end_sortie()
	check(not gs.is_sortie_active(), "离场后本局会话结束")
	check(gs.settle_sortie(gs.Sortie.NORMAL) == false, "非战斗场景调用结算事务是空操作")

	# 场景宝箱是显式提交点：开箱产出与开启记录都提交，开箱后的拾取仍算未提交。
	gs.begin_sortie()
	gs.open_scene_chest("tx_commit_chest")
	check(gs.is_sortie_dirty() == false, "开箱是提交点")
	check(gs.item_count("potion") == 3, "宝箱产出已入库")
	# 宝箱的随机装备可能正好是 worn_blade，所以比增量而不是比绝对值。
	var blades_before: int = gs.item_count("worn_blade")
	gs.give_item("worn_blade", 1)
	check(gs.item_count("worn_blade") == blades_before + 1, "提交点之后的拾取先记入背包")
	gs.settle_sortie(gs.Sortie.DEATH)
	check(gs.is_scene_chest_opened("tx_commit_chest"), "已提交的宝箱开启记录保留")
	check(gs.item_count("potion") == 3, "已提交的宝箱产出保留")
	check(gs.item_count("worn_blade") == blades_before, "提交点之后的拾取仍会回滚")
	gs.end_sortie()

	# ---------------------------------------------------------------- 存档可靠性
	print("---- 存档版本 / 备份 / 原子写 ----")
	_cleanup()
	gs.reset_progress()
	gs.complete_contract("第一代")
	check(FileAccess.file_exists(gs.save_path), "首次落盘生成正式档")
	check(not FileAccess.file_exists(gs.save_path + ".tmp"), "原子替换后不留临时档")
	check(int(read_save(gs.save_path, "version", 0)) == gs.SAVE_VERSION, "存档写入格式版本号")
	check(read_save(gs.save_path, "player_name", "") == "第一代", "正式档内容可读")

	gs.coins = 111
	gs.save_game()
	gs.coins = 222
	gs.save_game()
	check(FileAccess.file_exists(gs.save_path + ".bak"), "第二次落盘留下备份档")
	check(read_save(gs.save_path + ".bak", "coins", -1) == 111, "备份档是上一代内容")
	check(read_save(gs.save_path, "coins", -1) == 222, "正式档是最新一代")

	# 坏档恢复：正式档被写坏时回退备份（读回上一代的 111），而不是整档归零。
	# 三种坏法都要挡住：写一半掉电被截断（ConfigFile 直接报错）、只剩段头的空壳、
	# 纯垃圾 —— 后两种 ConfigFile 不报错却读不出任何东西，最阴，会把姓名与
	# 乐园币静默清空，看起来就像「进度没了」。
	for broken in ["[progress]\n\ncampaign={\"stage\": 0, \"bag\": {\"knife\":\n", "[progress]\n", "<<< truncated garbage\n", ""]:
		var bad := FileAccess.open(gs.save_path, FileAccess.WRITE)
		bad.store_string(broken)
		bad.close()
		check(not gs._is_valid_save(gs.save_path), "坏档能被识别：%s" % broken.substr(0, 24).strip_edges())
		gs.coins = 0
		gs.player_name = ""
		gs.load_game()
		check(gs.coins == 111 and gs.player_name == "第一代", "坏档回退备份读回上一代进度")
		# 再次落盘不能把坏档复制成备份，否则会顶掉唯一一份好档。
		gs.save_game()
		check(gs._is_valid_save(gs.save_path + ".bak"), "坏档情况下备份档仍可解析")
		check(read_save(gs.save_path + ".bak", "player_name", "") == "第一代", "坏档情况下备份档内容未被顶掉")
		check(int(read_save(gs.save_path, "coins", -1)) == 111, "坏档后重新落盘写回正式档")

	# ---------------------------------------------------------------- 场景端到端
	print("---- 场景端到端：拾取 + 扣耐久 -> 阵亡 -> 重试 ----")
	gs.end_sortie()
	gs.reset_progress()
	gs.complete_contract("验证事务")
	await mount()
	check(scene.location == "arena" and gs.is_sortie_active(), "进入战斗区域自动开启本局会话")
	scene.start_encounter()
	var enemy: Node = scene.enemies[0]
	scene.player.global_position = enemy.global_position + Vector3(0, 0, 2)
	scene.player.facing = Vector3.FORWARD
	enemy.attack_cd = 10
	scene._spawn_equipment_drop(enemy, 1.0)  # 100% 掉落，避免随机性
	var drops := get_nodes_in_group("equipment_drop")
	check(drops.size() == 1, "击杀掉落生成拾取物")
	var drop_id := str(drops[0].item_id)
	drops[0]._collect()
	check(gs.item_count(drop_id) == 1, "走近拾取进入背包")

	var fight_max := dura_max("knife")
	enemy.hp_ = 1.0
	scene.player._hurt_in_cone(3, 12)
	check(not enemy.is_alive(), "玩家近战击杀目标")
	check(dura("knife") < fight_max, "击杀真实扣除主武器耐久（走 player.gd 战斗路径）")
	var after_fight := dura("knife")

	scene.player.potions = 0
	scene.player.take_damage(999)
	check(scene.state == "dead", "阵亡进入重试状态")
	check(gs.item_count(drop_id) == 0, "阵亡回滚本局拾取的装备")
	check(is_equal_approx(dura("knife"), fight_max), "阵亡回滚战斗中扣掉的耐久")
	check(not gs.is_sortie_dirty(), "阵亡后没有残留的未提交状态")
	var body := str(scene.hud.panel_body.text)
	check(body.contains("回滚"), "阵亡面板如实说明已回滚")
	check(body.contains("宝箱"), "阵亡面板说明已提交部分保留")

	await mount()
	check(scene.state == "prepare" and scene.player.alive, "重试回到准备状态")
	check(scene.player.potions == 2, "重试回滚本局消耗的血药")
	check(is_equal_approx(dura("knife"), fight_max), "重试时耐久是满的")
	check(gs.item_count(drop_id) == 0, "重试时未提交掉落不在背包")
	check(scene.player.attack_damage > 0 and not is_equal_approx(after_fight, fight_max), "战斗确实产生过耐久损耗（断言前提成立）")

	# 已提交的宝箱在死亡重试后仍保留：确认提交点与回滚点不会互相污染。
	check(gs.is_scene_chest_opened("arena_0") == false, "未开箱时记录为空")
	gs.begin_sortie()
	gs.open_scene_chest("arena_0")
	gs.give_item("worn_blade", 1)
	gs.settle_sortie(gs.Sortie.DEATH)
	check(gs.is_scene_chest_opened("arena_0"), "阵亡不回滚已提交的宝箱开启记录")
	check(gs.item_count("worn_blade") == 0, "同一局里未提交的拾取照样回滚")

	if is_instance_valid(scene):
		scene.free()
		scene = null
	gs.end_sortie()
	gs.persistence_enabled = false
	_cleanup()
	print("SAVE_TRANSACTION_FAILURES=", failures)
	quit(1 if failures else 0)
