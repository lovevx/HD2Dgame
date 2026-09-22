"""从「Holopix 视频逐帧 sheet」抽取并归一化每个朝向的帧序列。

布局（2026-09-20 实测确认，8 张 sheet 一致）：
  每张 = 11 个块，每块 3 条子行（行内按「列组」轮方向，组数 = 12 帧）：
    上排 36 个 = 12 组 × [down_left, down, down_right]
    中排 24 个 = 12 组 × [left, right]      ← 肤色判据实测：偶=朝左、奇=朝右
    下排 36 个 = 12 组 × [up_left, up, up_right]
  最后一块只剩 5 帧/向（15/10/15）→ 每朝向约 125 帧（≈5s 视频逐帧）。
  判据：行内相邻间隙呈周期性（中排 [328, 692] 交替）→ 组内轮方向，不是每方向连续帧。

归一化（沿用项目既有口径，避免"角色乱跳"）：
  * 本体定位用**深色像素**（避开亮色刀光/水印）；
  * 逐帧锚点 = 头顶带中线（横向）+ 脚底（纵向，feet_lift 扣掉垂地衣摆/刀尖）；
  * **逐朝向**统一缩放（源图各朝向画得大小不一致，正面偏大）。

输出：
  assets/characters/black_swordsman_video/<动作>_<方向>.png   归一化后的整条帧序列
  .tmp_preview/video_frames/<动作>_report.txt                 逐朝向帧数与尺寸报告

用法: python tools/extract_video_frames.py [动作名...]
"""
import os
import sys
from PIL import Image, ImageChops

Image.MAX_IMAGE_PIXELS = None

SRC_CANDIDATES = [
    "assets/characters/black_swordsman/最新版动作",   # 2026-09-21：用户抠好透明的新版（每带 8 组、12fps 真帧）
    "assets/characters/black_swordsman/新版动作",     # 旧版（白底，需抠白）
]
DST = "assets/characters/black_swordsman_video"
TMP = ".tmp_preview/video_frames"


def resolve_sheet(action):
    """新旧两版 sheet 都支持；文件名有三种形态（含「待机 .png」这种带空格的）。"""
    for base in SRC_CANDIDATES:
        for name in ("%s.png" % action, "%s .png" % action, "%s_sprite_sheet.png" % action):
            p = os.path.join(base, name)
            if os.path.exists(p):
                return p
    return None

ALPHA_MIN = 24
DARK_MAX = 110
TARGET_BODY_H = 104
GROUND_SLACK = 16
COLS_PER_ROW = 25

LUT_ALPHA = [255 if i > ALPHA_MIN else 0 for i in range(256)]
LUT_DARK = [255 if i < DARK_MAX else 0 for i in range(256)]

SUB_DIRS = [["down_left", "down", "down_right"], ["left", "right"],
            ["up_left", "up", "up_right"]]
ACTIONS = ["待机", "行走", "跑步", "攻击", "直踹", "受击", "闪避", "死亡"]
# 攻击/直踹的刀光弧更宽、风衣垂得更低 → 用放宽的格子（与游戏内 attack 口径一致）
WIDE_CELL = {"攻击": (224, 192), "直踹": (192, 160)}


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


def row_profile(mask, ds):
    small = mask.resize((max(1, mask.width // ds), max(1, mask.height // ds)), Image.BOX)
    return [small.crop((0, y, small.width, y + 1)).resize((1, 1), Image.BOX).getpixel((0, 0))
            for y in range(small.height)]


def col_profile(mask, ds):
    small = mask.resize((max(1, mask.width // ds), max(1, mask.height // ds)), Image.BOX)
    return [small.crop((x, 0, x + 1, small.height)).resize((1, 1), Image.BOX).getpixel((0, 0))
            for x in range(small.width)]


def main_component_box(mask_crop, ds=8):
    """裁剪区里最大深色连通域的 bbox（相对裁剪区坐标）。

    为什么不用整块深色 bbox：攻击帧的**刀光/长刀与身体是分离的连通块**，
    整块 bbox 会被撑得又宽又高 —— 幅面一撑大，按身高归一化时人物就被缩成小人；
    更糟的是 feet_lift 的阈值按「最大行宽比例」算，被刀光撑大后会把角色的**细腿**
    误判成"垂地尾巴"跳过，锚点整体上移，整帧被贴到格子外（2026-09-20 踩过）。
    取最大连通域 = 身体本体，两个问题一起解决。
    """
    w, h = mask_crop.size
    sw, sh = max(1, w // ds), max(1, h // ds)
    small = mask_crop.resize((sw, sh), Image.BOX).point(lambda v: 255 if v > 40 else 0)
    data = small.tobytes()
    seen = bytearray(sw * sh)
    best = None
    best_area = 0
    for start in range(sw * sh):
        if not data[start] or seen[start]:
            continue
        stack = [start]
        seen[start] = 1
        area = 0
        minx = maxx = start % sw
        miny = maxy = start // sw
        while stack:
            p = stack.pop()
            x, y = p % sw, p // sw
            area += 1
            if x < minx:
                minx = x
            if x > maxx:
                maxx = x
            if y < miny:
                miny = y
            if y > maxy:
                maxy = y
            for q, ok in ((p - 1, x > 0), (p + 1, x < sw - 1), (p - sw, y > 0), (p + sw, y < sh - 1)):
                if ok and 0 <= q < sw * sh and data[q] and not seen[q]:
                    seen[q] = 1
                    stack.append(q)
        if area > best_area:
            best_area = area
            best = (minx, miny, maxx, maxy)
    if best is None:
        return None
    return (best[0] * ds, best[1] * ds, min(w - 1, best[2] * ds + ds - 1), min(h - 1, best[3] * ds + ds - 1))


def feet_lift(mask, bx0, by0, bx1, by1):
    """抬升量（源图像素）：从包围盒底往上跳过连续的窄行（垂地衣摆/刀尖）。

    阈值按**行宽中位数**算而不是最大行宽：最大行宽会被刀光撑大，
    阈值跟着变大就会把角色的细腿误判成"尾巴"（2026-09-20 踩过）。
    """
    w, h = bx1 - bx0 + 1, by1 - by0 + 1
    if w <= 0 or h <= 0:
        return 0
    p = mask.crop((bx0, by0, bx1 + 1, by1 + 1)).resize((1, h), Image.BOX)
    counts = sorted(p.getpixel((0, y)) * w / 255.0 for y in range(h))
    med = counts[len(counts) // 2]
    thresh = max(8.0, 0.25 * med)
    raw = [p.getpixel((0, y)) * w / 255.0 for y in range(h)]
    lift = 0
    for y in range(h - 1, -1, -1):
        if raw[y] >= thresh:
            break
        lift += 1
    return lift if lift < 0.35 * h else 0


def head_center_x(mask, bx0, bx1, by0, by1):
    hh = max(1, int((by1 - by0 + 1) * 0.22))
    bb = mask.crop((bx0, by0, bx1 + 1, by0 + hh)).getbbox()
    if bb is None:
        return (bx0 + bx1) / 2.0
    return bx0 + (bb[0] + bb[2] - 1) / 2.0


def sheet_has_alpha(im):
    """sheet 是否已自带透明背景（2026-09-21 新版用户已抠好）。

    已透明的 sheet **绝不能再过 key_out_white**：透明像素的 RGB 通常是 (0,0,0)，
    min(R,G,B)=0 → 会被整片刷成不透明黑底。
    """
    lo, _hi = im.getchannel('A').getextrema()
    return lo < 200


def parse_sheet(path):
    """解析成 {方向: [(窗口矩形, 采样序号)...]}（按时间顺序）。

    **不再逐帧找锚点**：源图每行的槽位是等间距规整网格、且整行共用地脚线，
    逐帧重新锚定/缩放反而会把检测噪声变成可见抖动（攻击帧尤其明显）。
    改成「按行固定开窗」：同一行所有帧用同一个窗口 + 同一个贴图偏移，
    横向按拟合网格的中心取，纵向按该行地脚线取 → 天生不跳。

    返回 {方向: {"win": (x0,y0,x1,y1), "base": 地脚线 y, "dirs_med_h": 身高中位}}
    """
    im = Image.open(path).convert('RGBA')
    bmask = ImageChops.darker(im.getchannel('A').point(LUT_ALPHA),
                              im.convert('L').point(LUT_DARK))
    ds = 4
    rp = row_profile(bmask, ds)
    rows = segments(rp, 1, 4, 4)
    if len(rows) < 6:
        raise RuntimeError("行带太少：%d" % len(rows))
    # —— 过高的行带按内部密度谷拆开 ——
    # 挥砍等大动作的残影/特效会在两条子行之间留下淡淡的暗像素（密度 1~4，不到 0），
    # 行带检测的 gap=4 判不干净，把两条子行粘成一带（攻击 sheet 带6 高 516px，正常 212px）。
    # 一带=两行时列剖面横向串行，窗口里塞进 3~4 个角色（2026-09-20 踩过）。
    heights = sorted(b - a + 1 for a, b in rows)
    med_bh = heights[len(heights) // 2]
    fixed = []
    for (a, b) in rows:
        todo = [(a, b)]
        while todo:
            a2, b2 = todo.pop(0)
            h2 = b2 - a2 + 1
            if h2 <= med_bh * 1.5 or h2 < 8:
                fixed.append((a2, b2))
                continue
            sub = bmask.crop((0, a2 * ds, im.width, (b2 + 1) * ds))
            small = sub.resize((max(1, sub.width // ds), max(1, sub.height // ds)), Image.BOX)
            prof = [small.crop((0, y, small.width, y + 1)).resize((1, 1), Image.BOX).getpixel((0, 0))
                    for y in range(small.height)]
            lo = min(range(2, len(prof) - 2), key=lambda y: prof[y])
            # 谷点密度得明显低于带的整体密度，否则是真·高带（角色真的画得高），不拆
            inner = sorted(prof[2:-2])
            if prof[lo] < inner[len(inner) // 2] * 0.35:
                todo.insert(0, (a2 + lo + 1, b2))
                todo.insert(0, (a2, a2 + lo))
            else:
                fixed.append((a2, b2))
    rows = fixed
    gaps = sorted(((rows[i + 1][0] - rows[i][1], i) for i in range(len(rows) - 1)),
                  reverse=True)
    n_blocks = max(1, len(rows) // 3)
    cuts = sorted(i for _, i in gaps[:n_blocks - 1])
    edges = [-1] + cuts + [len(rows) - 1]
    blocks = [rows[edges[k] + 1:edges[k + 1] + 1] for k in range(len(edges) - 1)]

    # —— 每块每方向的帧数（组数）自动检测 ——
    # 旧版 sheet 每带 12 组（每方向 125 帧），2026-09-21 新版每带 8 组（12fps 真帧）。
    # 用「段数能整除该带方向数」的众数投票；别写死 12，否则新版会把 24 段硬切成 12×2 组。
    group_votes = {}
    for bi in range(min(9, len(rows))):
        chunk = len(SUB_DIRS[bi % 3])
        r0, r1 = rows[bi]
        y0, y1 = r0 * ds, r1 * ds + ds - 1
        small = bmask.crop((0, y0, im.width, y1 + 1)).resize(
            (max(1, im.width // ds), max(1, (y1 - y0 + 1) // ds)), Image.BOX)
        cp = [small.crop((x, 0, x + 1, small.height)).resize((1, 1), Image.BOX).getpixel((0, 0))
              for x in range(small.width)]
        c = len(segments(cp, 1, 3, 3))
        if c % chunk == 0 and c // chunk >= 2:
            group_votes[c // chunk] = group_votes.get(c // chunk, 0) + 1
    groups = max(group_votes, key=group_votes.get) if group_votes else 12

    per_dir = {}
    # 窗口中心 = **该槽位自己的角色中心**（每个"列组"是一个不同的帧，x 各不相同）。
    # 坑：曾把中心换成"该朝向在所有槽位里的中位数"，结果同一方向的所有帧都裁自同一位置
    # —— 等于把同一帧复制 125 遍（alpha 相邻帧差全 0，2026-09-20 踩过）。
    # 稳定性靠"地脚线固定 + 逐朝向统一缩放"，横向就用槽位中心即可（视频是固定机位）。
    for block in blocks:
        for si, band in enumerate(block[:3]):
            ry0, ry1 = band[0] * ds, band[1] * ds + ds - 1
            dirs = SUB_DIRS[si]
            cp = col_profile(bmask.crop((0, ry0, im.width, ry1 + 1)), ds)
            cols = segments(cp, 1, 3, 3)
            real = []
            for c0, c1 in cols:
                crop = bmask.crop((c0 * ds, ry0, (c1 + 1) * ds, ry1 + 1))
                mean = crop.resize((1, 1), Image.BOX).getpixel((0, 0))
                if mean * crop.width * crop.height / 255.0 >= 400:
                    real.append((c0 * ds, (c1 + 1) * ds))
            chunk = len(dirs)
            expected = groups * chunk
            if len(real) < chunk:
                continue
            # —— 拆过宽段：残影把相邻角色粘成一段时，段宽是 2~3 个角色 ——
            widths = sorted(x1 - x0 for (x0, x1) in real)
            med_w = widths[len(widths) // 2]
            slots = []
            for (x0, x1) in real:
                k = max(1, int(round((x1 - x0) / max(1.0, med_w * 1.6))))
                if k == 1:
                    slots.append((x0, x1))
                else:
                    step = (x1 - x0) / float(k)
                    for t in range(k):
                        slots.append((int(x0 + t * step), int(x0 + (t + 1) * step) - 1))
            # —— 槽位→方向：数量正好按顺序轮排；多了/少了按 x 等距网格就近对齐 ——
            # （段计数差 1 就会让 idx%chunk 整体错位，把别的方向帧灌进这条序列）
            picked = []
            if len(slots) == expected:
                for idx, (x0, x1) in enumerate(slots):
                    picked.append((idx % chunk, (x0 + x1) / 2.0, x1 - x0))
            elif len(slots) > expected:
                cs = sorted((x0 + x1) / 2.0 for (x0, x1) in slots)
                pitch = (cs[-1] - cs[0]) / max(1, expected - 1)
                used = [False] * len(slots)
                for k in range(expected):
                    tx = cs[0] + k * pitch
                    best, bd = None, 1e18
                    for t, (x0, x1) in enumerate(slots):
                        if used[t]:
                            continue
                        d = abs((x0 + x1) / 2.0 - tx)
                        if d < bd:
                            bd, best = d, t
                    if best is not None and bd < pitch * 0.6:
                        used[best] = True
                        x0, x1 = slots[best]
                        picked.append((k % chunk, (x0 + x1) / 2.0, x1 - x0))
            else:
                # 少于期望：段有合并且拆不开，按顺序轮排（老行为），至少方向分布均匀
                for idx, (x0, x1) in enumerate(slots):
                    picked.append((idx % chunk, (x0 + x1) / 2.0, x1 - x0))
            if not picked:
                continue
            picked.sort(key=lambda t: t[1])
            bottoms = []
            for _, cx, w in picked:
                bb = bmask.crop((int(cx - w / 2), ry0, int(cx + w / 2) + 1, ry1 + 1)).getbbox()
                if bb:
                    bottoms.append(ry0 + bb[3])
            bottoms.sort()
            base = bottoms[int(len(bottoms) * 0.75)] if bottoms else ry1
            centers = [t[1] for t in picked]
            for n_i, (j, cx, w) in enumerate(picked):
                # 窗宽 = 中位宽 ×2.6，但**按相邻槽位中心距封顶**（挥砍帧段宽虚胖 3 倍时，
                # 老窗宽会把左右邻居整个裁进画面——攻击第 6~14 帧一格 3 个角色，2026-09-20）
                half = max(0.6 * med_w, min(1.3 * med_w, 0.45 * _ngap(centers, n_i)))
                win = (int(cx - half), ry0, int(cx + half), ry1)
                per_dir.setdefault(dirs[j], []).append({"win": win, "base": base})
    return per_dir, bmask


def _ngap(centers, i):
    """到最近邻槽位中心的距离；没有邻居时返回极大（不设限）。"""
    out = 1e18
    if i > 0:
        out = min(out, centers[i] - centers[i - 1])
    if i < len(centers) - 1:
        out = min(out, centers[i + 1] - centers[i])
    return out


def key_out_white(img, hi=235, span=20):
    """把白底抠成透明。

    **这些 sheet 是白底不透明**（alpha 全是 255）——直接用会把白框带进游戏；
    更坑的是：拿 alpha 通道判"两帧是否相同"会永远得出"相同"（白底 alpha 恒 255），
    一度误判成"源图只有一个姿势"（2026-09-20 踩过）。
    判据用「min(R,G,B) 高 = 接近白」，避免把肤色高光也抠掉；边缘 span 级做羽化。
    """
    r, g, b = img.getchannel('R'), img.getchannel('G'), img.getchannel('B')
    mn = ImageChops.darker(ImageChops.darker(r, g), b)
    alpha = mn.point(lambda v: 0 if v >= hi else (255 if v <= hi - span
                                                  else int((hi - v) * 255 / span)))
    out = img.copy()
    out.putalpha(alpha)
    return out


def main():
    targets = [a for a in ACTIONS if not sys.argv[1:] or a in sys.argv[1:]]
    os.makedirs(DST, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    for action in targets:
        path = resolve_sheet(action)
        if path is None:
            print("!! 缺文件", action)
            continue
        per_dir, bmask = parse_sheet(path)
        sheet = Image.open(path).convert('RGBA')
        use_alpha = sheet_has_alpha(sheet)   # 已抠好的新版直接用；白底旧版才抠白
        report = ["=== %s  (%s)" % (action, os.path.basename(path))]
        cell_w, cell_h = WIDE_CELL.get(action, (192, 160))
        gl = cell_h - GROUND_SLACK
        for dname in sorted(per_dir.keys()):
            items = per_dir[dname]
            # 该朝向的本体身高中位（决定缩放）
            hs = []
            for it in items:
                bb = bmask.crop(it["win"]).getbbox()
                if bb:
                    hs.append(bb[3] - bb[1] + 1)
            if not hs:
                continue
            # 归一基准用 **85 分位身高**，不是中位：
            # 大动作的"低姿势"帧常占多数（死亡跪倒占 2/3 帧），中位会把基准压到跪姿高，
            # 起手站立帧反被放大 40%（实测死亡站立 145px vs 待机 104px，切换动作时人突然变大）。
            # 85 分位 ≈ 动作里最常出现的"高位"（站立/跃起），与待机的 104px 口径衔接。
            hs.sort()
            ref_h = hs[int(round(0.85 * (len(hs) - 1)))]
            scale = TARGET_BODY_H / float(ref_h)
            w = items[0]["win"][2] - items[0]["win"][0]
            h = items[0]["win"][3] - items[0]["win"][1] + 1
            nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
            # 固定贴图偏移：同一方向所有帧完全一致（横向居中 + 地脚线贴地面线）
            ox = int(round((cell_w - nw) / 2.0))
            oy = int(round(gl - (items[0]["base"] - items[0]["win"][1]) * scale))
            n = len(items)
            rows_n = (n + COLS_PER_ROW - 1) // COLS_PER_ROW
            atlas = Image.new("RGBA", (cell_w * COLS_PER_ROW, cell_h * rows_n), (0, 0, 0, 0))
            for i, it in enumerate(items):
                crop = sheet.crop(it["win"]) if use_alpha else key_out_white(sheet.crop(it["win"]))
                crop = crop.resize((nw, nh), Image.LANCZOS)
                cell = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
                cell.alpha_composite(crop, (ox, oy))
                atlas.alpha_composite(cell, ((i % COLS_PER_ROW) * cell_w,
                                             (i // COLS_PER_ROW) * cell_h))
            out = os.path.join(DST, "%s_%s.png" % (action, dname))
            atlas.save(out)
            report.append("  %-11s 帧 %3d  源身高中位 %3dpx 缩放 %.3f  窗 %dx%d 格 %dx%d"
                          % (dname, n, ref_h, scale, w, h, cell_w, cell_h))
        with open(os.path.join(TMP, "%s_report.txt" % action), "w", encoding="utf-8") as fp:
            fp.write("\n".join(report))
        print("\n".join(report), flush=True)
    print("完成")


main()
