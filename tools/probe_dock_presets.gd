extends SceneTree
## 临时量具：打印码头相关预设的包围盒（世界单位，未缩放）与静态碰撞能力，
## 用于确定码头拼接的间距与贴合高度。用完即删。
## 用法：godot --headless --path . --script res://tools/probe_dock_presets.gd

const Catalog := preload("res://tools/preset_catalog.gd")

const TITLES := [
	"SM_JN_matou", "SM_Shore", "SM_JN_yuchuan003", "SM_JN_yuchuan004",
	"SM_YX_Dachuan004", "SM_JN_xiaochuan005", "SM_JN_xiaochuan006",
	"SM_LC_fangzi002", "SM_jzc_mapeng001", "SM_jzc_dengzi001",
	"SM_jiangnan_yuwang001", "SM_jiangnan_yuwang002", "SM_jzc_shuicao001",
	"SM_Licheng_shizhuzi001", "SM_Box001Close", "SM_Box001Open",
	"SM_Item_NJhuojia001", "SM_Item_NJtanwei001", "SM_JN_shikuai002",
	"SM_mjsz_Mudunzi001", "SM_mjsz_muzhuzi001", "SM_mjsz_shidengzi001",
	"SM_NJ_ZhuPengzi001", "SM_NJ_Shitoudui001", "SM_YX_Shiban001",
	"SM_YX_Shiban006", "SM_mjsz_muban001", "SM_mjsz_muban002",
	"SM_jzc_taijie003", "SM_JN_Chengshakuang001", "SM_Item_Chengshakuang001",
	"SM_hpsz_weilan111zuo", "SM_NJ_Zhuziweilan001", "SM_ltem_Shuiche001",
	"SM_JN_wuguan001", "SM_JN_yaogui001", "SM_JN_Gongmen001",
	"SM_NJ_ShiDeng_001", "SM_JN_Huipaiweiqiang001", "SM_YX_Shitou001",
	"SM_DM_Zudangshitou001", "SM_Nanjiang_YYPshidun002", "SM_NJ_Shitoudui001",
	"SM_JN_Weiqiang001", "SM_JN_Weiqiang002", "SM_NJ_ZhuPai002",
	"SM_XYNJiangnan003", "SM_XYNJiangnan005", "SM_XYNJiangnan006",
	"SM_XYNJiangnan007", "SM_XYNJiangnan008", "SM_XYNJiangnan012",
	"SM_XYNJiangnan016", "SM_XYNJiangnan018", "SM_XYNJiangnan019",
	"SM_XYNJiangnan026", "SM_XYNJiangnan027", "SM_XYNJiangnan029",
	"SM_XYNJiangnan030", "SM_XYNJiangnan035", "SM_jzc_taijie111",
	"SM_jzc_taijie112", "SM_Nanjiang_taijie005", "SM_Nanjiang_taijie006",
	"SM_Wjiangnan_fancheng001", "SM_Item_NJhuojia003", "SM_Item_NJtanwei002",
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for title in TITLES:
		var asset: HD2DAsset = Catalog.asset(title)
		if asset == null:
			print("MISSING  ", title)
			continue
		var node := asset.make_node()
		root.add_child(node)
		var aabb := _bounds(node)
		print("PROBE %-28s size=(%.2f, %.2f, %.2f) min=(%.2f, %.2f, %.2f) max=(%.2f, %.2f, %.2f) parts=%d collision=%s" % [
			title, aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.position.x, aabb.position.y, aabb.position.z,
			aabb.end.x, aabb.end.y, aabb.end.z,
			asset.mesh_parts().size(), str(asset.static_collision),
		])
		root.remove_child(node)
		node.free()
	quit(0)

func _bounds(node: Node) -> AABB:
	var total := AABB()
	var started := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is GeometryInstance3D and (current as GeometryInstance3D).mesh:
			pass
			var local: AABB = (current as GeometryInstance3D).mesh.get_aabb()
			var xform: Transform3D = (current as Node3D).transform
			var here: AABB = xform * local
			total = here if not started else total.merge(here)
			started = true
		for child in current.get_children():
			stack.append(child)
	return total
