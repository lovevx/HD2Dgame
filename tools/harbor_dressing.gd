extends RefCounted
## 港口装饰景观层：给已经成形的「商店区 / 工坊 / 任务所 / 码头」补血肉，
## 但按"成组成片、主题分明、留白"来做，不往空地里撒点。
##
## 五个子区，各管一片：
##   EastQuarter  东侧民居坊（x∈[23,38]，强化巷东延以北）——两栋民居 + 房后竹林 + 竹栅栏小院
##   WestYard     西侧货栈院（x∈[-38,-28]，任务所副楼以西）——工棚、竹棚、箱堆、渔网、酒坛、篝火
##   ShoreGreen   岸线绿化（水岸 z≈11 的几段）——灌木草丛压住驳岸的生硬
##   GatePlaza    北门广场（传送门两侧）——石灯、招幌、贴城墙的背景林带
##   StreetGreen  主街南段与试炼场周边——路缘灌木、一棵桃树、演武场的旗与石墩
##
## 素材：只用已入库共享预设。实测要点（tools/probe_dressing_presets.gd）：
##   · 灌木/草/桃树/竹/松柏全是 facing=2 的薄片植物（运行时转向镜头，不会侧成一条线），
##     且预设自身不带碰撞 → COLLIDE_PRESET 摆下去就是纯装饰。
##   · SM_1dashu001 是 facing=0 的固定平面，低俯角下会侧成线，不用。
##   · SM_Item_yjdashu003 是真 3D 大树（12.3×14.0×14.9，自带碰撞），必须缩小着用。
##   · SM_hpsz_weilan111zuo 栅栏段 2.00×1.62×0.25，用 COLLIDE_BOX 给一段 2 米的实体。
##   · SM_ltem_Shuiche001 水车 2.89×2.89×1.30（实体），留给内港边。
##
## 布置约束（别踩）：
##   · 港口机位与玩家同 x，「镜头→玩家」的遮挡射线是 x=玩家 的竖列：
##     probe 落点在 x=0 / -4 / -5.7 / -8 / -20 / 16.5，凡 z 大于这些落点的高物一律别压进同列。
##     主街两侧的植物必须让树冠内缘留在 |x|≥3，高大乔木留在 |x|≥6。
##   · 服务点可达走廊神圣依旧：z=-9 与 z=1（x∈[-14,18]）、商店区走廊 z∈[-18.4,-17.6]。
##   · 码头贴岸开口（x∈[-8.2,8.2] 与 x∈[13.9,30.1] 的 z≈12）与内港喉口（x∈[8.1,13.9]）不摆东西。
##   · 北门通道 x∈[-4.4,4.4] 通往 z=-31.5，背景林从 x≤-8 起。
##   · check_harbor_port 的 (-20,0,-7) 历史断言：西区货栈整体收到 x≤-28。

const PortLayout := preload("res://tools/harbor_port_layout.gd")

const NODE_NAME := "HarborDressing"


static func make_node() -> Node3D:
	var holder := Node3D.new()
	holder.name = NODE_NAME
	east_quarter(holder)
	west_yard(holder)
	shore_green(holder)
	gate_plaza(holder)
	street_green(holder)
	return holder


## ---------------------------------------------------------------- 东侧民居坊
## 强化巷东延以北的两栋民居：两层楼压西端，单层屋收东端，房后一片竹林与松柏做纵深，
## 门前竹栅栏围出小院（正对两栋之间留门口）。工坊街的热闹到这里收成"住家"的安静。
static func east_quarter(holder: Node3D) -> void:
	# 民居两栋（只有南立面有门窗，一律 yaw 0 朝南）。
	PortLayout.prop(holder, "SM_JN_fangzi003", Vector3(26.5, 0.0, -16.0), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_JN_fangzi007", Vector3(33.0, 0.0, -16.0), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 房后竹林：两三株成组、错位，配上松柏，把贴城墙的空当变成纵深。
	_grove(holder, [
		["SM_zhuzi008_2", Vector3(25.0, 0.0, -23.5), 15.0, 1.0],
		["SM_zhuzi008_2", Vector3(29.5, 0.0, -24.5), -20.0, 0.95],
		["SM_zhuzi010_2", Vector3(33.5, 0.0, -24.0), 40.0, 0.9],
		["SM_1songbaiB01_LODs", Vector3(36.8, 0.0, -24.5), 0.0, 0.8],
		["SM_zhuzi006_2", Vector3(24.0, 0.0, -27.0), -10.0, 1.0],
		["SM_zhuzi006_2", Vector3(31.0, 0.0, -27.5), 25.0, 0.95],
	])
	# 院边竹栅栏：沿 z=-20.6 一道，正对两栋之间留 1.4 米门口。
	for x in [24.2, 26.2, 28.2, 31.6, 33.6, 35.6]:
		PortLayout.prop(holder, "SM_hpsz_weilan111zuo", Vector3(x, 0.0, -20.6), 0.0, 1.0, PortLayout.COLLIDE_BOX)
	# 门前陈设：石凳、水缸、木牌、石灯，撑起"有人住"的痕迹。
	PortLayout.prop(holder, "SM_mjsz_shidengzi001", Vector3(25.0, 0.0, -12.3), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_mjsz_shidengzi001", Vector3(34.5, 0.0, -12.3), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_gsc_gu001", Vector3(31.8, 0.0, -12.4), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ZhuPai002", Vector3(28.0, 0.0, -12.5), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(24.0, 0.0, -12.2), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	# fangzi003 本体是一座过街门楼：门洞正中挂一片布帘，半掩的过堂比空门洞更有生活气。
	# ※ 晾衣绳方案废弃——绳横穿两侧楼体、第二片帘子嵌进隔壁屋顶（实拍穿帮），别再挂横绳。
	PortLayout.prop(holder, "SM_Item_lianzi001", Vector3(26.5, 1.65, -15.0), 0.0, 1.0, PortLayout.COLLIDE_OFF)
	# 招幌立在坊东端收口。
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(37.8, 0.0, -13.0), 8.0, 0.9, PortLayout.COLLIDE_PRESET)
	_lamp(holder, Vector3(24.0, 0.0, -12.2), 3.2, 6.0)


## ---------------------------------------------------------------- 西侧货栈院
## 任务所副楼以西的作业院：大工棚压中线，竹棚、箱堆、渔网、酒坛靠墙，
## 篝火给黄昏的院子一点火光。整片收到 x≤-28，把"港"的货运气味补在西墙根。
static func west_yard(holder: Node3D) -> void:
	# 大工棚（货运码头同款，略缩）：院子里的主屋。
	PortLayout.prop(holder, "SM_jzc_mapeng001", Vector3(-33.0, 0.0, -2.0), 0.0, 0.85, PortLayout.COLLIDE_PRESET)
	# 候货竹棚：靠东南角，与任务所副楼之间留 1.6 米。
	PortLayout.prop(holder, "SM_NJ_ZhuPengzi001", Vector3(-29.8, 0.0, 3.8), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 货箱堆两组：棚后成组堆放。
	for entry in [
			[Vector3(-36.2, 0.0, -6.4), 14.0, 1.3],
			[Vector3(-35.2, 0.0, -7.3), -10.0, 1.15],
			[Vector3(-36.9, 0.0, -7.7), 32.0, 1.2]]:
		PortLayout.prop(holder, "SM_Box001Close", entry[0], float(entry[1]), float(entry[2]), PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Box001Open", Vector3(-35.4, 0.0, -5.9), -18.0, 1.2, PortLayout.COLLIDE_PRESET)
	for entry in [
			[Vector3(-31.2, 0.0, 1.8), 22.0, 1.25],
			[Vector3(-30.2, 0.0, 0.9), -12.0, 1.1]]:
		PortLayout.prop(holder, "SM_Box001Close", entry[0], float(entry[1]), float(entry[2]), PortLayout.COLLIDE_PRESET)
	# 石料堆与晾开的渔网：贴西墙根。
	PortLayout.prop(holder, "SM_NJ_Shitoudui001", Vector3(-31.0, 0.0, -6.8), 18.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_jiangnan_yuwang001", Vector3(-37.0, 0.0, 1.5), 90.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 酒坛一排靠墙立着（模型本来就是 8.3 米的一排坛子）。
	PortLayout.prop(holder, "SM_Item_jiutanzi04", Vector3(-38.6, 0.0, -3.0), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 篝火：院子东南角，配一盏橙光。
	PortLayout.prop(holder, "SM_Item_gouhuo001", Vector3(-28.8, 0.0, -7.2), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	var fire := OmniLight3D.new()
	fire.name = "YardFireGlow"
	fire.position = Vector3(-28.8, 0.9, -7.2)
	fire.light_color = Color("ff9040")
	fire.light_energy = 2.6
	fire.omni_range = 6.0
	fire.omni_attenuation = 1.5
	fire.light_size = 0.25
	fire.light_volumetric_fog_energy = 0.4
	holder.add_child(fire)
	# 院南缘一道矮栅栏收边（离岸线通道 6 米，不挡去码头的路）。
	for x in [-36.0, -34.0, -32.0]:
		PortLayout.prop(holder, "SM_hpsz_weilan111zuo", Vector3(x, 0.0, 6.0), 0.0, 1.0, PortLayout.COLLIDE_BOX)
	# 西墙根一棵真 3D 大树（必须缩小）：给西片区一个高处的绿色锚点。
	PortLayout.prop(holder, "SM_Item_yjdashu003", Vector3(-39.0, 0.0, -11.5), 24.0, 0.4, PortLayout.COLLIDE_PRESET)
	_lamp(holder, Vector3(-34.0, 0.0, -4.6), 3.0, 6.0)


## ---------------------------------------------------------------- 岸线绿化
## 水岸 z≈11 的几段：灌木与草丛压住驳岸的生硬，避开两座码头的贴岸开口与内港喉口，
## 也避开 probe 落点（x=-20 / -8 / 16.5）的同列。
static func shore_green(holder: Node3D) -> void:
	# 西段（QuayLine 系船石以西）：灌木 + 草。
	_grove(holder, [
		["SM_HD_Guanmu007", Vector3(-32.0, 0.0, 11.0), 0.0, 0.9],
		["SM_HD_Guanmu007", Vector3(-27.5, 0.0, 11.2), 40.0, 0.85],
		["SM_aicao001", Vector3(-30.5, 0.0, 11.3), 0.0, 1.0],
		["SM_aicao001", Vector3(-28.8, 0.0, 10.9), 90.0, 0.9],
		["SM_changzacao001", Vector3(-33.2, 0.0, 11.3), 0.0, 1.0],
		["SM_changzacao001", Vector3(-29.6, 0.0, 11.1), 70.0, 0.9],
	])
	# 东段（货运码头以东）：同款一组。
	_grove(holder, [
		["SM_HD_Guanmu001", Vector3(27.0, 0.0, 11.0), 30.0, 0.85],
		["SM_HD_Guanmu009", Vector3(34.5, 0.0, 11.2), 0.0, 0.9],
		["SM_HD_Guanmu001", Vector3(38.5, 0.0, 11.0), -20.0, 0.8],
		["SM_aicao001", Vector3(30.0, 0.0, 10.9), 0.0, 0.95],
		["SM_changzacao001", Vector3(26.0, 0.0, 11.2), 0.0, 1.0],
		["SM_changzacao001", Vector3(36.5, 0.0, 11.3), 110.0, 0.9],
	])
	# 内港港池里的水车：半浸在水中（水面 y=-0.72），离踏步与泊船都留足距离。
	PortLayout.prop(holder, "SM_ltem_Shuiche001", Vector3(8.3, -0.45, 16.5), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 内港两侧的框景：松柏与灌木比竹子耐看（竹子贴图偏暗紫，近看像枯竹，只留在房后做剪影）。
	_grove(holder, [
		["SM_1songbaiA01_LODs", Vector3(6.2, 0.0, 10.6), 30.0, 0.7],
		["SM_HD_Guanmu009", Vector3(15.2, 0.0, 10.8), -25.0, 0.9],
		["SM_changzacao001", Vector3(5.0, 0.0, 11.1), 0.0, 0.9],
		["SM_changzacao001", Vector3(16.3, 0.0, 11.0), 90.0, 0.9],
	])


## ---------------------------------------------------------------- 北门广场
## 传送门两侧：石灯一对、招幌一面、路缘石墩；贴城墙的北面用一排竹柏当背景林，
## 把商店区背后与城墙之间那道空缝填成"城根的树影"（北门通道 x∈[-4.4,4.4] 不放东西）。
static func gate_plaza(holder: Node3D) -> void:
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(-5.0, 0.0, -20.5), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_NJ_ShiDeng_001", Vector3(5.0, 0.0, -20.5), 0.0, 0.95, PortLayout.COLLIDE_PRESET)
	_lamp(holder, Vector3(-5.0, 0.0, -20.5), 3.4, 6.5)
	_lamp(holder, Vector3(5.0, 0.0, -20.5), 3.4, 6.5)
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(7.2, 0.0, -22.0), -6.0, 0.9, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Wuxianjiao_shidun001", Vector3(-3.9, 0.0, -23.4), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Wuxianjiao_shidun001", Vector3(3.9, 0.0, -23.4), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 城根背景林：北墙一排（x≤-8），西墙一列。
	_grove(holder, [
		["SM_zhuzi008_2", Vector3(-32.0, 0.0, -29.6), 10.0, 1.0],
		["SM_1yuanbai01_LODs", Vector3(-28.0, 0.0, -29.7), 0.0, 0.85],
		["SM_zhuzi008_2", Vector3(-24.0, 0.0, -29.8), -15.0, 0.95],
		["SM_zhuzi006_2", Vector3(-19.5, 0.0, -29.7), 20.0, 1.0],
		["SM_1yuanbai01_LODs", Vector3(-12.0, 0.0, -29.8), 0.0, 0.8],
		["SM_zhuzi008_2", Vector3(-8.0, 0.0, -29.9), -8.0, 0.9],
		["SM_zhuzi006_2", Vector3(-40.0, 0.0, -25.0), 80.0, 1.0],
		["SM_zhuzi006_2", Vector3(-40.2, 0.0, -21.0), 100.0, 0.95],
		["SM_1yuanbai02_LODs", Vector3(-40.0, 0.0, -18.0), 0.0, 0.8],
	])


## ---------------------------------------------------------------- 主街南段与试炼场
## 主街南段（z∈[3,11]）两侧的路缘灌木与一棵桃树：树冠内缘一律留在 |x|≥3，
## 桃树整树收到 |x|≥4.5。试炼传送门东侧立旗与石墩，标出"演武场"的入口。
static func street_green(holder: Node3D) -> void:
	_grove(holder, [
		["SM_HD_Guanmu001", Vector3(4.8, 0.0, 4.6), 0.0, 0.85],
		["SM_HD_Guanmu009", Vector3(5.2, 0.0, 8.6), 60.0, 0.9],
		["SM_taoshu001", Vector3(-6.8, 0.0, 7.5), 0.0, 0.42],
		["SM_HD_Guanmu007", Vector3(-4.4, 0.0, 6.2), -30.0, 0.75],
		["SM_changzacao001", Vector3(3.9, 0.0, 3.2), 0.0, 1.0],
		["SM_changzacao001", Vector3(-3.9, 0.0, 3.2), 90.0, 1.0],
		["SM_changzacao001", Vector3(3.9, 0.0, 10.2), 40.0, 0.9],
		["SM_changzacao001", Vector3(-3.9, 0.0, 10.2), 0.0, 0.95],
	])
	# 演武场入口：旗与一对石墩（离传送门交互圈 3 米以上，走进不会误传）。
	PortLayout.prop(holder, "SM_Wuxianjiao_qizi003", Vector3(21.0, 0.0, 3.2), 10.0, 0.9, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Wuxianjiao_shidun001", Vector3(19.6, 0.0, 2.6), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_Wuxianjiao_shidun001", Vector3(22.4, 0.0, 2.6), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	# 演武场东南角补一组木桩阵与歇脚处（单根竹桩竖四根当练功桩），呼应试炼入口。
	for at in [Vector3(24.0, 0.0, 5.0), Vector3(25.6, 0.0, 5.0), Vector3(24.0, 0.0, 6.6), Vector3(25.6, 0.0, 6.6)]:
		PortLayout.prop(holder, "SM_NJ_Zhuziweilan001", at, 0.0, 1.3, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_mjsz_shidengzi001", Vector3(29.0, 0.0, 6.0), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	PortLayout.prop(holder, "SM_gsc_gu001", Vector3(31.0, 0.0, 6.5), 0.0, 1.0, PortLayout.COLLIDE_PRESET)
	_grove(holder, [
		["SM_changzacao001", Vector3(23.0, 0.0, 7.4), 0.0, 1.0],
		["SM_aicao001", Vector3(27.2, 0.0, 7.8), 0.0, 0.95],
		["SM_HD_Guanmu007", Vector3(33.0, 0.0, 7.0), 25.0, 0.8],
	])


## 一小片植物：成组、错位、转角，绝不排成等距阵列——排阵就是"杂乱感"的来源。
static func _grove(holder: Node3D, entries: Array) -> void:
	for entry in entries:
		PortLayout.prop(holder, entry[0], entry[1], float(entry[2]), float(entry[3]), PortLayout.COLLIDE_PRESET)


## 门灯：石灯上方一盏暖色点光（与商店区、码头岸灯同一套做法）。
static func _lamp(parent: Node3D, at: Vector3, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.name = "DressingLantern"
	light.position = at + Vector3(0, 1.62, 0)
	light.light_color = Color("ffc17b")
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.light_size = 0.2
	light.light_volumetric_fog_energy = 0.4
	parent.add_child(light)
