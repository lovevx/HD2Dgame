extends RefCounted
## 设置项的「按路径读取」入口，以及设定的常量。给**不能直接写 `GameSettings.` 的脚本**用。
##
## 为什么存在这一层：`GameSettings` 是自动加载，直接用标识符最省事，但自动加载名在被
## tools/ 里的校验脚本于**文件顶层 preload** 间接带进来时还没注册（那时是 --script 的解析
## 阶段），直接引用会编译失败、脚本静默降级，再往后崩成「函数不存在」。
## 按节点路径取在任何上下文都成立，所以相机机位与过场这类脚本统一走这里。
## 面板 / HUD / 主菜单（只由场景在运行时实例化）直接用 GameSettings 即可，不必绕。
##
## 用法：`const Prefs := preload("res://data/prefs.gd")` → `Prefs.value("camera_sensitivity", 1.0)`

## 音效总线名（正本在 res://default_bus_layout.tres）：主音量外唯一一条总线。
## GameSettings 按它调音量、dash_fx 按它挂播放器，两边不会各写一个字符串。
const SFX_BUS := "SFX"

## 设置自动加载的节点名（与 project.godot 的 [autoload] 一致）。
const AUTOLOAD_NAME := "GameSettings"

## 缓存：首次取到后就记住，免得每次鼠标拖动都走一遍 get_node_or_null。
static var _cached: Node = null

## 取设置节点；进程里还没有自动加载（校验脚本早期、纯数据测试）时返回 null。
static func node() -> Node:
	if _cached != null and is_instance_valid(_cached):
		return _cached
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var root := (loop as SceneTree).root
		if root != null:
			_cached = root.get_node_or_null(AUTOLOAD_NAME)
	return _cached

## 读一项设置：设置节点不在（或没有这个键）时返回 fallback，调用方不必自己判空。
static func value(key: String, fallback: Variant) -> Variant:
	var settings := node()
	if settings == null:
		return fallback
	var raw: Variant = settings.get(key)
	return fallback if raw == null else raw
