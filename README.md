# 轮回乐园 · HD-2D

Godot 4.7 的 HD-2D 动作 RPG（2D 精灵 + 3D 场景），题材取自《轮回乐园》。
战斗是**双形态**：平时即时动作（攻击 / 剃 / 直踢 / 拼刀），打满敌人眩晕后补一刀，
切进**回合制**（AT 顺序 + 五条指令：攻击 / 战技 / 防御 / 道具 / 逃跑）。

## 环境

- Godot **4.7.x**（开发机为 Steam 版 `4.7.2`）。
  本机可执行文件：`E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
  （不在 PATH 里，所以下面的命令行示例都用完整路径或 `$GODOT_BIN`。）
- 无需额外依赖；`.godot/` 与 `.tools/` 不入库，首次打开由编辑器生成。

## 跑游戏

编辑器里打开 `project.godot` 然后 F5，或命令行：

```bash
GODOT="E:/SteamLibrary/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
"$GODOT" --path .                      # 直接进主菜单
"$GODOT" --path . res://scenes/world/harbor.tscn   # 单开某个场景调试
```

入口流程：**主菜单 → 开场（取名 / 船上）→ 灰潮港引导 → 各关**。
`scenes/main/level_select.tscn`（选关面板）现在只是**调试用的跳关清单**，
不再是启动场景 —— 启动场景见 `project.godot` 的 `application/run/main_scene`（主菜单）。

操作：`WASD` 移动 · 左键朝鼠标斩击 · `Space` 剃 · `K` 直踢 · `1` 炸弹 · `2` 药剂 ·
`V` 交互（宝箱 / 港口服务点）· `F1` 按键说明 · `Esc` 菜单。
传送门是**走进圈子即传送**，不需要按键。

## 回归流程

```bash
tools/run_regressions.sh              # 跑默认套件，逐条报 PASS/FAIL/耗时
tools/run_regressions.sh --list       # 只列套件内容
tools/run_regressions.sh validate_battle validate_demo   # 只跑指定几支
GODOT_BIN=/path/to/godot tools/run_regressions.sh        # 指定 Godot
RG_TIMEOUT=600 tools/run_regressions.sh                  # 改单支超时（默认 420s）
```

单支脚本也可以直接跑：

```bash
"$GODOT" --headless --path . --script res://tools/validate_battle.gd
```

日志落在 `.tmp_preview/regressions/`（已 gitignore），失败时脚本会打印各失败日志的尾部。
退出码：`0` 全过 / `1` 有失败 / `2` 找不到 Godot。

### 写校验脚本的三条约定

1. **先隔离存档，再碰任何全局状态** —— 用 `tools/test_env.gd`：

   ```gdscript
   const TestEnv := preload("res://tools/test_env.gd")
   func run() -> void:
       var gs: Node = root.get_node("GameState")
       TestEnv.isolate(gs, "battle")   # 独立存档 + 固定六维（Campaign.BASE_STATS）
       ...
       TestEnv.cleanup(gs)             # 退出前删掉隔离档（含 .bak/.tmp）
   ```

   两件事缺一不可：只换 `save_path` 只挡住**写**，内存里的 `attributes`/`coins`
   仍是 `_ready()` 时从真实存档读进来的 —— 派生上限（`max_hp=50+体力×10`、
   `max_mp=智力×10`、`max_stamina=60+体力×12`）会随本机进度漂移，断言就成了
   「装了这台机器的存档才过」。`isolate()` 走 `reset_progress()` 把六维钉死，
   于是固定为 `max_hp=100 / max_mp=60 / max_stamina=120`。
   需要真写盘的校验（`validate_save_transaction` 验原子替换与 `.bak` 回退）
   传 `TestEnv.isolate(gs, "tag", true)`。

2. **`--script` 模式的坑**：自动加载在脚本解析时还没注册，所以
   - 不要 `preload()` 那些**脚本里引用 autoload 的场景**（如 `boss_colpo.tscn`），
     要在 `run()` 里 `load()`；
   - 要读 autoload 的值就运行时按路径取（`root.get_node("GameState")`），
     别在脚本体里直接写 `GameState.xxx`。
   - 无头模式下 `SceneTree` 脚本内的**运行时脚本错误不会打印也不退出，只挂住**，
     所以建议重定向到文件再看。

3. **断言写派生公式，别写字面量**。例如体力上限断
   `player.max_stamina == Attributes.max_stamina(attrs)`，而不是 `== 120`：
   后者等于假设体力恰好是 5，换套属性/装备就假失败（历史上真踩过）。

### 套件里只放全绿的

一盏常年亮着的红灯会训练人忽略失败。当前**已知红、未进套件**的两支
（都不是新引入的，待单独处理）：

| 脚本 | 症状 |
| --- | --- |
| `tools/validate_player_anim.gd` | 8 个 `attack_*` 动画帧率断言失败：期望 15，实测 12 |
| `tools/check_harbor_hub.gd` | 8 项陈旧断言（锻造/任务服务点提示与 V 交互、`DeparturePortal` 传送），并在过场后段错误（signal 11） |

## 待决

- **`assets/characters/black_swordsman_new/` 这套图集要不要留？**
  它是 meowa 图集时代的产物，当前玩家用的是
  `assets/characters/player_frames_video.tres`（`player.tscn` 的 `sprite_frames` 指向它，
  由 `tools/build_video_player_frames.gd` 生成，回归覆盖在 `tools/validate_player_anim.gd`）。
  `player_frames_new.tres` 与整个 `black_swordsman_new/` 目录**全仓库没有第二处引用**
  （只剩生成它的 `tools/build_new_player_frames.gd` 与被它校验的 `validate_new_player_frames.gd`）。
  实测 64 个动画 / 744 帧里有 **39 帧「内容贴到格边（可能被裁）」**，全在 `attack_*`
  —— 图集切格把刀光弧裁掉了。不影响游戏（没人读它），但复检会一直报红。
  `tools/validate_new_player_frames.gd` 已改成**默认跳过**（加 `-- --force` 才真跑）。
  待拍板：**修那 39 处裁切**，还是**连同目录与 `build_new_player_frames.gd` 一起删掉**。
  注意 `.gitignore` 的注释把该目录描述为「已入库的派生图集」，即当初是**有意保留**的，
  所以删之前先确认这个意图是否还有效。

- **项目级 CI**：仓库在 GitHub（`origin`），但目前没有 CI。要加需先定两件事：
  runner 怎么拿到 Godot（固定版本下载 vs 缓存），以及要不要在 CI 里拉 LFS 素材
  （仓库含大量图片）。
- **导出预设**：没有 `export_presets.cfg`。导出目标平台还没定，定了再补。

## 目录

| 路径 | 内容 |
| --- | --- |
| `autoload/game_state.gd` | 全局状态 + 存档（两层：已提交层 / 本局临时层，见下） |
| `player.gd` · `player.tscn` | 玩家本体（在仓库根，不在 `scripts/player/`） |
| `scripts/main/` | 主菜单、开场、港口战役流程、选关、练习场、教学战斗场 |
| `scripts/combat/` | 敌人、Boss、技能弹道、掉落 |
| `scripts/battle/` | 回合制：状态机、作战单位、指令面板、AT 条、眩晕条 |
| `scripts/ui/` · `scripts/world/` | HUD / 面板 / 按键说明；相机、传送门、宝箱、港口布景 |
| `data/` | 纯数据表：六维公式、技能数值、装备、战役表 |
| `tools/` | 构建脚本（`build_*`）、校验脚本（`validate_*` / `check_*`）、回归流程 |
| `docs/` | 设计文档，见下 |

存档分两层：只有「已提交层」（检查点、乐园操作如开箱/换装/商店、结算提交）写进
`user://save.cfg`；一次出击里未到提交点的拾取与耐久损耗属「本局临时层」，
死亡 / 放弃 / 异常退出整体回滚。写入走「临时档 + rename 原子替换 + `.bak` 回退」。

## 文档

**先看 [`docs/DOCS_INDEX.md`](docs/DOCS_INDEX.md)** —— 它按类型和时间列出全部文档，
并标注每份的落地状态（已落地 / 部分 / 未开工 / 冻结）与冲突时的效力顺序。
改代码前再按下面找到对应的那份：

- `docs/GDD.md` · `docs/PROJECT_OVERVIEW.md` — 玩法总览 / 代码结构索引
- `docs/COMBAT_DESIGN.md` · `COMBAT_SYSTEM.md` · `TURNBASED_COMBAT_PLAN.md` · `COMBAT_REWORK_PLAN.md`
  — 战斗四份，各有分工，改战斗前先确认该看哪份
- `docs/EQUIPMENT_SYSTEM.md` · `docs/QUEST_PANEL.md` · `docs/HARBOR_MAP.md` — 子系统
- `docs/DEMO_STATUS.md` · `docs/P1_SCOPE_BASELINE.md` — 当前范围与状态
- `docs/PROJECT_STATUS_AUDIT.md` — 进度与缺口权威（哪些做了、哪些没做）
