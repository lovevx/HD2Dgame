from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman"
CELL_W = 192
CELL_H = 160
GROUND_Y = 144

STANDING_SHEETS = [
    "idle_up.png",
    "idle_down.png",
    "idle_right.png",
    "idle_up_right.png",
    "idle_down_right.png",
    "walk_up.png",
    "walk_down.png",
    "walk_right.png",
    "walk_up_right.png",
    "walk_down_right.png",
    "attack_up.png",
    "attack_down.png",
    "attack_right.png",
    "attack_up_right.png",
    "attack_down_right.png",
    "combo_norm/stab_up.png",
    "combo_norm/stab_down.png",
    "combo_norm/stab_right.png",
    "combo_norm/stab_up_right.png",
    "combo_norm/stab_down_right.png",
    "combo_norm/heavy_up.png",
    "combo_norm/heavy_down.png",
    "combo_norm/heavy_right.png",
    "combo_norm/heavy_up_right.png",
    "combo_norm/heavy_down_right.png",
    "guard_up.png",
    "guard_down.png",
    "guard_right.png",
    "guard_up_right.png",
    "guard_down_right.png",
    "hit.png",
]


def body_bottom(cell: Image.Image) -> int | None:
    rgba = np.asarray(cell.convert("RGBA"))
    alpha = rgba[:, :, 3]
    rgb = rgba[:, :, :3]
    # Keep the dark coat, boots, and hair in the anchor mask while excluding
    # bright sword pixels and red hit/slash effects.
    mask = (alpha > 32) & (rgb.sum(axis=2) < 420)
    mask &= ~((rgb[:, :, 0] > rgb[:, :, 1] * 1.35) & (rgb[:, :, 0] > rgb[:, :, 2] * 1.2))
    ys = np.where(mask)[0]
    return int(ys.max() + 1) if len(ys) else None


def move_cell(cell: Image.Image, delta_y: int) -> Image.Image:
    out = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    out.alpha_composite(cell, (0, delta_y))
    return out


def normalize(path: Path) -> None:
    image = Image.open(path).convert("RGBA")
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    for index in range(8):
        x = (index % 4) * CELL_W
        y = (index // 4) * CELL_H
        cell = image.crop((x, y, x + CELL_W, y + CELL_H))
        bottom = body_bottom(cell)
        if bottom is not None:
            cell = move_cell(cell, GROUND_Y - bottom)
        out.alpha_composite(cell, (x, y))
    out.save(path, format="PNG")


def main() -> None:
    for relative in STANDING_SHEETS:
        path = ASSET_DIR / relative
        if path.exists():
            normalize(path)


if __name__ == "__main__":
    main()
