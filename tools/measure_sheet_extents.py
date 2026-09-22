"""量每个动作每个方向的「本体宽高 vs 含特效宽高」，用于定格子尺寸。
本体 = 深色像素（黑衣），特效 = 其余（刀光弧等）。
用法: python tools/measure_sheet_extents.py
"""
import os
from PIL import Image

SRC = "assets/characters/black_swordsman/新版动作"
SHEETS = ["行走.png", "跑步动画.png", "待机.png", "攻击.png", "直踹.png",
          "受击动画.png", "闪避动画.png", "死亡.png"]
BLOCKS = [(0, 862), (870, 1758), (1766, 2688)]
SUB_DIRS = [["down_left", "down", "down_right"], ["left", "right"],
            ["up_left", "up", "up_right"]]
ALPHA_MIN = 24
DARK_MAX = 110


def profile(mask, y0, y1, axis):
    px = mask.load()
    if axis == "row":
        out = [0] * (y1 - y0)
        for y in range(y0, y1):
            c = 0
            for x in range(0, mask.width, 2):
                if px[x, y] > 0:
                    c += 1
            out[y - y0] = c
        return out
    out = [0] * (y1 - y0)          # 这里 y1 复用为 x1
    for x in range(y0, y1):
        c = 0
        for y in range(0, mask.height, 2):
            if px[x, y] > 0:
                c += 1
        out[x - y0] = c
    return out


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


def dark_mask(im, y0, y1):
    crop = im.crop((0, y0, im.width, y1)).convert("RGBA")
    a = crop.getchannel("A")
    l = crop.convert("L")
    ap, lp = a.load(), l.load()
    out = Image.new("L", crop.size, 0)
    op = out.load()
    for y in range(crop.height):
        for x in range(crop.width):
            if ap[x, y] > ALPHA_MIN and lp[x, y] < DARK_MAX:
                op[x, y] = 255
    return out, crop


print(f"{'动作':8s} {'方向':10s} {'本体高':>6s} {'本体宽':>6s} {'含特效宽':>8s} {'含特效高':>8s} {'宽比':>6s} {'高比':>6s}")
for name in SHEETS:
    path = os.path.join(SRC, name)
    if not os.path.exists(path):
        continue
    im = Image.open(path).convert("RGBA")
    stats = {}
    for bi, (by0, by1) in enumerate(BLOCKS):
        dm, crop = dark_mask(im, by0, by1)
        rows = segs(profile(dm, 0, dm.height, "row"), gap=5, min_len=5)
        rows = [r for r in rows if r[1] - r[0] + 1 >= 30]
        for si, (ry0, ry1) in enumerate(rows):
            if si >= 3:
                break
            dirs = SUB_DIRS[si]
            sub = dm.crop((0, ry0, dm.width, ry1 + 1))
            cols = segs(profile(sub, 0, sub.width, "col"), gap=6, min_len=8)
            if not cols:
                continue
            # 顺序等分给各方向
            base, extra = divmod(len(cols), len(dirs))
            idx = 0
            for di, dname in enumerate(dirs):
                take = base + (1 if di < extra else 0)
                for cx0, cx1 in cols[idx:idx + take]:
                    idx += 1
                    # 本体内纵向范围
                    sp = sub.load()
                    top = bot = None
                    for y in range(sub.height):
                        if any(sp[x, y] > 0 for x in range(cx0, cx1 + 1)):
                            if top is None:
                                top = y
                            bot = y
                    if top is None:
                        continue
                    # 含特效：在本体左右各留 40% 本宽的窗口内找 alpha 包围盒
                    pad = int((cx1 - cx0) * 0.42)
                    wx0, wx1 = max(0, cx0 - pad), min(crop.width - 1, cx1 + pad)
                    ap = crop.getchannel("A").load()
                    ax0 = ax1 = ay0 = ay1 = None
                    for y in range(crop.height):
                        for x in range(wx0, wx1 + 1):
                            if ap[x, y] > ALPHA_MIN:
                                if ax0 is None or x < ax0:
                                    ax0 = x
                                if ax1 is None or x > ax1:
                                    ax1 = x
                                if ay0 is None:
                                    ay0 = y
                                ay1 = y
                    if ax0 is None:
                        continue
                    st = stats.setdefault(dname, {"bh": [], "bw": [], "aw": [], "ah": []})
                    st["bh"].append(bot - top + 1)
                    st["bw"].append(cx1 - cx0 + 1)
                    st["aw"].append(ax1 - ax0 + 1)
                    st["ah"].append(ay1 - ay0 + 1)

    for dname, st in stats.items():
        if not st["bh"]:
            continue
        bh = sum(st["bh"]) / len(st["bh"])
        bw = sum(st["bw"]) / len(st["bw"])
        aw = sum(st["aw"]) / len(st["aw"])
        ah = sum(st["ah"]) / len(st["ah"])
        print(f"{name[:4]:8s} {dname:10s} {bh:6.0f} {bw:6.0f} {aw:8.0f} {ah:8.0f} {aw/bh:6.1f} {ah/bh:6.1f}")
