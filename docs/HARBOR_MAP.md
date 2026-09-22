# 灰潮港口主城

## 正式核心循环接入（2026-09-17）

从F5主菜单运行正式流程，猎虎结算后返回本场景。原五个功能点现已接真实逻辑：潮汐杂货购买药剂；铸潮工坊消费属性点/乐园币/结晶强化；委托所读取任务及阶段报告；演武场进入原木桩并隔离练习资源；北侧入口开启下一次试炼。C面板采用原人物/装备/64格背包布局并显示真实物品。地图文件和美术布局未改写，接入在运行时控制器完成。

以下为场景建造与独立F6调试模式的历史记录；其中“服务待接入”不适用于当前正式流程。

入口：`scenes/world/harbor.tscn`。选关菜单中选择“灰潮港口（主城）”，或在 Godot 中打开场景按 F6。

使用现有 `assets/hd2d_presets` 素材搭建：城门、民居、客栈、摊位、药柜、货架、竹棚、石桌、矿石、水车、屏风、鼓、双码头与泊船。未生成或下载新美术。

| 功能区 | 交互位置 (x, z) | 内容 |
| --- | --- | --- |
| 北侧传送广场 | (0, -21) | 走入门传送至阶段试炼（按存档阶段装载 campaign，新档从 1.2 废品终点站开始） |
| 西侧潮汐杂货 | (-10, -9) | 商店陈设、招牌、服务说明面板 |
| 东侧铸潮工坊 | (10, -9) | 强化台、矿石货架、暖色灯光、服务说明面板 |
| 西南港务委托所 | (-10, 0.5) | 委托屏风、办公桌棚、任务说明面板 |
| 东南演武场 | (17, 1) | 鼓、石柱、V 传送至战斗试炼 |

出生点在中央主街 (0, -12)，通往各区的通道保持开放。南侧双 L 形码头保留可走甲板与水域屏障。服务点通过常显招牌和不同颜色的地面环辨识；开发用分区标记仍默认隐藏。

操作：WASD 移动，靠近功能点按 V；服务面板打开时停止角色移动，点击“返回港口”或按 Esc 关闭。其他场景通过 Esc 菜单的“返回灰潮港口”返回主城。

本轮交付为主城场景与交互入口。商店交易、强化消耗/数值、任务接取/进度/奖励仍未接入，不扣除资源，也不写入存档。

生成入口：`tools/build_harbor.gd`；功能区装配：`tools/harbor_zones.gd`。重跑生成脚本会覆盖场景。改造前场景备份：`tools/backups/harbor_before_hub.tscn.bak`。

验证：Godot 4.7.2 / D3D12 实际渲染。`tools/capture_harbor.gd` 验证码头、水岸、强化台、主街和城门边界；`tools/check_harbor_hub.gd` 验证五区可达、交互提示、V 打开面板、Esc 关闭与移动恢复、两处实际传送和返回主城。结果分别为 `HARBOR_CAPTURE: PASS` 与 `HUB_RESULT: PASS`。退出时存在 RID / ObjectDB 资源释放警告，尚未解决；功能检查未出现脚本错误。

预览：`docs/harbor_preview.png`、`docs/harbor_pier_preview.png`、`docs/harbor_quest.png`、`docs/harbor_forge.png`、`docs/harbor_gate.png`、`docs/harbor_quest_panel.png`。

## 场景优化（2026-09-17）

- 降低石板纹理反差，散落碎石由 270 处缩减到边缘 60 处；主街保持整洁。
- 增加主街与两条横向服务步道、浅色嵌边，步道使用世界坐标纹理保持砖块比例。
- 四组矮树池、桃树与座椅组织街道空间，商店补充棚顶；不改变功能点坐标。
- 交互环改为细线，远景景深起点延后到 48 米、模糊强度降低，功能区更清楚。
- 水面闪光合并为一个 MultiMesh，位移动画由 shader 完成，移除逐帧分组查询和逐节点移动。序列化场景节点从 463 减少至 221；未据此声称实测帧率提升。
- 街市到码头的镜头前视偏移连续过渡。

优化前备份为 `tools/backups/harbor_before_polish.tscn.bak`，对比图为 `docs/harbor_before_polish.png`。

## 植被清空（2026-09-19）

- 移除街道桃树 10 棵、景观大树 3 棵、松柏 2 棵、四组石砌树池（含树土与碰撞体），以及岸线草丛 / 矮草 / 绿植 / 灌木共 615 处散布（`ShoreGrass` 节点）。
- 保留非植被陈设：山石（`SM_Jiangnan_xuanya*`，仍作活动边界外的天然围墙）、街边石灯笼、渔网、系船柱、货箱、竹棚、码头与泊船、地面碎石（`PavingDetail`）。原树池旁的四盏石灯笼（x=±5.8，z=-14.3 / -2.8）保留为独立街边陈设。
- 生成脚本 `tools/build_harbor.gd` 同步移除植被生成代码：`build_street()` 的树池循环与 `build_scenery()` 的街道树 / 大树 / 松柏 / 岸线草丛。重跑生成脚本不会再长出植被；将来需要重新植绿时在 `build_scenery()` 补回，并同步本节。
- 植被素材定义（`SM_taoshu001`、`SM_1dashu001_LODs`、`SM_1songbaiA01/A02_LODs`、`SM_changzacao001`、`SM_aicao001`、`SM_NJ_Yvlinzhiwu001`、`SM_HD_Guanmu005/007`）已从场景引用与树池材质网格中一并清理，散列场景节点 293 → 261（后代 264）。
- 校验：Godot 4.7.2 无头加载 `scenes/world/harbor.tscn` 通过，`HARBOR_CHECK: PASS`（植被命中 0）。本次只做移除，未调整机位、光影与功能区坐标。

## 围墙（2026-09-19）

沿陆地基座外缘（x=±42、z=-32~12）砌一整圈砖石城墙，取代原先压在场边充当"天然围墙"的山石，给场地一个统一的边界收口。

- 墙体改为四层几何砌筑（石砌勒脚 / 砖砌墙身 / 挑出瓦檐 / 收进瓦脊，总高 5.76 米），南侧临水为同构矮墙。早期做法是把素材墙段连续排列，每段自带一圈四面瓦檐，连排起来像一排牌位，已废弃。
- 墙体内表面与地基边缘齐平（墙线 x=±41.5、z=-31.5 / 12），转角由角墩收口。北墙在城门处断开（开口半宽 4.4 米，城门本身宽 8.19 米）；南墙在两座码头贴岸段断开，玩家仍可从石板街直接走上码头（开口位置与 `PIER_CENTERS`/`PIER_SPAN` 对齐）。
- 墙体不生成碰撞：边界碰撞仍由 `build_actors()` 的隐形屏障（x=±32.3、z=-28.3 与水岸三段）负责，城墙只把边界做成看得见的东西。
- 移除原边界山石 6 处（`SM_Jiangnan_xuanya001/002/003/004/005/007`，体量 20~28 米宽、12~20 米高），它们与墙线穿模。
- 实现：布局集中在 `tools/harbor_walls.gd`，用 `HD2DFoliage` + MultiMesh 合批，整圈只增加 1 个场景节点（`HarborWall`）。整体重建走 `tools/build_harbor.gd` 的 `build_walls()`；已生成的场景用增量脚本 `tools/apply_harbor_walls.gd`（改布局后重跑，脚本会先删旧墙再重建，幂等）。
- 验收：`tools/capture_harbor.gd` 的 15 项通行检查全部 `PASS`（`HARBOR_CAPTURE: PASS`）；场景接口（Player / Camera3D / WorldEnvironment / 5 个服务点 / 港口调色层）与机位、光影均未改动。预览：`docs/harbor_wall_top.png`、`docs/harbor_wall_north.png`、`docs/harbor_wall_shore_top.png`、`docs/harbor_wall_corner.png`。

## HD-2D 光影调整

参考《八方旅人 II》的像素与 3DCG 结合方向：https://www.playstation.com/en-us/games/octopath-traveler-ii/ 。沿用已有建筑、植被与角色素材，调整港口独立视觉，不修改共享素材原文件。

- 镜头：24°俯角、正面朝向、33 米距离 / 26° FOV，压缩透视；近远景景深保留中景角色清晰。
- 黄昏侧向主光、冷色天空填充、角色补光、服务区与岸灯的真实点光源；四处关键灯开启阴影。
- SSAO 接触阴影、SSIL 间接光、低密度体积雾、光晕、冷暖调色与轻暗角。HUD 在后期层之上保持清晰。
- 世界坐标像素石板含色差、磨损与湿润反射；水面具有像素分段波纹与动态法线，闪光直接由海面 shader 生成。
- 64 个缓慢漂浮的 GPU 尘光粒子。
- 修正陆地基座南界至 z=12，码头下面现在是真正水面，甲板碰撞不变。

光影装配：`tools/harbor_lighting.gd`。调色、石板、水面材质在 `shaders/harbor_grade.gdshader`、`shaders/harbor_paving.gdshader`、`shaders/harbor_water.gdshader`。效果仅用于港口。Forward+ 为验证渲染路径；新增阴影、SSIL 和体积雾增加 GPU 开销，未作设备间帧率对比。

改造前备份：`tools/backups/harbor_before_hd2d.tscn.bak`。实机通行与服务/传送回归通过；退出时原有 RID / ObjectDB 释放警告仍存在。当前是现有素材上的 HD-2D 风格强化，不等同于完成商业作品级的统一美术制作。

运行检查中定位到独立 WaterGlints 实例绘制会出现前景大块遮挡；已移除该批实例，将闪光合入海面材质，重新运行确认遮挡消失。

## 南岸客货码头（2026-09-19）

把南岸两座 L 形码头做成一处成形的**客货两用港**：补完木甲板外观与码头陈设，两座之间的空档整成一处内港泊位，并沿南岸补齐系泊石作。本次只做外观与通行，不接 V 交互面板、不划分功能区。

- **补完两座码头**。此前南岸只剩 `Pier0Deck` / `Pier22Deck` 等隐形碰撞盒，木甲板外观（`tools/harbor_pier.gd` 的砌木甲板）从未真正应用到场景，从街上看是"两块看不见的板浮在水上"。本次用共享预设 `SM_JN_matou`（L 形木码头）补回外观：主段贴岸 z∈[12,18.5]、西侧支段伸海 z∈[18.5,25]，与 `build_harbor.gd` 的 `PIER_SPAN` / `PIER_LEG` 对齐。另沿 L 形轮廓砌石砌驳岸与台面收边、在支段端头与主段东南角补墩柱、临水三面布系船柱，避免木面像一块浮板。
- **实测纠正两处**：`SM_JN_matou` 的甲板顶面在模型原点上方 **4.31 米**（下沉 4.31 后与石板街齐平）；**模型原点是俯视包围盒中心而非角点**（包围盒 x∈[-8.23,8.06]、z∈[-6.5,6.5]，主段 z∈[-6.5,0]、西侧支段 z∈[0,6.5]）。早期脚本 `harbor_dock_layout.gd` 按"原点＝角点"摆放，整体差 8.2 米，据此废弃。
- **客运码头（`SouthPort/Pier0`，x=0）**：小尺寸候船竹棚 `SM_NJ_ZhuPengzi001` 压在主段西端，东侧留出上落客通道；候船长凳、行李货箱、码头木牌、渔网；渡船 `SM_JN_xiaochuan005`（长条平底船）靠在内港喉口东侧，与 Pier0 东沿平行。
- **货运码头（`SouthPort/Pier22`，x=22）**：装卸棚 `SM_jzc_mapeng001` 在西端，两座货架 `SM_Item_NJhuojia003` 贴棚东侧，东半幅成组堆放货箱（7 只闭箱 + 2 只开箱），另有散货垫石、木墩、码头木牌；货船 `SM_JN_yuchuan003` 靠东外档、大船 `SM_JN_yuchuan004` 锚在内港外海。中线留出通行带。
- **内港（`SouthPort/InnerBasin`）**：空档水域 x∈[8.145,13.855] 沿喉口砌三级石踏步下水，两岸布系船石墩，立木牌与两盏码头灯把这片水域指认为泊位，港池里横泊一条渔船。支段以南展开为港池 x∈[-1.855,13.855]、z∈[18.5,25]。
- **南岸沿线（`SouthPort/QuayLine`）**：两座码头开口以外的岸段补系船石、渔网与散箱，把整条岸线读成一处成形的港。开口位置刻意留空，不挡上桥通道。
- **打开被砌死的喉口**。`HarborWall` 里还留着上一版南岸矮墙的 4 段（勒脚/墙身/瓦檐/瓦脊，x=11、z=11.5），正好封在内港喉口上。`apply_harbor_south_port.gd` 按坐标精确拆除这 4 段；其余南岸矮墙、四边城墙、城门均未改动。
- **碰撞未动**：不新增可行走面，也不改水域屏障。喉口只是把**看得见**的墙拿掉，`build_actors()` 的隐形拦水仍在原位 —— `check_harbor_port.gd` 的"水岸拦水下海（两码头之间）"仍为 PASS。**即：从主街看向内港是通的，但走不进水里。** 已确认这是想要的效果（不需要走进水里），保持现状。

### 两处碰撞缺陷（2026-09-19 修复）

**① 甲板模型多叠了一层碰撞 → 上得去、下不来。**
`SM_JN_matou` 这个共享预设自带 `static_collision = true`，所以摆它时会**自动生成**一个 `SM_JN_matou_col` 碰撞体，而甲板的可行走碰撞**已经由 `build_harbor.gd` 的 `Pier0Deck`/`Pier22Deck` 提供**。两层叠在一起，角色在甲板与砖路的接缝处被自己脚下的甲板卡住 —— 表现是**能走上木板，但从木板走回砖路被挡住**（实测首个阻挡点在 z≈12.7）。
`harbor_port_layout.gd` 的 `prop()` 原来用 `box=false` 表示"不加碰撞"，但那只等于"不覆盖预设设置"，预设的碰撞照旧生成。现在改成显式的三档 `COLLIDE_OFF / COLLIDE_PRESET / COLLIDE_BOX`，甲板模型用 `COLLIDE_OFF` 强制关掉。修好后 `SM_JN_matou_col` 在场景里彻底消失（62 个自动碰撞节点里已无此项）。

**② 货运码头的装饰把支段出口横断 → 可能进了出不来。**
L 形码头的支段只占主段西半幅（`PIER_LEG.x=6.29`，x∈[west, west+6.29]），接缝在 z=mid=18.5。装卸棚 `SM_jzc_mapeng001` 碰撞体实测约 4.9 × 5.1（0.78 缩放），原来放在 z=SHORE_Z+3.5 时伸到 z≈18.0，再叠上石灯笼与木墩，正好把整条支段出口覆盖掉（诊断显示 z=18.0 处**空通道 0/9**）。
已把货运装饰整体北移（装卸棚 −0.9、石灯笼 −1.2、木墩 −1.8；客运的长凳与石灯笼同样北移），给接缝留出净空。修好后 z=18.1 与 z=18.4 两处扫描，**两座码头支段整宽 13 条通道全部净空**。

> 布置约束（写进 `_deck_cargo()` 的注释）：**主段西半幅 z 超过 ~17 的地方不能摆东西**，否则会堵死支段出口。

### 验收与过程记录

- `tools/check_harbor_port.gd`（headless，只做碰撞检查、不覆盖预览图）：原 `capture_harbor.gd` 的 **14 项通行断言全部 PASS**，另加 2 项"从甲板走回砖路"（原脚本只测了"街上→甲板"这个往下的方向，**返回方向从来没测过**，所以①一直没被发现）；`SouthPort` 四分区齐备（Pier0 32 / Pier22 38 / InnerBasin 11 / QuayLine 10 个子节点）；两座码头中线 z=11.5→17.5 纵向通道畅通（z≈18.5 处是 L 形缺口栏杆 `Pier*NotchRail`，越过后下方即水面）。
- 支段↔主段接缝**只作诊断输出、不计入 PASS/FAIL**：接缝处两个甲板碰撞盒在 z=18.5 严丝合缝相贴，角色胶囊底在毫米级上与盒面切线，`test_move` 的结果在多次运行间不稳定（同一位置时挡时通），手工驱动 `move_and_slide` 也给出过自相矛盾的结果。这里给不出可信结论，所以只打印 `intersect_shape` 的碰撞体占位供核对（重叠检测结果稳定）。
- 过程中还发现 `tools/capture_harbor.gd` 之外的一个通用前提：`intersect_shape` 可靠、`test_move` 在亚厘米接缝上不可靠。定位"看不见但挡路"的东西时，先量碰撞体 AABB 缩小范围，再用重叠检测点名。
- 当前模型不能读图，**观感未经视觉确认**。

### 实现与其它

- 实现：布局集中在 `tools/harbor_port_layout.gd`；应用到已生成场景用 `tools/apply_harbor_south_port.gd`（幂等：先删旧 `SouthPort` 再重建；备份已存在时**不再覆盖**，避免第二次运行用改后的场景盖掉真正的"改造前"快照）。改造前备份 `tools/backups/harbor_before_south_port.tscn.bak`。
- **过程中的坑（已修）**：`apply` 脚本第一版写成链式 `PackedScene.new().pack(root)`，没接住新建的 `PackedScene` 引用，`ResourceSaver.save` 保存的仍是 `load()` 进来的旧场景 —— 表现是"打印落盘成功，但一个节点都没进去"。改为用变量接住再保存后正常。同类写法在已废弃的 `apply_harbor_dock.gd` 里也存在，那对脚本已归档为 `tools/backups/apply_harbor_dock.gd.bak` + `harbor_dock_layout.gd.bak`。
- 布置备注：这批共享预设多数自带 `static_collision = true`，摆件是**会挡路的实体**，布局要"中线留通行带、摆件靠边"；要放纯装饰必须显式 `COLLIDE_OFF`。
- 预览：`docs/harbor_south_port_aerial.png`、`docs/harbor_south_port_top.png`、`docs/harbor_south_port_town.png`、`docs/harbor_south_port_sea.png`。

## 前景遮挡淡出（2026-09-19）

镜头与玩家之间有城墙、棚屋、招牌、船这类大体量景物挡住角色时，把那件景物调成半透明，让开后再平滑恢复。角色不再被前景吞掉。

- **实现**：`scripts/world/camera_occlusion_fade.gd`（控制器，`Node3D`）由 `player.gd` 在 `_ready()` 里挂到玩家身上。四张关卡图共用同一套 `player.tscn`，所以**一处接入、全场景生效**，没有改任何 `.tscn`。相机与关卡树都由控制器自己找。
- **检测用「包围盒 vs 视线线段」而不是物理射线**：城墙、城门只砌几何、不生成碰撞（碰撞由 `build_actors()` 的隐形屏障负责），射线会整个漏掉它们 —— 而它们恰恰是最常挡住人的东西。
- **每 1 秒重扫候选**：高度 ≥1.2 m 的 `MeshInstance3D`/`MultiMeshInstance3D`，排除玩家自身与 `occlusion_ignore` 组。对玩家身上三个采样高度（头顶 1.72 / 胸口 1.10 / 小腿 0.45）加胸口两侧 0.35 m 做线段-AABB（slab 法）求交，**穿透厚度 ≥0.15 m** 才算遮挡 —— 不给这个下限，长条景物（船、崖壁）的包围盒被视线从角落擦过去就会到处误淡。
- **淡出怎么落到材质上**（2026-09-19 像素回读实测）：标准材质直接用 `GeometryInstance3D.transparency`；但自定义着色器（`harbor_wall.gdshader` / `preset_normal.gdshader`，城墙与预设模型都是这一类）**`transparency` 完全没有反应**。所以给这两类各做了一份淡出变体着色器（`shaders/occlusion_fade_harbor_wall.gdshader`、`shaders/occlusion_fade_preset.gdshader`），外观逐行相同，只加 `instance uniform float occl_fade` 并 `ALPHA = occl_fade`，逐实例 `set_instance_shader_parameter()` 控制透明度。淡出期间临时换材质，让开后还原 —— 静止时场景与改动前**逐像素一致**（已用像素回读对照）。
- **淡出材质刻意不写深度**：写深度的半透明墙会把身后的玩家整个深度剔除掉，只剩背景透出来，功能直接失效。所以变体着色器是 `blend_mix`，不带 `depth_draw_always`。
- **淡出单元粒度（砌体）**：程序化砌体按「同一次砌筑的叠层」合并，判据是**俯视投影重合度 ≥0.6**（勒脚/墙身/瓦檐/瓦脊脚底一致，必然并入；沿墙相邻的两段只擦一条缝，不会并入）。早期用"包围盒外扩后相交"会把整圈墙连成一片、一挡淡全部，已废弃。
- **同一处的摆件成簇（2026-09-19 补）**：竹棚、渔网、货架这类相邻摆件是**各自独立的 `HD2DProp`**，早先每件各自判定、各自成单元，于是出现"渔网淡了、紧挨着的竹棚没淡"的割裂观感 —— 贴着南岸矮墙走到 x≈-8 时最明显（用户即在此处发现）。现在按「投影相交 + 水平中心距 ≤`cluster_radius` + 高度比 ≥`cluster_height_ratio`」把同一处的几件并成一簇，**判定与淡出都按整簇的合并包围盒**走：视线的列擦到其中任何一件，整堆一起淡，不再卡在单件的边界上。
  用距离和高度比而不是单纯的重合度，是因为客运码头那块 16×13 m 的大平台会把整个 `Pier0` 罩进投影里，只看重合度就会在竹棚命中时把脚下栈桥一起拖淡（改簇时踩过这个坑，已在检查脚本里留断言）。
- **可调参数**（挂在玩家身上那个 `CameraOcclusionFade` 节点上）：`enabled` / `min_height` 1.2 / `fade_amount` 0.62 / `fade_in_speed` 9 / `fade_out_speed` 6 / `sample_heights` / `side_reach` 0.35 / `refresh_interval` 1.0 / `cluster_overlap` 0.6（砌体叠层）/ `cluster_radius` 2.5（摆件成簇）/ `cluster_height_ratio` 0.45 / `hit_skin` 0.06 / `min_cross` 0.15。想让某件景物不参与，把它加进 `occlusion_ignore` 组。
- **验收**：`tools/check_occlusion_fade.gd`（headless，只读状态、不覆盖预览图）—— 5 个落点 + 材质落地 + 恢复 + 砌体单元粒度不退化 + 摆件成簇，`OCCLUSION_FADE_CHECK: PASS`。实测确认会淡出的场景：南岸临水矮墙（4 层一起淡）、客运码头竹棚（连同挨着的渔网成簇）、货运码头装卸棚、码头木牌与货架、货船。
- **南岸沿线的实测触发地图**（2026-09-19，逐米扫描 `z=8/9.5/11/12`）：矮墙 `Shore_*` 覆盖 x≤-8.2 与 x≥24.1，这两段贴着走时墙会淡；客运码头东端的竹棚簇（竹棚+渔网）在 **x≈-8.3 ~ -3.7** 之间进入视线列，走到墙的最东端即能覆盖；再往西（x≤-8.5）竹棚在角色右侧半个身位以上、几何上不挡人，不淡是对的。中段 x∈(-8.2, 24.1) 是码头开口，没有矮墙。
- **触发范围（重要）**：港口是「相机固定偏移跟随玩家」的机位（俯角 16°、位于玩家正南约 43 米，`harbor.gd` 里 lerp 跟随、约 1.7 秒收敛）。因此只有**玩家正南那条窄列里够高**的景物才会挡人；两侧与北侧的高墙（x=±41.5 的城墙、北墙）在几何上永远挡不到玩家，实测也确实不误淡。做这类校验必须先等相机收敛，否则射线整条偏掉、结论不可信。
- **核查发现（与本文档前面的描述不符）**：当前 `harbor.tscn` 里**没有民居/客栈网格** —— `SM_JN_fangzi*`、`sm_gsc_kezhan001` 这些素材只存在于 `tools/backups/harbor_before_hd2d|hub|polish.tscn.bak`。因此 `capture_harbor.gd` / `check_harbor_port.gd` 里"客栈是带院落的屋舍，正面可走入"这条断言现在是**空过**的。是否把民居/客栈补回场景，待定。
- 当前模型不能读图，**观感未经视觉确认**。

## 镜头操控（2026-09-19）

取消「鼠标让出」，镜头改由玩家显式操作：**按住鼠标中键拖动绕角色转视角，滚轮推拉相机与角色的距离**。默认机位（16° 俯角 / 正北 / 48.1 米 / FOV 18°）没有变，变的是"谁能改它、怎么改"。

- **取消鼠标让出**。原来光标离屏幕中心越远，取景中心越往那一侧让出（`camera_mouse_lead.gd`）。现在光标移到哪都不再带动镜头，组件与它的全部调用一起删除。四张图共用同一套机位，改动落在 `harbor.gd` / `colpo_level.gd` / `scripts/main/main.gd` 三处脚本，**没有动任何 `.tscn`**。
- **中键拖动转视角**（`scripts/world/camera_orbit_controls.gd`）：左右拖动改偏航——向右拖 = 相机绕到角色东侧、视线朝东，画面上就是"左北右南"；上下拖动改俯角。**俯角同时决定机位高度**：俯角越大相机越高、水平距离越短。灵敏度 0.22 度/像素，俯角限位 6°~45°，偏航按 -180°~180° 环绕。
- **滚轮推拉距离**：按比例改变相机到焦点的距离（每格 ×1.12 / ÷1.12），限位 12~96 米。
- **景深跟着距离等比缩放**（必须做，否则功能是坏的）：相机到角色就是 `distance`，近景景深原本按 48.1 米档位设成 37.9 米，拉近到 20 米时角色会整个掉进近景模糊区。组件在配置时记下景深四个距离作基准，每次缩放按 `distance / 基准距离` 同步改。
- **拖动时加快跟随**（~~2026-09-19 晚已废弃~~，见下一节：转动不再经过平滑，不需要加速）：港口原本 4/s、丛林与练习场 5.5/s 的指数跟随，按住中键期间提到 14~16，免得起手转视角有拖尾。
- **取景纵深偏移跟着视角转**：港口街市段那 3 米「往北偏」原来写死在世界 -Z 方向。转了视角它会变成横向偏移、把角色挤出取景中心，所以改成沿「画面深处」的世界方向给（`forward_flat()`），任何偏航下构图一致。

**键位冲突（需要留意）**：鼠标中键原本空置给后置的「吞噬之核」（P1 明确不制作，见 `P1_SCOPE_BASELINE.md`）。现在中键用于镜头控制，吞噬之核的键位在 `scripts/ui/key_bindings.gd`（F1 面板与底部提示的唯一数据源）里标为「待重新指定」，其余文档同步加注。

### 实现与验收

- 组件 `scripts/world/camera_orbit_controls.gd`（`RefCounted`，不依赖场景）；接入点 `harbor.gd` / `colpo_level.gd` / `scripts/main/main.gd`，三处都用各图原有的默认参数 `configure()` 起步。
- `tools/validate_camera_orbit.gd`（headless，新增，只读状态、不覆盖预览图）：四张图（港口 / 丛林外围 / 丛林空地 / 自由练习场）—— 出生机位不变、光标落在画面四角都不带动镜头、中键左右与上下拖动按灵敏度改机位且真的落到取景里、俯角与距离的上下限被夹住、滚轮拉近拉远、景深等比缩放、四个朝向角色都在画面内。**本轮又扩了 19 项/图，见下一节**（当时每图 43 项、合计 169 项）。
- 既有回归未退化：`tools/validate_jungle_camera.gd`（86 项，原来的「鼠标让出」断言已换成轨道机位断言）、`tools/check_harbor_port.gd`、`tools/check_occlusion_fade.gd` 全部 PASS，stderr 为空。
- 改造前脚本备份：`.local-backups/camera-orbit-20260919/`。
- 当前模型不能读图，**拖动与缩放的实际观感未经视觉确认**；灵敏度（0.22 度/像素）与限位（俯角 6°~45°、距离 12~96 米）是给的初值，手感不对改 `camera_orbit_controls.gd` 顶部的常量即可。

## 转视角甩镜头与走动方向（2026-09-19 晚，玩家实测反馈）

玩家反馈两条：「转到 180° 后按 W 是往画面下方走的」「按住后移动起来屏幕抖抖的」。第一条是移动方向写死在世界上；第二条**逐帧量到了真凶**：拖动转视角时相机脱离轨道球，角色最多被甩出 800~1300 px。

### 1. 移动方向改为按机位算（`player.gd`）

- 原来 `input_dir` 直接当世界方向用（`Vector3(input_dir.x, 0, input_dir.y)`），W 永远指世界北。机位转到 180° 后世界北落在画面下方，W 就成了"往下走"。
- 现在新增 `player.world_move(input)`：把 WASD 按**当前机位朝向**投影到地面（`-camera.global_basis.z` 为前、`camera.global_basis.x` 为右），**W 永远朝画面深处走**。`facing`、剃的 `dodge_dir`、目标速度三处统一改走它；返回长度＝输入长度（摇杆半推仍是半速）。
- 四张图出生偏航都是 0（`CAMERA_YAW`／`CameraStyle.YAW`），默认朝向下 W/A/S/D 的世界方向与改动前**完全一致**，所以既有朝向/冲刺/关卡断言不受影响。

### 2. 机位改成「平滑锚点 + 刚性轨道」

旧做法把平滑加在 `camera.position` 上（`camera.position.lerp(焦点 + 轨道偏移, k)`）——**位置在追、朝向却是即时的**，于是拖得越快相机离轨道球越远：

| 场景 | 拖动转视角时角色离画面基准点的漂移 | 相机到角色的距离 |
| --- | --- | --- |
| 港口（改前） | 825 px | 43.23~44.91 m（标称 48.1） |
| 丛林空地 / 练习场（改前） | 1262 ~ 1286 px | 42.37~48.21 m |
| 四张图（改后） | **0 px** | 恒定 |

新结构（`camera_orbit_controls.gd` 的 `place()` / `snap()`）：

```
position = 平滑锚点 + 构图偏移 + 轨道偏移
```

- **平滑只加在锚点上**（锚点＝玩家那一侧的世界点，走路由它负责跟手，收敛率 4~5.5/s）。
- **构图偏移与轨道偏移挂在机位朝向上**，随转动**即时**生效、不过平滑：转视角时角色在画面里的位置完全不变，不会先甩出去再追回来。
- 相机到锚点的距离恒为 `distance`（轨道是刚性的），景深基准不随加减速漂移。
- 顺带删掉"拖动时加快跟随"（`FOLLOW_SPEED_DRAGGING`）：转动已经不经过平滑，不需要加速。
- 构图偏移（丛林/练习场的 `CameraStyle.composition()`、港口街市段那 3 米）统一按「画面深处」给：世界口径只在出生偏航下等价，转到 180° 后角色会从"下三分之一"翻到"上三分之一"，转的过程中取景还会横向滑动。

### 3. "走路抖不抖"是量出来的

无头逐帧喂固定 dt：

- **角色屏幕坐标抖动**：渲染:物理 = 1:1 与 1:3 两种比例下都是 **±0.62 px**（四张图、四个偏航数值一致，说明取景关系确实与朝向无关）。这 0.62 px 是"角色位置按物理步长跳、相机按渲染帧平滑"的固有锯齿，不是缺陷；回归阈值按实测定在 1.0 px。
- **相机逐帧位移**：匀速段单帧跳变 ≤0.007 m，没有高频分量。
- **遮挡淡出**：走动全程淡出单元的 `t` 方向翻转 0~1 次，没有边界抖动。

### 4. 顺带发现的坑：无头里 `move_and_slide` 用的不是物理步长

`tools/validate_*.gd` 手动调 `player._physics_process(dt)` 时，内部的 `move_and_slide()` 取的是**空闲帧 delta**（实测等效 0.16 m/次，约物理步长的十倍），位移被放大、不同次运行还不一样（0.093 / 0.353 m/帧都出现过）。所以校验脚本里"走多远"不能当判据；`validate_camera_orbit.gd` 的走路检查只取脚本算出的朝向（`player.facing`），位置按真实物理步长自己推进。

### 实现与验收（本轮）

- 改动：`scripts/world/camera_orbit_controls.gd`、`scripts/world/jungle_camera_style.gd`、`scripts/world/harbor.gd`、`scripts/world/colpo_level.gd`、`scripts/main/main.gd`、`player.gd`、`scripts/ui/key_bindings.gd`、`tools/validate_camera_orbit.gd`。**没有动任何 `.tscn`**。
- `tools/validate_camera_orbit.gd`：四张图各 62 项，**`CAMERA_ORBIT: PASS`（249 项）**。新增断言：拖动 90 帧角色漂移 ≤40 px（旧实现 825 px，必失败）、拖动时相机到锚点距离恒定 ≤0.01 m（旧实现差 1.7 m，必失败）、玩家不动则锚点不漂、按 W 真的会走、四个偏航下 W 都朝画面深处走且角色不出画、走路时角色屏幕抖动 ≤1 px。
- 既有回归未退化：`validate_jungle_camera.gd`(86) / `validate_player_visual.gd` / `validate_jungle_art.gd`(105) / `validate_level_refine.gd`(0 失败) / `check_harbor_port.gd` / `check_occlusion_fade.gd` 全 PASS，stderr 为空。`validate_colpo.gd`（启动场景未指向选关面板、传送门提示）与 `validate_demo.gd`（练习场 coins≠0，存档所致）的失败**与本轮无关**，是既有问题。
- 备份：`.local-backups/camera-rig-20260919/`。
- 当前模型不能读图，**观感未经视觉确认**；跟随收敛率、构图偏移（1.5 m / 1 m）都在对应脚本顶部常量里。



## 动作跟按键走：八方向取图改为“以机位为北”（2026-09-19 晚·二）

### 问题

走动方向修正后用户反馈：机位转 180° 后按 W，**位移对了但动作不对**——角色播的是正面 walk_down，看起来像倒着走。根因：`player.facing` 已按机位换算成世界方向，但 `player_visual._to_dir_name()` 直接拿**世界方向** `atan2(x,z)` 量化取图。机位转到 180° 时按 W 的 facing 指向世界南，取到“朝观众”的正面图；而人在画面上明明往深处走。

### 修法

- `player.gd` 新增 `view_dir(world_dir)`：把世界方向转回“以机位为北”的视角系（`Vector3(d·right, 0, -d·forward)`），机位为空时原样返回（退回旧口径，截图/无头工具安全）。
- `player_visual.gd` 的 `_to_dir_name()` 入参先过 `player.view_dir()` 再量化。它被死亡/受击/闪避/待机行走/攻击/架挡全部动作取图共用，**一处改，全部动作跟按键走**：W 永远播背面、D 永远播画面右侧的图。攻击的鼠标预瞄方向（`buffered_direction`）同样受益——朝画面上方出招就播背面招式。
- 战斗判定的 `facing`（攻击扇形、伤害方向）保持世界口径，不受影响；`dash_fx` 残影拷贝 sprite 当前帧，自动跟随。

### 验收

- `tools/validate_camera_orbit.gd` 扩到 **269 项 PASS**：新增四偏航 × 按 W 必播 up、偏航 180° 按 D 必播 right（四张图各 5 项）。做过负向测试（临时退回世界口径取图）：精确复现“偏航 180° 按 W 实际 down”，证明断言真抓得到旧 bug。
- `validate_player_visual.gd` PASS，无回归。

## 俯角上限收到 45°（2026-09-19 晚·三）

用户反馈：俯角抬太高后"看着像趴在地上"——HD-2D 立绘是竖直贴片，俯角越陡越被压扁，接近俯视时人物就像躺在地上。`camera_orbit_controls.gd` 的 `MAX_PITCH` 从 70° 收到 **45°**（下限 6° 不变）。

- 目视对照（`.tmp_preview/pitch_cap/` 三张图）：16° 正常；**45° 角色依然立得住、舞台感保留**；70° 已近俯视、立绘与灯柱都被压扁，正是要避免的观感。
- `tools/validate_camera_orbit.gd` 限位断言本来就读 `Orbit.MAX_PITCH`，自动跟随；另加一条上限数值锁死（`MAX_PITCH <= 45`，四张图各 1 项），抬高"抬高俯角"测试基准改为 `MAX_PITCH - 1`。**273 项 PASS**；`validate_jungle_camera.gd` 86 项 PASS。

## 左上商店区「轮回商店」+ 商店 UI 框架（2026-09-19 晚·四）

按用户两张概念图搭出：① 左上（西北角）一处商店区（暗色店面 + 门楣挂匾 + 门前陈设），② 「轮回商店」UI 框架（左分类 / 中商品网格 / 右详情 + 购买）。概念图是暗黑哥特风，素材库是江南系，按"用现有资源"的约定取意象、不追形。

### 商店区（3D）

- 布局模块 `tools/harbor_shop.gd`，增量脚本 `tools/apply_harbor_shop.gd`（幂等：先删旧 ShopDistrict 再重建；同时把服务点从主街西段 (-10,0,-9) 搬到店面正前方，并改写服务点标题/描述/招牌文案）。全量重建管线同步：`harbor_zones.gd` 引用 `HarborShop.SERVICE_AT` 并挂 `HarborShop.make_node()`。
- 素材（全部已入库预设）：店面 `SM_JN_fangzi006`（自带格子窗的两层小楼）+ 门楣挂匾 `SM_gsc_gusuchengpaizi001`（y=5.55 嵌门脸，像素字匾额——实拍确认它就是"悬匾"观感的来源，曾被误删又恢复）；货架 `SM_Item_NJhuojia001/002` 分立门口；石灯 `SM_NJ_ShiDeng_001` 贴门脸两侧；木牌 `SM_NJ_ZhuPai002`、货箱堆、集市红毯 `SM_gsc_tanzi001`（0 高度贴片，**必须 COLLIDE_OFF**）+ 石桌 + 木凳、蓝布贴片 `SM_xgg_tanzi003`；青色灯带 `ShopSignGlow` 打门脸 + 暖色 `ShopDoorLantern`。
- 服务点坐标 `SERVICE_AT = (-24, 0, -18)`：**z∈[-18.4,-17.6] 的南北向直达走廊必须净空**（check_harbor_hub 的可达断言走这条线）——石灯贴门脸 (z=-19.5)、货架贴楼 (z=-19.9)、石桌收进集市心 (z=-16.8)，都是为这条线让路。
- 截图（`.tmp_preview/shop_area/`）：`shop_street.png` / `shop_front.png` / `shop_east.png`（3D 区成片）、`shop_ui.png` / `shop_ui_selected.png`（UI 框架实拍）。

### 商店 UI（轮回商店）

- `scripts/ui/shop_panel.gd`（CanvasLayer，纯代码构建，风格与 HUD 一致）：左分类页签（全部/武器/防具/饰品/消耗品/材料/宝藏）、中间商品网格（ScrollContainer + Grid，名称带品质色 + ◇价格，点选金边高亮）、右详情面板（预览字块 + 名称 + 品质分类 + 描述 + 单价 + 购买）、右下乐园币（`GameState.coins`）。占位商品表 14 条（`GOODS` 常量），购买 `_purchase()` 走 `GameState.buy_item()`：扣币、入包、落盘都是真的。
- 接线：`harbor.gd` 实例化 ShopPanel 并把 `ShopService.panel_handler` 指到 `open()`；`harbor_service.gd` 的 `panel_handler`（**campaign_action 优先**，而当前战役模式不再给 ShopService 设 campaign_action）面板自管开/关、冻结玩家、Esc/V 关闭；加入 `shop_panel` 组，HUD 的 `is_modal_open()` 与鼠标模式把它当模态面板。
- 口径：主城（战役 / 直接开港调试都一样）→ V 开轮回商店 UI，购买统一由店内完成。

### 任务 UI（任务档案）

- `scripts/ui/quest_panel.gd`（CanvasLayer，纯代码构建，同一套 `SystemUI` 设计语言）：左任务名列表（分章 + 状态方块，可点选 / ↑↓），右选中任务的状态、委托方与地点、目标清单、说明、奖励与记录，底栏进度与（可选）动作按钮。数据只读，来自 `data/quest_log.gd`（把 `campaign` 进度映射成任务表），详见 [QUEST_PANEL.md](QUEST_PANEL.md)。
- 接线：HUD 里按 <kbd>J</kbd> 或在 Esc 菜单点「任务档案」随时打开；灰潮港西侧**委托所 <kbd>V</kbd>**（`QuestService`）也开同一块面板 —— 战役模式走 `campaign.show_tasks()`，有可接任务（`flow == equipped`）时把底栏动作设成「接取任务 · 猎杀者试炼」，按下即 `_accept_first_quest`；非战役模式（直接开港调试）走 `harbor.gd` 接的 `QuestService.panel_handler`。
- 口径：委托所不再是纯文字说明面板；原来的「船到港 / 教学中 / 已接取 / 阶段记录」几段文案由面板的序章条目与「轮回记录」章承接。加入 `quest_panel` 组，HUD 的 `is_modal_open()` 与鼠标模式把它当模态面板（商店开着时 <kbd>J</kbd> 不生效）。

### 验收与顺手修的回归脚本

- `check_harbor_hub.gd` **PASS（25 项）**：商店 7 项（可达/提示/V 打开轮回商店 UI/冻结/Esc 关闭恢复/离开收提示）全过。该脚本原来按"传送门按 V"旧口径测传送门，而 `scene_portal.gd` 早已改成**走进即传**——试炼门接触即传送把场景切走，脚本访问已释放的 HUD 直接崩、quit() 永远跑不到（表现为无头挂死）。已按现状改口径：传送门只测目标存在 + 实际传送/返回（改造前基线同样复现，确认与本轮无关）。
- `check_harbor_port.gd` PASS（16 项通行）、`validate_camera_orbit.gd` PASS（273 项）。
- 备份：`tools/backups/harbor_before_shop.tscn.bak`（首跑创建，重跑不覆盖）。

### 修复：淡出单元平行数组错位导致收尾越界（2026-09-19 晚·五）

实机报错：`camera_occlusion_fade.gd:418 _end_unit` —— `Invalid access of index 3 on a base object of type: Array`（栈：`_physics_process` → `_update` → `_end_unit`）。

- **根因**：`_begin_unit()` 维护四条平行数组 `instances / modes / fades / originals`，但 `originals` 只在 `mode == "shader"` 时 append，其余三条每个被接受的实例都 append。**同一个淡出单元里混有标准材质网格与自定义着色器网格时**（例：预设摆件 + 程序化网格并进同簇）数组就错位；`_end_unit()` 按 `originals[i]` 还原材质时越界。
- **修法**：`originals` 与非 shader 模式同样占位（值补 `null`），四条数组逐位对齐；`originals[i]` 仍只在 shader 模式使用。
- **为什么现在才炸**：这是既有缺陷，但需要"同一簇里混材质"才触发。左上商店区把预设摆件（自定义着色器）与程序化网格（标准材质：服务点光圈等）摆得足够近之后才真正命中。
- **回归**：`tools/check_occlusion_fade.gd` 新增「混合材质单元」断言——人造一个 3×标准材质 + 1×着色器（第 4 格正是旧代码越界的那一格）的单元，断言四条数组等长、收尾能还原材质。**先比长度再调用 `_end_unit`**：将来再错位时脚本要干净地记 FAIL，而不是抛越界把整个脚本中断（不 quit 会表现为无头运行无限挂起）。负向测试（临时改回旧写法）精确复现 `instances=4 / originals=1` 并报 FAIL。
- 复跑：`OCCLUSION_FADE_CHECK: PASS`（含 5 个落点、材质落地、恢复、砌体粒度、摆件成簇、混合材质单元）。

### 商街扩展：从一间店面扩成一条街（2026-09-19 晚·六）

用户反馈"商店区不够繁华，多做一点建筑"。把原来孤零零一间轮回商店扩成西北角一条小商街：**北排四家铺面**（成衣铺 `SM_JN_fangzi001` / 轮回商店 `SM_JN_fangzi006` / 茶馆 `SM_JN_fangzi005` / 杂货铺 `SM_JN_fangzi002`，x 从 -35.2 连续到 -5），街心货摊四座 + 两座竹棚 + 晾绳挂药材 + 陶缸 + 石桌石凳 + 茶座竹桌椅，门窗陈设补石狮、门帘、二层阳台，街面插三面招幌、西口立牌楼 `SM_JN_Gongmen001`，灯串铺到四盏（青灯仍打在匾额上）。`ShopDistrict` 从 17 个子节点增至 69 个，场景 385 → 437 节点。

两条布置经验（都是这轮踩出来的）：

- **这类民居预设只有南立面有门窗**。横转 90° 想做出"朝东的铺子"，从街上看到的只是两面**空白山墙**（第一版在 x=-34 立了两家，实拍就是两堵白墙）。要"多建筑"就往同一朝向的排面上加长，别指望侧转能变出店面来。西侧因此改做货栈后院（竹棚 + 货箱 + 酒旗 + 石凳），既有内容又不露白墙。
- **新家具会啃进已有的净空走廊**：街南侧坐具排原本写死在 z=-16.7，加常量后木凳碰撞盒（比网格看上去外扩得多，实测探到 z≈-17.6）压进 `z∈[-18.4,-17.6]` 的直达走廊，`check_harbor_hub` 的"从主街可达"立刻 FAIL。修法是把坐具排南移到 `SOUTH_LINE=-15.9`（离走廊 ≥1.2 米）并在常量处写明理由。定位手段：从主街沿走廊逐米 `test_move` 找首个阻挡点，再用 `intersect_shape`（排除玩家）点名碰撞体——比读模型猜快且准。
- 牌楼的位置也据镜头实拍定过两次：**侧转 90° 在低俯角机位下只剩一根立板**，所以要面朝南（yaw 0）；摆在广场正中又会把轮回商店的石狮与门帘整个罩住（低俯角下门楼必然压住它身后的立面），最终放到集市西口 x=-29.4 的开阔地，当西巷门用。

验收：`check_harbor_hub` PASS（25 项，含商店 V 开 UI / Esc 关闭 / 从主街可达）、`check_harbor_port` PASS（16 项通行）、`check_occlusion_fade` PASS（含混合材质单元断言）、`validate_camera_orbit` PASS（273 项）。截图：`.tmp_preview/shop_area/town_{street,plaza,west,east,market}.png`。

## 东侧工坊「铸潮工坊」+ 西侧任务所「港务委托所」（2026-09-20 凌晨）

把强化区与任务区两处只剩光圈与招牌的功能点，按商店区同一套做法（布局模块 + 幂等 apply 脚本）补上建筑与陈设。素材仍只用已入库共享预设；服务点位置不动，只在其周围成街。

### 实现路径

- 布局模块 `tools/harbor_forge.gd`（ForgeDistrict，34 子节点）、`tools/harbor_quest.gd`（QuestDistrict，30 子节点）；增量脚本 `tools/apply_harbor_hub_districts.gd`（幂等：先删旧区再重建，备份 `tools/backups/harbor_before_hub_districts.tscn.bak` 首跑创建、重跑不覆盖；落盘后校验两个服务点仍落在模块声明的 `SERVICE_AT` 上，防止将来"服务点搬了家、布局没跟"）。全量管线同步：`harbor_zones.gd` 的 ForgeService / QuestService 改为引用两模块的 `SERVICE_AT` 并挂 `make_node()`。场景 437 → 503 节点。
- 素材实测工具 `tools/probe_quest_forge_presets.gd`（一次量出候选预设世界 AABB；这批预设原点均在脚底中心）。截图工具 `tools/capture_hub_districts.gd`（只写 `.tmp_preview/hub_zones/`，不碰 docs 既有文档图）。

### 铸潮工坊（ForgeDistrict）

强化巷（z=-9）北侧一排锻造铺面：两层锻造楼 `SM_JN_fangzi001`（x∈[3,9]）+ 宽车间 `SM_JN_fangzi002`（x∈[9,18]）拼成 15 米连续立面，与巷东端 x=18 对齐。门前陈设排 z≈-12.3：熔炉 `SM_Item_luzi001`（带火光 OmniLight3D）+ 烟囱 `SM_Item_yancong002`、锻造台 `SM_Item_zaotai001`、武器架 `SM_Item_NJhuojia001/002`、淬火缸 `SM_gsc_gu002/001`、石灯；立面外挂矿石标本贴片（铁/乌晶/黄铜/萤，0 厚度必须 COLLIDE_OFF）与"剑心亭"招幌 `SM_mjsz_jianxintingpaizi001`；街南侧收石料堆、大魔晶 `SM_Item_damoshuijing001`、货箱与坐具。

### 港务委托所（QuestDistrict）

任务巷（z=1）北侧：主楼 `SM_JN_fangzi002`（x∈[-14.5,-5.5]，正对服务点）挂"姑苏"匾额，门前公告板两座（`SM_NJ_ZhuPai002` / `SM_Item_paizi002`）、登记柜台 `SM_Item_guitai002`（台上放卷轴 `SM_xgg_yjzpjuanzhou001`）、石狮一对、神龛；主楼与副楼 `SM_JN_fangzi005`（x∈[-26.5,-20.5]）之间留 6 米前院，铺 `SM_mjsz_diban001` 地砖（0 高度贴片必须 COLLIDE_OFF）；巷南侧一排石桌木凳与竹桌椅书架，旗 `SM_Wuxianjiao_qizi003` 立在副楼西侧。青绿灯 `QuestSignGlow` 打在匾额上（呼应任务区分区色）。

### 布置约束（这轮新踩出来的）

- **港口机位与玩家同 x，「镜头→玩家」的遮挡射线是一条 x=玩家 的竖列**：任何东西的包围盒压进玩家所在的 x 列且够高，就会顶进那台机位的视线，`check_occlusion_fade` 的「石板街中段 @(-4,0,-4) 单元数=0」立刻 FAIL。第一版把 3.88×6.2 的招幌立在 (-4.9, 0, 4.8)、2.05 宽的巷口木牌立在 (-5.0, 0, 4.6)，两条都被诊断日志点名（`单元「@Node3D@14」含 SM_NJ_ZhuPai002`）。修法：路标类东西要么往西收到 x≤-5.7（东沿 -4.68），要么挪出主街列；定位手段就是脚本打印的单元明细，不用猜。
- **服务点可达走廊依旧神圣**：工坊门前陈设排压在 z≤-11.3（与 z=-9 可达线留 2.3 米），任务所门前陈设排压在 z≤-2.1（与 z=0.5 可达线留 2.6 米）。
- **已有的灯柱 LanternPost 别吞进楼里**：harbor_lighting.gd 在 (11.3, 0, -12) 立着灯柱（也是「强化台实心」断言的阻挡来源），工坊铺面南沿因此收到 z=-12.83，让灯柱露在门外。
- **check_harbor_port 有条历史断言「(-20,0,-7) 向 -z 可走」（名字还叫"客栈…正面可走入"，其实早就空过）**：任务所副楼因此收到 x≤-26.5，不摆进 x=-20 一带，断言不必改口径。
- 建筑依旧只有南立面有门窗，一律 yaw 0 面朝街；主楼东沿收到 x=-5.5，东侧 2.5 米不摆东西（保住 (-4,0,-4)→(0,0,3) 的通行断言）。

### 验收

`check_harbor_port` PASS（16 项通行）、`check_harbor_hub` PASS（25 项，服务点可达 / V 开面板 / Esc 恢复全过）、`check_occlusion_fade` PASS（9 项）。截图（`.tmp_preview/hub_zones/`）：`{forge,quest}_{front,front_west,west,aerial}.png`、`hub_pair.png`、`game_{forge,quest,street}.png`（游戏默认机位实拍）。

## 港口装饰景观层（2026-09-20 凌晨·二）

主体功能区齐了之后补"血肉"，原则：**成组成片、主题分明、留白**——五个子区各管一片，不做满铺。

### 实现路径

- 布局模块 `tools/harbor_dressing.gd`（HarborDressing，93 子节点）+ 增量脚本 `tools/apply_harbor_dressing.gd`（幂等，备份 `tools/backups/harbor_before_dressing.tscn.bak`）。素材探测 `tools/probe_dressing_presets.gd`，截图 `tools/capture_dressing.gd`。场景 503 → 597 节点。

### 五个子区

- **EastQuarter 东侧民居坊**（x∈[23,38]）：`SM_JN_fangzi003`（实拍发现它是**过街门楼**，门洞正中挂一片布帘 `SM_Item_lianzi001`，穿堂正好框出房后竹林）+ `SM_JN_fangzi007`（格子窗单层屋）；房后竹林松柏成组错位、竹栅栏 `SM_hpsz_weilan111zuo`（COLLIDE_BOX）沿 z=-20.6 围院留门口，门前石凳水缸木牌石灯，坊东端招幌收口。
- **WestYard 西侧货栈院**（x∈[-38,-28]）：大工棚 `SM_jzc_mapeng001`(0.85) 压中线、竹棚、两组箱堆、渔网贴西墙、一排酒坛 `SM_Item_jiutanzi04`（模型本身就是 8.3 米的整排坛子）、篝火 `SM_Item_gouhuo001` 配橙光、院南缘矮栅栏、真 3D 大树 `SM_Item_yjdashu003` 缩 0.4 给西片区一个绿色锚点。
- **ShoreGreen 岸线绿化**：水岸 z≈11 的西段/东段/内港两侧三组灌木草丛（避开码头贴岸开口与内港喉口）；内港港池里半浸一架水车 `SM_ltem_Shuiche001`（y=-0.45）。
- **GatePlaza 北门广场**：传送门两侧石灯一对、招幌、路缘石墩；**城根背景林**沿北墙 z≈-29.7（x≤-8，北门通道净空）与西墙一列，把建筑背面与城墙之间的空缝填成树影。
- **StreetGreen 主街南段与试炼场**：路缘灌木与一棵粉桃树 `SM_taoshu001`(0.42)（树冠内缘留在 |x|≥4.5）；演武场入口旗 + 石墩 + 东南角四根练功木桩（`SM_NJ_Zhuziweilan001` 单根竹桩 ×4）与歇脚石凳水缸。

### 素材结论（这轮实测的）

- 灌木/草/桃树/竹/松柏全是 **facing=2 薄片植物**（运行时转向镜头，随便摆不会侧成线），预设不带碰撞，COLLIDE_PRESET 摆下去即纯装饰；`SM_1dashu001` 是 facing=0 固定平面，**不可用**（侧看成线）。
- 植物配色要挑：竹子（zhuzi 系列）贴图偏暗紫，近看像枯竹，只适合房后/城根做剪影；`SM_HD_Guanmu005` 近看像仙人掌，主街两侧换成 `Guanmu001/009` + 松柏。
- **晾衣绳方案废弃**：绳横跨两栋楼会穿墙、第二片帘子嵌进隔壁屋顶（实拍穿帮）；门楼里挂单片布帘成立。

### 布置约束（沿用并强化）

- 机位同 x 竖列约束依旧生效：主街两侧植物树冠内缘 ≥|x|3，乔木 ≥|x|4.5；probe 落点列（x=0/-4/-5.7/-8/-20/16.5）的南侧不摆高物。
- 截图脚本偶发挂在 game 机位等待段（SIGTERM、无 SCRIPT ERROR），重跑即好——批量截图脚本要有"重跑即好"的心理预期，别急着改代码。

### 验收

三回归 PASS（port 16 项 / hub 25 项 / occlusion 9 项）。截图（`.tmp_preview/hub_zones/`）：`{east,west}_{front,aerial}.png`、`shoreline.png`、`town_overview.png`、`game_{street_south,east_quarter,west_yard}.png`。


## 北墙外「科尔波山」远景层（2026-09-20 凌晨·三）

北门传送环（`DeparturePortal` @(0,0,-21)，招牌"世界入口 · 阶段试炼"）是新手流程与常规循环的出发口：hub 内由 campaign.gd 注入 `start_first_trial()`，按存档阶段装载 `campaign.tscn`；节点上的 `target_scene` 只作无控制器时的兜底，现已改为 `campaign.tscn`。这轮在北墙外用已有"山石"预设搭出科尔波山的视觉示意（1.6 阶段试炼的所在地），兼作港口北向的后景。

### 实现路径

- 布局模块 `tools/harbor_mountain.gd`（`HarborMountain`，29 节点）+ 幂等 apply `tools/apply_harbor_mountain.gd`（备份 `tools/backups/harbor_before_mountain.tscn.bak`）；素材探测 `tools/probe_mountain_presets.gd`、预览截图 `tools/capture_mountain_preview.gd`（带渲染跑，不覆盖既有 docs 图）。
- 分区：**Ridge** 前排山脊 7 座悬崖沿 z=-33 脚线连绵咬合（脚线 = 中心 z − 深度×scale/2，模型原点在俯视几何中心）；**Peaks** 后排群峰 4 座退到 z≈-55（主峰 xuanya005×1.35 ≈ 28 m，偏西；中峰正压前排同位悬崖，上层露头下层挡脚）；**GateView** 北门门洞正后一棵圆柏 ×1.5 + 一盏青白山口冷光；**Foothill** 前沿孤岩散石 6 件；**Treeline** 山脚薄片松柏 10 棵；东西两翼悬崖包过城墙转角成环抱。全部 `COLLIDE_OFF`（玩家不可达的纯背景）。

### 素材结论（这轮实测的）

- `SM_Jiangnan_xuanya001~007`（分类"山石"）是桂林式喀斯特峰林模型，落地即站、群摆咬合成连绵山脊，俯瞰效果极佳；001 宽扁（24×12.7×28）、003/004/005 高（20~21 m）、007 宽大（28×16×26）。
- `SM_DM_Zudangshitou001` 大山石 15 m 级，×0.4 左右当城外孤岩；`SM_YX_Shitou001` 散石点缀。
- 预设无可见距离/LOD 限制，多远都渲染。

### 机位可见性（重要结论，别再踩）

港口机位是 **18° 长焦 + 16° 俯角**（`harbor.gd` CAM_FOV/CAM_PITCH），画面顶缘对应"俯视 7°"的视线——**城墙以外任何正高度的物体，在任何合法俯角（6~45°）与距离（12~96 m）下都进不了默认画面**；长焦平铺舞台机位天然"看不见远方"。因此：

- 山体的可见场景＝俯瞰/全图视角（`docs/harbor_mountain_aerial_preview.png`）、编辑器、以及未来"出城山路"等自带机位的场景直接复用这批悬崖。
- 默认画面里唯一能带进北墙外的窗口是**北门门洞取景框**（门洞上沿视线到 z=-34.5 处只剩 4.5 m 以下）：门洞正后的垭口圆柏 + 青白冷光落在这条带里，夜景中门洞上部透出一线冷光，与城中暖橙灯形成"门后是另一片山"的色彩语言（`docs/harbor_mountain_gate_preview.png`）。门叶（GateLeaf x=±1.1）会挡去中部视线。
- 若日后想让山真正进默认画面，得动机位（加宽 FOV 或减小俯角下限），属场景级决策，本轮不动。

### 布置约束（新增）

- 山脚线统一 z=-33（北墙外沿 -32.2 之外留缝），不压墙体、不进北门通道 x∈[-4.4,4.4]。
- 山全在所有遮挡探针玩家位以北，遮挡淡出"相机→玩家"线段到不了墙外，山体不会误触发淡出（check_occlusion_fade 全 PASS 验证）。
- 城墙外是水面（山脚直接立在水上，y=0 vs 水面 -0.72），喀斯特峰林临水的观感成立；若未来要做"出北门的山路"，需另铺地面网格+石板路，本轮未做。

### 验收

三回归 PASS（port 16 项 / hub 25 项 / occlusion 9 项）。预览图：`docs/harbor_mountain_aerial_preview.png`（高空全山）、`docs/harbor_mountain_gate_preview.png`（北门门洞机位）。



