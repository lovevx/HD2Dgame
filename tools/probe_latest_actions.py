# -*- coding: utf-8 -*-
"""探测 最新版动作/*.png：块网格 → 子行 → 角色列，导出精确 bbox 表 + 故事板。

布局（用户参考图）：整图 = 8 块列 × 8 块行（每块 1184×896）；
每块含 8 方向角色，分 3 子行：子行0 = down_left/down/down_right，
子行1 = left/right，子行2 = up_left/up/up_right。块列 = 帧序号。

用法:
  python tools/probe_latest_actions.py             # 全部 sheet，打印 bbox 表
  python tools/probe_latest_actions.py 死亡.png     # 指定 sheet
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "characters" / "black_swordsman" / "最新版动作"
OUT = ROOT / ".tmp_preview" / "latest_actions"
ALPHA_MIN = 32
BLOCK_W, BLOCK_H = 9472 // 8, 7168 // 8      # 1184 × 896
DIRS_ROWS = [["down_left", "down", "down_right"], ["left", "right"],
             ["up_left", "up", "up_right"]]
DIRS = [d for row in DIRS_ROWS for d in row]
LUT = [255 if i > ALPHA_MIN else 0 for i in range(256)]


def runs(vals, gap, min_len):
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


def scan_sheet(name):
    """返回 {(br,bc,dir): (bbox_abs, subrow_band)}；bbox 为相对整图的绝对框。"""
    im = Image.open(SRC / name).convert("RGBA")
    mask_full = im.getchannel("A").point(LUT)
    fig = {}
    for br in range(8):
        for bc in range(8):
            bx, by = bc * BLOCK_W, br * BLOCK_H
            block = mask_full.crop((bx, by, bx + BLOCK_W, by + BLOCK_H))
            subs = runs(rows_with_content(block), gap=18, min_len=25)
            if len(subs) != 3:
                print(f"  !! 块(r{br}c{bc}) 子行 {len(subs)} 而非 3: {subs}")
            for si, (sy0, sy1) in enumerate(subs[:3]):
                if si >= 3:
                    break
                strip = block.crop((0, sy0, BLOCK_W, sy1 + 1))
                cols = runs(cols_with_content(strip), gap=25, min_len=20)
                names = DIRS_ROWS[si]
                if len(cols) != len(names):
                    print(f"  !! 块(r{br}c{bc}) 子行{si} 列 {len(cols)} 而非 {len(names)}")
                for ci, (cx0, cx1) in enumerate(cols[:len(names)]):
                    one = strip.crop((cx0, 0, cx1 + 1, strip.height))
                    bb = one.getbbox()
                    if bb is None:
                        continue
                    fig[(br, bc, names[ci])] = (
                        (bx + cx0 + bb[0], by + sy0 + bb[1], bx + cx0 + bb[2], by + sy0 + bb[3]),
                        (by + sy0, by + sy1),
                    )
    return im, fig


def board(im, fig, dirname, out_path, cw=190, ch=230):
    b = Image.new("RGB", (cw * 8, ch * 8), (18, 20, 30))
    dr = ImageDraw.Draw(b)
    for br in range(8):
        for bc in range(8):
            key = (br, bc, dirname)
            if key not in fig:
                continue
            (x0, y0, x1, y1), _ = fig[key]
            sub = im.crop((x0 - 8, y0 - 8, x1 + 9, y1 + 9))
            sub.thumbnail((cw - 14, ch - 14), Image.Resampling.LANCZOS)
            px = bc * cw + (cw - sub.width) // 2
            py = br * ch + (ch - sub.height) // 2
            b.paste(sub.convert("RGB"), (px, py), sub)
            dr.rectangle([bc * cw, br * ch, bc * cw + cw - 1, br * ch + ch - 1],
                         outline=(70, 80, 110))
        dr.text((4, br * ch + 4), f"br{br}", fill=(255, 220, 120))
    b.save(out_path)


def main():
    argv = sys.argv[1:]
    board_dirs = ["down"]
    if "--dirs" in argv:
        i = argv.index("--dirs")
        board_dirs = argv[i + 1].split(",")
        del argv[i:i + 2]
    names = argv or [p.name for p in sorted(SRC.glob("*.png"))]
    OUT.mkdir(parents=True, exist_ok=True)
    for name in names:
        im, fig = scan_sheet(name)
        stem = Path(name).stem.strip()
        print("=" * 100)
        print(f"{name}  图元 {len(fig)}/512")
        for d in DIRS:
            hs, ws = [], []
            print(f"  --- {d} (br行 × c0..c7) ---")
            for br in range(8):
                line = []
                for bc in range(8):
                    k = (br, bc, d)
                    if k not in fig:
                        line.append("  --  ")
                        continue
                    (x0, y0, x1, y1), _ = fig[k]
                    h, w = y1 - y0, x1 - x0
                    hs.append(h)
                    ws.append(w)
                    line.append(f"{h:3d}x{w:<3d}")
                print("   " + " ".join(line))
            if hs:
                print(f"   高 {min(hs)}~{max(hs)} (中位 {sorted(hs)[len(hs)//2]})  "
                      f"宽 {min(ws)}~{max(ws)}")
            if d in board_dirs:
                board(im, fig, d, OUT / f"{stem}_{d}_board.png")
        print()


if __name__ == "__main__":
    main()
