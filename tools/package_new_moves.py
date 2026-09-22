"""新版动作打包：自由排布 sheet → 每方向一张游戏规格图集 PNG。

布局（作者确认，8 张 sheet 一致）：
  每张 sheet 含 3 个块（分隔线切开），每块内 3 行：
    上排 3 张 = down_left / down / down_right
    中排 2 张 = left / right
    下排 3 张 = up_left / up / up_right
  每个角色 = 1 帧；三个块共 12 帧（不足 12 帧的循环等比补采样到 12）。

对齐规则（核心）：
  * 定位/量身高只用「深色像素」（黑衣本体）。攻击、闪避帧带大亮色刀光弧，
    用 alpha 包围盒会把弧光算进本体，行带也会糊成一片。
  * 缩放：全局统一 scale = 104 / 全体本体高中位数 —— 8 动作 × 8 方向人物一样大。
  * 纵向：每帧按本体底边对齐到格子地面线（格底往上 GROUND_SLACK 像素）。
  * 横向：每段用「头顶中线中位数」定统一偏移 —— 保留帧内真实位移（出刀/突进），
    不做逐帧居中（逐帧居中会把位移压平）。
  * 画布：高度按动作所需（≥160）统一，宽度按动作内容放宽（攻击刀光）；
    锚点恒在 (W/2, 地面线)。游戏侧 offset.y = 地面线 − 格高/2。

输出：
  assets/characters/black_swordsman_new/<动作>_<方向>.png   图集（6 列 × 2 行）
  .tmp_preview/new_moves/verify/<动作>.png                 核对图（含网格与地面线）
  .tmp_preview/new_moves/package_report.txt

用法: python tools/package_new_moves.py
"""
import math
import os
from PIL import Image, ImageChops, ImageDraw

SRC = "assets/characters/black_swordsman/新版动作"
DST = "assets/characters/black_swordsman_new"
TMP = ".tmp_preview/new_moves"
ALPHA_MIN = 24
DARK_MAX = 110
TARGET_BODY_H = 104
GROUND_SLACK = 16
COLS = 6
FRAMES = 12

SHEETS = [
    ("行走.png", "walk"),
    ("跑步动画.png", "run"),
    ("待机.png", "idle"),
    ("攻击.png", "attack"),
    ("直踹.png", "kick"),
    ("受击动画.png", "hit"),
    ("闪避动画.png", "dodge"),
    ("死亡.png", "death"),
]
SUB_DIRS = [["down_left", "down", "down_right"], ["left", "right"],
            ["up_left", "up", "up_right"]]


LUT_ALPHA = [255 if i > ALPHA_MIN else 0 for i in range(256)]
LUT_DARK = [255 if i < DARK_MAX else 0 for i in range(256)]


def bin_mask(im, mode):
    if mode == "alpha":
        return im.getchannel("A").point(LUT_ALPHA)
    dark = im.convert("L").point(LUT_DARK)
    return ImageChops.darker(im.getchannel("A").point(LUT_ALPHA), dark)


def segments(vals, thresh, gap, min_len):
    runs, start, last = [], None, None
    for i, v in enumerate(vals):
        if v > thresh:
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


def row_profile(mask):
    p = mask.resize((1, mask.height), Image.BOX)
    return [p.getpixel((0, y)) for y in range(mask.height)]


def col_profile(mask):
    p = mask.resize((mask.width, 1), Image.BOX)
    return [p.getpixel((x, 0)) for x in range(mask.width)]


def blocks_of(mask):
    """→ [(block_y0, block_y1, [(sub_y0, sub_y1) x3]) x3]"""
    rows = segments(row_profile(mask), 3, 6, 5)
    seps = [r for r in rows if r[1] - r[0] + 1 < 30]
    subs = [r for r in rows if r[1] - r[0] + 1 >= 30]
    if len(seps) >= 2:
        edges = [0] + [s[0] for s in seps] + [mask.height]
    else:
        edges = [0, mask.height]
    out = []
    if len(edges) >= 3:
        for a, b in zip(edges, edges[1:]):
            grp = [s for s in subs if a <= s[0] < b]
            if grp:
                out.append((a, b, grp))
    if not out:
        out = [(0, mask.height, subs[i:i + 3]) for i in range(0, min(len(subs), 9), 3)]
    return out


def body_box(mask, x0, x1, y0, y1):
    sub = mask.crop((x0, y0, x1 + 1, y1 + 1))
    bb = sub.getbbox()
    if bb is None:
        return None
    return (x0 + bb[0], y0 + bb[1], x0 + bb[2] - 1, y0 + bb[3] - 1)


def head_center_x(mask, bx0, bx1, by0, by1):
    h = max(1, int((by1 - by0 + 1) * 0.22))
    sub = mask.crop((bx0, by0, bx1 + 1, by0 + h))
    bb = sub.getbbox()
    if bb is None:
        return (bx0 + bx1) / 2.0
    return bx0 + (bb[0] + bb[2] - 1) / 2.0


def sample_to(n, target):
    if n <= 0:
        return []
    if n == target:
        return list(range(n))
    return [int(round(i * n / float(target))) % n for i in range(target)]


# ---------------------------------------------------------------- 解析
report = []
parsed = {}          # action -> dir -> [frame dict]
body_heights = []

for fname, action in SHEETS:
    path = os.path.join(SRC, fname)
    if not os.path.exists(path):
        report.append(f"!! 缺文件 {fname}")
        continue
    im = Image.open(path).convert("RGBA")
    bmask = bin_mask(im, "body")
    blocks = blocks_of(bmask)
    per_dir = {}
    for (by0, by1, subs) in blocks:
        for si, (ry0, ry1) in enumerate(subs):
            if si >= len(SUB_DIRS):
                continue
            dirs = SUB_DIRS[si]
            band = bmask.crop((0, ry0, im.width, ry1 + 1))
            cols = segments(col_profile(band), 3, 6, 8)
            if not cols:
                continue
            mids = [0] + [int((cols[i][1] + cols[i + 1][0]) / 2) for i in range(len(cols) - 1)] + [im.width]
            base, extra = divmod(len(cols), len(dirs))
            idx = 0
            for di, dname in enumerate(dirs):
                take = base + (1 if di < extra else 0)
                for _ in range(take):
                    cx0, cx1 = cols[idx]
                    wx0 = mids[idx] if idx < len(mids) else 0
                    wx1 = mids[idx + 1] if idx + 1 < len(mids) else im.width
                    idx += 1
                    wx0, wx1 = max(0, wx0), min(im.width, wx1)
                    bb = body_box(bmask, wx0, min(im.width - 1, wx1 - 1), ry0, ry1)
                    if bb is None:
                        continue
                    hcx = head_center_x(bmask, bb[0], bb[2], bb[1], bb[3])
                    body_heights.append(bb[3] - bb[1] + 1)
                    per_dir.setdefault(dname, []).append(
                        {"im": im, "body": bb, "head_cx": hcx,
                         "win": (wx0, wx1), "block_y": (by0, by1)})
    parsed[action] = per_dir
    print(f"  解析 {action} 完成", flush=True)
    report.append(f"{action:7s} " + " ".join(f"{d}={len(v)}" for d, v in sorted(per_dir.items())))

body_heights.sort()
median_bh = body_heights[len(body_heights) // 2] if body_heights else 185
SCALE = TARGET_BODY_H / float(median_bh)
report.append(f"\n全局：本体重高中位 {median_bh}px → 缩放 {SCALE:.4f}（目标身高 {TARGET_BODY_H}px）")

# ---------------------------------------------------------------- 切割 + 对齐
os.makedirs(DST, exist_ok=True)
os.makedirs(os.path.join(TMP, "verify"), exist_ok=True)

for action, per_dir in parsed.items():
    # ① 每方向先算出缩放后的内容相对锚点范围
    clips = {}
    for dname, items in per_dir.items():
        n = len(items)
        idxs = sample_to(n, FRAMES)
        hcxs = sorted(it["head_cx"] for it in items)
        med_hcx = hcxs[len(hcxs) // 2]
        frames = []
        min_x = max_x = None
        max_up = max_down = 0
        for i in idxs:
            it = items[i]
            wx0, wx1 = it["win"]
            by0, by1 = it["block_y"]
            crop = it["im"].crop((wx0, by0, wx1, by1))          # 竖向限在本块内
            bx0, by0b, bx1, by1b = it["body"]
            nw = max(1, int(round(crop.width * SCALE)))
            nh = max(1, int(round(crop.height * SCALE)))
            small = crop.resize((nw, nh), Image.LANCZOS) if (nw, nh) != crop.size else crop
            ax = (med_hcx - wx0) * SCALE                        # 锚点（横向=段中位头顶中线）
            ay = (by1b - by0) * SCALE                           # 锚点（纵向=本体底边）
            box = small.getchannel("A").point(LUT_ALPHA).getbbox()
            if box is None:
                continue
            cx0, cy0, cx1, cy1 = box
            min_x = (cx0 - ax) if min_x is None else min(min_x, cx0 - ax)
            max_x = (cx1 - ax) if max_x is None else max(max_x, cx1 - ax)
            max_up = max(max_up, ay - cy0)
            max_down = max(max_down, cy1 - ay)
            frames.append({"img": small, "ax": ax, "ay": ay})
        clips[dname] = {"frames": frames, "min_x": min_x or 0, "max_x": max_x or 0,
                        "max_up": max_up, "max_down": max_down,
                        "src_n": n, "dir": dname}
    # ② 全动作统一画布（8 向同尺寸，便于游戏侧切换）
    half_w = max(max(abs(c["min_x"]), abs(c["max_x"])) for c in clips.values()) + 6
    cell_w = max(192, int(math.ceil(half_w * 2 / 16.0) * 16))
    max_up = max(c["max_up"] for c in clips.values())
    max_down = max(c["max_down"] for c in clips.values())
    cell_h = max(160, int(math.ceil((max_up + max_down + 8) / 16.0) * 16))
    gl = cell_h - GROUND_SLACK                              # 地面线（= 锚点 y）
    # ③ 落盘
    for dname, c in sorted(clips.items()):
        atlas = Image.new("RGBA", (cell_w * COLS, cell_h * 2), (0, 0, 0, 0))
        for i, p in enumerate(c["frames"]):
            ox = int(round(cell_w / 2 - p["ax"]))
            oy = int(round(gl - p["ay"]))
            col, row = i % COLS, i // COLS
            atlas.paste(p["img"], (col * cell_w + ox, row * cell_h + oy), p["img"])
        atlas.save(os.path.join(DST, f"{action}_{dname}.png"))
    # ④ 核对图（画出网格 + 地面线 + 中线）
    rows_n = len(clips)
    sheet = Image.new("RGB", (cell_w * COLS, cell_h * 2 * rows_n), (250, 250, 250))
    for r, dname in enumerate(sorted(clips)):
        a = Image.open(os.path.join(DST, f"{action}_{dname}.png")).convert("RGBA")
        for rr in range(2):
            for cc in range(COLS):
                piece = a.crop((cc * cell_w, rr * cell_h, cc * cell_w + cell_w, rr * cell_h + cell_h))
                sheet.paste(piece, (cc * cell_w, (r * 2 + rr) * cell_h), piece)
    d = ImageDraw.Draw(sheet)
    for r in range(rows_n):
        for rr in range(2):
            y0 = (r * 2 + rr) * cell_h
            for cc in range(COLS + 1):
                d.line([(cc * cell_w, y0), (cc * cell_w, y0 + cell_h)], fill=(225, 225, 225))
            d.line([(0, y0 + gl), (cell_w * COLS, y0 + gl)], fill=(210, 120, 120))     # 地面线
            d.line([(cell_w / 2, y0), (cell_w / 2, y0 + cell_h)], fill=(120, 120, 210))  # 中线
    for r, dname in enumerate(sorted(clips)):
        d.text((6, r * 2 * cell_h + 3),
               f"{action}_{dname}  格{cell_w}x{cell_h} 地面线y={gl} 帧={len(clips[dname]['frames'])}/源{clips[dname]['src_n']}",
               fill=(70, 70, 70))
    sheet.save(os.path.join(TMP, "verify", f"{action}.png"))
    report.append(f"{action:7s} 格 {cell_w}x{cell_h} 地面线 y={gl} | " + " ".join(
        f"{d}:{len(c['frames'])}帧(源{c['src_n']})" for d, c in sorted(clips.items())))

with open(os.path.join(TMP, "package_report.txt"), "w", encoding="utf-8") as fp:
    fp.write("\n".join(report))
print("\n".join(report))
