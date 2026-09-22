extends SceneTree
## 设置页校验：设置档的读写与非法值兜底、四类设置是否真的作用到消费方
## （画面 → DisplayServer/Engine、声音 → 音频总线、游玩 → 相机机位 / HUD 光标、按键 → InputMap），
## 以及两个入口的面板接入（主菜单「设置」按钮、游戏内 Esc 菜单 + 模态冻结）。
## 跑法：godot --headless --path . --script res://tools/validate_settings.gd
##
## 场景与脚本一律在 run() 里 load()，不在文件顶层 preload —— 顶层 preload 会在自动加载
## 注册之前编译依赖，脚本会静默降级再崩（见 tools/ 的踩坑记录）。

const TestEnv := preload("res://tools/test_env.gd")

var failures := 0
var gs: Node
var settings: Node
var KeyBindings
var Prefs

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	if value:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

## 子树里全部 Label 与 Button 的文字（设置页的行是「文字标签 + 选项按钮」，两者都要算上）。
func texts(node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += child.text + "\n"
		elif child is Button:
			out += child.text + "\n"
		out += texts(child)
	return out

## 子树里全部 Button 的文字。
func button_texts(node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Button:
			out.append(child.text)
		out += button_texts(child)
	return out

## 找「标题 = title」那一行右侧的控件文字（设置页的行都是 HBox：左标题 + 右控件）。
func row_text(panel, title: String) -> String:
	for row in panel._content.get_children():
		if not (row is HBoxContainer):
			continue
		var labels: Array = []
		for child in row.get_children():
			if child is Label:
				labels.append(child.text)
		if labels.size() > 0 and labels[0] == title:
			for child in row.get_children():
				if child is Button:
					return child.text
			if labels.size() > 1:
				return str(labels[1])
	return ""

func key_event(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func run() -> void:
	await process_frame
	gs = root.get_node("GameState")
	settings = root.get_node("GameSettings")
	KeyBindings = preload("res://scripts/ui/key_bindings.gd")
	Prefs = preload("res://data/prefs.gd")
	TestEnv.isolate(gs, "settings")
	# 偏好档要真写盘才验得了往返，所以这里 keep_persistence=true；路径仍隔离在测试专属文件上。
	var settings_path := TestEnv.isolate_settings(settings, "settings", true)

	# ---------- 设置档：非法值兜底 ----------
	var cfg := ConfigFile.new()
	cfg.set_value("display", "window_mode", 9)
	cfg.set_value("display", "fps_limit", 37)
	cfg.set_value("display", "resolution", Vector2i(1234, 567))
	cfg.set_value("audio", "master", 9999)
	cfg.set_value("gameplay", "camera_sensitivity", 99.0)
	cfg.save(settings_path)
	settings.load_settings()
	check(int(settings.window_mode) == 2, "非法窗口模式夹回合法档位（9 → 无边框全屏）")
	check(int(settings.fps_limit) == 60, "非法帧率档位回落到 60")
	check(settings.resolution == Vector2i(1920, 1080), "非法分辨率回落到内置默认")
	check(int(settings.master_volume) == 100, "超范围音量夹到 100")
	check(is_equal_approx(float(settings.camera_sensitivity), 2.0), "超范围灵敏度夹到上限")

	# 档不存在时不该把内存值冲掉（手滑删档不该变成「全部静默重置」）
	TestEnv.purge(settings_path)
	settings.fps_limit = 144
	settings.load_settings()
	check(int(settings.fps_limit) == 144, "设置档缺失时保留内存里的值")

	# ---------- 设置档：写入 / 读回往返 ----------
	settings.set_master_volume(37)
	settings.set_sfx_volume(64)
	settings.set_fps_limit(0)
	settings.set_camera_invert_y(true)
	settings.set_cinematic_shake(false)
	check(FileAccess.file_exists(settings_path), "改动后偏好档落盘")
	settings.master_volume = 1
	settings.sfx_volume = 1
	settings.fps_limit = 144
	settings.camera_invert_y = false
	settings.cinematic_shake = true
	settings.load_settings()
	check(int(settings.master_volume) == 37, "主音量读回 37")
	check(int(settings.sfx_volume) == 64, "音效音量读回 64")
	check(int(settings.fps_limit) == 0, "帧率上限读回「不限制」")
	check(bool(settings.camera_invert_y), "镜头上下反转读回开")
	check(not bool(settings.cinematic_shake), "过场震动读回关")
	settings.set_fps_limit(60)
	settings.set_camera_invert_y(false)
	settings.set_cinematic_shake(true)

	# ---------- 画面：设置真的作用到引擎 ----------
	settings.set_fps_limit(0)
	check(Engine.max_fps == 0, "帧率上限写入 Engine.max_fps（不限制）")
	settings.set_fps_limit(90)
	check(Engine.max_fps == 90, "帧率上限写入 Engine.max_fps（90）")
	settings.set_fps_limit(60)
	settings.set_window_mode(9)
	check(int(settings.window_mode) == 2, "窗口模式接口按合法区间夹取")
	settings.set_window_mode(0)
	settings.set_resolution(Vector2i(1234, 567))
	check(settings.resolution != Vector2i(1234, 567), "非档位内的分辨率被拒绝")
	settings.set_resolution(Vector2i(1280, 720))
	check(settings.resolution == Vector2i(1280, 720), "档位内的分辨率被接受")
	settings.set_resolution(Vector2i(1920, 1080))
	settings.apply_display()  # headless 下必须是空操作而不是报错
	check(true, "headless 下 apply_display 不报错")

	# ---------- 声音：音频总线 ----------
	var sfx_index := AudioServer.get_bus_index(Prefs.SFX_BUS)
	check(sfx_index >= 0, "存在 SFX 总线（default_bus_layout.tres）")
	# 上面那条只证明「总线在」，证明不了它来自布局文件而不是 GameSettings 的运行时兜底，
	# 所以再钉住「布局文件确实被工程引用且存在」，以及没有多余的总线。
	check(str(ProjectSettings.get_setting("audio/buses/default_bus_layout")) == "res://default_bus_layout.tres"
		and ResourceLoader.exists("res://default_bus_layout.tres"),
		"工程引用着随仓库分发的总线布局文件")
	check(AudioServer.bus_count == 2, "总线只有 Master + SFX 两条（没有多余总线）")
	settings.set_master_volume(50)
	var master_index := AudioServer.get_bus_index("Master")
	check(is_equal_approx(AudioServer.get_bus_volume_db(master_index), linear_to_db(0.5)),
		"主音量 50%% → %.2f dB" % AudioServer.get_bus_volume_db(master_index))
	check(not AudioServer.is_bus_mute(master_index), "音量非零时不静音总线")
	settings.set_sfx_volume(25)
	check(is_equal_approx(AudioServer.get_bus_volume_db(sfx_index), linear_to_db(0.25)),
		"音效音量 25% 独立落在 SFX 总线上")
	settings.set_sfx_volume(0)
	check(AudioServer.is_bus_mute(sfx_index), "音效音量 0 → 静音（不是 -inf dB）")
	settings.set_sfx_volume(100)
	settings.set_master_volume(100)

	# ---------- 游玩：相机机位读的是设置里的实时值 ----------
	var Orbit = load("res://scripts/world/camera_orbit_controls.gd")
	var orbit = Orbit.new()
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(100.0, 0.0)
	settings.set_camera_sensitivity(1.0)
	orbit.yaw_deg = 0.0
	orbit.handle_input(middle)
	orbit.handle_input(drag)
	var yaw_1x: float = orbit.yaw_deg
	check(is_equal_approx(yaw_1x, -100.0 * Orbit.ORBIT_SENSITIVITY), "1.0× 灵敏度 = 基准手感")
	settings.set_camera_sensitivity(2.0)
	orbit.yaw_deg = 0.0
	orbit.handle_input(drag)
	var yaw_2x: float = orbit.yaw_deg
	check(is_equal_approx(yaw_2x, yaw_1x * 2.0), "2.0× 灵敏度是基准的两倍（不需要重配机位）")
	settings.set_camera_sensitivity(1.0)
	# 上下反转只翻俯角方向
	var pitch_drag := InputEventMouseMotion.new()
	pitch_drag.relative = Vector2(0.0, 10.0)
	orbit.pitch_deg = 16.0
	orbit.handle_input(pitch_drag)
	var pitch_normal: float = orbit.pitch_deg
	settings.set_camera_invert_y(true)
	orbit.pitch_deg = 16.0
	orbit.handle_input(pitch_drag)
	var pitch_inverted: float = orbit.pitch_deg
	check(pitch_normal < 16.0 and pitch_inverted > 16.0,
		"上下反转把「下拉＝压低机位」翻成「下拉＝抬高机位」（%.1f / %.1f）" % [pitch_normal, pitch_inverted])
	check(is_equal_approx(pitch_inverted - 16.0, 16.0 - pitch_normal), "反转的幅度与正向一致")
	settings.set_camera_invert_y(false)

	# 过场震动开关：消费方与设置共用同一份 Prefs（Cinematic 只读这一个键）
	settings.set_cinematic_shake(false)
	check(not bool(Prefs.value("cinematic_shake", true)), "过场震动开关能被消费方（Cinematic 走的 Prefs）读到")
	settings.set_cinematic_shake(true)
	check(bool(Prefs.value("cinematic_shake", true)), "过场震动可以再打开")
	check(Prefs.node() == settings, "Prefs 按路径取到的就是 GameSettings 自动加载")

	# ---------- 按键：改键 / 冲突对调 / 恢复默认 ----------
	settings.rebind("dodge", "key", KEY_K)
	check(KeyBindings.key_text("dodge") == "K", "dodge 改绑到 K 并同步写入 InputMap")
	check(KeyBindings.key_text("kick") == "空格", "撞车的直踹（原 K）拿到 dodge 的旧键空格")
	# 与新键冲突：对方只剩一个键时与旧键对调，不留下「按不出来」的动作
	settings.rebind("potion", "key", KEY_K)
	check(KeyBindings.key_text("potion") == "K", "potion 抢到 K")
	check(KeyBindings.key_text("dodge") == "2", "被抢的 dodge 拿到 potion 原来的 2（对调）")
	check(InputMap.action_get_events("dodge").size() == 1, "对调后 dodge 仍有且只有一个键")
	# 不可绑定的输入（滚轮）不能被写成键位
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	check(KeyBindings.binding_of(wheel).is_empty(), "滚轮不是可绑定的键位")
	settings.rebind("dodge", "key", KEY_K)
	check(KeyBindings.key_text("dodge") == "K", "dodge 改回 K 用于往返断言")
	# 落盘 → 清空内存与 InputMap → 读回并套用
	settings.key_overrides = {}
	InputMap.load_from_project_settings()
	check(KeyBindings.key_text("dodge") == "空格", "清空覆盖表后回到工程默认键")
	settings.load_settings()
	settings.apply_keys()
	check(KeyBindings.key_text("dodge") == "K", "改键落盘后重启能读回")
	check(KeyBindings.key_text("kick") == "空格", "对调结果也落盘：重启后直踹不会和新键撞在同一个键上")
	settings.reset_keys()
	check(KeyBindings.key_text("dodge") == "空格" and not settings.has_key_overrides(),
		"恢复默认键位：InputMap 与覆盖表都清干净")
	check(KeyBindings.key_text("kick") == "K", "直踹默认绑在 K")
	check(KeyBindings.key_text("shoot") == "右键", "燧发枪默认绑在鼠标右键")
	check(KeyBindings.key_text("dodge") == "空格" and KeyBindings.key_text("potion") == "2", "恢复默认后 potion 也回到 2")

	# ---------- 提示条与 F1 说明：键名现读，改键后跟着变 ----------
	check(KeyBindings.hint_text().contains("空格 剃") and KeyBindings.hint_text().contains("右键 枪"),
		"底部提示条按 InputMap 现读键名")
	settings.rebind("dodge", "key", KEY_K)
	check(KeyBindings.hint_text().contains("K 剃"), "改键后提示条文案跟着变")
	settings.reset_keys()
	check(KeyBindings.hint_text().contains("空格 剃"), "恢复默认后提示条也跟着回默认")

	# ---------- 面板层：主菜单入口 ----------
	var menu = load("res://scenes/main/main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var panel = menu.settings_panel
	check(panel != null and panel.is_in_group("settings_panel"), "主菜单里挂上了设置面板")
	check(button_texts(menu).has("设 置"), "主菜单有「设置」按钮")
	check(not panel.visible, "设置面板默认收起")
	panel.open()
	check(panel.visible, "open() 打开面板")
	check(texts(panel._content).contains("窗口模式"), "默认页是「画面」")
	panel._select_page("audio")
	check(texts(panel._content).contains("主音量") and texts(panel._content).contains("音效音量"), "声音页有两条音量")
	panel._select_page("gameplay")
	check(texts(panel._content).contains("镜头灵敏度"), "游玩页有镜头灵敏度")
	panel._select_page("keys")
	var keys_text := texts(panel._content)
	var missing: Array = []
	for entry in KeyBindings.REBINDABLE:
		if not keys_text.contains(str(entry["label"])):
			missing.append(entry["label"])
	check(missing.is_empty(), "按键页列出了全部 %d 个可改键动作%s" % [
		KeyBindings.REBINDABLE.size(), "" if missing.is_empty() else "，缺：" + str(missing)])
	check(keys_text.contains("鼠标中键拖动取景"), "按键页说明了哪些手势改不了")
	check(row_text(panel, "六式・剃（闪避）") == "空格", "改键行显示当前键位（空格）")
	panel._select_page("display")
	check(texts(panel._content).contains("无边框全屏"), "画面页列出全部窗口模式")
	# 捕获流程：点格子 → 按键 → 落定；Esc 取消
	var dodge_button := Button.new()
	panel._select_page("keys")
	panel._begin_capture("dodge", dodge_button)
	check(panel._capturing and panel._capture_button == dodge_button, "点改键格进入捕获态")
	panel._input(key_event(KEY_K))
	check(not panel._capturing, "按键后退出捕获态")
	check(KeyBindings.key_text("dodge") == "K", "捕获的按键写进了 InputMap")
	check(KeyBindings.key_text("move_left") == "A", "其它动作没被牵连")
	panel._begin_capture("dodge", dodge_button)
	panel._input(key_event(KEY_ESCAPE))
	check(not panel._capturing and KeyBindings.key_text("dodge") == "K", "捕获中按 Esc 只取消绑定，不改键")
	settings.reset_keys()
	check(KeyBindings.key_text("dodge") == "空格", "面板测试后键位回默认")
	# Esc 关闭（面板自己的兜底路径）
	panel._input(key_event(KEY_ESCAPE))
	check(not panel.visible, "Esc 兜底关闭设置面板")
	menu.free()
	await process_frame

	# ---------- 面板层：游戏内 Esc 菜单 + 模态冻结 ----------
	gs.reset_progress()
	gs.complete_contract("设置验收")
	gs.begin_onboarding()
	var scene = load("res://scenes/main/campaign.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var hud = scene.hud
	var hud_panel = hud.settings_panel
	check(hud_panel != null and hud_panel.is_in_group("settings_panel"), "HUD 里挂上了设置面板")
	check(button_texts(hud.menu).has("设 置 · 画面 / 声音 / 按键"), "Esc 菜单里有「设置」入口")
	check(not hud.is_modal_open(), "默认设置面板不算模态")
	check(hud.wants_game_cursor(), "默认用游戏内光标")
	hud._open_settings()
	check(hud_panel.visible and hud.is_modal_open(), "开设置后成为模态面板")
	check(not hud.wants_game_cursor(), "面板开着时交还系统光标")
	check(not scene.player.is_physics_processing(), "战役控制器接管：开设置时冻结玩家")
	# 模态面板开着时相机不吃滚轮（与任务面板同一套 is_modal_open 口径）
	var orbit2 = scene.world._orbit
	var wheel_up := InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	var dist_before: float = orbit2.distance
	scene.world._input(wheel_up)
	check(is_equal_approx(orbit2.distance, dist_before), "设置面板开着时滚轮不推拉镜头")
	var open_event := InputEventAction.new()
	open_event.action = "open_menu"
	open_event.pressed = true
	hud._unhandled_input(open_event)
	check(not hud_panel.visible and not hud.is_modal_open(), "Esc（open_menu）关掉设置面板")
	check(scene.player.is_physics_processing(), "关掉设置后恢复玩家物理")
	scene.world._input(wheel_up)
	check(orbit2.distance < dist_before, "关掉设置后滚轮恢复推拉镜头")
	# 玩家选了系统光标：HUD 不再隐藏系统光标
	settings.set_game_cursor(false)
	check(not hud.wants_game_cursor(), "设置里选系统光标后 HUD 不再用游戏内光标")
	settings.set_game_cursor(true)
	check(hud.wants_game_cursor(), "选回游戏内光标后恢复")
	# 改键后 HUD 底部提示条要重算（_on_settings_changed 是唯一刷新点）
	settings.rebind("dodge", "key", KEY_K)
	check(hud.hint_bar.text.contains("K 剃"), "改键后 HUD 底部提示条立即跟着变")
	settings.reset_keys()
	check(hud.hint_bar.text.contains("空格 剃"), "恢复默认后 HUD 提示条也回到默认")
	# 剃的音效挂在 SFX 总线上（设置页的音效滑条才管得到它）
	var dash_fx = scene.player.get_node_or_null("DashFX")
	check(dash_fx != null, "玩家身上有 DashFX")
	var audio_buses: Array = []
	for child in dash_fx.get_children():
		if child is AudioStreamPlayer:
			audio_buses.append(child.bus)
	check(audio_buses.size() == 3 and audio_buses.count(Prefs.SFX_BUS) == 3,
		"剃的 3 个音效播放器都挂在 SFX 总线上（%s）" % str(audio_buses))

	print("----------------------------------------")
	if failures == 0:
		print("设置页校验：全部 PASS")
	else:
		print("设置页校验：%d 项 FAIL" % failures)
	TestEnv.cleanup(gs)
	TestEnv.cleanup_settings(settings)
	scene.free()
	await process_frame
	quit(1 if failures > 0 else 0)
