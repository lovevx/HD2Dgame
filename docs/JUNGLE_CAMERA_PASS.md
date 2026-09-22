# 丛林镜头优化 · 2026-09-17

本轮只调整两张丛林地图的相机与跟随逻辑，保留现有场景摆放、碰撞和战斗流程。参考入口为 [《八方旅人Ⅱ》官方画面介绍](https://www.jp.square-enix.com/octopathtraveler2/about/)。下述数值是本项目实测选择，不是该游戏的官方相机参数。

## 最终取景

| 项目 | 调整前 | 调整后 |
|---|---|---|
| 俯角 | 43° | 30°，更多显示树干、屋檐与远景 |
| 投影 | 正交 | 轻透视，固定偏航 8° |
| 镜头距离 | 27 米 | 29 米 |
| 视野 | 正交尺寸 16 / 18 | 垂直 FOV：外围 30°、空地 33° |
| 构图 | 角色接近正中心 | 静止时脚部约在画面高度 60%，上方留出探索空间 |
| 跟随 | 根据角色面朝方向前瞻 | 按实际移动速度前瞻，最大 0.75 米；原地瞄准不晃镜头 |
| 平滑 | 随帧间隔线性插值 | 指数平滑，减少不同帧率下的差异 |
| 初始状态 | 从原点附近追到出生点 | 出生第一帧即正确取景 |
| 景深 | 远端从 34 米开始 | 远端从 43 米开始、18 米过渡；附近战斗范围保持清晰 |
| 镜头边界 | 两图共同限制 | 外围和空地分别限制焦点范围 |

试渲染了 43° 正交、30° 正交、30° 透视三种方案，最终选择透视方案。对比图在 `docs/camera_study/`；最终六个场景视点在 `docs/camera_after/`。

原视角：

![调整前](camera_study/trail_original_43.png)

最终视角：

![调整后](camera_after/outer_trail.png)

空地北侧：

![空地北侧](camera_after/clearing_north.png)

## 验证

- 70 项镜头检查通过：出生构图、原地转身不推动镜头、16:9 / 4:3 / 21:9 下中央和四角的玩家可见性、鼠标射线与地面位置一致、22 米/秒位移下仍保持角色在画面中、30 与 120 FPS 跟随结果一致性。
- 原有 123 项关卡检查通过，涵盖通路、遮挡、前景淡出、波次、Boss 和传送。
- 97 项美术整合检查通过，涵盖素材库、贴片朝向和地被避让。
- 合计 290 项检查通过。最终独立渲染和这三组检查的 stderr 均为空。
- 实际渲染使用 Godot 4.7.2 / Forward+ / D3D12，1280×720。降低视角后能看到更多远景，因此绘制调用增加：小径约 676、空地约 626。截图中的即时 FPS 不代表长期战斗基准；未验证其他显卡和长时间手感。

## 后续调整位置

- `scripts/world/jungle_camera_style.gd`：统一镜头俯角、偏航、距离、FOV、景深与焦点范围。
- `scripts/world/colpo_level.gd`：跟随、移动前瞻和出生定位。每张图根节点的 `camera_focus_bounds` 可单独编辑。
- `tools/apply_jungle_camera.gd`：只将镜头配置写回现有两张地图，不重建场景美术。
- `tools/build_colpo.gd`：后续完整构建也使用同一镜头配置，不会恢复旧角度。
- `tools/validate_jungle_camera.gd`：镜头回归检查。

本轮修改前的场景及脚本位于 `.local-backups/camera-20260917/`。

```powershell
$godotExe = 'E:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
& $godotExe --headless --path E:/godotproject/hd-2d --script tools/apply_jungle_camera.gd
& $godotExe --headless --path E:/godotproject/hd-2d --script tools/validate_jungle_camera.gd
& $godotExe --path E:/godotproject/hd-2d --resolution 1280x720 --script tools/capture_jungle.gd -- --out=res://docs/camera_after
```

## 镜头操控改版 · 2026-09-19

相机参数没变（16° 俯角 / 正北 / 外围与空地各自的默认距离 / FOV 18°），变的是**操控方式**：

| 项目 | 调整前 | 调整后 |
|---|---|---|
| 光标 | 鼠标离屏幕中心越远，取景往那一侧让出 | 光标移到哪都不带动镜头（「鼠标让出」组件删除） |
| 视角 | 固定 16° 俯角、正北朝向 | 按住**鼠标中键拖动**绕角色转：左右改偏航、上下改俯角（俯角同时决定机位高度），限位 6°~45° |
| 远近 | 固定距离（外围 42.3 / 空地 46.8 米） | **滚轮**按比例推拉，限位 12~96 米 |
| 景深 | 按固定距离设一次 | 跟着距离等比缩放（拉近后角色不会掉进近景模糊区） |
| 跟随 | 统一 5.5/s 指数跟随 | 平滑只加在**锚点**（玩家那一侧）上；构图偏移与轨道偏移挂在机位朝向上、转动即时生效（原先按住中键期间提到 14 的加速已删——转动不过平滑，不需要） |
| 移动 | WASD 写死世界方向（W＝世界北） | WASD 按**机位朝向**算，W 永远朝画面深处走；转视角不会把前进方向反过来 |

改动落在 `scripts/world/camera_orbit_controls.gd`（新组件）+ `colpo_level.gd` / `scripts/main/main.gd` / `harbor.gd` 三处接入；地图文件未改。`tools/validate_jungle_camera.gd` 里原先那段「鼠标让出」断言已替换为机位控制断言（`JUNGLE_CAMERA: PASS`，86 项），另新增 `tools/validate_camera_orbit.gd` 覆盖四张图共 249 项（含「拖动转视角不甩镜头」「走路不抖」「W 跟着视角走」）。完整说明见 [灰潮港口主城·镜头操控](HARBOR_MAP.md#镜头操控2026-09-19) 与 [转视角甩镜头与走动方向](HARBOR_MAP.md#转视角甩镜头与走动方向2026-09-19-晚玩家实测反馈)。改造前脚本备份在 `.local-backups/camera-orbit-20260919/` 与 `.local-backups/camera-rig-20260919/`。
