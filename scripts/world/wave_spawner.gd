extends Node3D
signal finished
var campaign_managed := false
## 科尔波山外围的波次调度：读场景里的刷怪点标记（colpo_spawn 分组 + wave / kind 元数据），
## 一波清完再放下一波；三波清完标记完成，传送门据此开锁。
## 波次配置写在场景标记上，改数量或换敌人只动 build_colpo.gd 里的标记，不改这里。

const EnemyScene := preload("res://scripts/combat/enemy.tscn")
const EnemyScript := preload("res://scripts/combat/enemy.gd")
const KIND_LABEL := {"wolf": "只野狼", "boar": "只野猪", "golem": "具肉体傀儡"}

@export var first_delay := 1.5   # 进场到第一波的准备时间
@export var wave_delay := 2.0    # 清完一波后的喘息时间
@export var spawn_jitter := 0.6  # 出生点散开半径，避免几只叠在一起

var _waves := {}        # 波次序号 -> 刷怪点标记数组
var _planned := 0       # 总波数
var _index := 0         # 已放出的波次
var _fighting := false  # 当前波是否还在打
var _finished := false
var _timer := 0.0
var _objective := ""

func _ready() -> void:
	add_to_group("wave_director")
	_collect_markers()
	_planned = _waves.size()
	_timer = first_delay
	if _planned == 0:
		_finished = true
	if campaign_managed:
		set_process(false)

## 传送门只看这个：波次没打完（含波与波之间的空隙）就不算清场。
func is_finished() -> bool:
	return _finished

## 当前存活敌人数。
func remaining() -> int:
	var alive := 0
	for enemy in get_children():
		if enemy.has_method("is_alive") and enemy.is_alive():
			alive += 1
	return alive

func _process(delta: float) -> void:
	if _finished:
		return
	_timer = maxf(0.0, _timer - delta)
	if _fighting and remaining() == 0:
		_fighting = false
		if _index >= _planned:
			_finish()
		else:
			_timer = wave_delay
			GameState.push_message("[科尔波山] 第 %d / %d 波已清除" % [_index, _planned])
	elif not _fighting and _index < _planned and _timer <= 0.0:
		_spawn_wave()
	_update_objective()

func _collect_markers() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for node in parent.get_children():
		if node is Marker3D and node.has_meta("wave") and node.has_meta("kind"):
			var wave: int = int(node.get_meta("wave"))
			if not _waves.has(wave):
				_waves[wave] = []
			_waves[wave].append(node)

func _spawn_wave() -> void:
	_index += 1
	var markers: Array = _waves.get(_index, [])
	var tally := {}
	for marker in markers:
		var enemy := EnemyScene.instantiate()
		enemy.set("kind", _kind_of(str(marker.get_meta("kind"))))
		enemy.position = marker.position + Vector3(randf_range(-spawn_jitter, spawn_jitter), 0, randf_range(-spawn_jitter, spawn_jitter))
		add_child(enemy)
		var spawn := create_tween()
		spawn.tween_property(enemy, "scale", Vector3.ONE, 0.25).from(Vector3.ONE * 0.25)
		var key := str(marker.get_meta("kind"))
		tally[key] = int(tally.get(key, 0)) + 1
	var parts := []
	for key in tally:
		parts.append("%d %s" % [tally[key], KIND_LABEL.get(key, key)])
	_fighting = true
	GameState.push_message("[科尔波山] 第 %d / %d 波 · %s" % [_index, _planned, "、".join(parts)])

func _finish() -> void:
	_finished = true
	GameState.push_message("[科尔波山] 外围威胁清除，继续深入山林，前往林间空地")
	finished.emit()

func _update_objective() -> void:
	var text := ""
	if _finished:
		text = "外围威胁清除 · 前往传送门"
	elif _fighting:
		text = "第 %d / %d 波 · 剩余目标 %d" % [_index, _planned, remaining()]
	else:
		text = "下一波 %d 秒后来袭 · 第 %d / %d 波" % [int(ceil(_timer)), _index + 1, _planned]
	if text == _objective:
		return
	_objective = text
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null:
		hud.set_objective(text)

func _kind_of(meta: String) -> int:
	match meta:
		"boar":
			return EnemyScript.Kind.BOAR
		"golem":
			return EnemyScript.Kind.GOLEM
		_:
			return EnemyScript.Kind.WOLF
