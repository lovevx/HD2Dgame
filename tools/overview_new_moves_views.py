"""把新版动作 sheet 的「9 行 × 4 列块」首个角色全部抠出，拼成 6x6 总览，
用于一次性确认方向覆盖（每格一个朝向样本）。
用法: python tools/overview_new_moves_views.py
"""
import os
from PIL import Image, ImageDraw

SRC = "assets/characters/black_swordsman/新版动作"
OUT = ".tmp_preview/new_moves"
os.makedirs(OUT, exist_ok=True)

ROWS = [(48, 261), (332, 527), (602, 802), (947, 1167), (1228, 1416),
        (1498, 1698), (1840, 2063), (2127, 2319), (2398, 2594)]
CLUSTERS = [(90, 1110), (1280, 2300), (2460, 3480), (3640, 4660)]
CELL = 250


def segments(vals, gap=8, min_len=12):
    runs, start, last = [], None, None
    for i, v in enumerate(vals):
        if v > 24:
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


for name in ["跑步动画.png", "攻击动画.png", "受击动画.png", "闪避动画.png"]:
    im = Image.open(os.path.join(SRC, name)).convert("RGBA")
    cells = []
    for ri, (y0, y1) in enumerate(ROWS):
        band = im.crop((0, y0, im.width, y1 + 1))
        ap = band.getchannel("A").load()
        for ci, (cx0, cx1) in enumerate(CLUSTERS):
            cx1 = min(cx1, band.width)
            col_max = [0] * (cx1 - cx0)
            for y in range(band.height):
                for x in range(cx0, cx1):
                    v = ap[x, y]
                    if v > col_max[x - cx0]:
                        col_max[x - cx0] = v
            figs = segments(col_max)
            if not figs:
                continue
            fx0, fx1 = figs[0]
            top, bot = None, None
            for y in range(band.height):
                hit = False
                for x in range(cx0 + fx0, min(cx0 + fx1 + 1, band.width)):
                    if ap[x, y] > 24:
                        hit = True
                        break
                if hit:
                    if top is None:
                        top = y
                    bot = y
            if top is None:
                continue
            one = band.crop((cx0 + fx0 - 2, max(0, top - 3), cx0 + fx1 + 3, bot + 4))
            ow, oh = one.size
            s = min((CELL - 40) / ow, (CELL - 40) / oh)
            one = one.resize((max(1, int(ow * s)), max(1, int(oh * s))), Image.LANCZOS)
            cell = Image.new("RGBA", (CELL, CELL), (255, 255, 255, 255))
            cell.paste(one, ((CELL - one.width) // 2, (CELL - one.height) // 2), one)
            d = ImageDraw.Draw(cell)
            d.rectangle([0, 0, CELL - 1, CELL - 1], outline=(210, 210, 210, 255))
            d.text((6, 4), f"r{ri}c{ci+1}", fill=(120, 120, 120, 255))
            cells.append(cell)
    # 6 列 × N 行
    cols = 6
    rows_n = (len(cells) + cols - 1) // cols
    sheet = Image.new("RGBA", (CELL * cols, CELL * rows_n), (255, 255, 255, 255))
    for i, cell in enumerate(cells):
        sheet.paste(cell, ((i % cols) * CELL, (i // cols) * CELL), cell)
    sheet.convert("RGB").save(os.path.join(OUT, f"allviews_{name}"))
    print(f"{name}: {len(cells)} 格  {sheet.size}")
