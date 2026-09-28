# 即时战斗内容总表

更新：2026-09-24  
本文件汇总项目当前战斗规则、数值、运行入口、场景、素材与验证工具，是战斗内容的唯一索引。

## 1. 核心循环

```text
探索与接敌 → 观察敌人前摇和地面预警 → 走位 / 闪避 / 攻击
→ 眩晕与处决或普通击杀 → 掉落 / 波次推进 → Boss 实时阶段战 → 关卡结算
```

战斗始终运行在当前探索场景中。敌人 AI、玩家移动与输入、攻击判定、伤害、Boss 阶段和战利品持续实时结算。

## 2. 玩家操作和技能

按键以 `project.godot` 的 InputMap 为准；可改键的当前显示名由 `scripts/ui/key_bindings.gd` 读取。

| 操作 | 当前规则 / 数值 |
|---|---|
| 移动 | WASD 八方向；基础速度 `2.6 + (敏捷−5)×0.026` |
| 斩击 | 左键朝鼠标地面落点出手；竖斩与横斩交替播放；竖斩有效帧 0.12 秒、横斩 0.24 秒；间隔 0.6 秒、倍率 1.3、扇形半角 1.0；输入缓冲 0.15 秒 |
| 六式·剃 | 空格；速度 18，耗体力 30；蓄力无敌 0.15 秒，总时长 0.55 秒，冷却 2.2 秒 |
| 直踹 | E；前向射程 2.8、弧半角 0.35；有效帧 0.16 秒、冷却 0.9 秒、倍率 1.0、耗体力 25、眩晕 +25 |
| 燧发枪 | 右键；需装备副手燧发枪。6 发，射击间隔 1.8 秒，前方 22 米内取最近目标，命中锥 `dot > 0.92`，伤害按武器区间 2~13 roll |
| 猎魔 | Q；开关式，持续耗 MP 4 / 秒；命中能量型目标时附加目标最大生命 2% 的真实伤害，MP ≤ 1% 时自动关闭 |
| 傲歌 | K；护盾耗 MP 14，持续 5 秒、冷却 8 秒，容量 `min(100, 25 + 智力×2)` |
| 环断 | F；原地范围攻击，耗 MP 24、冷却 4.5 秒、前摇 0.18 秒、恢复 0.45 秒，半径 4.2、倍率 1.2 |
| 刀芒 | R；朝鼠标方向发射剑气，耗 MP 12、冷却 2.5 秒，伤害倍率 0.9 |
| 炼金炸弹 | 1；投掷并布防后引爆。固定伤害 90、半径 4.5、布防 0.25 秒、引信 0.35 秒，只伤害敌人 |
| 药剂 | 2；练习模式回复 45 HP；战役读条 1.2 秒，完成后按本次出击使用次数分摊最大 HP 的 40%，受击打断且不返还 |

`player.gd` 中刀芒（R）使用剑气参数：MP 12、冷却 2.5 秒、速度 18、射程 9、半宽 0.9、倍率 0.9。影刺要求 1.25 秒内的普攻标记，距离 ≤4、耗 MP 18、冷却 3 秒、倍率 0.8，并对能量目标附加 16 点真实伤害；影刺目前没有玩家输入入口。

玩家动作帧表现已接入 8 个用户朝向：普攻交替使用原竖斩和新增横斩，环断与刀芒分别播放独立动作。三种新增动作的首尾帧锁定为该朝向原图，并统一到 224×192 帧格与 y=176 脚底线。

## 3. 玩家资源与伤害

- 最大 HP：`50 + 体力×10`；最大 MP：`智力×10`；最大体力：`60 + 体力×12`。
- 体力每秒恢复 20；剃耗 30，直踹耗 25。MP 每次有效命中回复最大 MP 的 1%，并每秒被动回复 0.2%。
- 战役武器伤害由武器区间、力量倍率、刀术训练和技能倍率结算；练习模式保留基础攻击公式。装备耐久、护盾、药剂与炸弹库存由 `GameState` / 战役流程管理。
- 单次攻击按逻辑有效帧判定，同一目标不重复结算；真实伤害跳过物理减免。小怪满眩晕后停止移动，可由直踹处决；Boss 满眩晕后硬直 2 秒，眩晕清空后继续实时行动。

## 4. 普通敌人与 Boss

普通敌人的实时 AI 为接近 / 巡逻 → 举招前摇和红圈预警 → 攻击 → 后摇恢复。玩家可以通过移动、剃、攻击和技能应对。

| 敌人 | HP | 移速 | 伤害 | 射程 | 前摇 | 能量 |
|---|---:|---:|---:|---:|---:|---|
| 野狼 | 34 | 1.70 | 10 | 2.3 | 0.50 秒 | 有 |
| 野猪 | 72 | 1.25 | 16 | 2.4 | 0.75 秒 | 有 |
| 肉体傀儡 | 58 | 0.95 | 18 | 2.4 | 0.85 秒 | 无 |
| 练功木桩 | 9999 | 0 | 0 | 0 | — | 无；不计入存活敌人 |
| 自定义 / 人形敌人 | 关卡配置 | 关卡配置 | 关卡配置 | 默认 2.5；远程 9 | 默认 0.65；远程 0.95 | 按配置 |

山之主为能量型巨虎 Boss，800 HP，三阶段阈值 65% / 25%。招式均有红圈预警：

| 招式 | 前摇 | 伤害 | 预警半径 | 后摇 |
|---|---:|---:|---:|---:|
| 爪击 | 0.55 秒 | 22 | 4.6 | 0.85 秒 |
| 踏击 | 0.80 秒 | 26 | 7.0 | 1.00 秒 |
| 扑击 | 0.65 秒 | 30 | 3.4 | 1.00 秒 |
| 诈死反扑 | 0.12 秒 | 45 | 5.5 | 1.10 秒 |

P2 缩短前摇、加快出招并加入二连扑击；P3 装死后进行近距离反扑。击杀、任务、耐久、装备掉落和阶段 HUD 由关卡 / 战役脚本处理。

## 5. 运行入口和项目文件

| 文件 / 目录 | 职责 |
|---|---|
| `player.gd`、`player.tscn` | 玩家即时输入、移动、攻击、技能、物品、伤害与死亡 |
| `scripts/player/player_visual.gd`、`scripts/player/dash_fx.gd` | 角色动作、受击、闪避和位移表现 |
| `data/combat_skills.gd`、`data/attributes.gd`、`data/equip_tables.gd` | 技能数值、属性公式、武器和耐久数据 |
| `scripts/combat/enemy.gd`、`enemy.tscn` | 普通敌人 AI、眩晕、处决与伤害 |
| `scripts/combat/boss_colpo.gd`、`boss_colpo.tscn` | 山之主实时 AI、硬直、预警攻击和阶段 |
| `scripts/combat/stun_gauge.gd`、`sword_wave.gd`、`alchemy_bomb.gd` | 眩晕条、技能弹体和投掷物 |
| `scripts/combat/equipment_drop.gd`、`coin.gd` | 装备 / 金币掉落与拾取 |
| `scripts/world/wave_spawner.gd`、`boss_director.gd`、`colpo_level.gd` | 敌人波次、Boss 房流程、相机与地图 |
| `scripts/main/campaign.gd`、`autoload/game_state.gd` | 战役遭遇、资源、任务、战利品和结算 |
| `scripts/ui/hud.gd`、`key_bindings.gd`、`settings_panel.gd` | 战斗 HUD、提示、改键和设置 |

主要场景为 `scenes/main/main.tscn`、`scenes/world/colpo_forest_outer.tscn` 和 `scenes/world/colpo_forest_clearing.tscn`。角色帧资源在 `assets/characters/black_swordsman/`、`assets/characters/black_swordsman_new/` 与 `assets/characters/player_frames_video.tres`；生成源和 QA 资源集中于 `art/meowa/`。

## 6. 即时战斗验证工具

- 手感与角色：`tools/validate_realtime_feel.gd`、`validate_combo_skills.gd`、`validate_combat_skills.gd`、`validate_player_anim.gd`、`validate_player_visual.gd`。
- 敌人与关卡：`tools/validate_colpo.gd`、`validate_demo.gd`、`validate_world_drops.gd`。
- 视觉检查：`tools/render_attack_offscreen.gd`、`tools/compare_attack_runtime.gd`、`tools/build_colpo.gd`。
