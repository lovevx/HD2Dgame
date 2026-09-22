# -*- coding: utf-8 -*-
"""归一化跑步 24 帧图集：身高统一 104px、脚底锚定 y=144，消除大小形变与抽动。

背景（2026-09-21 用户反馈）：
  跑步帧高 92~110px、脚底 y 131~145 乱跳（run_down_left 高差 14px），
  播放时人物忽大忽小、上下浮动（"抽动/形变"）。
  另外 run 各朝向本体均值 98~106px 不等，换向时人物会"变个尺寸"。

做法：逐帧等比缩放（LANCZOS，软边抗锯齿）到本体高 104px，脚底贴回 y=144；
  偏差 < TOLERANCE 的帧不做重采样，只平移把脚底钉到 144。
  所有朝向统一目标 104px，保证换向尺寸一致。

用法：
  python tools/normalize_run_video_sheets.py --check   # 只测量，不写文件
  python tools/normalize_run_video_sheets.py           # 备份原图后就地修复
"""
import argparse
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman_video"
BACKUP_DIR = ROOT / "tools" / "backups" / "run_normalize_20260921"
CELL_W, CELL_H = 192, 160
GROUND_Y = 144          # 脚底目标线（格底-16）
TARGET_H = 104.0        # 本体目标高（与 walk/idle 一致）
TOLERANCE = 1.5         # 身高偏差小于该值不重采样，保持原像素
COLS, ROWS = 6, 4
DIRS = ["down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right"]
DARK_SUM = 420          # r+g+b 低于此值算角色本体（排除亮色特效）


def split_frames(image: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(COLS * ROWS):
        x = (i % COLS) * CELL_W
        y = (i // COLS) * CELL_H
        frames.append(image.crop((x, y, x + CELL_W, y + CELL_H)))
    return frames


def body_span(cell: Image.Image):
    """角色本体（深色衣物/头发/靴子）的上下界；空帧返回 None。"""
    px = cell.load()
    ys = [y for y in range(cell.height) for x in range(cell.width)
          if px[x, y][3] > 32 and sum(px[x, y][:3]) < DARK_SUM]
    return (min(ys), max(ys)) if ys else None


def normalize_cell(cell: Image.Image) -> Image.Image:
    """把单帧缩放/平移成：本体高 104、脚底 y=144。返回新帧（内容居中于 192 宽）。"""
    span = body_span(cell)
    if span is None:
        return cell
    h = span[1] - span[0] + 1
    if abs(h - TARGET_H) < TOLERANCE:
        # 不重采样：只平移把脚底钉到 144
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


def process(path: Path, check_only: bool) -> None:
    image = Image.open(path).convert("RGBA")
    frames = split_frames(image)
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    new_frames: list[Image.Image] = []
    for i, frame in enumerate(frames):
        nf = frame if check_only else normalize_cell(frame)
        new_frames.append(nf)
        out.alpha_composite(nf, ((i % COLS) * CELL_W, (i // COLS) * CELL_H))

    def report(fs: list[Image.Image]) -> None:
        hs = []
        foots = []
        for f in fs:
            s = body_span(f)
            if s is None:
                continue
            hs.append(s[1] - s[0] + 1)
            foots.append(s[1])
        print(f"  高: min {min(hs)} max {max(hs)} 均值 {sum(hs)/len(hs):.1f}  波幅 {max(hs)-min(hs)}px"
              f"  脚底 {min(foots)}~{max(foots)}")

    before = "  [修前]"; after = "  [修后]"
    print(f"[{path.name}]")
    report(frames)
    if check_only:
        return
    report(new_frames)
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, BACKUP_DIR / path.name)
    out.save(path, format="PNG")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只测量不写文件")
    args = ap.parse_args()
    for d in DIRS:
        path = ASSET_DIR / f"跑步_{d}_24.png"
        if path.exists():
            process(path, args.check)
    if not args.check:
        print(f"\n原图备份: {BACKUP_DIR}")


if __name__ == "__main__":
    main()
