class_name BattleUnit
extends RefCounted
## 双形态战斗的统一作战封装：玩家与敌人各持一份；数值源 = 各自实体现有字段。
## 纯数据 + 纯函数给 battle_controller 算，不碰场景树。
## v1（2026-09-21）：只覆盖 P1 回合核心所需字段；眩晕/意图字段随 P2 补。

var node: Node3D                # 挂的实体（player / enemy）
var is_player := false
var hp := 0.0
var max_hp := 100.0
var mp := 0.0
var max_mp := 0.0
var move_power := 3.0            # 移动力（米）：玩家 = 3.0 + (敏捷-5)*0.2，敌人 = move_speed
var attack_power := 0.0          # 敌人才用：参考攻击（玩家结算走 roll_attack_damage）
var agility := 5                 # AT 先攻排序用

func hp_ratio() -> float:
	return hp / maxf(max_hp, 0.001)

func take_regen_mp() -> void:
	mp = minf(max_mp, mp + round_mp_regen())

func round_mp_regen() -> float:
	return maxf(max_mp * 0.05, 1.0)

func set_defend(active: bool) -> void:
	set_meta("defend_round", active)

func is_defending() -> bool:
	return bool(get_meta("defend_round", false))

func clear_defend() -> void:
	remove_meta("defend_round")

static func from_player(player: Node, agi: int) -> BattleUnit:
	var u := BattleUnit.new()
	u.node = player
	u.is_player = true
	u.hp = player.hp
	u.max_hp = player.max_hp
	u.mp = player.mp
	u.max_mp = player.max_mp
	u.move_power = 3.0 + (agi - 5) * 0.2
	u.agility = agi
	return u

## 敌人侧字段名在各实现里不一致（enemy.gd 用 hp_/move_speed/attack_damage，
## 科尔波山之主用 hp/walk_speed/battle_damage），这里按候选名依次取第一个数值。
static func _num(node: Node, names: Array, fallback: float) -> float:
	for n in names:
		var v: Variant = node.get(n)
		if v is float or v is int:
			return float(v)
	return fallback

static func from_enemy(enemy: Node) -> BattleUnit:
	var u := BattleUnit.new()
	u.node = enemy
	u.hp = _num(enemy, ["hp_", "hp"], 1.0)
	u.max_hp = _num(enemy, ["max_hp"], u.hp)
	u.move_power = _num(enemy, ["move_speed", "walk_speed", "charge_speed"], 1.2)
	u.attack_power = _num(enemy, ["attack_damage", "battle_damage"], 10.0)
	u.agility = int(_num(enemy, ["agility"], 5.0))
	return u

## 把实体的当前 HP 同步回来（回合内被 controller 结算过之后调用）。
func sync_from_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	hp = _num(enemy, ["hp_", "hp"], hp)

## 玩家实体是 HP/MP 唯一权威，这里把实体当前值抄进单位（出手后调用，
## 见 battle_controller.pull_player_stats）。HP 只作镜像：玩家掉血走 take_damage，
## 收尾时不把镜像写回，否则会把同步点之后受到的伤害抹掉。
func sync_from_player(player: Node) -> void:
	if player == null:
		return
	hp = player.hp
	mp = player.mp