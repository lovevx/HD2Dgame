extends SceneTree
## 一次性探测：量出「装饰景观」候选素材的世界包围盒（植被 / 围栏 / 水车 / 未用民居），
## 供布局时判断占地、高度与碰撞口径。

const Catalog := preload("res://tools/preset_catalog.gd")

const TITLES := [
	# 建筑（未用过的民居 / 铺面 / 棚屋）
	"SM_JN_fangzi003", "SM_JN_fangzi007",
	"SM_xgg_fangzi001", "SM_xgg_fangzi004",
	"SM_NJ_LouKongFangzi004", "SM_NJ_Fangzi012",
	"SM_jzc_mapeng001", "SM_jzc_cunminjia001",
	"SM_linchang_fangzi032", "SM_JN_Liushanmenfudian003",
	# 乔木
	"SM_1dashu001", "SM_1dashu002", "SM_Dataoshu001", "SM_Dataoshu002",
	"SM_taoshu001", "SM_taoshu002", "SM_1taoshu111_LODs",
	"SM_1songbaiA01_LODs", "SM_1songbaiB01_LODs", "SM_1songbaiC01_LODs",
	"SM_1yuanbai01_LODs", "SM_1yuanbai02_LODs",
	"SM_NJ_Jvqingshu001", "SM_NJ_Gurongshu001_2", "SM_Item_yjdashu003",
	# 灌木 / 草 / 地被
	"SM_HD_Guanmu001", "SM_HD_Guanmu005", "SM_HD_Guanmu007", "SM_HD_Guanmu009",
	"SM_changzacao001", "SM_aicao001", "SM_NJ_CSD_Huacao024", "SM_sz_fuhuocao001LLL",
	"SM_NJ_Yvlinzhiwu001", "SM_NJ_Yvlinzhiwu002", "SM_NJ_Yvlinzhiwu003",
	"SM_zhuzi005_2", "SM_zhuzi006_2", "SM_zhuzi008_2", "SM_zhuzi010_2",
	# 围栏 / 院墙 / 台阶
	"SM_NJ_Zhuziweilan001", "SM_NJ_Zhuziweilan002",
	"SM_mjsz_weilan001", "SM_hpsz_weilan111zuo",
	"SM_mjsz_qiang001", "SM_mjsz_qiang002", "SM_xgg_qiang001",
	"SM_mjsz_taijie001", "SM_NJ_MuLouTi001",
	# 水岸与生活景观
	"SM_ltem_Shuiche001", "SM_gsc_qiao001", "SM_JN_Xiaoqiao001",
	"SM_NJ_Gongqiao001", "SM_NJ_Zhuqiao001",
	"SM_Wuxianjiao_shidun001", "SM_YX_Shitou001", "SM_DM_Zudangshitou001",
	"SM_Item_NJshaizi002", "SM_Item_gouhuo001", "SM_Item_jiutanzi04",
	"SM_Item_diaoyu003", "SM_Item_Chuanggong001", "SM_Item_xianhe001",
	"SM_xhj_shenkan002", "SM_Item_NJtanwei001",
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("PROBE: %-32s %5s  %-24s %s" % ["title", "parts", "size(x,y,z)", "min(x,y,z)"])
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
		print("PROBE: %-32s %5d  (%6.2f,%6.2f,%6.2f)  (%6.2f,%6.2f,%6.2f)   max=(%6.2f,%6.2f,%6.2f)" % [
			title, parts.size(), box.size.x, box.size.y, box.size.z,
			box.position.x, box.position.y, box.position.z,
			box.end.x, box.end.y, box.end.z])
	quit(0)

func _world_aabb(part: Dictionary) -> AABB:
	var mesh: Mesh = part["mesh"]
	var xform: Transform3D = part["transform"]
	return xform * mesh.get_aabb()
