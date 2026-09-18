@tool
class_name HD2DCharacterProfile
extends Resource
@export var title: String = "角色"
@export var frames: SpriteFrames
@export_enum("2:2", "4:4", "8:8") var directions: int = 4
## Keys: idle_s, walk_s, idle_ne ...; values: actual SpriteFrames animation names.
@export var mapping: Dictionary = {}
@export var foot_anchor: Vector2 = Vector2(0.5,1.0)
@export_range(0.001,0.1,0.001) var pixel_size: float = 0.025
@export_range(0.1,3,0.05) var collider_radius: float = 0.3
@export_range(0.2,5,0.05) var collider_height: float = 1.5
@export_range(0,20,0.1) var move_speed: float = 4.0
@export var shaded: bool = false
@export var flip_h: bool = false
## Optional explicit reuse of a supplied side view, e.g. ["e"]. No new frames are generated.
@export var mirror_directions: PackedStringArray = []
## Full camera-facing billboard keeps a sprite readable at a steep camera pitch.
@export var full_billboard: bool = false
@export var color_tint: Color = Color(1,0.975,0.86,1)
@export var contact_shadow: bool = true
@export var projected_shadow: bool = false

func resolve(action: String, direction: String) -> StringName:
	if frames == null: return &""
	var key := action+"_"+direction
	var candidates := [String(mapping.get(key,key))]
	for mapped_key in mapping:
		if str(mapped_key).begins_with(action+"_"): candidates.append(str(mapping[mapped_key]))
	candidates.append_array([action+"_s",action,action.capitalize(),"idle_s","idle","Idle","default"])
	for candidate in candidates:
		if frames.has_animation(candidate) and frames.get_frame_count(candidate)>0: return StringName(candidate)
	for candidate in frames.get_animation_names():
		if frames.get_frame_count(candidate)>0: return candidate
	return &""

func warnings() -> PackedStringArray:
	var result := PackedStringArray()
	if frames == null:
		result.append("尚未导入帧。")
		return result
	var dirs := ["e","w"] if directions==2 else (["s","w","n","e"] if directions==4 else ["s","sw","w","nw","n","ne","e","se"])
	for action in ["idle","walk"]:
		for dir in dirs:
			var requested := String(mapping.get(action+"_"+dir,action+"_"+dir))
			if not frames.has_animation(requested) or frames.get_frame_count(requested)==0:
				result.append("缺少 %s_%s → 回退到 %s（不生成/镜像新素材）" % [action,dir,resolve(action,dir)])
	return result
