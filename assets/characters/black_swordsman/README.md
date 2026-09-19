# 黑衣剑士 · 四方向 Godot 接入

## 完成范围

- Meowa 新生成八方向静态角色图，取正面和背面生成各8帧移动动画。
- 上下移动使用新动画；左右移动使用上一轮的朝右移动动画及其水平镜像。
- 朝上、朝下攻击使用各自新生成的8帧动画。
- 左右攻击使用上一轮朝左斩击及其水平镜像。镜像会改变持刀手。
- 四方向 idle 为对应移动中的静态帧，不是新生成的呼吸动画。

## 项目使用

直接运行主场景：WASD 移动，鼠标左键攻击，左 Shift 剃。player.tscn 已将胶囊显示模型替换为 AnimatedSprite3D，物理碰撞保留。动画按主移动轴选择朝向，斜向不播放八方向动画。

player_frames.tres 是 Godot SpriteFrames 资源；walk_up/down/side.png、attack_up/down/side.png 以及 combo_norm/ 下的 stab/heavy 图集都是统一192×160单帧、4列2行图集。素材仅平移和打包，不缩放像素。脚底参考锚点(96,144)，Sprite3D offset=(0,64)，pixel_size=0.016，Nearest采样，面向相机并接受场景光照。侧面图集通过 flip_h 复用。

2026-09-19 已将移动、待机、第一段攻击、受击、死亡、防御、闪避共 17 张动作图集按 combo_norm 的角色画法重新统一：每套图集使用统一整套比例，站立类主体高度约 104px，脚底固定到 y=144；倒地与闪避只保留动作本身的姿态变化，不逐帧缩放制造大小跳变。旧图备份在 `art/meowa/black_swordsman_fourdir/backups/other_actions_before_style_fix_20260919/`。

2026-09-19 后续修正：walk_side/down/up 改为明确的左右脚交替与 passing pose；stab_up 改为背视角中线直刺。修复前图备份在 `art/meowa/black_swordsman_fourdir/backups/walk_and_stab_up_before_fix_20260919/`。

scripts/player/player_visual.gd 控制显示状态：移动循环10 FPS；攻击单次速度匹配当前冷却；剃按蓄力-爆发节奏播放；攻击播放期间保持出手朝向；重生清除动画锁。三段连击分别使用 player_frames.tres 中的 attack、stab、heavy 序列，伤害逻辑未改动。

2026-09-19 八方向改造（进行中）：每动作改为 5 张唯一图集（up/down/right/up_right/down_right），left/up_left/down_left 由 flip_h 镜像；`player_visual.gd` 已改为 8 向量化（atan2 每 45° 一档），侧面/斜向图集统一面朝右（attack/dodge 不再特判朝左）。`.tres` 由 `tools/package_8dir.py` 统一生成（含锚点验收，脚底 y=144±2），旧 `*_side.png` / `idle.png` / `guard.png` 命名废弃。详见 `ANIMATION_SPEC.md`。

## 剃（六式・剃）

物理高速爆发位移，非空间传送。四个方向各有素材：左右复用 `dodge.png`（源图朝左，与 walk_side / attack_side 反向，因此镜像规则相反——**左不镜像、右镜像**，见 `set_flip_for`）；上/下各有独立图集 `dodge_up.png`（背面视角）与 `dodge_down.png`（正面视角），均不镜像。`dodge.png` 前 3 帧在打包时做过水平翻转对齐（`MIRROR_FRAMES`），因为生成结果的前 3 帧朝向与冲刺帧相反。上下两套以 `walk_up` / `walk_down` 的中性单帧为参考图生成，保证画布、比例与脚底锚点一致。

> 八方向改造后：dodge 改为 `dodge_right/up_right/down_right` 唯一图集（统一面朝右）+ 左向镜像，`MIRROR_FRAMES` 预翻转不再需要，上/下独立图集保留为八方向中的 up/down 两张。

- 按键左 Shift，冷却 2.2 秒，单次位移约 6.6 米（`dodge_speed` 18 × `dodge_duration` 0.55 秒）。
- 速度分三段：`DODGE_WINDUP` 0.15 秒蓄力下蹲（脚踩地面，人留在原地）→ 瞬间满速爆发 → 末段 `DODGE_STOP_TIME` 0.08 秒骤停，用位移曲线的对比制造爆发感。
- 无敌帧只覆盖蓄力段（按下即受保护），爆发后的规避靠高速位移本身。
- 撞墙由 CharacterBody3D 的 move_and_slide 自然截停；悬空不能释放，由 `_is_grounded()` 把关（当前竞技场为平地，恒为真）。
- dodge 动画采用不等长帧时长 `DODGE_RHYTHM`（合计 8.0，仍为 0.8 秒整段）：蓄力帧放慢、爆发帧缩短。

主场景相机 offset 改为(0,8,8)，便于看清像素人物。原文件备份在 art/meowa/black_swordsman_fourdir/backups。

## 验证

Godot 4.7.2：无窗口逻辑检查与 D3D12 Forward+ 实际渲染检查均通过。覆盖四方向输入与实际位移、停步保持朝向、四方向攻击选择与左右镜像、攻击结束、剃的按键绑定/蓄力/爆发/位移距离/冷却/左右镜像/上下独立图集、格挡停帧与重生。校验脚本 tools/validate_player_visual.gd；素材打包脚本 tools/package_swordsman.py。

补全上下攻击时使用15积分生成统一的八方向攻击准备姿势，并使用80积分生成两段动画。
