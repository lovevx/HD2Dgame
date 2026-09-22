extends Node3D
## 剃（六式・剃）的表现特效：残影、尘土、破空气流与三段音效。
## 只读取 player 的闪避状态来驱动表现，不参与任何战斗逻辑。

enum Phase { IDLE, WINDUP, BURST }

const Prefs := preload("res://data/prefs.gd")

const STOMP_SOUND := preload("res://assets/audio/dash/dash_stomp.mp3")
const WHOOSH_SOUND := preload("res://assets/audio/dash/dash_whoosh.mp3")
const LAND_SOUND := preload("res://assets/audio/dash/dash_land.mp3")

const AFTERIMAGE_INTERVAL := 0.15  # 残影生成间隔
const AFTERIMAGE_LIFE := 0.28  # 单个残影渐隐时长
const AFTERIMAGE_COLOR := Color(0.72, 0.78, 0.85, 0.55)  # 半透明灰
const DUST_COLOR := Color(0.66, 0.71, 0.76, 0.5)
const DUST_TEX_SIZE := 16

## 残影只取角色图的 alpha 作为剪影，再整体涂成灰色。
## 直接用 modulate 是乘算，黑衣乘灰色仍是黑色，会看不见。
const AFTERIMAGE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;
uniform sampler2D ghost_texture : hint_default_white, filter_nearest;
uniform vec4 ghost_tint : source_color = vec4(0.72, 0.78, 0.85, 0.55);
void vertex() {
	// 手动 billboard，让残影始终面向相机
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	ALBEDO = ghost_tint.rgb;
	ALPHA = texture(ghost_texture, UV).a * ghost_tint.a;
}
"""

@onready var player: CharacterBody3D = get_parent()
@onready var sprite: AnimatedSprite3D = get_parent().get_node("pivot/CharacterSprite")

var phase: int = Phase.IDLE
var afterimage_timer: float = 0.0
var _ghost_shader: Shader
var _stomp_dust: CPUParticles3D
var _land_dust: CPUParticles3D
var _trail: CPUParticles3D
var _stomp_audio: AudioStreamPlayer
var _whoosh_audio: AudioStreamPlayer
var _land_audio: AudioStreamPlayer

func _ready() -> void:
	_ghost_shader = Shader.new()
	_ghost_shader.code = AFTERIMAGE_SHADER
	var dust_texture := _make_dust_texture()
	# 颗粒尺寸按角色比例定：角色约 1.7 米 / 107 像素，单个灰粒取 4~9 像素
	_stomp_dust = _add_dust("StompDust", 16, 0.45, 1.0, 2.4, 0.13, 0.5, dust_texture)
	_land_dust = _add_dust("LandDust", 24, 0.60, 1.4, 3.0, 0.16, 0.5, dust_texture)
	_trail = _add_dust("DashTrail", 20, 0.35, 0.2, 0.8, 0.07, 0.4, dust_texture)
	_trail.one_shot = false
	_trail.explosiveness = 0.0
	_trail.position = Vector3(0, 0.5, 0)
	_stomp_audio = _add_audio(STOMP_SOUND)
	_whoosh_audio = _add_audio(WHOOSH_SOUND)
	_land_audio = _add_audio(LAND_SOUND)

func _process(delta: float) -> void:
	var next := _current_phase()
	if next != phase:
		_enter_phase(next, phase)
		phase = next
	if phase == Phase.BURST:
		_tick_afterimage(delta)

## 把闪避拆成蓄力与爆发两段，作为特效的触发时机。
func _current_phase() -> int:
	if not player.alive or not player.dodging:
		return Phase.IDLE
	if player.dodge_duration - player.dodge_timer < player.DODGE_WINDUP:
		return Phase.WINDUP
	return Phase.BURST

func _enter_phase(next: int, previous: int) -> void:
	match next:
		Phase.WINDUP:
			# 蓄力踩踏：脚掌砸地，尘土碎石向外崩起
			_stomp_dust.restart()
			_stomp_audio.play()
		Phase.BURST:
			# 爆发启动：破空声、稀薄气流，并在旧位置开始留残影
			afterimage_timer = 0.0
			_trail.emitting = true
			_whoosh_audio.play()
		Phase.IDLE:
			afterimage_timer = 0.0
			_trail.emitting = false
			# 只有真正冲出去过才算落地，避免刚按下就中断时误触发
			if previous == Phase.BURST and player.alive:
				_land_dust.restart()
				_land_audio.play()

## 爆发冲刺期间每隔一小段在旧位置留一个灰色剪影，自行渐隐后释放。
func _tick_afterimage(delta: float) -> void:
	afterimage_timer -= delta
	if afterimage_timer > 0.0:
		return
	afterimage_timer = AFTERIMAGE_INTERVAL
	_spawn_afterimage()

func _spawn_afterimage() -> void:
	var host := player.get_parent()
	if host == null:
		return
	var frame_texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if frame_texture == null:
		return
	var ghost := Sprite3D.new()
	ghost.texture = frame_texture
	ghost.pixel_size = sprite.pixel_size
	ghost.offset = sprite.offset
	ghost.flip_h = sprite.flip_h
	ghost.texture_filter = sprite.texture_filter
	var material := ShaderMaterial.new()
	material.shader = _ghost_shader
	material.set_shader_parameter("ghost_texture", frame_texture)
	material.set_shader_parameter("ghost_tint", AFTERIMAGE_COLOR)
	ghost.material_override = material
	ghost.add_to_group("dash_afterimages")
	host.add_child(ghost)
	ghost.global_position = global_position
	# 渐隐通过 shader 的 tint 透明度完成，不能用 modulate（乘算对黑衣无效）
	var faded := AFTERIMAGE_COLOR
	faded.a = 0.0
	var tween := ghost.create_tween()
	tween.tween_property(material, "shader_parameter/ghost_tint", faded, AFTERIMAGE_LIFE)
	tween.tween_callback(ghost.queue_free)

## 生成一张中心实、边缘虚的像素灰尘贴图，省掉额外资源与导入步骤。
func _make_dust_texture() -> ImageTexture:
	var size := DUST_TEX_SIZE
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := (size - 1) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(x - center, y - center).length() / (size * 0.5)
			if distance > 1.0:
				continue
			# 量化成 4 级透明度，保持像素颗粒感
			var alpha := roundf(pow(1.0 - distance, 1.5) * 4.0) / 4.0
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)

## base_size 为单颗粒的基础边长（米），scale_min 是相对基础尺寸的最小缩放。
## 尺寸主要靠网格定，缩放只做轻微变化，避免受粒子缩放参数影响而失控。
func _add_dust(node_name: String, amount: int, lifetime: float, velocity_min: float, velocity_max: float,
		base_size: float, scale_min: float, texture: Texture2D) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.name = node_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.direction = Vector3.UP
	particles.spread = 85.0
	particles.initial_velocity_min = velocity_min
	particles.initial_velocity_max = velocity_max
	particles.gravity = Vector3(0, -4.5, 0)
	particles.scale_amount_min = scale_min
	particles.scale_amount_max = 1.0
	particles.color = DUST_COLOR
	# 沿生命周期由实到虚，尘土才像扬起来又散掉
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1.0))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	particles.color_ramp = ramp
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 0.16
	particles.position = Vector3(0, 0.06, 0)
	particles.emitting = false
	var quad := QuadMesh.new()
	quad.size = Vector2(base_size, base_size)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = texture
	quad.material = material
	particles.mesh = quad
	particles.add_to_group("dash_particles")
	add_child(particles)
	return particles

func _add_audio(stream: AudioStream) -> AudioStreamPlayer:
	var audio := AudioStreamPlayer.new()
	audio.stream = stream
	audio.volume_db = -5.0
	# 挂在 SFX 总线上，设置页的「音效」滑条才管得到它（正本见 res://default_bus_layout.tres）。
	audio.bus = Prefs.SFX_BUS
	add_child(audio)
	return audio
