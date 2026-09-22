"""把新版动作 sheet 每一行的 4 个列块各取首个角色，拼成"朝向地图"判断布局。
用法: python tools/map_new_moves_layout.py
"""
import os
from PIL import Image, ImageDraw

SRC = "assets/characters/black_swordsman/新版动作"
OUT = ".tmp_preview/new_moves"
os.makedirs(OUT, exist_ok=True)

# 行带（9 行）——四张 sheet 同网格
ROWS = [(48, 261), (332, 527), (602, 802), (947, 1167), (1228, 1416),
        (1498, 1698), (1840, 2063), (2127, 2319), (2398, 2594)]
# 列块（4 块）
CLUSTERS = [(90, 1110), (1280, 2300), (2460, 3480), (3640, 4660)]

CELL = 250


def figures(band_a, gap=8, min_len=12):
    """在一条 alpha 投影上找角色块"""
    w = len(band_a)
    runs, start, last = [], None, None
    for x in range(w):
        if band_a[x] > 24:
            if start is None:
                start = x
            last = x
        elif start is not None and x - last > gap:
            if last - start + 1 >= min_len:
                runs.append((start, last))
            start = None
    if start is not None and last - start + 1 >= min_len:
        runs.append((start, last))
    return runs


for name in ["跑步动画.png", "攻击动画.png", "受击动画.png", "闪避动画.png"]:
    im = Image.open(os.path.join(SRC, name)).convert("RGBA")
    for gi in range(3):
        rows_idx = [gi * 3 + 0, gi * 3 + 1, gi * 3 + 2]
        sheet = Image.new("RGBA", (CELL * 4, CELL * 3), (255, 255, 255, 255))
        dr = ImageDraw.Draw(sheet)
        for r, ri in enumerate(rows_idx):
            y0, y1 = ROWS[ri]
            band = im.crop((0, y0, im.width, y1 + 1))
            a = band.getchannel("A")
            ap = a.load()
            for c, (cx0, cx1) in enumerate(CLUSTERS):
                cx1 = min(cx1, band.width)
                col_max = [0] * (cx1 - cx0)
                for y in range(band.height):
                    for x in range(cx0, cx1):
                        v = ap[x, y]
                        if v > col_max[x - cx0]:
                            col_max[x - cx0] = v
                figs = figures(col_max)
                if not figs:
                    continue
                fx0, fx1 = figs[0]                      # 首个角色
                top, bot = None, None
                for y in range(band.height):
                    hit = False
                    for x in range(cx0 + fx0, cx0 + fx1 + 1):
                        if ap[x, y] > 24:
                            hit = True
                            break
                    if hit:
                        if top is None:
                            top = y
                        bot = y
                one = band.crop((cx0 + fx0 - 2, max(0, top - 2), cx0 + fx1 + 3, bot + 3))
                ow, oh = one.size
                s = min((CELL - 30) / ow, (CELL - 30) / oh)
                one = one.resize((max(1, int(ow * s)), max(1, int(oh * s))), Image.LANCZOS)
                cell = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 255))
                cell.paste(one, ((CELL - one.width) // 2, (CELL - one.height) // 2), one)
                sheet.paste(cell, (c * CELL, r * CELL), cell)
                dr.rectangle([c * CELL, r * CELL, c * CELL + CELL - 1, r * CELL + CELL - 1],
                             outline=(200, 200, 200, 255))
                dr.text((c * CELL + 6, r * CELL + 4), f"r{ri}c{c+1}", fill=(120, 120, 120, 255))
        sheet.convert("RGB").save(os.path.join(OUT, f"map_g{gi}_{name}"))
print("done ->", OUT)
