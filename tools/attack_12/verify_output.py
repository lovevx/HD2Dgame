# -*- coding: utf-8 -*-
"""验证 攻击_*_12.png：每格本体高(暗色掩码行宽>=10)、脚底 y、空洞帧。
用法: python tools/attack_12/verify_output.py
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT / "assets" / "characters" / "black_swordsman_video"
ALPHA_MIN = 32
DARK_SUM = 560
FOOT_MIN_WIDTH = 10
CELL_W, CELL_H = 224, 192
DIRS = ["down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right"]


def body_span(img, x0, y0, x1, y1):
    px = img.load()
    counts = []
    for y in range(y0, y1 + 1):
        c = 0
        for x in range(x0, x1 + 1):
            if px[x, y][3] > ALPHA_MIN and sum(px[x, y][:3]) < DARK_SUM:
                c += 1
        counts.append(c)
    m = max(counts) if counts else 0
    thresh = max(8, 0.20 * m)
    rows = [(y0 + y, c) for y, c in enumerate(counts) if c >= thresh]
    if not rows:
        return None
    return (rows[0][0], rows[-1][0])


def main():
    bad = 0
    for d in DIRS:
        p = DIR / f"攻击_{d}_12.png"
        if not p.exists():
            print(f"!! 缺 {p.name}")
            continue
        im = Image.open(p).convert("RGBA")
        hs, foots, empties, clipped = [], [], [], []
        for i in range(12):
            x0 = (i % 6) * CELL_W
            y0 = (i // 6) * CELL_H
            s = body_span(im, x0, y0, x0 + CELL_W - 1, y0 + CELL_H - 1)
            cell = im.crop((x0, y0, x0 + CELL_W, y0 + CELL_H))
            bb = cell.getchannel("A").getbbox()
            if bb and (bb[1] < 0 or bb[3] > CELL_H - 1):
                clipped.append(i)
            if s is None:
                empties.append(i)
                continue
            hs.append(s[1] - s[0] + 1)
            foots.append(s[1] - (i // 6) * CELL_H)   # 相对各自行底
        hmin, hmax = (min(hs), max(hs)) if hs else (0, 0)
        fmin, fmax = (min(foots), max(foots)) if foots else (0, 0)
        flag = "OK"
        if hmin < 94 or hmax > 110:
            flag = "高异常"
            bad += 1
        if empties:
            flag += " 空帧:" + ",".join(str(e) for e in empties)
            bad += 1
        if clipped:
            flag += " 超格裁掉:" + ",".join(str(e) for e in clipped)
            bad += 1
        print(f"{d:12s} 高 {hmin}~{hmax}px 脚底(y) {fmin}~{fmax}  {flag}")
    print("异常数:", bad)


if __name__ == "__main__":
    main()