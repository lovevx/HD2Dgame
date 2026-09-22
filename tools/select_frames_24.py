"""从抽取好的整条帧序列里选 24 帧，组成衔接流畅、不乱跳的帧序列。

策略（可解释、可复现）：
  1. **找周期**（循环动作）：对待机/行走/跑步这类循环，用描述子自相似度找最小 P
     （mean_i dist(i, i+P) 最小且显著低于全局均值）→ 一圈长度 P，取 [s, s+P) 作为跨度；
     找不到明显周期就退回整条（125 帧）。
  2. **均匀布点**：在跨度内等距放 24 个点（保证覆盖整条动作弧线，不会只挑静止段）。
  3. **局部松弛**：反复微调每个点 ±2 帧，使「相邻帧姿态差之和 + 首尾衔接差（循环时）」
     最小 —— 每帧都在 ±2 帧内换，既抹掉视频抖动（AI 视频的抽帧抖动），又不会把动作顺序打乱。
  4. **报告**：打印选中帧号、相邻差的最大/均值、首尾衔接差，供人工复核。

输入：assets/characters/black_swordsman_video/<动作>_<方向>.png（extract_video_frames.py 产出）
输出：assets/characters/black_swordsman_video/<动作>_<方向>_24.png   （6×4 的 24 帧图集）
      .tmp_preview/video_frames/<动作>_<方向>_24.gif                （复核动图）
      .tmp_preview/video_frames/<动作>_24_report.txt

用法: python tools/select_frames_24.py [动作名...]
"""
import os
import sys
from PIL import Image, ImageChops

Image.MAX_IMAGE_PIXELS = None

SRC = "assets/characters/black_swordsman_video"
TMP = ".tmp_preview/video_frames"
PICK = 24
COLS = 6
DESC_W, DESC_H = 24, 20
MIN_PERIOD, MAX_PERIOD = 10, 120
CYCLE_ACTIONS = {"待机", "行走", "跑步"}
ACTIONS = ["待机", "行走", "跑步", "攻击", "直踹", "受击", "闪避", "死亡"]


def load_cells(path, cell_w, cell_h, cols_per_row):
    im = Image.open(path).convert('RGBA')
    n = (im.height // cell_h) * cols_per_row
    cells = []
    for i in range(n):
        c = im.crop(((i % cols_per_row) * cell_w, (i // cols_per_row) * cell_h,
                     (i % cols_per_row + 1) * cell_w, (i // cols_per_row + 1) * cell_h))
        if c.getchannel('A').getbbox() is None:
            break
        cells.append(c)
    return cells


A_LUT = [255 if v > 24 else 0 for v in range(256)]
D_LUT = [255 if v < 110 else 0 for v in range(256)]


def silhouette(cell):
    """深色本体掩码（alpha 且够暗）。判帧间差异**必须用它**：
    用 alpha 通道会永远"相同"（sheet 原本是白底不透明），用灰度会被大片白底稀释。"""
    return ImageChops.darker(cell.getchannel('A').point(A_LUT), cell.convert('L').point(D_LUT))


def descriptor(cell):
    return list(silhouette(cell).resize((DESC_W, DESC_H), Image.BOX).getdata())


def dist(a, b):
    s = 0
    for x, y in zip(a, b):
        s += abs(x - y)
    return s / float(len(a))


def find_period(desc):
    """返回 (周期 P, 该周期下的平均差)；没有显著周期时 P = None。"""
    n = len(desc)
    best = (None, 1e9)
    baseline = 0.0
    cnt = 0
    for i in range(0, n - 1, 3):
        baseline += dist(desc[i], desc[i + 1])
        cnt += 1
    baseline = baseline / max(1, cnt)          # 相邻帧的典型差异
    for p in range(MIN_PERIOD, min(MAX_PERIOD, n - 1) + 1, 1):
        s, c = 0.0, 0
        for i in range(0, n - p, 2):
            s += dist(desc[i], desc[i + p])
            c += 1
        if c == 0:
            continue
        m = s / c
        if m < best[1]:
            best = (p, m)
    # 判定：周期处的相似度要明显好于"随便错开"的水平（用 P=n//3 作参照）
    ref_p = max(MIN_PERIOD, n // 3)
    s, c = 0.0, 0
    for i in range(0, n - ref_p, 2):
        s += dist(desc[i], desc[i + ref_p])
        c += 1
    ref = s / max(1, c)
    if best[0] is not None and best[1] < 0.75 * ref and best[1] < 2.0 * baseline:
        return best[0]
    return None


def outlier_flags(desc):
    """离群帧：与前后帧的平均姿态差远超中位的帧（AI 视频的抽帧抖动/形变）。
    这类帧一旦被选中，播放时就是一次「乱跳」——直接从候选池剔除。"""
    n = len(desc)
    m = []
    for i in range(n):
        prev = desc[i - 1] if i > 0 else desc[i]
        nxt = desc[i + 1] if i < n - 1 else desc[i]
        m.append((dist(desc[i], prev) + dist(desc[i], nxt)) / 2.0)
    med = sorted(m)[len(m) // 2]
    return [x > 3.5 * max(med, 0.05) for x in m], med


def total_cost(desc, picks, loop):
    """以「最大相邻跳变」为主、均值为辅（minimax）：
    只压总和会让选点贴着静止段、把跳变挤到某一处；压最大值才能真正消除"乱跳"那一下。
    循环动作的接缝（末帧→首帧）单独加权——接缝跳一下比中间跳一下更显眼。"""
    adjs = [dist(desc[picks[k]], desc[picks[k + 1]]) for k in range(len(picks) - 1)]
    if not adjs:
        return 0.0
    worst = max(adjs)
    mean = sum(adjs) / len(adjs)
    penalty = worst * 3.0 + mean
    if loop:
        penalty += dist(desc[picks[-1]], desc[picks[0]]) * 1.5
    return penalty


def dark_height(cell):
    """深色本体的高度（alpha 与亮度同时满足才算，避开透明像素被当成黑色）。"""
    d = ImageChops.darker(cell.getchannel('A').point([255 if v > 24 else 0 for v in range(256)]),
                          cell.convert('L').point([255 if v < 110 else 0 for v in range(256)]))
    bb = d.getbbox()
    return bb[3] - bb[1] + 1 if bb else 0


def diff_ratio(a, b, tol=8):
    """两张 L8 图里"明显不同"的像素占比（0~1）。

    判"是否重复帧"不能用平均差：待机的呼吸/微动在 24×20 降采样下平均差 < 0.1，
    会把真实动作帧也折叠掉（125 帧只剩 10 帧，2026-09-20 踩过）。
    重复帧是**逐像素完全相同**（占比 0），真实微动也会有 1%~5% 的像素在变。
    """
    da = list(a.getdata())
    db = list(b.getdata())
    if not da or len(da) != len(db):
        return 1.0
    changed = sum(1 for x, y in zip(da, db) if abs(x - y) > tol)
    return changed / float(len(da))


def dedup_indices(cells, eps=0.5):
    """折叠"连续重复帧"，返回保留下来的原始帧号列表。

    用深色本体掩码的 48×40 描述子 + 平均差阈值判定。**不要用 alpha 通道**：
    这些 sheet 是白底不透明（alpha 恒 255），alpha 判据会得出"所有帧都相同"的错误结论。
    """
    lums = [silhouette(c).resize((48, 40), Image.BOX) for c in cells]
    ds = [list(im.getdata()) for im in lums]
    keep = [0]
    for i in range(1, len(ds)):
        if dist(ds[i], ds[keep[-1]]) > eps:
            keep.append(i)
    return keep


def pick_frames(cells, action):
    desc_all = [descriptor(c) for c in cells]
    n_all = len(desc_all)
    loop = action in CYCLE_ACTIONS
    # 行走/跑步：**不去重**。去重在源帧上不均匀折叠，"去重空间的 30 帧"≠两个步态周期
    # （2026-09-21 踩过：行走 down 被折掉 16 帧，闭环差被抬到相邻差的 2.7 倍）。
    # 源帧本身就是 12fps 等时长采样。跨度不靠估计周期（自相关被大衣摆动带偏，9~25 不等），
    # 而是**联合搜索（起点, 跨度）**：跨度 26~40、起点扫全序列，取 dist(首帧, 首帧+跨度)
    # 最小的窗口 —— 窗口首尾姿势天然重合 = 整数个步态周期，闭环由构造保证。
    if action in ("行走", "跑步"):
        uniq = list(range(n_all))
        desc = desc_all
        n = n_all
        outliers = [False] * n
        cand = list(range(n))          # 步态的极限帧（最大跨步）是必须保留的接触位，不做离群剔除
        best = None                    # (闭环差, 起点, 跨度)
        for s in range(26, min(41, n)):
            for start in range(0, n - s):
                c = dist(desc[start], desc[start + s])
                if best is None or c < best[0]:
                    best = (c, start, s)
        _c, start, span = best
        period = None                  # 不再单独报周期，跨度即整数个周期
        base_pool = list(range(start, start + span))
    else:
        uniq = dedup_indices(cells)
        desc = [desc_all[i] for i in uniq]      # 去重后的序列（在其上做全部选帧逻辑）
        n = len(desc)
        outliers, med = outlier_flags(desc)
        cand = [i for i in range(n) if not outliers[i]]
        if len(cand) < PICK:
            cand = list(range(n))
        period = find_period(desc) if loop else None
        span = period if period else n
        base_pool = [i for i in cand if i < span]
        # 护栏：候选池不足 PICK 个就退回全序列（去重后序列可能明显变短）
        if len(base_pool) < PICK:
            base_pool = list(range(n))
    # 死亡：用户要求"取到倒地那一段"（后面的起身留给复活道具）。
    # **不要在去重后的序列上做**：站立前缀和跪姿平台都被折叠掉后剩不到 20 帧，
    # 24 帧填不满会把尾段站立帧又填回来（2026-09-20 踩过）；且 hs[:10] 不再保证是站立帧，
    # 站立高会被低估。直接在原始帧上取：站立高 = 全片最高，跨度收在
    # **最后一个低于站立高 ×0.95 的帧**（从后往前扫；跪/倒姿势都比站立矮一截，
    # 尾段起立回到站立高就被剔掉）。平台段稀采样正好表达"保持倒地"。
    if action == "死亡":
        uniq = list(range(n_all))
        desc = desc_all
        n = n_all
        outliers, med = outlier_flags(desc)
        cand = [i for i in range(n) if not outliers[i]] or list(range(n))
        hs = [dark_height(cells[i]) for i in range(n)]
        stand = max(hs)
        span_end = 0
        for i in range(n - 1, -1, -1):
            # 0 < h：空帧（h=0）不算"跪伏"，否则跨度被空帧撑到序列尾、起立段又混进来
            # （2026-09-21 新死亡源 63~74 是空帧，56~62 是起立，踩过）
            if 0 < hs[i] < stand * 0.95:
                span_end = i
                break
        base_pool = [i for i in range(span_end + 1) if i in cand] or list(range(span_end + 1))
    # 均匀布点（在候选池上等距取 PICK 个，保证覆盖整条动作弧线）
    picks = [base_pool[int(round(k * (len(base_pool) - 1) / float(PICK - 1)))] for k in range(PICK)]
    picks = sorted(set(picks))
    while len(picks) < PICK and len(picks) < n:
        added = False
        for i in range(n):
            if i not in picks:
                picks.append(i)
                added = True
                break
        if not added:
            break
        picks.sort()
    # 局部松弛：每个点在自己 ±4 帧内的合法候选里找最优（3 轮）
    for _round in range(3):
        for k in range(len(picks)):
            lo = 0 if k == 0 else picks[k - 1] + 1
            hi = (n - 1) if k == len(picks) - 1 else picks[k + 1] - 1
            base = picks[k]
            best_pos, best_c = base, total_cost(desc, picks, loop)
            for c_i in cand:
                if c_i < max(lo, base - 4) or c_i > min(hi, base + 4) or c_i == base:
                    continue
                trial = picks[:]
                trial[k] = c_i
                c = total_cost(desc, trial, loop)
                if c < best_c - 1e-9:
                    best_c, best_pos = c, c_i
            picks[k] = best_pos
    # 回到原始帧号（图集里的格号），指标按原始帧计算（播放时相邻的就是这些帧）
    picks = [uniq[i] for i in picks]
    adj = [dist(desc_all[picks[k]], desc_all[picks[k + 1]]) for k in range(len(picks) - 1)]
    closure = dist(desc_all[picks[-1]], desc_all[picks[0]]) if loop else None
    return picks, adj, closure, period, span, sum(1 for o in outliers if o), n_all - n


def main():
    targets = [a for a in ACTIONS if not sys.argv[1:] or a in sys.argv[1:]]
    os.makedirs(TMP, exist_ok=True)
    for action in targets:
        files = sorted(f for f in os.listdir(SRC)
                       if f.startswith(action + "_") and f.endswith(".png")
                       and not f.endswith("_24.png"))
        if not files:
            print("!! 没有 %s 的抽取结果" % action)
            continue
        report = ["=== %s（选 %d 帧）" % (action, PICK)]
        for f in files:
            dname = f[len(action) + 1:-4]
            path = os.path.join(SRC, f)
            probe = Image.open(path)
            cw = 224 if action == "攻击" else 192
            ch = 192 if action == "攻击" else 160
            cells = load_cells(path, cw, ch, 25)
            if len(cells) < PICK:
                report.append("  %-11s 帧不足（%d）" % (dname, len(cells)))
                continue
            picks, adj, closure, period, span, n_out, n_dup = pick_frames(cells, action)
            # 输出 24 帧图集（6×4）
            atlas = Image.new("RGBA", (cw * COLS, ch * 4), (0, 0, 0, 0))
            for k, idx in enumerate(picks):
                atlas.alpha_composite(cells[idx], ((k % COLS) * cw, (k // COLS) * ch))
            atlas.save(os.path.join(SRC, "%s_%s_24.png" % (action, dname)))
            # 复核动图
            fr = []
            for idx in picks:
                c = cells[idx].convert('RGB').resize((cw, ch), Image.NEAREST)
                fr.append(c.convert('P', palette=Image.ADAPTIVE))
            fr[0].save(os.path.join(TMP, "%s_%s_24.gif" % (action, dname)),
                       save_all=True, append_images=fr[1:], duration=100, loop=0)
            mx = max(adj)
            mean = sum(adj) / len(adj)
            report.append("  %-11s 周期 %s 跨度 %3d 去重 %2d 剔除离群 %2d | 相邻差 均值 %.2f 最大 %.2f (峰均比 %.2f)%s"
                          % (dname, str(period) if period else "无", span, n_dup, n_out, mean, mx, mx / max(mean, 0.01),
                             ("  闭环差 %.2f" % closure) if closure is not None else ""))
            report.append("      选中帧号: %s" % picks)
        with open(os.path.join(TMP, "%s_24_report.txt" % action), "w", encoding="utf-8") as fp:
            fp.write("\n".join(report))
        print("\n".join(report), flush=True)
    print("完成")


main()
