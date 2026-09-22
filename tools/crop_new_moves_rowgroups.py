"""放大裁剪新版动作 sheet 的单个视角行组（第一列块），确认视角到底覆盖几个方向。
用法: python tools/crop_new_moves_rowgroups.py
"""
import os
from PIL import Image

SRC = "assets/characters/black_swordsman/新版动作"
OUT = ".tmp_preview/new_moves"
os.makedirs(OUT, exist_ok=True)

# 行组边界：四张 sheet 同源同网格（跑步量得 48-802 / 947-1698 / 1840-2594，分隔线在 853/1750/2646）
ROWGROUPS = [("g0", 40, 810), ("g1", 935, 1705), ("g2", 1785, 2605)]
# 列块边界：4 个块，取第 1、2 块对照
COLBLOCKS = [("c1", 100, 1100), ("c2", 1290, 2290)]

for name in ["跑步动画.png", "攻击动画.png", "受击动画.png", "闪避动画.png"]:
    im = Image.open(os.path.join(SRC, name)).convert("RGBA")
    for gname, y0, y1 in ROWGROUPS:
        for cname, x0, x1 in COLBLOCKS:
            crop = im.crop((x0, y0, x1, y1))
            w, h = crop.size
            scale = min(1100 / w, 700 / h)
            crop2 = crop.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            crop2.save(os.path.join(OUT, f"{gname}_{cname}_{name}"))
print("done ->", OUT)
