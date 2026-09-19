extends RefCounted
## 当前可试玩技能的唯一数值入口；后续平衡只改这里。
const HUNTER_DRAIN_PER_SECOND := 4.0
## 猎魔附加真实伤害 = 目标最大生命 × 该比例（仅对拥有能量的敌人生效，跳过物理减免）。
const HUNTER_TRUE_RATIO := 0.02
## 法力回复：每次命中敌人回复最大法力的 1%；此外每秒回复最大法力的 0.2%。战役与试炼场统一。
const MP_ON_HIT_RATIO := 0.01
const MP_REGEN_PER_SECOND := 0.002
## 第一段斜劈 / 第二段前刺 / 第三段重斩；有效帧与 8 帧动画的命中姿态对齐。
const COMBO_HIT_TIMES := [0.12, 0.18, 0.23]
const COMBO_COOLDOWNS := [0.42, 0.48, 0.60]
const COMBO_MULTIPLIERS := [1.0, 1.1, 1.3]
const COMBO_REACH_BONUS := [0.0, 0.5, 0.3]
const COMBO_ARC_HALF := [1.0, 0.45, 1.2]
const SHIELD_MP_COST := 14.0
const SHIELD_DURATION := 5.0
const SHIELD_COOLDOWN := 8.0
const SHIELD_BASE_CAPACITY := 25.0
const SHIELD_CAPACITY_PER_INT := 2.0
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

static func shield_capacity(intelligence: int) -> float:
	return minf(100.0, SHIELD_BASE_CAPACITY + maxf(0.0, intelligence) * SHIELD_CAPACITY_PER_INT)
