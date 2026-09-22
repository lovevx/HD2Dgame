# -*- coding: utf-8 -*-
"""归一化攻击 24 帧图集：本体（暗像素掩码，排除刀身/刀光）统一 104px，脚底锚定 y=176。

背景（2026-09-21 用户反馈"攻击时人物形变/缩小"）：
  攻击帧本体高 58~91px 逐帧乱跳（起手/挥击/收招各帧比例不一致），
  而同 pixel_size 渲染时，本体矮的帧人物就"缩小"。
  刀身（中亮）与刀光（高亮）必须排除在判定外，只量暗色本体。

做法：逐帧等比缩放（LANCZOS）到本体高 104px，脚底贴回 y=176（格底-16）；
  偏差 < TOLERANCE 的帧不重采样，只平移钉脚底。水平方向保持帧内容相对位置。

用法：
  python tools/normalize_attack_video_sheets.py --check
  python tools/normalize_attack_video_sheets.py
"""
import argparse
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman_video"
BACKUP_DIR = ROOT / "tools" / "backups" / "attack_normalize_20260921"
CELL_W, CELL_H = 224, 192
GROUND_Y = 176          # 脚底目标线（格底-16，攻击格 224×192）
TARGET_H = 104.0        # 本体目标高（与 idle/run/walk 一致）
TOLERANCE = 1.5
COLS, ROWS = 6, 4
DIRS = ["down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right"]
DARK_SUM = 420          # r+g+b 低于此值 = 暗色本体（排除刀身/刀光）
FOOT_MIN_WIDTH = 10     # 脚底判定：暗像素行宽度 >= 此值才算脚（排除 2-4px 的刀尖）


def split_frames(image: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(COLS * ROWS):
        x = (i % COLS) * CELL_W
        y = (i // COLS) * CELL_H
        frames.append(image.crop((x, y, x + CELL_W, y + CELL_H)))
    return frames


def body_span(cell: Image.Image):
    """暗色本体的上下界（alpha 有效且 r+g+b < DARK_SUM）；空帧返回 None。

    关键：攻击帧里"垂直向下的刀/刀尖"与人物同为暗色，若按全部暗像素算，
    挥击帧会把刀长计入本体高（117-122px）、把脚底锚到刀尖（悬空）——
    用户反馈"攻击时人物缩小/悬空"的根因。
    因此**只统计宽度 >= FOOT_MIN_WIDTH 的暗像素行**：刀是 2-4px 细条，
    人物躯干/脚是宽块。这样刀完全不参与本体判定。
    """
    px = cell.load()
    rows: list[tuple[int, int]] = []   # (y, 行宽)
    for y in range(cell.height):
        xs = [x for x in range(cell.width)
              if px[x, y][3] > 32 and sum(px[x, y][:3]) < DARK_SUM]
        if len(xs) >= FOOT_MIN_WIDTH:
            rows.append((y, len(xs)))
    if not rows:
        return None
    ys = [y for y, _ in rows]
    return (min(ys), max(ys))


def normalize_cell(cell: Image.Image) -> Image.Image:
    span = body_span(cell)
    if span is None:
        return cell
    h = span[1] - span[0] + 1
    if abs(h - TARGET_H) < TOLERANCE:
        dy = GROUND_Y - span[1]
        out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        out.alpha_composite(cell, (0, dy))
        return out
    k = TARGET_H / h
    new_w = max(1, round(CELL_W * k))
    new_h = max(1, round(CELL_H * k))
    resized = cell.resize((new_w, new_h), Image.Resampling.LANCZOS)
    span2 = body_span(resized)
    if span2 is None:
        return cell
    dy = GROUND_Y - span2[1]
    dx = (CELL_W - new_w) // 2
    out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    out.alpha_composite(resized, (dx, dy))
    return out


def alpha_bbox(cell: Image.Image):
    return cell.getchannel('A').getbbox()


def process(path: Path, check_only: bool) -> None:
    image = Image.open(path).convert("RGBA")
    frames = split_frames(image)
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    new_frames: list[Image.Image] = []
    clipped = 0
    for i, frame in enumerate(frames):
        nf = frame if check_only else normalize_cell(frame)
        new_frames.append(nf)
        out.alpha_composite(nf, ((i % COLS) * CELL_W, (i // COLS) * CELL_H))
        if not check_only:
            bb = alpha_bbox(nf)
            if bb and (bb[0] < 0 or bb[1] < 0 or bb[2] > CELL_W or bb[3] > CELL_H):
                clipped += 1

    def report(fs: list[Image.Image]) -> None:
        hs, foots = [], []
        for f in fs:
            s = body_span(f)
            if s is None:
                continue
            hs.append(s[1] - s[0] + 1)
            foots.append(s[1])
        print(f"  高: min {min(hs)} max {max(hs)} 均值 {sum(hs)/len(hs):.1f}  波幅 {max(hs)-min(hs)}px"
              f"  脚底 {min(foots)}~{max(foots)}")

    print(f"[{path.name}]")
    report(frames)
    if check_only:
        return
    report(new_frames)
    print(f"  出格帧数: {clipped}")
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, BACKUP_DIR / path.name)
    out.save(path, format="PNG")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只测量不写文件")
    args = ap.parse_args()
    for d in DIRS:
        path = ASSET_DIR / f"攻击_{d}_24.png"
        if path.exists():
            process(path, args.check)
    if not args.check:
        print(f"\n原图备份: {BACKUP_DIR}")


if __name__ == "__main__":
    main()
