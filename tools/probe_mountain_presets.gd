extends SceneTree
## 一次性探测：量出「科尔波山」候选素材的世界包围盒（悬崖 / 山石 / 点缀树），
## 供布局时判断占地、高度与拼接口径。

const Catalog := preload("res://tools/preset_catalog.gd")

const TITLES := [
	# 悬崖 / 山体主料
	"SM_Jiangnan_xuanya001", "SM_Jiangnan_xuanya002", "SM_Jiangnan_xuanya003",
	"SM_Jiangnan_xuanya004", "SM_Jiangnan_xuanya005", "SM_Jiangnan_xuanya007",
	# 石料点缀
	"SM_YX_Shitou001", "SM_DM_Zudangshitou001", "SM_NJ_Shitoudui001",
	# 山上点缀树（松柏 / 圆柏）
	"SM_1songbaiA01_LODs", "SM_1songbaiB01_LODs", "SM_1yuanbai01_LODs", "SM_1yuanbai02_LODs",
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("PROBE: %-30s %5s  %-24s %s" % ["title", "parts", "size(x,y,z)", "min(x,y,z)"])
	for title in TITLES:
		var asset: HD2DAsset = Catalog.asset(title)
		if asset == null:
			print("PROBE: MISSING %s" % title)
			continue
		var parts := asset.mesh_parts()
		if parts.is_empty():
			print("PROBE: EMPTY   %s" % title)
			continue
		var box := _world_aabb(parts[0])
		for i in range(1, parts.size()):
			box = box.merge(_world_aabb(parts[i]))
		print("PROBE: %-30s %5d  (%6.2f,%6.2f,%6.2f)  (%6.2f,%6.2f,%6.2f)   max=(%6.2f,%6.2f,%6.2f)" % [
			title, parts.size(), box.size.x, box.size.y, box.size.z,
			box.position.x, box.position.y, box.position.z,
			box.end.x, box.end.y, box.end.z])
	quit(0)

func _world_aabb(part: Dictionary) -> AABB:
	var mesh: Mesh = part["mesh"]
	var xform: Transform3D = part["transform"]
	return xform * mesh.get_aabb()
