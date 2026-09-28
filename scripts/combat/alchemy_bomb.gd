extends Area3D
const GameAudio := preload("res://data/game_audio.gd")
## 炼金炸弹：扔出去落地后变成预埋陷阱，敌人踩到 → 引信 0.35 秒 → 爆炸。
## 只炸敌人不炸苏晓：陷阱是玩家自己布的，踩自家陷阱受伤会让准备阶段变得难受。
## 预警做在引信上：红圈收缩 + 闪光，敌人和玩家都有时间离开爆炸范围。

const EXPLOSION_RADIUS := 4.5
const EXPLOSION_DAMAGE := 90.0
const FUSE_TIME := 0.35
const ARM_DELAY := 0.25   # 落地到布防完成，避免刚扔出去就被自己触发的错觉

var armed := false
var exploded := false
var fuse := -1.0
var clock := 0.0
var arm_timer := ARM_DELAY
var body_mesh: MeshInstance3D
var ring: MeshInstance3D
var core_mat: StandardMaterial3D
var ring_mat: StandardMaterial3D

func _ready() -> void:
	add_to_group("alchemy_bombs")  # 巨虎靠这个分组嗅探地面上的陷阱
	# 炸弹外壳与引信：暗色罐体 + 一点发光药芯，白盒阶段够读就行
	body_mesh = MeshInstance3D.new()
	var shell := SphereMesh.new()
	shell.radius = 0.26
	shell.height = 0.52
	body_mesh.mesh = shell
	core_mat = _unshaded(Color("c9a44a"), 1.0)
	body_mesh.material_override = core_mat
	body_mesh.position = Vector3(0, 0.26, 0)
	add_child(body_mesh)
	# 地面色环：布防完成后出现，引信期间收缩并转红
	ring = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.6
	disc.bottom_radius = 1.6
	disc.height = 0.02
	ring.mesh = disc
	ring_mat = _unshaded(Color(0.9, 0.5, 0.15, 0.35), 0.0)
	ring.material_override = ring_mat
	ring.position = Vector3(0, 0.03, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)
	body_entered.connect(_on_body_entered)

func _unshaded(color: Color, glow: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = glow
	return mat

## 抛物线飞向落点：平地距离越远飞得越久。
func throw_to(target: Vector3) -> void:
	var start := global_position
	var distance := Vector2(target.x - start.x, target.z - start.z).length()
	var flight := clampf(distance / 16.0, 0.28, 0.7)
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void:
		var point := start.lerp(target, t)
		point.y = lerpf(start.y, target.y, t) + sin(t * PI) * 1.5
		global_position = point
	, 0.0, 1.0, flight)
	tween.tween_callback(_arm)

func _arm() -> void:
	armed = true
	global_position.y = 0.06
	ring.visible = true

## 直接布防在指定位置：不走投掷的预埋方式（关卡预置与验证脚本用）。
func place_at(point: Vector3) -> void:
	global_position = Vector3(point.x, 0.06, point.z)
	_arm()

func _process(delta: float) -> void:
	clock += delta
	if not armed:
		# 抛出后由飞行落地触发布防；没经过投掷就按固定延时布防
		arm_timer -= delta
		if arm_timer <= 0.0:
			_arm()
		return
	if fuse < 0.0:
		# 待机：色环缓慢呼吸，提示这里埋了炸弹
		ring.scale = Vector3.ONE * (1.0 + 0.06 * sin(clock * 3.0))
		return
	fuse -= delta
	var ratio: float = maxf(0.0, fuse / FUSE_TIME)
	ring.scale = Vector3.ONE * (0.35 + ratio * 0.65)
	ring_mat.albedo_color = Color(1.0, 0.25 + ratio * 0.4, 0.15, 0.5)
	if fuse <= 0.0:
		_explode()

func _on_body_entered(body: Node3D) -> void:
	if not armed or exploded or fuse >= 0.0:
		return
	if body.is_in_group("enemies"):
		fuse = FUSE_TIME

func _explode() -> void:
	exploded = true
	monitoring = false
	GameAudio.play_sfx("explosion", global_position, -1.0)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.has_method("is_alive") or not enemy.is_alive():
			continue
		var offset: Vector3 = enemy.global_position - global_position
		offset.y = 0
		# 巨虎这类大体积目标按碰撞半径放宽判定，不然要贴到中心才算命中
		var extra := 0.0
		if enemy.has_method("hit_radius"):
			extra = enemy.hit_radius()
		if offset.length() - extra > EXPLOSION_RADIUS:
			continue
		var push := offset.normalized() * 9.0 if offset.length() > 0.05 else Vector3.ZERO
		enemy.take_damage(EXPLOSION_DAMAGE, push, self)
	_burst()
	queue_free()

func _burst() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var burst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	burst.mesh = sphere
	var mat := _unshaded(Color(1.0, 0.66, 0.28, 0.6), 0.0)
	burst.material_override = mat
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(burst)
	burst.global_position = global_position + Vector3(0, 0.7, 0)
	var tween := burst.create_tween()
	tween.set_parallel(true)
	tween.tween_property(burst, "scale", Vector3.ONE * EXPLOSION_RADIUS * 1.15, 0.32)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.36)
	tween.chain().tween_callback(burst.queue_free)
