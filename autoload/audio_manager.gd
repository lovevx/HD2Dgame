extends Node
## 全局声音入口：音乐随场景淡入淡出，战斗音效通过统一 SFX 总线播放。

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const MAX_ACTIVE_SFX := 24
const MUSIC_FADE_SECONDS := 0.9
const COMBAT_POLL_SECONDS := 0.75

const SOUND_PATHS := {
	"ui_hover": "res://assets/audio/synth/sfx/ui_hover.wav",
	"ui_confirm": "res://assets/audio/synth/sfx/ui_confirm.wav",
	"ui_back": "res://assets/audio/synth/sfx/ui_back.wav",
	"sword_swing": "res://assets/audio/synth/sfx/sword_swing.wav",
	"kick": "res://assets/audio/synth/sfx/kick.wav",
	"magic_cast": "res://assets/audio/synth/sfx/magic_cast.wav",
	"healing": "res://assets/audio/synth/sfx/healing.wav",
	"gunshot": "res://assets/audio/synth/sfx/gunshot.wav",
	"bomb": "res://assets/audio/synth/sfx/bomb.wav",
	"explosion": "res://assets/audio/synth/sfx/explosion.wav",
	"enemy_attack": "res://assets/audio/synth/sfx/enemy_attack.wav",
	"enemy_hit": "res://assets/audio/synth/sfx/enemy_hit.wav",
	"enemy_death": "res://assets/audio/synth/sfx/enemy_death.wav",
	"player_hurt": "res://assets/audio/synth/sfx/player_hurt.wav",
	"coin": "res://assets/audio/synth/sfx/coin.wav",
	"pickup": "res://assets/audio/synth/sfx/pickup.wav",
	"chest": "res://assets/audio/synth/sfx/chest.wav",
	"quest_complete": "res://assets/audio/synth/sfx/quest_complete.wav",
	"boss_roar": "res://assets/audio/synth/sfx/boss_roar.wav",
	"footstep": "res://assets/audio/synth/sfx/footstep.wav",
}

const MUSIC_PATHS := {
	"title": "res://assets/audio/synth/music/title.wav",
	"harbor": "res://assets/audio/synth/music/harbor.wav",
	"journey": "res://assets/audio/synth/music/journey.wav",
	"battle": "res://assets/audio/synth/music/battle.wav",
}

var _stream_cache: Dictionary = {}
var _voices: Array[Node] = []
var _music_players: Array[AudioStreamPlayer] = []
var _music_slot := 0
var _music_fade: Tween
var _current_theme := ""
var _base_theme := "title"
var _combat_probe := 0.0
var _combat_quiet_time := 0.0
var _last_ui_button_id := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in 2:
		var player := AudioStreamPlayer.new()
		player.name = "MusicPlayer%d" % index
		player.bus = MUSIC_BUS
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_music_players.append(player)
	get_tree().node_added.connect(_on_node_added)
	get_tree().scene_changed.connect(_on_scene_changed)
	call_deferred("_sync_current_scene")

func _process(delta: float) -> void:
	_combat_probe -= delta
	if _combat_probe > 0.0:
		return
	_combat_probe = COMBAT_POLL_SECONDS
	_update_combat_music()

func play_sfx(sound_id: String, world_position := Vector3.INF, volume_db := 0.0, pitch_scale := 1.0) -> void:
	var path: String = SOUND_PATHS.get(sound_id, "")
	if path.is_empty():
		return
	var stream := _load_stream(path)
	if stream == null:
		return
	_play_stream(stream, SFX_BUS, world_position, volume_db, pitch_scale)

func play_stream(stream: AudioStream, world_position := Vector3.INF, volume_db := 0.0, pitch_scale := 1.0) -> void:
	if stream == null:
		return
	_play_stream(stream, SFX_BUS, world_position, volume_db, pitch_scale)

func play_music(theme: String) -> void:
	if theme == _current_theme or not MUSIC_PATHS.has(theme):
		return
	var stream := _load_stream(str(MUSIC_PATHS[theme]))
	if stream == null:
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		var channels := 2 if wav.stereo else 1
		wav.loop_begin = 0
		wav.loop_end = int(wav.data.size() / (2 * channels))

	if _music_fade != null and _music_fade.is_running():
		_music_fade.kill()
	var old_player := _music_players[_music_slot]
	var next_slot := 1 - _music_slot
	var next_player := _music_players[next_slot]
	next_player.stop()
	next_player.stream = stream
	next_player.volume_db = -36.0
	next_player.play()
	_music_slot = next_slot
	_current_theme = theme
	_music_fade = create_tween().set_parallel(true)
	_music_fade.tween_property(next_player, "volume_db", 0.0, MUSIC_FADE_SECONDS)
	if old_player.playing:
		_music_fade.tween_property(old_player, "volume_db", -42.0, MUSIC_FADE_SECONDS)
	_music_fade.finished.connect(_stop_faded_music.bind(old_player, next_player), CONNECT_ONE_SHOT)

func _play_stream(stream: AudioStream, bus_name: String, world_position: Vector3, volume_db: float, pitch_scale: float) -> void:
	var scene := get_tree().current_scene
	var voice: Node
	if world_position != Vector3.INF and is_instance_valid(scene) and scene is Node3D:
		var spatial := AudioStreamPlayer3D.new()
		spatial.unit_size = 4.0
		spatial.max_distance = 28.0
		spatial.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		spatial.stream = stream
		spatial.bus = bus_name
		spatial.volume_db = volume_db
		spatial.pitch_scale = pitch_scale
		voice = spatial
		scene.add_child(spatial)
		spatial.global_position = world_position
	else:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = bus_name
		player.volume_db = volume_db
		player.pitch_scale = pitch_scale
		voice = player
		add_child(player)
	voice.finished.connect(_release_voice.bind(voice), CONNECT_ONE_SHOT)
	_voices.append(voice)
	while _voices.size() > MAX_ACTIVE_SFX:
		_release_voice(_voices[0])
	voice.play()

func _release_voice(voice: Node) -> void:
	_voices.erase(voice)
	if is_instance_valid(voice):
		voice.queue_free()

func _load_stream(path: String) -> AudioStream:
	if not _stream_cache.has(path):
		_stream_cache[path] = load(path) as AudioStream
	return _stream_cache[path] as AudioStream

func _stop_faded_music(old_player: AudioStreamPlayer, new_player: AudioStreamPlayer) -> void:
	if _music_players[_music_slot] == new_player and old_player != new_player:
		old_player.stop()

func _sync_current_scene() -> void:
	_on_scene_changed()


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if not is_instance_valid(scene):
		return
	_bind_ui_tree(scene)
	_base_theme = _theme_for_scene(scene)
	_combat_quiet_time = 0.0
	play_music(_base_theme)

func _theme_for_scene(scene: Node) -> String:
	var path := scene.scene_file_path.to_lower()
	if path.contains("main_menu") or path.contains("level_select"):
		return "title"
	if path.contains("opening_boat"):
		return "journey"
	if path.contains("harbor") or path.contains("campaign"):
		return "harbor"
	if path.contains("world") or path.contains("freewalk") or path.contains("colpo"):
		return "journey"
	return "journey" if scene is Node3D else "title"

func _update_combat_music() -> void:
	if _base_theme not in ["harbor", "journey"]:
		return
	var combat_active := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(enemy) and enemy.has_method("is_alive") and enemy.is_alive():
			combat_active = true
			break
	if combat_active:
		_combat_quiet_time = 0.0
		if _current_theme != "battle":
			play_music("battle")
	elif _current_theme == "battle":
		_combat_quiet_time += COMBAT_POLL_SECONDS
		if _combat_quiet_time >= 7.5:
			play_music(_base_theme)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		call_deferred("_bind_ui_button", node)

func _bind_ui_tree(node: Node) -> void:
	if node is BaseButton:
		_bind_ui_button(node)
	for child in node.get_children():
		_bind_ui_tree(child)

func _bind_ui_button(node: Node) -> void:
	if not is_instance_valid(node) or not node is BaseButton:
		return
	var button := node as BaseButton
	if button.has_meta("audio_manager_bound"):
		return
	button.set_meta("audio_manager_bound", true)
	var button_ref: WeakRef = weakref(button)
	button.mouse_entered.connect(_on_ui_button_targeted.bind(button_ref))
	button.mouse_exited.connect(_on_ui_button_left.bind(button_ref))
	button.focus_entered.connect(_on_ui_button_targeted.bind(button_ref))
	button.pressed.connect(_on_ui_button_pressed)

func _on_ui_button_targeted(button_ref: WeakRef) -> void:
	var button := button_ref.get_ref() as BaseButton
	if not is_instance_valid(button) or button.disabled:
		return
	var button_id := button.get_instance_id()
	if button_id == _last_ui_button_id:
		return
	_last_ui_button_id = button_id
	play_sfx("ui_hover", Vector3.INF, -11.0)

func _on_ui_button_left(button_ref: WeakRef) -> void:
	var button := button_ref.get_ref() as BaseButton
	if is_instance_valid(button) and button.get_instance_id() == _last_ui_button_id:
		_last_ui_button_id = 0

func _on_ui_button_pressed() -> void:
	play_sfx("ui_confirm", Vector3.INF, -5.0)
