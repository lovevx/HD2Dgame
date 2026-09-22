extends RefCounted
## 科尔波山远景层：在北墙外（z < -31.5）用现有悬崖/山石/松柏预设搭一座连绵的
## 「科尔波山」——既是整个港口的北向后景，也是北门传送环（城门传送 · 科尔波山，
## DeparturePortal @ (0,0,-21)，环 @ (0,0.06,-28)）指向的下一张地图的视觉示意。
##
## 素材：只用已入库共享预设。实测要点（tools/probe_mountain_presets.gd）：
##   · SM_Jiangnan_xuanya001~007 是悬崖/山崖模型，min.y=0 落地即站：
##     001 24.2×12.7×28.2（宽扁）  002 20.5×15.6×17.8  003 21.0×20.7×17.1（高）
##     004 22.4×19.7×17.1          005 26.4×20.7×16.0（最高）  007 28.4×16.0×26.1（宽大）
##     模型原点在俯视几何中心，深度半值要计入：脚线 z = 中心 z + (深度×scale)/2。
##   · SM_DM_Zudangshitou001 大山石 15.3×15.4×13.1，×0.4 左右当城外孤岩。
##   · SM_YX_Shitou001 散石 2.7×3.6×2.8，山脚点缀。
##   · 松柏/圆柏全是 facing=2 薄片树（运行时转向镜头），跟 dressing 同款用法。
##
## 布置约束（别踩）：
##   · 北墙沿 z=-31.5（墙顶约 5.6 m），山脚线统一收到 z=-33，离墙外沿 1~2 m 不压墙。
##   · 北门通道 x∈[-4.4,4.4]：通道正后方摆最矮的 xuanya001×0.8（高 10.1）当垭口，
##     两侧高崖（20m+）收在天际线，穿门进山的"山口"读感就出来了。
##   · 全部 COLLIDE_OFF：山在玩家不可达的墙外，纯背景装饰；也免得巨大包围盒
##     参与物理与遮挡候选的判定。遮挡淡出的视线是「相机→玩家」线段，永远
##     到不了玩家以北的墙体之外，山体不会误触发淡出。
##   · 服务点走廊、probe 落点全在城内，与山无关；不摆任何东西进 z > -33。

const PortLayout := preload("res://tools/harbor_port_layout.gd")

const NODE_NAME := "HarborMountain"

## 前排山脊脚线（各悬崖南沿统一收到这条线上）。
const RIDGE_FOOT_Z := -33.0


static func make_node() -> Node3D:
	var holder := Node3D.new()
	holder.name = NODE_NAME
	ridge(holder)
	peaks(holder)
	gate_view(holder)
	foothill(holder)
	treeline(holder)
	return holder


## ---------------------------------------------------------------- 前排山脊
## 七座悬崖沿 z=-33 脚线连绵咬合（相邻重叠 20~30%，剪影互借看不出接缝）。
## 从西到东：中 → 高 → 高 → 矮（垭口，正对北门）→ 高 → 中 → 中。
static func ridge(holder: Node3D) -> void:
	# 每条：[标题, 缩放, 中心 x]。中心 z 由脚线反推：z = RIDGE_FOOT_Z - 半深×缩放。
	var entries := [
		["SM_Jiangnan_xuanya002", 0.85, -44.0],
		["SM_Jiangnan_xuanya004", 1.05, -30.0],
		["SM_Jiangnan_xuanya003", 1.10, -17.0],
		["SM_Jiangnan_xuanya001", 0.80, 4.0],    # 垭口：北门正后方，高 10.1 m
		["SM_Jiangnan_xuanya003", 1.05, 18.0],
		["SM_Jiangnan_xuanya004", 0.95, 31.0],
		["SM_Jiangnan_xuanya002", 0.90, 44.0],
	]
	var depths := {
		"SM_Jiangnan_xuanya001": 28.24, "SM_Jiangnan_xuanya002": 17.84,
		"SM_Jiangnan_xuanya003": 17.07, "SM_Jiangnan_xuanya004": 17.11,
		"SM_Jiangnan_xuanya005": 15.96, "SM_Jiangnan_xuanya007": 26.05,
	}
	for entry in entries:
		var title: String = entry[0]
		var scale: float = entry[1]
		var half: float = depths[title] * 0.5 * scale
		PortLayout.prop(holder, title,
			Vector3(float(entry[2]), 0.0, RIDGE_FOOT_Z - half),
			0.0, scale, PortLayout.COLLIDE_OFF)


## ---------------------------------------------------------------- 后排群峰
## 退到 z≈-55 的放大悬崖，从前排头顶露出层叠的远山。主峰偏西，中峰压在
## 前排同位悬崖的正北——上层露头、下层挡脚，天然的双层山。
static func peaks(holder: Node3D) -> void:
	var cliffs := [
		["SM_Jiangnan_xuanya005", 1.35, -22.0, -55.0],   # 主峰 28 m（西）
		["SM_Jiangnan_xuanya003", 1.20, 16.0, -55.2],    # 中峰 24.8 m（东）
		["SM_Jiangnan_xuanya007", 1.10, 39.0, -57.3],    # 东远峰
		["SM_Jiangnan_xuanya007", 1.05, -46.0, -56.7],   # 西北远峰
	]
	for entry in cliffs:
		PortLayout.prop(holder, entry[0],
			Vector3(float(entry[2]), 0.0, float(entry[3])),
			0.0, float(entry[1]), PortLayout.COLLIDE_OFF)


## ---------------------------------------------------------------- 垭口示意
## 北门门洞正后方 2.8 m 立一棵放大的圆柏：港口机位是 18° 长焦 + 16° 俯角，
## 画面顶缘压在「俯视 7°」的视线上，墙外的山体整体出画——唯一能带进默认画面的
## 北墙外景物，就是透过门洞取景框看到的那一条（门洞上沿视线到 z=-34.5 处
## 只剩 4.5 m 以下）。树干与低枝正好落进这条带：开着的城门里立着树，
## 「穿门进山」的示意直接长在画面里，与传送环的指认互相咬合。
static func gate_view(holder: Node3D) -> void:
	PortLayout.prop(holder, "SM_1yuanbai01_LODs", Vector3(0.0, 0.0, -34.3), 0.0, 1.5, PortLayout.COLLIDE_OFF)
	# 山口冷光：城里的灯全是暖橙，唯有北门门洞里透出一线青白——
	# 夜景里给「门后是另一片山」打上色彩语言，顺带把门洞里的树干照亮。
	# 挂在树冠高处，范围收小，只染门洞一带，不往城里溢光。
	var light := OmniLight3D.new()
	light.name = "GateMountainGlow"
	light.position = Vector3(0.0, 4.6, -34.8)
	light.light_color = Color("9fd8e8")
	light.light_energy = 2.8
	light.omni_range = 7.0
	light.omni_attenuation = 1.6
	light.light_size = 0.3
	light.light_volumetric_fog_energy = 0.5
	light.shadow_enabled = true
	holder.add_child(light)


## ---------------------------------------------------------------- 前沿孤岩
## 贴着山脚线再撒一层岩石，把"墙外就是山根"的贴地感压实。全部在 z<-34。
static func foothill(holder: Node3D) -> void:
	var rocks := [
		["SM_DM_Zudangshitou001", 0.45, -37.0, -35.9],
		["SM_DM_Zudangshitou001", 0.38, 33.0, -35.5],
		["SM_YX_Shitou001", 1.60, -24.0, -35.2],
		["SM_YX_Shitou001", 1.40, 26.0, -35.2],
		["SM_YX_Shitou001", 1.20, 12.0, -34.8],
		["SM_YX_Shitou001", 1.00, -13.0, -35.0],
	]
	for entry in rocks:
		PortLayout.prop(holder, entry[0],
			Vector3(float(entry[2]), 0.0, float(entry[3])),
			0.0, float(entry[1]), PortLayout.COLLIDE_OFF)


## ---------------------------------------------------------------- 山脚林带
## 薄片松柏贴着崖脚前后错落（绝不排成等距阵列），垭口两侧的树让出
## 北门通道 x∈[-4.4,4.4]（含树冠外扩后仍要留在 |x|≥4.9）。
static func treeline(holder: Node3D) -> void:
	var trees := [
		["SM_1songbaiB01_LODs", 1.00, -38.0, -34.5, 15.0],
		["SM_1songbaiA01_LODs", 0.90, -35.0, -36.0, -30.0],
		["SM_1yuanbai01_LODs", 0.85, -31.0, -34.8, 0.0],
		["SM_1yuanbai01_LODs", 0.75, -20.0, -35.0, 20.0],
		["SM_1songbaiB01_LODs", 0.90, -8.5, -34.2, -12.0],
		["SM_1songbaiA01_LODs", 1.00, 18.0, -34.6, 25.0],
		["SM_1songbaiB01_LODs", 0.85, 22.0, -36.2, -40.0],
		["SM_1yuanbai02_LODs", 0.90, 28.0, -34.9, 10.0],
		["SM_1yuanbai02_LODs", 0.80, 10.0, -35.6, -25.0],
		["SM_1songbaiA01_LODs", 0.80, 37.0, -35.4, 0.0],
	]
	for entry in trees:
		PortLayout.prop(holder, entry[0],
			Vector3(float(entry[2]), 0.0, float(entry[3])),
			float(entry[4]), float(entry[1]), PortLayout.COLLIDE_OFF)
