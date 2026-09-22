extends SceneTree
## 一次性探测：量出「任务所 / 工坊」候选预设的世界包围盒（含 mesh 累计变换），
## 供布局时判断进深、高度与原点是否在脚底中心。

const Catalog := preload("res://tools/preset_catalog.gd")

const TITLES := [
	# 建筑（民居 / 铺面 / 武馆 / 客店）
	"SM_JN_fangzi001", "SM_JN_fangzi002", "SM_JN_fangzi003", "SM_JN_fangzi005",
	"SM_JN_fangzi006", "SM_JN_fangzi007",
	"SM_xgg_fangzi001", "SM_xgg_fangzi004",
	"SM_hpsz_fangzi001", "SM_hpsz_fangzi002", "SM_hpsz_fangzi004", "SM_hpsz_fangzi005",
	"SM_NJ_Fangzi011", "SM_NJ_Fangzi012", "SM_NJ_WuGuan001", "SM_NJ_JiuGuan001",
	"SM_mjsz_fangzi003", "SM_linchang_fangzi032", "SM_jzc_cunminjia001",
	"SM_kushuicun_pofangzi002", "SM_LC_fangzi002", "SM_wmd_fangzi008",
	"SM_JN_wuguan001", "SM_JN_kezhan001", "SM_JN_Damen001",
	"SM_NJ_LouKongFangzi002", "SM_NJ_LouKongFangzi004",
	"SM_Wuxianjiao_fangzi001", "SM_Wuxianjiao_fangzi002",
	"SM_hpsz_dameng001", "SM_hpsz_dameng002", "SM_hpsz_dameng003",
	"SM_hpsz_gelou001", "SM_hpsz_gongmen001", "SM_JN_Gongmen001",
	# 工坊
	"SM_Item_luzi001", "SM_Item_luzi003", "SM_Item_zaotai001", "SM_Item_yancong002",
	"SM_Item_Nwuqi001", "SM_Item_Nwuqi005", "SM_Item_Nwuqi007", "SM_Item_Nwuqi008",
	"SM_Item_Chengshakuang001", "SM_Item_Tiekuang001", "SM_Item_Hantiekuang001",
	"SM_Item_Huangtongkuang001", "SM_Item_Wujingkuang001", "SM_Item_Yingkuang001",
	"SM_Item_muchai001", "SM_Item_guopen001", "SM_Item_guopen002",
	"SM_gsc_gu001", "SM_gsc_gu002", "SM_NJ_Shitoudui001",
	"SM_Item_stone005", "SM_Item_stone008", "SM_Item_damoshuijing001",
	"SM_Item_zhaidaozhuzi001", "SM_Item_jiutanzi04", "SM_Item_daizi001", "SM_Item_daizi003",
	"SM_Item_kaozhejian001", "SM_Item_xianhe001", "SM_Item_muxiang002",
	"SM_Item_NJhuojia001", "SM_Item_NJhuojia002", "SM_Item_NJhuojia003",
	"SM_Item_NJhuojia004", "SM_Item_NJhuojia006", "SM_Item_NJhuojia016",
	"SM_Item_NJtanwei001", "SM_Item_NJtanwei002", "SM_jzc_mapeng001",
	"SM_Item_louti", "SM_NJ_MuLouTi001", "SM_NJ_Fudiaodiban_002", "SM_mjsz_diban001",
	# 任务所
	"SM_xgg_yjzpjuanzhou001", "SM_xgg_yjzptong001", "SM_xgg_yuanjunyizi001",
	"SM_Item_guitai002", "SM_Item_paizi002", "SM_xgg_jiangjunfupaizi001",
	"SM_NJ_ZhuPai002", "SM_gsc_gusuchengpaizi001", "SM_Item_Chuanggong001",
	"SM_Item_chahu001", "SM_Item_chabei001", "SM_SZ_zhuozi001",
	"SM_NJ_ZhuZhuozi001", "SM_NJ_ZhuYizi001", "SM_mjsz_shizhuozi001",
	"SM_mjsz_shidengzi001", "SM_mjsz_Mudunzi001", "SM_xhj_shenkan002",
	"SM_Item_fenghuangbei001", "SM_Wuxianjiao_qizi003", "SM_Item_pingfeng001",
	"SM_Item_pingfeng002", "SM_NJ_MenDong001", "SM_NJ_PingTai001",
	"SM_mjsz_jianxintingpaizi001", "SM_mjsz_moxiegepaizi001",
	"SM_mjsz_muban001", "SM_mjsz_muban002", "SM_Item_taidenglong001",
	"SM_Item_xianglu001", "SM_Item_lianzi001", "SM_Item_lianzi005",
	"SM_NJ_ShiDeng_001", "SM_NJ_ZhuPengzi001", "SM_Item_shishizi001",
	"SM_Item_gouhuo001", "SM_Item_zhuzibaoguo001", "SM_Item_diaoyu002",
	"SM_Item_xianglu001", "SM_NJ_HuoyaoMuxiangzi_002", "SM_mjsz_taijie001",
]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("PROBE: %-34s %5s  %-24s %-24s" % ["title", "parts", "size(x,y,z)", "min(x,y,z)"])
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
		print("PROBE: %-34s %5d  (%6.2f,%6.2f,%6.2f)  (%6.2f,%6.2f,%6.2f)   max=(%6.2f,%6.2f,%6.2f)" % [
			title, parts.size(), box.size.x, box.size.y, box.size.z,
			box.position.x, box.position.y, box.position.z,
			box.end.x, box.end.y, box.end.z])
	quit(0)

func _world_aabb(part: Dictionary) -> AABB:
	var mesh: Mesh = part["mesh"]
	var xform: Transform3D = part["transform"]
	return xform * mesh.get_aabb()
