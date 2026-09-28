extends SceneTree
## 任务面板校验：数据层（data/quest_log.gd 各种存档状态 → 任务表）与面板层
## （HUD J 键开关、列表/详情内容、模态冻结、键位绑定）两段。
## 跑法：godot --headless --path . --script res://tools/validate_quest_panel.gd

var failures := 0
var gs: Node
var scene: Node
var QuestLog
var Data

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

## 面板子树里所有 Label / Button 的文字拼起来，用来断言详情确实渲染出来了。
func texts(node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += child.text + "\n"
		elif child is Button:
			out += child.text + "\n"
		out += texts(child)
	return out

func rows(panel) -> Array:
	var out: Array = []
	for child in panel._list.get_children():
		if child is Button:
			out.append(child)
	return out

func stats(campaign: Dictionary) -> Dictionary:
	var out := {}
	for entry in QuestLog.entries(campaign):
		out[str(entry["id"])] = str(entry["status"])
	return out

func run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	QuestLog = preload("res://data/quest_log.gd")
	Data = preload("res://data/campaign.gd")
	gs.save_path = "user://quest_panel_validation.cfg"

	# ---------- 数据层：序章（船到港） ----------
	gs.reset_progress()
	gs.complete_contract("任务面板验收")
	gs.begin_onboarding()
	var c: Dictionary = gs.campaign
	var s := stats(c)
	check(s["ep_arrive"] == QuestLog.ACTIVE, "船到港：序章第 1 步进行中")
	check(s["ep_training"] == QuestLog.LOCKED and s["ep_accept"] == QuestLog.LOCKED, "船到港：后续序章步骤未解锁")
	check(s["stage_0"] == QuestLog.LOCKED, "船到港：主线未接取时压成未解锁")
	check(QuestLog.default_id(c) == "ep_arrive", "默认选中当前进行中的任务")
	# 教学目标里的键名必须现读（2026-09-23 修：原先写死「Shift」，而剃默认在空格 ——
	# 那不是「文案不好」，是玩家照着按不出教学要求的那一下）。
	var KeyBindings = preload("res://scripts/ui/key_bindings.gd")
	var dodge_key: String = KeyBindings.key_text("dodge")
	check(_objs(c, "ep_training").has("使用一次剃（%s）" % dodge_key),
		"教学目标按当前键位写剃（当前 %s）" % dodge_key)
	check(not "Shift" in " ".join(_objs(c, "ep_training")), "教学目标里不再残留写死的 Shift")

	# ---------- 数据层：教学完成待接任务 ----------
	c.flow = "equipped"
	c.training_done = true
	s = stats(c)
	check(s["ep_arrive"] == QuestLog.DONE and s["ep_training"] == QuestLog.DONE, "教学完成后序章前两步已完成")
	check(s["ep_accept"] == QuestLog.ACTIVE, "待接任务：第 3 步进行中")
	check(s["stage_0"] == QuestLog.LOCKED, "待接任务：主线仍未解锁")

	# ---------- 数据层：接取后出发 ----------
	c.flow = "quested"
	s = stats(c)
	check(s["stage_0"] == QuestLog.ACTIVE, "接取任务后 1.2 进入进行中")
	check(s["stage_1"] == QuestLog.LOCKED, "1.3 尚未解锁")
	check(_objs(c, "stage_0").has("在码头与港口向导对话") == false, "主线目标不混入序章条目")

	# ---------- 数据层：1.4 清场待离场 ----------
	c.flow = "trial"
	c.stage = 2
	c.cleared = true
	c.kills = ["0_0", "1_0", "2_0"]
	c.bag = {"letter": 1, "dragon": 1}
	c.equipment = {"main_weapon": "dragon"}
	c.opened_chests = ["arena_0"]
	s = stats(c)
	check(s["stage_0"] == QuestLog.DONE and s["stage_1"] == QuestLog.DONE, "走过的地区标记已完成")
	check(s["stage_2"] == QuestLog.PENDING, "已清场待离场的地区标记待交接")
	check(s["stage_3"] == QuestLog.LOCKED and s["stage_4"] == QuestLog.LOCKED, "未到达的地区标记未解锁")
	check(_obj_done(c, "stage_2", "装备斩龙闪并完成技能练习后前往北侧出口") == false, "待交接地区仍留着未完成目标")
	check(_obj_done(c, "stage_2", "取得斩龙闪") == true, "已装备的斩龙闪判定为取得")
	check(_obj_done(c, "side_chest", "1.2 废品终点站补给箱") == true, "开过的补给箱打勾")
	check(_obj_done(c, "side_chest", "1.3 王都入口补给箱") == false, "没开过的补给箱不打勾")
	check(_records(c, "stage_2").size() == 2, "当前地区显示本轮世界之源与噬灵者法力")
	check(QuestLog.default_id(c) == "stage_2", "支线进行中时默认仍选当前主线")

	# ---------- 数据层：科尔波山决战中 / 结算回港 ----------
	c.stage = 4
	c.cleared = false
	c.kills = ["0_0", "1_0", "2_0", "3_0", "3_1", "tiger"]
	c.colpo_outer_cleared = true
	c.bag = {"tiger_tooth": 1, "claw": 1}
	s = stats(c)
	var main_ids: Array[String] = []
	for entry in QuestLog.entries(c):
		if entry["kind"] == "主线": main_ids.append(str(entry["id"]))
	check(not main_ids.has("skill_training"), "主线不再列欢乐街后的必经技能教学")
	check(s["stage_4"] == QuestLog.ACTIVE, "决战进行中")
	check(_obj_done(c, "stage_4", "清理外围三波威胁") == true, "外围清完打勾")
	check(_obj_done(c, "stage_4", "预埋一枚陷阱引出巨虎") == false, "猎虎核心练习未完成时留在任务目标中")
	c.tutorial_steps = {"trap": true}
	check(_obj_done(c, "stage_4", "预埋一枚陷阱引出巨虎") == true, "已预埋陷阱后任务目标打勾")
	check(_obj_done(c, "stage_4", "猎杀科尔波山巨虎") == true, "巨虎已猎杀打勾")
	check(s["side_tiger"] == QuestLog.ACTIVE, "虎齿到手后支线进行中（交付未开放）")
	check(_obj_done(c, "side_tiger", "交付左大臣的藏品（后续版本开放）") == false, "未开放的交付目标不打勾")
	c.hub = true
	c.settled = true
	c.source = 9.2
	c.report = "阶段试炼评价 A · 世界之源 9.2%\n属性点 +2 · 乐园币 +1200 · 奖励倍率 ×1"
	s = stats(c)
	check(s["stage_4"] == QuestLog.DONE, "结算回港后主线全完成")
	check(s.has("rec_settle"), "结算后出现阶段试炼结算条目")
	check(QuestLog.find("rec_settle", c)["records"].size() == 2, "结算条目按行拆出报告")
	check(_records(c, "stage_4").is_empty(), "回港后不再显示本轮进度行")

	# ---------- 面板层：灰潮港 HUD 里开面板 ----------
	gs.reset_progress()
	gs.complete_contract("任务面板验收")
	gs.begin_onboarding()
	scene = load("res://scenes/main/campaign.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var hud = scene.hud
	var panel = hud.quest_panel
	check(panel != null and panel.is_in_group("quest_panel"), "HUD 里挂上了任务面板")
	check(not panel.visible and not hud.is_modal_open(), "默认收起，不算模态")
	hud.open_quest_log()
	check(panel.visible and hud.is_modal_open(), "J 打开后是模态面板")
	check(not scene.player.is_physics_processing(), "打开时冻结玩家（战役控制器接管）")
	var expected: int = QuestLog.entries(gs.campaign).size()
	check(rows(panel).size() == expected, "左侧列表按任务数铺满（%d 行）" % expected)
	check(panel._selected_id == "ep_arrive", "默认选中当前序章任务")
	check(panel._detail_title.text == "船靠岸 · 抵达灰潮港", "右侧标题 = 选中任务名")
	check(panel._detail_status.text == "进行中", "右侧状态 = 进行中")
	check(texts(panel._detail_body).contains("在码头与港口向导对话"), "目标清单渲染出来了")
	check(panel._summary.text.contains("已完成"), "底栏有完成度汇总")
	panel._select("ep_training")
	check(panel._detail_title.text == "演武场 · 新手教学", "点选左侧行切换详情")
	check(panel._detail_status.text == "未解锁", "未解锁任务的状态文案")
	check(texts(panel._detail_body).contains("在演武场命中练功木桩 ×3"), "未解锁任务的目标清单可见")
	hud.close_quest_log()
	check(not panel.visible and not hud.is_modal_open(), "关闭后退出模态")
	check(scene.player.is_physics_processing(), "关闭后恢复玩家物理")
	hud.toggle_quest_log()
	check(panel.visible, "toggle 再开一次")
	hud.toggle_quest_log()
	check(not panel.visible, "toggle 再关一次")
	check(InputMap.has_action("quest_log"), "输入映射里有 quest_log")
	var events := InputMap.action_get_events("quest_log")
	var key_ok := events.size() == 1 and events[0] is InputEventKey and (events[0] as InputEventKey).physical_keycode == KEY_J
	check(key_ok, "quest_log 绑在 J 键")

	# ---------- 机位输入：面板开着时不吃滚轮 / 中键（滚轮留给面板自己滚动） ----------
	var orbit = scene.world._orbit
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	var middle_up := InputEventMouseButton.new()
	middle_up.button_index = MOUSE_BUTTON_MIDDLE
	middle_up.pressed = false
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(40, 0)
	var dist_before: float = orbit.distance
	var yaw_before: float = orbit.yaw_deg
	hud.open_quest_log()
	scene.world._input(wheel)
	check(is_equal_approx(orbit.distance, dist_before), "面板开着时滚轮不推拉镜头")
	scene.world._input(middle)
	scene.world._input(drag)
	check(is_equal_approx(orbit.yaw_deg, yaw_before), "面板开着时中键拖动不转视角")
	scene.world._input(middle_up)
	check(not orbit.dragging, "面板开着时松开中键会清掉拖动状态")
	hud.close_quest_log()
	scene.world._input(wheel)
	check(orbit.distance < dist_before, "关掉面板后滚轮恢复推拉镜头")
	scene.world._input(middle)
	scene.world._input(drag)
	check(not is_equal_approx(orbit.yaw_deg, yaw_before), "关掉面板后中键拖动恢复转视角")
	scene.world._input(middle_up)

	# ---------- 面板层：底栏动作位（灰潮港委托所接取任务走它） ----------
	var fired := [false]
	panel.open("接取任务 · 验收用", func(): fired[0] = true)
	check(panel.visible and panel._action_button.visible, "带动作打开时底栏出现动作按钮")
	panel._action_button.pressed.emit()
	check(fired[0] and not panel.visible and not hud.is_modal_open(), "动作按钮触发回调并收起面板")
	panel.open()
	check(not panel._action_button.visible, "只读打开时不出现动作按钮")
	panel.close()

	# ---------- 接口层：灰潮港「港务委托所」V → 任务档案（待接任务时给接取按钮） ----------
	gs.campaign.flow = "equipped"
	scene.world.get_node("QuestService").campaign_action.call()
	check(panel.visible and panel._action_button.visible, "委托所 V 打开任务档案并给出接取按钮")
	panel._action_button.pressed.emit()
	check(gs.campaign.flow == "quested", "委托所接取任务真的推进流程")
	check(not panel.visible, "接取后面板收起")

	# ---------- 面板层：切到 1.4 清场待离场，列表与默认选中同步 ----------
	gs.campaign.flow = "trial"
	gs.campaign.stage = 2
	gs.campaign.cleared = true
	gs.campaign.kills = ["0_0", "1_0", "2_0"]
	gs.campaign.bag = {"letter": 1, "dragon": 1}
	gs.campaign.equipment = {"main_weapon": "dragon"}
	hud.open_quest_log()
	check(panel._selected_id == "ep_training", "重开保留上次选中的任务，不自己跳走")
	panel._selected_id = ""
	hud.open_quest_log()
	check(panel._selected_id == "stage_2", "没有上次选中时默认落在当前地区")
	check(panel._detail_status.text == "待交接", "当前地区已清场 = 待交接")
	check(texts(panel._detail_body).contains("本轮世界之源"), "当前地区显示本轮进度行")
	scene._refresh_objective()
	check(scene.hud.objective.text.contains("J 任务档案"), "主城目标栏提示 J 任务档案")
	var list_text := texts(panel._list)
	check(list_text.contains("■ 1.2 废品终点站") and list_text.contains("□ 1.6 科尔波山"),
		"列表行带状态方块（已完成 / 未解锁）")
	hud.close_quest_log()

	# ---------- 面板层：直接开灰潮港（无战役控制器）时面板自己冻结玩家 ----------
	scene.free()
	await process_frame
	var harbor = load("res://scenes/world/harbor.tscn").instantiate()
	root.add_child(harbor)
	current_scene = harbor
	await process_frame
	var hud2 = harbor.get_node("HUD")
	var player2 = harbor.get_node("Player")
	hud2.open_quest_log()
	check(hud2.quest_panel.visible and hud2.is_modal_open(), "无战役控制器时也能开面板")
	check(not player2.is_physics_processing(), "无战役控制器时面板自己冻结玩家")
	hud2.close_quest_log()
	check(player2.is_physics_processing(), "关闭后玩家恢复物理")
	# 轮回商店开着时不叠面板（两个模态会抢同一只鼠标）
	var shop = harbor.get_node("ShopPanel")
	shop.open()
	var key := InputEventAction.new()
	key.action = "quest_log"
	key.pressed = true
	hud2._unhandled_input(key)
	check(not hud2.quest_panel.visible, "商店开着时按 J 不叠任务面板")
	shop.close()
	# 直接开主城（无战役控制器）时，委托所的 panel_handler 也接到同一块面板
	var quest_service = harbor.get_node("QuestService")
	check(quest_service.panel_handler.is_valid(), "非战役主城的委托所已接线")
	quest_service.panel_handler.call()
	check(hud2.quest_panel.visible and hud2.is_modal_open(), "非战役主城委托所 V 也开任务档案")
	hud2.close_quest_log()
	check(hud2.objective.text.contains("J 任务档案"), "非战役主城目标栏提示 J 任务档案")

	print("----------------------------------------")
	if failures == 0:
		print("任务面板校验：全部 PASS")
	else:
		print("任务面板校验：%d 项 FAIL" % failures)
	quit(1 if failures > 0 else 0)

## 取某任务的目标文案清单（断言用）。
func _objs(c: Dictionary, id: String) -> Array:
	var out: Array = []
	for obj in QuestLog.find(id, c)["objectives"]:
		out.append(str(obj["text"]))
	return out

func _obj_done(c: Dictionary, id: String, text: String) -> bool:
	for obj in QuestLog.find(id, c)["objectives"]:
		if str(obj["text"]) == text:
			return bool(obj["done"])
	push_error("找不到目标：" + id + " / " + text)
	return false

func _records(c: Dictionary, id: String) -> Array:
	return QuestLog.find(id, c)["records"]
