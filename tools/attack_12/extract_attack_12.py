# -*- coding: utf-8 -*-
"""从 最新版动作/攻击.png 提取 8 方向 × 12 帧攻击序列。

布局（作者确认 + 像素验证）：
  每块 = 3 行；行0 3 方向(down_left,down,down_right)交错、行1 2 方向(left,right)、
  行2 3 方向(up_left,up,up_right)；组内交错排列（同方向帧在行内按组间距 1184px 均匀分布）。
  每方向每块 8 帧；攻击序列 = 块0(待机站位) + 块1-3(挥击) = 32 帧/方向，均匀重采样到 12 帧。

归一化（复用 normalize_attack_video_sheets.py 口径）：
  本体(暗像素掩码 r+g+b<420，行宽>=10 排除刀身/刀光) 统一 104px，脚底锚定 y=176，
  格 224×192，输出 6×2=12 帧。

输出：
  assets/characters/black_swordsman_video/攻击_<dir>_12.png（8 张）
  .tmp_preview/attack12/ 预览图 + report

用法: python tools/attack_12/extract_attack_12.py
"""
import argparse
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "assets" / "characters" / "black_swordsman" / "最新版动作" / "攻击.png"
DST = ROOT / "assets" / "characters" / "black_swordsman_video"
TMP = ROOT / ".tmp_preview" / "attack12"
BACKUP = ROOT / "tools" / "backups" / "attack_new12_20260921"

ALPHA_MIN = 32
DARK_SUM = 560          # 暗色本体掩码阈值（560 涵盖中灰衣料；纯亮刀光 >560 仍排除）
FOOT_MIN_WIDTH = 10     # 脚底判定行宽
CELL_W, CELL_H = 224, 192
GROUND_Y = 176
TARGET_H = 104.0
TOLERANCE = 1.5
COLS, ROWS = 6, 2       # 输出网格 6×2=12
FRAMES = 12
DARK_COL_FILTER = 260   # 单列暗像素下限：滤掉刀光碎屑伪列

DIRS_ROW0 = ["down_left", "down", "down_right"]
DIRS_ROW1 = ["left", "right"]
DIRS_ROW2 = ["up_left", "up", "up_right"]
# 每个方向的组内偏移 / 组块大小（交错排列：组内第 k 个=该行第 k 方向）
COL_OFFSET = {"down_left": 0, "down": 1, "down_right": 2,
              "left": 0, "right": 1,
              "up_left": 0, "up": 1, "up_right": 2}
CHUNK = {"down_left": 3, "down": 3, "down_right": 3,
         "left": 2, "right": 2,
         "up_left": 3, "up": 3, "up_right": 3}

# 使用块 0-3（待机+挥击完整序列），行带 y 范围（对应 bands 0..11）
BLOCK_BANDS = [(51, 262), (336, 527), (607, 796),
               (896, 1175), (1182, 1435), (1464, 1699),
               (1881, 2071), (2153, 2331), (2418, 2596),
               (2774, 3000), (3048, 3227), (3313, 3492)]


def alpha_cols(img, y0, y1, gap=30, min_w=50):
    px = img.load()
    colsum = []
    for x in range(img.width):
        c = 0
        for y in range(y0, y1):
            if px[x, y][3] > ALPHA_MIN:
                c += 1
        colsum.append(c)
    ranges = []
    start = None
    last = None
    for x, c in enumerate(colsum):
        if c > 0:
            if start is None:
                start = x
            else:
                if x - last > gap:
                    ranges.append((start, last))
                    start = x
            last = x
    if start is not None:
        ranges.append((start, last))
    return [(a, b) for (a, b) in ranges if b - a + 1 >= min_w]


def dark_col_counts(img, x0, y0, x1, y1):
    px = img.load()
    n = 0
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            if px[x, y][3] > ALPHA_MIN and sum(px[x, y][:3]) < DARK_SUM:
                n += 1
    return n


def body_span(img, x0, y0, x1, y1):
    """暗色本体的上下界。相对阈值：行暗像素数 >= 帧内最高行暗数的 20% 才计入。

    绝对阈值（r+g+b<420 + 行宽>=10）在腾空/发光帧失败：身体高光使整块像素越过
    暗阈值、或双腿收窄 <10px，导致把"低矮的窄体"当成全身 → 过大/缩小错乱。
    相对阈值按强度分布取主质量（躯干+腿脚），天然排除 2~4px 细刀身，也不怕局部高光。
    """
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


def content_box(img, x0, y0, x1, y1, pad=6):
    """alpha 外接框（内容+刀光），返回扩展后的框。"""
    sub = img.crop((x0, y0, x1 + 1, y1 + 1))
    bb = sub.getchannel("A").getbbox()
    if bb is None:
        return None
    return (x0 + bb[0] - pad, y0 + bb[1] - pad, x0 + bb[2] - 1 + pad, y0 + bb[3] - 1 + pad)


def normalize_cell(img, src_box, report=None):
    """取帧内容 → 归一化到格 224×192：本体高 104px，脚底 y=176，水平居中。
    若整帧内容（含刀光/下摆/突刺腿）超过格高格宽 → 整体等比缩小放入格内，
    脚底仍贴地面线，绝不裁掉内容（裁掉会在播放时出现"下半身飞出/四肢断"）。
    """
    x0, y0, x1, y1 = src_box
    cell = img.crop((max(0, x0), max(0, y0), min(img.width - 1, x1) + 1, min(img.height - 1, y1) + 1))
    span = body_span(cell, 0, 0, cell.width - 1, cell.height - 1)
    if span is None:
        return None, None
    h = span[1] - span[0] + 1
    if abs(h - TARGET_H) < TOLERANCE:
        resized = cell
        span2 = span
    else:
        k = TARGET_H / h
        nw = max(1, round(cell.width * k))
        nh = max(1, round(cell.height * k))
        resized = cell.resize((nw, nh), Image.Resampling.LANCZOS)
        span2 = body_span(resized, 0, 0, resized.width - 1, resized.height - 1)
        if span2 is None:
            span2 = span
    # 试摆：脚底贴地面线（本体保持 104px，绝不整体缩小——缩小会让帧与帧大小跳动）。
    # 脚底以下只可能是剑尖/风衣下摆，超出 186 行的部分直接裁掉（脚/腿在 176 即止，
    # 不存在误裁下半身；不裁则动画播放时剑尖探出格子/被格截断）。
    dx = (CELL_W - resized.width) // 2
    dy = GROUND_Y - span2[1]
    out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    out.alpha_composite(resized, (dx, dy))
    cnt = out.getchannel("A").getbbox()
    if cnt and cnt[3] > CELL_H - 4:
        # 裁掉脚底以下的溢出内容（保留 176..186 的弧尖余量）
        trimmed = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        vit = resized.crop((0, 0, resized.width, resized.height))
        # 直接按合成位置重裁：新画一张，仅保留 y<186 部分
        keep_y = min(resized.height, max(0, CELL_H - 4 - dy))
        trimmed.alpha_composite(vit.crop((0, 0, vit.width, keep_y)), (dx, dy))
        out = trimmed
    if report is not None:
        rep_bottom = out.getchannel("A").getbbox()
        report.append((h, span[1], rep_bottom[3] if rep_bottom else 0))
    return out, span


def silhouette(img, x0, y0, x1, y1):
    """降采样剪影描述子（alpha+L 明度，缩到 48×40），用于判重复。"""
    from PIL import Image as _I
    cell = img.crop((x0, y0, x1 + 1, y1 + 1)).convert("RGBA")
    small = cell.resize((48, 40), _I.Resampling.BILINEAR)
    out = bytearray()
    px = small.load()
    for y in range(40):
        for x in range(48):
            r, g, b, a = px[x, y]
            lum = (r * 299 + g * 587 + b * 114) // 1000
            out.append(255 if (a > 24 and lum < 110) else 0)
    return bytes(out)


def sil_dist(a, b):
    n = min(len(a), len(b))
    return sum(abs(x - y) for x, y in zip(a, b)) / float(n)


def sample_to(n, target):
    if n <= 0:
        return []
    if n == target:
        return list(range(n))
    return [int(round(i * n / float(target))) % n for i in range(target)]


def unique_indices(raw, img, eps=2.0):
    """按剪影差异去除相邻补数重复格，返回保序的源帧下标。"""
    out = []
    prev = None
    for i, (cb, title) in enumerate(raw):
        s = silhouette(img, cb[0], cb[1], cb[2], cb[3])
        if prev is not None and sil_dist(prev, s) < eps:
            continue
        out.append(i)
        prev = s
    return out


def foot_width(cell):
    """暗色本体底部的行宽：>10px 视为有脚（两脚/单脚踩地）；窄尖角=风衣下摆/剑尖（无脚）。"""
    px = cell.load()
    for y in range(cell.height - 1, -1, -1):
        xs = [x for x in range(cell.width)
              if px[x, y][3] > ALPHA_MIN and sum(px[x, y][:3]) < DARK_SUM]
        if len(xs) >= FOOT_MIN_WIDTH // 2:
            return len(xs)
    return 0


def _final_size_clamp(sheets, dname):
    """最终帧尺寸钳制：只处理「本体明显画残」的帧（体高 < 90px 或 > 135% 中位）。
    轻微 ±10% 偏差多为刀尖/下摆计入掩码（本体已 104px），不动。
    偏残帧用前一帧站位替代，避免收招站位半截身子。
    """
    hs = []
    for cell in sheets:
        s = body_span(cell, 0, 0, cell.width - 1, cell.height - 1)
        hs.append(None if s is None else s[1] - s[0] + 1)
    meds = sorted(h for h in hs if h)
    med = meds[len(meds) // 2] if meds else 104.0
    fixed = 0
    for i in range(len(sheets)):
        h = hs[i]
        h_ok = h is not None and h >= 90 and h <= med * 1.35
        if not h_ok and i > 0:
            sheets[i] = sheets[i - 1].copy()
            fixed += 1
            print(f"    [{dname}] f{i}: 体高 {h}px 画残 -> 用前一帧站位", flush=True)
    return sheets


def pick_frames(img, dirname):
    """按方向取 4 块序列（32 帧）。返回列表 [(img_crop, title)]。"""
    if dirname in DIRS_ROW0:
        row_sel, chunk = 0, 3
    elif dirname in DIRS_ROW1:
        row_sel, chunk = 1, 2
    else:
        row_sel, chunk = 2, 3
    off = COL_OFFSET[dirname]
    frames = []
    for bi in range(4):
        y0, y1 = BLOCK_BANDS[bi * 3 + row_sel]
        cols = alpha_cols(img, y0, y1)
        # 过滤伪列（刀光碎屑）
        cols = [c for c in cols if dark_col_counts(img, c[0], y0, c[1], y1) >= DARK_COL_FILTER]
        cols.sort()
        picks = cols[off::chunk]
        for guess, (x0, x1) in enumerate(picks):
            if len(cols) < off + chunk * guess + 1:
                continue
            cb = content_box(img, x0 - 21, y0 - 90, x1 + 21, y1 + 90)
            if cb is None:
                continue
            frames.append((cb, f"b{bi}f{guess}"))
    return frames


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    img = Image.open(SRC).convert("RGBA")
    TMP.mkdir(parents=True, exist_ok=True)
    BACKUP.mkdir(parents=True, exist_ok=True)

    order = DIRS_ROW0[:1] + DIRS_ROW1[:1] + DIRS_ROW2[1:1]  # down, right, up 先预览
    all_dirs = ["down_left", "down", "down_right", "left", "right",
                "up_left", "up", "up_right"]

    for dname in all_dirs:
        raw = pick_frames(img, dname)
        print(f"{dname:11s} 源帧 {len(raw)}", flush=True)
        if args.check:
            continue
        if len(raw) < FRAMES:
            print(f"  !! 帧数不足({len(raw)}<12)，改用重采样")
        u = unique_indices(raw, img)
        print(f"  去重: 32 → {len(u)} 独立帧", flush=True)
        idxs = [u[i] for i in sample_to(len(u), FRAMES)] if len(u) > FRAMES else list(u)
        sheets = []
        hs = []
        report = []
        for i in idxs:
            cb, title = raw[i]
            cell, span = normalize_cell(img, cb, report)
            if cell is None:
                continue
            sheets.append(cell)
            hs.append(span[1] - span[0] + 1 if span else -1)
        # 不足 12 帧时以末帧垫足（收招停顿），保证 6×2 网格完整
        if 0 < len(sheets) < FRAMES:
            tail = sheets[-1].copy()
            while len(sheets) < FRAMES:
                sheets.append(tail.copy())
        if len(sheets) != FRAMES:
            print(f"  !! 归一化后只剩 {len(sheets)} 帧，跳过")
            continue
        sheets = _final_size_clamp(sheets, dname)
        out = Image.new("RGBA", (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
        for i, cell in enumerate(sheets):
            out.alpha_composite(cell, ((i % COLS) * CELL_W, (i // COLS) * CELL_H))
        dst = DST / f"攻击_{dname}_12.png"
        if dst.exists() and not args.check:
            shutil.copy2(dst, BACKUP / dst.name)
        out.save(dst)
        print(f"  源高 {min(hs)}~{max(hs)}px 已生成 {dst.name}")
        # 预览蒙太奇：12 格 2 行
        ph, pw = 128, CELL_H
        prev = Image.new("RGBA", (pw * COLS, (pw + 20) * ROWS + 10), (16, 20, 34, 255))
        dr = ImageDraw.Draw(prev)
        for i, cell in enumerate(sheets):
            spr = cell.copy()
            spr.thumbnail((pw - 10, pw - 10), Image.Resampling.BILINEAR)
            cx = (i % COLS) * pw + (pw - spr.width) // 2
            cy = (i // COLS) * (pw + 20) + 10 + (pw - spr.height) // 2
            prev.alpha_composite(spr, (cx, cy))
            dr.text((cx + (pw - spr.width) // 2, (i // COLS) * (pw + 20)), f"{i}",
                    fill=(255, 230, 120))
        prev.save(TMP / f"sheet_{dname}_12.png")
    print("done ->", DST)


if __name__ == "__main__":
    main()