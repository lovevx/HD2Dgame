# -*- coding: utf-8 -*-
"""消除 walk 图集的"走路时人忽高忽低"：逐帧纵向缩放到统一身高，脚底锚点不动。

背景：脚底固定在 y=144，所以头顶 y 的波动就是弹动幅度（规格 ≤4px）。
实测 walk_down_right 帧 1/5 头顶 y=50/51（其余 41/42），降幅 9px 像是走路时忽然
矮一截；walk_down 掉 7px、walk_up 单调漂移 5px。

姿势性质判定：帧 1/5 的身高 94px 但上半身宽 56px（其余帧 高 103 / 宽 49），
说明是"压扁＋变宽"的下蹲姿势，不是等比例缩小 —— 因此只做**纵向**缩放，
等比缩放会把已经偏宽的姿势再撑宽。

做法：逐帧把角色本体高度缩放到本图集中位数（脚底对齐原位置），
偏差 < TOLERANCE 的帧原样保留不重采样。水平方向不动（头顶横移已在
fix_walk_sway.py 里对齐，不受纵向缩放影响）。

用法：
  python tools/normalize_walk_height.py --check   # 只测量，不写文件
  python tools/normalize_walk_height.py           # 备份原图后就地修复
"""
import argparse
import shutil
import statistics
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman"
BACKUP_DIR = ROOT / "tools" / "backups" / "walk_height_20260919"
CELL_W, CELL_H = 192, 160
GROUND_Y = 144
TOLERANCE = 1.5  # 身高偏差小于该值就不重采样，保持原像素

# 头顶 y 波动超标的图集（walk_right 2px、walk_up_right 4px 已达标，不动）
FILES = ["walk_down_right.png", "walk_down.png", "walk_up.png"]


def split_frames(image: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(8):
        x = (i % 4) * CELL_W
        y = (i // 4) * CELL_H
        frames.append(image.crop((x, y, x + CELL_W, y + CELL_H)))
    return frames


def body_span(cell: Image.Image) -> tuple[int, int] | None:
    """角色本体（深色衣物/头发/靴子，排除亮银刀身与红色特效）的上下界。"""
    px = cell.load()
    ys = [y for y in range(cell.height) for x in range(cell.width)
          if px[x, y][3] > 32 and sum(px[x, y][:3]) < 420]
    return (min(ys), max(ys)) if ys else None


def scale_frame(cell: Image.Image, k: float, foot_bottom: int) -> Image.Image:
    """按倍率 k 纵向缩放，并把缩放后的脚底贴回 foot_bottom。"""
    new_h = max(1, round(CELL_H * k))
    resized = cell.resize((CELL_W, new_h), Image.Resampling.LANCZOS)
    span = body_span(resized)
    delta_y = 0 if span is None else foot_bottom - span[1]
    out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    out.alpha_composite(resized, (0, delta_y))
    return out


def process(path: Path, check_only: bool) -> None:
    image = Image.open(path).convert("RGBA")
    frames = split_frames(image)
    spans = [body_span(f) for f in frames]
    heights = [b - a + 1 for (a, b) in [s for s in spans if s]]
    target = float(statistics.median(heights))
    before = max(heights) - min(heights)

    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shifted: list[Image.Image] = []
    for i, frame in enumerate(frames):
        span = spans[i]
        if span is None:
            new_frame = frame
        else:
            h = span[1] - span[0] + 1
            k = 1.0 if abs(h - target) < TOLERANCE else target / h
            new_frame = frame if k == 1.0 else scale_frame(frame, k, span[1])
        shifted.append(new_frame)
        out.alpha_composite(new_frame, ((i % 4) * CELL_W, (i // 4) * CELL_H))

    new_spans = [body_span(f) for f in shifted]
    new_h = [b - a + 1 for (a, b) in [s for s in new_spans if s]]
    new_bottom = [s[1] for s in new_spans if s]
    after = max(new_h) - min(new_h)

    print(f"[{path.name}] 目标身高 {target:.0f}px  波动 {before}px -> {after}px")
    print(f"  头顶 y: {[s[0] for s in new_spans if s]}")
    print(f"  脚底 y: {new_bottom}")
    print(f"  身高:   {new_h}")
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
