# -*- coding: utf-8 -*-
"""消除 walk 图集的"左右摇摆"：按头顶锚点逐帧水平重新对齐。

背景：normalize_walk_atlases.py 用"整体身体包围盒中心"对齐 x=96。过渡帧双腿
并拢时包围盒变窄且左右不对称，中心被拉偏，导致头和躯干在循环里左右横移
（实测 walk_right 帧 2/6 偏左 11px、walk_down_right 帧 3/6 偏 13px），
走起来就是身体左右摆动。

做法：以"头顶深色像素带的水平中心"为锚点（头部是紧凑块，跨帧最稳），
把 8 帧对齐到同一 x。只做整数像素水平平移，不改垂直位置、不缩放，保持像素清晰。

用法：
  python tools/fix_walk_sway.py --check   # 只测量，不写文件
  python tools/fix_walk_sway.py           # 备份原图后就地修复
"""
import argparse
import shutil
import statistics
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman"
BACKUP_DIR = ROOT / "tools" / "backups" / "walk_sway_20260919"
CELL_W, CELL_H = 192, 160

# 摆幅超标的图集（idle 系实测 ≤2px，保持不动）
FILES = ["walk_right.png", "walk_down_right.png"]

CROWN_ROWS = 22      # 头顶往下取多少行作为头部锚点带
DARK_SUM = 270       # r+g+b 低于此值算角色本体（排除亮银刀身/红色特效）


def split_frames(image: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(8):
        x = (i % 4) * CELL_W
        y = (i // 4) * CELL_H
        frames.append(image.crop((x, y, x + CELL_W, y + CELL_H)))
    return frames


def crown_center(cell: Image.Image) -> float | None:
    """头顶带的水平中心；空帧返回 None。"""
    px = cell.load()
    rows = []
    for y in range(CELL_H):
        xs = [x for x in range(CELL_W)
              if px[x, y][3] > 128 and sum(px[x, y][:3]) < DARK_SUM]
        if xs:
            rows.append((y, min(xs), max(xs)))
    if not rows:
        return None
    top = rows[0][0]
    band = [r for r in rows if r[0] < top + CROWN_ROWS]
    return (min(r[1] for r in band) + max(r[2] for r in band)) / 2.0


def shift_cell(cell: Image.Image, dx: int) -> Image.Image:
    out = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    out.alpha_composite(cell, (dx, 0))
    return out


def alpha_span(cell: Image.Image) -> tuple[int, int] | None:
    bb = cell.split()[3].getbbox()
    return (bb[0], bb[2]) if bb else None


def process(path: Path, check_only: bool) -> None:
    image = Image.open(path).convert("RGBA")
    frames = split_frames(image)
    centers = [crown_center(f) for f in frames]
    valid = [c for c in centers if c is not None]
    if not valid:
        print(f"[skip] {path.name} 无可测帧")
        return
    target = int(round(statistics.median(valid)))
    before = round(max(valid) - min(valid), 1)

    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shifted: list[Image.Image] = []
    clamp = False
    for i, frame in enumerate(frames):
        dx = 0 if centers[i] is None else target - int(round(centers[i]))
        new_frame = shift_cell(frame, dx)
        span = alpha_span(new_frame)
        if span and (span[0] < 0 or span[1] > CELL_W):
            clamp = True
        shifted.append(new_frame)
        out.alpha_composite(new_frame, ((i % 4) * CELL_W, (i // 4) * CELL_H))

    after_centers = [crown_center(f) for f in shifted]
    after_valid = [c for c in after_centers if c is not None]
    after = round(max(after_valid) - min(after_valid), 1)

    print(f"[{path.name}] 锚点 x={target}  摆幅 {before}px -> {after}px"
          f"{'  越界:有' if clamp else ''}")
    print(f"  帧内位移: {[0 if c is None else target - int(round(c)) for c in centers]}")
    if check_only:
        return
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, BACKUP_DIR / path.name)
    out.save(path, format="PNG")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只测量不写文件")
    args = ap.parse_args()
    for name in FILES:
        path = ASSET_DIR / name
        if path.exists():
            process(path, args.check)
    if not args.check:
        print(f"\n原图备份: {BACKUP_DIR}")


if __name__ == "__main__":
    main()
