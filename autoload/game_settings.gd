extends Node
## 玩家偏好设置：画面 / 声音 / 游玩 / 按键。落盘到 `user://settings.cfg`。
##
## 与 GameState 的分工：`save.cfg` 装的是**进度**（会被「开始新游戏」清掉），
## `settings.cfg` 装的是**偏好**（跟机器走，删档/换档都不该把音量与键位重置），
## 所以两者分开写 —— reset_progress() 不碰这份文件。
##
## 应用时机：本自动加载在第一个场景之前 `_ready`，窗口模式/音量在开机那一刻就位；
## 之后每次 set_* 都即时生效并落盘。相机、HUD、过场这些消费方读的是内存里的值，
## 所以改完立刻起作用，不需要重启游戏。
##
## 写盘策略比 GameState 简单：偏好档损坏最多回到默认值，不会丢进度，所以不做
## 「临时档 + rename + .bak」那套原子替换，直接写并在失败时报错。

const Prefs := preload("res://data/prefs.gd")

signal changed(section: String)

## 窗口模式。WINDOWED = 窗口；FULLSCREEN = 独占全屏（会切显示模式）；
## BORDERLESS = 无边框全屏（桌面分辨率铺满，切出去最不容易乱）。
enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }

const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_VERSION := 1

## 窗口可选分辨率（16:9，与 1920×1080 设计分辨率同比，缩放比都是整的）。
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
]
const RESOLUTION_LABELS := ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440"]
## 帧率上限档位（0 = 不限制）。60 是默认：垂直同步之外再兜一层，笔记本不会空转烧电。
const FPS_OPTIONS := [60, 90, 120, 144, 0]
const FPS_LABELS := ["60", "90", "120", "144", "不限制"]
## 镜头灵敏度倍率区间（1.0 = 原手感）。
const MIN_SENSITIVITY := 0.4
const MAX_SENSITIVITY := 2.0

var settings_path := SETTINGS_PATH
## 校验脚本可断写盘，避免跑一次验证就改掉真实偏好（与 GameState.persistence_enabled 同一约定）。
var persistence_enabled := true

# ---------------------------------------------------------------- 画面
## 用 int 而不是 WindowMode 类型：读取时要 clampi 兜底脏档，int 省掉一层枚举转换。
var window_mode: int = WindowMode.WINDOWED
var resolution := Vector2i(1920, 1080)
var vsync := true
var fps_limit := 60

# ---------------------------------------------------------------- 声音
## 0~100 的百分比：滑条与档位都用整数，写进配置也读得懂。落在总线上换算成 dB。
var master_volume := 100
var sfx_volume := 100
var music_volume := 70

# ---------------------------------------------------------------- 游玩
var camera_sensitivity := 1.0
var camera_invert_y := false
var cinematic_shake := true
var game_cursor := true

# ---------------------------------------------------------------- 按键
## 改键覆盖：动作名 → {"kind": "key"/"mouse", "code": int}。没列出的动作走工程默认键，
## 所以「恢复默认」只要清空这张表再让 InputMap 重读 project.godot 即可 —— 不必在代码里
## 再抄一份默认键位表（抄了就会和 project.godot 走偏）。
var key_overrides: Dictionary = {}

func _ready() -> void:
	load_settings()
	apply_all()

func _commit(section: String) -> void:
	save_settings()
	changed.emit(section)

func apply_all() -> void:
	apply_display()
	apply_audio()
	apply_keys()

# ---------------------------------------------------------------- 画面

## 立刻套用画面设置。headless（校验脚本）下 DisplayServer 是空驱动，整体跳过，
## 免得日志里塞满无意义的窗口调用警告。
func apply_display() -> void:
	Engine.max_fps = fps_limit
	if DisplayServer.get_name() == "headless":
		return
	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			# 先回窗口模式再定尺寸：独占全屏里设 size 是无效的，切回来才认得。
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			apply_resolution()
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

## 窗口尺寸与居中（全屏模式下不适用，由系统决定分辨率）。
func apply_resolution() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if window_mode != WindowMode.WINDOWED:
		return
	DisplayServer.window_set_size(resolution)
	var screen := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position((screen - resolution) / 2)

func set_window_mode(value: int) -> void:
	window_mode = clampi(value, WindowMode.WINDOWED, WindowMode.BORDERLESS)
	apply_display()
	_commit("display")

func set_resolution(value: Vector2i) -> void:
	if not RESOLUTIONS.has(value):
		return
	resolution = value
	apply_resolution()
	_commit("display")

func set_vsync(enabled: bool) -> void:
	vsync = enabled
	apply_display()
	_commit("display")

func set_fps_limit(value: int) -> void:
	fps_limit = value if FPS_OPTIONS.has(value) else 60
	Engine.max_fps = fps_limit
	_commit("display")

# ---------------------------------------------------------------- 声音

## 立刻套用音量。总线的声音走 default_bus_layout.tres（Master + SFX）。
func apply_audio() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume(Prefs.SFX_BUS, sfx_volume)
	_set_bus_volume(Prefs.MUSIC_BUS, music_volume)

## 按名取总线，缺了就现建一条挂在 Master 下：正常情况布局文件里已经有 SFX，
## 这里只是新克隆 / 布局文件丢失时的兜底，保证滑条永远有真实作用对象、不会是空操作。
func _bus_index(bus_name: String) -> int:
	var index := AudioServer.get_bus_index(bus_name)
	if index >= 0:
		return index
	AudioServer.add_bus()
	index = AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")
	return index

## 百分比 → dB。0 不写成 -inf dB，而是直接静音：-inf 在部分驱动上会有杂音。
func _set_bus_volume(bus_name: String, percent: int) -> void:
	var index := _bus_index(bus_name)
	var muted := percent <= 0
	AudioServer.set_bus_mute(index, muted)
	AudioServer.set_bus_volume_db(index, -80.0 if muted else linear_to_db(percent / 100.0))

func set_master_volume(value: int) -> void:
	master_volume = clampi(value, 0, 100)
	apply_audio()
	_commit("audio")

func set_sfx_volume(value: int) -> void:
	sfx_volume = clampi(value, 0, 100)
	apply_audio()
	_commit("audio")

func set_music_volume(value: int) -> void:
	music_volume = clampi(value, 0, 100)
	apply_audio()
	_commit("audio")

# ---------------------------------------------------------------- 游玩
# 这四项不需要「套用」：消费方（机位 / 过场 / HUD）用的时候即时来读，
# 所以改完下一帧就生效，也不会在切场景时被谁覆盖回旧值。

func set_camera_sensitivity(value: float) -> void:
	camera_sensitivity = clampf(value, MIN_SENSITIVITY, MAX_SENSITIVITY)
	_commit("gameplay")

func set_camera_invert_y(enabled: bool) -> void:
	camera_invert_y = enabled
	_commit("gameplay")

func set_cinematic_shake(enabled: bool) -> void:
	cinematic_shake = enabled
	_commit("gameplay")

func set_game_cursor(enabled: bool) -> void:
	game_cursor = enabled
	_commit("gameplay")

# ---------------------------------------------------------------- 按键

## 开机把已存的改键套回 InputMap。必须在第一个场景之前跑完，否则场景脚本读到的还是默认键。
func apply_keys() -> void:
	for action in key_overrides.keys():
		var entry: Variant = key_overrides[action]
		if not InputMap.has_action(str(action)) or not (entry is Dictionary):
			continue
		var event := _make_event(str(entry.get("kind", "key")), int(entry.get("code", 0)))
		if event == null:
			continue
		InputMap.action_erase_events(str(action))
		InputMap.action_add_event(str(action), event)

## 改键：把某个动作整体换成单个事件。新键若已被别的动作占用，就把对方那一个事件摘掉；
## 摘完对方一个键都不剩时，把自己原来的键让给它（对调）—— 否则会留下「按不出来」的动作。
## 对调的结果同样记进覆盖表：只改 InputMap 不落盘的话，重启后对方会被工程默认键顶回来，
## 于是两个动作撞在同一个键上（默认动作都是单事件，所以这里只会走「摘空并换手」这条分支）。
func rebind(action: String, kind: String, code: int) -> void:
	var target := _make_event(kind, code)
	if target == null or not InputMap.has_action(action):
		return
	var previous := InputMap.action_get_events(action)
	for other in InputMap.get_actions():
		if str(other) == action:
			continue
		for event in InputMap.action_get_events(other):
			if not _matches(event, kind, code):
				continue
			InputMap.action_erase_event(other, event)
			if InputMap.action_get_events(other).is_empty() and not previous.is_empty():
				InputMap.action_add_event(other, previous[0])
				var swapped := _describe_event(previous[0])
				if not swapped.is_empty():
					key_overrides[str(other)] = swapped
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, target)
	key_overrides[action] = {"kind": kind, "code": code}
	_commit("keys")

## 恢复默认键位：让 InputMap 重读 project.godot 的 [input]（那才是默认值的正本），再清空覆盖表。
## 注意这会重置**全部**动作，包括玩家没改过的 —— 与「恢复默认」的字面意思一致。
func reset_keys() -> void:
	InputMap.load_from_project_settings()
	key_overrides.clear()
	_commit("keys")

func has_key_overrides() -> bool:
	return not key_overrides.is_empty()

## 键位事件构造：kind 为 "key" 时按物理键位（跟键盘布局无关，AZERTY 也不会错位），
## 为 "mouse" 时按鼠标键号。
static func _make_event(kind: String, code: int) -> InputEvent:
	if kind == "mouse":
		var button := InputEventMouseButton.new()
		button.button_index = code
		return button
	if kind == "key":
		var key := InputEventKey.new()
		key.physical_keycode = code
		return key
	return null

static func _matches(event: InputEvent, kind: String, code: int) -> bool:
	if event is InputEventMouseButton:
		return kind == "mouse" and (event as InputEventMouseButton).button_index == code
	if event is InputEventKey:
		var key := event as InputEventKey
		var bound := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return kind == "key" and bound == code
	return false

## _make_event 的逆运算：把一个已有事件描述成可存盘的形式（改键对调时要把对方的旧键记下来）。
## 与脚本层的 KeyBindings.binding_of 同口径；这里单独一份是为了不让数据层的自动加载
## 反过来依赖 UI 层的按键表。
static func _describe_event(event: InputEvent) -> Dictionary:
	if event is InputEventMouseButton:
		return {"kind": "mouse", "code": (event as InputEventMouseButton).button_index}
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code != 0:
			return {"kind": "key", "code": code}
	return {}

# ---------------------------------------------------------------- 读写

func save_settings() -> void:
	if not persistence_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "resolution", resolution)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "fps_limit", fps_limit)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("gameplay", "camera_sensitivity", camera_sensitivity)
	cfg.set_value("gameplay", "camera_invert_y", camera_invert_y)
	cfg.set_value("gameplay", "cinematic_shake", cinematic_shake)
	cfg.set_value("gameplay", "game_cursor", game_cursor)
	cfg.set_value("keys", "overrides", key_overrides)
	var error := cfg.save(settings_path)
	if error != OK:
		push_error("设置写入失败：%s" % error_string(error))

## 读盘。逐项校验取值合法性：手改过的档、旧版本残留都不该让游戏跑在非法状态上，
## 任何一项不合法就退回该内置项的默认值。
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	window_mode = clampi(int(cfg.get_value("display", "window_mode", window_mode)), 0, WindowMode.BORDERLESS)
	var saved_res: Variant = cfg.get_value("display", "resolution", resolution)
	if saved_res is Vector2i and RESOLUTIONS.has(saved_res):
		resolution = saved_res
	vsync = bool(cfg.get_value("display", "vsync", vsync))
	var saved_fps := int(cfg.get_value("display", "fps_limit", fps_limit))
	fps_limit = saved_fps if FPS_OPTIONS.has(saved_fps) else 60
	master_volume = clampi(int(cfg.get_value("audio", "master", master_volume)), 0, 100)
	sfx_volume = clampi(int(cfg.get_value("audio", "sfx", sfx_volume)), 0, 100)
	music_volume = clampi(int(cfg.get_value("audio", "music", music_volume)), 0, 100)
	camera_sensitivity = clampf(float(cfg.get_value("gameplay", "camera_sensitivity", camera_sensitivity)), MIN_SENSITIVITY, MAX_SENSITIVITY)
	camera_invert_y = bool(cfg.get_value("gameplay", "camera_invert_y", camera_invert_y))
	cinematic_shake = bool(cfg.get_value("gameplay", "cinematic_shake", cinematic_shake))
	game_cursor = bool(cfg.get_value("gameplay", "game_cursor", game_cursor))
	var saved_keys: Variant = cfg.get_value("keys", "overrides", {})
	if saved_keys is Dictionary:
		key_overrides = saved_keys
