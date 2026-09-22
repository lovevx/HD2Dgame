"""按作者确认的布局，把新版动作 sheet 切成"每方向一串帧"，并归一化到游戏规格。

布局（每个块 = 一个行组 = 完整 8 方向）：
  上排 3 张：down_left / down / down_right
  中排 2 张：left / right
  下排 3 张：up_left / up / up_right
一张 sheet 有 3 个这样的行组，行组之间用细横线分隔。

输出：
  .tmp_preview/new_moves/sliced/<动作>/<方向>_<序号>.png   —— 单帧（192x160，脚底 y=144，头心中线 x=96）
  .tmp_preview/new_moves/review_<动作>_<方向>.png           —— 该方向的帧条，人工核对姿态连续性
  .tmp_preview/new_moves/slice_report.txt                  —— 每方向帧数/身高/头顶 y 波动

用法: python tools/slice_new_moves.py
"""
import os
from PIL import Image, ImageDraw

SRC = "assets/characters/black_swordsman/新版动作"
OUT = ".tmp_preview/new_moves"
CELL_W, CELL_H = 192, 160          # 游戏规格单帧
FEET_Y = 144                        # 脚底锚点
CENTER_X = 96                       # 躯干中线
TARGET_H = 104                      # 目标身高（规格书）
ALPHA_MIN = 24

# 行组：每组的 3 个子行 y 范围（由 probe_new_moves_v2.py 量得）
GROUPS = [
    [(48, 261), (332, 527), (602, 802)],
    [(947, 1167), (1228, 1416), (1498, 1698)],
    [(1840, 2063), (2127, 2319), (2398, 2594)],
]
# 每个子行的方向表（顺序 = 左→右）
SUBS = [
    ["down_left", "down", "down_right"],
    ["left", "right"],
    ["up_left", "up", "up_right"],
]


def figures(alpha, x0, x1, y0, y1, gap=6, min_len=10):
    """在 x0..x1 范围内按列投影找角色块，返回 [(bx0,bx1,by0,by1)]（绝对坐标）"""
    px = alpha.load()
    col_max = [0] * (x1 - x0)
    for y in range(y0, y1):
        for x in range(x0, x1):
            v = px[x, y]
            if v > col_max[x - x0]:
                col_max[x - x0] = v
    runs, start, last = [], None, None
    for i, v in enumerate(col_max):
        if v > ALPHA_MIN:
            if start is None:
                start = i
            last = i
        elif start is not None and i - last > gap:
            if last - start + 1 >= min_len:
                runs.append((x0 + start, x0 + last))
            start = None
    if start is not None and last - start + 1 >= min_len:
        runs.append((x0 + start, x0 + last))
    out = []
    for bx0, bx1 in runs:
        top, bot = None, None
        for y in range(y0, y1):
            hit = False
            for x in range(bx0, bx1 + 1):
                if px[x, y] > ALPHA_MIN:
                    hit = True
                    break
            if hit:
                if top is None:
                    top = y
                bot = y
        if top is not None:
            out.append((bx0, bx1, top, bot))
    return out


def split_even(figs, n_groups):
    """顺序等分：一张子行里 [方向1 的4帧][方向2 的4帧]... 按序切 n_groups 份。
    （实测每子行检出 方向数×4 张，等分比按间隙聚类稳。）"""
    n = len(figs)
    if n_groups <= 0:
        return []
    base, extra = divmod(n, n_groups)
    out, i = [], 0
    for g in range(n_groups):
        take = base + (1 if g < extra else 0)
        out.append(figs[i:i + take])
        i += take
    return out


def normalize(im, box, target_h):
    """裁出角色 → 按 target_h 等比缩放 → 贴到 192x160 格（脚底 y=144、头带中线 x=96）。

    身高/锚点只按"深色像素"（角色本体，黑衣）量：攻击/闪避帧带大刀光弧，
    若按整块 alpha 包围盒归一，弧光会把身高撑大、角色被缩成小人。
    """
    bx0, bx1, by0, by1 = box
    pad = 3
    crop = im.crop((max(0, bx0 - pad), max(0, by0 - pad),
                    min(im.width, bx1 + pad + 1), min(im.height, by1 + pad + 1))).convert("RGBA")
    ap = crop.getchannel("A").load()
    lp = crop.convert("L").load()
    cw, ch = crop.size

    def is_body(x, y):
        return ap[x, y] > ALPHA_MIN and lp[x, y] < 110      # 深色 = 角色本体

    # 本体纵向范围
    top = bot = None
    for y in range(ch):
        hit = False
        for x in range(cw):
            if is_body(x, y):
                hit = True
                break
        if hit:
            if top is None:
                top = y
            bot = y
    if top is None:                                          # 兜底：全亮色帧
        top, bot = 0, ch - 1

    body_h = max(1, bot - top + 1)
    s = target_h / float(body_h)
    nw, nh = max(1, int(round(cw * s))), max(1, int(round(ch * s)))

    # 水平锚点：本体顶部 22% 区域的中线
    band_y1 = min(ch, top + max(1, int(body_h * 0.22)))
    xs = [x for y in range(top, band_y1) for x in range(cw) if is_body(x, y)]
    anchor_x = (min(xs) + max(xs)) / 2.0 if xs else cw / 2.0

    crop2 = crop.resize((nw, nh), Image.LANCZOS) if (nw, nh) != crop.size else crop
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    ox = int(round(CENTER_X - anchor_x * s))
    oy = int(round(FEET_Y - bot * s))
    cell.paste(crop2, (ox, oy), crop2)
    overflow = 1 if (ox < 0 or oy < 0 or ox + nw > CELL_W or oy + nh > CELL_H) else 0
    return cell, body_h, overflow


report = []
for name in ["跑步动画.png", "攻击动画.png", "受击动画.png", "闪避动画.png"]:
    action = name.replace("动画.png", "")
    im = Image.open(os.path.join(SRC, name)).convert("RGBA")
    alpha = im.getchannel("A")
    per_dir = {}          # dir -> [(group_index, cell, height, overflow)]
    for gi, group in enumerate(GROUPS):
        for si, (y0, y1) in enumerate(group):
            dirs = SUBS[si]
            figs = figures(alpha, 0, im.width, y0, y1 + 1)
            groups = split_even(figs, len(dirs))
            report.append(f"{action} 组{gi} 子行{si}({y0}-{y1}) 检出角色 {len(figs)} → "
                          f"{[len(g) for g in groups]} 帧组, 对应 {dirs}")
            for di, dname in enumerate(dirs):
                if di >= len(groups):
                    report.append(f"    !! {dname} 缺失")
                    continue
                per_dir.setdefault(dname, [])
                for f in groups[di]:
                    per_dir[dname].append((gi, f))

    rep_dir = os.path.join(OUT, "sliced", action)
    os.makedirs(rep_dir, exist_ok=True)
    for dname, items in per_dir.items():
        cells, heights, over = [], [], 0
        for i, (gi, box) in enumerate(items):
            cell, h, ov = normalize(im, box, TARGET_H)
            over += ov
            cells.append(cell)
            heights.append(box[3] - box[2] + 1)
            cell.save(os.path.join(rep_dir, f"{dname}_{i:02d}.png"))
        # 帧条（放大 2 倍便于肉眼核对）
        strip = Image.new("RGBA", (CELL_W * len(cells), CELL_H), (250, 250, 250, 255))
        for i, c in enumerate(cells):
            strip.paste(c, (i * CELL_W, 0), c)
        d = ImageDraw.Draw(strip)
        for i in range(len(cells)):
            d.rectangle([i * CELL_W, 0, i * CELL_W + CELL_W - 1, CELL_H - 1], outline=(215, 215, 215, 255))
        strip = strip.resize((CELL_W * len(cells) * 2, CELL_H * 2), Image.LANCZOS)
        strip.convert("RGB").save(os.path.join(OUT, f"review_{action}_{dname}.png"))
        report.append(f"  {dname}: {len(cells)} 帧, 源身高 {min(heights)}~{max(heights)}px, 出格 {over} 帧")

with open(os.path.join(OUT, "slice_report.txt"), "w", encoding="utf-8") as fp:
    fp.write("\n".join(report))
print("\n".join(report))
