# HD2D《轮回乐园》· 项目总览

> 整理日期：**2026-09-22**（上一版 09-19）
> 性质：**结构与索引文档**。回答「工程里有什么、放在哪、怎么串起来」。
> **文档本身的清单看 [DOCS_INDEX.md](DOCS_INDEX.md)**（按类型 + 时间分类，含每份的落地状态与效力）。
> 进度与缺口以 [PROJECT_STATUS_AUDIT.md](PROJECT_STATUS_AUDIT.md) 为准；玩法规则以 [GDD.md](GDD.md) 与 [P1_SCOPE_BASELINE.md](P1_SCOPE_BASELINE.md) 为准；战斗规则和代码入口见 [REALTIME_COMBAT_EXTRACTION.md](REALTIME_COMBAT_EXTRACTION.md)。
>
> **本轮（09-20~09-22）增量**：任务档案面板（<kbd>J</kbd>）、面板设计语言 `system_ui.gd`、开场第二幕坐船过场、前景遮挡淡出、港口扩写（南岸码头 / 围墙 / 商街 / 工坊 / 委托所 / 科尔波山远景）、4 个新 shader、`levels/` 试验场景；§14 未提交快照同步重写。

---

## 1. 定位

PC 单人、俯视 **HD2D**、近战技法主导的世界任务制动作 RPG。题材为《轮回乐园》，主角苏晓（黑衣剑士）。

- 引擎：Godot **4.7.2.stable**（Steam 版；`config/features = 4.7 / Forward Plus`），3D 物理用 **Jolt**，Windows 渲染驱动 **D3D12**。
- 分辨率：1920×1080，拉伸 `canvas_items`，默认纹理过滤 Nearest（像素角色）。
- 技术形态：**3D 场景与碰撞 + 2D 像素角色 Sprite3D**，真实遮挡（含前景淡出），固定斜俯视镜头 + 可轨道转视角。
- 主场景：`scenes/main/main_menu.tscn`。
- 当前可玩范围：**契约开场 → 船上过场 → 五阶段试炼（1.2~1.6）→ 巨虎 Boss → 阶段结算 → 灰潮港主城 → 再次出发**。原著国王主线未完成。
- **战斗现状**：战役关卡、普通敌人与 Boss 共用即时战斗；技能、眩晕、处决与 Boss 硬直见 [REALTIME_COMBAT_EXTRACTION.md](REALTIME_COMBAT_EXTRACTION.md)。

---

## 2. 快速上手

| 目的 | 做法 |
|---|---|
| 正常游玩 | Godot 打开工程，F5（走主菜单） |
| 直接进战斗试炼 | 运行 `scenes/main/main.tscn`（F6） |
| 关卡调试 | 主菜单 →「关卡调试 · 选关」→ `scenes/main/level_select.tscn` |
| 跑验收脚本 | `godot --headless --path E:/godotproject/hd-2d --script tools/validate_xxx.gd` |
| 重新生成预览图 | 去掉 `--headless` 并追加 `-- --capture`（见 `docs/DEMO_STATUS.md`） |

Godot 可执行文件本机路径：`E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`（Steam 版，不在 PATH 上）。

**默认按键**（权威定义在 `scripts/ui/key_bindings.gd`，输入映射在 `project.godot`）：

```
WASD 移动（方向按当前机位算，W 永远朝画面深处走） · 左键 单段斩击（朝鼠标方向） · 右键 副手燧发枪
Q 猎魔 · K 傲歌护盾 · F 环断 · Space 剃（闪避，耗体力 30）· E 直踹（耗体力 25）
1 炼金炸弹 · 2 药剂 · V 交互 · C 角色面板 · J 任务面板 · F1 键位说明 · Esc 菜单
Tab 使徒之眼（后置）· 吞噬之核（后置；原中键已改作镜头控制，键位待重新指定）
中键拖动 转镜头朝向 / 调机位高度 · 滚轮 推拉镜头远近
```

> 注：直踢（`kick`）**已进** `key_bindings.gd` 的 `HINT_ITEMS` / `GROUPS`，底部提示条与 F1 面板都看得到它。
> **2026-09-23 默认键对调**：直踢由 `K` 改为 **`E`**，原 `E` 的傲歌（`aoge`）改为 `K` —— 正本仍是 `project.godot` 的 `[input]`，本文键位行已同步。
| `scripts/player/player_visual.gd` | 按方向选择 / 镜像帧、攻击、受击和闪避表现 |

---

## 3. 顶层目录

```
hd-2d/
├── project.godot              工程配置：自动加载 / 输入映射（19 动作）/ 渲染 / 编辑器插件
├── .mcp.json                  Godot MCP 服务注册（编辑器接管）
├── icon.svg
├── player.gd / player.tscn     玩家根脚本与场景
├── autoload/
│   └── game_state.gd          唯一自动加载：存档 + 全局状态 + 经济 + 过场
├── data/                      静态数值与查表（纯数据，无场景依赖）
│   ├── attributes.gd          六维属性与派生公式
│   ├── campaign.gd            阶段 / 物品 / 宝箱 / 悬赏 / 掉落池
│   ├── combat_skills.gd       战斗技能与连击唯一数值入口（含直踢 KICK_*）
│   ├── equip_tables.gd        品质 / 强化 / 耐久 / 出售分解查表
│   └── quest_log.gd           任务档案四章任务表（J 面板数据源，纯函数，09-22 新增）
├── scenes/                    场景（.tscn，共 11 个）
│   ├── main/                  主菜单 / 开场 / 坐船段 / 战役宿主 / 试炼场 / 选关
│   ├── world/                 港口 / 科尔波山外围 / 决战空地
│   ├── workshop/              丛林调色台
│   └── actors/  world_3d/     空目录（预留）
├── scripts/                   逻辑脚本（.gd，共 32 个）
│   ├── main/                  流程编排与菜单（含 cinematic.gd / opening_boat.gd）
│   ├── combat/                敌人 / Boss / 眩晕条 / 刀气 / 炸弹 / 掉落实体
│   ├── world/                 镜头（轨道 + 遮挡淡出）/ 传送门 / 宝箱 / 波次 / Boss 导演 / 主城服务
│   ├── ui/                    HUD（最大文件）/ panel 设计语言 / 商店 / 任务 / 键位表
│   ├── player/                角色表现与剃特效
│   └── characters/  shaders/  autoload/   空目录（预留）
├── shaders/                   港口调色·铺装·水面·围墙 + 试炼地面 + 船天空 + 过场叠加 + 遮挡淡出 ×2
├── assets/                    已接入工程的资源（588 文件）
│   ├── characters/black_swordsman/        角色帧图集（旧版）+ combo / combo_norm
│   ├── characters/black_swordsman_new/    新版动作集（视频重制，未提交）
│   ├── characters/black_swordsman_video/  视频抽帧中间产物（未提交）
│   ├── environments/jungle/               丛林 3D 道具库与地面 shader
│   ├── audio/dash/                        剃三段音效
│   └── textures_3d/  fonts/  sprites/  ui/
├── art/                       原始生成素材（Meowa，未全部接入）
│   └── meowa/                         角色 / 光标 / 守势等 403 文件
├── tools/                     构建 / 验证 / 美术处理脚本（77 gd + 34 py，不参与游戏运行）
├── docs/                      策划、审计、验收与本文档
├── levels/                    FreeWalk 自由漫步试验场景（未接入主流程，未提交）
├── background/                原著《轮回乐园》1~4172 章文本（考据素材，不入库）
└── addons/                    编辑器插件：godot_mcp / hd2d_scene_tools
```

---

## 4. 场景与流程

```
main_menu.tscn ──开始新游戏──▶ opening.tscn（2D 剧情 + 登记姓名）
      │                              │ 取名完成
      └──继续游戏───────────────────▶│
                                     ▼
                        opening_boat.tscn（第二幕 3D 坐船过场：船上醒来 → 靠灰潮港；
                        镜头 cinematic.gd + 全屏片场特效 cinematic_overlay.gdshader）
                                     ▼
                            campaign.tscn  ← 唯一编排宿主
                            （scripts/main/campaign.gd）
                                     │
        ┌────────────┬───────────────┼────────────────┬──────────────┐
        ▼            ▼               ▼                ▼              ▼
   main.tscn    main.tscn      colpo_forest_   colpo_forest_    harbor.tscn
   (练习/试炼)  (1.2~1.5)       outer.tscn      clearing.tscn    (灰潮港主城)
                              科尔波山外围      林间决战空地      商店/工坊/
                             三波+传送门       15s准备+巨虎Boss   委托/演武场
                                                                  │
                                     ◀── settle_trial / 返回门 ────┘
                                     │
                              begin_next_trial → 回到 campaign 重开一轮
```

- `campaign.tscn` 本身只是一个空宿主，真正的关卡由 `campaign.gd::_build_world()` 按 `GameState.campaign.stage` 与 `location`（`arena` / `outer` / `clearing` / `hub` / `practice`）动态 `load().instantiate()` 装载。
- `scripts/main/opening.gd` → `opening_boat.gd`：开场两幕；取名后 `change_scene(OPENING_BOAT_SCENE)`，坐船段结束再 `change_scene(GameState.Campaign.SCENE)` 进战役。
- `scripts/world/scene_portal.gd`：进圈即传送，门控由 `campaign_can_enter` 回调接管；未清场只显示锁定提示。
- `scripts/world/wave_spawner.gd`：读场景里 `colpo_spawn` 分组标记（带 `wave` / `kind` 元数据），一波清完再放下一波。
- `scripts/world/boss_director.gd`：林间空地节奏（剧情 → 15 秒准备发 3 颗炸弹 → 巨虎登场 → 三阶段 → 结算），Boss 本体在 `scripts/combat/boss_colpo.gd`。
- `scripts/main/main.gd`（`practice`）：自由练习场，包含练功木桩和使用实时 AI 的训练敌人。

---

## 5. 代码分层

### 5.1 全局状态 `autoload/game_state.gd`

唯一的自动加载节点（另一个自动加载 `MCPGameBridge` 来自 MCP 插件，不是游戏逻辑）。

| 职责 | 关键 API |
|---|---|
| 存档 | `save_game()` / `load_game()`，单槽 `user://save.cfg`（ConfigFile），`persistence_enabled` 供验证脚本关写盘 |
| 进度 | `player_name` / `coins` / `attributes` / `attr_points` / `campaign` 字典 |
| 属性 | `get_attribute` / `effective_attributes()`（裸装 + 装备词条聚合）/ `spend_attr_point` |
| 装备 | `equip_item` / `unequip_item` / `enhance_item` / `repair_item` / `sell_item` / `decompose_item` / `devour_item` |
| 耐久 | `damage_item_dura` / `is_item_broken` / `armor_reduction` / `repair_all_equipment` |
| 掉落 | `open_chest` / `open_scene_chest` / `roll_equipment_drop` |
| 流程 | `record_hunt` / `clear_region` / `can_advance_region` / `advance_region` / `settle_trial` / `begin_next_trial` |
| 过场 | `change_scene(path)`：淡出 → 切场景 → 淡入，遮挡层挂在自动加载节点上避免黑屏残影 |
| 信号 | `message` / `coins_changed` / `attributes_changed` |

### 5.2 数据层 `data/`

| 文件 | 内容 |
|---|---|
| `attributes.gd` | 六维键 `str/agi/con/int/cha/luk`；派生：`max_hp = 50 + con×10`、`max_mp = int×10`、`move_speed = 2.6 + (agi−5)×0.026`、`attack = 武器7 + str`；只有力/敏/体/智可加点 |
| `campaign.gd` | `STAGES`（1.2~1.6 名称/简介/剧情/敌人档位/战利品/源点）、`SLOTS`（11 槽）+`SLOT_CN`、`ITEMS`（全字段：品质/评分/攻击区间/词条/耐久/需求/export/growth/被动）、`CHESTS`、`HUNTS`、`RANDOM_EQUIP_POOL`、`SCENE_CHEST_ITEMS`、`fresh()` 存档模板、`dura_state`/`enhance_level`/`fury_value` 兜底读取 |
| `combat_skills.gd` | 猎魔消耗/真伤比、回蓝比例、三段连击命中帧(`0.12/0.18/0.23`)/冷却/倍率/范围、护盾、环断、刀芒、影刺全部数值 |
| `equip_tables.gd` | 5 档品质（Q 值 / 评分区间 / 配色）、`con_hit_factor` 肉体修正、`str_atk_coef` 力量倍率（上限 1.45）、`ATTACK_ADD_BY_TYPE` 强化增幅、`ENHANCE_ROWS` 成功率与失败掉级、`KSTR`、成长倍率、`SELL_R`/`DECOMP_R`、`KILL_DUR` 击杀扣耐 |
| `quest_log.gd` | 任务档案（J 键任务面板的数据源）：把 `campaign` 里的进度只读映射成「序章 / 主线 / 支线 / 记录」四章任务表，每条的 `status` 由 `flow/stage/cleared/settled/kills/bag/opened_chests` 推出；纯函数、不引用 autoload，详见 [QUEST_PANEL.md](QUEST_PANEL.md) |

> **口径提醒**：`attributes.attack()`（武器7+力量）只在非战役面板/独立试炼生效；战役伤害走 `equip_tables` 的区间链。这是已知的双轨问题，见 §13。

### 5.3 玩家 `player.gd`（根目录）+ `scripts/player/`

| 文件 | 职责 |
|---|---|
| `player.gd` | 普攻（单段斜劈）、输入缓冲、剃、右键燧发枪、Q 猎魔 / K 傲歌 / F 环断、E 直踹（眩晕与处决）、炸弹和药剂，以及伤害、护盾、耐久与体力管理 |
| `scripts/player/player_visual.gd` | 按方向选择 / 镜像帧、攻击、受击和闪避表现 |
| `scripts/player/dash_fx.gd` | 剃的残影、尘土、气流与三段音效 |

### 5.4 战斗 `scripts/combat/`

| 文件 | 职责 |
|---|---|
| `enemy.gd` | 敌人类型与实时 AI、预警攻击、能量属性、眩晕 / 处决、耐久档和练功木桩 |
| `boss_colpo.gd` | 巨虎本体与三阶段（狂暴/诈死/破腿）AI |
| `sword_wave.gd` / `alchemy_bomb.gd` / `coin.gd` | 飞行刀气（可被墙挡）/ 投掷炸弹（可预埋）/ 掉落币 |
| `equipment_drop.gd` | 世界内可拾取装备实体 |

### 5.5 世界 `scripts/world/`

| 文件 | 职责 |
|---|---|
| `harbor.gd` | 灰潮港机位（默认 16° 俯角 / 距离 48.1 / FOV 18°）、焦点收边、北偏取景；运行时可被中键/滚轮改 |
| `colpo_level.gd` | 科尔波山共用：移动前瞻、**前景树淡出**（HD-2D 防遮挡）、光柱呼吸 |
| `jungle_camera_style.gd` | 丛林/试炼统一镜头参数（俯角、距离、构图偏移、边界） |
| `camera_orbit_controls.gd` | 镜头操控：中键拖动转视角 / 调高度（俯角上限 45°）、滚轮推拉距离、景深随距离等比缩放（取代已删除的 `camera_mouse_lead.gd`）；机位＝平滑锚点＋构图偏移＋轨道偏移，转视角刚性不甩镜头 |
| `camera_occlusion_fade.gd`（648 行，09-19 新增） | 前景遮挡淡出：按镜头与角色连线判定遮挡单元并降透明度（`occlusion_fade_preset.gdshader` / `occlusion_fade_harbor_wall.gdshader`），HD-2D 防挡视线的通用件 |
| `wave_spawner.gd` | 三波调度（读标记元数据） |
| `boss_director.gd` | Boss 关节奏与 HUD 协调 |
| `scene_portal.gd` | 进圈传送 + 门控回调 |
| `scene_chest.gd` | 场景宝箱（V 开启，按 key 防重复） |
| `harbor_service.gd` | 主城服务点（靠近显示提示、V 打开面板或调 `campaign_action`） |

### 5.6 UI `scripts/ui/`

| 文件 | 职责 |
|---|---|
| `hud.gd`（40KB / 853 行，最大文件） | **HP / MP / 体力 三条**、目标、消息、底部提示、剧情条、Boss 条、按键说明面板、`show_panel`+`add_choice` 的 modal 系统、**C 角色面板**（11 槽穿戴环 + 64 格背包 + 六维与属性点 + tooltip）、**J 任务面板**（挂 `quest_panel.gd`）、商店（挂 `shop_panel.gd`）、剑刃光标 |
| `system_ui.gd`（09-21 新增） | **面板设计语言唯一数据源**：深蓝灰底 + 电光青边 + 四角铆钉的 `card()` / `style_button()` 与配色常量；商店和任务档案共用同一套外观 |
| `shop_panel.gd`（09-21 新增） | 「轮回商店」面板（CanvasLayer 模态）：陈设、价格、购买与余额显示 |
| `quest_panel.gd`（09-22 新增） | 「任务档案」面板（CanvasLayer 模态）：左任务名列表（分章 + 状态方块），右选中任务的目标 / 说明 / 奖励 / 记录；底栏进度与可选动作按钮。数据只读，来自 `data/quest_log.gd`，详见 [QUEST_PANEL.md](QUEST_PANEL.md) |
| `key_bindings.gd` | 键位唯一数据源：`HINT` 底部提示 + `GROUPS` F1 面板（READY/PLANNED/DEFERRED 状态）。直踢（`kick`）与傲歌（`aoge`）均已收录；2026-09-23 起两者默认键为 **E / K**（对调过） |
| `hud.tscn` | HUD 场景壳（位于 `scripts/ui/`，不在 `scenes/`） |

### 5.7 流程 `scripts/main/`

| 文件 | 职责 |
|---|---|
| `campaign.gd`（696 行） | 跨场景进度、加载世界、交互接线、工坊（强化/修复/分解/出售/吞噬/属性与刀术）、商店、委托面板、结算与再出发 |
| `main.gd` | 自由练习场 + 1.2~1.5 试炼场：按 `stage` 程序化布景、地面与环境差异化、传送门、练功木桩和实时训练敌人 |
| `opening_boat.gd`（607 行，09-21 新增） | 开场第二幕：3D 坐船过场（船上醒来 → 靠灰潮港），结束后进战役 |
| `cinematic.gd`（399 行，09-21 新增） | 程序化「2D 电影镜头」：黑边、推拉、字幕节拍；供 `opening.gd` 与坐船段复用 |
| `main_menu.gd` | 主菜单（继续/新游戏/选关/退出），有档才显示「继续游戏」 |
| `opening.gd` | 开场第一幕：剧情与契约者取名，取名后切 `opening_boat.tscn` |
| `level_select.gd` | 白盒选关入口 |

## 6. 数据流（关键链路）

**伤害链（战役）**
```
左键点击 → 记录鼠标地面方向到输入缓冲(0.15s)
→ attack_cd 就绪 → _start_attack(段位) → 到达命中帧
→ _hurt_in_cone(射程, 弧) → _damage_target
→ enemy.take_damage(物理, 击退, 源, 真伤)
→ 物理按 enemy.physical_reduction 减免；真伤跳过减免
→ 命中回蓝 1%；击杀则按 kill_tier 扣主/副手武器耐久
```

**玩家受击链（战役）**
```
enemy 结算命中 → player.take_damage
→ 无敌/闪避拦截 → 护甲百分比减免(armor_reduction, clamp 0~0.9)
→ 肉体修正(con_hit_factor) → 傲歌护盾吸收 → HP
→ 按实际扣血扣一件护甲耐久 → HP≤0 触发 died
```

**物品与成长**
```
击杀/宝箱 → give_item → campaign.bag
→ C 面板 equip_item（需求校验 → campaign.equipment）
→ effective_attributes() 聚合装备词条 → player._refresh_derived_stats()
→ 工坊 enhance/repair/decompose/sell/devour → GameState 原子扣款并 save_game()
```

**段落结算**
```
清场 → state="loot" → V 领奖 → record_hunt(法力上限) + clear_region(战利品 + 源点)
→ advance_region()（1.3 需引荐信、1.4 需装备斩龙闪）
→ stage==4 时 settle_trial()：评级 → 属性点 + 乐园币，清理本土(export=false)物品，hub=true
→ 港口整备 → begin_next_trial() 重开一轮
```

## 7. 存档

分两层，只有「已提交层」会写进盘：

- **已提交层**：检查点、乐园操作（开箱 / 换装 / 商店消费）与结算提交的内容。
  单槽位 `user://save.cfg`（ConfigFile，section `progress`），另有一份 `save.cfg.bak` 备份档。
- **本局临时层**（`SORTIE_KEYS = ["bag", "item_dura"]`）：一次出击里还没到提交点的易变状态
  —— 途中拾取的装备、战斗中扣掉的耐久。只留在内存里，死亡 / 放弃出击 / 异常退出整体回滚。
- 写入时机：契约登记、乐园操作、检查点提交、`NOTIFICATION_WM_CLOSE_REQUEST` 兜底。
  **任何显式 `save_game()` 都是一次提交**：它先把当前 `SORTIE_KEYS` 定为新基线再写盘，
  所以乐园操作与检查点天然就是提交点，不需要额外调提交 API。
- 写入方式：先写 `save.cfg.tmp`，成功后 `rename` 原子替换正式档；替换前把上一份**可解析**的
  正式档复制成 `.bak`。坏档（写一半被截断、或只剩段头的空壳档）一律回退 `.bak` 读取，
  不会静默清空姓名与乐园币。
- 内容：`campaign` 字典（stage/cleared/hub/run/level/source/world_mana/permanent_mana/kills/bag/equipment/opened_chests/item_dura/item_enhance/item_fury/hp_ratio/mp_ratio/bullets/settled/training/report/colpo_outer_cleared/flow/training_done）、`player_name`、`coins`、`attributes`、`attr_points`、`version`。
- 迁移：`version` 字段（当前 `SAVE_VERSION = 2`）+ 旧档缺字段用 `Campaign.fresh()` + `merge()` 兜底；**8 槽时代 `equipment.weapon` 自动迁到 11 槽 `main_weapon`**。
- 尚未实现：账户档/角色档/世界档分离、逃脱币、救援与永久死亡（现死亡 = 免费重试本地区）。
  四条结束路径（正常撤离 / 救援 / 永久死亡 / 超时）已收敛到唯一入口 `GameState.settle_sortie(outcome)`，
  但 `RESCUE` 的「本局收益只结算 30%」与 `PERMADEATH` 的角色销毁仍是空实现（待拍板）。
- 回归：`tools/validate_save_transaction.gd` 覆盖本局事务 / 提交点 / 坏档回退 / 场景内阵亡重试，
  通过时输出 `SAVE_TRANSACTION_FAILURES=0`。

---

## 8. 美术与场景资产

| 位置 | 内容 | 入库 |
|---|---|---|
| `assets/characters/player_frames_video.tres` | **当前生效的角色帧表**：`player.tscn` 的 `sprite_frames` 指向它，贴图取自 `black_swordsman_video/` | ❌ 未提交 |
| `assets/characters/black_swordsman_video/`（257 文件） | 视频抽帧重制的动作集（含 `受击_*` 八方向与 `_12` 十二帧版） | ❌ 未提交 |
| `assets/characters/black_swordsman_new/`（129 文件） | 新一版八方向动作集（attack_left / right / up / down + 四斜向） | ❌ 未提交 |
| `assets/characters/black_swordsman/`（158 文件） | 旧版帧图集：六方向 idle / walk / attack / dodge / guard / hit / death；`combo/`（未归一原图）与 `combo_norm/`（归一版）；`新版动作/`(34) 与 `最新版动作/`(16) 中间产物；`ANIMATION_SPEC.md` 帧表规格；`player_frames.tres`（**旧帧表，已不被 player.tscn 引用**） | 部分未提交 |
| `assets/environments/jungle/` | `jungle_library.tres` + `props/`（`HD2DAsset` 预置库，道具以 `.tres`+`.tscn` 成对存在）+ `forest_floor.gdshader` | ✅ |
| `assets/audio/dash/` | `dash_stomp` / `dash_whoosh` / `dash_land` 剃三段音效 | ✅ |
| `assets/ui/cursor.png` | 剑刃光标（剑尖锚点 `Vector2(8,8)`） | ✅ |
| `art/meowa/`（403 文件） | Meowa 生成的原始素材仓库，含 qa 图、gif、`final_outputs.json`、多方向多视图；**未全部接入工程** | ❌ 未提交 |
| `docs/**/*.png`（`ui/` `opening/` `opening_boat/` `camera_*` `jungle_*`） | 各阶段实机截图存档：港口 / 丛林 / 菜单 / 关灯前后 / 任务面板 / 开场分镜等 | 按仓库约定不入库，用 `tools/capture_*.gd` 随打出图 |

> ⚠️ **帧表依赖链是未提交的**：`player.tscn`（已跟踪、已修改）→ `player_frames_video.tres`（未跟踪）→ `black_swordsman_video/*.png`（未跟踪）。只提交已跟踪文件、或清理未跟踪文件，会让角色动画直接失效。

**预置系统**：`tools/preset_catalog.gd` 提供 `asset(title)`，`HD2DProp` 按 `HD2DAsset` 摆放；关卡布景全部走它，纯装饰可 `asset_overrides = {"static_collision": false}`。

---

## 9. Shader

| 文件 | 用途 | 引用方 |
|---|---|---|
| `shaders/harbor_grade.gdshader` | 港口整体调色（黄昏暖灯 / 冷色阴影） | harbor.tscn |
| `shaders/harbor_paving.gdshader` | 石板街铺装 | harbor.tscn |
| `shaders/harbor_water.gdshader` | 水面 | harbor.tscn |
| `shaders/harbor_wall.gdshader`（09-19 新增） | 港口围墙材质 | harbor.tscn、`_probe_save_test.tscn` |
| `shaders/trial_floor.gdshader` | 试炼/关卡地面（砖色、砖块尺寸、砖缝参数化，按 stage 换） | main.tscn |
| `shaders/boat_sky.gdshader`（09-21 新增） | 开场坐船段的天空 | `scripts/main/opening_boat.gd` |
| `shaders/cinematic_overlay.gdshader`（09-21 新增） | 全屏「片场」叠加（黑边 / 颗粒等过场特效） | `scripts/main/opening.gd` |
| `shaders/occlusion_fade_preset.gdshader`（09-19 新增） | 前景遮挡淡出：预置素材通用版 | `scripts/world/camera_occlusion_fade.gd` |
| `shaders/occlusion_fade_harbor_wall.gdshader`（09-19 新增） | 前景遮挡淡出：港口围墙专用版 | `scripts/world/camera_occlusion_fade.gd` |
| `assets/environments/jungle/forest_floor.gdshader` | 丛林地面 | colpo 场景 |

> 旧文档提到的 `harbor_glints` 相关资源已不存在（`grep` 无引用）。`addons/hd2d_scene_tools/` 自带一份 `shaders/` 目录，属于插件而非游戏着色器。

---

## 10. 工具链 `tools/`

> `tools/` 共 **77 个 `.gd` + 34 个 `.py`**，全部只在编辑器/命令行跑，不参与游戏运行。

**场景生成（重跑会覆盖场景，动手前先备份）**
`build_harbor.gd`、`build_colpo.gd`

**港口分区装配**
`harbor_zones.gd`、`harbor_port_layout.gd`、`harbor_pier.gd`、`harbor_walls.gd`、`harbor_gate.gd`、`harbor_shop.gd`、`harbor_forge.gd`、`harbor_quest.gd`、`harbor_dressing.gd`、`harbor_mountain.gd`、`harbor_lighting.gd`

**港口增量应用（只改一块，不重跑全量生成）**
`apply_harbor_clear.gd`、`apply_harbor_walls.gd`、`apply_harbor_shop.gd`、`apply_harbor_south_port.gd`、`apply_harbor_mountain.gd`、`apply_harbor_dressing.gd`、`apply_harbor_hub_districts.gd`

**预置库与角色**
`preset_catalog.gd`、`import_presets.gd`、`apply_face_player.gd`、`apply_guard_frames.gd`、`apply_jungle_camera.gd`、`build_new_player_frames.gd`、`build_video_player_frames.gd`

**验证（19 个）**

`2026-09-22 实跑结果` —— 以下 8 个脚本在本机（Godot 4.7.2 + `--headless`）逐个跑过且全部通过：

| 脚本 | 通过标志 |
|---|---|
| `validate_combo_skills.gd` | `COMBO_SKILLS_FAILURES=0` |
| `validate_combat_skills.gd` | `COMBAT_SKILLS_FAILURES=0` |
| `validate_core_loop.gd` | `CORE_LOOP_FAILURES=0` |
| `validate_onboarding_flow.gd` | `ONBOARDING_FLOW_FAILURES=0` |
| `validate_player_visual.gd` | `PLAYER_VISUAL_CHECKS: PASS` |
| `validate_camera_orbit.gd` | `CAMERA_ORBIT: PASS (285 checks)` |
| `validate_quest_panel.gd` | `任务面板校验：全部 PASS` |

未在本次跑过（沿用 `*_FAILURES=0` 约定）：`validate_demo.gd`、`validate_six_attrs.gd`、`validate_colpo.gd`、`validate_level_refine.gd`、`validate_jungle_art.gd`、`validate_jungle_camera.gd`、`validate_world_drops.gd`、`validate_player_anim.gd`、`validate_new_player_frames.gd`。

**截图 / 实机检查**
`capture_harbor.gd`、`capture_jungle.gd`、`capture_menu.gd`、`capture_ui.gd`、`capture_quest.gd`、`capture_south_port.gd`、`capture_mountain_preview.gd`、`capture_hub_districts.gd`、`capture_dressing.gd`、`capture_occlusion_demo.gd`、`capture_opening_boat.gd`、`capture_opening_shots.gd`；`check_harbor_hub.gd`、`check_harbor_port.gd`、`check_occlusion_fade.gd`、`check_presets.gd`；`compare_jungle_cameras.gd`、`compare_sword_cameras.gd`、`compare_attack_runtime.gd`

**探针（临时排查用，`probe_*` 17 个）**
`probe_dock_deck` / `probe_dock_presets` / `probe_dressing_presets` / `probe_layout` / `probe_mountain_presets` / `probe_quest_forge_presets` / `probe_occlusion_cost` / `probe_occlusion_coverage` / `probe_save` / `probe_frame_duration` / `probe_new_moves_sheet` 等，另有 `dump_opening_boat.gd` / `dump_opening_frame.gd` / `render_attack_offscreen.gd`

**美术处理（Python 34 个）**
打包：`package_swordsman.py`、`package_8dir.py`、`package_meowa_missing.py`、`package_new_moves.py`、`package_new_moves_v2.py`
归一：`normalize_combo_frames` / `normalize_walk_atlases` / `normalize_walk_height` / `normalize_generated_sheet` / `normalize_attack_video_sheets` / `normalize_run_video_sheets`
修图：`fix_combo_anchors` / `fix_walk_sway` / `fix_broken_attack_frames`
分析：`foot_analysis` / `measure_sheet_extents` / `diagnose_anim_sheets` / `verify_new_atlases` / `map_new_moves_layout`
图集与预览：`build_combo_sheet` / `build_animation_spec_assets` / `anchor_normalize_sheets` / `make_frame_overview` / `make_new_moves_gifs` / `overview_new_moves_views`
抽帧：`extract_video_frames` / `extract_latest_12` / `select_frames_24` / `slice_new_moves` / `crop_new_moves_rowgroups`
生成：`gemini_attack_regenerate.py`

**运行日志 / 备份**：`harbor_*.log`、`hub_*.log`、`tools/backups/`、`tools/meowa_out/`、`tools/attack_12/`、`__pycache__/`

---

## 11. 工程配置与外部依赖

- **自动加载**：`GameState`（游戏）、`MCPGameBridge`（编辑器桥，非游戏逻辑）。
- **编辑器插件**：`addons/godot_mcp/`（读写/运行编辑器）、`addons/hd2d_scene_tools/`（自带 `editor/`、`runtime/`、`shaders/`）。
- **输入映射**：`project.godot` `[input]` 共 **19** 个动作（见 §2 按键表）。
- **渲染**：D3D12、MSAA 3D ×2、Nearest 过滤、默认清屏色深蓝。
- **MCP**：`.mcp.json` 注册 `godot-mcp` 服务，用 `node` 启动 `.tools/godot-mcp-control/server/dist/cli.js`，连 `127.0.0.1:6550`（对应 `project.godot [godot_mcp]`）。它提供 21 个 `godot_*` 工具（场景/节点编辑、输入注入、冻结步进、运行时状态）。
- **本地工具目录**：`.tools/`（godot-mcp 源码与构建产物）、`.local-backups/`（6 份带日期的场景/脚本备份）、`.zcode/` `.codebuddy/` `.workbuddy/` `.trae/`（各 AI 工具的工作与记忆目录，未跟踪）。
- **美术生成**：Meowa `game-assets` skill（素材在 `art/meowa/`、`skills-lock.json`）。
- **Git 忽略**：`.local-backups/`、`.env`（API key）、`docs/**/*.png` 等。

---

## 12. 核心约定

1. **数值集中在 `data/`**：改平衡不动代码。战斗技能只改 `combat_skills.gd`；装备只改 `equip_tables.gd`；内容只改 `campaign.gd`。
2. **键位文案只改 `key_bindings.gd`**：底部提示与 F1 面板共用同一数据源，避免两处走偏。
3. **静态定义与运行态分离**：`Campaign.ITEMS` 是 `const` 不可变；成长/晋升等改动写入 `campaign.item_upgrade` 覆盖层，读取一律走 `GameState.item_def()`。
4. **场景过场统一走 `GameState.change_scene()`**，不直接 `change_scene_to_file`。
5. **UI 不解析提示文本**：面板通过回调/`campaign_action` 驱动逻辑。
6. **术语沿用**：乐园 / 烙印 / 契约者 / 世界之源 / 噬灵者。未实装的功能不写成已解锁。
7. **改动前先看 `git diff`**：工作区常有多轮未提交改动，不要覆盖他人工作，也不要重跑会覆盖场景的生成脚本。
8. **验证脚本各有通过标志**（`*_FAILURES=0` / `*_CHECKS: PASS` / 中文「全部 PASS」，见 §10 表），跑绿才算通过；但脚本只验流程与状态，不替代真人手感测试。
9. **色彩语言**：蓝色 = 系统、红色 = 危险、金色 = 高价值；同时配文字与形状，不只靠颜色。
10. **面板外观只改 `system_ui.gd`**：商店、任务档案共用同一套 `card()` / `style_button()` 设计语言，避免各面板各写一套。
11. **任务文案只改 `data/quest_log.gd`**：任务档案是存档进度的只读映射，不新增存档字段、不在面板里写业务规则；加地区/支线只动这一个文件。

---

## 13. 已知缺口（详见 `PROJECT_STATUS_AUDIT.md` §4/§5）

| 项 | 状态 |
|---|---|
| ~~<kbd>K</kbd> 直踢未进键位表~~ **✅ 2026-09-23 已修** | `key_bindings.gd` 的 `HINT_ITEMS` / `GROUPS` 已收录直踢，F1 面板与底部提示条都能看到（功能含眩晕与处决）。同日默认键由 `K` 对调为 **`E`**（傲歌改 `K`），正本在 `project.godot` |
| 角色帧表依赖**未提交**资源 | `player.tscn` → `player_frames_video.tres` → `black_swordsman_video/`，三者需一起入库，否则角色动画失效 |
| 防具/首饰类 **乐园公证（export）** 装备内容缺失，11 槽中多槽无物可填 | 未做 |
| 成长吞噬**供给不足**（掉落池无刀类武器可喂斩龙闪） | 未做 |
| 强化**经济断链**（单次 1500 币 vs 单局收入约 1000~1760） | 待调参 |
| 伤害公式**双轨**（campaign 区间链 vs `attributes.attack()`） | 待收口 |
| 逃脱币 / 救援 / 永久死亡 | 未实装（现死亡=免费重试本地区） |
| 35 分钟世界时限 / 情报 / 直感 / 三分类任务 | 未做 |
| Q/E/R/F/T 的**剧情解锁节点**未定 | 待拍板（另有：猎魔被动化后 Q 键的去留） |
| MP 生态仅靠命中回蓝，无技能消耗出口设计 | 待技能体系收口 |
| Tab 使徒之眼 / 吞噬之核 | 明确后置（鼠标中键现用于轨道镜头，吞噬之核键位待重新指定） |
| 退出时 RID / ObjectDB 资源释放警告 | 未解决（来自 [HARBOR_MAP.md](HARBOR_MAP.md)，功能检查无脚本错误） |

---

## 14. 未提交改动现状（**2026-09-22** 工作区快照）

**统计：48 已修改 / 5 已删除 / 173 未跟踪。** 上一版记录的 09-19 快照（13 个文件）已完全过期，以下为当前口径。

**已修改（48 个）**

| 组 | 文件 |
|---|---|
| 根级与配置 | `.gitignore`、`project.godot`、`player.gd`、`player.tscn` |
| 数据层 | `autoload/game_state.gd`、`data/campaign.gd`、`data/combat_skills.gd` |
| 战斗 | `scripts/combat/enemy.gd`、`scripts/world/{boss_director,wave_spawner}.gd` |
| `scripts/player/player_visual.gd` | 按方向选择 / 镜像帧、攻击、受击和闪避表现 |
| 流程与 UI | `scripts/main/{main,campaign,main_menu,opening,level_select}.gd`、`scripts/ui/{hud,key_bindings}.gd` |
| 世界与镜头 | `scripts/world/{harbor,harbor_service,colpo_level,jungle_camera_style}.gd` |
| 场景 | `scenes/main/{campaign,main_menu}.tscn`、`scenes/world/{harbor,colpo_forest_outer,colpo_forest_clearing}.tscn` |
| 美术 | `assets/characters/black_swordsman/player_frames.tres`、`art/meowa/black_swordsman_fourdir/qa/*.png` ×3 |
| 工具 | `tools/{build_harbor,build_colpo,apply_jungle_camera,harbor_zones,capture_harbor,check_harbor_hub}.gd` + 6 个 `validate_*.gd` |
| 文档 | `docs/{GDD,HARBOR_MAP,JUNGLE_CAMERA_PASS,NOVEL_CORE_SYSTEMS,P1_SCOPE_BASELINE}.md`（本次更新另加 `PROJECT_OVERVIEW.md`） |

**已删除（5 个）**

```
旧战斗规格文档已移除；当前即时战斗规则与数值见 docs/REALTIME_COMBAT_EXTRACTION.md
scripts/world/camera_mouse_lead.gd (+uid)   被 camera_orbit_controls.gd 取代
```

**未跟踪（173 项，按性质分组）**

```
scripts/combat/stun_gauge.gd      即时眩晕状态条
data/quest_log.gd                 任务档案数据源
scripts/ui/{quest_panel,shop_panel,system_ui}.gd
scripts/main/{cinematic,opening_boat}.gd + scenes/main/opening_boat.tscn
scripts/world/{camera_occlusion_fade,camera_orbit_controls}.gd
shaders/{boat_sky,cinematic_overlay,harbor_wall,occlusion_fade_*}.gdshader
assets/characters/black_swordsman_new/  black_swordsman_video/
assets/characters/player_frames_video.tres   ← player.tscn 现在依赖它
assets/characters/black_swordsman/{新版动作,最新版动作}/
levels/                           FreeWalk.tscn + terrain（未接入主流程）
tools/                            约 40 个新脚本（harbor_* / apply_* / capture_* / probe_* / validate_* / package_* / normalize_*）
docs/{REALTIME_COMBAT_EXTRACTION,COMBAT_DESIGN,COMBAT_SYSTEM,QUEST_PANEL,PROJECT_OVERVIEW}.md + docs/camera_sword/
.mcp.json                         Godot MCP 注册
.zcode/  .codebuddy/  .workbuddy/  .trae/     各 AI 工具的工作与记忆目录
probe_out.txt  scenes/world/_probe_save_test.tscn
```

> ⚠️ 这批改动横跨 **09-19 ~ 09-22 四天**，包含港口三次扩写（南岸码头 / 围墙 / 商街 / 工坊 / 委托所 / 科尔波山远景）、镜头与遮挡系统重做、开场第二幕、面板体系、即时战斗技能和角色动作重制等多个**独立主题**。动手前先确认作者与意图。
> ⚠️ **不要重跑** `build_harbor.gd` / `build_colpo.gd` / `harbor_*.gd` 这些会覆盖场景的生成脚本。
> ⚠️ `player.tscn` 已指向未跟踪的 `player_frames_video.tres`：提交时 `player.tscn` + `.tres` + `black_swordsman_video/` 三者必须一起入库，否则角色动画失效。

---

## 15. 文档索引 `docs/`

| 文档 | 内容 |
|---|---|
| **PROJECT_OVERVIEW.md** | 本文：结构与索引（09-22 更新） |
| `PROJECT_STATUS_AUDIT.md` | 开发时间线总览 + 当前状态 + 缺口（**进度权威**，09-22 更新） |
| `GDD.md` | 游戏设计文档 v0.4（**规则权威**） |
| `GDD_legacy_20260916.md` | 旧版 GDD |
| `P1_SCOPE_BASELINE.md` | P1 范围基线 v1.1：锁定内容、禁止新增清单、退出标准 |
| `IMPLEMENTATION_PLAN.md` | A01~E04 工作包与验收 |
| `NOVEL_CORE_SYSTEMS.md` | 原著规则考据与游戏化取舍 |
| `NOVEL_VOL1_LEVELS.md` | 当前剧情范围（止于猎虎） |
| `REALTIME_COMBAT_EXTRACTION.md` | 即时战斗规则、数值、运行入口和素材清单 |
| `COMBAT_DESIGN.md` / `COMBAT_SYSTEM.md` | 即时战斗设计与实现入口，指向上表 |
| `QUEST_PANEL.md` | 任务档案面板（<kbd>J</kbd>）：三个入口、文件地图、为什么这么做（2026-09-22） |
| `EQUIPMENT_SYSTEM.md` | 装备系统 v0.2（槽位/品质/评分/强化/耐久/吞噬） |
| `HARBOR_MAP.md` | 灰潮港**逐轮施工日志**（383 行，09-17 ~ 09-20）：正式核心循环接入、场景优化、植被清空、围墙、南岸码头、前景遮挡淡出、镜头操控、商街、铸潮工坊、港务委托所、装饰景观层、科尔波山远景 |
| `JUNGLE_ART_PASS.md` / `JUNGLE_CAMERA_PASS.md` | 丛林美术与镜头两轮验收 |
| `CORE_LOOP_PLAYTEST.md` | 核心循环试玩记录 |
| `DEMO_STATUS.md` | P0 Demo 交付说明与验证方式 |
| `OPTIMIZATION_HANDOFF_20260918.md` | Demo 优化交接清单 |
| `meowa_design_20260916/` | Meowa 策划素材（16 md + 2 json） |
| `camera_sword/compare.html` | 剑刃机位对比页 |

> **口径提示**：本文与 `PROJECT_STATUS_AUDIT.md` 是仅有的两份「索引/进度」文档，其余文档各自记录某一轮施工（`HARBOR_MAP.md` 是最典型的一例，按日期分段追加，不回头改）。**发版或改口时，先更新这两份，再去看专题文档是否还成立。**

---

*本文档只做结构整理，未修改任何游戏代码。若与代码不一致，以代码与 `PROJECT_STATUS_AUDIT.md` 为准，并欢迎直接更新本文。*
