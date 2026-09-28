extends Node
## 全局游戏状态：契约者、阶段试炼、背包/装备、永久成长与场景过场。
## 存档分两层，只有「已提交层」会被写进 user://save.cfg：
## - 已提交层：检查点、乐园操作（开箱/换装/商店）与结算提交的内容。写入走临时档 +
##   rename 原子替换，并在替换前留一份 .bak，主档损坏时回退到备份。
## - 本局临时层（SORTIE_KEYS）：一次出击里还没到提交点的易变状态 —— 途中拾取与战斗中
##   扣掉的耐久。死亡 / 放弃出击 / 异常退出把临时层整体回滚，因此不会出现
##   「收益留下、消耗不还原」的半提交。见 sortie 事务 API。
## 主菜单据 player_name 是否为空决定是否显示「继续游戏」。
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

## 玩家未填写姓名时使用的中性默认名。
const DEFAULT_PLAYER_NAME := "契约者"
const SAVE_PATH := "user://save.cfg"
var save_path := SAVE_PATH

## 存档格式版本：落盘字段新增/改义时 +1，load_game 据它决定升级路径。
## v1 = 无 version 字段的旧档（8 槽装备 / 未分离出击事务）。
const SAVE_VERSION := 2

## 出击事务里「未提交」的 campaign 键：这些键在本局可被整体回滚，其余键只经提交点写入。
## bag = 途中拾取的装备与场景宝箱产出；item_dura = 战斗中扣掉的耐久。
const SORTIE_KEYS: Array[String] = ["bag", "item_dura"]

## 一次出击的结束路径。P1 要求四条路径共用同一事务：只有正常撤离提交，
## 其余三条把未提交部分回滚，恢复时不得重复发奖、扣币或折损。
## RESCUE 的「本局收益只结算 30%」与 PERMADEATH 的角色销毁尚未实装（待拍板），
## 现在都按回滚处理。ABANDON = 玩家主动放弃（战斗中退回主菜单 / 关窗），
## 同样只可能回滚，不允许靠退出「蒙混提交」。
enum Sortie { NORMAL, DEATH, RESCUE, PERMADEATH, TIMEOUT, ABANDON }

var _sortie_active := false
## 本局是否有过未提交改动：用于把「已回滚」与「本局无未提交变更」对玩家说清楚。
var _sortie_dirty := false
## 上一个提交点的 SORTIE_KEYS 快照，回滚即还原到它。
var _sortie_base: Dictionary = {}

## 契约者姓名：档案是否成立以它为准（空串 = 还没建档）。
var player_name: String = ""

var coins: int = 0
## 六维属性：str/agi/con/int/cha/luk，见 data/attributes.gd。
var attributes: Dictionary = Attributes.defaults()
## 测试面板临时属性覆盖，不进存档；调试期间所有派生属性读取都能看到它。
var debug_attribute_overrides: Dictionary = {}
## 测试面板打开过的本次运行会话：离开战役区域时不回写临时资源。
var debug_mode_active := false
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
	debug_attribute_overrides.clear()
	debug_mode_active = false
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

## 新手流程开局：签订契约后醒来在船上，船靠岸抵达灰潮港（港口引导阶段）。
## 单独一步（不在 complete_contract 里）是为了保持旧档/验证脚本的契约语义不变。
func begin_onboarding() -> void:
	campaign.hub = true
	campaign.flow = "ship"
	save_game()

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

## 显式落盘 = 出击事务的提交点：先把当前 SORTIE_KEYS 记为新的提交基线，
## 之后的易变改动才算「未提交」、才回滚得动。所以检查点与乐园操作天然就是提交点。
func save_game() -> void:
	if _sortie_active:
		_commit_sortie_now()
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "version", SAVE_VERSION)
	cfg.set_value("progress", "campaign", campaign)
	cfg.set_value("progress", "player_name", player_name)
	cfg.set_value("progress", "coins", coins)
	cfg.set_value("progress", "attributes", attributes)
	cfg.set_value("progress", "attr_points", attr_points)
	# 先写临时档，成功后再原地替换：中途掉电最多留一份 .tmp + 一份 .bak，
	# 正式档始终是完整的某一代（旧写法直接覆盖正式档，写一半就整档报废）。
	var tmp := save_path + ".tmp"
	var error := cfg.save(tmp)
	if error != OK:
		push_error("存档写入失败：%s" % error_string(error))
		return
	var abs_save := ProjectSettings.globalize_path(save_path)
	var abs_bak := ProjectSettings.globalize_path(save_path + ".bak")
	# 只备份「读得动」的正式档：否则一次坏档会被复制成备份，把上一份好档顶掉。
	if _is_valid_save(save_path):
		DirAccess.copy_absolute(abs_save, abs_bak)
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_save)
	if rename_error != OK:
		push_error("存档替换失败：%s" % error_string(rename_error))

func _is_valid_save(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var cfg := ConfigFile.new()
	return cfg.load(path) == OK and cfg.has_section("progress")

## 读档：正式档优先，解析失败或缺失时回退 .bak，再不行当新档处理。
func load_game() -> void:
	debug_attribute_overrides.clear()
	debug_mode_active = false
	if not _load_from(save_path) and not _load_from(save_path + ".bak"):
		return

func _load_from(path: String) -> bool:
	var cfg := ConfigFile.new()
	# 两种坏档都要回退备份，不能当有效进度：load 失败（写一半被截断）与
	# load 成功但没有 progress 段（空壳档 —— ConfigFile 对只有段头或纯垃圾的
	# 内容不报错，直接读会把姓名与乐园币静默清空）。
	if cfg.load(path) != OK or not cfg.has_section("progress"):
		if FileAccess.file_exists(path):
			push_warning("存档不可用，回退备份：%s" % path)
		return false
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
	# 新手流程：任何加载都回到灰潮港（教学中间状态不落档，继续游戏从港口接着走）。
	if ["ship", "training", "equipped", "quested"].has(str(campaign.get("flow", ""))):
		campaign.hub = true
	# 载入即视为一个干净提交点：此时内存里的易变状态就等于落盘内容。
	_sortie_dirty = false
	if _sortie_active:
		_commit_sortie_now()
	return true

# ---------------------------------------------------------------- 出击结算事务
#
# P1 基线：正常撤离、逃脱币救援、无币永久死亡与任务超时共用唯一事务提交，
# 恢复时不得重复发奖、扣币或折损。这里的做法是「出击快照 → 本局临时状态 → 一次性提交」：
#
#   begin_sortie()        进入战斗区域时拍快照（SORTIE_KEYS 的当前值）
#   （本局内的易变改动）  途中拾取、战斗扣耐久只改内存，不落盘
#   commit_sortie()       检查点 / 领取战利品 / 开箱 / 换装 / 结算时提交，快照推进
#   rollback_sortie()     死亡、放弃出击、异常退出时把临时层还原回快照
#   settle_sortie(原因)   上面两条的唯一入口，四条结束路径都从这里走

## 进入战斗区域：以一个干净的提交基线开启本局。可重复调用（重试会重新拍）。
func begin_sortie() -> void:
	_sortie_active = true
	_commit_sortie_now()

## 离开战斗进入非战斗区域（灰潮港 / 演武场）：本局结束，清掉会话。
func end_sortie() -> void:
	_sortie_active = false
	_sortie_base.clear()
	_sortie_dirty = false

func is_sortie_active() -> bool:
	return _sortie_active

## 本局是否有过未提交改动（未提交的拾取 / 耐久损耗）。
func is_sortie_dirty() -> bool:
	return _sortie_active and _sortie_dirty

## 标记本局有未提交改动。直接写 campaign 易变键的代码（如 _copy_supplies）应调用它。
func mark_sortie_dirty() -> void:
	if _sortie_active:
		_sortie_dirty = true

## 提交：把当前易变状态定为新的基线。注意它不落盘 —— save_game() 负责写盘，
## 并在写盘前自动调用本函数，所以任何显式落盘都是提交点。
func commit_sortie() -> void:
	if _sortie_active:
		_commit_sortie_now()

## 回滚：把未提交的拾取与耐久损耗还原到上一个提交点。返回是否真的处于本局中。
func rollback_sortie() -> bool:
	if not _sortie_active:
		return false
	for key in SORTIE_KEYS:
		var base = _sortie_base.get(key)
		if base == null:
			campaign[key] = Campaign.fresh().get(key)
			continue
		campaign[key] = (base as Dictionary).duplicate(true)
	_sortie_dirty = false
	return true

## 四条结束路径 + 主动放弃的唯一入口：只有 NORMAL 提交；其余一律回滚未提交部分。
## RESCUE 将来要「保留角色，本局收益只结算 30%」、PERMADEATH 要销毁角色档，
## 都需要在回滚之后追加对应的资产/存档动作（待拍板，P1 未实装）。
## 返回是否确实处于本局中（非战斗场景调用时返回 false，无事务可结束）。
func settle_sortie(outcome: int) -> bool:
	match outcome:
		Sortie.NORMAL:
			commit_sortie()
		_:
			rollback_sortie()
	return _sortie_active

func _commit_sortie_now() -> void:
	_sortie_base.clear()
	for key in SORTIE_KEYS:
		var value = campaign.get(key)
		_sortie_base[key] = (value as Dictionary).duplicate(true) if value is Dictionary else value
	_sortie_dirty = false

func debug_attributes() -> Dictionary:
	var result: Dictionary = attributes.duplicate()
	for key in debug_attribute_overrides:
		result[key] = int(debug_attribute_overrides[key])
	return result

## 测试面板使用：临时覆写裸装属性，不扣属性点、不写存档。
func set_debug_attribute(key: String, value: int) -> void:
	if not Attributes.ALL_KEYS.has(key):
		return
	var normalized := clampi(value, 1, 999)
	var base_value := int(attributes.get(key, Attributes.BASE))
	if normalized == base_value:
		debug_attribute_overrides.erase(key)
	else:
		debug_attribute_overrides[key] = normalized
	attributes_changed.emit()

func clear_debug_attribute_overrides() -> void:
	if debug_attribute_overrides.is_empty():
		return
	debug_attribute_overrides.clear()
	attributes_changed.emit()

func effective_attributes() -> Dictionary:
	## 作战六维 = 裸装 + 已穿戴装备词条（通用聚合，替换原项坠硬编码特例）。
	var result := debug_attributes()
	for slot in campaign.equipment:
		var id: String = str(campaign.equipment[slot])
		if is_item_broken(id):
			continue
		var def := item_def(id)
		for key in def.get("stats", {}):
			result[key] = int(result.get(key, Attributes.BASE)) + int(def["stats"][key])
	return result

func item_count(id: String) -> int:
	return int(campaign.bag.get(id, 0))

func give_item(id: String, count: int) -> void:
	campaign.bag[id] = maxi(0, item_count(id) + count)
	mark_sortie_dirty()

## 新手教学完成后发放的整套基础装备（本土装备，结算时随世界限定清除）。
const STARTER_GEAR := ["worn_blade", "leather_cap", "ragged_vest", "leather_bracer", "worn_boots", "tattered_cloak", "copper_ring"]

## 发放整套基础装备并自动穿戴（无需求门槛），返回装备名列表。
func grant_starter_gear() -> Array[String]:
	var names: Array[String] = []
	for id in STARTER_GEAR:
		give_item(id, 1)
		if Campaign.is_equippable(id):
			equip_item(id)
		names.append(item_def(id).get("name", id))
	save_game()
	return names

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
## 战斗中的损耗属于「本局消耗」：只改内存、不落盘，死亡回滚时连同拾取一起还原，
## 提交点在检查点 / 领取战利品 / 开箱等显式 save_game() 处。
func damage_item_dura(id: String, amount: float) -> void:
	if amount <= 0 or item_count(id) < 1:
		return
	var state: Dictionary = Campaign.dura_state(campaign, id)
	if state["max"] <= 0:
		return
	var was_intact: bool = state["cur"] > 0.0
	state["cur"] = maxf(0.0, state["cur"] - amount)
	campaign.item_dura[id] = state
	mark_sortie_dirty()
	if was_intact and state["cur"] <= 0.0:
		attributes_changed.emit()

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
		var fdur := clampf(st["cur"] / st["max"] if st["max"] > 0 else 1.0, 0.4, 1.0)
		var base_sell := minf(q * Equip.SELL_R, float(item.get("score", 0)) * 25.0)
		price = int(base_sell * Equip.kstr(Campaign.enhance_level(campaign, id)) * fdur * (Equip.GROW_SELL if item.get("growth", false) else 1.0))
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
	var fdur := clampf(st["cur"] / st["max"] if st["max"] > 0 else 1.0, 0.4, 1.0)
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
	var tutorials: Dictionary = campaign.get("tutorial_steps", {})
	if campaign.stage == 1 and item_count("letter") == 0:
		return false
	if campaign.stage == 1 and not bool(tutorials.get("gun", false)):
		return false
	if campaign.stage == 2 and campaign.equipment.get("main_weapon") != "dragon":
		return false
	if campaign.stage == 2 and (not bool(tutorials.get("kick", false)) or not bool(tutorials.get("shadow", false))):
		return false
	if campaign.stage == 3 and (not bool(tutorials.get("wave", false)) or not bool(tutorials.get("ring", false))):
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
	# 属性点 = 世界之源每 20% 换 1 点（不足 20% 保底 1 点）；首轮噩梦倍率仍生效。
	var points := maxi(1, int(floor(campaign.source / 20.0))) * multiplier
	var money := (1000 if high else 600) * multiplier
	attr_points += points
	coins += money
	campaign.level += 1
	campaign.settled = true
	campaign.hub = true
	campaign.report = "阶段试炼评价 %s · 世界之源 %.1f%%\n属性点 +%d · 乐园币 +%d · 奖励倍率 ×%d\n世界之源每20%%兑1属性点（保底1点）· 巨虎已猎杀；国王主线与虎齿交付尚未完成。" % ["A" if high else "B", campaign.source, points, money, multiplier]
	campaign.hub_guide_done = {"growth": false, "supplies": false, "training": false, "archive": false, "practice": false}
	campaign.settlement_intro_seen = false
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

## ---------- 乐园商店购买（轮回商店 UI 走这里扣币/入包/落盘） ----------
func buy_item(id: String, price: int) -> bool:
	var def := item_def(id)
	if def.is_empty() or price <= 0:
		push_message("该商品暂无货源")
		return false
	if def.get("item_kind", "") == "quest":
		return false
	if coins < price:
		push_message("乐园币不足（需要 %d）" % price)
		return false
	coins -= price
	give_item(id, 1)
	save_game()
	push_message("购入 · 【%s】" % def.get("name", id))
	return true

func buy_potion() -> bool:
	if not campaign.hub or coins < 150:
		return false
	coins -= 150
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
	campaign.hub_guide_done = {}
	campaign.settlement_intro_seen = false
	if campaign.equipment.get("main_weapon", "") == "":
		give_item("knife", 1)
		campaign.equipment.main_weapon = "knife"
	save_game()
	return true

func _notification(what: int) -> void:
	# 关窗/切后台（Android 返回）兜底保存，避免改了币没写盘。
	# 但本局未提交的拾取/耐久损耗不能靠关窗「蒙混提交」：先按放弃出击回滚再写，
	# 落盘内容因此永远是最近一个合法提交点（崩溃恢复口径，不是死亡回滚口径）。
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		settle_sortie(Sortie.ABANDON)
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
