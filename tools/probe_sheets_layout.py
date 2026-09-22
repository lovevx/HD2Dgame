"""自动探测新版动作 sheet 的块/子行/角色结构（不依赖硬编码 y 坐标）。
用法: python tools/probe_sheets_layout.py
"""
import os
from PIL import Image

SRC = "assets/characters/black_swordsman/新版动作"
SHEETS = ["行走.png", "跑步动画.png", "待机.png", "攻击.png", "直踹.png",
          "受击动画.png", "闪避动画.png", "死亡.png"]
ALPHA_MIN = 24


def segs(vals, gap, min_len):
    runs, start, last = [], None, None
    for i, v in enumerate(vals):
        if v > 0:
            if start is None:
                start = i
            last = i
        elif start is not None and i - last > gap:
            if last - start + 1 >= min_len:
                runs.append((start, last))
            start = None
    if start is not None and last - start + 1 >= min_len:
        runs.append((start, last))
    return runs


def row_profile(alpha, y0, y1):
    px = alpha.load()
    out = [0] * (y1 - y0)
    for y in range(y0, y1):
        c = 0
        for x in range(0, alpha.width, 2):          # 横向 2px 抽样，够用且快
            if px[x, y] > ALPHA_MIN:
                c += 1
        out[y - y0] = c
    return out


def col_profile(alpha, x0, x1, y0, y1):
    px = alpha.load()
    out = [0] * (x1 - x0)
    for x in range(x0, x1):
        c = 0
        for y in range(y0, y1):
            if px[x, y] > ALPHA_MIN:
                c += 1
        out[x - x0] = c
    return out


for name in SHEETS:
    path = os.path.join(SRC, name)
    if not os.path.exists(path):
        print(f"!! 缺文件 {name}")
        continue
    im = Image.open(path).convert("RGBA")
    alpha = im.getchannel("A")
    rows = segs(row_profile(alpha, 0, im.height), gap=6, min_len=5)
    seps = [s for s in rows if s[1] - s[0] + 1 < 30]
    subs = [s for s in rows if s[1] - s[0] + 1 >= 30]
    print("=" * 72)
    print(f"{name}  {im.size[0]}x{im.size[1]}  分隔线 {len(seps)} 条, 子行 {len(subs)} 条")
    for i, (y0, y1) in enumerate(subs):
        figs = segs(col_profile(alpha, 0, im.width, y0, y1 + 1), gap=6, min_len=10)
        print(f"   子行{i}: y={y0}-{y1} ({y1-y0+1}px)  角色块 {len(figs)}")
