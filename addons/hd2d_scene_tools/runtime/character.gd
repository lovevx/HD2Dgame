@tool
class_name HD2DCharacter
extends CharacterBody3D
@export var profile: HD2DCharacterProfile:
	set(value):
		profile=value
		if is_inside_tree(): rebuild.call_deferred()
@export var keyboard_control: bool = true
@export var preview_active: bool = false
@export_range(1,80,1) var slope_limit_degrees: float = 46.0
var sprite: AnimatedSprite3D
var projected: AnimatedSprite3D
var facing: String = "s"
var external_input := Vector2.ZERO
var external_control := false
var input_enabled := true
var stage_walk_animation := false

func _ready() -> void:
	rebuild()
	floor_snap_length=0.6
	floor_constant_speed=true
	floor_max_angle=deg_to_rad(slope_limit_degrees)

func rebuild() -> void:
	for node in get_children():
		if node.has_meta("hd2d_generated"):
			remove_child(node)
			node.queue_free()
	if profile == null or profile.frames == null: return
	sprite=AnimatedSprite3D.new()
	sprite.set_meta("hd2d_generated",true)
	sprite.name="SpriteVisual"
	sprite.sprite_frames=profile.frames
	sprite.pixel_size=profile.pixel_size
	sprite.alpha_cut=SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded=profile.shaded
	sprite.flip_h=profile.flip_h
	sprite.modulate=profile.color_tint
	sprite.double_sided=true
	sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED if profile.full_billboard else BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(sprite)
	sprite.frame_changed.connect(_align_feet)
	play_action("idle")
	var collision := CollisionShape3D.new()
	collision.name="BodyCollider"
	collision.set_meta("hd2d_generated",true)
	var capsule := CapsuleShape3D.new()
	capsule.radius=profile.collider_radius
	capsule.height=maxf(profile.collider_height,2*profile.collider_radius)
	collision.shape=capsule
	collision.position.y=capsule.height*0.5
	add_child(collision)
	projected=null
	if profile.projected_shadow:
		projected=AnimatedSprite3D.new()
		projected.name="ProjectedShadow"; projected.set_meta("hd2d_generated",true)
		projected.sprite_frames=profile.frames; projected.pixel_size=profile.pixel_size
		projected.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
		projected.flip_h=profile.flip_h; projected.modulate=Color(0.14,0.11,0.025,0.34)
		projected.basis=Basis(Vector3(0.88,0,0),Vector3(-0.48,0,3.6),Vector3(0,-1,0))
		projected.position.y=0.02; projected.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(projected)
	if profile.contact_shadow:
		var contact := MeshInstance3D.new(); contact.name="ContactShadow"; contact.set_meta("hd2d_generated",true)
		var plane := PlaneMesh.new(); plane.size=Vector2(profile.collider_radius*2.5,profile.collider_radius*1.4)
		contact.mesh=plane; contact.position.y=0.012
		var mat := ShaderMaterial.new(); mat.shader=preload("../shaders/contact_shadow.gdshader")
		contact.material_override=mat; contact.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(contact)
	_align_feet()
	update_configuration_warnings()

func _align_feet() -> void:
	if not is_instance_valid(sprite) or profile.frames == null: return
	if profile.frames.get_frame_count(sprite.animation)==0: return
	var texture := profile.frames.get_frame_texture(sprite.animation,sprite.frame)
	if texture:
		sprite.offset=Vector2((0.5-profile.foot_anchor.x)*texture.get_width(),(profile.foot_anchor.y-0.5)*texture.get_height())
		if is_instance_valid(projected):
			projected.animation=sprite.animation; projected.frame=sprite.frame; projected.offset=sprite.offset

func set_movement_input(value: Vector2) -> void:
	external_control=true
	external_input=value.limit_length(1.0)

func release_external_input() -> void:
	external_control=false
	external_input=Vector2.ZERO

func play_action(action: String) -> void:
	if not is_instance_valid(sprite): return
	var animation := profile.resolve(action,facing)
	sprite.flip_h=profile.flip_h != profile.mirror_directions.has(facing)
	if is_instance_valid(projected): projected.flip_h=sprite.flip_h
	if animation != &"": sprite.play(animation)

func direction_for(value: Vector2) -> String:
	if profile.directions==2: return "e" if value.x>=0 else "w"
	if profile.directions==4:
		if absf(value.x)>absf(value.y): return "e" if value.x>0 else "w"
		return "s" if value.y>0 else "n"
	var index := posmod(int(round(atan2(value.x,value.y)/(PI/4))),8)
	return ["s","se","e","ne","n","nw","w","sw"][index]

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() and not preview_active: return
	if profile==null: return
	var movement := external_input if external_control else Vector2.ZERO
	if keyboard_control and not external_control and input_enabled:
		movement=Vector2(float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))-float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))-float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))).limit_length(1)
	if not input_enabled: movement=Vector2.ZERO
	if movement.length_squared()>0.01: facing=direction_for(movement)
	velocity.x=movement.x*profile.move_speed
	velocity.z=movement.y*profile.move_speed
	velocity.y-=20.0*delta
	move_and_slide()
	play_action("walk" if movement.length_squared()>0.01 or stage_walk_animation else "idle")

func _get_configuration_warnings() -> PackedStringArray:
	return profile.warnings() if profile else PackedStringArray(["请在角色面板导入角色配置。"])
