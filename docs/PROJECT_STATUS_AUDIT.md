# 轮回乐园 HD-2D · 项目开发时间线总览

> 整理日期：2026-09-18。
> 数据来源：① 当前代码逐文件盘查；② docs/ 内既有规划文档；③ Codex 会话记录（`C:\Users\31992\.codex\sessions\2026\*`，11 个会话的文件级改动）；④ Trae 会话记忆。
> 配套文档：[GDD.md](GDD.md) · [P1_SCOPE_BASELINE.md](P1_SCOPE_BASELINE.md) · [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) · [EQUIPMENT_SYSTEM.md](EQUIPMENT_SYSTEM.md) · [CORE_LOOP_PLAYTEST.md](CORE_LOOP_PLAYTEST.md) · [DEMO_STATUS.md](DEMO_STATUS.md)

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

`.local-backups/`：`camera-20260917` / `core-loop-20260917` / `jungle-20260917` / `reuse-existing-20260917` —— 各关键改动前的快照，可回滚。

---

## §3 截至 09-18 晚的当前状态

### 3.1 可玩闭环（一句话）

主菜单 → 开场剧情 → 契约者姓名 → 五阶段试炼 → 巨虎 Boss → 结算 → 灰潮港主城（商店/工坊/委托/演武场）→ 再次出发；装备、六维、强化、耐久、成长吞噬数值层已接线。

### 3.2 已实现系统速查

| 系统 | 状态 | 关键位置 |
|---|---|---|
| 主流程 + 单槽存档（检查点/迁移/兜底） | ✔ | [main.gd](../scripts/main/main.gd) · [game_state.gd](../autoload/game_state.gd) |
| 战斗：三连击/缓冲/剃/拼刀/燧发枪右键/炸弹/药剂 | ✔ | [player.gd](../player.gd) |
| 伤害链路：区间双 roll/力量倍率/护甲减免/肉体修正/扣耐 | ✔ | [player.gd](../player.gd) · [equip_tables.gd](../data/equip_tables.gd) |
| 装备：11 槽/64 背包/5 品质/需求/耐久/强化/修复/出售/分解/成长吞噬 | ✔（内容缺件见 §5） | [game_state.gd](../autoload/game_state.gd) · [campaign.gd](../data/campaign.gd) |
| 六维属性 + 属性点 + 词条聚合 | ✔ | [attributes.gd](../data/attributes.gd) |
| 灰潮港服务（杂货/工坊/委托/演武场/世界入口） | ✔ | [harbor_service.gd](../scripts/world/harbor_service.gd) |
| 波次系统 + 巨虎三阶段 Boss + 检查点 | ✔ | [wave_spawner.gd](../scripts/world/wave_spawner.gd) · [boss_colpo.gd](../scripts/combat/boss_colpo.gd) |
| 验证脚本（demo/visual/six_attrs/core_loop/jungle*） | ✔ 通过 | `tools/validate_*.gd` |

---

## §4 已规划但未实现（缺口）

| 项 | 说明 | 状态 |
|---|---|---|
| R 刀芒 / F 环断 / T 影刺 | 近战技能三件套 | PLANNED（F1 键位表标注"规划中"） |
| Q 青钢影・猎魔 / E 傲歌 | 开关真伤 / 护盾 | PLANNED；敌人 `has_energy` 字段与噬灵者回蓝无实际玩法 |
| MP 生态 | 无技能消耗出口，再生 3/3600/s，护盾球为死代码 | 待技能实装时重算 |
| 逃脱币 / 救援 / 永久死亡 | 现死亡=免费重试本地区 | 与 P1 基线/原著"等价交换"冲突，需拍板 |
| 35 分钟世界时限 / 情报 / 直感 / 三分类任务 | 现仅阶段主线 + 虎齿文字钩子 | 未做 |
| 防具 / 戒指类装备内容 | 11 槽中 7 槽无物品可填 | 见 §5 #2 |
| Tab 使徒之眼 / 中键吞噬之核 | — | 明确后置（DEFERRED） |

---

## §5 已做内容的不足（按优先级）

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| 1 | **HUD 文案写 "F 燧发枪"，实际绑定是右键副手**（campaign 底部提示与 F1 键位表都写 F） | [hud.gd](../scripts/ui/hud.gd#L110-L216) vs [key_bindings.gd](../scripts/ui/key_bindings.gd#L11) | 玩家按 F 无反应 → **建议立即修正** |
| 2 | **防具内容缺失**：ITEMS 无 head/body/arm/boots/cloak/ring 装备 | [campaign.gd](../data/campaign.gd#L24-L65) | `armor_reduction()`、护甲扣耐从未触发；防御链路是死代码 |
| 3 | **成长吞噬无供给**：噬刀仅认 dagger/1h_sword，掉落表无刀类武器 | [campaign.gd](../data/campaign.gd#L79) | 斩龙闪品质晋升不可达 |
| 4 | **强化经济断链**：斩龙闪单次 1500 币 vs 一局收入≈1000~1760 | [equip_tables.gd](../data/equip_tables.gd) | 强化/分解/出售难进入玩家决策 |
| 5 | **伤害公式双轨**：campaign 走区间链，独立试炼/面板仍用"武器7+力量" | [attributes.gd](../data/attributes.gd#L53-L55) | 口径两套，易遗漏 |
| 6 | **护盾视觉死代码**：红球 Mesh 创建后永久隐藏 | [player.gd](../player.gd#L60-L73) | 待 E 傲歌接入 |
| 7 | **文档过期**：CORE_LOOP_PLAYTEST 仍写"8槽装备"（hud 已 11 槽） | [CORE_LOOP_PLAYTEST.md](CORE_LOOP_PLAYTEST.md) | 阅读者误判现状 |

---

## §6 建议后续（沿用时间线）

1. **立即（下一单）**：修正 HUD/F1 "F 燧发枪"→"右键 副手武器"两处文案；同步 CORE_LOOP_PLAYTEST "8 槽"措辞
2. **短程（激活现有能力）**：补 4~6 件低品质防具 + 1 件可掉落/可购刀类武器 → 激活防御链路、护甲扣耐、成长吞噬、11 槽面板
3. **短程**：拍板逃脱币/救援/永久死亡是否纳入本版
4. **中程**：Q/E/R/F/T 五技能 + 敌人能量生态 + MP/噬灵者经济统一重算
5. **中程**：强化经济校准（提高单局收入或降低门槛）

> 注：本文件为纯审计/时间线文档，未改动任何游戏代码。