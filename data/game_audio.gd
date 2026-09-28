extends RefCounted
## 脚本层声音入口。自动加载尚未注册的早期校验环境里会安静跳过。

const AUTOLOAD_NAME := "AudioManager"
static var _cached_manager: Node = null

static func play_sfx(sound_id: String, world_position := Vector3.INF, volume_db := 0.0, pitch_scale := 1.0) -> void:
	var manager := _manager()
	if manager != null:
		manager.call("play_sfx", sound_id, world_position, volume_db, pitch_scale)

static func play_stream(stream: AudioStream, world_position := Vector3.INF, volume_db := 0.0, pitch_scale := 1.0) -> void:
	var manager := _manager()
	if manager != null:
		manager.call("play_stream", stream, world_position, volume_db, pitch_scale)

static func _manager() -> Node:
	if _cached_manager != null and is_instance_valid(_cached_manager):
		return _cached_manager
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		_cached_manager = (loop as SceneTree).root.get_node_or_null(AUTOLOAD_NAME)
	return _cached_manager
