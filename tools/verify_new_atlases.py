"""对齐自检：逐帧量图集里本体（深色像素）的底边与头顶中线，验证是否落在锚点上。

判定标准：
  * 本体底边（脚底）应落在该图集的地面线 gl = 格高 − 16 上，允许 ±2px；
  * 每帧内容（含刀光）必须完全落在本格内（不越格、不被裁）；
  * 同一动作同一方向 12 帧的脚底线偏差 ≤ 2px（不上下跳）。

用法: python tools/verify_new_atlases.py
"""
import os
import sys
from PIL import Image, ImageChops

DST = "assets/characters/black_swordsman_new"
COLS, ROWS = 6, 2
GROUND_SLACK = 16
ALPHA_MIN = 24
DARK_MAX = 110
LUT_ALPHA = [255 if i > ALPHA_MIN else 0 for i in range(256)]
LUT_DARK = [255 if i < DARK_MAX else 0 for i in range(256)]

if not os.path.isdir(DST):
    print("!! 图集目录不存在:", DST)
    sys.exit(1)

files = sorted(f for f in os.listdir(DST) if f.endswith(".png"))
if not files:
    print("!! 没有图集文件")
    sys.exit(1)

bad = 0
print(f"{'动画':22s} {'格':>10s} {'地面线偏差':>10s} {'中线偏差':>9s} {'内容越格':>8s} {'略空帧':>6s}")
for f in files:
    im = Image.open(os.path.join(DST, f)).convert("RGBA")
    cw, ch = im.width // COLS, im.height // ROWS
    gl = ch - GROUND_SLACK
    dm = ImageChops.darker(im.getchannel("A").point(LUT_ALPHA),
                           im.convert("L").point(LUT_DARK))
    am = im.getchannel("A").point(LUT_ALPHA)
    foot_devs, head_devs, bleed, empty = [], [], 0, 0
    for i in range(COLS * ROWS):
        col, row = i % COLS, i // COLS
        box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
        cell_d = dm.crop(box)
        cell_a = am.crop(box)
        bb = cell_d.getbbox()
        if bb is None:
            empty += 1
            continue
        foot_devs.append(abs(bb[3] - gl))
        top_h = max(1, int((bb[3] - bb[1] + 1) * 0.22))
        hb = cell_d.crop((bb[0], bb[1], bb[2], bb[1] + top_h)).getbbox()
        if hb is not None:
            head_cx = bb[0] + (hb[0] + hb[2]) / 2.0
            head_devs.append(abs(head_cx - cw / 2.0))
        ab = cell_a.getbbox()
        if ab is not None and (ab[0] <= 0 or ab[1] <= 0 or ab[2] >= cw or ab[3] >= ch):
            bleed += 1
    fmax = max(foot_devs) if foot_devs else -1
    hmax = max(head_devs) if head_devs else -1
    flag = ""
    if fmax > 2 or bleed > 0 or empty > 0:
        flag = "  <-- 查"
        bad += 1
    print(f"{f:22s} {cw:4d}x{ch:<4d} {fmax:9.1f}px {hmax:8.1f}px {bleed:8d} {empty:6d}{flag}")

print()
print(f"图集数 {len(files)}；脚底/越格/空帧有问题的 {bad} 个" + ("（全部通过）" if bad == 0 else ""))
print("注：中线偏差是「本体头顶带中心 vs 格中线」的距离 —— 出刀/突进姿势会故意偏，"
      "不一定是错；脚底偏差才是硬指标。")
