# 任务面板（J）· 2026-09-22

一个「任务档案」面板：**左边是任务名列表（分章 + 状态方块），右边是选中任务的目标 / 说明 / 奖励**。
内容只读，全部由存档进度推导；灰潮港「港务委托所」打开它时额外给一个接取任务的底栏按钮。

三个入口，都开同一块面板：

| 入口 | 场景 | 说明 |
|---|---|---|
| <kbd>J</kbd> | 任何有 HUD 的场景 | 再按 <kbd>J</kbd> 或 <kbd>Esc</kbd> 关闭；轮回商店开着时 J 不生效（两个模态不叠） |
| <kbd>Esc</kbd> 菜单 →「任务档案 · 阶段进度」 | 战役模式 | 原「任务 / 阶段进度」按钮改开面板，阶段结算报告移入面板的「轮回记录」章 |
| 灰潮港西侧「港务委托所」<kbd>V</kbd> | 主城（战役 / 直接开港调试都一样） | 待接任务时（`flow == equipped`）底栏出现「接取任务 · 猎杀者试炼」；按下即接取并推进流程，面板自动收起 |

实拍：`docs/ui/quest_panel_prologue.png`（序章档）、`docs/ui/quest_panel_run.png`（1.4 待交接档）、
`docs/ui/quest_panel_accept.png`（委托所接取档）—— `docs/**/*.png` 按仓库约定不入库，用第五节的命令随打出图。

## 一、为什么这么做

- **不新增存档字段、不改流程**。任务状态是 `GameState.campaign` 的**只读映射**，所以面板显示的永远和实际进度一致；
  以后加地区 / 支线，只改 `data/quest_log.gd` 一处，不会出现第二份任务表跑偏。
- **接取动作留在战役控制器里**。面板不认识任何流程，底栏按钮的文案与回调由开门方给
  （`hud.open_quest_log_with(text, callable)`，灰潮港那边传的是 `campaign._accept_first_quest`）。
  委托所原来那几段纯文字说明（船到港 / 教学中 / 已接取 / 阶段记录）已由面板的序章条目与「轮回记录」章承接。

## 二、文件地图

| 文件 | 职责 |
|---|---|
| `data/quest_log.gd` | 数据源：`groups()` 四章任务表、`entries()` 拍平顺序、`find(id)`、`default_id()`、状态文案与配色。**纯函数**，存档字典由调用方传入，不引用 autoload |
| `scripts/ui/quest_panel.gd` | 面板本体（CanvasLayer，纯代码构建，`SystemUI` 设计语言）：左列表 + 右详情 + 底栏进度与可选动作按钮；`open(action_text, action)/close()/toggle()` |
| `scripts/ui/hud.gd` | 挂载与开关：`_build_quest_panel()`、`open_quest_log()/open_quest_log_with()/close_quest_log()/toggle_quest_log()`；`is_modal_open()`、鼠标模式、<kbd>J</kbd>/<kbd>Esc</kbd> 都收在 HUD 这一处 |
| `scripts/main/campaign.gd` | `show_tasks()`：委托所 <kbd>V</kbd> → 开面板；有待接任务时把 `_accept_first_quest` 作为底栏动作传进去 |
| `scripts/world/harbor.gd` | 非战役模式（直接开港调试）把 `QuestService.panel_handler` 接到 `hud.open_quest_log` |
| `project.godot` | 输入映射新增 `quest_log`（J，physical_keycode 74） |
| `scripts/ui/key_bindings.gd` | 底部提示条与 F1 键位说明补上 J |
| `tools/validate_quest_panel.gd` | 71 项 headless 校验（数据层 4 种存档状态 + 面板层开合/内容/模态/键位 + 机位输入拦截 + 动作按钮 + 委托所入口 + 无战役控制器场景 + 商店不叠面板 + 目标栏 J 提示） |
| `tools/capture_quest.gd` | 三个档位的实拍出图（写 `docs/ui/`，用独立 save_path，不碰正式存档） |

## 三、状态口径

| 状态 | 方块 | 颜色 | 判定 |
|---|---|---|---|
| 已完成 `done` | ■ | 绿 | 地区已走过（`stage > i` 或本轮已结算回港），或该任务目标全打勾 |
| 待交接 `pending` | ◆ | 金 | 就是当前地区且 `campaign.cleared`——已清场，还差离场 / 结算 |
| 进行中 `active` | ▶ | 蓝 | 当前地区（未清场），或序章正在走的那一步 |
| 未解锁 `locked` | □ | 灰 | 还没到（`stage < i`），或任务还没接取（序章档位 < 3，整条主线压成未解锁） |

序章档位由 `campaign.flow` 推出：`ship(0) → training(1) → equipped(2) → quested(3) → trial/空(4)`；
主线的每个地区目标直接读存档标志：`kills`（`"{地区}_{序号}"`，巨虎是 `"tiger"`）、`bag`（引荐信 / 斩龙闪 / 项坠 / 虎齿 / 虎爪）、
`equipment`（是否装上斩龙闪）、`opened_chests`、`colpo_outer_cleared`、`settled`。

四章：

1. **序章 · 乐园契约**：码头对话 / 演武场教学 / 委托所接取。木桩与剃的过程计数不落档，教学一完成三项一起打勾，不假装有分步进度。
2. **主线 · 第一轮试炼**：`Data.STAGES` 1.2~1.6 五条，奖励按 `loot` 与 `source` 生成。
3. **支线 · 港务委托**：左大臣的藏品（虎齿，交付后续版本开放）、沿途补给箱（6 口场景宝箱，读 `opened_chests`）。
4. **轮回记录**：`campaign.report` 非空时出现「阶段试炼结算」条，报告按行展示（原 <kbd>Esc</kbd> 菜单里的阶段记录内容都在这里）。

## 四、交互与冻结

- 列表行可点选、可用 <kbd>↑</kbd><kbd>↓</kbd> 走焦点；默认选中**当前主线**（没有主线在走才退到任一进行中任务，都没有则落到最后一条结算记录）。
- 重开面板保留上次选中的任务；该任务不存在了才回落到默认项。
- 打开即模态：`hud.is_modal_open()` 认它 → 战役控制器 `sync_pause()` 一并冻结玩家、敌人与炸弹；
  主城这类没有战役控制器的场景由面板自己冻结玩家（否则 <kbd>Space</kbd> 剃、左键斩击还会被吃掉）。
- 鼠标：面板打开时交还系统光标（HUD 的剑刃光标只在战斗中显示）。
- **面板打开时机位不吃输入**：滚轮不再推拉镜头、中键不再转视角（`camera_orbit_controls.gd` 的 `handle_input`
  在有模态面板时直接放行不吃事件，灰潮港 / 丛林 / 练习场三套机位共用这一处）。滚轮因此会穿到面板自己的
  滚动区，能滚任务列表与任务详情；`dragging` 也会跟着中键的真实状态走，免得面板期间松开中键、
  关掉面板后鼠标一动镜头就跑。
- 轮回商店开着时 <kbd>J</kbd> 不生效：商店有自己的 Esc/V 关法与玩家冻结，两个模态不叠在一起抢鼠标。
- 详情长过一屏时可滚动，滚动条换成银灰轨道 + 幽蓝滑块——默认滚动条在深色面板上几乎看不见，会让人以为内容被截断。
- 底栏动作按钮：只有开门方给了动作才出现（文本为空 = 纯只读）。按下先收起面板再执行动作，
  这样接取提示（`GameState.push_message`）能露出来，也不会把面板留在已经过期的状态上。

## 五、验收

```bash
godot --headless --path . --script res://tools/validate_quest_panel.gd        # 71 项断言
godot --headless --path . --script res://tools/validate_camera_orbit.gd       # 回归：四张图的机位（含模态拦截）
godot --path . --script res://tools/capture_quest.gd                          # 出图到 docs/ui/
godot --headless --path . --script res://tools/validate_onboarding_flow.gd    # 回归：序章流程（含委托所接取）
godot --headless --path . --script res://tools/validate_core_loop.gd          # 回归：全流程（含委托所读任务进度）
```

> `tools/check_harbor_hub.gd`（直接开港口调试路径）在当前工作区里另有一组**既有失败**：ForgeService 的
> 触发圈查不到传送过去的玩家，以及 `DeparturePortal 实际传送成功` 与退出时崩溃。ForgeService 与本次改动无关
> （一行未动却同样失败），委托所那条断言也只是同一个原因（visitor 为空 → V 根本没进服务点）的连带结果；
> 战役模式（真实游玩路径）的委托所已单独验证可用。

机位输入这条规则同时收在 `tools/validate_camera_orbit.gd`（灰潮港 / 丛林外围 / 丛林空地 / 练习场四张图各 3 项）
与 `tools/validate_quest_panel.gd`（面板开着 vs 关掉后的滚轮与中键对比）。

## 六、已知边界

- 面板内容只读：不做交付 / 追踪 / 地图指引；底栏只可能有开门方给的那一个动作（目前只有委托所的接取）。
- 序章的教学进度只有 `training_done` 一个落档标志，木桩 / 剃的分步计数是运行时的，所以那三条目标同进同退。
- 目标里的「取得 X」按背包与穿戴判定，玩家把道具卖掉会重新变成未完成——这是展示口径，不影响任何流程判定。
