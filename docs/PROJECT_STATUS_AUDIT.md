# 轮回乐园 HD-2D · 项目开发时间线总览

> 整理日期：**2026-09-22**（上一版 09-18）；**§4 / §5 / §6 于 2026-09-23 逐行对照代码复核**，已推翻的断言就地标 ✅（见 [DOCS_INDEX.md](DOCS_INDEX.md) §5）。
> 数据来源：① 当前代码逐文件盘查（09-22 逐项对照）；② docs/ 内既有规划文档；③ Codex 会话记录（`C:\Users\31992\.codex\sessions\2026\*`，11 个会话的文件级改动）；④ Trae 会话记忆。
> 配套文档：[PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md)（结构与索引）· [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md)（战斗现状）· [GDD.md](GDD.md) · [P1_SCOPE_BASELINE.md](P1_SCOPE_BASELINE.md) · [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) · [EQUIPMENT_SYSTEM.md](EQUIPMENT_SYSTEM.md) · [COMBAT_REWORK_PLAN.md](COMBAT_REWORK_PLAN.md)（双形态改版分期）· [HARBOR_MAP.md](HARBOR_MAP.md)（港口逐轮施工日志）
>
> **本轮（09-22）更新范围**：补 09-19 ~ 09-22 四天的日志与里程碑；**§3 / §4 / §5 / §6 已按当日代码重核**（原 §5 中 #1/#2/#3/#6 四项已被 09-19 loot 提交与技能提交修掉，见下表删除线标注）。

---

## §1 时间线速览

| 日期 | 阶段 | 里程碑 | 驱动方 |
|---|---|---|---|
| 09-15 | 接入期 | 装好 Godot MCP，实现对编辑器的接管 | Codex |
| 09-16 上午 | 资产与工具期 | meowart game-assets skill + API key；四方向像素角色与动画 | Codex |
| 09-16 白天 | 策划期 | GDD v0.4 / P1 范围基线 / 实施清单三件套定稿 | Codex |
| 09-16 傍晚 | Demo 期 | 首个可漫游的 HD-2D 港区小样 | Codex |
| 09-17 凌晨 | 工具期 | Blender MCP 接通（127.0.0.1:9876） | Codex |
| 09-17 白天 | 场景期 | 丛林地图 HD-2D 化（镜头/美术两轮验收）+ 港口光影完善 | Codex |
| 09-17 晚 | 核心循环期 | 五地区试炼 + 巨虎 Boss + 港口服务正式串线 | Codex |
| 09-18 | 系统深化期 | 六维属性落地、装备系统 v0.2 策划逐条拍板并实施、核心循环二次打磨 | Trae |
| **09-19** | **提交日 + 港口扩写** | 5 个提交：技能数值表与刀芒/影刺、动作图集四方向化、关卡入口提示与 HUD、前期本土装备掉落与场景宝箱、忽略规则整理。同时未提交推进：南岸客货码头、围墙、前景遮挡淡出、轨道镜头（取代"鼠标让出"）、商街、商店 UI 框架 | Codex |
| **09-20** | **港口分区期** | 铸潮工坊（东）、港务委托所（西）、港口装饰景观层（5 子区）、北墙外科尔波山远景层；确认"单段斜劈"为普攻最终形态 | Codex |
| **09-21** | **战斗改版日 + 开场第二幕** | 白天：开场第二幕坐船过场（cinematic + opening_boat）、前景遮挡淡出落地；晚：面板设计语言 `system_ui.gd`、商店面板；**深夜：双形态战斗 P1（`scripts/battle/` 5 文件 + `validate_battle.gd`）定案并实装**；同日合并战斗文档为 `COMBAT_SYSTEM.md`、产出 `COMBAT_REWORK_PLAN.md` | Codex |
| **09-22** | **任务面板 + 文档校准** | 任务档案面板（J）落地（`quest_log.gd` + `quest_panel.gd` + 回归）；文档同步（QUEST_PANEL / PROJECT_OVERVIEW / HARBOR_MAP）；本项目审计文档重核 | Codex |

---

## §2 详细开发日志（正序）

### 2.1 09-15 · 接入期 —— Godot MCP 接管

- **任务**：让 AI 能直接操作 / 运行 Godot 编辑器。
- **文件改动**：
  - 新增 `.tools/godot-mcp/`（`git clone` mkdevkit/godot-mcp，npm 构建）
  - 新增 `addons/godot_mcp/`（编辑器插件，复制自 .tools）
  - 新增 `.codex/config.toml`（注册 `godot_mcp` 服务，端口 6505）
  - `project.godot`：注册 `[editor_plugins]` 开启插件
- **成果**：编辑器读/写/运行桥接可用；调试过一次 6505 端口多客户端互斥问题（单客户端保护机制，正常现象）。

### 2.2 09-16 上午 · 资产与工具期

- **meowart game-assets skill 配置**（09-16 00:20）
  - 新增 `.env`（API key，已入 `.gitignore`）、`.env.example`
  - `npx skills add meowa-skills`；认证通过（体验积分 200）
  - 临时密码脚本用完即删
- **像素角色 + 四方向动画**（09-16 00:41，Meowa 生成）
  - 产出 `art/meowa/black_swordsman_fourdir/`（gb/商家产出 + final_outputs.json/preview.html）
  - 新增 `scripts/player/player_visual.gd`、`tools/package_swordsman.py`、`tools/validate_player_visual.gd`
  - 改 `player.gd`、`player.tscn`、`scenes/main/main.tscn`、`assets/characters/black_swordsman/README.md`
  - 成果：四方向移动 + 上下攻击动画接入（8 帧、192×160），无头 + D3D12 实渲染通过

### 2.3 09-16 白天 · 策划期 —— 三件套定稿

- **任务**：把原著游戏化提炼固化为正式规划文档。
- **文件改动**（仅文档，未动代码）：
  - 新建 `docs/P1_SCOPE_BASELINE.md`（v1.1：范围锁定、按键与技能集、禁止新增清单、变更门禁、退出标准）
  - 大改 `docs/GDD.md`（v0.4）、`docs/IMPLEMENTATION_PLAN.md`（A01~E04 工作包与验收）
- **关键决策**：猩红卡后置 P2、逃脱币为保命消耗品、敏捷只改移速、魅力/幸运 P1 不生效、主城四面板、图鉴仅留 P2 占位按钮。

### 2.4 09-16 傍晚 · Demo 期 —— 港区小样

- **任务**：先搭出可漫游的 HD-2D 港口雏形验证风格。
- **文件改动**：经 Godot MCP 编辑器操作搭出 `scenes/world/harbor.tscn`（像素角色、树木、立体仓库、石板街、木栈桥、水面/路灯/雾/景深）。
- **成果**：可漫游、碰撞已验；`docs/harbor_preview.png` 存档。

### 2.5 09-17 凌晨 · 工具期 —— Blender MCP

- **任务**：接通 Blender 以便自建 3D 场景资产。
- **文件改动**：全局 `C:\Users\31992\.codex\config.toml` 注册 blender 服务；安装 uv + blender-mcp 插件并启用。
- **成果**：`127.0.0.1:9876` 监听就绪（mcp-for-blender 社区方案）。

### 2.6 09-17 白天 · 场景期 —— 丛林 + 港口两轮美术验收

- **丛林 HD-2D 化**（09-17 01:28）
  - 新增 `shaders/forest_floor.gdshader`、`scripts/world/jungle_camera_style.gd`、`tools/apply_jungle_camera.gd`、`tools/compare_jungle_cameras.gd`、`tools/validate_jungle_art.gd`、`tools/validate_jungle_camera.gd`、`docs/JUNGLE_ART_PASS.md`、`docs/JUNGLE_CAMERA_PASS.md`
  - 大改 `tools/build_colpo.gd`（+259/-115）、改 `scripts/world/colpo_level.gd`、`tools/capture_jungle.gd`
  - 成果：43° 正交 → 30° 轻透视、移动前瞻、原地瞄准不晃镜头、景深后移；290 项检查通过
- **港口光影完善**（09-17 12:23）
  - 新增 `shaders/harbor_grade/paving/water/glints` 四套 shader、`tools/harbor_lighting.gd`、`tools/harbor_zones.gd`、`tools/check_harbor_hub.gd`、`docs/HARBOR_MAP.md`
  - 改 `tools/build_harbor.gd`、`scripts/world/harbor.gd`、`scripts/world/harbor_service.gd`、`scripts/ui/hud.gd`、`scripts/main/level_select.gd`
  - 成果：黄昏暖灯/冷色阴影/体积雾/接触阴影；修复码头穿帮与闪光遮挡；通行/交互/传送检查通过

### 2.7 09-17 晚 · 核心循环期 —— 正式串线（到巨虎为止）

- **任务**：把已有场景复用进正式流程，跑通「契约 → 五地区 → 巨虎 → 结算 → 港口」核心循环。
- **文件改动**（本轮最大工程量）：
  - 大改 `scripts/main/campaign.gd`（+370/-18，跨场景进度/Boss/波次/战利品/检查点编排）
  - 大改 `autoload/game_state.gd`（+150，存档/背包/装备/经济/结算）
  - 大改 `scripts/ui/hud.gd`（+139，11 槽面板雏形 + 64 格背包 + 品质交互）
  - 改 `player.gd`（+58）、`data/campaign.gd`（+42，五地区 STAGES/ITEMS/CHESTS/HUNTS）
  - 新增 `tools/validate_core_loop.gd`（+273）与 `docs/CORE_LOOP_PLAYTEST.md`
  - 补 `scripts/world/scene_portal.gd`、`wave_spawner.gd`、`boss_director.gd`、`boss_colpo.gd`、`enemy.gd`、`colpo_level.gd`、`harbor.gd` 的 campaign 支持
- **成果**：练习场=1.2~1.5、科尔波山=外围三波→传送门→15s 准备→巨虎战、港口=买/强化/委托/演武场/再出发、C 面板=实际开箱/装备；存档续玩/死亡重试/传送/资源隔离测试通过。

### 2.8 09-18 · 系统深化期（Trae）—— 六维 + 装备 v0.2

- **六维属性系统落地**：裸装六维 + 属性点（力/敏/体/智）、派生公式（HP/MP/移速/攻击）、装备词条聚合替代硬编码
  - 文档：`.trae/documents/六维属性系统实现.md`；代码：`data/attributes.gd`、`autoload/game_state.gd`
- **装备系统 v0.2 策划**（`docs/EQUIPMENT_SYSTEM.md`）：原著 11 位布局（弃 8 槽、取消勋章位）、5 档品质 + 评分 + Q 表、攻击区间双 roll、耐久/强化/修复/分解/出售/成长吞噬规则**逐条拍板**
- **原著槽位核对**：`NOVEL_CORE_SYSTEMS.md §5.1` 记录原著 8 槽设定（含原文引用）；GDD §7.4 同步槽位数
- **装备系统实施**（拍板后按数据→状态→UI→战斗四层落地）：
  - 数据层：`data/equip_tables.gd`（品质/肉体系数/力量倍率/AttackAdd/成功率/Kstr/扣耐/出售分解全查表）、`data/campaign.gd` ITEMS 全字段扩展
  - 状态层：`autoload/game_state.gd`（equip/unequip/req 校验/强化/修复/出售/分解/吞噬晋升/export 结算清理）
  - UI：`scripts/ui/hud.gd`（11 槽穿戴栏 + 64 格背包 + 右侧六维属性 + 品质配色 + tooltip 详情）
  - 战斗：`player.gd`（区间双 roll、护甲减免、肉体修正、击杀/受击扣耐、副手右键射击）
- **核心循环二次打磨**：`docs/CORE_LOOP_PLAYTEST.md` 09-18 更新（原表单开箱/装备实机验证、主菜单继续游戏、北门第二轮出发）

### 2.9 变更前备份

`.local-backups/`：`camera-20260917` / `core-loop-20260917` / `jungle-20260917` / `reuse-existing-20260917` / **`camera-orbit-20260919`** / **`camera-rig-20260919`** —— 各关键改动前的快照，可回滚。

### 2.10 09-19 · 提交日 + 港口大扩写

**当日 5 个提交（全部已入库）**

| 提交 | 内容 |
|---|---|
| `9e0d649 feat(combat)` | 技能数值表 `data/combat_skills.gd` + 刀芒/影刺等战斗技能实现 |
| `01e7150 feat(art)` | 黑衣剑士动作图集四方向化与帧锚点统一 |
| `f8e28a5 feat(level)` | 关卡入口提示、HUD 边缘锚点与流程优化 |
| `c192dfa chore` | 整理仓库忽略规则并同步数据与设计文档 |
| `c71b3e9 feat(loot)` | 前期本土装备掉落、场景宝箱与决战全回复 |

**同日未提交的港口/镜头推进**（逐条见 [HARBOR_MAP.md](HARBOR_MAP.md)）

- 南岸客货码头建成，并修复两处碰撞缺陷；植被清空；港口围墙（`harbor_wall.gdshader` + `harbor_walls.gd` / `apply_harbor_walls.gd`）
- **前景遮挡淡出**：新增 `scripts/world/camera_occlusion_fade.gd`（648 行）+ `occlusion_fade_preset.gdshader` / `occlusion_fade_harbor_wall.gdshader` + `tools/check_occlusion_fade.gd`；修掉一处"淡出单元平行数组错位导致收尾越界"
- **镜头改为轨道式**：`scripts/world/camera_orbit_controls.gd` **取代并删除** `camera_mouse_lead.gd`；移动方向改为"按机位算"（W 恒朝画面深处），八方向取图改为"以机位为北"；俯角上限收到 45°
- 左上「轮回商店」区（一间店面）→ 商店 UI 框架 `scripts/ui/shop_panel.gd`；任务 UI 框架起步
- 新增工具：`harbor_{gate,pier,port_layout,shop,walls}.gd`、`apply_harbor_{clear,shop,south_port,walls}.gd`、`capture_south_port.gd`、`check_harbor_port.gd`、`probe_save.gd`、`compare_sword_cameras.gd` + `scenes/world/_probe_save_test.tscn`

### 2.11 09-20 · 港口分区期

- 东侧「铸潮工坊」ForgeDistrict、西侧「港务委托所」QuestDistrict：`tools/harbor_forge.gd` / `harbor_quest.gd` / `apply_harbor_hub_districts.gd`
- 港口装饰景观层（5 个子区）：`tools/harbor_dressing.gd` + `apply_harbor_dressing.gd`
- 北墙外「科尔波山」远景层：`tools/harbor_mountain.gd` + `apply_harbor_mountain.gd`
- **普攻口径落定：单段斜劈**（原三段连击取消）
- 商街从一间店面扩成一条街；各轮素材结论与布置约束记入 `HARBOR_MAP.md`

### 2.12 09-21 · 战斗改版日 + 开场第二幕

- **开场第二幕**：`scripts/main/cinematic.gd`（程序化 2D 电影镜头）+ `scripts/main/opening_boat.gd`（3D 坐船过场）+ `shaders/boat_sky.gdshader` / `cinematic_overlay.gdshader` + `scenes/main/opening_boat.tscn`；`opening.gd` 取名后切第二幕，坐船结束再进 `campaign`
- **面板设计语言**：`scripts/ui/system_ui.gd` 统一"深蓝灰底 + 电光青边 + 四角铆钉"，商店面板改走它
- **双形态战斗定案并实装 P1**（当日 22:57 ~ 23:06 落文件）：
  - 文档：`TURNBASED_COMBAT_PLAN.md`（提案 + D1~D5 决策）→ `COMBAT_REWORK_PLAN.md`（分期实施计划）；`COMBAT_SYSTEM.md` 合并三份旧战斗文档（`COMBAT_SPEC_SUXIAO` / `SKILL_NUMERICS_SUXIAO` / `COMBAT_SYSTEM_HANDOFF` 同日删除）
  - 代码：`scripts/battle/{battle_unit,battle_controller,order_bar,battle_menu,encounter_zone}.gd`、`tools/validate_battle.gd`；`player.gd` 加 `battle_mode` 门闩 + 回合执行入口 + K 直踢；`enemy.gd` 加 `battle_driven` 与 `battle_advance`
  - **实装量超过计划中的 P1 最低线**：五条指令（攻击 / 战技 / 防御 / 道具 / 逃跑）、侧/背击加成、防御减伤 75% 与 30% 弹反**全部落地**；入口在 `main.gd`（练习场白盒）
- 角色动作重制：`assets/characters/black_swordsman_new/`（129 文件）、`black_swordsman_video/`（257 文件，视频抽帧）、`player_frames_video.tres` —— **`player.tscn` 已改指新帧表**（这批未提交）

### 2.13 09-22 · 任务面板 + 文档校准

- **任务档案面板（J）**：`data/quest_log.gd`（四章任务表，存档进度的只读映射）+ `scripts/ui/quest_panel.gd` + `tools/validate_quest_panel.gd` + `tools/capture_quest.gd`；三个入口（<kbd>J</kbd> / Esc 菜单 / 港务委托所 <kbd>V</kbd>），委托所接取动作由 `campaign._accept_first_quest` 提供
- 文档：`docs/QUEST_PANEL.md`、`docs/PROJECT_OVERVIEW.md`、`docs/HARBOR_MAP.md`
- **回归实测**（本机 Godot 4.7.2 + `--headless`，全部通过）：`validate_battle` / `validate_combo_skills` / `validate_combat_skills` / `validate_core_loop` / `validate_onboarding_flow` / `validate_player_visual` / `validate_camera_orbit` / `validate_quest_panel`

---

## §3 截至 09-22 晚的当前状态

### 3.1 可玩闭环（一句话）

主菜单 → 开场剧情（取名）→ **船上 3D 过场** → 五阶段试炼 → 巨虎 Boss → 结算 → 灰潮港主城（商店/工坊/委托/演武场）→ 再次出发；装备、六维、强化、耐久、成长吞噬数值层已接线。
另有一条**并行支线**：练习/试炼场内可与游荡野狼触发**回合指令战**（双形态改版 P1），战役主线尚未接它。

### 3.2 已实现系统速查

| 系统 | 状态 | 关键位置 |
|---|---|---|
| 主流程 + 出击结算事务 + 版本化存档（原子写/备份/迁移/兜底） | ✔（09-23 补事务与存档可靠性） | [main.gd](../scripts/main/main.gd) · [game_state.gd](../autoload/game_state.gd) · [validate_save_transaction.gd](../tools/validate_save_transaction.gd) |
| 开场两幕（2D 剧情 + 3D 坐船过场） | ✔ | [opening.gd](../scripts/main/opening.gd) · [opening_boat.gd](../scripts/main/opening_boat.gd) · [cinematic.gd](../scripts/main/cinematic.gd) |
| 战斗（**即时野战**）：单段斜劈/缓冲/剃/拼刀/直踢/燧发枪右键/炸弹/药剂 | ✔ | [player.gd](../player.gd) |
| **回合指令战（双形态 P1）** | ✔ **仅练习/试炼场白盒**；战役未接 | [scripts/battle/](../scripts/battle) · [main.gd](../scripts/main/main.gd) |
| 伤害链路：区间双 roll/力量倍率/护甲减免/肉体修正/扣耐 | ✔ | [player.gd](../player.gd) · [equip_tables.gd](../data/equip_tables.gd) |
| 装备：11 槽/64 背包/5 品质/需求/耐久/强化/修复/出售/分解/成长吞噬 | ✔（前期本土防具/刀类已补，09-19） | [game_state.gd](../autoload/game_state.gd) · [campaign.gd](../data/campaign.gd) |
| 六维属性 + 属性点 + 词条聚合 | ✔ | [attributes.gd](../data/attributes.gd) |
| 面板体系：角色面板（C）· 商店 · **任务档案（J）** · 统一设计语言 | ✔ | [system_ui.gd](../scripts/ui/system_ui.gd) · [shop_panel.gd](../scripts/ui/shop_panel.gd) · [quest_panel.gd](../scripts/ui/quest_panel.gd) · [quest_log.gd](../data/quest_log.gd) |
| 镜头：轨道操控（中键转视角/滚轮推拉/俯角 ≤45°）+ 前景遮挡淡出 | ✔ | [camera_orbit_controls.gd](../scripts/world/camera_orbit_controls.gd) · [camera_occlusion_fade.gd](../scripts/world/camera_occlusion_fade.gd) |
| 灰潮港服务（杂货/工坊/委托/演武场/世界入口） | ✔ | [harbor_service.gd](../scripts/world/harbor_service.gd) |
| 波次系统 + 巨虎三阶段 Boss + 检查点 | ✔ | [wave_spawner.gd](../scripts/world/wave_spawner.gd) · [boss_colpo.gd](../scripts/combat/boss_colpo.gd) |
| 验证脚本（18 个；09-23 实跑 8 个旧脚本 + 1 个新脚本全通过） | ✔ 通过 | `tools/validate_*.gd` |

---

## §4 已规划但未实现（缺口）

| 项 | 说明 | 状态 |
|---|---|---|
| ~~R 刀芒 / F 环断 / T 影刺~~ | 近战技能三件套 | **✔ 已实装**（09-19 `9e0d649`，数值入 `combat_skills.gd`） |
| ~~Q 青钢影・猎魔 / E 傲歌~~ | 开关真伤 / 护盾 | **✔ 已实装**（护盾球已有显隐逻辑，非死代码） |
| MP 生态 | 回蓝口径已改（命中 1% + 被动 0.2%/秒，09-19）；但**仍无技能消耗出口设计** | 部分解决，待技能体系收口 |
| **双形态战斗 P2 / P3** | ~~眩晕条与处决、眩晕切回合、首轮先手权、山之主接入~~ **✅ 09-22 已实装**；**仍缺**：影刺/傲歌/青钢影回合化、猎魔被动化、意图预告、战斗运镜、炸弹延迟引爆、战役接入、Boss 回合化、单方向战斗演出 | **P1 ✅（仅练习场 + 教学场） · P2 🟡 部分 · P3 ⬜ 未开始**，逐条见 [COMBAT_REWORK_PLAN.md](COMBAT_REWORK_PLAN.md) |
| ~~防具 / 戒指类装备内容~~ | 11 槽中多槽无物品可填 | **部分已补**（09-19 loot 提交加了 6 件前期本土防具 + 铜戒指）；**乐园公证（`export=true`）防具/首饰仍缺**，多槽无高阶物可填 |
| 逃脱币 / 救援 / 永久死亡 | 现死亡=免费重试本地区；**结算事务入口已就绪**（`GameState.settle_sortie(outcome)` 四路径共用，09-23） | 与 P1 基线/原著"等价交换"冲突，仅剩数值与角色销毁规则需拍板 |
| 35 分钟世界时限 / 情报 / 直感 / 三分类任务 | 现仅阶段主线 + 虎齿文字钩子 | 未做 |
| 成长吞噬供给 | 掉落池已含刀类（缺口铁刀 / 精铁刀，均 `1h_sword`，09-19 入库） | **✔ 链路已通**，仅数量偏少 |
| Tab 使徒之眼 / 吞噬之核 | — | 明确后置（DEFERRED）；中键已改作镜头控制，键位待重指 |

---

## §5 已做内容的不足（按优先级）

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| 1 | ~~**HUD 文案写 "F 燧发枪"，实际绑定是右键副手**~~ **✅ 09-19 已修** | [hud.gd](../scripts/ui/hud.gd) 现为"右键 燧发枪（需装备）" · [key_bindings.gd](../scripts/ui/key_bindings.gd) 为"鼠标右键" | 已一致 |
| 2 | ~~**防具内容缺失**：ITEMS 无 head/body/arm/boots/cloak/ring 装备~~ **✅ 09-19 已补** | [campaign.gd](../data/campaign.gd)：`leather_cap` / `hunter_hat` / `ragged_vest` / `leather_bracer` / `worn_boots` / `tattered_cloak` / `copper_ring` | 防御链路与护甲扣耐已可触发；**`export=true` 的高阶防具仍缺** |
| 3 | ~~**成长吞噬无供给**：掉落表无刀类武器~~ **✅ 09-19 已补** | `RANDOM_EQUIP_POOL` 现含 `worn_blade` / `iron_sword`（均 `1h_sword`） | 斩龙闪晋升链路可达 |
| 4 | **强化经济断链**：斩龙闪单次 1500 币 vs 一局收入≈1000~1760 | [equip_tables.gd](../data/equip_tables.gd) | 强化/分解/出售难进入玩家决策（仍待调参） |
| 5 | **伤害公式双轨**：campaign 走区间链，独立试炼/面板仍用"武器7+力量" | [attributes.gd](../data/attributes.gd) | 口径两套，易遗漏（仍待收口） |
| 6 | ~~**护盾视觉死代码**：红球 Mesh 创建后永久隐藏~~ **✅ 已非死代码** | [player.gd](../player.gd) 已有 `shield_visual.visible = true/false` 分支 | 傲歌护盾表现生效 |
| 7 | ~~文档过期：CORE_LOOP_PLAYTEST 原写"8 槽装备"~~ | **✅ 2026-09-19 已修** | 已改为 11 槽 |
| 8 | **K 直踢未进键位表** | [key_bindings.gd](../scripts/ui/key_bindings.gd) 的 `HINT` / `GROUPS` 均无 K，而 [player.gd](../player.gd) 已实装 | 玩家从 F1 面板与底部提示**看不到这个技能** |
| 9 | ~~**角色帧表依赖未提交资源**~~ **✅ 09-23 已修** | [player.tscn](../player.tscn) → `player_frames_video.tres` → `black_swordsman_video/`（**均已入库**，后者 256 文件） | 已无"指向空资源"风险 |
| 10 | ~~**回合战眩晕链是空调用**~~ **✅ 09-22 已修（P2）** | [enemy.gd](../scripts/combat/enemy.gd) L467 与 [boss_colpo.gd](../scripts/combat/boss_colpo.gd) L132 均已实现 `add_stun` / `is_stunned`，[stun_gauge.gd](../scripts/battle/stun_gauge.gd) 已建 | K 直踢的 25 点眩晕**现已生效** |
| 11 | ~~**`BattleUnit.sync_from_player()` 定义了但从未被调用**~~ **✅ 09-23 已修** | 调用点在 [battle_controller.gd](../scripts/battle/battle_controller.gd) L84 | 玩家单位 hp/mp 已随回合同步 |
| 12 | **`encounter_zone.gd` 未挂进任何场景** | 只有 `tools/validate_battle.gd` 引用它；开战走 `main.gd::_try_trigger_battle()` | ⚠️ **已非待办**：[COMBAT_DESIGN.md](COMBAT_DESIGN.md) v0.2 取消了"圈内入战 + 禁出结界"，该文件按设计**不再挂入**；残留文件可随 P2 清理 |
| 13 | **拼刀两套语义并存** | D3 决定删拼刀（机制由回合「防御」承担，已实装），但 `CLASH_*` 与实时侧触发仍在跑 | 同一场战斗可能两套判定叠用，需 P2 明确口径 |
| 14 | **未提交规模偏大** | 截至 09-23：源码/文档/脚本改动 **172** 项（112 `.gd` · 23 `.py` · 19 `.md` · 10 `.tscn` · 5 `gdshader`）+ 128 张预览 png；另有 `art/`·`assets/` 素材整理 **1432** 项（09-23 素材迁移所致）。横跨 09-19~09-23 **五个多主题工作日** | 改动难回溯、协作易冲突；建议按主题分批提交 |

---

## §6 建议后续（2026-09-22 重排，09-23 复核）

> **09-23 复核结论**：下列第 2 条②、第 3 条前半**已完成**；第 1 条未动且规模变大（见 §5 #14）；第 3 条"`encounter_zone` 挂进场景"**已按设计变更作废**（[COMBAT_DESIGN.md](COMBAT_DESIGN.md) v0.2 取消"圈内入战"）。

1. **立即（清理风险）**：把横跨 09-19 ~ 09-22 的未提交改动**按主题分批提交**，建议拆五批：① 港口扩写（南岸码头/围墙/商街/工坊/委托所/山景）② 镜头 + 遮挡淡出 ③ 开场第二幕 + 面板体系 ④ 双形态战斗 P1 ⑤ 角色动作重制。**第 ⑤ 批必须带上 `player_frames_video.tres` 与 `black_swordsman_video/`**，否则 `player.tscn` 指向空资源。
2. **立即（小修，成本极低）**：① K 直踢补进 `key_bindings.gd` 的 `HINT` / `GROUPS`（**仍待办**）；~~② `BattleUnit.sync_from_player()` 接上调用或直接删除~~ **✅ 09-23 已接上调用**；③ 明确"实时拼刀是否保留"（D3 已决定删，代码仍留着）。
3. **短程（双形态 P2）**：~~野战眩晕条 `stun_gauge.gd` + `enemy.add_stun()` / 处决 → 打开 K 直踢的眩晕效果；眩晕切回合~~ **✅ 09-22 已完成**；**仍待办**：影刺 / 傲歌 / 青钢影回合化、猎魔被动化、意图预告、战斗运镜、炸弹延迟引爆。~~`encounter_zone` 挂进场景并补禁出限制~~ **作废（设计变更取消圈内入战）**。
4. **短程（拍板）**：逃脱币 / 救援 / 永久死亡是否纳入本版。
5. **中程（双形态 P3）**：战役关卡接入（`wave_spawner` 遭遇化）、Boss 回合化、战斗演出单方向化、数值平衡回填。
6. **中程（老缺口）**：强化经济校准；伤害公式双轨收口；乐园公证（`export=true`）防具/首饰内容补齐；MP 生态的技能消耗出口设计。

> 注：本文件为纯审计/时间线文档。**2026-09-22 本轮更新只改文档，未改动任何游戏代码**；§3 / §4 / §5 / §6 已按当日代码逐项重核。
>
> **2026-09-23 追加（有代码改动）**：修正死亡「回滚」名不副实的问题 —— `equipment_drop._collect()` 与 `game_state.damage_item_dura()` 原先即时 `save_game()`，等于阵亡重试保留战利品却不还原耐久，还留下了「反复阵亡刷掉落」的口子。现改为「出击快照 → 本局临时状态 → 一次性提交」：`SORTIE_KEYS = ["bag","item_dura"]` 只改内存，任何显式 `save_game()` 即提交点，`settle_sortie(outcome)` 为四条结束路径的唯一入口。存档同批加固：`version` 字段、写临时档 + rename 原子替换、`.bak` 备份档与坏档回退（此前单文件直接覆盖，写坏即整档报废；且只剩段头的空壳档会被当成有效进度，静默清空姓名与乐园币）。回归 `tools/validate_save_transaction.gd`（67 项断言，`SAVE_TRANSACTION_FAILURES=0`），受影响的 8 个旧脚本全部复跑通过。