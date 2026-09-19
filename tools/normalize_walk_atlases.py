from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman"
CELL_W = 192
CELL_H = 160
TARGET_HEIGHT = 104.0
GROUND_Y = 144.0

FILES = [
    "walk_up.png",
    "walk_down.png",
    "walk_right.png",
    "walk_up_right.png",
    "walk_down_right.png",
]


def body_bbox(cell: Image.Image) -> tuple[int, int, int, int] | None:
    rgba = np.asarray(cell.convert("RGBA"))
    alpha = rgba[:, :, 3]
    rgb = rgba[:, :, :3]
    mask = (alpha > 32) & (rgb.sum(axis=2) < 420)
    mask &= ~((rgb[:, :, 0] > rgb[:, :, 1] * 1.35) & (rgb[:, :, 0] > rgb[:, :, 2] * 1.2))
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)


def normalize(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    cells = []
    heights = []
    for index in range(8):
        x = (index % 4) * CELL_W
        y = (index // 4) * CELL_H
        cell = image.crop((x, y, x + CELL_W, y + CELL_H))
        bbox = body_bbox(cell)
        if bbox is not None:
            heights.append(bbox[3] - bbox[1])
        cells.append((cell, bbox))

    if not heights:
        return
    # The specification compares frame 0 across all five views. Use that
    # frame as the shared screen-height reference, while keeping one scale
    # factor for the whole atlas so the character does not resize mid-walk.
    scale = TARGET_HEIGHT / float(heights[0])
    output = Image.new("RGBA", image.size, (0, 0, 0, 0))
    for index, (cell, _) in enumerate(cells):
        scaled_w = max(1, round(CELL_W * scale))
        scaled_h = max(1, round(CELL_H * scale))
        scaled = cell.resize((scaled_w, scaled_h), Image.Resampling.NEAREST)
        bbox = body_bbox(scaled)
        if bbox is None:
            continue
        body_center_x = (bbox[0] + bbox[2]) / 2.0
        body_bottom = float(bbox[3])
        offset_x = round((CELL_W / 2.0) - body_center_x)
        offset_y = round(GROUND_Y - body_bottom)
        canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        canvas.alpha_composite(scaled, (offset_x, offset_y))
        x = (index % 4) * CELL_W
        y = (index // 4) * CELL_H
        output.alpha_composite(canvas, (x, y))
    output.save(path, format="PNG")


def main() -> None:
    for relative in FILES:
        normalize(ASSET_DIR / relative)


if __name__ == "__main__":
    main()
