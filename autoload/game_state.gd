extends Node
## 全局游戏状态：契约者、阶段试炼、背包/装备、永久成长与场景过场。
## 存档：单槽位 user://save.cfg；已提交检查点与乐园操作自动落盘，
## 退出游戏兜底保存；主菜单据 player_name 是否为空决定是否显示「继续游戏」。
const Attributes := preload("res://data/attributes.gd")
const Campaign := preload("res://data/campaign.gd")
const Equip := preload("res://data/equip_tables.gd")
## 成长武器品质晋升顺序（斩龙闪）
const TIER_ORDER := ["white", "green", "blue", "purple", "gold_light"]
var campaign: Dictionary = Campaign.fresh()
## 验证脚本可禁用写盘，避免污染真实存档。
var persistence_enabled := true
var campaign_practice := false # 临时自由练习，不写入正式进度。

signal message(text)          # 蓝色乐园提示文本
signal coins_changed(value)   # 乐园币数量变化
signal attributes_changed     # 六维属性或属性点变化（HUD/玩家派生值刷新用）

const LEVEL_SELECT_SCENE := "res://scenes/main/level_select.tscn"
const MAIN_MENU_SCENE := "res://scenes/main/main_menu.tscn"
const OPENING_SCENE := "res://scenes/main/opening.tscn"
const HARBOR_SCENE := "res://scenes/world/harbor.tscn"

## 契约者默认名（原著主角），开场取名留空时回退到它。
const DEFAULT_PLAYER_NAME := "苏晓"
const SAVE_PATH := "user://save.cfg"
var save_path := SAVE_PATH

## 契约者姓名：档案是否成立以它为准（空串 = 还没建档）。
var player_name: String = ""

var coins: int = 0
## 六维属性：str/agi/con/int/cha/luk，见 data/attributes.gd。
var attributes: Dictionary = Attributes.defaults()
## 永久属性点：由阶段评价发放，仅力量/敏捷/体力/智力可分配。
var attr_points: int = 0
var _transitioning := false

func _ready() -> void:
	load_game()

## 是否已有可继续的进度（建档即视为有进度）。
func has_progress() -> bool:
	return player_name != ""

## 开新档：清空进度并立即落盘（主菜单「开始新游戏」按下时调用）。
func reset_progress() -> void:
	player_name = ""
	coins = 0
	attributes = Attributes.defaults()
	attr_points = 0
	campaign = Campaign.fresh()
	campaign_practice = false
	attributes = Campaign.BASE_STATS.duplicate()
	save_game()

## 开场确认姓名后调用：写入并落盘，返回最终登记的姓名。
func complete_contract(raw: String) -> String:
	var n := raw.strip_edges()
	player_name = n if n != "" else DEFAULT_PLAYER_NAME
	save_game()
	return player_name

func add_coins(n: int) -> void:
	coins += n
	coins_changed.emit(coins)
	save_game()
	push_message("[乐园] 获得 %d 乐园币" % n)

func push_message(text: String) -> void:
	message.emit(text)

## 六维属性值（缺键时返回起始基准）。
func get_attribute(key: String) -> int:
	return int(attributes.get(key, Attributes.BASE))

func get_attr_points() -> int:
	return attr_points

## 测试/结算发放属性点，成功落盘并发信号。
func grant_attr_points(n: int) -> void:
	if n <= 0:
		return
	attr_points += n
	save_game()
	attributes_changed.emit()

## 分配 1 点属性到指定维度。仅力量/敏捷/体力/智力可投，点数不足或非法维度返回 false。
func spend_attr_point(key: String, delta: int = 1) -> bool:
	if not Attributes.is_spendable(key) or attr_points < delta or delta <= 0:
		return false
	attributes[key] = int(attributes.get(key, Attributes.BASE)) + delta
	attr_points -= delta
	save_game()
	attributes_changed.emit()
	push_message("属性分配至【%s】" % Attributes.CN_NAMES.get(key, key))
	return true

func is_transitioning() -> bool:
	return _transitioning

func save_game() -> void:
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "campaign", campaign)
	cfg.set_value("progress", "player_name", player_name)
	cfg.set_value("progress", "coins", coins)
	cfg.set_value("progress", "attributes", attributes)
	cfg.set_value("progress", "attr_points", attr_points)
	var error := cfg.save(save_path)
	if error != OK:
		push_error("存档写入失败：%s" % error_string(error))

func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return
	player_name = str(cfg.get_value("progress", "player_name", ""))
	coins = int(cfg.get_value("progress", "coins", 0))
	# 旧档缺属性字段用默认六维兜底合并，attr_points 缺省为 0。
	attributes = Attributes.merged(cfg.get_value("progress", "attributes", {}))
	attr_points = int(cfg.get_value("progress", "attr_points", 0))
	campaign = Campaign.fresh()
	var saved = cfg.get_value("progress", "campaign", {})
	if saved is Dictionary:
		campaign.merge(saved, true)
	# 旧档迁移：8 槽时代的 weapon 键 → 新 11 槽 main_weapon
	if campaign.equipment.has("weapon") and not campaign.equipment.has("main_weapon"):
		campaign.equipment["main_weapon"] = campaign.equipment["weapon"]
		campaign.equipment.erase("weapon")
	if not cfg.has_section_key("progress", "campaign"):
		attributes = Campaign.BASE_STATS.duplicate()
	campaign.stage = clampi(int(campaign.stage), 0, Campaign.STAGES.size() - 1)

func effective_attributes() -> Dictionary:
	## 作战六维 = 裸装 + 已穿戴装备词条（通用聚合，替换原项坠硬编码特例）。
	var result := attributes.duplicate()
	for slot in campaign.equipment:
		var id: String = str(campaign.equipment[slot])
		var def := item_def(id)
		for key in def.get("stats", {}):
			result[key] = int(result.get(key, Attributes.BASE)) + int(def["stats"][key])
	return result

func item_count(id: String) -> int:
	return int(campaign.bag.get(id, 0))

func give_item(id: String, count: int) -> void:
	campaign.bag[id] = maxi(0, item_count(id) + count)

## 物品定义读取（含成长晋升后的覆盖层）：Campaign.ITEMS 为不可变 const，
## 成长改动写入 campaign.item_upgrade，读取一律走本函数保证口径一致。
func item_def(id: String) -> Dictionary:
	var base: Dictionary = Campaign.ITEMS.get(id, {})
	if base.is_empty():
		return {}
	var over: Dictionary = campaign.get("item_upgrade", {}).get(id, {})
	if over.is_empty():
		return base
	var merged := base.duplicate()
	for key in over:
		merged[key] = over[key]
	return merged

## 穿戴装备：需求不满足拒绝穿戴并提示；换装覆盖槽位（原物保留在背包）。
## 装备不扣背包计数（原快捷装备语义），卸下只清槽位。
func equip_item(id: String) -> bool:
	if item_count(id) < 1 or not Campaign.is_equippable(id):
		return false
	var item: Dictionary = item_def(id)
	var slot: String = item.get("slot", "")
	if slot == "":
		return false
	for key in item.get("req", {}):
		if get_attribute(key) < int(item["req"][key]):
			push_message("无法装备【%s】：需 %s %d" % [item.name, Attributes.CN_NAMES.get(key, key), item["req"][key]])
			return false
	campaign.equipment[slot] = id
	attributes_changed.emit()
	save_game()
	return true

func unequip_item(slot: String) -> bool:
	var id: String = str(campaign.equipment.get(slot, ""))
	if id == "":
		return false
	campaign.equipment.erase(slot)
	attributes_changed.emit()
	save_game()
	return true

## ---------- 耐久（简化版：受伤扣护甲耐、击杀扣武器耐；两态，无灭失） ----------
func damage_item_dura(id: String, amount: float) -> void:
	if amount <= 0 or item_count(id) < 1:
		return
	var state: Dictionary = Campaign.dura_state(campaign, id)
	if state["max"] <= 0:
		return
	state["cur"] = maxf(0.0, state["cur"] - amount)
	campaign.item_dura[id] = state
	save_game()

func is_item_broken(id: String) -> bool:
	var st: Dictionary = Campaign.dura_state(campaign, id)
	return st["max"] > 0 and st["cur"] <= 0

## 护甲总减免（%）：穿戴中护甲 def_pct 累加；严重受损（耐久 0）装备词条失效。
func armor_reduction() -> float:
	var total := 0.0
	for slot in campaign.equipment:
		var id := str(campaign.equipment[slot])
		var def := item_def(id)
		var pct := float(def.get("def_pct", 0.0))
		if pct > 0.0 and not is_item_broken(id):
			total += pct
	return clampf(total, 0.0, 0.9)

## ---------- 强化机（仅乐园公证装备；成功率/消耗见 equip_tables） ----------
func enhance_item(id: String) -> bool:
	if item_count(id) < 1:
		return false
	var item: Dictionary = item_def(id)
	if not item.has("slot") or not item.get("export", false):
		push_message("【%s】本土装备无法进入乐园强化机" % item.name)
		return false
	var level := Campaign.enhance_level(campaign, id)
	if level >= Equip.ENHANCE_MAX:
		push_message("已达强化上限 +%d" % Equip.ENHANCE_MAX)
		return false
	var cost := int(Equip.quality_q(item.get("quality", "white")) * (Equip.GROW_ENHANCE if item.get("growth", false) else 1.0))
	if coins < cost:
		push_message("乐园币不足（需要 %d）" % cost)
		return false
	coins -= cost
	var p := Equip.enhance_success_rate(level)
	if randf() <= p:
		level += 1
		campaign.item_enhance[id] = level
		var state: Dictionary = Campaign.dura_state(campaign, id)
		state["max"] = state["max"] + Equip.enhance_dur_max_add(item)
		campaign.item_dura[id] = state
		push_message("强化成功 · 【%s】+%d" % [item.name, level])
	else:
		var row: Dictionary = {"fail_min": 99, "fail_max": 99} if level >= Equip.ENHANCE_ROWS.size() else Equip.ENHANCE_ROWS[level]
		if row["fail_min"] >= 90:
			level = 0
		else:
			level = maxi(0, level - randi_range(row["fail_min"], row["fail_max"]))
		campaign.item_enhance[id] = level
		push_message("强化失败 · 【%s】+%d（简化版：不掉耐久、装备不损毁）" % [item.name, level])
	save_game()
	attributes_changed.emit()
	return true

## ---------- 修复（乐园锻造铺，仅公证装备） ----------
func repair_item(id: String) -> bool:
	if item_count(id) < 1:
		return false
	var item: Dictionary = item_def(id)
	if not item.has("slot") or not item.get("export", false):
		push_message("乐园锻造铺拒绝受理本土装备")
		return false
	var state: Dictionary = Campaign.dura_state(campaign, id)
	var max_v: float = state["max"]
	if state["cur"] >= max_v or max_v <= 0:
		push_message("【%s】无需修复" % item.name)
		return false
	var cost := int(Equip.quality_q(item.get("quality", "white")) * (max_v - state["cur"]) / max_v * (Equip.GROW_REPAIR if item.get("growth", false) else 1.0))
	if coins < cost:
		push_message("乐园币不足（修复需 %d）" % cost)
		return false
	coins -= cost
	state["cur"] = max_v
	campaign.item_dura[id] = state
	save_game()
	push_message("修复完成 · 【%s】%d/%d" % [item.name, int(max_v), int(max_v)])
	return true

## ---------- 出售（乐园回收：装备走公式，材料/消耗品固定单价） ----------
func sell_item(id: String) -> bool:
	if item_count(id) < 1:
		return false
	var item: Dictionary = item_def(id)
	if not item.get("can_sell", true):
		push_message("【%s】禁止乐园回收" % item.name)
		return false
	var price := 0
	if int(item.get("sell_price", 0)) > 0:
		price = int(item["sell_price"])
	else:
		var q := Equip.quality_q(item.get("quality", "white"))
		var st: Dictionary = Campaign.dura_state(campaign, id)
		var fdur := clampf(st["cur"] / st["max"] if st["max"] > 0 else 1.0, 0.0, 1.0)
		price = int(q * Equip.SELL_R * Equip.kstr(Campaign.enhance_level(campaign, id)) * fdur * (Equip.GROW_SELL if item.get("growth", false) else 1.0))
	if item.has("slot"):
		_unmount_slot_with(id)
	give_item(id, -1)
	coins += price
	save_game()
	push_message("回收 · 【%s】+%d 乐园币" % [item.name, price])
	return true

## ---------- 分解（出对应品质锻造材料，几乎不给币） ----------
func decompose_item(id: String) -> bool:
	if item_count(id) < 1:
		return false
	var item: Dictionary = item_def(id)
	if not item.get("can_decompose", false):
		push_message("【%s】不可分解" % item.name)
		return false
	var q := Equip.quality_q(item.get("quality", "white"))
	var st: Dictionary = Campaign.dura_state(campaign, id)
	var fdur := clampf(st["cur"] / st["max"] if st["max"] > 0 else 1.0, 0.0, 1.0)
	var count := ceili(q / 100.0 * Equip.DECOMP_R * Equip.kstr(Campaign.enhance_level(campaign, id)) * fdur * (Equip.GROW_SELL if item.get("growth", false) else 1.0))
	var mat: String = {"white": "white_mat", "green": "green_mat", "blue": "blue_mat", "purple": "purple_mat", "gold_light": "gold_mat"}.get(item.get("quality", "white"), "white_mat")
	if item.has("slot"):
		_unmount_slot_with(id)
	give_item(id, -1)
	give_item(mat, count)
	save_game()
	push_message("分解 · 【%s】→ %s ×%d" % [item.name, Campaign.ITEMS[mat].name, count])
	return true

## 成长吞噬（斩龙闪·至尊锋刃）：吞噬同类型刀类武器积累锋刃值，满阈值品质晋升。
func devour_item(host: String, food: String) -> bool:
	var hi: Dictionary = item_def(host)
	var fi: Dictionary = item_def(food)
	if not hi.get("growth", false):
		push_message("【%s】不是成长武器" % hi.name)
		return false
	if item_count(host) < 1 or item_count(food) < 1:
		return false
	if fi.get("item_kind", "") != "weapon" or fi.get("weapon_type", "") not in ["1h_sword", "dagger"]:
		push_message("只能吞噬同类型（刀类）武器")
		return false
	var gained := float(fi.get("score", 1)) * 3.0
	var fury := float(campaign.get("item_fury", {}).get(host, 0.0)) + gained
	campaign.item_fury[host] = fury
	if fi.has("slot"):
		_unmount_slot_with(food)
	give_item(food, -1)
	campaign.item_dura.erase(food)
	campaign.item_enhance.erase(food)
	campaign.item_fury.erase(food)
	if fury >= Equip.GROW_MAX_FURY:
		_upgrade_growth_item(host)
	save_game()
	attributes_changed.emit()
	push_message("【%s】吞噬锋刃 +%.0f（%.0f/%.0f）" % [hi.name, gained, fury, Equip.GROW_MAX_FURY])
	return true

## 品质晋升：词条继承、强化保留、攻击区间提升；覆盖写 campaign.item_upgrade。
func _upgrade_growth_item(id: String) -> void:
	var base: Dictionary = item_def(id)
	var idx: int = TIER_ORDER.find(str(base.get("quality", "white")))
	if idx >= TIER_ORDER.size() - 1:
		return
	var next: String = TIER_ORDER[idx + 1]
	var add := Equip.growth_tier_attack_add(idx + 1)
	var over: Dictionary = campaign.get("item_upgrade", {}).get(id, {})
	over["quality"] = next
	over["score"] = Equip.QUALITY[next]["score_min"]
	over["attack_min"] = float(base.get("attack_min", 0.0)) + add
	over["attack_max"] = float(base.get("attack_max", 0.0)) + add
	campaign.item_upgrade[id] = over
	campaign.item_fury[id] = 0.0
	push_message("【%s】品质晋升 · %s！词条与强化等级保留" % [base.name, Equip.quality_cn(next)])

func _unmount_slot_with(id: String) -> void:
	for slot in campaign.equipment.keys():
		if str(campaign.equipment[slot]) == id:
			campaign.equipment.erase(slot)

func open_chest(id: String) -> bool:
	if item_count(id) < 1 or not Campaign.CHESTS.has(id):
		return false
	var reward: Dictionary = Campaign.CHESTS[id]
	give_item(id, -1)
	coins += reward.coins
	for item in reward.items:
		give_item(item, reward.items[item])
	save_game()
	return true

## ---------- 场景宝箱（世界内放置，靠近按 V 开启） ----------
## 每个场景一个，开启后记录 key 防重复领取（新试炼 begin_next_trial 时清空）。
func is_scene_chest_opened(key: String) -> bool:
	return campaign.get("opened_chests", []).has(key)

## 开启场景宝箱：固定产出 1 炸弹 + 1 血药 + 1 随机装备；已开过返回空数组。
func open_scene_chest(key: String) -> Array:
	if key == "" or is_scene_chest_opened(key):
		return []
	var rewards: Array = []
	for id in Campaign.SCENE_CHEST_ITEMS:
		give_item(id, Campaign.SCENE_CHEST_ITEMS[id])
		rewards.append(id)
	var equip := Campaign.random_equip_id()
	if equip != "":
		give_item(equip, 1)
		rewards.append(equip)
	campaign.opened_chests.append(key)
	save_game()
	return rewards

## ---------- 击杀随机装备掉落 ----------
## 按概率判定是否掉落；命中则返回随机装备 id，未命中返回空串。
func roll_equipment_drop(chance: float) -> String:
	if randf() > chance:
		return ""
	return Campaign.random_equip_id()

## 全回复（BOSS 房进入时调用）：所有已持有装备耐久修满，返回修复件数。
func repair_all_equipment() -> int:
	var ids: Array[String] = []
	for id in campaign.bag.keys():
		if item_count(str(id)) > 0:
			ids.append(str(id))
	for slot in campaign.equipment:
		var eid := str(campaign.equipment[slot])
		if eid != "" and not ids.has(eid):
			ids.append(eid)
	var repaired := 0
	for id in ids:
		var def := item_def(id)
		if int(def.get("dur_max", 0)) <= 0:
			continue
		var st: Dictionary = Campaign.dura_state(campaign, id)
		if st["cur"] >= st["max"]:
			continue
		st["cur"] = st["max"]
		campaign.item_dura[id] = st
		repaired += 1
	if repaired > 0:
		save_game()
	return repaired

## 击杀由战斗实例触发；检查唯一ID，结算和读档不能重复领奖。
func record_hunt(id: String) -> int:
	if campaign.kills.has(id) or campaign.hub or campaign.cleared:
		return 0
	campaign.kills.append(id)
	var gain := mini(int(Campaign.HUNTS.get(id, 0)), 100 - int(campaign.world_mana))
	campaign.world_mana += gain
	campaign.permanent_mana += gain
	attributes_changed.emit()
	return gain

func clear_region(hp_ratio: float) -> bool:
	if campaign.cleared or campaign.hub:
		return false
	campaign.cleared = true
	campaign.hp_ratio = clampf(hp_ratio, 0.01, 1.0)
	var stage: Dictionary = Campaign.STAGES[campaign.stage]
	for id in stage.loot:
		give_item(id, stage.loot[id])
	campaign.source = snappedf(float(campaign.source) + float(stage.source), 0.1)
	save_game()
	return true

func can_advance_region() -> bool:
	if not campaign.cleared or campaign.hub or campaign.stage >= 4:
		return false
	if campaign.stage == 1 and item_count("letter") == 0:
		return false
	if campaign.stage == 2 and campaign.equipment.get("main_weapon") != "dragon":
		return false
	return true

func advance_region() -> bool:
	if not can_advance_region():
		return false
	campaign.stage += 1
	campaign.cleared = false
	save_game()
	return true

func settle_trial() -> bool:
	if campaign.stage != 4 or not campaign.cleared or campaign.settled:
		return false
	# 截止猎虎的独立切片结算；不冒充国王主线完成。
	var high := float(campaign.source) >= 8.9
	var multiplier := 2 if 6 - int(campaign.level) >= 5 else 1
	var points := (2 if high else 1) * multiplier
	var money := (1000 if high else 600) * multiplier
	attr_points += points
	coins += money
	campaign.level += 1
	campaign.settled = true
	campaign.hub = true
	campaign.report = "阶段试炼评价 %s · 世界之源 %.1f%%\n属性点 +%d · 乐园币 +%d · 奖励倍率 ×%d\n巨虎已猎杀；国王主线与虎齿交付尚未完成。" % ["A" if high else "B", campaign.source, points, money, multiplier]
	for id in campaign.bag.keys():
		if not Campaign.ITEMS.get(id, {}).get("export", false):
			campaign.bag.erase(id)
	# 本土（不可带出）装备必须销毁：槽位引用同步清除；公证装备即使不在背包（已穿戴）也保留。
	for slot in campaign.equipment.keys():
		var eid := str(campaign.equipment[slot])
		if item_count(eid) == 0 and not Campaign.ITEMS.get(eid, {}).get("export", false):
			campaign.equipment.erase(slot)
	# 清理已不持有的物品动态状态（耐久/强化/锋刃/晋升覆盖）
	var owned: Array[String] = []
	for id in campaign.bag.keys():
		owned.append(id)
	for id in campaign.equipment.values():
		owned.append(str(id))
	for key in ["item_dura", "item_enhance", "item_fury", "item_upgrade"]:
		var table: Dictionary = campaign.get(key, {})
		for id in table.keys():
			if not owned.has(str(id)):
				table.erase(id)
	campaign.hp_ratio = 1.0
	campaign.mp_ratio = 1.0
	save_game()
	return true

func buy_potion() -> bool:
	if not campaign.hub or coins < 100:
		return false
	coins -= 100
	give_item("potion", 1)
	save_game()
	return true

func train_blade() -> bool:
	if not campaign.hub or coins < 1000 or item_count("crystal") < 1 or campaign.training >= 3:
		return false
	coins -= 1000
	give_item("crystal", -1)
	campaign.training += 1
	save_game()
	return true

func begin_next_trial() -> bool:
	if not campaign.hub or not campaign.settled:
		return false
	campaign.run += 1
	campaign.stage = 0
	campaign.cleared = false
	campaign.hub = false
	campaign.settled = false
	campaign.source = 0.0
	campaign.world_mana = 0
	campaign.colpo_outer_cleared = false
	campaign.kills = []
	campaign.opened_chests = []
	campaign.bullets = 6
	campaign.hp_ratio = 1.0
	campaign.mp_ratio = 1.0
	if campaign.equipment.get("main_weapon", "") == "":
		give_item("knife", 1)
		campaign.equipment.main_weapon = "knife"
	save_game()
	return true

func _notification(what: int) -> void:
	# 关窗/切后台（Android 返回）兜底保存，避免改了币没写盘
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_game()

## 场景过场：淡出 → 换场景 → 淡入，避免硬切。
## 遮罩挂在本自动加载节点上，切场景时不会被一起销毁，所以能挡住黑屏与旧画面残影。
func change_scene(path: String) -> void:
	if _transitioning:
		return
	_transitioning = true
	get_tree().paused = false  # 过场期间不能是被暂停状态，否则补间不会推进
	var layer := CanvasLayer.new()
	layer.name = "SceneCurtain"
	layer.layer = 128
	add_child(layer)
	var curtain := ColorRect.new()
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0, 0, 0, 0)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP  # 过场期间不接受操作
	layer.add_child(curtain)
	var fade_out := create_tween()
	fade_out.tween_property(curtain, "color:a", 1.0, 0.32)
	await fade_out.finished
	var result := get_tree().change_scene_to_file(path)
	if result != OK:
		push_message("[乐园] 场景切换失败：%s" % path)
		layer.queue_free()
		_transitioning = false
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var fade_in := create_tween()
	fade_in.tween_property(curtain, "color:a", 0.0, 0.32)
	await fade_in.finished
	layer.queue_free()
	_transitioning = false
