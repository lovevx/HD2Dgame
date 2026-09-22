# 丛林场景美术整理 · 2026-09-17

> 后续已完成低角度透视镜头调整；当前参数及最新预览见 [丛林镜头优化](JUNGLE_CAMERA_PASS.md)。本文保留首次美术整理时的对比记录。

森林外围和森林空地已应用同一套美术规范。优先复用 HD2D 场景工坊中现有的模型和像素贴片，本轮没有生成付费素材，也没有新增 Blender 建筑。

## 打开与继续编辑

- `scenes/world/colpo_forest_outer.tscn`：森林外围，包含林间小路和西南侧废弃木屋。
- `scenes/world/colpo_forest_clearing.tscn`：森林空地，北侧古树地标、内外林缘，以及保留的中央战斗空间。
- `scenes/workshop/jungle_palette.tscn`：真正的 `HD2DStage` 素材板，挂接丛林专用库。打开后可用场景工坊按“乔木 / 地被 / 山石 / 建筑”筛选这批资源。
- `assets/environments/jungle/jungle_library.tres`：16 项专用资源。
- `assets/environments/jungle/props/`：对应的场景包装与资源定义，使用中文显示名和固定资源身份。

游戏场景中按原操作移动和战斗。出生点、刷怪点、炸弹建议点等开发标记默认隐藏；需要检查布局时，在场景根节点启用 `show_layout_markers`。实际刷怪、准备阶段、HUD、传送交互均保留。

## 实施内容

1. 原树木存在大量薄片网格，却被随机旋转 360°，造成侧面对镜头时变成细线。本轮让乔木和地被统一朝向 8° 固定镜头，只加入小幅角度与大小变化。
2. 主树种收敛为两种阔叶乔木，移出松柏、竹子和突兀的花灌木。11 米宽的蕨丛按 0.13–0.22 倍使用，避免素材源尺度混乱。
3. 地面改用统一的世界坐标材质，形成泥土小径、苔藓林缘和空地磨损过渡；取消重叠道路砖块，压低碎屑的尺寸与对比。噪声使用整数哈希，修正首轮 GPU 渲染中出现的矩形接缝。
4. 镜头俯角从 52° 改为 43°；主光采用暖色，环境光偏冷，降低饱和度、辉光与景深强度。地面保持清晰，前景树冠仍按玩家位置淡出。
5. 岩石外观按既有掩体碰撞尺寸适配，避免原先高大石柱抢占画面。保留可绕行掩体、关卡边界与主通路。
6. 外围采用现有破屋构成废弃林间木屋，补充周围蕨丛；空地北侧设置古树地标，并在中央 12 米以外补充内层树冠。
7. 两张地图加入少量漂浮花粉，减少装饰光柱。地被与背景树林沿用工坊 MultiMesh 分块散布，主路和战斗核心排除地被。

## 资源取舍与依赖

| 类型 | 保留来源 | 用途 |
|---|---|---|
| 主树种 | `SM_1dashu001_LODs`、`SM_1dashu002_LODs` | 前景与林缘，固定朝向 |
| 古树 | `SM_NJ_Jvqingshu001` | 空地北侧地标 |
| 地被 | `SM_NJ_Yvlinzhiwu001/002/003` | 蕨丛、低矮植物与卷叶蕨 |
| 苔岩 | `SM_XYNJiangnan006/012/016` | 掩体和近景边界 |
| 山壁 | `SM_Jiangnan_xuanya001/002/003/005/007` | 外围高差与背景围合 |
| 建筑 | `SM_kushuicun_pofangzi002` | 废弃木屋；本轮不提供室内玩法 |
| 备用 | `SM_NJ_Shitoudui001` | 库内保留，未用于最终近景石带 |

原始 `assets/hd2d_presets` 目录保留。专用包装引用其中的原网格和纹理，材质修改保存在专用包装中，没有改写原始材质。因此不能删除原始目录；这次是建立可维护的使用层，并非把所有依赖物理搬走。纹理统一使用最近邻加 mipmap 采样，降低远处闪烁。

## 验证与性能记录

- `tools/validate_colpo.gd`：123 项检查通过，覆盖路线、边界、掩体、树干、前景淡出、波次、Boss、传送、死亡结算与操作界面。
- `tools/validate_jungle_art.gd`：97 项检查通过，覆盖 16 项资源依赖、唯一身份、素材板、贴片朝向、地被避让和默认隐藏开发标记。
- 使用 Godot 4.7.2、Forward+ / D3D12、RTX 3060 Laptop 实际渲染，检查入口、小径、出口、木屋、空地与北侧地标，并保存素材板预览。
- 相同的 1280×720 小径视点，绘制调用由 418 降到约 316；空地中央由 403 降到约 311。截图工具关闭了战斗调度器，这些数据是静态场景对比，不是完整战斗性能保证。首次加载和换图瞬间 FPS 会明显波动。
- 退出时存在资源/RID 清理警告；改造前的独立截图运行也出现过这类警告。本次构建没有脚本解析或着色器编译错误，清理警告未在本轮处理。尚未进行长时间人工战斗手感和其他显卡的验证。

## 预览

外围改造前：

![外围改造前](jungle_before/outer_trail.png)

外围改造后：

![外围改造后](jungle_after/outer_trail.png)

废弃木屋与前景淡出：

![废弃木屋](jungle_after/outer_hut.png)

森林空地：

![森林空地](jungle_after/clearing_arena.png)

工坊素材板：

![丛林素材板](jungle_after/palette.png)

## 构建与备份

原始两张场景、生成脚本和关卡脚本已备份在 `.local-backups/jungle-20260917/`，目录包含 `.gdignore`，不会作为游戏资产导入。该目录也保存了本轮构建、测试和渲染日志。

运行命令（PowerShell）：

```powershell
$godotExe = 'E:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
& $godotExe --headless --path E:/godotproject/hd-2d --script tools/build_colpo.gd
& $godotExe --headless --path E:/godotproject/hd-2d --script tools/validate_colpo.gd
& $godotExe --headless --path E:/godotproject/hd-2d --script tools/validate_jungle_art.gd
& $godotExe --path E:/godotproject/hd-2d --resolution 1280x720 --script tools/capture_jungle.gd
```

`build_colpo.gd` 会重建两张关卡、素材板和丛林专用包装。后续手工编辑场景前，应保留副本，或把需要长期保留的布局修改同步到生成脚本。截图脚本只在独立实例中移除战斗调度器并调整玩家位置，不修改保存的游戏场景。
