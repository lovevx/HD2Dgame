# -*- coding: utf-8 -*-
"""
修正 combo_norm 连击帧的锚点/身高问题（保留透明通道，逐帧独立归一）：
  - 每帧 alpha bbox 独立缩放到统一身高 target_h（默认 108px，对齐原版 attack）
  - 脚底对齐 y=144、水平居中 x=96（格内坐标）
  - 特效/刀光超出格子的部分会被裁剪，脚本 WARN 提示

与旧 normalize_combo_frames.py 的区别：旧脚本全图集统一缩放系数，导致
"特效帧被撑大、普通帧偏小、身高忽大忽小"；本脚本逐帧 bbox 归一到统一
身高，彻底消除帧间身高波动，脚底严格贴 144。

用法：
  python tools/fix_combo_anchors.py [--height 108] [--out <dir>] [--ratio FILE=RATIO,...]
"""
import argparse
import os
import sys
from PIL import Image

BASE = r"e:\godotproject\hd-2d\assets\characters\black_swordsman"
DEFAULT_OUT = os.path.join(BASE, "combo_norm")
CELL_W, CELL_H = 192, 160
ANCHOR_X, ANCHOR_Y = 96, 144  # 脚底中心 (x), 脚底 (y)

COMBO_FILES = [
    "combo_norm/stab_down.png", "combo_norm/stab_up.png",
    "combo_norm/heavy_side.png", "combo_norm/heavy_down.png", "combo_norm/heavy_up.png",
]


def split_frames(img):
    """4 列 2 行拆 8 帧（非整数格宽也支持）。"""
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


def paste_normalized(face_frame, canvas, target_h, col, row, ratio):
    """逐帧裁剪 bbox -> 等比缩放到 target_h -> 脚底对齐锚点 -> 居中。
    ratio：身体占 bbox 高的比例（刀光/特效会拖大 bbox，默认 0.85）。"""
    w, h = face_frame.size
    alpha = face_frame.split()[3]
    bb = alpha.getbbox()
    if bb is None:
        return False  # 空帧
    x0, y0, x1, y1 = bb
    body = face_frame.crop((x0, y0, x1, y1))
    scale = target_h / max(1.0, (y1 - y0) * ratio)
    new_w = max(1, round(body.size[0] * scale))
    new_h = max(1, round(body.size[1] * scale))
    body = body.resize((new_w, new_h), Image.NEAREST)
    # 脚底对齐锚点：new_h 内的最终一行贴到 ANCHOR_Y
    final_foot = new_h - 1
    foot_center = ANCHOR_X + col * CELL_W
    bx = foot_center - new_w // 2
    by = row * CELL_H + (ANCHOR_Y - final_foot)
    # 避免把身体裁出格子：若按锚点会出格，退让到贴边（会导致脚底偏离锚点，WARN）
    if bx < col * CELL_W:
        bx = col * CELL_W
    if bx + new_w > (col + 1) * CELL_W:
        bx = (col + 1) * CELL_W - new_w
    if by < row * CELL_H:
        by = row * CELL_H
    if by + new_h > (row + 1) * CELL_H:
        by = (row + 1) * CELL_H - new_h
    clipped = (bx != foot_center - new_w // 2) or (by != row * CELL_H + (ANCHOR_Y - final_foot))
    canvas.paste(body, (bx, by), body)
    return not clipped


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--height", type=float, default=108.0, help="目标角色像素高")
    ap.add_argument("--ratio", type=float, default=0.85, help="身体占 bbox 高比例（特效帧覆盖）")
    ap.add_argument("--ratio-per", default="", help="逗号分隔 FILE=ratio 覆盖")
    ap.add_argument("--out", default=DEFAULT_OUT)
    args = ap.parse_args()

    per = {}
    for kv in args.ratio_per.split(","):
        if "=" in kv:
            k, v = kv.split("=", 1)
            per[k.strip()] = float(v)

    os.makedirs(args.out, exist_ok=True)
    for rel in COMBO_FILES:
        name = os.path.basename(rel).replace(".png", "")
        src = os.path.join(BASE, rel)
        if not os.path.exists(src):
            print(f"[skip] {rel} 不存在")
            continue
        frames = split_frames(Image.open(src).convert("RGBA"))
        canvas = Image.new("RGBA", (CELL_W * 4, CELL_H * 2), (0, 0, 0, 0))
        clean = True
        for i, f in enumerate(frames):
            r = per.get(name, args.ratio)
            if not paste_normalized(f, canvas, args.height, i % 4, i // 4, r):
                clean = False
        out_path = os.path.join(args.out, name + ".png")
        canvas.save(out_path)
        # 复测：每帧 bbox 与脚底
        sep = ", ".join(f"{_foot(Image.open(out_path).convert('RGBA'))}" for _ in [1])
        nf = split_frames(canvas)
        feet = []
        for g in nf:
            a = g.split()[3]
            bb = a.getbbox()
            feet.append("空" if bb is None else f"{bb[3]}")
        print(f"[{name:<14s}] 脚底={feet}  越界:{'否' if clean else '有(WARN)'}")
    print(f"\n输出: {args.out}")


def _foot(img):
    return ""


if __name__ == "__main__":
    main()