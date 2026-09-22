# 文档总索引

> 整理日期：**2026-09-23**（本轮逐项对照代码复核）
> 用途：回答「仓库里一共有几份文档、各属哪一类、什么时候写的、**做了没有**、两份打架时以哪份为准」。
> 三份索引的分工：**本文 = 文档清单与状态**；[PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) = 代码结构与目录索引；[PROJECT_STATUS_AUDIT.md](PROJECT_STATUS_AUDIT.md) = 进度与缺口权威。
> 本文只做分类与状态标注，不改任何游戏代码。

---

## 0. 三步用法

1. **改代码前**：按 §1 找到对应「类型」的权威文档，先读它 —— 别从最早的那份开始读。
2. **两份文档打架**：查 §3 的效力表。设计层 < PRD 层 < **代码（as-built）**。
3. **看到标 🔒 的**：已完成或被取代的**冻结件**。它们记录的是当时的事实，不要在上面追新改动 —— 新事实写进 §1 里标 ✅/🟡 的那几份。

**状态图例**

| 标记 | 含义 |
|---|---|
| ✅ 已落地 | 文档要求的范围已完成，并经 `tools/validate_*.gd` 或代码核对确认 |
| 🟡 部分落地 | 主体已落地，仍有明确未做项（见 §4） |
| ⬜ 未开工 | 只有计划，代码里查不到对应实现 |
| 🔒 冻结 | 历史件（已交付 / 已被取代 / 追加式日志），只读 |
| 📌 生效 | 现行权威，改动要按它走 |

---

## 1. 分类总表

### A. 立项与规则（PRD 层）

| 文档 | 版本 / 日期 | 状态 | 效力 | 一句话定位 |
|---|---|---|---|---|
| [GDD.md](GDD.md) | v0.4 · 2026-09-16（09-19 有改） | 📌 生效 | **§5 战斗规格、§15 已确认按键与技能集**：与 [COMBAT_DESIGN.md](COMBAT_DESIGN.md) 冲突时以 GDD 已确认项为准 | 玩法总规则、四支柱、关卡与排期 |
| [P1_SCOPE_BASELINE.md](P1_SCOPE_BASELINE.md) | v1.1 · 2026-09-16 | 📌 生效 | **P1 范围裁决最高**：保留 / 降级 / 禁止新增以它为准 | P1 垂直切片范围基线、退出标准 |
| [GDD_legacy_20260916.md](GDD_legacy_20260916.md) | 旧版 | 🔒 冻结 | 无（已被 GDD.md v0.4 取代） | 换代前的 GDD，留作对照 |

> ⚠️ GDD §5/P1 基线仍写「鼠标左键 = 近战**三段连击**」，而 2026-09-20 已定案普攻为**单段斜劈**（`player_visual.gd` 的 `COMBO_CLIPS = ["attack"]`）。以代码为准，见 §5。

### B. 计划与实施（怎么做）

| 文档 | 版本 / 日期 | 状态 | 一句话定位 |
|---|---|---|---|
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | 2026-09-16 | 🟡 部分落地 | A01~E04 工作包与验收清单。A 组（战斗）已基本落地；B03/B04 逃脱币与永久死亡、C02~C05 世界任务与情报、D01 整备仍 ⬜ |
| [COMBAT_REWORK_PLAN.md](COMBAT_REWORK_PLAN.md) | 2026-09-21 起，09-22 / 09-23 更新 | 🟡 **P1 ✅ / P2 🟡 / P3 ⬜** | 双形态战斗分期实施计划（含 validate 命令）。**动手前先读它的「⚠️ 设计变更」表** |
| [TURNBASED_COMBAT_PLAN.md](TURNBASED_COMBAT_PLAN.md) | 2026-09-20（状态仍写「待确认」） | 🔒 历史依据 | 双形态改版的**提案原文 + D1~D5 决策记录**。D1~D5 已定案，正本在 plan/design 两份 |
| [.trae/documents/技能树与天赋面板实现计划.md](../.trae/documents/技能树与天赋面板实现计划.md) | 2026-09-21 | ⬜ 未开工 | 刀术技能树（`campaign.training` 可视化）+ 天赋面板（噬灵者 / 灵魂回响）。代码里查不到 `soul_fragments` / `spirit_echo` / `skill_tree` |
| [.trae/documents/六维属性系统实现.md](../.trae/documents/六维属性系统实现.md) | 2026-09-18 | ✅ 已落地 | 六维属性落地方案书。落地结果见 `data/attributes.gd`，回归 `tools/validate_six_attrs.gd` |

### C. 系统设计（专题）

| 文档 | 版本 / 日期 | 状态 | 一句话定位 |
|---|---|---|---|
| [COMBAT_DESIGN.md](COMBAT_DESIGN.md) | **v0.8 草稿** · 09-22 起草 → 09-23 定 v0.8 | 📌 设计层（待评审） | 战斗**应该是什么样、为什么**。标记约定 `✅已定` / `📝提案` / `⚑待定`；**§4.2 有 13 条 `Qn` 待拍板** |
| [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) | v1.1 · 整理 09-21 · 回合补录 09-22 | 📌 as-built | 战斗**实际是什么**。真值源是代码；§3 有「设计 vs 已实现」差异框（8 行） |
| [EQUIPMENT_SYSTEM.md](EQUIPMENT_SYSTEM.md) | v0.2 原著向整合版 · 2026-09-18 | 🟡 主体已落地 | 装备策划与实施：11 槽 / 5 品质 / 评分 / 耐久 / 强化 / 分解 / 成长吞噬。`export=true` 的高阶防具首饰仍缺 |
| [QUEST_PANEL.md](QUEST_PANEL.md) | 2026-09-22 | ✅ 已落地 | 任务档案面板（<kbd>J</kbd>）三个入口与只读映射设计；数据源 `data/quest_log.gd` |
| [SETTINGS.md](SETTINGS.md) | 2026-09-23 | ✅ 已落地 | 设置页（画面 / 声音 / 游玩 / 按键）的四个分页、每项的作用点、改键对调规则与未做项；正本 `autoload/game_settings.gd` + `scripts/ui/settings_panel.gd` |
| [NOVEL_CORE_SYSTEMS.md](NOVEL_CORE_SYSTEMS.md) | v0.3 · 2026-09-17（09-18 补槽位核对） | 📌 生效 | 原著通用底层规则（半数据化、等价交换、乐园契约）。跨卷复用 |
| [NOVEL_VOL1_LEVELS.md](NOVEL_VOL1_LEVELS.md) | v0.3 · 2026-09-17 | 🟡 1.2~1.6 已接通 | 卷一关卡设计（海贼王·哥亚王国篇）。1.7 之后仅留原著规划，不作验收 |
| [HARBOR_MAP.md](HARBOR_MAP.md) | 09-17 起逐轮追加 | 🔒 追加式日志 | 灰潮港主城逐轮施工记录与坐标表。**约定永不回改历史轮次**，新事实往后追加 |

### D. 现状与验收记录

| 文档 | 日期 | 状态 | 一句话定位 |
|---|---|---|---|
| [PROJECT_STATUS_AUDIT.md](PROJECT_STATUS_AUDIT.md) | 整理 09-22 · 追加 09-23 | 📌 **进度权威** | 开发时间线、已实现系统速查、缺口、不足、后续建议。**唯一会被反复对照代码重核的文件** |
| [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) | 整理 09-22 | 📌 结构索引 | 工程里有什么、放在哪、怎么串起来；§14 是未提交快照 |
| [DEMO_STATUS.md](DEMO_STATUS.md) | 2026-09-19 | 🔒 冻结（P0 已交付） | P0 战斗试炼交付记录与验证脚本清单 |
| [CORE_LOOP_PLAYTEST.md](CORE_LOOP_PLAYTEST.md) | 09-18 起，09-19 修订 | 🔒 记录 | 核心循环试玩路径与原有内容复用表 |
| [OPTIMIZATION_HANDOFF_20260918.md](OPTIMIZATION_HANDOFF_20260918.md) | 2026-09-18 | 🔒 冻结 | 09-18 交接清单 + 下一轮工作包。其中 P0/P1 建议多数已在 09-19~09-23 完成 |
| [JUNGLE_ART_PASS.md](JUNGLE_ART_PASS.md) | 2026-09-17 | 🔒 冻结 | 丛林首轮美术整理对照记录 |
| [JUNGLE_CAMERA_PASS.md](JUNGLE_CAMERA_PASS.md) | 2026-09-17 | 🔒 冻结 | 丛林镜头参数（43°→30° 等）。后续镜头已改轨道式，见 COMBAT/OVERVIEW |
| [../README.md](../README.md) | 2026-09-23 | 📌 工程入口 | 环境、跑法、回归流程、写校验脚本的三条约定、待决项 |

### E. 仓库其他位置的文档

| 文档 | 日期 | 状态 | 一句话定位 |
|---|---|---|---|
| [../assets/characters/black_swordsman/ANIMATION_SPEC.md](../assets/characters/black_swordsman/ANIMATION_SPEC.md) | 2026-09-19 | 📌 生效 | 八方向动作图集统一生成规格（画布 768×320 / 4 列 2 行 / 单帧 192×160）。交给外部重绘用 |
| [../assets/characters/black_swordsman/README.md](../assets/characters/black_swordsman/README.md) | 2026-09-19 | 📌 生效 | 四方向图集接入说明与锚点（脚底 96,144 / offset 0,64 / pixel_size 0.016） |
| [../assets/characters/black_swordsman/combo/README.md](../assets/characters/black_swordsman/combo/README.md) | 2026-09-19 | 📌 生效 | combo 系列图集说明 |
| [../art/meowa/black_swordsman_fourdir/attack2_redraw_prompts.md](../art/meowa/black_swordsman_fourdir/attack2_redraw_prompts.md) | 2026-09-20 | ⬜ 待执行 | 两段攻击（袈裟斩 / 逆袈裟）Holopix 八方向生成规格。生成的素材尚未接入 |
| [../art/meowa/black_swordsman_20260916/deliverables/README.md](../art/meowa/black_swordsman_20260916/deliverables/README.md) | 2026-09-16 | 🔒 冻结 | 首批 Meowa 生成物交付说明 |

### F. 本地工具与记忆（**不入库**）

| 位置 | 日期 | 说明 |
|---|---|---|
| `docs/meowa_design_20260916/**` | 2026-09-16 | Meowa 生成的策划骨架 16 份（concept / top_design / architecture / systems），内容基本为占位 |
| `.workbuddy/memory/**` · `.codebuddy/memory/**` | 09-19 ~ 09-21 | 各 Agent 的会话记忆。⚠️ **`.codebuddy/memory/MEMORY.md` 已 stale**：仍把 `COMBAT_SPEC_SUXIAO.md` / `SKILL_NUMERICS_SUXIAO.md` 列为战斗规格正本，这两份已于 09-21 删除并合并进 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) |
| `.local-backups/**` | 09-17 ~ 09-19 | 关键改动前的快照（camera / jungle / core-loop / reuse-existing 等），可回滚 |
| `tools/meowa-skills-update-20260919-v2/**` | 2026-09-19 | meowart `game-assets` skill 包快照（SKILL.md + references）。属工具链，非项目文档 |
| `background/轮回乐园_*.txt` | — | 原著 1~4172 章考据素材，不入库 |

**计入统计**：正式项目文档 **27 份**（`docs/` 21 含本文 · `README.md` 1 · `assets/characters/black_swordsman/` 3 · `art/` 2），另有 2 份 `.trae/documents/` 计划（gitignore，已列在 B 组）；周边 **35 份**（Meowa 生成模板 16 · `.workbuddy` 记忆 4 · `.codebuddy` 记忆 2 · `.local-backups` 2 · meowart skill 包 11）。

---

## 2. 时间线总表（全部正式文档，正序）

| 日期 | 文档 | 类型 | 当时的状态 |
|---|---|---|---|
| ≤ 09-16 | GDD_legacy_20260916.md | 立项 | 🔒 后被取代 |
| **09-16** | GDD.md v0.4 · P1_SCOPE_BASELINE.md v1.1 · IMPLEMENTATION_PLAN.md | 立项 + 计划 | 策划三件套定稿 |
| 09-16 | art/…/deliverables/README.md · docs/meowa_design_20260916/** | 素材 + 模板 | 首批生成物 |
| **09-17** | NOVEL_CORE_SYSTEMS.md v0.3 · NOVEL_VOL1_LEVELS.md v0.3 | 设计 | 原著考据与卷一切片 |
| 09-17 | JUNGLE_ART_PASS.md · JUNGLE_CAMERA_PASS.md | 美术专项 | 丛林两轮验收 |
| 09-17 | HARBOR_MAP.md（起） | 施工日志 | 追加式，至今仍在长 |
| **09-18** | EQUIPMENT_SYSTEM.md v0.2 | 设计 | 11 槽 / 5 品质逐条拍板 |
| 09-18 | CORE_LOOP_PLAYTEST.md · OPTIMIZATION_HANDOFF_20260918.md | 验收 | 核心循环串线完成 |
| 09-18 | .trae/…/六维属性系统实现.md | 计划 | ✅ 同日落地 |
| **09-19** | DEMO_STATUS.md · README.md（初版） | 验收 + 入口 | 提交日，5 个 commit 入库 |
| 09-19 | assets/characters/black_swordsman/{ANIMATION_SPEC,README}.md · combo/README.md | 素材规格 | 图集四方向化统一 |
| **09-20** | TURNBASED_COMBAT_PLAN.md | 计划 | 双形态提案起草（状态「待确认」） |
| 09-20 | art/…/attack2_redraw_prompts.md | 素材规格 | ⬜ 至今未接入 |
| **09-21** | COMBAT_SYSTEM.md v1.1 · COMBAT_REWORK_PLAN.md | 设计 + 计划 | 三份旧战斗文档合并；P1 当日定案并实装 |
| 09-21 | .trae/…/技能树与天赋面板实现计划.md | 计划 | ⬜ 至今未开工 |
| **09-22** | COMBAT_DESIGN.md（v0.1→v0.7）· QUEST_PANEL.md | 设计 + 设计 | 战斗设计草稿七轮；任务面板落地 |
| 09-22 | PROJECT_OVERVIEW.md · PROJECT_STATUS_AUDIT.md | 索引 | 结构与进度双双校准 |
| **09-23** | COMBAT_DESIGN.md **v0.8** · COMBAT_REWORK_PLAN.md（P2 状态回填） | 设计 + 计划 | 指令集**由三条改回五条** |
| 09-23 | PROJECT_STATUS_AUDIT.md（追加存档事务）· README.md（更新） | 索引 + 入口 | 出击快照 / `settle_sortie` 落地 |
| **09-23** | **DOCS_INDEX.md（本文）** | 索引 | 文档清单与状态复核 |

---

## 3. 冗余与冲突：谁压谁

### 3.1 战斗四份 + 提案一份

| 文档 | 回答的问题 | 效力 |
|---|---|---|
| [GDD.md](GDD.md) §5 / §15 | PRD 层规则；§15 载有**已确认**的按键与技能集 | 与 COMBAT_DESIGN 冲突时**以 GDD 已确认项为准** |
| [COMBAT_DESIGN.md](COMBAT_DESIGN.md) | 战斗**应该是什么样、为什么** | 设计层，**待评审** |
| [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) | 现在**实际**是什么（as-built） | 与代码冲突时**以代码为准** |
| [COMBAT_REWORK_PLAN.md](COMBAT_REWORK_PLAN.md) | **怎么落地**（分期任务 + validate 命令） | 实施层 |
| [TURNBASED_COMBAT_PLAN.md](TURNBASED_COMBAT_PLAN.md) | 提案原文与 D1~D5 决策过程 | 历史依据 |

### 3.2 其他重复

- **两代 GDD**：[GDD.md](GDD.md) v0.4 为现行，[GDD_legacy_20260916.md](GDD_legacy_20260916.md) 只作对照。
- **两份丛林文档**：`JUNGLE_CAMERA_PASS.md` 的镜头参数（正交 43° → 轻透视 30°）已被后来的**轨道式镜头**取代，现行口径看 [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) 与 `scripts/world/camera_orbit_controls.gd`。
- **三份索引**：本文（文档清单）、[PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md)（代码结构）、[PROJECT_STATUS_AUDIT.md](PROJECT_STATUS_AUDIT.md)（进度权威）。互不重复裁决。

---

## 4. 做没做（2026-09-23 对照代码）

### 4.1 ✅ 已完成

| 系统 | 证据 |
|---|---|
| 核心循环：主菜单 → 开场（取名）→ 船上过场 → 五阶段试炼 → 巨虎 Boss → 结算 → 灰潮港 → 再出发 | `scripts/main/campaign.gd` |
| 即时战斗全套：单段斜劈 / 剃 / 拼刀 / 直踢 / 燧发枪 / 炼金炸弹 / 药剂 | `player.gd` |
| 技能：猎魔 Q / 傲歌护盾 E / 刀芒 R / 环断 F / 影刺 T | `data/combat_skills.gd` |
| 装备：11 槽 / 64 格背包 / 5 品质 / 需求 / 耐久 / 强化 / 修复 / 出售 / 分解 / 成长吞噬 | `autoload/game_state.gd` · `data/equip_tables.gd` |
| 六维属性 + 属性点 + 装备词条聚合 | `data/attributes.gd` |
| 面板体系：角色 C / 商店 / 任务档案 J / 统一设计语言 | `scripts/ui/{system_ui,shop_panel,quest_panel}.gd` · `data/quest_log.gd` |
| 镜头：轨道操控（中键转视角 / 滚轮推拉 / 俯角 ≤45°）+ 前景遮挡淡出 | `scripts/world/camera_orbit_controls.gd` · `camera_occlusion_fade.gd` |
| 开场两幕（2D 剧情 + 3D 坐船过场） | `scripts/main/{opening,opening_boat,cinematic}.gd` |
| 波次系统 + 巨虎三阶段 Boss + 检查点 | `scripts/world/wave_spawner.gd` · `scripts/combat/boss_colpo.gd` |
| 灰潮港服务：杂货 / 工坊 / 委托 / 演武场 / 世界入口 | `scripts/world/harbor_service.gd` |
| **回合指令战 P1**：五条指令 / 侧背击加成 / 防御减伤 75% + 30% 弹反 | `scripts/battle/**`（**仅练习场与教学场，战役未接**） |
| **回合战 P2（部分）**：眩晕链 `stun_gauge.gd` + `enemy.add_stun()` + 处决、眩晕补刀触发回合、首轮先手权、山之主接入 | `scripts/battle/stun_gauge.gd` · `scripts/combat/enemy.gd:467` · `boss_colpo.gd:132` |
| 新手教程训练场（小怪 + 山之主，均不还手） | `scenes/main/battle_lab.tscn` · `scripts/main/battle_lab.gd` |
| 存档可靠性：出击快照 → 一次性提交、`settle_sortie` 四路径、版本字段 / 原子写 / `.bak` 回退 | `autoload/game_state.gd` · `tools/validate_save_transaction.gd` |
| 回归套件（18 支 `validate_*`，套件内只放全绿） | `tools/run_regressions.sh` |

### 4.2 🟡 部分完成

| 项 | 还缺什么 |
|---|---|
| **回合战 P2** | 影刺 / 傲歌 / 青钢影回合化、猎魔被动化、意图预告、战斗运镜（`start_battle()` 未锁机位）、炸弹延迟引爆 |
| **回合战 P3** | **未开始**：`campaign.gd` / `wave_spawner.gd` / `colpo_level.gd` / `boss_colpo.gd` 对 battle 侧引用数为 0 |
| **MP 生态** | 回蓝口径已改（命中 1% + 被动 0.2%/秒），但**尚无技能消耗出口设计** |
| **装备内容** | 11 槽中 `export=true` 的乐园公证高阶防具 / 首饰仍缺，多槽无高阶物可填 |
| **逃脱币 / 救援 / 永久死亡** | 结算入口已就绪（`settle_sortie`），**规则与数值未拍板** —— 与 P1 基线/原著「等价交换」冲突 |
| **强化经济** | 斩龙闪单次 1500 币 vs 一局收入 ≈ 1000~1760，强化/分解/出售难进入玩家决策 |
| **伤害公式** | 双轨：campaign 走区间链，独立试炼/面板仍用「武器 7 + 力量」 |
| **拼刀** | D3 已决定删（机制转生为回合「防御」），但实时侧 `CLASH_*` 仍在跑，两套语义并存 |
| **K 直踢** | `player.gd` 已实装，但**不在** `scripts/ui/key_bindings.gd` 的 `HINT`/`GROUPS`，F1 面板与底部提示看不到它 |
| **`encounter_zone.gd`** | 文件在 `scripts/battle/`，但只被 `tools/validate_battle.gd` 引用，**未挂进任何场景**；白盒开战走 `main.gd::_try_trigger_battle()` |

### 4.3 ⬜ 未开工

| 项 | 证据 |
|---|---|
| 刀术技能树 + 天赋面板 | 代码无 `soul_fragments` / `spirit_echo` / `skill_tree` / `tree_panel` |
| 35 分钟世界时限 / 情报 / 直感 / 三分类任务 | 现仅阶段主线 + 虎齿文字钩子 |
| Tab 使徒之眼 / 吞噬之核 | 仅存在于 `key_bindings.gd` 文案，明确后置（DEFERRED）；原中键已改作镜头控制，键位待重指 |
| 两段攻击素材接入 | `attack2_redraw_prompts.md` 规格已写，生成物未接入 |
| 导出预设 / CI | 无 `export_presets.cfg`；仓库在 GitHub 但无 CI |

---

## 5. 09-23 复核发现的「文档 vs 代码」不一致

本轮对照代码，发现下列断言已被推翻；其中前三条**已在 [PROJECT_STATUS_AUDIT.md](PROJECT_STATUS_AUDIT.md) 就地更新**（沿用该文件既有的删除线+✅ 约定）：

| # | 文档原话 | 实际 | 处理 |
|---|---|---|---|
| 1 | 审计 §5 #9「角色帧表依赖未提交资源」 | `player_frames_video.tres` 与 `black_swordsman_video/`（256 文件）**均已入库** | ✅ 已更新 |
| 2 | 审计 §5 #10「眩晕链是空调用，`enemy.gd` 无 `add_stun`」 | `scripts/combat/enemy.gd:467` 与 `boss_colpo.gd:132` **都有** `add_stun` / `is_stunned` | ✅ 已更新 |
| 3 | 审计 §5 #11「`BattleUnit.sync_from_player()` 从未被调用」 | `scripts/battle/battle_controller.gd:84` **已在调用** | ✅ 已更新 |
| 4 | 审计 §4「双形态战斗 P2/P3 未做」 | P2 **部分完成**（眩晕链 / 触发 / 先手权 / 山之主接口 / 教学场） | ✅ 已更新为 P1 ✅ / P2 🟡 / P3 ⬜ |
| 5 | GDD §5 与 P1 基线「鼠标左键 = 近战三段连击」 | 09-20 已定案**单段斜劈** | ⚠️ 未改 GDD（属 PRD 层，改它要走变更流程）；以代码为准 |
| 6 | `.codebuddy/memory/MEMORY.md` 把 `COMBAT_SPEC_SUXIAO.md` / `SKILL_NUMERICS_SUXIAO.md` 列为战斗规格正本 | 两份文档 09-21 已删除，合并进 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) | ⚠️ 该文件 gitignore，不进版本库；如仍在用请手改 |

仍成立、未修的两条（都是设计层有意为之，不是错误）：

- [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md) §3 的「设计 vs 已实现」差异框（8 行）—— 按仓库约定**故意保留双份**，直到代码真的改。
- [PROJECT_OVERVIEW.md](PROJECT_OVERVIEW.md) line 159 把 `combat_skills.gd` 描述为「三段连击命中帧」—— 数组仍在，但普攻只用第一段。

---

## 6. 维护约定

1. **改前先读对的那份**：设计意图 → COMBAT_DESIGN；现有行为 → COMBAT_SYSTEM；怎么落地 → COMBAT_REWORK_PLAN；范围该不该做 → P1_SCOPE_BASELINE。
2. **更新顺序**：先改两份索引（本文 + [PROJECT_STATUS_AUDIT.md](PROJECT_STATUS_AUDIT.md)），再看专题文档是否还成立。
3. **文档与代码冲突时，记录双方而不是覆盖**：把「设计 vs 已实现」差异框加在该节开头，as-built 描述在被改之前保持准确。
4. **冻结件不回改**：标 🔒 的文档记录的是当时事实；新事实写进 ✅/🟡 的文档，或在 [HARBOR_MAP.md](HARBOR_MAP.md) 这类日志里**往后追加**。
5. **重复符号先 grep 再写**：往文档里写某个常量 / 函数 / 文件前，先确认它还存在（历史上出现过 `harbor_glints` 式幽灵引用）。
6. **新增文档**：加进 §1 对应类型的分组表，并在 §2 时间线补一行 —— 否则三个月后又变成「太多太杂」。
