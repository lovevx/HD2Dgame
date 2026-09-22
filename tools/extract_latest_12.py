# -*- coding: utf-8 -*-
"""从「最新版动作/*.png」按块切出 8 方向 × 12 帧动画（统一 224×192 格，本体 104px）。

## sheet 布局（用户参考图 + 像素实测）
整图 9472×7168 = **8 块列 × 8 块行**（每块 1184×896）；一块 = 一帧，含 8 个方向的角色：
  子行0 = [down_left, down, down_right]，子行1 = [left, right]，
  子行2 = [up_left, up, up_right]（3/2/3 布局）。
按块列 = 时间顺序读：帧号 = 块行 × 8 + 块列（一块行 = 8 帧）。

## 切帧：连通域（不是固定窗）
对每块做 alpha 连通域 → 正常情况下正好 8 个（每个 = 角色 + 它自己的刀/刀光，天然连在一起），
按质心 y 聚成 3 组（3/2/3）+ 组内按 x 排序 → 直接对上 8 个方向。
这样每帧只取"自己那一坨"，**不会把相邻帧/相邻方向的像素裁进来**（固定窗那套的通病）。
多于 8 坨时取最大的 8 坨，其余小碎块并进最近的坨（刀光碎屑）。

## 归一化：全动作共用一套缩放
缩放基准 = **待机 sheet 的站立高**（每方向一个）→ scale = 104 / 站立高；
所有动作、所有帧共用该方向的 scale —— 姿态矮（坐/滚/蹲）就真的矮，不会像逐帧归一化
那样把"跪坐"放大成站立高（旧 24 帧版死亡/闪避被放大的根因）。
锚点：**本体落地行**（细线状垂地刀尖/衣角不算，见 contact_row）贴地面线 GROUND_Y=176，
横向用"落地带中心"对齐格中线，脚不飘不抖。

## 输出
  assets/characters/black_swordsman_video/<动作>_<方向>_12.png   （6×2 = 12 帧，224×192）
  .tmp_preview/latest12/<动作>_<方向>_12.png                      （放大预览，人工复核）
  .tmp_preview/latest12/report.txt                               （选帧/缩放报告）

用法: python tools/extract_latest_12.py [动作名...]
"""
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "characters" / "black_swordsman" / "最新版动作"
DST = ROOT / "assets" / "characters" / "black_swordsman_video"
TMP = ROOT / ".tmp_preview" / "latest12"
BACKUP = ROOT / "tools" / "backups" / "latest12_20260921"

ALPHA_MIN = 32          # 有效像素
BODY_LUM = 110          # 本体暗部阈值（刀身/刀光是亮部，锚点只认暗部）
DS = 8                  # 连通域降采样倍率（块内 148×112 网格，够快也够准）
CC_MIN_AREA = 5         # 降采样网格上的最小连通域面积（碎屑）
CC_MERGE_PAD = 8        # 连通域 bbox 外扩（还原到原图像素）后再收紧到 alpha 实际边界
BLOCK_W, BLOCK_H = 9472 // 8, 7168 // 8      # 1184 × 896
N_BLOCKS = 8
N_FRAMES_SRC = N_BLOCKS * N_BLOCKS           # 64 帧源序列

CELL_W, CELL_H = 224, 192
GROUND_Y = 176          # 地面线（与 player_visual.GROUND_SLACK=16 同口径）
TARGET_H = 104.0        # 站立本体高（游戏内所有动作同口径）
FEET_ROWS = 8           # 横向锚点取本体掩码最下几行 = 脚（挥砍时脚不动、下摆会摆）

OUT_COLS, OUT_ROWS = 6, 2
FRAMES = OUT_COLS * OUT_ROWS                 # 12

DIRS_ROWS = [["down_left", "down", "down_right"], ["left", "right"],
             ["up_left", "up", "up_right"]]
DIRS = [d for row in DIRS_ROWS for d in row]

# 动作配置：
#   mode=loop → 自动找闭环窗口（首尾姿势最接近的**一个**周期），在 search 帧区间内扫
#   mode=once → 自动找"第一段有效动作"（剪影帧间差 > MOTION_EPS 的连续段），窗口 =
#               [段首-lead, 段尾+tail]，再用 max_span 截断（源 sheet 里同一动作常重复好几遍）
#   注意：**同一 sheet 里 8 个方向的起手帧号并不一致**（实测死亡 down 帧 17 才倒、up_right 帧 11
#   就倒了），所以窗口必须逐方向自动定，不能写死一套全局帧号。
#   循环动作的 span 区间 = 实测的单周期长度（跑步=12、行走=15 帧，取自"腿部"自相关），
#   取"一个周期"而不是两个：12 帧输出正好覆盖一圈，步态极限帧不会被抽样跳掉。
#   gait=True 的动作用"腿部描述子"判周期/取帧（只看腿，见 legs_desc）。
ACTIONS = {
    "待机": dict(mode="loop", span=(30, 40), search=(0, 63), idle=True),
    "行走": dict(mode="loop", span=(14, 16), search=(1, 58), gait=True),
    "跑步": dict(mode="loop", span=(12, 13), search=(2, 58), gait=True),
    # 攻击：起手蓄力 → 挥砍（刀光）→ 收回站立；源里第 2 遍从 30 起，max_span 截掉
    # arc=True：源 sheet 的 8 个方向**不同步**（down 的刀光在帧 30~33、down_left 在 12~15），
    # 且挥砍前有一大段"举刀定住"的静帧。所以按「蓝色刀光出现的帧」定位窗口右端，
    # 再把窗口里内容重复的定帧折叠掉，保证 12 帧里挥砍动作占比够。
    "攻击": dict(mode="once", lead=1, tail=2, max_span=22, fallback=(7, 29), arc=True),
    # 直踹：站立 → 蹬出 → 收腿；源里反复蹬了 8 遍，只取第一遍
    "直踹": dict(mode="once", lead=1, tail=2, max_span=11, fallback=(2, 13)),
    # 受击：站立 → 后仰峰值 → 回正（源里 2 遍，取第一遍）
    "受击": dict(mode="once", lead=1, tail=2, max_span=20, fallback=(8, 24)),
    # 闪避：站立 → 下蹲 → 翻滚 → 起身回正（整段就是一次闪避，不截断）
    # end_stand=True：翻滚中段帧间差很小（持续慢滚），"动作段"会提前收尾把起身段切掉，
    # 所以改用「回到站立姿势的那一帧」当窗口右端。
    "闪避": dict(mode="once", lead=1, tail=2, max_span=48, fallback=(2, 47), end_stand=True),
    # 死亡：站立 → 倒地 → 落地停住（end_settle：窗口右端卡在落定帧，别把静止平台摊进 12 帧）
    "死亡": dict(mode="once", lead=1, tail=3, max_span=16, fallback=(15, 26), end_settle=True),
}
REF_ACTION = "待机"      # 缩放基准动作：用它的站立帧高定 scale，全动作共用
REF_FRAMES = (0, 7)     # 基准帧区间（各 sheet 开头都是站立起手）
MOTION_EPS = 5.0        # 帧间剪影差阈值（站立呼吸 0~4，真动作 ≥ 10）
MOTION_MIN_LEN = 3      # 有效动作段最短帧数
MOTION_MIN_PEAK = 10.0  # 有效动作段的峰值帧间差
MERGE_GAP = 2           # 段内允许的静帧间隔（动作里的短暂停顿）
ARC_TAIL = 6            # 刀光结束后再留几帧收招（arc 类动作）
STAND_EPS = 6.0         # 剪影差低于此值 = 已回到站立姿势（end_stand 类动作的收尾判据）
SETTLE_EPS = 8.0        # 落定判据（比 MOTION_EPS 宽：源里倒地停住后仍有 ±6 的抖）

LUT_ALPHA = [255 if i > ALPHA_MIN else 0 for i in range(256)]


def runs(vals, gap, min_len):
    """把 0/1 剖面切成段（间隙 > gap 断开，段长 >= min_len）。"""
    out, start, last = [], None, None
    for i, v in enumerate(vals):
        if v > 0:
            if start is None:
                start = i
            last = i
        elif start is not None and i - last > gap:
            if last - start + 1 >= min_len:
                out.append((start, last))
            start = None
    if start is not None and last - start + 1 >= min_len:
        out.append((start, last))
    return out


def rows_with_content(mask):
    data = mask.tobytes()
    w = mask.width
    return [1 if data[y * w:(y + 1) * w].count(255) else 0 for y in range(mask.height)]


def cols_with_content(mask):
    w = mask.width
    data = mask.tobytes()
    return [1 if data[x::w].count(255) else 0 for x in range(w)]


def components(mask):
    """alpha 掩码的连通域列表 [(x0,y0,x1,y1)]（降采样 BFS，坐标已还原）。"""
    sw, sh = BLOCK_W // DS, BLOCK_H // DS
    small = mask.resize((sw, sh), Image.BOX).point(lambda v: 255 if v > 60 else 0)
    data = small.tobytes()
    seen = bytearray(sw * sh)
    out = []
    for s in range(sw * sh):
        if not data[s] or seen[s]:
            continue
        stack = [s]
        seen[s] = 1
        area = 0
        mnx = mxx = s % sw
        mny = mxy = s // sw
        while stack:
            p = stack.pop()
            x, y = p % sw, p // sw
            area += 1
            if x < mnx:
                mnx = x
            if x > mxx:
                mxx = x
            if y < mny:
                mny = y
            if y > mxy:
                mxy = y
            for q, ok in ((p - 1, x > 0), (p + 1, x < sw - 1),
                          (p - sw, y > 0), (p + sw, y < sh - 1)):
                if ok and data[q] and not seen[q]:
                    seen[q] = 1
                    stack.append(q)
        if area >= CC_MIN_AREA:
            out.append((mnx * DS, mny * DS,
                        min(BLOCK_W - 1, mxx * DS + DS - 1),
                        min(BLOCK_H - 1, mxy * DS + DS - 1)))
    return out


def merge_to_eight(boxes):
    """连通域多于 8 个时：保留最大的 8 个，其余按质心最近并进去（并成外接框）。"""
    if len(boxes) <= 8:
        return boxes
    def area(b):
        return (b[2] - b[0]) * (b[3] - b[1])
    order = sorted(range(len(boxes)), key=lambda i: -area(boxes[i]))
    keep = [boxes[i] for i in order[:8]]
    for i in order[8:]:
        bx0, by0, bx1, by1 = boxes[i]
        cx, cy = (bx0 + bx1) / 2.0, (by0 + by1) / 2.0
        best, bd = 0, 1e18
        for k, (kx0, ky0, kx1, ky1) in enumerate(keep):
            d = abs((kx0 + kx1) / 2.0 - cx) + abs((ky0 + ky1) / 2.0 - cy)
            if d < bd:
                bd, best = d, k
        kx0, ky0, kx1, ky1 = keep[best]
        keep[best] = (min(kx0, bx0), min(ky0, by0), max(kx1, bx1), max(ky1, by1))
    return keep


def assign_dirs(boxes):
    """8 个连通域 → [(方向, 框)]：按质心 y 聚 3 组（必须是 3/2/3），组内按 x 排。"""
    if len(boxes) != 8:
        return None
    cy = sorted(((b[1] + b[3]) / 2.0, i) for i, b in enumerate(boxes))
    gaps = sorted(((cy[k + 1][0] - cy[k][0], k) for k in range(7)), reverse=True)
    cut = sorted(k for _, k in gaps[:2])
    groups = [cy[:cut[0] + 1], cy[cut[0] + 1:cut[1] + 1], cy[cut[1] + 1:]]
    if [len(g) for g in groups] != [3, 2, 3]:
        return None
    out = []
    for gi, g in enumerate(groups):
        members = sorted((boxes[i][0], i) for _, i in g)
        for k, (_, i) in enumerate(members):
            out.append((DIRS_ROWS[gi][k], boxes[i]))
    return out


def scan_block(im, mask, br, bc):
    """返回 {方向: 精确 bbox}（bbox = 连通域外扩后收紧到 alpha 实际边界）。"""
    bx, by = bc * BLOCK_W, br * BLOCK_H
    block_mask = mask.crop((bx, by, bx + BLOCK_W, by + BLOCK_H))
    boxes = merge_to_eight(components(block_mask))
    picked = assign_dirs(boxes)
    if picked is None:
        return None, len(boxes)
    out = {}
    for dname, (x0, y0, x1, y1) in picked:
        cx0 = max(0, x0 - CC_MERGE_PAD)
        cy0 = max(0, y0 - CC_MERGE_PAD)
        cx1 = min(BLOCK_W - 1, x1 + CC_MERGE_PAD)
        cy1 = min(BLOCK_H - 1, y1 + CC_MERGE_PAD)
        sub = block_mask.crop((cx0, cy0, cx1 + 1, cy1 + 1))
        bb = sub.getbbox()                      # 收紧到真正有像素的范围
        if bb is None:
            continue
        out[dname] = (bx + cx0 + bb[0], by + cy0 + bb[1],
                      bx + cx0 + bb[2], by + cy0 + bb[3])
    return out, len(boxes)


def scan_sheet(action):
    """整张 sheet → [{(方向): bbox} × 64 帧]（按块行/块列的时间顺序）。"""
    path = None
    for cand in ("%s.png" % action, "%s .png" % action):
        if (SRC / cand).exists():
            path = SRC / cand
            break
    if path is None:
        return None, None
    im = Image.open(path).convert("RGBA")
    mask = im.getchannel("A").point(LUT_ALPHA)
    frames = []
    warn = []
    for br in range(N_BLOCKS):
        for bc in range(N_BLOCKS):
            got, ncc = scan_block(im, mask, br, bc)
            if got is None:
                warn.append(f"块(r{br}c{bc}) 连通域 {ncc} 个、方向配对失败")
                got = {}
            frames.append(got)
    return im, (frames, warn)


def alpha_desc(im, bb):
    """整张图（含刀与刀光）的 alpha 轮廓描述子（40×48）。

    攻击必须用这个：刀是**亮部**，而 silhouette() 只取暗部——看不见刀在动，
    于是"举刀 → 下劈"会被当成几乎没变化，等弧长取点就把下劈那几帧跳掉了
    （用户反馈："我要的是下劈，你把下劈全删了"）。用 alpha 轮廓则刀、刀光都算进变化量。
    """
    c = im.crop(bb).convert("RGBA").getchannel("A")
    s = c.resize((40, 48), Image.BILINEAR)
    px = s.load()
    out = bytearray()
    for y in range(48):
        for x in range(40):
            out.append(255 if px[x, y] > 24 else 0)
    return bytes(out)


def legs_desc(im, bb):
    """腿部剪影描述子（裁剪框下 45%，32×24），步态循环专用。

    判周期/取帧只看腿：整体剪影被大衣下摆和手臂带着走，实测跑步用它找周期会选中 13~16 帧
    （真正的一圈是 12 帧，自相关 p6=一步、p12=两步谐波），窗口就跨了 1.1~1.3 个周期，
    接缝永远对不上 → 播放时每圈顿一下（"卡卡的"）。只取腿部，p12 立刻成为最优解。
    分辨率不能太低（试过 24×16：两帧会被判成完全一样，松弛优化被假相等带偏）。
    """
    c = im.crop(bb).convert("RGBA")
    low = c.crop((0, int(c.height * 0.55), c.width, c.height))
    s = low.resize((32, 24), Image.BILINEAR)
    px = s.load()
    out = bytearray()
    for y in range(24):
        for x in range(32):
            r, g, b, a = px[x, y]
            lum = (r * 299 + g * 587 + b * 114) // 1000
            out.append(255 if (a > 24 and lum < 110) else 0)
    return bytes(out)


def silhouette(im, bb):
    """深色剪影描述子（40×48），用于帧间差异/闭环判定。

    先把内容等比缩进 160×160 的框、底边贴齐再降采样：与源图里角色画得大小无关，
    只描述"姿势"，闭环判定才不会被 AI 视频的轻微缩放带偏。
    """
    sub = im.crop(bb).convert("RGBA")
    sub.thumbnail((160, 160), Image.BILINEAR)
    canvas = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    canvas.alpha_composite(sub, ((160 - sub.width) // 2, 160 - sub.height))
    px = canvas.resize((40, 48), Image.BILINEAR).load()
    out = bytearray()
    for y in range(48):
        for x in range(40):
            r, g, b, a = px[x, y]
            lum = (r * 299 + g * 587 + b * 114) // 1000
            out.append(255 if (a > 24 and lum < 110) else 0)
    return bytes(out)


def dist(a, b):
    return sum(abs(p - q) for p, q in zip(a, b)) / float(len(a))


def pick_loop(descs, span_lo, span_hi, search):
    """闭环窗口：在 [lo,hi] 内找 (起点, 跨度) 使 dist(首帧, 首帧+跨度) 最小。"""
    s_lo, s_hi = search
    best = None
    for span in range(span_lo, span_hi + 1):
        for s in range(s_lo, min(s_hi, N_FRAMES_SRC - span - 1) + 1):
            if descs[s] is None or descs[s + span] is None:
                continue
            c = dist(descs[s], descs[s + span])
            if best is None or c < best[0]:
                best = (c, s, span)
    if best is None:
        return 0, N_FRAMES_SRC - 1
    _, s, span = best
    return s, s + span       # 首尾同姿势，取 [s, s+span)


def motion_series(descs):
    out = [0.0] * len(descs)
    for i in range(1, len(descs)):
        if descs[i] is not None and descs[i - 1] is not None:
            out[i] = dist(descs[i], descs[i - 1])
    return out


def find_segment(motion):
    """第一段有效动作 [首帧, 末帧]；找不到返回 None。

    静止的站立/倒地停住帧间差 < MOTION_EPS，真动作（倒地/挥砍/翻滚）远大于它，
    中间允许 MERGE_GAP 帧的短暂停顿（收招定帧）。峰值不足的抖动段不算动作。
    """
    segs, cur, gap = [], None, 0
    for i, m in enumerate(motion):
        if m > MOTION_EPS:
            if cur is None:
                cur = [i, i, m]
            else:
                cur[1] = i
                cur[2] = max(cur[2], m)
            gap = 0
        elif cur is not None:
            gap += 1
            if gap > MERGE_GAP:
                segs.append(cur)
                cur, gap = None, 0
    if cur is not None:
        segs.append(cur)
    for s in segs:
        if s[1] - s[0] + 1 >= MOTION_MIN_LEN and s[2] >= MOTION_MIN_PEAK:
            return s[0], s[1]
    return None


def stand_end(descs, start, ref):
    """动作回到"站立姿势"的那一帧（起身收尾）；找不到返回 None。"""
    for i in range(start + 3, N_FRAMES_SRC):
        if descs[i] is None or ref is None:
            continue
        if dist(descs[i], ref) < STAND_EPS:
            return i
    return None


def settle_end(motion, seg_start, max_span, hold=3):
    """动作"落定"的那一帧：其后 hold 帧帧间差都低于 SETTLE_EPS（倒地停住）。

    死亡源里倒地后有一长段静止平台，等距采样会把一半帧名额浪费在静止帧上
    （播放时就是"倒下去后卡住不动"）；改成窗口右端卡在落定处、再往前补站立起手帧，
    12 帧里倒地过程才占得满。
    """
    lim = min(N_FRAMES_SRC - 1, seg_start + max_span)
    for i in range(seg_start, lim + 1):
        tail = range(i + 1, min(i + 1 + hold, N_FRAMES_SRC))
        if all(motion[j] <= SETTLE_EPS for j in tail):
            return i
    return None


def once_window(motion, cfg, descs=None):
    """一次性动作的窗口：动作段 ± lead/tail，再按 max_span 截断并补足 12 帧。"""
    seg = find_segment(motion)
    if seg is None:
        lo, hi = cfg["fallback"]
    else:
        lo = max(0, seg[0] - cfg["lead"])
        hi = min(N_FRAMES_SRC - 1, min(seg[1] + cfg["tail"], seg[0] + cfg["max_span"]))
        if cfg.get("end_stand") and descs is not None:
            back = stand_end(descs, seg[0], descs[0])
            if back is not None:
                hi = min(N_FRAMES_SRC - 1, back)
        if cfg.get("end_settle"):
            st = settle_end(motion, seg[0], cfg["max_span"])
            if st is not None:
                hi = min(N_FRAMES_SRC - 1, st + 1)
    pad_back = bool(cfg.get("end_settle"))
    while hi - lo + 1 < FRAMES:          # 帧数不够：默认往后借停住帧，end_settle 往前借站立帧
        if pad_back and lo > 0:
            lo -= 1
        elif hi < N_FRAMES_SRC - 1:
            hi += 1
        elif lo > 0:
            lo -= 1
        else:
            break
    return lo, hi, seg


def blue_count(crop):
    """裁剪框里"偏蓝"像素数（刀光弧判据）。"""
    r, g, b = crop.convert("RGB").split()
    m = ImageChops.darker(
        b.point(lambda v: 255 if v > 140 else 0),
        ImageChops.darker(
            ImageChops.subtract(b, r).point(lambda v: 255 if v > 30 else 0),
            ImageChops.subtract(b, g).point(lambda v: 255 if v > 10 else 0)))
    return m.tobytes().count(255)


def overhead_runs(im, frames, d, thr=25, gap=2):
    """刀举在头顶的连续帧段：刀立起来时轮廓顶部只剩一条细刀身（顶宽 < thr）。

    源 sheet 每向挥两刀，两刀都有"举刀→下劈"；take1 = 刀从头顶往身前劈下去（看得见刀），
    take2 = 上挑 + 蹲身收刀（刀被身体挡住，看不出下劈）。用户要的"下劈"在 take1，
    所以用这个信号定位第一刀的举刀段，窗口就取"这一刀 + 它之后的收势"。
    """
    al = im.getchannel("A")
    flags = {}
    for i, f in enumerate(frames):
        bb = f.get(d)
        if bb is None:
            continue
        x0, y0, x1, y1 = bb
        c = al.crop((x0, y0, x1 + 1, y1 + 1))
        w, h = c.size
        tw = 0
        for y in range(min(10, h)):
            xs = [x for x in range(w) if c.getpixel((x, y)) > 40]
            if xs:
                tw = max(tw, max(xs) - min(xs) + 1)
        flags[i] = tw < thr
    runs, cur, skip = [], None, 0
    for i in range(N_FRAMES_SRC):
        if flags.get(i):
            if cur is None:
                cur = [i, i]
            else:
                cur[1] = i
            skip = 0
        elif cur is not None:
            skip += 1
            if skip > gap:
                runs.append(tuple(cur))
                cur, skip = None, 0
    if cur is not None:
        runs.append(tuple(cur))
    return [r for r in runs if r[1] - r[0] >= 2]      # 太短的抖动不算


def arc_run(counts, cfg):
    """刀光弧所在的连续段 → 返回 (起帧, 止帧)。

    源 sheet 每个方向其实挥了**两刀**（实测 take1 ≈ 帧 8~18、take2 ≈ 帧 28~42）。
    取"最后一次挥砍"：它前面压着一段较长的不动帧，12 帧按姿势变化量等分时会把那一段压掉，
    于是起手→挥砍推进得干脆利落；取 take1 则几乎 1:1 照抄源帧、末尾还拖几帧静止，动作发木
    （用户反馈："上下朝向的挥砍比斜/侧向干脆利落"——上下两向刀光恰好只在 take2，所以本来就走了这条路）。
    """
    thr = max(60, 0.2 * max(counts))
    runs, cur, gap = [], None, 0
    for i, c in enumerate(counts):
        if c > thr:
            if cur is None:
                cur = [i, i, c]
            else:
                cur[1] = i
                cur[2] += c
            gap = 0
        elif cur is not None:
            gap += 1
            if gap > 1:                  # 允许 1 帧断点
                runs.append(cur)
                cur, gap = None, 0
    if cur is not None:
        runs.append(cur)
    if not runs:
        return None
    biggest = max(r[2] for r in runs)
    cands = [r for r in runs if r[2] >= 0.35 * biggest]   # 太弱的碎光不算一次挥砍
    best = cands[-1]
    return best[0], best[1]


def gait_period(descs, lo, hi):
    """腿部自相关定基频周期：返回与最优同级的**最小**周期（避免选到 2 倍谐波）。"""
    vals = []
    for p in range(lo, hi + 1):
        ds = [dist(descs[s], descs[s + p]) for s in range(3, N_FRAMES_SRC - 1 - p)
              if descs[s] is not None and descs[s + p] is not None]
        vals.append((sum(ds) / len(ds) if ds else 1e9, p))
    if not vals:
        return None
    best = min(v for v, _ in vals)
    cands = [p for v, p in vals if v <= best * 1.10]
    return min(cands) if cands else None


def loop_cost(descs, picks):
    """循环片段的"晃动代价"：步长（含接缝）离散度 + 最大值 + 均值。"""
    adjs = [dist(descs[picks[k]], descs[picks[k + 1]]) for k in range(len(picks) - 1)]
    seam = dist(descs[picks[-1]], descs[picks[0]])
    allv = adjs + [seam]
    m = sum(allv) / len(allv)
    var = sum((a - m) ** 2 for a in allv) / len(allv)
    return max(adjs) * 2.0 + (var ** 0.5) * 3.0 + m * 0.2


def sample_gait(descs, cost_descs, base_period, search):
    """步态循环：窗口 = 基频周期 ~ +2 帧，扫起点，取"步长最匀（含接缝）"的那一窗。

    窗口比周期多 1~2 帧是必需的：源每圈夹着 1~2 个**冻结帧**（相邻帧整帧几乎一样，只有轻微抖动），
    12 输出对 12 源帧是 1:1，冻结帧必然进游戏 → 每圈卡一两下。多留 1~2 帧，
    等弧长取点就能把它们跳掉——**弧长必须按整身剪影算**（冻结帧只动一点点腿，
    按"只取腿部"的描述子算弧长会把它当正常帧留下来）。
    descs = 腿部描述子（只用来定周期），cost_descs = 整身剪影（算弧长 + 评估代价 + 松弛）。
    """
    best = None
    for period in (base_period, base_period + 1, base_period + 2):
        for s in range(search[0], max(search[0] + 1, search[1] - period)):
            if len([i for i in range(s, s + period) if descs[i] is not None]) < FRAMES:
                continue
            picks = sample_loop_by_pose(cost_descs, s, s + period)
            if len(picks) < FRAMES:
                continue
            cost = loop_cost(cost_descs, picks)
            if best is None or cost < best[0]:
                best = (cost, s, period, picks)
    if best is None:
        return None, None, None
    _, s, period, picks = best
    idx = [i for i in range(s, s + period) if descs[i] is not None]
    pos = relax_picks(idx, [idx.index(f) for f in picks], cost_descs, True)
    return [idx[j] for j in pos], s, period


def idle_plan(descs):
    """待机：以「站立平视」为基准帧，只在少数帧上走一次低头/抬头。

    源 idle 是"站定 → 低头沉一下 → 站定"的反复；把整圈均摊到 12 帧会变成一直在动头
    （用户反馈：待机应以平视为基准，偶尔才抬头低头）。做法：
      ① 基准帧 = 全片"最中心"的那一帧（到其余帧距离和最小 = 出现最多的站姿）；
      ② 保持段 = 基准帧所在的连续安静段（8 帧，配"安静帧停更久"的逐帧时长就停得住）；
      ③ 偏移段 = 安静段之后第一段明显偏离基准的连续帧，压到 4 帧走完低头与回位。
    返回 12 个源帧号；没有明显偏移时返回 None（退回常规循环取帧）。
    """
    valid = [i for i in range(N_FRAMES_SRC) if descs[i] is not None]
    if len(valid) < FRAMES:
        return None
    base = min((sum(dist(descs[i], descs[j]) for j in valid), i) for i in valid)[1]
    dev = {i: dist(descs[i], descs[base]) for i in valid}
    dmax = max(dev.values())
    if dmax < 1e-6:
        return None
    quiet = {i for i in valid if dev[i] < 0.25 * dmax}
    lo = hi = base
    while lo - 1 in quiet:
        lo -= 1
    while hi + 1 in quiet:
        hi += 1
    hold = list(range(lo, hi + 1))[:8]
    if len(hold) < 8:                       # 站定段太短：用别的安静帧补齐（都是同一站姿）
        for _d, i in sorted((abs(i - base), i) for i in quiet if i not in hold):
            if len(hold) >= 8:
                break
            hold.append(i)
        hold.sort()
    need = FRAMES - len(hold)
    exc, started = [], False
    for i in valid:
        if i <= hi:
            continue
        if dev[i] >= 0.45 * dmax or (started and dev[i] >= 0.20 * dmax):
            started = True
            exc.append(i)
        elif started:
            break
    if not exc:
        return None
    if len(exc) > need:          # 均匀压到 need 帧（保首末）
        exc = [exc[int(round(k * (len(exc) - 1) / float(max(need - 1, 1))))] for k in range(need)]
    return hold + exc


def pick_equal_arc(cum, n, total, frames, loop):
    """在累计弧长 cum（长度 n）上等距取 frames 个下标。

    取"弧长最接近目标"的帧，而不是"第一个超过目标的帧"：后者会把量化误差全甩到最后一步
    （实测跑步接缝差 3.6 而相邻均值 12.1，每圈在接缝处顿一下 —— 就是"卡卡的"）。
    loop=True：12 个目标均匀铺在 [0, total)，接缝那一步也算一份；
    loop=False（一次性动作）：首末帧固定（有开头有收尾），中间按等弧长铺。
    """
    span = float(frames) if loop else float(frames - 1)
    out: list[int] = []
    for k in range(frames):
        if not loop and k == 0:
            j = 0
        elif not loop and k == frames - 1:
            j = n - 1
        else:
            target = total * k / span
            jmin = (out[-1] + 1) if out else 0
            jmax = max(jmin, n - (frames - k))
            j = min(range(jmin, jmax + 1), key=lambda x: abs(cum[x] - target))
        out.append(j)
    return out


def sample_loop_by_pose(descs, lo, hi):
    """循环动作按「姿势变化量等分」取 12 帧，**把闭环接缝也算进步长**。

    源视频的节奏本身忽快忽慢（实测跑步相邻帧剪影差在 2~24 之间跳），按时间等距取 12 帧
    等于把这个不均匀原样搬进游戏：有的帧几乎没动（看着像定住）、有的帧猛跳，
    而且接缝那一步常落在慢段上 —— 每圈顿一下，就是"卡卡的"。
    改成按累计剪影差等分，并把"末帧→首帧"这一步一并算入总弧长：
    每帧推进的姿势量相同，接缝那一步也等于平均步长 → 循环匀速、不顿不跳。
    """
    idx = [i for i in range(lo, hi) if descs[i] is not None]
    n = len(idx)
    if n < 3:
        return sample_indices(lo, hi, True)
    cum = [0.0]
    for k in range(1, n):
        cum.append(cum[-1] + dist(descs[idx[k]], descs[idx[k - 1]]))
    total = cum[-1] + dist(descs[lo], descs[idx[-1]])     # + 接缝那一步
    if total < 1e-6:
        return sample_indices(lo, hi, True)
    return [idx[j] for j in pick_equal_arc(cum, n, total, FRAMES, True)]


def relax_picks(idxs, picks, descs, loop, rounds=6, span=2, movable_ends=True):
    """局部松弛：每个采样点在 ±span 帧内微调，压小「相邻剪影差的离散度 + 最大值」。

    等弧长取点只能把量化误差摊平，摊不掉——源帧不是任意相位都有的，接缝那一步常常还是
    比平均大/小一截（实测某几向 +43%~-58%，播放时就是每圈顿一下）。
    目标里同时压**标准差**和**最大值**：只压总和会让跳变挤到某一步；只压最大值则会留下
    "某两步几乎没动"的小步（源视频里存在近乎重复的相邻帧，采到就是一次顿）。
    movable_ends=False 时首末点固定（一次性动作要保证"有开头有收尾"）。
    """
    n = len(picks)
    if n < 3:
        return picks

    def step(p, q):
        return dist(descs[idxs[p]], descs[idxs[q]])

    def cost(p):
        frames = [idxs[j] for j in p]
        if loop:
            return loop_cost(descs, frames)
        adjs = [step(p[k], p[k + 1]) for k in range(len(p) - 1)]
        m = sum(adjs) / len(adjs)
        var = sum((a - m) ** 2 for a in adjs) / len(adjs)
        return max(adjs) * 2.0 + (var ** 0.5) * 3.0 + m * 0.2

    for _ in range(rounds):
        for k in range(n):
            if not movable_ends and (k == 0 or k == n - 1):
                continue
            lo = picks[k - 1] + 1 if k > 0 else 0
            hi = picks[k + 1] - 1 if k < n - 1 else len(idxs) - 1
            base = picks[k]
            best, bc = base, cost(picks)
            for cand in (base - span, base - 1, base + 1, base + span):
                if cand < lo or cand > hi or cand == base:
                    continue
                trial = picks[:]
                trial[k] = cand
                c = cost(trial)
                if c < bc - 1e-9:
                    bc, best = c, cand
            picks[k] = best
    return picks


def sample_by_pose(descs, lo, hi, relax=True):
    """按「姿势变化量等分」取 12 帧（一次性动作用）。

    按时间等距取样的问题是：源 sheet 里挥砍前后常常各压着一大段"举刀定住"，
    等距取样会把一半帧名额分给静止帧，12 帧里真正在动的只有几帧 → 动作发木、拖沓
    （用户反馈："上下朝向的挥砍比斜/侧向干脆利落"，根因就是它俩窗口长、定帧被折叠过）。
    改成按累计剪影差等分：每输出一帧，角色就推进相近的动作量——定帧自然只留 1~2 帧，
    起手/挥砍这些大幅度段拿到更多帧。首末帧始终保留（有开头有收尾）。
    """
    idx = [i for i in range(lo, hi + 1) if descs[i] is not None]
    n = len(idx)
    if n < 2:
        return sample_indices(lo, hi, False)
    cum = [0.0]
    for k in range(1, n):
        cum.append(cum[-1] + dist(descs[idx[k]], descs[idx[k - 1]]))
    total = cum[-1]
    if total < 1e-6:                     # 整段静止：退回按时间等距
        return sample_indices(lo, hi, False)
    picks = pick_equal_arc(cum, n, total, FRAMES, False)
    if relax:
        picks = relax_picks(idx, picks, descs, False, movable_ends=False)   # 首末帧固定：有开头有收尾
    return [idx[j] for j in picks]


def sample_indices(lo, hi, loop):
    """在 [lo, hi) 或 [lo, hi] 上等距取 12 个帧号（保留首尾）。"""
    if loop:
        n = hi - lo
        return [lo + int(round(k * n / float(FRAMES))) for k in range(FRAMES)]
    n = hi - lo
    return [lo + int(round(k * n / float(FRAMES - 1))) for k in range(FRAMES)]


def body_mask(sub):
    """本体暗部掩码（与 alpha 相交）：刀身/刀光都是**亮部**，锚点不能被它们带偏。

    否则左下/右下挥砍时刀扫到脚边，落地带中心被刀拉走 → 整个人物横向偏移，
    播放时就是"往后跳一下"（2026-09-21 用户反馈）；刀尖垂到脚底以下还会把人物顶起来。
    """
    a = sub.getchannel("A").point(lambda v: 255 if v > ALPHA_MIN else 0)
    lum = sub.convert("L").point(lambda v: 255 if v < BODY_LUM else 0)
    return ImageChops.multiply(a, lum)


def contact_row(alpha):
    """本体"落地行"：从底往上找第一行内容宽度 >= max(6, 25% 行宽中位) 的行。

    不能用整帧最低像素当锚点：脚底以下只可能是**垂地刀尖/风衣尖角**（细线，宽度几个像素），
    照它锚定会把整个人物顶起来——正面挥刀时刀尖探到脚底以下 20px，播放时就是"人物上跳"
    （2026-09-21 用户反馈）。按行宽中位的 25% 取阈值，细线跳过、腿脚/衣摆算数。
    """
    w, h = alpha.size
    px = alpha.load()
    counts = []
    for y in range(h):
        n = 0
        for x in range(w):
            if px[x, y] > ALPHA_MIN:
                n += 1
        counts.append(n)
    nz = sorted(c for c in counts if c > 0)
    if not nz:
        return h - 1
    thr = max(6.0, 0.25 * nz[len(nz) // 2])
    for y in range(h - 1, -1, -1):
        if counts[y] >= thr:
            return y
    return h - 1


def frame_anchor(im, bb, scale, use_feet=True):
    """算一帧的摆放参数：缩放好的图 + 锚点 (cy, cx)。

    锚点只认**本体暗部**（body_mask）：刀身/刀光是亮部，按整张 alpha 算会被人带偏。
    cy = 本体落地行（片段级竖直基准在调用处统一给），cx 取哪个特征分两种：
    - use_feet=True（攻击等一次性动作）：取**脚**（最下 FEET_ROWS 行）中心——攻击是原地的，
      用脚最稳，也不会被扫到脚边的刀带走。
    - use_feet=False（待机/行走/跑步等循环）：取**整体本体框中心**——侧向跑步时最下几行
      常常只剩一只脚，按脚对齐会让锚点在 97↔134 之间来回跳（"人物横方向一前一后地闪"）。
    """
    x0, y0, x1, y1 = bb
    sub = im.crop((x0, y0, x1 + 1, y1 + 1))
    nw = max(1, int(round(sub.width * scale)))
    nh = max(1, int(round(sub.height * scale)))
    sub = sub.resize((nw, nh), Image.LANCZOS)
    mask = body_mask(sub)
    cy = contact_row(mask)
    bob = mask.getbbox()
    if bob and use_feet:
        fb = mask.crop((0, max(0, bob[3] - FEET_ROWS + 1), nw, bob[3] + 1)).getbbox()
        cx = (fb[0] + fb[2] - 1) / 2.0 if fb else nw / 2.0
    elif bob:
        cx = (bob[0] + bob[2] - 1) / 2.0
    else:
        cx = nw / 2.0
    return sub, cy, cx


def main():
    targets = [a for a in ACTIONS if not sys.argv[1:] or a in sys.argv[1:]]
    TMP.mkdir(parents=True, exist_ok=True)
    BACKUP.mkdir(parents=True, exist_ok=True)

    # ---- 1) 缩放基准：待机 sheet 的站立高（每方向一个），全动作共用 ----
    ref_im, ref_data = scan_sheet(REF_ACTION)
    if ref_im is None:
        print("!! 缺基准动作 sheet", REF_ACTION)
        return
    ref_frames = ref_data[0]
    scale = {}
    for d in DIRS:
        hs = []
        for i in range(REF_FRAMES[0], REF_FRAMES[1] + 1):
            bb = ref_frames[i].get(d)
            if bb:
                hs.append(bb[3] - bb[1] + 1)
        hs.sort()
        ref_h = hs[len(hs) // 2] if hs else 0
        scale[d] = TARGET_H / ref_h if ref_h else 1.0
    print("缩放基准（%s 站立高 → %.0fpx）: %s" % (
        REF_ACTION, TARGET_H, ", ".join("%s %.3f" % (d, scale[d]) for d in DIRS)))
    del ref_im

    report = ["缩放基准（%s 站立帧 %d~%d 高的中位 → %.0fpx）"
              % (REF_ACTION, REF_FRAMES[0], REF_FRAMES[1], TARGET_H),
              "  " + "  ".join("%s %.3f" % (d, scale[d]) for d in DIRS), ""]

    # ---- 2) 逐个动作切帧 ----
    for action in targets:
        cfg = ACTIONS[action]
        im, (frames, warn) = scan_sheet(action)
        if im is None:
            print("!! 缺 sheet", action)
            continue
        for w in warn:
            print("  !! %s %s" % (action, w))
        report.append("=== %s  (%s)" % (
            action, "循环：自动找闭环窗口" if cfg["mode"] == "loop" else "一次性：逐方向自动定动作段"))
        for d in DIRS:
            if cfg.get("gait"):
                desc_fn = legs_desc
            elif cfg.get("arc"):
                desc_fn = alpha_desc      # 攻击要看得见刀：用整图 alpha 轮廓
            else:
                desc_fn = silhouette
            descs = [desc_fn(im, f[d]) if d in f else None for f in frames]
            cost_descs = descs if not cfg.get("gait") else \
                [silhouette(im, f[d]) if d in f else None for f in frames]
            if cfg["mode"] == "loop":
                loop, seg = True, None
                if cfg.get("idle"):
                    # 待机：站姿为基准 + 偶尔一次低头/抬头（见 idle_plan）
                    picks = idle_plan(cost_descs)
                    if picks:
                        idxs = picks
                        lo, hi = min(picks), max(picks)
                    else:
                        lo, hi = pick_loop(cost_descs, cfg["span"][0], cfg["span"][1], cfg["search"])
                        hi = max(hi, lo + FRAMES)
                        idxs = sample_loop_by_pose(cost_descs, lo, hi)
                    plan = list(idxs)
                elif cfg.get("gait"):
                    # 步态：腿部基频定周期 → 扫（周期, 起点）取"步长最匀（含接缝）"的窗口，
                    # 弧长按整身剪影算，好把源里的冻结帧跳掉（见 sample_gait）
                    base = gait_period(descs, cfg["span"][0], cfg["span"][1]) or FRAMES
                    picks, s0, period = sample_gait(descs, cost_descs, base, cfg["search"])
                    if picks is None:
                        lo, hi = pick_loop(descs, cfg["span"][0], cfg["span"][1], cfg["search"])
                        period = hi - lo
                    else:
                        lo, hi = s0, s0 + period
                    idxs = picks if picks else []
                    seg = period
                    plan = list(idxs)
                else:
                    lo, hi = pick_loop(descs, cfg["span"][0], cfg["span"][1], cfg["search"])
                    hi = max(hi, lo + FRAMES)     # 12 帧输出必须有 12 个不重复的源帧
                    idxs = sample_loop_by_pose(descs, lo, hi)
                    idxs = relax_picks(list(range(lo, hi)), [i - lo for i in idxs], descs, True)
                    idxs = [i + lo for i in idxs]
                    plan = list(idxs)
            else:
                lo, hi, seg = once_window(motion_series(descs), cfg, descs)
                loop = False
                if cfg.get("arc"):
                    # 攻击只要"下劈 + 收势"：源每向挥两刀，都有"举刀→下劈"，但只有第一刀
                    # （take1）是刀从头顶劈到身前、看得见刀；take2 是上挑 + 蹲身收刀（刀被身体挡住）。
                    # 所以窗口 = take1 举刀前 3 帧 起、到 take2 举刀前止（把上挑那段横着挪刀的挡在外面）。
                    runs = overhead_runs(im, frames, d)
                    if runs:
                        lo = max(0, runs[0][0] - 3)
                        hi = (runs[1][0] - 4) if len(runs) >= 2 else min(
                            N_FRAMES_SRC - 1, runs[0][1] + FRAMES)
                        back = stand_end(descs, runs[0][1], descs[0])
                        hi = min(hi, back) if back and back > runs[0][1] else hi
                        if hi - lo + 1 < FRAMES:
                            hi = min(N_FRAMES_SRC - 1, lo + FRAMES - 1)
                # 攻击不做平滑松弛：它会把"下劈"那一下的爆发步抹平（实测把 79 的爆发换成 72 的平滑步）
                idxs = sample_by_pose(descs, lo, hi, relax=not cfg.get("arc"))
                plan = list(idxs)
            plan = [min(a, N_FRAMES_SRC - 1) for a in plan]
            idxs = list(plan)
            cells = []
            miss = 0
            hs = []
            items = []
            for a in plan:
                bb = frames[a].get(d)
                if bb is None:
                    continue
                # 循环动作横向锚点用"整体本体框中心"（侧向跑步按脚对齐会来回跳），
                # 攻击等一次性动作用"脚"（原地、且不会被扫到脚边的刀带走）
                sub, cy, cx = frame_anchor(im, bb, scale[d], use_feet=cfg["mode"] != "loop")
                # 该帧内容顶边在"视频画面"里的 y。源 sheet 的每块就是视频的一帧（固定机位），
                # 所以跨块比较画面坐标是有效的；用裁剪框坐标则会随刀长/衣摆变化。
                top_rel = (bb[1] - (a // 8) * BLOCK_H) * scale[d]
                items.append((a, sub, cy, cx, top_rel, top_rel + cy, bb))
            if len(items) != FRAMES:
                print("  !! %s %s 只取到 %d 帧" % (action, d, len(items)))
                if not items:
                    continue
                while len(items) < FRAMES:
                    items.append(items[-1])
            # 竖直：按"视频画面坐标"摆（帧间起伏完全保留 = 源的原速弹跳），地面基准取
            # **最深的那次着地**（次大值，避免单帧衣摆异常把整体顶起来）。
            # 用中位当基准的话，着地那一帧会陷到地面线以下 10~14px；逐帧贴地又会把弹跳删掉。
            grel = sorted((it[5] for it in items), reverse=True)
            g_ref = grel[1] if len(grel) > 1 else grel[0]
            for a, sub, cy, cx, top_rel, _g, bb in items:
                y = int(round(GROUND_Y + top_rel - g_ref))
                cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
                # 横向逐帧对齐到"脚"（见 frame_anchor）
                cell.alpha_composite(sub, (int(round(CELL_W / 2.0 - cx)), y))
                cells.append(cell)
                hs.append((bb[3] - bb[1] + 1) * scale[d])
            out = Image.new("RGBA", (CELL_W * OUT_COLS, CELL_H * OUT_ROWS), (0, 0, 0, 0))
            for i, c in enumerate(cells[:FRAMES]):
                out.alpha_composite(c, ((i % OUT_COLS) * CELL_W, (i // OUT_COLS) * CELL_H))
            dst = DST / ("%s_%s_12.png" % (action, d))
            if dst.exists():
                shutil.copy2(dst, BACKUP / dst.name)
            out.save(dst)
            # 放大预览（白底 + 地面线 + 格线），便于人工复核
            pv = Image.new("RGB", out.size, (250, 250, 250))
            pv.paste(out, (0, 0), out)
            dr = ImageDraw.Draw(pv)
            for gx in range(OUT_COLS + 1):
                dr.line([(gx * CELL_W, 0), (gx * CELL_W, pv.height)], fill=(210, 210, 220))
            for gy in range(OUT_ROWS + 1):
                dr.line([(0, gy * CELL_H), (pv.width, gy * CELL_H)], fill=(210, 210, 220))
            for r in range(OUT_ROWS):
                y = r * CELL_H + GROUND_Y
                dr.line([(0, y), (pv.width, y)], fill=(120, 190, 255))
            pv.save(TMP / ("%s_%s_12.png" % (action, d)))
            # 越格检查：内容不得顶到格子边缘（顶到就会被播放时截断）
            clip = 0
            for c in cells[:FRAMES]:
                bb = c.getchannel("A").getbbox()
                if bb and (bb[1] <= 0 or bb[3] >= CELL_H - 1 or bb[0] <= 0 or bb[2] >= CELL_W - 1):
                    clip += 1
            if loop and cfg.get("gait"):
                seg_txt = " 周期%d帧" % (seg or 0)
            elif seg:
                seg_txt = " 动作段[%d,%d]" % tuple(seg)
            else:
                seg_txt = ""
            report.append("  %-11s 窗口[%d,%d]%s 源帧 %s  体高 %.0f~%.0fpx%s" % (
                d, lo, hi, seg_txt, idxs, min(hs) if hs else 0, max(hs) if hs else 0,
                ("  越格 %d 帧" % clip) if clip else ""))
        report.append("")
        with open(TMP / "report.txt", "w", encoding="utf-8") as fp:
            fp.write("\n".join(report))
        print("\n".join(report), flush=True)
    print("完成 ->", DST)


if __name__ == "__main__":
    main()
