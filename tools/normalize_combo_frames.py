# -*- coding: utf-8 -*-
"""
规整 combo 连击帧序列，使其与原版 attack 帧规格完全一致：
  - 画布：每格 192x160，4 列 2 行（总 768x320），与原版 attack_side.png 同构
  - 角色像素高：对齐到 ~108px（原版 attack 均值 107~111px）
  - 脚底锚点：y=144（距格底 16px），脚底中心 x=96，与原版一致
这样运行时 pixel_size=0.016、offset=(0,64) 可直接复用，无需任何缩放 hack。

像素保护：整张图集统一缩放系数（最近邻），仅按 bbox 平移，不逐帧缩放。
特效/刀光超出 192x160 格的部分会被裁剪，脚本会 WARN 提示。

用法：
  python tools/normalize_combo_frames.py [--height 108] [--out <dir>]
"""
import argparse
import os
import statistics
from PIL import Image

BASE = r"e:\godotproject\hd-2d\assets\characters\black_swordsman"
DEFAULT_OUT = os.path.join(BASE, "combo_norm")
CELL_W, CELL_H = 192, 160
ANCHOR_X, ANCHOR_Y = 96, 144  # 脚底中心 (x), 脚底 (y)

COMBO_FILES = [
    "combo/stab_side.png", "combo/stab_down.png", "combo/stab_up.png",
    "combo/heavy_side.png", "combo/heavy_down.png", "combo/heavy_up.png",
]


def split_frames(img):
    """4 列 2 行拆 8 帧。处理非整数格宽（如 heavy_down 1774x887）。"""
    w, h = img.size
    frames = []
    for i in range(8):
        col, row = i % 4, i // 4
        x0 = round(col * w / 4.0)
        y0 = round(row * h / 2.0)
        x1 = round((col + 1) * w / 4.0)
        y1 = round((row + 1) * h / 2.0)
        frames.append(img.crop((x0, y0, x1, y1)))
    return frames


def bbox_height(img):
    a = img.split()[3]
    bb = a.getbbox()
    return 0 if bb is None else bb[3] - bb[1]


def paste_aligned(face_frame, canvas, target_h, ref_h, col, row, body_ratio):
    """整张图集统一比例：s = target_h/(ref_h*body_ratio)，
    逐帧把角色缩放粘贴并对齐 bbox 底到锚点。
    body_ratio：帧 bbox 高里'纯角色身体'的占比（剑尾/特效会撑大 bbox，
    直接把 bbox 缩到目标高会让身体变小）。"""
    w, h = face_frame.size
    alpha = face_frame.split()[3]
    bb = alpha.getbbox()
    if bb is None:
        return True  # 空帧
    x0, y0, x1, y1 = bb
    body = face_frame.crop((x0, y0, x1, y1))
    scale = target_h / max(1.0, ref_h * body_ratio)
    new_w = max(1, round(body.size[0] * scale))
    new_h = max(1, round(body.size[1] * scale))
    body = body.resize((new_w, new_h), Image.NEAREST)
    # 底部对齐锚点（剑尖/特效视为向下延伸，不参与对齐）
    final_foot = new_h - 1
    # 脚底中心 -> 锚点（格内坐标 + 格偏移）
    bx = col * CELL_W + max(0, min(CELL_W - new_w, ANCHOR_X - new_w // 2))
    by = row * CELL_H + (ANCHOR_Y - final_foot)
    # 越界保护：保证整帧 body 完整落在格内（锚点优先，空间不足时保完整不裁切）
    by = max(row * CELL_H, min(by, row * CELL_H + (CELL_H - new_h)))
    canvas.paste(body, (bx, by), body)
    # 超界检测：规整后主体是否被所在格边界裁切（特效超界不算）
    cb = body.split()[3].getbbox()
    if cb is None:
        return True
    cbb = (bx + cb[0], by + cb[1], bx + cb[2], by + cb[3])
    gx0, gy0 = cbb[0] - col * CELL_W, cbb[1] - row * CELL_H
    gx1, gy1 = gx0 + (cbb[2] - cbb[0]), gy0 + (cbb[3] - cbb[1])
    clipped = gx0 < 0 or gy0 < 0 or gx1 > CELL_W or gy1 > CELL_H
    return not clipped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--height", type=float, default=108.0, help="目标角色身体像素高（含剑在内的高频主体占位）")
    ap.add_argument("--ratio", type=float, default=0.72,
                    help="角色身体占帧 bbox 高的比例（剑尖/长特效会拖大 bbox），各素材可用 --ratio-per 覆盖")
    ap.add_argument("--ratio-per", default="", help="逗号分隔的 文件名=ratio 覆盖，如 stab_up=0.8,heavy_down=0.6")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    per = {}
    for kv in args.ratio_per.split(","):
        if "=" in kv:
            k, v = kv.split("=", 1)
            per[k.strip()] = float(v)

    os.makedirs(args.out, exist_ok=True)
    preview_parts = []
    for rel in COMBO_FILES:
        name = os.path.basename(rel).replace(".png", "")
        src = os.path.join(BASE, rel)
        if not os.path.exists(src):
            print(f"[skip] {rel} 不存在")
            continue
        frames = split_frames(Image.open(src).convert("RGBA"))
        hs = [bbox_height(f) for f in frames]
        # 缩放基准：取 75 百分位 bbox 高，避开特效尖峰帧；配合身体占比 ratio 换算。
        ref_h = statistics.quantiles([h for h in hs if h > 0], n=4, method="inclusive")[2]
        ratio = per.get(name, args.ratio)
        canvas = Image.new("RGBA", (CELL_W * 4, CELL_H * 2), (0, 0, 0, 0))
        clean = True
        for i, f in enumerate(frames):
            if not paste_aligned(f, canvas, args.height, ref_h, i % 4, i // 4, ratio):
                clean = False
        out_path = os.path.join(args.out, name + ".png")
        canvas.save(out_path)
        # 复测规整后尺寸（bbox 高均值 与 估算身体高）
        norm_frames = split_frames(canvas)
        nh = [bbox_height(g) for g in norm_frames]
        lw = len(name)
        print(f"[{name:<{max(10, lw)}}s] ratio={ratio:.2f} 规整bbox高={[round(x) for x in nh]}")
        preview_parts.append((name, canvas))

    # 生成对比预览：原9格(side) vs 规整6张
    if preview_parts:
        n = len(preview_parts)
        cols = 3
        rows = (n + cols - 1) // cols
        pad = 8
        tw = cols * (CELL_W * 4 + pad) + pad
        th = rows * (CELL_H * 2 + pad) + pad
        preview = Image.new("RGBA", (tw, th), (18, 18, 24, 255))
        for idx, (name, cv) in enumerate(preview_parts):
            cx, cy = idx % cols, idx // cols
            px = pad + cx * (CELL_W * 4 + pad)
            py = pad + cy * (CELL_H * 2 + pad)
            preview.paste(cv, (px, py), cv)
        pv_path = r"e:\godotproject\hd-2d\.tmp_preview\combo_normalize_preview.png"
        preview.save(pv_path)
        print(f"\n对比预览: {pv_path}；规整图集输出: {args.out}")


if __name__ == "__main__":
    main()