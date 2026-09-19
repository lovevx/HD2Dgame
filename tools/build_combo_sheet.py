# -*- coding: utf-8 -*-
"""
把 meowa 生成的 8 帧透明动画(WebP)拆帧、可选修复指定帧、重组为
768x320 (4x2 @ 192x160) sprite sheet，落盘到 combo_norm/ 同名文件。
用法:
  python tools/build_combo_sheet.py <name> <webp> [--fix 5] [--out ...]
  name 示例: stab_side / stab_down / heavy_up
"""
import argparse, os, sys
from PIL import Image

CELL_W, CELL_H = 192, 160
BASE_OUT = r"e:\godotproject\hd-2d\assets\characters\black_swordsman\combo_norm"


def blend(a: Image.Image, b: Image.Image, t: float) -> Image.Image:
    """像素级线性混合两帧（RGBA），用于修复残影帧。"""
    return Image.blend(a, b, t)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name", help="动作名，如 stab_side")
    ap.add_argument("webp", help="meowa 输出的 8 帧透明 WebP 路径")
    ap.add_argument("--fix", default="", help="逗号分隔的帧索引=替换模式: N->blend prev/next 混合, 或 N=M 直接复制帧M")
    ap.add_argument("--out", default=BASE_OUT)
    args = ap.parse_args()

    g = Image.open(args.webp)
    if g.n_frames != 8:
        print(f"[ERROR] 需要 8 帧动画，实际 {g.n_frames} 帧")
        sys.exit(1)
    frames = []
    for i in range(g.n_frames):
        g.seek(i)
        fr = g.convert("RGBA")
        if fr.size != (CELL_W, CELL_H):
            print(f"[ERROR] 帧画布 {fr.size} 不是 {CELL_W}x{CELL_H}")
            sys.exit(1)
        frames.append(fr)

    # 帧修复
    for spec in args.fix.split(","):
        spec = spec.strip()
        if not spec:
            continue
        if "->" in spec:
            idx, mode = spec.split("->", 1)
            idx = int(idx)
            if mode.startswith("blend"):
                a, b = frames[idx - 1], frames[idx + 1]
                frames[idx] = blend(a, b, 0.5)
                print(f"frame{idx} 混合 prev/next 修复")
            else:
                print(f"[?] 未知修复模式 {mode}")
        elif "=" in spec:
            idx, src = spec.split("=")
            idx, src = int(idx), int(src)
            frames[idx] = frames[src]
            print(f"frame{idx} 复制自 frame{src}")

    canvas = Image.new("RGBA", (CELL_W * 4, CELL_H * 2), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        canvas.paste(fr, ((i % 4) * CELL_W, (i // 4) * CELL_H), fr)
    out = os.path.join(args.out, args.name + ".png")
    canvas.save(out)
    print(f"完成: {out} ({canvas.size})")
    # 复测锚点
    for i in range(8):
        cell = canvas.crop(((i % 4) * CELL_W, (i // 4) * CELL_H,
                            (i % 4 + 1) * CELL_W, (i // 4 + 1) * CELL_H))
        bb = cell.split()[3].getbbox()
        h = 0 if bb is None else bb[3] - bb[1]
        foot = 0 if bb is None else CELL_H - 1 - bb[3]
        print(f"  f{i}: 高={h} 脚底距格底={foot}")


if __name__ == "__main__":
    main()