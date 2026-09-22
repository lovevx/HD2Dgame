"""扫描 black_swordsman_new 图集的异常帧：近空帧、本体面积骤缩、脚底悬浮。

三类历史问题（2026-09-20）：
  * NEAR_EMPTY：AI 出图偶发"整格只剩一点刀尖"——不透明像素 < 400；
  * SHRINK：本体像素 < 该图集中位数的 25%（本体突然消失/缩水）；
  * LIFT：主体（最大深色连通域）底边悬在地面线之上——切图锚点被
    "风衣下摆/刀尖垂地"的姿势拉低后，整个人吊在半空。
    注意：主体底边低于地面线是正常的（悬垂尾垂进地面留白区），不算异常。

用法: python tools/diagnose_anim_sheets.py
"""
import os
import sys
from PIL import Image, ImageChops
from statistics import median

DST = "assets/characters/black_swordsman_new"
COLS, ROWS = 6, 2
ALPHA_MIN = 24
DARK_MAX = 110
NEAR_EMPTY_PX = 400
SHRINK_RATIO = 0.25
LIFT_TOL = 6  # 主体底边高出地面线超过该值视为悬浮

LUT_ALPHA = [255 if i > ALPHA_MIN else 0 for i in range(256)]
LUT_DARK = [255 if i < DARK_MAX else 0 for i in range(256)]


def main_blob_bottom(cell_dark):
    """最大深色连通域的底边 y（2 倍降采样 BFS，坐标已还原到原尺寸）。"""
    w, h = cell_dark.size
    data = cell_dark.tobytes()
    seen = bytearray(w * h)
    best_bottom, best_area = -1, 0
    for start in range(w * h):
        if not data[start] or seen[start]:
            continue
        stack = [start]
        seen[start] = 1
        area, maxy = 0, start // w
        while stack:
            p = stack.pop()
            area += 1
            y = p // w
            if y > maxy:
                maxy = y
            x = p % w
            for q in (p - 1, p + 1, p - w, p + w):
                if 0 <= q < w * h and data[q] and not seen[q]:
                    if (q == p - 1 and x > 0) or (q == p + 1 and x < w - 1) or abs(q - p) == w:
                        seen[q] = 1
                        stack.append(q)
        if area > best_area:
            best_area, best_bottom = area, maxy
    return best_bottom * 2 if best_area else -1


if not os.path.isdir(DST):
    print("!! 图集目录不存在:", DST)
    sys.exit(1)

files = sorted(f for f in os.listdir(DST) if f.endswith(".png"))
bad = 0
for f in files:
    im = Image.open(os.path.join(DST, f)).convert("RGBA")
    cw, ch = im.width // COLS, im.height // ROWS
    gl = ch - 16
    dark = ImageChops.darker(im.getchannel("A").point(LUT_ALPHA), im.convert("L").point(LUT_DARK))
    alpha = im.getchannel("A").point(LUT_ALPHA)
    counts, flags = [], []
    for i in range(COLS * ROWS):
        col, row = i % COLS, i // COLS
        box = (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)
        n = sum(1 for p in alpha.crop(box).getdata() if p)
        counts.append(n)
        tag = ""
        if n < NEAR_EMPTY_PX:
            tag = "NEAR_EMPTY"
        cell_d = dark.crop(box).resize((cw // 2, ch // 2), Image.BOX).point(lambda v: 255 if v > 40 else 0)
        bot = main_blob_bottom(cell_d)
        if bot >= 0 and gl - bot > LIFT_TOL:
            tag = (tag + "+" if tag else "") + f"LIFT({gl - bot}px)"
        if tag:
            flags.append(f"帧{i}(行{row + 1}列{col + 1}):{tag}")
    med = median(counts)
    shrink = [f"帧{i}:{counts[i]}px" for i in range(COLS * ROWS) if counts[i] < med * SHRINK_RATIO]
    if shrink:
        flags.append("SHRINK " + "; ".join(shrink))
    if flags:
        bad += 1
        print(f"{f:24s} 中位{int(med):6d}px -> " + "; ".join(flags))
print()
print(f"图集 {len(files)} 张，异常 {bad} 张" + ("（全部正常）" if bad == 0 else ""))
