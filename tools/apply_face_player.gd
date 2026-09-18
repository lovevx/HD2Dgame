extends SceneTree
## 把“始终绕 Y 轴朝向玩家”写进素材的朝向字段：立着的薄片植物与扁平立式道具。
## 只改 HD2DAsset.facing，外观、图集、碰撞与场景摆放都不动。
## 植物按素材自身的分类筛选（共享库的“植被”，丛林包装的“乔木 / 地被”），不靠文件名硬编码。
const PRESET_DIR := "res://local_study/preset3d/assets"
const JUNGLE_DIR := "res://assets/environments/jungle/props"
const JUNGLE_PLANT_CATEGORIES := ["丛林 / 乔木", "丛林 / 地被"]
## 扁平立式道具：屏风与渔网。木箱、架子、桌椅这类有体积的道具不在此列。
const FLAT_PROPS := ["SM_Item_pingfeng001", "SM_Item_pingfeng002", "SM_jiangnan_yuwang001", "SM_jiangnan_yuwang002"]
const FACE_PLAYER := 2
var changed := 0
var untouched := 0

func _initialize() -> void:
	if not patch_dir(PRESET_DIR, false) or not patch_dir(JUNGLE_DIR, true):
		return
	print("FACE_PLAYER_APPLY: PASS (changed=%d untouched=%d)" % [changed, untouched])
	quit()

func patch_dir(dir_path: String, jungle: bool) -> bool:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Missing asset directory: " + dir_path)
		quit(1)
		return false
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var asset := load(dir_path.path_join(file)) as HD2DAsset
		if asset == null:
			push_error("Not an HD2D asset: " + file)
			quit(1)
			return false
		if not wants_face_player(asset, jungle):
			untouched += 1
			continue
		if asset.facing == FACE_PLAYER:
			continue
		asset.facing = FACE_PLAYER
		var error := ResourceSaver.save(asset, asset.resource_path)
		if error != OK:
			push_error("Save failed: " + asset.resource_path)
			quit(1)
			return false
		changed += 1
		print("face player: " + asset.resource_path)
	return true

func wants_face_player(asset: HD2DAsset, jungle: bool) -> bool:
	if jungle:
		return asset.category in JUNGLE_PLANT_CATEGORIES
	return asset.category == "植被" or asset.title in FLAT_PROPS
