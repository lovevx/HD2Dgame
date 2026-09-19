# -*- coding: utf-8 -*-
"""
把 Gemini 网页生成的攻击帧 JPG 处理为项目规格图集：
  - 抠除棋盘格浅灰背景 -> RGBA 透明
  - 按 4 列 2 行切 8 帧
  - 规整到 768x320（每格 192x160），脚底锚点 (96,144)，角色身体高 ~108px

用法：
  python tools/gemini_attack_regenerate.py <输入jpg> <输出png> [--preview <预览png>]
"""
import argparse
import os
import statistics
import sys
from PIL import Image

CELL_W, CELL_H = 192, 160
ANCHOR_X, ANCHOR_Y = 96, 144

def probe_bg(src):
    """采样四角 + 棋盘相邻点，输出最常见的两个浅灰背景值。"""
    im = Image.open(src).convert("RGB")
    w, h = im.size
    pts = [(0, 0), (12, 0), (0, 12), (24, 0), (0, 24), (w - 1, 0), (w - 1, h - 1), (0, h - 1),
           (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]
    vals = [im.getpixel(p) for p in pts]
    from collections import Counter
    c = Counter(vals)
    return [v for v, _ in c.most_common(6)]

def key_bg(rgb, tol):
    """是否接近背景灰阶（RGB 三者相近的浅灰）。"""
    r, g, b = rgb
    return max(r, g, b) - min(r, g, b) < 20 and 150 < (r + g + b) / 3 < 245

def make_alpha(img_rgb, tol):
    """边缘连通清除：只删除与画布边缘连通的亮色（背景棋盘格），
    角色内部剑刃高光等亮色因不与边缘连通而保留。返回 RGBA。
    tol：判定“亮色背景”的灰阶下限（>tol 且 R≈G≈B 视为背景）。"""
    rgba = img_rgb.convert("RGBA")
    w, h = rgba.size

    def is_bg(r, g, b):
        return (r + g + b) // 3 > tol and max(r, g, b) - min(r, g, b) < 40

    # 边缘种子（先收集四边亮色像素）
    seeds = []
    for x in range(w):
        for y in (0, h - 1):
            r, g, b, _a = rgba.getpixel((x, y))
            if is_bg(r, g, b):
                seeds.append((x, y))
    for y in range(1, h - 1):
        for x in (0, w - 1):
            r, g, b, _a = rgba.getpixel((x, y))
            if is_bg(r, g, b):
                seeds.append((x, y))
    # BFS 从边缘向内部蔓延，标记连通背景像素
    visited = bytearray(w * h)
    clear = bytearray(w * h)
    queue = seeds
    for x, y in seeds:
        if visited[y * w + x]:
            continue
        visited[y * w + x] = 1
        clear[y * w + x] = 1
    head = 0
    while head < len(queue):
        x, y = queue[head]
        head += 1
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if nx < 0 or ny < 0 or nx >= w or ny >= h:
                continue
            idx = ny * w + nx
            if visited[idx]:
                continue
            r, g, b, _a = rgba.getpixel((nx, ny))
            if not is_bg(r, g, b):
                continue
            visited[idx] = 1
            clear[idx] = 1
            queue.append((nx, ny))
    px = rgba.load()
    for y in range(h):
        row = y * w
        for x in range(w):
            if clear[row + x]:
                rgba.putpixel((x, y), (0, 0, 0, 0))
    return rgba

def split_frames(img):
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
    w, h = face_frame.size
    alpha = face_frame.split()[3]
    bb = alpha.getbbox()
    if bb is None:
        return True
    x0, y0, x1, y1 = bb
    body = face_frame.crop((x0, y0, x1, y1))
    scale = target_h / max(1.0, ref_h * body_ratio)
    new_w = max(1, round(body.size[0] * scale))
    new_h = max(1, round(body.size[1] * scale))
    body = body.resize((new_w, new_h), Image.NEAREST)
    final_foot = new_h - 1
    bx = col * CELL_W + max(0, min(CELL_W - new_w, ANCHOR_X - new_w // 2))
    by = row * CELL_H + (ANCHOR_Y - final_foot)
    by = max(row * CELL_H, min(by, row * CELL_H + (CELL_H - new_h)))
    canvas.paste(body, (bx, by), body)
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
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--preview", default="")
    ap.add_argument("--height", type=float, default=108.0)
    ap.add_argument("--ratio", type=float, default=0.72)
    ap.add_argument("--tol", type=int, default=175, help="亮色背景灰阶下限（>tol 且 R≈G≈B 视为背景连通区域）")
    args = ap.parse_args()

    if not os.path.exists(args.src):
        print("源文件不存在:", args.src)
        sys.exit(1)
    bg = probe_bg(args.src)
    print("背景采样色:", bg)
    rgb = Image.open(args.src).convert("RGB")
    print("原始尺寸:", rgb.size, "模式:", rgb.mode)
    rgba = make_alpha(rgb, args.tol)
    frames = split_frames(rgba)
    hs = [bbox_height(f) for f in frames]
    print("抠图后各帧 bbox 高:", [round(x) for x in hs])
    ref_h = statistics.quantiles([h for h in hs if h > 0], n=4, method="inclusive")[2]
    canvas = Image.new("RGBA", (CELL_W * 4, CELL_H * 2), (0, 0, 0, 0))
    clean = True
    for i, f in enumerate(frames):
        if not paste_aligned(f, canvas, args.height, ref_h, i % 4, i // 4, args.ratio):
            clean = False
    norm_frames = split_frames(canvas)
    nh = [bbox_height(g) for g in norm_frames]
    print("规整后各帧 bbox 高:", [round(x) for x in nh], "超界:", not clean)
    canvas.save(args.out)
    print("输出:", args.out)
    if args.preview:
        canvas.save(args.preview)
        print("预览:", args.preview)

if __name__ == "__main__":
    main()