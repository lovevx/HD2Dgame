class_name BattleController
extends RefCounted
## 回合状态机：遭遇 → ORDER(排序入场) → ACTION(当前单位行动) → CHECK(轮转)
## → VICTORY / DEFEAT。只做调度与结算，不拥有场景节点（单位仍是场景里的 player / enemy）。
## 回合规则（P1 v1）：AT = 敏捷降序；玩家回合 = 先自动走位再出一招；
## 敌人回合 = 接近→攻击；每整轮回蓝 5% 最大 MP；全歼胜 / 玩家死亡败。
## v1 未做：眩晕触发切入、处决、Boss 强制回合（P2）。

enum Phase { IDLE, ORDER, ACTION, CHECK, VICTORY, DEFEAT }

const Skills := preload("res://data/combat_skills.gd")

var units: Array[BattleUnit] = []
var order: Array[BattleUnit] = []   # 本轮行动序列（每轮重排）
var index := 0
var round := 0
var phase := Phase.IDLE

func set_units(list: Array[BattleUnit]) -> void:
	units = list

func begin_battle() -> void:
	round = 0
	_rebuild_order()
	_begin_turn_for(current())

## 进入回合制的首轮先手权（docs/COMBAT_DESIGN.md §2.4）：把玩家单位挪到本轮序列首位。
## 从第 2 轮起回到正常的敏捷降序。
func begin_battle_with_player_first() -> void:
	begin_battle()
	var pu := player_unit()
	if pu == null or order.is_empty():
		return
	var at := order.find(pu)
	if at > 0:
		order.remove_at(at)
		order.push_front(pu)
	index = 0
	phase = Phase.ACTION
	_begin_turn_for(current())

func _rebuild_order() -> void:
	order = units.duplicate()
	order.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		if a.agility == b.agility:
			return a.is_player and not b.is_player  # 同名时玩家先手
		return a.agility > b.agility)
	index = 0
	phase = Phase.ORDER

## 某单位回合开始：清掉它自己上一轮留下的防御态。
##
## 防御的存活期是「到该单位自己下次行动开始为止」，所以清点必须落在**该单位**的回合开头，
## 不能在整轮重排时对全体统一清 —— 若玩家是本轮最后行动者（敌人敏捷更高、或站着不动等敌人先动），
## 防御会在自己回合结束的瞬间被抹掉，紧接着敌人回击时 is_defending() 已是 false，白选一次。
func _begin_turn_for(u: BattleUnit) -> void:
	if u != null:
		u.clear_defend()

## 当前行动单位。
func current() -> BattleUnit:
	if order.is_empty():
		return null
	return order[clampi(index, 0, order.size() - 1)]

## 行动完成 → 下一个单位；走完一轮则重排、回蓝并滚回合。
func finish_turn() -> void:
	phase = Phase.CHECK
	index += 1
	if index >= order.size():
		round += 1
		for u in units:
			u.take_regen_mp()
		_rebuild_order()
	else:
		phase = Phase.ACTION
	_begin_turn_for(current())

## 玩家实体是 HP/MP 的唯一权威，作战单位只是镜像：出手后（技能扣蓝 / 药剂回血）
## 调这个把实体值抄进单位。旧实现整场只同步一次（且方向相反），回合内花掉的蓝会被退回。
func pull_player_stats() -> void:
	var pu := player_unit()
	if pu != null and is_instance_valid(pu.node):
		pu.sync_from_player(pu.node)

## 把玩家的蓝抄回实体：每整轮回蓝（5%）结算在单位上，wrap 后必须落到玩家身上。
## 只写 MP —— HP 会因敌人出手在同步点之外变化，抄回会把伤害抹掉。
func flush_player_mp() -> void:
	var pu := player_unit()
	if pu == null or not is_instance_valid(pu.node):
		return
	pu.node.set("mp", minf(float(pu.node.get("max_mp")), pu.mp))

func alive_units() -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in units:
		if node_alive(u.node):
			out.append(u)
	return out

func foes_of(unit: BattleUnit) -> Array[BattleUnit]:
	var out: Array[BattleUnit] = []
	for u in units:
		if u.is_player != unit.is_player and node_alive(u.node):
			out.append(u)
	return out

func nearest_foe_to(unit: BattleUnit) -> BattleUnit:
	var best: BattleUnit = null
	var best_dist := INF
	for u in foes_of(unit):
		var d := u.node.global_position.distance_to(unit.node.global_position)
		if d < best_dist:
			best_dist = d
			best = u
	return best

func all_enemies_dead() -> bool:
	for u in units:
		if not u.is_player and node_alive(u.node):
			return false
	return true

func player_unit() -> BattleUnit:
	for u in units:
		if u.is_player:
			return u
	return null

## 事实存活判断：敌人用 is_alive()，玩家（CharacterBody3D）用 alive 字段。
static func node_alive(node: Node) -> bool:
	if node == null:
		return false
	if node.has_method("is_alive"):
		return node.is_alive()
	return bool(node.get("alive"))

## 侧击 +10% / 背击 +25%。判定看**目标朝向**：目标正对着我 = 正面，背对着我 = 背击。
##
## 不能用攻击者朝向去点乘 to_target —— 出手前 _face() 刚把攻击者拧向目标，
## 两个向量同向、点乘恒为 1，永远落进"正面"分支（旧实现就是这么恒判正面的）。
func attack_bonus(unit: BattleUnit, target: BattleUnit) -> float:
	if not is_instance_valid(unit.node) or not is_instance_valid(target.node):
		return 1.0
	var to_target: Vector3 = target.node.global_position - unit.node.global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return 1.0
	# 目标正面朝向攻击者的程度：+1 = 正对着我，−1 = 完全背对我。
	var faces_me: float = forward_of(target.node).dot(-to_target.normalized())
	if faces_me > 0.7:
		return 1.0          # 正面：目标面向我
	if faces_me < -0.45:
		return 1.25         # 背击：目标背对我
	return 1.1              # 侧击

## 取节点朝向：玩家有 `facing` 字段；敌人只维护 rotation.y，用 −basis.z 反推。
static func forward_of(node: Node) -> Vector3:
	if not is_instance_valid(node):
		return Vector3.FORWARD
	var f: Variant = node.get("facing")
	if f is Vector3:
		var v: Vector3 = f
		v.y = 0.0
		if v.length_squared() > 0.001:
			return v.normalized()
	var spatial := node as Node3D
	if spatial != null:
		var fwd: Vector3 = -spatial.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.001:
			return fwd.normalized()
	return Vector3.FORWARD

## 逃跑：我方敏捷+d10 vs 敌方平均敏捷+d10。
func flee(unit: BattleUnit) -> bool:
	var foes := foes_of(unit)
	if foes.is_empty():
		return true
	var score := unit.agility + randi_range(1, 10)
	var avg := 0.0
	for f in foes:
		avg += f.agility
	avg /= float(foes.size())
	var enemy_score := int(avg) + randi_range(1, 10)
	return score > enemy_score

func force_win() -> void:
	phase = Phase.VICTORY

func force_lose() -> void:
	phase = Phase.DEFEAT

func order_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for u in order:
		out.append(("玩家" if u.is_player else "敌") + " Lv." + str(u.agility))
	return out