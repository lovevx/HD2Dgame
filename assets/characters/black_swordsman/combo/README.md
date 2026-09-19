# 三段连击新增帧

第一段继续使用上级目录的 `attack_*.png`。这里的六张透明 PNG 是第二段前刺与第三段重斩的侧、正、背三种视角；左右侧向共用侧面帧并在游戏中镜像。图片由内置 ImageGen 按原角色攻击帧作编辑参考生成，未覆盖原图。

| 动作 | 侧面 | 正面 | 背面 |
|---|---|---|---|
| 前刺 | `stab_side.png` 1942×809 | `stab_down.png` 1944×809 | `stab_up.png` 1945×809 |
| 重斩 | `heavy_side.png` 1944×809 | `heavy_down.png` 1774×887 | `heavy_up.png` 1944×809 |

每张图是四列两行的八帧。原图不是原角色的 192×160 格尺寸；早期 `player_visual.gd` 在运行时按四列两行分帧，并按格高调整 `pixel_size` 与偏移，导致连击角色在游戏里比第一段大 ~40%、脚底锚点乱跳。

## 规整（combo_norm/，已生效）

`tools/normalize_combo_frames.py` 把上面六张图统一重采样到 **192×160 每格、4 列 2 行（总 768×320）**，角色像素高对齐原版 108px，脚底锚点对齐 (96,144)。`player_visual.gd` 已改为固定分帧并删除运行时缩放。逐帧细节：

| 动作 | 侧面 | 正面 | 背面 |
|---|---|---|---|
| 前刺 | `combo_norm/stab_side.png` | `combo_norm/stab_down.png` | `combo_norm/stab_up.png` |
| 重斩 | `combo_norm/heavy_side.png` | `combo_norm/heavy_down.png` | `combo_norm/heavy_up.png` |

## 2026-09-19 视觉修复（已生效）

上一版虽然把画布统一成 192×160，但不同动作的角色主体仍有明显大小跳变，且 `stab_up` 实际画成横斩。现已按原版 `attack_*.png` 做风格与比例基准，重做六张连击图集：

- 第二段：侧面、正面、背面均为明确直线前刺；`stab_up` 为背视角直刺，不再使用横斩姿势
- 第三段：侧面、正面、背面均为蓄力 → 重斩 → 暗红弧光命中 → 收势
- 每帧按角色身体轮廓归一到约 104px，脚底固定在 y=144；刀与特效不再参与角色主体缩放
- 旧图备份：`art/meowa/black_swordsman_fourdir/backups/combo_norm_before_visual_fix_20260919/`
- 校验：`COMBO_SKILLS_FAILURES=0`

## meowa 重绘进度

以原版 attack 第 0 帧为参考（同一黑衣银刀像素角色），`keyframes-run` 8 帧 + 透明抠底，输出 192×160 画布（画布与锚点天然对齐，无需再缩放）。

| 动作 | 状态 | 说明 |
|---|---|---|
| stab_side | ✅ 已替换 | 侧面直线前刺，主体比例与原版攻击帧统一 |
| stab_up | ✅ 已替换 | 背视角直刺，主体比例与原版攻击帧统一 |
| stab_down | ✅ 已替换 | 正面直刺，主体比例与原版攻击帧统一 |
| heavy_side / heavy_down / heavy_up | ✅ 已替换 | 三方向蓄力、重斩、暗红弧光与收势 |

生成参数（供后续沿用）：`keyframes-run --keyframe 0=<attack_xxx_f0.png> --keyframe 7=<攻击_xxx_f0.png> --total-frames 8 --output-format spritesheet --animation-type attack --remove-bg-method standard`，prompt 描述"一次干净前刺：反握蓄力→水平直线刺出→红色小闪光→平滑收回起势，保留发型/风衣/银刀/像素风/比例/脚底锚点"。翻车倾向：背视角/正视角容易画成横扫，需明确"朝向镜头(上/下)直线刺出"并验收。

## 历史问题记录

旧版曾出现 `stab_down` 混入格挡/横扫、`stab_up` 方向错误，以及 `stab_side/heavy_*` 帧间头身比波动；这些版本已由 2026-09-19 的六张新图集替换。

## 生成提示词

输入均为同方向的原 `attack_side/down/up.png`，身份、黑衣、银刀、像素风和视角保持一致。侧面前刺另外参考了正面和背面原攻击图。

- 侧面前刺：`Produce ONE new sprite sheet for a distinct second-combo reverse-grip forward sword thrust viewed from the side, matching the identity, pixel size, costume, sword, silhouette, camera angle, foot anchor, and transparent background of the side reference. Exactly 4 columns and 2 rows, 8 sequential frames. Frames show anticipation, reverse grip, forward stab with sword extended, impact, and recovery. No text, other character, solid background, or borders. Crisp pixel edges.`
- 正面/背面前刺：`Create ONE new 8-frame sheet of the same black-cloaked pixel swordsman, facing toward/away from camera. Distinct second-combo reverse-grip forward thrust, anticipation, straight stab, impact, recovery. Preserve costume, sword, scale, viewing angle and foot anchor. Four columns by two rows, transparent background, no text or scenery.`
- 侧面重斩：`Create ONE distinct final-combo heavy sword attack sprite sheet viewed from the side, preserving the same character, black coat, hair, silver sword, pixel-art language, camera angle, foot anchor and silhouette. Four columns by two rows, 8 sequential poses: crouched preparation, raised sword, powerful diagonal slash, dark-red arc at impact, follow-through and recovery. Transparent background, no borders.`
- 正面/背面重斩：`Create ONE new 8-frame sheet of the same black-cloaked pixel swordsman, facing toward/away from camera. Third-combo heavy sword slash with a wide dark-red crescent: preparation, overhead wind-up, diagonal slash, impact, follow-through, recovery. Preserve costume, scale, viewing angle and foot anchor. Four columns by two rows, transparent background, no text or scenery.`
