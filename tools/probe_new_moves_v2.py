"""量新版动作 sheet 的网格结构与视角覆盖。
用法: python tools/probe_new_moves_v2.py
输出: .tmp_preview/new_moves/ 下的结构报告 + 裁剪放大图
"""
import os
from PIL import Image

SRC = "assets/characters/black_swordsman/新版动作"
OUT = ".tmp_preview/new_moves"
FILES = ["跑步动画.png", "攻击动画.png", "受击动画.png", "闪避动画.png"]

os.makedirs(OUT, exist_ok=True)


def segments(flags, gap=6, min_len=8):
    """把布尔序列切成连续段（允许 gap 像素的空隙合并）。返回 [(start, end)]"""
    runs = []
    start = None
    last_true = None
    for i, v in enumerate(flags):
        if v:
            if start is None:
                start = i
            last_true = i
        else:
            if start is not None and i - last_true > gap:
                if last_true - start + 1 >= min_len:
                    runs.append((start, last_true))
                start = None
    if start is not None and last_true - start + 1 >= min_len:
        runs.append((start, last_true))
    return runs


for name in FILES:
    path = os.path.join(SRC, name)
    im = Image.open(path).convert("RGBA")
    w, h = im.size
    alpha = im.getchannel("A")
    px = alpha.load()

    # 列/行投影：该列/行是否含不透明像素
    col_has = [False] * w
    row_has = [False] * h
    for y in range(h):
        for x in range(w):
            if px[x, y] > 24:
                col_has[x] = True
                row_has[y] = True

    cols = segments(col_has, gap=8, min_len=10)
    rows = segments(row_has, gap=8, min_len=10)

    print("=" * 70)
    print(f"{name}  {w}x{h}")
    print(f"  非空行带 {len(rows)} 条: " + ", ".join(f"{a}-{b}({b-a+1}px)" for a, b in rows))
    print(f"  非空列带 {len(cols)} 条: " + ", ".join(f"{a}-{b}" for a, b in cols))

    # 按行带切图，每行带内再做列投影，得到"每行有几个角色块"
    for ri, (y0, y1) in enumerate(rows):
        sub = im.crop((0, y0, w, y1 + 1))
        sa = sub.getchannel("A")
        sp = sa.load()
        cw, ch = sub.size
        ch_has = [False] * cw
        for y in range(ch):
            for x in range(cw):
                if sp[x, y] > 24:
                    ch_has[x] = True
        blobs = segments(ch_has, gap=4, min_len=6)
        heights = []
        for bx0, bx1 in blobs:
            top = None
            bot = None
            for y in range(ch):
                for x in range(bx0, bx1 + 1):
                    if sp[x, y] > 24:
                        if top is None:
                            top = y
                        bot = y
            if top is not None:
                heights.append(bot - top + 1)
        hs = f"  身高 {min(heights)}~{max(heights)}px" if heights else ""
        print(f"  行带{ri}: y={y0}-{y1}  块数={len(blobs)}{hs}")

    # 裁剪：整图缩略 + 每行带一条放大条
    im.resize((1184, 672), Image.LANCZOS).save(os.path.join(OUT, f"thumb_{name}"))
    for ri, (y0, y1) in enumerate(rows[:4]):
        band = im.crop((0, y0, w, y1 + 1))
        bw, bh = band.size
        scale = min(1184 / bw, 260 / max(bh, 1))
        band2 = band.resize((max(1, int(bw * scale)), max(1, int(bh * scale))), Image.LANCZOS)
        band2.save(os.path.join(OUT, f"band{ri}_{name}"))

print("\n输出目录:", OUT)
