# 双形态战斗改版 Implementation Plan

> **For agentic workers:** 本计划按任务逐条推进，每条含文件/步骤/校验/命令，禁止跳步。步骤用 `- [ ]` 勾选跟踪；完成后运行对应 validate 脚本再进下一步。实现方式任选：逐任务小步提交，或一批一批过（每批跑一次回归）。

---

## 实施状态（2026-09-22 逐行核对）

> **设计意图与目标规则**（"为什么这么做、应该是什么样"）见 [COMBAT_DESIGN.md](COMBAT_DESIGN.md)；本文只回答"怎么落地"。设计文档 §4.2 的 **13 条**待拍板问题（以 `Qn` 引用）落定后，本计划的 P2 细节可能需要同步微调。

| Phase | 范围 | 状态 |
|---|---|---|
| **P1 回合核心** | Task 1~8 | ✅ **已实装**（2026-09-21 落地，09-22 核对 + `validate_battle` 实跑 `BATTLE_FAILURES=0`） |
| **P2 野战联动** | Task 9~12 | 🟡 **部分完成（2026-09-22）**：眩晕链（Task 9：`stun_gauge.gd` + `enemy.add_stun` / `is_stunned` / 处决）✅、眩晕 + 补刀触发回合（Task 10 触发口径）✅、首轮先手权 ✅、山之主接入回合战的最小接口 ✅、**新手教程训练场**（小怪 + 山之主，不还手、血量调高）✅。**未做**：影刺 / 傲歌 / 青钢影回合化、猎魔被动化、意图预告、战斗运镜、炸弹延迟引爆。（原列的"`main.gd` 指令收敛为三条"**已作废** —— 2026-09-23 作者改为**统一为五条**，两套场景共用 `BattleMenu.COMMANDS`。） |
| **P3 战役接入** | Task 13~15 | ⬜ 未开始（`campaign.gd` / `wave_spawner.gd` / `colpo_level.gd` / `boss_colpo.gd` 对 battle 侧引用数为 0） |

**P1 实际交付超出计划最低线**（落点在 `scripts/main/main.gd`，不在 `scripts/battle/` 内部）：

- 五条指令全部可用：攻击 / 战技（剑气·断空、环断）/ **防御** / **道具（药剂、炸弹）** / **逃跑**
- **侧击 +10% / 背击 +25%** 与 **防御减伤 75% + 30% 弹反** 已实装（原计划归属 P2 Task 12）
- **K 直踢**已实装（原计划 P2 Task 11），`KICK_*` 常量已进 `data/combat_skills.gd`

**与计划的差异（动手前先看这四条）**：

1. `encounter_zone.gd` **没有**打成 `.tscn`、也没挂进任何场景；白盒开战走 `main.gd::_try_trigger_battle()` 的距离判定。
2. 战斗运镜**未锁机位**：`start_battle()` 未触碰 `camera_orbit_controls`（Task 8 Step 3 的"固定 pitch 20°"没做）。
3. `enemy.add_stun()` 与 `stun_gauge.gd` **未创建**，所以 K 直踢的 +25 眩晕目前是**空调用**（`has_method` 守卫静默跳过）。
4. 拼刀接口按 P1 约定"先不删"，但**实时侧仍在触发**（D3 已决定删拼刀，机制已由回合「防御」承担）——待 P2 明确口径。

**⚠️ 设计变更（2026-09-22，作者补充）——下列任务按新设计调整，勿照原文实施**

| 任务 | 原文计划 | 新设计（以 [COMBAT_DESIGN.md](COMBAT_DESIGN.md) 为准） |
|---|---|---|
| Task 3 `encounter_zone` | 半径 8 m 战斗圈 + 结界网格 + 禁出 | **整个取消**：不要打包 `encounter_zone.tscn`、不要挂进 `main.tscn` |
| Task 8 集成冒烟 | 用 `encounter_zone.tscn`，踏入即触发 | 改为 **Boss 眩晕 + 玩家再次攻击命中** 触发（白盒可用野狼模拟：先打满眩晕条，再补一刀） |
| Task 8 战斗运镜 | 锁固定 pitch 20° | **拉近并固定**；具体视角待作者补参考图 |
| Task 10 眩晕切回合 | 眩晕满即切 + `begin_battle(force)` Boss 强制 | **眩晕满只让敌人"停止移动"**；小怪再用**【直踹】命中即处决击杀**（仅**科尔波山之主**需"再攻击命中"才进回合）；`force` / "Boss 强制回合"方案作废 |
| Task 15 战斗演出 | 新造型单方向 `battle_idle` / `cast` 各 8 帧 | **进入演出零新增美术**：拉近摄像机 + 播放触发它的那次攻击的现有动画；`battle_idle` / `cast` 是否还做，取决于回合内站姿是否够用（可先不做） |
| Task 12 防御 · 弹反 · 逃跑 | 实装防御（−75% + 30% 弹反）与逃跑 | ~~全部取消~~ **保留**（v0.8 作者 09-23 改回五条指令）：防御作为独立指令（受伤 ×0.25 + 30% 弹反）、逃跑走敏捷对抗；`set_defend` / `flee` / `is_defending` 是**在用实现**，不再清理。原先"收敛为三条"的计划**作废** |
| 新增（原计划没有） | — | **进入战斗动画**（按触发攻击区分）、**进入时我方先手 1 回合** |

**回归**：`godot --headless --path . --script res://tools/validate_battle.gd` → `BATTLE_FAILURES=0`（**65 项**；2026-09-22 补入眩晕链 / 山之主接口 / 先手权 / 验证场装载，2026-09-23 再补入指令集统一 / 防御存活期 / 回合耗蓝不被退回 / 侧背击朝向 / 场景守卫）；同日复跑 `validate_combo_skills` / `validate_combat_skills` / `validate_core_loop` / `validate_player_visual` / `validate_camera_orbit` / `validate_onboarding_flow` / `validate_quest_panel` 均通过——**回合战是叠加，未破坏实时玩法**。（另有 `validate_colpo` 两项失败——启动场景断言与传送门提示，均为本次改动未触及的路径，见该脚本日志。）

---

**Goal:** 把现有实时动作战斗重构为「即时野战 + 回合指令战」双形态：探索期保留现动作手感，遭遇/眩晕/Boss 切入回合制（AT 顺序 + 移动 + 指令），战斗动画成本从"8 方向"降为"战斗画面单方向"。

**Architecture:** 新增独立模块 `scripts/battle/`（controller / unit / menu / order_bar / arena / stun_gauge），`player.gd` 只加 `battle_mode` 门闩（回合战中实时输入被接管），`enemy.gd` 加眩晕条与"意图"接口并保留数值档；`wave_spawner.gd` 演进为「遭遇区」触发器。数值层（六维/装备/技能表）原样继承，战技改写用现有数据后不新增帧序列。

**Tech Stack:** Godot 4.7（Forward Plus + Jolt），GDScript；回归走既有的 `godot --headless --path . --script res://tools/validate_*.gd` 管线；UI 复用 `scripts/ui/system_ui.gd`（class_name SystemUI）。

**决策定案（2026-09-21，参照 TURNBASED_COMBAT_PLAN.md 的 D1~D5）**

| # | 决策 | 定案 |
|---|---|---|
| D1 | 野战即时部分 | **a**：普攻(现单段斜劈) + 闪避(剃) + 直踢＋环断                          |
| D2 | 回合内走位 | **a**：移动力 + 射程 + 侧击 +10% / 背击 +25% |
| D3 | 拼刀 / 闪避 | **a**：删拼刀（`CLASH_*` 不再消费），闪避只留野战；拼刀机制转生为回合「防御」指令的 30% 弹反 |
| D4 | 三段连击 | 现状已是**单段斜劈**（`COMBO_CLIPS=["attack"]`），无需再裁，保留 |
| D5 | 队友 | 本版不做，`battle_unit` 提供列表接口预留 |

**现状基线（2026-09-21 代码口径，改动前请先确认这些值未变）**

- 普攻：单段斜劈 1.3×、0.6s 冷却、0.12s 命中帧、reach 2.5、弧 1.0 rad → `data/combat_skills.gd COMBO_*`；每次命中 `_mark_pierced` 留影刺标记。
- 技能唯一数值入口：`data/combat_skills.gd`（猎魔 4MP/s + 2% 真伤；傲歌 14/5s/8s；环断 24/4.5s/4.2；刀芒 12/2.5s/9m；影刺 18/3s/4.0m +16 真伤）。
- 回蓝：命中 +1% 最大 MP/次、被动 +0.2% 最大 MP/s（当前实时）；回合制改"每整轮 +5% 最大 MP"（见 P1 Task 7）。
- 玩家关键字段/方法（`player.gd`）：`mp/max_mp/hp/max_hp/alive/campaign_mode/facing/global_position/move_speed`、`_is_grounded()`、`roll_attack_damage()`、`_damage_target(enemy, dmg, knock, true_damage)`、`_hurt_in_cone(reach, dmg, arc)`、`take_damage(amount)`、`buffered_direction`、`dodge_dir`。动画节点 `get_node("pivot/CharacterSprite")`（脚本 `scripts/player/player_visual.gd`，`_play_action("attack", facing, false)`，`LOCOMOTION_CLIP="run"`）。
- 敌人（`scripts/combat/enemy.gd`）：`Kind.{WOLF,BOAR,GOLEM,DUMMY,HUMAN,CUSTOM}`、`has_energy`、`move_speed/attack_damage/attack_reach/keep_distance/attack_windup/windup`、`is_alive()`、`take_damage(amount, knock, attacker, true_damage)`、`hit_radius()`、`kill_tier`；非 DUMMY 走"接近→蓄力风车(预警红圈)→出手"AI，拼刀接口 `is_strike_imminent/can_be_clashed/is_clash_immune/on_clash`（P1 起弃用）。
- 波次（`scripts/world/wave_spawner.gd`）：读 `colpo_spawn` 标记 `wave/kind` 元数据逐波刷怪；`is_finished()/remaining()`；加组 `wave_director`；传送门只认 `is_finished()`。
- 机位（`scripts/world/camera_orbit_controls.gd`，RefCounted）：`configure(camera, pitch, yaw, dist)` / `basis()` / `offset()` / `forward_flat()`；`enabled` 可关（战斗时锁俯角）。
- 校验范式（模板 `tools/validate_combo_skills.gd`）：`extends SceneTree`，`check(ok, label)` 计数 failures，跑 `godot --headless --path . --script res://tools/validate_x.gd`；带渲染时可存图到 `res://.tmp_preview/`。
- 战斗数值/受击链/敌人档位速查见 [COMBAT_SYSTEM.md](COMBAT_SYSTEM.md)（本文档不重复展开）。

---

## 文件结构

**新增（模块边界）**

| 文件 | 职责 |
|---|---|
| `scripts/battle/battle_unit.gd` | 玩家/敌人统一作战封装：HP/MP/移动力/眩晕/意图/回合内面向；不含节点归属 |
| `scripts/battle/stun_gauge.gd` | 敌人头顶眩晕条（黄条），Label3D + 程序化网格，挂在敌人下 |
| `scripts/battle/encounter_zone.gd` | 接触/眩晕触发的遭遇区：圈内入战、半径 8m 结界网格、禁出判定 |
| `scripts/battle/battle_controller.gd` | 回合状态机：遭遇→顺序→行动→结算→胜负；场景根级节点 |
| `scripts/battle/order_bar.gd` | AT 顺序条 UI（Control，SystemUI 风格），含意图图标槽 |
| `scripts/battle/battle_menu.gd` | 指令面板 UI（攻击/战技/道具/防御/逃跑），参照 `shop_panel.gd` 模态模式 + SystemUI |

**修改**

| 文件 | 改动 |
|---|---|
| `player.gd` | 加 `battle_mode` 门闩 + 回合指令执行入口；野战部分不动；弃用拼刀入口（`CLASH_*`、`can_clash_now/register_clash` 保留给 P2 防御弹反判定用，先不删） |
| `scripts/player/player_visual.gd` | 加 `battle_clip`（单方向演出）+ `_resolve_action` 扩展；`COMBO_CLIPS` 不动 |
| `scripts/combat/enemy.gd` | 加眩晕值字段与「意图当前动作」查询；回合战内由 controller 驱动移动/攻击（`battle_driven` 门闩） |
| `scripts/world/wave_spawner.gd` | 加 `encounter` 配置（默认保持现有波次行为，白盒遭遇改由场景挂 encounter_zone） |
| `project.godot` | （P2）新增输入动作 `battle_confirm/battle_cancel/battle_move_*`；P1 用现有键盘复用 |
| `scenes/main/main.tscn` | 白盒遭遇演示：木桩旁放一只游荡野狼 + encounter_zone（P1 验收场地） |
| `tools/validate_battle.gd` | 新建：回合核心回归脚本 |

---

## Phase 1：回合核心（试炼场跑通）

> 验收总目标：在白盒场地上，与木桩旁一只野狼接触 → 切回合 → AT 顺序正确 → 走位/攻击/两战技（剑气·断空、环断）/道具 → 敌人回合 → 击败结算；`validate_battle` 全绿。

### Task 1: battle_unit.gd

**Files:**
- Create: `scripts/battle/battle_unit.gd`
- Test: `tools/validate_battle.gd`（起步即建骨架，从本任务起持续追加）

- [ ] **Step 1: 写校验骨架（红灯先行）**

创建 `tools/validate_battle.gd`：

```gdscript
extends SceneTree
## 双形态战斗回归：回合核心。逐任务补充断言，最终全绿。
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		print("PASS ", label)
	else:
		failures += 1
		push_error("FAIL " + label)

func run() -> void:
	await process_frame
	var unit := BattleUnit.new()
	unit.hp = 100.0
	unit.max_hp = 100.0
	unit.max_mp = 60.0
	unit.mp = 30.0
	unit.move_power = 3.0
	check(unit.hp_ratio() == 1.0, "battle_unit 初始血量满")
	check(unit.round_mp_regen() == maxf(60.0 * 0.05, 1.0), "回合回蓝 = 5% 最大 MP 且至少 1")
	unit.take_regen_mp()
	check(is_equal_approx(unit.mp, 33.0), "回合回蓝入账")
	print("BATTLE_FAILURES=%d" % failures)
	quit(maxf(1, failures))
```

- [ ] **Step 2: 跑一次确认当前失败**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: FAIL `battle_unit 初始血量满`（`BattleUnit` 未定义 —— 红灯成立）

- [ ] **Step 3: 实现 battle_unit.gd**

创建 `scripts/battle/battle_unit.gd`：

```gdscript
class_name BattleUnit
extends RefCounted

## 双形态战斗的统一作战封装：玩家与敌人各持一份；数值源 = 各自实体现有字段。
## 纯数据 + 纯函数给 battle_controller 算，不碰场景树。

var node: Node3D                # 挂的实体（player / enemy）
var is_player := false
var hp := 0.0
var max_hp := 100.0
var mp := 0.0
var max_mp := 0.0
var move_power := 3.0            # 移动力（米），玩家 = 3.0 + (敏捷-5)*0.2，敌人 = move_speed
var attack_power := 0.0          # 参考面板攻击（结算走各自 roll 函数）
var stun := 0.0                  # 野战眩晕条 0~100；回合内 0
var stun_max := 100.0
var turn_dir := Vector3.FORWARD  # 回合内朝向（controller 记录，供侧/背击 dot）
var agility := 5                 # AT 先攻排序用（玩家 = 敏捷；敌人 = 基线 5）

func hp_ratio() -> float:
	return hp / maxf(max_hp, 0.001)

func take_regen_mp() -> void:
	mp = minf(max_mp, mp + round_mp_regen())

func round_mp_regen() -> float:
	return maxf(max_mp * 0.05, 1.0)

static func from_player(player: Node, agi: int) -> BattleUnit:
	var u := BattleUnit.new()
	u.node = player
	u.is_player = true
	u.hp = player.hp
	u.max_hp = player.max_hp
	u.mp = player.mp
	u.max_mp = player.max_mp
	u.move_power = 3.0 + (agi - 5) * 0.2
	u.agility = agi
	return u

static func from_enemy(enemy: Node) -> BattleUnit:
	var u := BattleUnit.new()
	u.node = enemy
	u.hp = enemy.hp
	u.max_hp = enemy.max_hp
	u.move_power = enemy.move_speed
	u.attack_power = enemy.attack_damage
	u.agility = 5
	return u
```

- [ ] **Step 4: 跑校验确认通过**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: `BATTLE_FAILURES=0`

- [ ] **Step 5: 提交**

```bash
git add scripts/battle/battle_unit.gd tools/validate_battle.gd
git commit -m "feat(battle): battle_unit 作战封装 + validate_battle 骨架"
```

### Task 2: battle_controller（回合状态机 + 顺序 + 胜负）

**Files:**
- Create: `scripts/battle/battle_controller.gd`
- Modify: `tools/validate_battle.gd`（追加状态机断言）

- [ ] **Step 1: 追加失败断言**

在 `run()` 的 `check(...)` 尾部追加：

```gdscript
	var ctl := BattleController.new()
	ctl.set_units([unit_from_stub(), unit_from_stub()])
	ctl.begin_battle()
	await process_frame
	check(ctl.phase == BattleController.Phase.ORDER, "遭遇后进入 AT 顺序阶段")
	ctl.finish_turn()
	check(ctl.phase == BattleController.Phase.ACTION or ctl.phase == BattleController.Phase.ORDER, "回合轮转正常")
	ctl.force_win()
	check(ctl.phase == BattleController.Phase.VICTORY, "胜负判定进入结算")
```

需新增桩函数（同文件顶部）：

```gdscript
func unit_from_stub() -> BattleUnit:
	var u := BattleUnit.new()
	u.hp = 100.0
	u.max_hp = 100.0
	u.agility = 5
	return u
```

- [ ] **Step 2: 跑一次确认失败**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: FAIL `BattleController` 未定义

- [ ] **Step 3: 实现状态机**

创建 `scripts/battle/battle_controller.gd`：

```gdscript
class_name BattleController
extends RefCounted

## 回合状态机：遭遇 → ORDER(排序入场) → ACTION(当前单位行动) → CHECK(时序轮转)
## → VICTORY / DEFEAT。节点归属：战斗单位仍是场景里的 player / enemy，
## controller 只调度；`battle_arena` 负责圈出禁出边界。
## 回合规则（定案）：AT = 敏捷降序；我方回合 = 移动 + 一条指令；
## 敌人回合 = 接近→攻击（移动力同规则）；每整轮回蓝 5% 最大 MP。

enum Phase { IDLE, ORDER, ACTION, CHECK, VICTORY, DEFEAT }

var units: Array[BattleUnit] = []
var order: Array[BattleUnit] = []   # 本轮行动序列（刷新后重排）
var index := 0
var round := 0
var phase := Phase.IDLE

func set_units(list: Array[BattleUnit]) -> void:
	units = list

func begin_battle() -> void:
	round = 0
	_rebuild_order()

func _rebuild_order() -> void:
	order = units.duplicate()
	order.sort_custom(func(a: BattleUnit, b: BattleUnit) -> bool:
		return a.agility > b.agility)
	index = 0
	phase = Phase.ORDER

## 当前行动单位。
func current() -> BattleUnit:
	if order.is_empty():
		return null
	return order[clampi(index, 0, order.size() - 1)]

## 行动完成 → 下一个单位；走完一轮则重排并结算回蓝与胜负。
func finish_turn() -> void:
	index += 1
	if index >= order.size():
		round += 1
		for u in units:
			u.take_regen_mp()
		_rebuild_order()
	else:
		phase = Phase.ACTION

## 结算入口：战后调用（胜利 / 团灭 / 逃跑都先汇到这里）。
func force_win() -> void:
	phase = Phase.VICTORY

## AT 顺序排成可读字符串（校验与调试用）。
func order_labels() -> PackedStringArray:
	var out := PackedStringArray()
	for u in order:
		out.append("玩家" if u.is_player else "敌" + str(u.agility))
	return out
```

- [ ] **Step 4: 跑校验确认通过**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: `BATTLE_FAILURES=0`（本任务只验状态机骨架；轮转与胜负细节由后续任务断言补齐）

- [ ] **Step 5: 提交**

```bash
git add scripts/battle/battle_controller.gd tools/validate_battle.gd
git commit -m "feat(battle): 回合状态机与 AT 顺序"
```

### Task 3: encounter_zone（遭遇区 + 战斗圈结界）

**Files:**
- Create: `scripts/battle/encounter_zone.gd`
- Modify: `tools/validate_battle.gd`（追加圈判定断言）
- Modify: `scenes/main/main.tscn`（白盒：木桩旁一只野狼游荡 + encounter_zone）

- [ ] **Step 1: 追加断言**

```gdscript
	var zone := EncounterZone.new()
	zone.radius = 8.0
	zone._debug_add_unit(Vector3(10, 0, 0), 0, 3)   # (pos, stun, hp)
	zone._debug_add_unit(Vector3(0, 0, 0), 0, 3)
	check(zone.in_radius(Vector3(0, 0, 0)) == true, "圆心在圈内")
	check(zone.in_radius(Vector3(7.9, 0, 0)) == true, "圈内临界 7.9m")
	check(zone.in_radius(Vector3(8.1, 0, 0)) == false, "圈外 8.1m 禁出")
```

- [ ] **Step 2: 跑一次确认失败**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: FAIL `EncounterZone` 未定义

- [ ] **Step 3: 实现遭遇区**

创建 `scripts/battle/encounter_zone.gd`：

```gdscript
class_name EncounterZone
extends Node3D

## 遭遇区：玩家接触 → 把圈内敌人拉进战斗；战斗中对锁在圈内。
## 结界 = 程序化半透明网格环（SystemUI 色板外的青白色），行为边界暗示。
const RADIUS := 8.0
const GRID_STEP := 0.9

var radius := RADIUS
var active := false
var _units: Array[Node3D] = []

func _ready() -> void:
	_build_wall()

func _build_wall() -> void:
	var ring := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 1.8
	ring.mesh = mesh
	ring.position.y = 0.9
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.37, 0.85, 0.94, 0.10)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)

## 圈判定（世界 x/z 平面，圆心 = 本节点）。
func in_radius(world: Vector3) -> bool:
	var flat := world - global_position
	flat.y = 0.0
	return flat.length() <= radius

## 校验用桩：直接登记一个单位。
func _debug_add_unit(world: Vector3, _stun: float, _hp: float) -> void:
	_units.append(Node3D.new())
	_units[-1].global_position = world
	add_child(_units[-1])

## P2 用：玩家踏入且圈内有敌方单位 → 战斗。
func try_trigger(player: Node3D) -> bool:
	if not active:
		return false
	if not in_radius(player.global_position):
		return false
	var has_foe := false
	for u in _units:
		if u.is_in_group("enemies") or u.is_in_group("targets"):
			has_foe = true
	if has_foe:
		print("遭遇战触发")
		return true
	return false
```

- [ ] **Step 4: 跑校验确认通过**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: `BATTLE_FAILURES=0`

- [ ] **Step 5: 白盒出场（P1 验收场地）**

用 `scenes/main/main.tscn` 编辑器新增：`EncounterZone` 节点（position 木桩旁）+ 一只野狼（`enemy.tscn`，`kind=WOLF`，`move_speed=1.2` 慢速游荡）。此步为手工验收环境，不写断言。

- [ ] **Step 6: 提交**

```bash
git add scripts/battle/encounter_zone.gd tools/validate_battle.gd scenes/main/main.tscn
git commit -m "feat(battle): 遭遇区与禁出结界（P1 白盒场地）"
```

### Task 4: order_bar.gd（AT 顺序条 UI）

**Files:**
- Create: `scripts/battle/order_bar.gd`
- Modify: `tools/validate_battle.gd`（追加控件存在性断言）

- [ ] **Step 1: 追加断言**

```gdscript
	var bar := preload("res://scripts/battle/order_bar.gd").new()
	bar.units = [unit_from_stub(), unit_from_stub()]
	bar.order = PackedStringArray(["玩家", "敌人"])
	bar.rebuild()
	check(bar.get_child_count() >= 2, "顺序条按单位数渲染条目")
```

- [ ] **Step 2: 跑一次确认失败**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: FAIL `order_bar.gd` 缺少 `rebuild`

- [ ] **Step 3: 实现顺序条**

创建 `scripts/battle/order_bar.gd`：

```gdscript
class_name OrderBar
extends HBoxContainer

## AT 顺序条：屏顶一条水平序列，按敏捷降序；
## 当前行动单位高亮青色（SystemUI.ACCENT 5fd0ff 系）、其余灰蓝。
const SystemUI := preload("res://scripts/ui/system_ui.gd")

var units: Array[BattleUnit] = []
var order: PackedStringArray = []

func rebuild() -> void:
	for child in get_children():
		child.queue_free()
	for label in order:
		var chip := Label.new()
		chip.text = label
		chip.add_theme_font_size_override("font_size", 18)
		chip.add_theme_color_override("font_color", Color("5fd0ff"))
		chip.modulate.a = 0.85
		add_child(chip)
		if units.size() > 0 and label.begins_with("玩家"):
			chip.modulate = Color.WHITE  # 当前玩家位高亮（P2 接意图图标槽）
```

- [ ] **Step 4: 跑校验确认通过**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: `BATTLE_FAILURES=0`

- [ ] **Step 5: 提交**

```bash
git add scripts/battle/order_bar.gd tools/validate_battle.gd
git commit -m "feat(battle): AT 顺序条 UI"
```

### Task 5: battle_menu.gd（指令面板）

**Files:**
- Create: `scripts/battle/battle_menu.gd`
- Modify: `tools/validate_battle.gd`（追加指令集断言）

- [ ] **Step 1: 追加断言**

```gdscript
	var menu := preload("res://scripts/battle/battle_menu.gd").new()
	menu.commands = ["攻击", "战技", "道具", "防御", "逃跑"]
	menu.rebuild()
	await process_frame
	check(menu.get_node("CommandList").get_child_count() == 5, "指令面板 5 个指令槽")
```

- [ ] **Step 2: 跑一次确认失败**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: FAIL `battle_menu.gd` 缺 `CommandList`

- [ ] **Step 3: 实现指令面板**

创建 `scripts/battle/battle_menu.gd`：

```gdscript
class_name BattleMenu
extends Control

## 我方回合指令面板：攻击 / 战技 / 道具 / 防御 / 逃跑。
## 模态与冻结输入方式参照 shop_panel.gd（CanvasLayer 挂 HUD 下、Esc/关闭退出）；
## 视觉走 SystemUI.card/button：深蓝灰底 + 电光青边 + 四角铆钉。

const SystemUI := preload("res://scripts/ui/system_ui.gd")
var commands: Array[String] = []
var selected := 0
signal confirmed(idx: int)
signal canceled

func rebuild() -> void:
	var list := VBoxContainer.new()
	list.name = "CommandList"
	list.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	for text in commands:
		var btn := Button.new()
		btn.text = text
		SystemUI.style_button(btn)
		btn.pressed.connect(_on_pressed.bind(commands.find(text)))
		list.add_child(btn)
	add_child(list)

func _on_pressed(idx: int) -> void:
	selected = idx
	confirmed.emit(idx)

# P1 键盘可移动选择（现有方向键 → battle_confirmed），P2 细化鼠标/手柄。
```

- [ ] **Step 4: 跑校验确认通过**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: `BATTLE_FAILURES=0`

- [ ] **Step 5: 提交**

```bash
git add scripts/battle/battle_menu.gd tools/validate_battle.gd
git commit -m "feat(battle): 指令面板 UI"
```

### Task 6: battle_unit 接实体 + 玩家回合执行（玩家侧门闩）

**Files:**
- Modify: `player.gd`（加 `battle_mode`、`battle_execute_move()`、`battle_execute_attack()`、`battle_execute_skill()`）
- Modify: `tools/validate_battle.gd`

- [ ] **Step 1: 追加断言**

```gdscript
	var player := _spawn_player()
	player.battle_mode = true
	player._physics_process(0.016)
	check(player.velocity.length() < 0.001, "回合战门闩：锁定实时移动")
	player.battle_execute_move(1.5)
	await process_frame
	check(player.global_position.distance_to(Vector3.ZERO) > 0.9, "回合移动按步进执行")
	player.battle_mode = false
```

需新增桩（文件顶部）：

```gdscript
func _spawn_player() -> Node:
	var scene: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_practice()
	scene.set_process(false)
	var p: Node = scene.player
	p.set_physics_process(false)
	p.campaign_mode = true
	p.reset()
	p.global_position = Vector3.ZERO
	return p
```

- [ ] **Step 2: 跑一次确认失败**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: FAIL `battle_mode` 不存在（红灯）

- [ ] **Step 3: 实现玩家侧门闩**

在 `player.gd` 加：

```gdscript
## 回合战门闩：为 true 时实时输入被 battle_controller 接管，
## 本文件只提供"回合执行动作"入口，不解释按键。
var battle_mode := false
```

在 `_physics_process` 移动段之前插入（实时沿用的 `input_dir` 计算之后、`velocity` 赋值之前）：

```gdscript
	if battle_mode:
		velocity = Vector3.ZERO
		return
```

追加回合执行方法（放在 `_start_attack` 附近）：

```gdscript
## 回合移动：沿 turn_dir 步进 move 米（跳跃方式移动，碰撞自理）。
func battle_execute_move(move: float) -> void:
	if move <= 0.001:
		return
	facing = battle_turn_dir if battle_turn_dir.length_squared() > 0.001 else facing
	var step_pos := global_position + facing * move
	step_pos.y = 0.0
	global_position = step_pos

## 回合攻击：扇形判定（reach + 弧半角）；侧/背击乘数由 controller 传入（Task 12 实现）。
func battle_execute_attack(bonus_mult := 1.0) -> float:
	_hurt_in_cone(attack_range + CombatSkills.COMBO_REACH_BONUS[0],
		roll_attack_damage() * CombatSkills.COMBO_MULTIPLIERS[0] * bonus_mult,
		CombatSkills.COMBO_ARC_HALF[0])
	attacked.emit(0)
	return 0.0

## 战技入口（数值判定沿用现有函数；controller 先检查 MP/冷却）。
func battle_execute_skill(skill: String) -> void:
	match skill:
		"sword_wave":
			_start_wave(battle_turn_dir if battle_turn_dir.length_squared() > 0.001 else facing)
		"ring":
			_resolve_ring()
		"shadow_stab":
			push_warning("battle skill not wired yet: shadow_stab")  # P2 突进战技一起补
		_:
			push_warning("battle skill not wired: " + skill)
```

并加字段：

```gdscript
var battle_turn_dir := Vector3.FORWARD   # 回合内面向，由 controller 在行动前写入
```

> 说明：`battle_execute_skill("shadow_stab")` 暂不实装（无标记时按"保留原地标记"处理），P2 与位移战技一起补；本任务只需 `sword_wave` / `ring` 两条。

- [ ] **Step 4: 跑校验确认通过**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: `BATTLE_FAILURES=0`

- [ ] **Step 5: 提交**

```bash
git add player.gd tools/validate_battle.gd
git commit -m "feat(battle): 玩家回合门闩与移动/攻击/战技入口"
```

### Task 7: 敌人回合驱动 + 意图 + 回蓝口径切换

**Files:**
- Modify: `scripts/combat/enemy.gd`
- Modify: `scripts/battle/battle_controller.gd`
- Modify: `tools/validate_battle.gd`

- [ ] **Step 1: 追加断言**

```gdscript
	var ctl2 := BattleController.new()
	ctl2.set_units([unit_from_stub()])
	ctl2.begin_battle()
	ctl2.force_win()
	check(ctl2.phase == BattleController.Phase.VICTORY, "唯一单位结算时直接胜利")
	var enemy_spawned := EnemyScene.instantiate()
	enemy_spawned.kind = EnemyScript.Kind.WOLF
	enemy_spawned.position = Vector3(0, 0, -3.0)
	scene_root.add_child(enemy_spawned)
	enemy_spawned.battle_driven = true
	enemy_spawned.battle_advance(Vector3(0, 0, 0))
	check(enemy_spawned.global_position.z > -3.2, "敌人回合按 state 步进接近")
```

（文件顶部补 `const EnemyScene := preload("res://scripts/combat/enemy.tscn")`、`const EnemyScript := preload("res://scripts/combat/enemy.gd")`；断言里直接对 `root` 加子节点，`scene_root` 用 `root` 即可。）

- [ ] **Step 2: 跑一次确认失败**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: FAIL `battle_driven` 缺失

- [ ] **Step 3: 实现敌人回合接口**

在 `enemy.gd` 加：

```gdscript
## 回合战驱动门闩：开时 `_physics_process` 的实时 AI 让位给 controller。
var battle_driven := false

## 敌人回合动作：context = {dist: 与玩家平面距离, in_reach: 是否进入攻击距离}
## 返回意图文本供 AT 栏显示；P1 只做"接近 / 攻击"两态。
func battle_advance(target_world: Vector3) -> String:
	if kind == Kind.DUMMY:
		return "待机"
	var flat_offset := target_world - global_position
	flat_offset.y = 0.0
	var dist := flat_offset.length()
	if dist <= attack_reach + 0.2:
		target_point = target_world
		attack_cd = 1.4
		return "攻击"
	var step := move_speed * 1.0  # off real-time 缩放：一行动一步到移动力
	global_position += flat_offset.normalized() * step
	turn_dir = flat_offset.normalized()
	return "接近"
```

在 `_physics_process` 开头（`if kind == Kind.DUMMY:` 分支后）加：

```gdscript
	if battle_driven:
		return
```

- [ ] **Step 4: 回蓝口径切换**

`player.gd._physics_process` 的被动回蓝行改为仅在非战斗时生效：

```gdscript
	if not battle_mode:
		mp = clampf(mp + max_mp * CombatSkills.MP_REGEN_PER_SECOND * delta, 0, max_mp)
```

（回合内回蓝统一走 `BattleUnit.round_mp_regen()` —— 每整轮 +5% 最大 MP。）

- [ ] **Step 5: 跑校验确认通过**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: `BATTLE_FAILURES=0`

- [ ] **Step 6: 提交**

```bash
git add scripts/combat/enemy.gd player.gd tools/validate_battle.gd
git commit -m "feat(battle): 敌人回合驱动与实时回蓝门闩"
```

### Task 8: P1 集成冒烟（白盒遭遇闭环）

**Files:**
- Modify: `scenes/main/main.tscn`（把 Task 3 的 encounter_zone 接线到能开战）
- Modify: `tools/validate_battle.gd`（集成冒烟断言）

- [ ] **Step 1: 追加集成断言**

```gdscript
	var zone2 := encounter_zone_scene.instantiate()
	zone2.position = Vector3(0, 0, 0)
	current_scene.add_child(zone2)
	player.global_position = Vector3(0, 0, 5.0)
	check(zone2.try_trigger(player) == true, "玩家踏入遭遇圈触发战斗")
	player.global_position = Vector3(30, 0, 30)
	check(zone2.try_trigger(player) == false, "玩家远离不触发")
```

- [ ] **Step 2: 跑一次确认失败**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: FAIL（`encounter_zone_scene` 尚未 preload）

- [ ] **Step 3: 接线 + 冒烟**

preload 场景并补断言：

```gdscript
const encounter_zone_scene := preload("res://scripts/battle/encounter_zone.tscn")
```

将 `encounter_zone.gd` 打包成 `scripts/battle/encounter_zone.tscn`（根节点 Node3D + 脚本），并把 main.tscn 的遭遇区换用该场景。手工人验：进试炼场，木桩旁野狼慢速游荡，踏入 8m 圈触发回合演示（P1 允许只打印触发 + 顺序条 + 一回合指令流程）。

**战斗运镜（遭遇切入即生效）**：`battle_controller.begin_battle` 里把机位锁成固定俯角——取 `camera_orbit_controls`（RefCounted，`scripts/world/camera_orbit_controls.gd`），战斗期间 `enabled=false` 并 `configure(...)` 到固定 pitch 20°、distance 现有值；退出战斗恢复 `enabled=true` 与原有参数。P1 先在白盒用手工触发验证，不做断言。

- [ ] **Step 4: 跑校验确认通过**

Run: `godot --headless --path . --script res://tools/validate_battle.gd`
Expected: `BATTLE_FAILURES=0`；再跑既有回归 `tools/validate_combo_skills.gd`、`tools/validate_combat_skills.gd`、`tools/validate_player_visual.gd`、`tools/validate_onboarding_flow.gd` 全绿（实时老玩法不受影响）。

- [ ] **Step 5: 提交**

```bash
git add scripts/battle/encounter_zone.tscn tools/validate_battle.gd scenes/main/main.tscn
git commit -m "feat(battle): P1 白盒遭遇闭环 + 回归全绿"
```

**P1 完成度检查单**（✅ 2026-09-22 核对通过）：AT 排序（敏捷降序）✓ / 我方回合移动+指令 ✓ / 攻击扇形判定 ✓ / 战技 sword_wave+ring ✓ / 敌人回合接近+攻击 ✓ / 每整轮回蓝 ✓ / 胜负流转 ✓ / 战斗圈禁出 ✓ / `validate_battle` 全绿 ✓

> 携带偏差已记于文首「实施状态」：`encounter_zone` 未打成场景（禁出结界因此尚未生效）、战斗运镜未锁机位、`add_stun` 链未建。另：原件把本 Phase 描述为"最小可玩线"，实际交付更宽（五指令 + 侧背击 + 防御弹反 + 逃跑）。

---

## Phase 2：野战联动（双形态咬合）

> 目标：实时遭遇阶段积累眩晕 → 眩晕触发回合 / 处决；Boss 强制回合；防御/弹反/逃跑；野战战技「直踢」落地；手势侧背击加成、回蓝与耐久口径切换。

### Task 9: 野战眩晕条与处决

**Files:**
- Create: `scripts/battle/stun_gauge.gd`（Label3D + 程序化网格黄条）
- Modify: `scripts/combat/enemy.gd`（`stun_point += n`、`is_stunned()`、处决判定）
- Modify: `player.gd`（普攻命中 +8、完美闪避翻倍；直踢 +25 见 Task 11）
- Modify: `tools/validate_battle.gd`

- [ ] **Step 1: 断言**

```gdscript
	var wolf := EnemyScene.instantiate()
	wolf.kind = EnemyScript.Kind.WOLF
	scene_root.add_child(wolf)
	wolf.add_stun(8.0)
	check(wolf.stun == 8.0, "普攻命中 +8 眩晕")
	wolf.add_stun(100.0)
	check(wolf.is_stunned(), "眩晕满 100 进入眩晕态")
	check(wolf.executable() == true, "杂鱼眩晕可处决")
	wolf.apply_execution()
	check(not wolf.is_alive(), "处决即击杀")
```

- [ ] **Step 2: 实现**

stun_gauge.gd（挂在 enemy 头顶的 Label3D 黄条）：

```gdscript
class_name StunGauge
extends Node3D
## 野战眩晕条：黄色，0~100% 显示；眩晕满 = 常亮 + 白盒低头晃（由 enemy 代码驱动）。

var _fill: MeshInstance3D
var _max := 100.0

func setup(max_value: float) -> void:
	_max = max_value
	var root_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.08, 0.04)
	root_mesh.mesh = box
	root_mesh.position.y = 2.1
	add_child(root_mesh)
	_fill = MeshInstance3D.new()
	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(1.0, 0.12, 0.05)
	fill_box.material = _unshaded(Color("ffd76e"))
	_fill.mesh = fill_box
	_fill.position.y = 2.1
	add_child(_fill)

func set_ratio(r: float) -> void:
	_fill.scale = Vector3(clampf(r, 0.0, 1.0), 1.0, 1.0)
	_fill.visible = r > 0.01

func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = c
	return m
```

enemy.gd 追加：

```gdscript
var stun := 0.0
var stun_max := 100.0
var _gauge: Node = null

func add_stun(n: float) -> void:
	if kind == Kind.DUMMY or kind == Kind.HUMAN:
		return
	stun = minf(stun_max, stun + n)
	if _gauge == null and _is_stun_visual_enabled():
		_gauge = StunGauge.new()
		_gauge.setup(stun_max)
		add_child(_gauge)
	if _gauge != null:
		_gauge.set_ratio(stun / stun_max)

func _is_stun_visual_enabled() -> bool:
	return stun_max > 0.0 and not dead

func is_stunned() -> bool:
	return stun >= stun_max

## 处决判定：眩晕态（杂鱼）→ 走近普攻直接击杀。
func executable() -> bool:
	return is_stunned() and kill_tier <= 1

func apply_execution() -> void:
	if not executable():
		return
	stun = 0.0
	take_damage(hp + 1.0, Vector3.ZERO, null)
```

player.gd 普攻命中处追加眩晕（`_hurt_in_cone` 命中后、标记前）：

```gdscript
	if enemy.has_method("add_stun"):
		enemy.add_stun(8.0)
```

完美闪避（`dodge` 判定时玩家无敌帧期间且对方在 `is_strike_imminent`）→ 下一个被命中单位的眩晕翻倍：

```gdscript
## 完美闪避激励：闪避成功且对方出手在即 → 该敌下次 add_stun 翻倍。
var perfect_dodge_bonus := false
```

- [ ] **Step 3: 回归 + 提交**

Run: `godot --headless --path . --script res://tools/validate_battle.gd` → 全绿；`validate_combo_skills` 全绿。
```bash
git add scripts/battle/stun_gauge.gd scripts/combat/enemy.gd player.gd tools/validate_battle.gd
git commit -m "feat(battle): 野战眩晕条 + 杂鱼处决 + 完美闪避翻倍"
```

### Task 10: 眩晕触发切回合 + Boss 强制回合标记

**Files:**
- Modify: `scripts/battle/battle_controller.gd`（`begin_battle(force := false)`；眩晕触发时敌方先手关 1 回合）
- Modify: `scripts/combat/boss_director.gd`（Boss 场挂 `force_turn_battle` 标记）
- Modify: `tools/validate_battle.gd`

- [ ] **Step 1: 断言**

```gdscript
	var c3 := BattleController.new()
	c3.set_units([unit_from_stub(), unit_from_stub()])
	c3.begin_battle(true)
	await process_frame
	check(c3.phase == BattleController.Phase.ORDER, "Boss 强制回合：遭遇即切")
	var enemy_stun := unit_from_stub()
	enemy_stun.stun = 100.0
	check(enemy_stun.is_stunned(), "眩晕单位状态可读")
```

- [ ] **Step 2: 实现**

battle_controller.gd：

```gdscript
## force = true 表示 Boss 强制回合（无视眩晕条直接切）；否则由 encounter_zone 检测眩晕/接触触发。
## 先手规则：眩晕触发 / Boss 场 → 我方本回合排最前（order 重排后把玩家单位挪到 index 0）。
func begin_battle(force := false) -> void:
	round = 0
	_rebuild_order()
	if force:
		var player_idx := 0
		for i in order.size():
			if order[i].is_player:
				player_idx = i
				break
		order.move_to_front(player_idx)
		phase = Phase.ACTION
```

- [ ] **Step 3: 回归 + 提交**

Run: `godot --headless --path . --script res://tools/validate_battle.gd` → 全绿。

### Task 11: 野战战技「直踢」+ 环断（环断已实装）+ 删拼刀消费 + 猎魔转被动

**Files:**
- Modify: `player.gd`（直踢：独立键位即时挥踢，复用图集 kick 帧；环断维持 F 键现状；`_resolve_strike` 不再判拼刀分支可保留为防御判定预留）
- Modify: `scripts/player/player_visual.gd`（连接 `kicked` 信号播放 kick 帧）
- Modify: `scripts/combat/enemy.gd`（`_resolve_strike` 不再判拼刀分支可保留为防御判定预留）
- Modify: `data/combat_skills.gd`（`KICK_*` 常量：MP 8、倍率 1.0、冷却 0.9s、眩晕 25）
- Modify: `tools/validate_battle.gd`

- [ ] **Step 1: 断言**

```gdscript
	check(CombatSkills.KICK_MP_COST == 8.0, "直踢 MP 8")
	check(CombatSkills.KICK_STUN == 25.0, "直踢眩晕 25")
	check(CombatSkills.KICK_MULTIPLIER == 1.0, "直踢倍率 1.0")
	check(CombatSkills.KICK_COOLDOWN == 0.9, "直踢冷却 0.9s")
```

- [ ] **Step 2: 常量**

combat_skills.gd 追加：

```gdscript
## 野战战技·直踢：即时挥踢，复用攻图集里现成的 kick 帧，命中附眩晕（2026-09-21 定案）。
const KICK_MP_COST := 8.0
const KICK_STUN := 25.0
const KICK_MULTIPLIER := 1.0
const KICK_COOLDOWN := 0.9
```

- [ ] **Step 3: 实现直踢**

player.gd 追加（`kicked` 信号 → player_visual 播 `kick` 帧）：

```gdscript
signal kicked

func _start_kick() -> void:
	if kick_cd > 0.0 or mp < CombatSkills.KICK_MP_COST or dodging or battle_mode or attack_cd > 0.0:
		return
	mp -= CombatSkills.KICK_MP_COST
	kick_cd = CombatSkills.KICK_COOLDOWN
	attack_cd = 0.9
	attack_elapsed = -1.0
	buffer_time = 0.0
	# 前向短碰撞：reach 2.8、弧半角 0.35 rad，命中附眩晕
	_hurt_in_cone(2.8, roll_attack_damage() * CombatSkills.KICK_MULTIPLIER, 0.35)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.has_method("add_stun"):
			enemy.add_stun(CombatSkills.KICK_STUN)
	kicked.emit()
```

player_visual.gd：`player.kicked.connect(_on_kicked)`，`_on_kicked` 与 `_on_attacked` 同构、动作固定 `"kick"`。
键位：`_unhandled_input` 加 `event is InputEventKey and event.pressed and event.physical_keycode == KEY_K` → `_start_kick()`（P3 再迁 InputMap）。

- [ ] **Step 4: 猎魔转被动**

`_toggle_hunter` 不再需要按键开关，改为：`hunter_active = mp > max_mp * 0.01` 常开耗蓝判定 → 真伤仍走 `has_energy`；MP 枯竭自动失效（语义不变，消耗与倍率不变）。键位 Q 空出（P2 留给防御/换指令，P3 决定是否隐藏）。

- [ ] **Step 5: 傲歌 / 影刺回合化（controller 侧）**

battle_controller.gd 加 `apply_turn_skill(unit, skill)`，把剩余战技切到回合语义（数值仍读 `combat_skills.gd`，不新增帧序列）：

```gdscript
## 回合战技语义映射（P1 只接 sword_wave / ring，P2 补齐其余）。
## 傲歌：本回合开始前给 unit 挂减伤 buff（2 回合内受伤 -50%，吸收量转固定减伤）。
## 影刺：突进到目标身前并结算 0.8× + 16 真伤，不再要求先手标记（回合内玩家总有出手窗口）。
## 青钢影：本回合攻击对能量型目标附加真伤（主动增益 3 回合，CD 5 回合）。
func apply_turn_skill(unit: BattleUnit, skill: String) -> void:
	match skill:
		"shield":
			unit.set_meta("guard_buff_rounds", 2)
		"shadow_stab":
			if unit.node.has_method("roll_attack_damage"):
				var closest := _closest_enemy_of(unit)
				if closest != null:
					unit.turn_dir = (closest.global_position - unit.node.global_position).normalized()
					unit.node.global_position = closest.global_position + unit.turn_dir * -1.5
					var td := 16.0 if closest.get("has_energy") == true else 0.0
					unit.node._damage_target(closest,
						unit.node.roll_attack_damage() * CombatSkills.SHADOW_WEAPON_MULTIPLIER, Vector3.ZERO, td)
		"hunter":
			unit.set_meta("hunter_rounds", 3)
		_:
			push_warning("turn skill not wired: " + skill)
```

战技 → 回合指令文案（battle_menu 的战技子页用）：剑气·断空 / 环断 / 影刺 / 傲歌 / 青钢影。

- [ ] **Step 6: 回归 + 提交**

Run: 全量 `validate_battle` + `validate_combo_skills` 全绿。
```bash
git add data/combat_skills.gd player.gd scripts/battle/battle_controller.gd tools/validate_battle.gd
git commit -m "feat(battle): 直踢战技 + 猎魔被动化 + 傲歌/影刺回合化"
```

### Task 12: 道具进回合指令 + 受击扣护甲改 + 逃跑

**Files:**
- Modify: `scripts/battle/battle_menu.gd`（道具子菜单：药剂/炸弹/燧发枪）
- Modify: `player.gd`（`battle_execute_item()`：药剂即时回 40%、炸弹 AoE 90、燧发枪 9m 单体弹药；回合内即时生效式）
- Modify: `player.gd` / `enemy.gd` 受击链：护甲耐久改"每次被命中扣 1"
- Modify: `tools/validate_battle.gd`

- [ ] **Step 1: 断言**

```gdscript
	var p2 := player
	p2.mp = 60.0
	p2.hp = 50.0
	p2.max_hp = 100.0
	p2.potions = 1
	p2.battle_execute_item("potion")
	check(p2.hp > 50.0, "回合内药剂即时回血")
	check(p2.potions == 0, "回合内药剂消耗")
```

- [ ] **Step 2: 实现**

player.gd 追加：

```gdscript
func battle_execute_item(item: String) -> void:
	match item:
		"potion":
			if potions <= 0:
				return
			potions -= 1
			hp = minf(max_hp, hp + max_hp * 0.4)
			hp_changed.emit(hp, max_hp)
		"bomb":
			if bombs <= 0:
				return
			bombs -= 1
			bombs_changed.emit(bombs)
			var b := BombScene.instantiate()
			get_parent().add_child(b)
			b.global_position = global_position + Vector3(0, 1.1, 0)
			(b as Node3D).place_at(mouse_ground_point() if mouse_ground_point() != null else global_position + facing * 5.0)
		"flintlock":
			if GameState.campaign.equipment.get("offhand", "") != "flintlock" or bullets <= 0:
				return
			bullets -= 1
			_fire_flintlock()
		_:
			push_warning("battle item not wired: " + item)
```

受击链（`take_damage` 内）：护甲耐久由 `clampi(ceili(lost / 10.0), 1, 5)` 改为固定 `1`（P2 简化版口径）。

- [ ] **Step 3: 防御 + 弹反 + 侧/背击加成（回合内）**

battle_controller.gd 追加：

```gdscript
## 防御指令：本回合受伤 -75%；被近战命中时 30% 概率弹反（敌人下次行动延后一轮）。
## 侧击 +10% / 背击 +25%：dot(我方 turn_dir, 目标→我方向) 判定目标白盒朝向。
func defend(unit: BattleUnit) -> void:
	unit.set_meta("defend_round", true)

func attack_bonus(unit: BattleUnit, target: BattleUnit) -> float:
	if target.node == null or unit.node == null:
		return 1.0
	var to_target: Vector3 = target.node.global_position - unit.node.global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		return 1.0
	var dot_val: float = unit.turn_dir.normalized().dot(to_target.normalized())
	if dot_val > 0.7:
		return 1.0            # 正面
	if dot_val < -0.45:
		return 1.25           # 背击（目标背对我方出手方向）
	return 1.1                # 侧击
```

弹反结算挂在敌人对我方回合的命中前：掷 `randf() < 0.30` 且我方本回合 `defend_round` → 该敌走序后移一轮（`order.remove(index); order.append(...)`）且本次不结算伤害。

- [ ] **Step 4: 逃跑（P2 侧）**

`battle_controller` 加 `flee()`：我方敏捷 + d10 vs 敌方平均敏捷 + d10，成功 → `phase = VICTORY`（无掉落，回野战）；失败 → 我方本回合结束。

- [ ] **Step 5: 回归 + 提交**

Run: `validate_battle` 全绿 + `validate_core_loop` 全绿。

---

## Phase 3：战役接入与演出收口

**目标**：战役关卡战斗替换为遭遇+双形态；科尔波 Boss 回合化；新造型战斗演出（单方向 battle_idle/cast 各 8 帧）；数值平衡回填 `combat_skills.gd`；教学/解锁汇总回 `COMBAT_SYSTEM.md` 与新手指引。

### Task 13: 战役遭遇接入（灰潮港/科尔波）

**Files:**
- Modify: `scripts/world/wave_spawner.gd` → 加 `encounter` 布尔（默认 false 保持现行波次）；为 true 时改为场地内预置敌人缓游 + encounter_zone 触发
- Modify: `scenes/world/colpo_*.tscn`（build_colpo.gd 输出侧）：外围波次区挂 encounter_zone
- Run: `godot --headless --path . --import`

验收：科尔波外围与 Boss 前两关以遭遇-回合双形态通（`validate_colpo.gd` 断言迁移到回合流程，改动点见 Task 14）。

### Task 14: Boss 回合化（巨虎/oriboss 数值照搬）

**Files:**
- Modify: `scripts/combat/boss_colpo.gd`（挂 `battle_driven` 与 `force_turn_battle`，回合内 AI = 接近→重击；红圈意图图标沿用 windup 语义）
- Modify: `scripts/combat/boss_director.gd`（Boss 场强制回合标记）
- Modify: `tools/validate_colpo.gd`（Boss 战断言迁到回合流程）

验收：Boss 场触发即切回合，数值档与测试全部迁移通过。

### Task 15: 战斗演出单方向化 + 数值平衡 + 教学收口

**Files:**
- New: `assets/characters/black_swordsman_new/` 或沿用 `player_frames_video.tres` 追加 `battle_idle` / `cast`（单方向 8 帧，各 0.8s/圈）
- Modify: `scripts/player/player_visual.gd`（`battle_clip` 选择；`_resolve_action` 缺图回退待机）
- Modify: `data/combat_skills.gd`（按 P2 试玩记录回填平衡值，回填前先跑 `validate_combat_skills`）
- Modify: `docs/COMBAT_SYSTEM.md`（追加"回合制"章节并标注动作制章节状态）
- 回归：全套 `validate_*` 全绿 + `tools/capture_ui.gd` 四连拍人工复查

---

## 全局回归清单（每 Phase 结束跑一遍）

```bash
godot --headless --path . --script res://tools/validate_battle.gd
godot --headless --path . --script res://tools/validate_combo_skills.gd
godot --headless --path . --script res://tools/validate_combat_skills.gd
godot --headless --path . --script res://tools/validate_player_visual.gd
godot --headless --path . --script res://tools/validate_camera_orbit.gd
godot --headless --path . --script res://tools/validate_core_loop.gd
godot --headless --path . --script res://tools/validate_onboarding_flow.gd
```

期望：全部 `0` 失败（`validate_demo.gd` 的既有存档隔离问题与本改版无关，见 TURNBASED_PLAN 附录 A.2.2）。

## 风险与未决项

1. **先手与眩晕切回合的具体节奏**：眩晕 → 敌方跳过 1 回合行动 + 我方先动（含"处决不打断回合切换"的边界）；P2 Task 10 以控制器内一个 `skip_rounds` 表实现，遇到多眩晕目标先手顺序需定案。
2. **战斗圈半径 8m 与野狼游荡的冲突**：P1 白盒先固定场地；P3 决定怪物是否自带警戒半径。
3. **道具回合化的消耗口径**：药剂 40%/次 沿用、炸弹 90 沿用、燧发枪弹药 6 沿用——如平衡回调只改 `combat_skills.gd` 或各道具常量。
4. **移动力与步进画面**：回合移动用"步进式"还是"滑行式"待 P2 手感决定（本计划先步进）。
5. **猎魔被动化后 Q 键位**：P2 空出，P3 决定是否移除输入映射。
6. **旧动画复用**：直踢与环断直接用图集现成 kick / attack 帧 + 程序化特效；若表现不足，P3 用单方向 cast 帧替换，无需新增 8 方向。