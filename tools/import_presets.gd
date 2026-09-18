extends SceneTree
## 从 HD-2D Scene Tools 共享素材库挑取预设并复制进本工程。
## 路径规则与插件 editor/shared_library.gd 的 prepare_files 保持一致：
##   源文件 = <库根>/<preset.payload>/<file.path>，目标 = res://<file.path>
##   .import 侧车优先写入索引里保存的 import_config 原文，让 Godot 重新生成缓存。
## 用法（工程根目录）：
##   godot --headless --script tools/import_presets.gd -- --list=<正则>
##   godot --headless --script tools/import_presets.gd -- --titles=A,B,C [--dry-run]
##   godot --headless --script tools/import_presets.gd -- --series=SM_GuSuCheng
## 复制完成后另跑一次 `godot --headless --import` 生成导入缓存。

const DEFAULT_LIBRARY := "D:/BaiduNetdiskDownload/HD2D_Shared_Asset_Library/HD2D_Shared_Asset_Library"
const ENV_LIBRARY := "HD2D_SHARED_LIBRARY"

var library := ""
var copied := 0
var skipped := 0
var conflicts := 0
var missing := 0
var copied_bytes := 0
var problems: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var options := parse_args(OS.get_cmdline_user_args())
	library = str(options.get("library", OS.get_environment(ENV_LIBRARY) if not OS.get_environment(ENV_LIBRARY).is_empty() else DEFAULT_LIBRARY)).simplify_path()
	var index_path := library.path_join("preset-index.json")
	if not FileAccess.file_exists(index_path):
		push_error("找不到共享库索引：" + index_path)
		quit(1); return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
	if not data is Dictionary or not data.get("entries") is Array:
		push_error("共享库索引格式不正确：" + index_path)
		quit(1); return
	var entries: Array = data.entries

	if options.has("list"):
		list_entries(entries, str(options.list)); quit(0); return

	var selected := select_entries(entries, options)
	if selected.is_empty():
		push_error("没有匹配到任何预设；可用 --list=<正则> 先查看。")
		quit(1); return
	var dry_run := bool(options.get("dry-run", false))
	print("IMPORT_PRESETS: 命中 %d 条预设，库=%s%s" % [selected.size(), library, "（试运行）" if dry_run else ""])
	for entry in selected:
		import_entry(entry, dry_run)
	print("IMPORT_PRESETS: copied=%d skipped=%d conflicts=%d missing=%d bytes=%d" % [copied, skipped, conflicts, missing, copied_bytes])
	for line in problems.slice(0, 20):
		print("IMPORT_PRESETS_PROBLEM: " + line)
	quit(0 if conflicts == 0 and missing == 0 else 1)

# ------------------------------------------------------------------ 参数

func parse_args(args: PackedStringArray) -> Dictionary:
	var options := {}
	for arg in args:
		var text := str(arg)
		if not text.begins_with("--"):
			continue
		var body := text.trim_prefix("--")
		var key := body.get_slice("=", 0)
		options[key] = body.split("=", true, 1)[1] if body.contains("=") else true
	return options

func select_entries(entries: Array, options: Dictionary) -> Array:
	var wanted_titles := str(options.get("titles", "")).split(",", false)
	var series := str(options.get("series", ""))
	var pattern := str(options.get("match", ""))
	var result: Array = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var title := str(entry.get("title", ""))
		if not wanted_titles.is_empty() and not wanted_titles.has(title):
			continue
		if not series.is_empty() and str(entry.get("series", "")) != series:
			continue
		if not pattern.is_empty():
			var re := RegEx.new()
			if re.compile(pattern) != OK:
				push_error("正则无效：" + pattern); return []
			if re.search(title) == null:
				continue
		result.append(entry)
	return result

func list_entries(entries: Array, pattern: String) -> void:
	var re := RegEx.new()
	if re.compile(pattern) != OK:
		push_error("正则无效：" + pattern); return
	for entry in entries:
		if not entry is Dictionary:
			continue
		var title := str(entry.get("title", ""))
		if re.search(title) == null:
			continue
		var bounds: Array = entry.get("bounds", [])
		var size := "%.2f x %.2f x %.2f" % [float(bounds[0]), float(bounds[1]), float(bounds[2])] if bounds.size() == 3 else "-"
		print("%s\t%s\t%s\t%s" % [title, entry.get("category", ""), entry.get("series", ""), size])

# ------------------------------------------------------------------ 复制

func import_entry(entry: Dictionary, dry_run: bool) -> void:
	var payload := library.path_join(str(entry.get("payload", "")))
	for file in entry.get("files", []):
		if not file is Dictionary:
			continue
		var relative := str(file.get("path", ""))
		if relative.is_empty() or relative.is_absolute_path() or relative.contains(".."):
			problems.append("无效路径：" + relative); missing += 1; continue
		var destination := ProjectSettings.globalize_path("res://" + relative)
		var checksum := str(file.get("sha256", ""))
		if FileAccess.file_exists(destination):
			if not checksum.is_empty() and FileAccess.get_sha256(destination) != checksum:
				problems.append("工程内已有不同内容，未覆盖：" + relative); conflicts += 1
			else:
				skipped += 1
			continue
		var config_text := str(file.get("import_config", "")) if relative.ends_with(".import") else ""
		if dry_run:
			copied += 1; continue
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		if not config_text.is_empty():
			var output := FileAccess.open(destination, FileAccess.WRITE)
			if output == null or not write_text(output, config_text) or FileAccess.get_sha256(destination) != checksum:
				problems.append("导入配置写入校验失败：" + relative); missing += 1; continue
		else:
			var source := payload.path_join(relative)
			if not FileAccess.file_exists(source):
				problems.append("共享库缺少文件：" + relative); missing += 1; continue
			if not checksum.is_empty() and FileAccess.get_sha256(source) != checksum:
				problems.append("共享库文件校验失败，请重新解压共享库：" + relative); missing += 1; continue
			if DirAccess.copy_absolute(source, destination) != OK:
				problems.append("复制失败：" + relative); missing += 1; continue
		copied += 1
		var written := FileAccess.open(destination, FileAccess.READ)
		if written:
			copied_bytes += written.get_length()
			written.close()

func write_text(output: FileAccess, text: String) -> bool:
	output.store_string(text)
	output.flush()
	output.close()
	return true
