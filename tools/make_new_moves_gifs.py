"""把打包好的图集转成动画 GIF，便于肉眼核对动作与对齐（同一条地面线）。

用法: python tools/make_new_moves_gifs.py [放大倍数]
输出: .tmp_preview/new_moves/gif/<动作>_<方向>.gif
"""
import os
import sys
from PIL import Image

SRC = "assets/characters/black_swordsman_new"
OUT = ".tmp_preview/new_moves/gif"
COLS, ROWS = 6, 2
SCALE = int(sys.argv[1]) if len(sys.argv) > 1 else 2
BG = (244, 244, 246)
GROUND_SLACK = 16

WANT = [
    ("walk", ["down", "left", "up"]),
    ("run", ["down", "right"]),
    ("idle", ["down", "up_left"]),
    ("attack", ["down", "right", "up"]),
    ("kick", ["left", "down_right"]),
    ("hit", ["down", "up_left"]),
    ("dodge", ["left", "down"]),
    ("death", ["down", "left"]),
]

os.makedirs(OUT, exist_ok=True)
made = 0
for action, dirs in WANT:
    for d in dirs:
        path = os.path.join(SRC, f"{action}_{d}.png")
        if not os.path.exists(path):
            continue
        atlas = Image.open(path).convert("RGBA")
        cw, ch = atlas.width // COLS, atlas.height // ROWS
        frames = []
        for i in range(COLS * ROWS):
            cell = atlas.crop(((i % COLS) * cw, (i // COLS) * ch,
                               (i % COLS) * cw + cw, (i // COLS) * ch + ch))
            canvas = Image.new("RGB", (cw, ch), BG)
            canvas.paste(cell, (0, 0), cell)
            gl = ch - GROUND_SLACK
            px = canvas.load()
            for x in range(cw):                       # 画一条地面线，便于核对对齐
                px[x, gl] = (216, 130, 130)
            if SCALE != 1:
                canvas = canvas.resize((cw * SCALE, ch * SCALE), Image.NEAREST)
            frames.append(canvas)
        fp = os.path.join(OUT, f"{action}_{d}.gif")
        frames[0].save(fp, save_all=True, append_images=frames[1:],
                       duration=int(1000 / 15), loop=0, optimize=True)
        made += 1
print(f"生成 {made} 个 GIF → {OUT}（放大 {SCALE}x）")
