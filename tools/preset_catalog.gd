class_name HD2DPresetCatalog
extends RefCounted
## 查询已导入本工程的 HD-2D 共享库预设。
## 导入后的素材路径规则：res://assets/hd2d_presets/{assets,scenes}/<标题>_<8位哈希>.<ext>

const ASSET_DIR := "res://assets/hd2d_presets/assets"
const SCENE_DIR := "res://assets/hd2d_presets/scenes"

static var _index: Dictionary = {}

## 标题 -> 资源路径（首次调用扫描一次目录并缓存）。
static func index() -> Dictionary:
	if not _index.is_empty():
		return _index
	var dir := DirAccess.open(ASSET_DIR)
	if dir == null:
		return _index
	for file in dir.get_files():
		var name := file.trim_suffix(".remap")
		if not name.ends_with(".tres"):
			continue
		var title := name.trim_suffix(".tres").get_slice("_", 0)
		var stem := name.trim_suffix(".tres")
		var hash_start := stem.rfind("_")
		if hash_start > 0:
			title = stem.substr(0, hash_start)
		_index[title] = ASSET_DIR.path_join(name)
	return _index

static func path_of(title: String) -> String:
	return str(index().get(title, ""))

static func asset(title: String) -> HD2DAsset:
	var path := path_of(title)
	if path.is_empty():
		push_error("预设未导入工程：" + title)
		return null
	return load(path) as HD2DAsset

## 批量取素材；缺失的标题会打印出来并跳过。
static func assets(titles: PackedStringArray) -> Array[HD2DAsset]:
	var result: Array[HD2DAsset] = []
	for title in titles:
		var item := asset(title)
		if item:
			result.append(item)
	return result
