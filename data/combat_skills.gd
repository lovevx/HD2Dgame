extends RefCounted
## 当前可试玩技能的唯一数值入口；后续平衡只改这里。
const HUNTER_DRAIN_PER_SECOND := 4.0
## 猎魔附加真实伤害 = 目标最大生命 × 该比例（仅对拥有能量的敌人生效，跳过物理减免）。
const HUNTER_TRUE_RATIO := 0.02
## 法力回复：每次命中敌人回复最大法力的 1%；此外每秒回复最大法力的 0.2%。战役与试炼场统一。
const MP_ON_HIT_RATIO := 0.01
const MP_REGEN_PER_SECOND := 0.002
## 单段斩击（2026-09-20 定）：取消直踹与三段连击，普攻只有一记斜劈。
## 攻击冷却 0.6s：12 帧 @15fps 剪辑时长 0.8s，播放倍率 = 0.8/0.6 ≈ 1.33×，整段动画正好铺满冷却
## （2026-09-21 用户反馈"动作慢吞吞、不符合攻击风格"，从 0.8s / 1.0× 提速）。
## 冷却同时是"出手间隔"，所以提速后连击节奏也更跟手。
## 竖斩与横斩的刀刃接触都排在第 5 帧附近；12 帧剪辑压入 0.6s 冷却后于 0.24s 结算。
const COMBO_HIT_TIMES := [0.24]
const COMBO_COOLDOWNS := [0.6]
const COMBO_MULTIPLIERS := [1.3]
const COMBO_REACH_BONUS := [0.0]
const COMBO_ARC_HALF := [1.0]
## 横斩动画的刀刃接触约在第 5 帧；单独延后伤害帧与画面同步。
const HORIZONTAL_ATTACK_HIT_TIME := 0.24
const SHIELD_MP_COST := 14.0
const SHIELD_DURATION := 5.0
const SHIELD_COOLDOWN := 8.0
const SHIELD_BASE_CAPACITY := 20.0
const SHIELD_CAPACITY_PER_INT := 4.0
const RING_MP_COST := 24.0
const RING_COOLDOWN := 4.5
const RING_WINDUP := 0.18
const RING_RECOVERY := 0.45
const RING_RADIUS := 4.2
const RING_WEAPON_MULTIPLIER := 1.2
const WAVE_MP_COST := 12.0
const WAVE_COOLDOWN := 2.5
const WAVE_WINDUP := 0.14
const WAVE_SPEED := 18.0
const WAVE_RANGE := 9.0
const WAVE_HALF_WIDTH := 0.9
const WAVE_WEAPON_MULTIPLIER := 0.9
const PIERCE_WINDOW := 1.25
const SHADOW_MP_COST := 18.0
const SHADOW_COOLDOWN := 3.0
const SHADOW_WINDUP := 0.10
const SHADOW_MAX_DISTANCE := 4.0
const SHADOW_WEAPON_MULTIPLIER := 0.8
const SHADOW_TRUE_DAMAGE := 16.0
## 野战战技·直踢（K 键）：即时挥踢，复用图集 kick 帧；命中叠眩晕。
## 消耗走**体力**（不是法力）——与闪避同源，见上方 STAMINA_*。
const KICK_STUN := 25.0
const KICK_MULTIPLIER := 1.0
const KICK_COOLDOWN := 0.9
const KICK_HIT_TIME := 0.16  # 脚真正踢出的有效帧；按键时只起手，不提前结算

## ---------- 体力（闪避 / 直踹的能量，2026-09-22 定） ----------
## 体力条：上限由「体力」属性派生（attributes.gd 的 max_stamina），这里是消耗与回复。
## 只有闪避（剃）与直踹吃体力；平A / 环断 / 刀术仍走法力。
const STAMINA_REGEN_PER_SECOND := 20.0
const DODGE_STAMINA_COST := 30.0
const KICK_STAMINA_COST := 25.0

## ---------- 眩晕条（即时战斗的破绽资源，见 docs/REALTIME_COMBAT_EXTRACTION.md） ----------
## 小怪打满 → 停止移动，可用直踹处决；山之主打满 → 短暂硬直后恢复行动。
## **不衰减**：小怪满值保持到处决；山之主硬直结束后清零。
## 早先版本的"每秒衰减 20"会让平A（+8 / 0.6s）净亏 4 点，眩晕条永远打不满，已废弃。
const STUN_MAX := 100.0
const STUN_ON_ATTACK := 8.0            # 平A 每命中

static func shield_capacity(intelligence: int) -> float:
	return minf(100.0, SHIELD_BASE_CAPACITY + maxf(0.0, intelligence) * SHIELD_CAPACITY_PER_INT)
