"""新版动作打包 v2：自由排布 sheet → 每方向一张游戏规格图集 PNG。

布局（作者确认）：
  每张 sheet = 3 个块，每块内 3 行：
    上排 3 张 = down_left / down / down_right
    中排 2 张 = left / right
    下排 3 张 = up_left / up / up_right
  每个角色 = 1 帧；三块共 12 帧（不足按循环等比补采样）。

关键实现点：
  1. 定位/量身高只用「深色像素」（黑衣本体）——攻击/闪避帧的大亮色刀光弧会让
     alpha 行带糊成一片。
  2. 块边界：优先用分隔线；没有分隔线时取 9 条子行里两个最大间隙的中点。
  3. 每帧内容用**连通域**抠：alpha 降采样 4 倍做连通域标记，质心落在本行 ±60% 行高
     且横向落在本角色切界内的分量归该角色 —— 邻帧刀光不会带进来，本帧刀光不会被切掉。
  4. 对齐：全局统一缩放（本体高 104px）；纵向按本体底边贴地面线；横向按整段
     「头顶中线中位数」定统一偏移（保留出刀/突进位移，不做逐帧居中）。
  5. 画布：宽度按动作内容放宽，高度按动作所需（≥160），锚点恒在 (W/2, 地面线)。

输出：
  assets/characters/black_swordsman_new/<动作>_<方向>.png
  .tmp_preview/new_moves/verify/<动作>.png      核对图（网格 + 地面线 + 中线）
  .tmp_preview/new_moves/package_report.txt

用法: python tools/package_new_moves_v2.py
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
ROWS = 2
FRAMES = 12
LABEL_DOWN = 4

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


def alpha_mask(im):
    return im.getchannel("A").point(LUT_ALPHA)


def body_mask(im):
    return ImageChops.darker(alpha_mask(im), im.convert("L").point(LUT_DARK))


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


def sub_rows_of(bmask):
    return [r for r in segments(row_profile(bmask), 3, 6, 5) if r[1] - r[0] + 1 >= 30]


def block_bounds(subs, height, seps):
    if len(seps) >= 2:
        edges = [0] + [s[0] for s in seps] + [height]
        return list(zip(edges, edges[1:]))
    if len(subs) >= 9:
        gaps = sorted(((subs[i + 1][0] - subs[i][1], i) for i in range(len(subs) - 1)),
                      reverse=True)
        cuts = sorted(i for _, i in gaps[:2])
        edges = [0] + [int((subs[i][1] + subs[i + 1][0]) / 2) for i in cuts] + [height]
        return list(zip(edges, edges[1:]))
    return [(0, height)]


def label_components(mask_small, min_area):
    w, h = mask_small.size
    data = mask_small.tobytes()
    seen = bytearray(w * h)
    out = []
    for start in range(w * h):
        if not data[start] or seen[start]:
            continue
        stack = [start]
        seen[start] = 1
        minx = maxx = start % w
        miny = maxy = start // w
        sx = sy = area = 0
        while stack:
            p = stack.pop()
            x = p % w
            y = p // w
            area += 1
            sx += x
            sy += y
            if x < minx:
                minx = x
            if x > maxx:
                maxx = x
            if y < miny:
                miny = y
            if y > maxy:
                maxy = y
            if x > 0 and data[p - 1] and not seen[p - 1]:
                seen[p - 1] = 1
                stack.append(p - 1)
            if x < w - 1 and data[p + 1] and not seen[p + 1]:
                seen[p + 1] = 1
                stack.append(p + 1)
            if y > 0 and data[p - w] and not seen[p - w]:
                seen[p - w] = 1
                stack.append(p - w)
            if y < h - 1 and data[p + w] and not seen[p + w]:
                seen[p + w] = 1
                stack.append(p + w)
        if area >= min_area:
            out.append((minx, miny, maxx, maxy, sx / float(area), sy / float(area), area))
    return out


def body_box(mask, x0, x1, y0, y1):
    sub = mask.crop((x0, y0, x1 + 1, y1 + 1))
    bb = sub.getbbox()
    if bb is None:
        return None
    return (x0 + bb[0], y0 + bb[1], x0 + bb[2] - 1, y0 + bb[3] - 1)


def head_center_x(mask, bx0, bx1, by0, by1):
    h = max(1, int((by1 - by0 + 1) * 0.22))
    bb = mask.crop((bx0, by0, bx1 + 1, by0 + h)).getbbox()
    if bb is None:
        return (bx0 + bx1) / 2.0
    return bx0 + (bb[0] + bb[2] - 1) / 2.0


def sample_to(n, target):
    if n <= 0:
        return []
    if n == target:
        return list(range(n))
    return [int(round(i * n / float(target))) % n for i in range(target)]


def feet_lift(mask, bx0, by0, bx1, by1):
    """量"脚底被悬垂物拉低"的幅度（源图像素）。

    攻击 sheet 里第二段是"身体腾起、风衣下摆/刀尖垂地"的动态帧：
    深色最低点不是脚，把最低点贴到地面线会让整个人吊在半空（2026-09-20 踩过）。
    从包围盒底往上逐行统计深色行宽，低于阈值的连续窄行视为悬垂尾；
    主体质量（脚/双腿）的底边才是锚点。保守双门槛：
      * 抬升 ≥ 20px 才认定是真腾空（小抖动不修，避免扰动正常帧）；
      * 抬升超过本体高 45% 视为检测不可信，放弃修正。
    """
    x0, y0, x1, y1 = bx0, by0, bx1, by1
    w, h = x1 - x0 + 1, y1 - y0 + 1
    if w <= 0 or h <= 0:
        return 0
    p = mask.crop((x0, y0, x1 + 1, y1 + 1)).resize((1, h), Image.BOX)
    counts = [p.getpixel((0, y)) * w / 255.0 for y in range(h)]
    max_c = max(counts) if counts else 0.0
    thresh = max(12.0, 0.12 * max_c)
    lift = 0
    for y in range(h - 1, -1, -1):
        if counts[y] >= thresh:
            break
        lift += 1
    if lift < 20 or lift > 0.45 * h:
        return 0
    return lift


report = []
parsed = {}
body_heights_by_dir = {}
miss = 0

for fname, action in SHEETS:
    path = os.path.join(SRC, fname)
    if not os.path.exists(path):
        report.append(f"!! 缺文件 {fname}")
        continue
    im = Image.open(path).convert("RGBA")
    bmask = body_mask(im)
    amask = alpha_mask(im)
    small = amask.resize((max(1, im.width // LABEL_DOWN), max(1, im.height // LABEL_DOWN)), Image.BOX)
    comps = label_components(small.point(LUT_ALPHA), min_area=10)
    rows_all = sub_rows_of(bmask)
    seps = [r for r in segments(row_profile(bmask), 3, 6, 5) if r[1] - r[0] + 1 < 30]
    blocks = block_bounds(rows_all, im.height, seps)

    per_dir = {}
    for bi, (by0, by1) in enumerate(blocks[:3]):
        subs = [s for s in rows_all if by0 <= s[0] < by1]
        for si, (ry0, ry1) in enumerate(subs[:3]):
            dirs = SUB_DIRS[si]
            cols = segments(col_profile(bmask.crop((0, ry0, im.width, ry1 + 1))), 3, 6, 8)
            # 过滤幽灵段：段内深色像素过少的是空白缝/孤立刀尖碎片（攻击 sheet 块1
            # 曾检出 13/9 段 vs 预期 12/8，多出的幽灵段让 chunk 配对整体错位，
            # 还会产出一格近空帧）。真角色深色像素以千计，500 是安全线。
            real = []
            for c0, c1 in cols:
                crop = bmask.crop((c0, ry0, c1 + 1, ry1 + 1))
                mean = crop.resize((1, 1), Image.BOX).getpixel((0, 0))
                if mean * crop.width * crop.height / 255.0 >= 500:
                    real.append((c0, c1))
            cols = real
            if not cols:
                continue
            mids = [0] + [int((cols[i][1] + cols[i + 1][0]) / 2) for i in range(len(cols) - 1)] + [im.width]
            band_h = ry1 - ry0 + 1
            # 布局（2026-09-20 实测确认）：**每「列组」= 该子行的全部方向**
            #   上/下排每组 3 个（down_left,down,down_right / up_left,up,up_right），中排每组 2 个（left,right）；
            #   一行 4 个列组 = 4 帧。所以组内第 k 个角色对应 dirs[k]，不是"每方向连续 4 帧"。
            #   依据：行内第 3/6/9 个间隙明显更大（待机 322 vs 277），中排第 2/4/6 个更大（695 vs 333）。
            chunk = len(dirs)
            n_groups = len(cols) // chunk
            if n_groups < 1:
                continue
            idx = 0
            for _g in range(n_groups):
                for dname in dirs:
                    wx0 = mids[idx] if idx < len(mids) else 0
                    wx1 = mids[idx + 1] if idx + 1 < len(mids) else im.width
                    idx += 1
                    wx0, wx1 = max(0, wx0), min(im.width, wx1)
                    bb = body_box(bmask, wx0, min(im.width - 1, wx1 - 1), ry0, ry1)
                    if bb is None:
                        continue
                    cy0, cy1 = ry0 - int(band_h * 0.6), ry1 + int(band_h * 0.6)
                    pick = [(c[0], c[1], c[2], c[3]) for c in comps
                            if cy0 <= c[5] * LABEL_DOWN <= cy1 and wx0 <= c[4] * LABEL_DOWN <= wx1]
                    if pick:
                        x0 = min(p[0] for p in pick) * LABEL_DOWN
                        y0 = min(p[1] for p in pick) * LABEL_DOWN
                        x1 = min(im.width - 1, max(p[2] for p in pick) * LABEL_DOWN + LABEL_DOWN)
                        y1 = min(im.height - 1, max(p[3] for p in pick) * LABEL_DOWN + LABEL_DOWN)
                        content = (x0, y0, x1, y1)
                        # 本体框也取自连通域（不用子行范围裁）——躺倒/迈步姿势会越出行带
                        bx = by = bx1 = by1 = None
                        for (mx0, my0, mx1, my1) in pick:
                            bb2 = body_box(bmask,
                                           mx0 * LABEL_DOWN, min(im.width - 1, mx1 * LABEL_DOWN + LABEL_DOWN),
                                           my0 * LABEL_DOWN, min(im.height - 1, my1 * LABEL_DOWN + LABEL_DOWN))
                            if bb2 is None:
                                continue
                            bx = bb2[0] if bx is None else min(bx, bb2[0])
                            by = bb2[1] if by is None else min(by, bb2[1])
                            bx1 = bb2[2] if bx1 is None else max(bx1, bb2[2])
                            by1 = bb2[3] if by1 is None else max(by1, bb2[3])
                        body = (bx, by, bx1, by1) if bx is not None else bb
                    else:
                        content = bb
                        body = bb
                        miss += 1
                    body_heights_by_dir.setdefault(dname, []).append(body[3] - body[1] + 1)
                    per_dir.setdefault(dname, []).append(
                        {"im": im, "body": body, "content": content,
                         "head_cx": head_center_x(bmask, body[0], body[2], body[1], body[3]),
                         "lift": feet_lift(bmask, body[0], body[1], body[2], body[3])})
    # 跑步专用修剪：源图块0组0 与 块2组2 是直立站立帧（起势/收势），不属于跑步循环。
    # 留在循环里每圈会「站起来一下」（用户实机反馈"跑着跑着一抽一抽"），而且这两帧
    # 在循环接缝处相邻 → 连着两帧站立。目视核对 8 个方向都是这个规律，
    # 且这两帧的本体横跨显著小于其余帧（run_right 45px vs 80~91px）。
    if action == "run":
        for dname in sorted(per_dir.keys()):
            items = per_dir[dname]
            if len(items) >= 4:
                drop = [items[0], items[-1]]
                per_dir[dname] = items[1:-1]
                widths = sorted(it["content"][2] - it["content"][0] + 1 for it in items)
                med_w = widths[len(widths) // 2]
                report.append("  跑步修剪 %s：去掉首末站立帧（宽 %d/%d px，其余中位 %d px）→ %d 帧"
                              % (dname,
                                 drop[0]["content"][2] - drop[0]["content"][0] + 1,
                                 drop[1]["content"][2] - drop[1]["content"][0] + 1,
                                 med_w, len(per_dir[dname])))
    parsed[action] = per_dir
    print(f"  解析 {action} 完成（连通域 {len(comps)}）", flush=True)
    report.append(f"{action:7s} " + " ".join(f"{d}={len(v)}" for d, v in sorted(per_dir.items())))

print(f"  连通域未命中退回本体框：{miss} 次", flush=True)
# 逐朝向归一化：源图各朝向画得大小不一致（正面 down 实测比侧面/背面高 10~15%），
# 用单一全局系数会把源图的尺寸差原样带进游戏（用户反馈"朝下时大一圈"）。
# 每个朝向用自己的身高中位数缩放到 TARGET_BODY_H，八个朝向在游戏里一样大。
SCALE_BY_DIR = {}
for dname, hs in sorted(body_heights_by_dir.items()):
    if not hs:
        continue
    hs.sort()
    med = hs[len(hs) // 2]
    SCALE_BY_DIR[dname] = TARGET_BODY_H / float(med)
    report.append(f"  朝向 {dname:11s} 身高中位 {med:3d}px → 缩放 {SCALE_BY_DIR[dname]:.4f}")
SCALE = (sum(SCALE_BY_DIR.values()) / len(SCALE_BY_DIR)) if SCALE_BY_DIR else 0.55
report.append(f"\n逐朝向归一化：{len(SCALE_BY_DIR)} 个朝向各自缩放到本体高 {TARGET_BODY_H}px"
              f"（全局均值 {SCALE:.4f}）；连通域未命中 {miss} 次")

os.makedirs(DST, exist_ok=True)
os.makedirs(os.path.join(TMP, "verify"), exist_ok=True)

for action, per_dir in parsed.items():
    clips = {}
    for dname, items in per_dir.items():
        frames = []
        min_x = max_x = None
        max_up = max_down = 0
        dir_scale = SCALE_BY_DIR.get(dname, SCALE)   # 逐朝向缩放（见上方说明）
        for i in sample_to(len(items), FRAMES):
            it = items[i]
            cx0, cy0, cx1, cy1 = it["content"]
            crop = it["im"].crop((cx0, cy0, cx1 + 1, cy1 + 1))
            nw = max(1, int(round(crop.width * dir_scale)))
            nh = max(1, int(round(crop.height * dir_scale)))
            img = crop.resize((nw, nh), Image.LANCZOS) if (nw, nh) != crop.size else crop
            # 逐帧锚点：该帧自己的头顶中线 / 脚底（本体质量底边，
            # 已扣除风衣下摆/刀尖等悬垂尾的拉低，见 feet_lift）
            ax = (it["head_cx"] - cx0) * dir_scale
            ay = (it["body"][3] - it.get("lift", 0) - cy0) * dir_scale
            box = img.getchannel("A").point(LUT_ALPHA).getbbox()
            if box is None:
                continue
            min_x = (box[0] - ax) if min_x is None else min(min_x, box[0] - ax)
            max_x = (box[2] - ax) if max_x is None else max(max_x, box[2] - ax)
            max_up = max(max_up, ay - box[1])
            max_down = max(max_down, box[3] - ay)
            frames.append({"img": img, "ax": ax, "ay": ay})
        clips[dname] = {"frames": frames, "min_x": min_x or 0, "max_x": max_x or 0,
                        "max_up": max_up, "max_down": max_down, "src_n": len(items)}

    half_w = max(max(abs(c["min_x"]), abs(c["max_x"])) for c in clips.values()) + 6
    cell_w = max(192, int(math.ceil(half_w * 2 / 16.0) * 16))
    max_up = max(c["max_up"] for c in clips.values())
    max_down = max(c["max_down"] for c in clips.values())
    cell_h = max(160, int(math.ceil((max_up + max_down + 8) / 16.0) * 16))
    gl = cell_h - GROUND_SLACK

    for dname, c in sorted(clips.items()):
        atlas = Image.new("RGBA", (cell_w * COLS, cell_h * ROWS), (0, 0, 0, 0))
        for i, p in enumerate(c["frames"]):
            ox = int(round(cell_w / 2 - p["ax"]))
            oy = int(round(gl - p["ay"]))
            atlas.paste(p["img"], ((i % COLS) * cell_w + ox, (i // COLS) * cell_h + oy), p["img"])
        atlas.save(os.path.join(DST, f"{action}_{dname}.png"))

    rows_n = len(clips)
    sheet = Image.new("RGB", (cell_w * COLS, cell_h * ROWS * rows_n), (250, 250, 250))
    for r, dname in enumerate(sorted(clips)):
        a = Image.open(os.path.join(DST, f"{action}_{dname}.png")).convert("RGBA")
        for rr in range(ROWS):
            for cc in range(COLS):
                piece = a.crop((cc * cell_w, rr * cell_h, (cc + 1) * cell_w, (rr + 1) * cell_h))
                sheet.paste(piece, (cc * cell_w, (r * ROWS + rr) * cell_h), piece)
    d = ImageDraw.Draw(sheet)
    for r in range(rows_n):
        for rr in range(ROWS):
            y0 = (r * ROWS + rr) * cell_h
            for cc in range(COLS + 1):
                d.line([(cc * cell_w, y0), (cc * cell_w, y0 + cell_h)], fill=(228, 228, 228))
            d.line([(0, y0 + gl), (cell_w * COLS, y0 + gl)], fill=(205, 110, 110))
            d.line([(cell_w // 2, y0), (cell_w // 2, y0 + cell_h)], fill=(120, 120, 200))
    for r, dname in enumerate(sorted(clips)):
        d.text((6, r * ROWS * cell_h + 3),
               f"{action}_{dname}  格{cell_w}x{cell_h} 地面线y={gl} 帧{len(clips[dname]['frames'])}/源{clips[dname]['src_n']}",
               fill=(60, 60, 60))
    sheet.save(os.path.join(TMP, "verify", f"{action}.png"))
    report.append(f"{action:7s} 格 {cell_w}x{cell_h} 地面线 y={gl} | " + " ".join(
        f"{d}:{len(c['frames'])}帧(源{c['src_n']})" for d, c in sorted(clips.items())))
    short = sorted(d for d, c in clips.items() if c["src_n"] < FRAMES)
    if short:
        report.append(f"  !! {action} 源姿势不足 {FRAMES} 帧：{', '.join(short)}"
                      "（源图该块少画了姿势；重采样会复制一帧补格，"
                      "build_new_player_frames 会跳过重复格 → 该动作剪辑帧数更少）")

with open(os.path.join(TMP, "package_report.txt"), "w", encoding="utf-8") as fp:
    fp.write("\n".join(report))
print("\n".join(report))
