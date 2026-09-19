from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman"

CELL_W = 192
CELL_H = 160
SHEET_W = CELL_W * 4
SHEET_H = CELL_H * 2


RIGHT_SOURCES = {
    "idle_right.png": "idle.png",
    "walk_right.png": "walk_side.png",
    "attack_right.png": "attack_side.png",
    "dodge_right.png": "dodge.png",
    "guard_right.png": "guard.png",
    "combo_norm/stab_right.png": "combo_norm/stab_side.png",
    "combo_norm/heavy_right.png": "combo_norm/heavy_side.png",
}

RIGHT_MIRRORS = {"dodge_right.png"}

DIAGONAL_SOURCES = {
    "idle": ("idle_up.png", "idle_down.png"),
    "walk": ("walk_up.png", "walk_down.png"),
    "attack": ("attack_up.png", "attack_down.png"),
    "dodge": ("dodge_up.png", "dodge_down.png"),
    "guard": ("guard_up.png", "guard_down.png"),
    "combo_norm/stab": ("combo_norm/stab_up.png", "combo_norm/stab_down.png"),
    "combo_norm/heavy": ("combo_norm/heavy_up.png", "combo_norm/heavy_down.png"),
}


def _load_sheet(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    if image.size != (SHEET_W, SHEET_H):
        raise ValueError(f"{path} is {image.size}, expected {(SHEET_W, SHEET_H)}")
    return image


def _shear_45(cell: Image.Image, direction: str) -> Image.Image:
    # Keep the existing y anchor and apply a restrained nearest-neighbor shear.
    # This turns the front/back source into a consistent 3/4 right-facing view
    # without resampling the character or moving the ground line.
    scale = 0.92
    shear = 0.075 if direction == "up_right" else 0.065
    cx = CELL_W / 2
    cy = 96.0
    a = 1.0 / scale
    b = -shear
    c = cx - cx / scale + shear * cy
    transformed = cell.transform(
        (CELL_W, CELL_H),
        Image.Transform.AFFINE,
        (a, b, c, 0.0, 1.0, 0.0),
        resample=Image.Resampling.NEAREST,
        fillcolor=(0, 0, 0, 0),
    )
    return transformed


def _make_diagonal(source: Image.Image, direction: str) -> Image.Image:
    output = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
    for index in range(8):
        x = (index % 4) * CELL_W
        y = (index // 4) * CELL_H
        cell = source.crop((x, y, x + CELL_W, y + CELL_H))
        output.alpha_composite(_shear_45(cell, direction), (x, y))
    return output


def _ensure_copy(target: Path, source: Path) -> None:
    if target.exists():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def _ensure_right(target: Path, source: Path) -> None:
    if target.exists():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.name in RIGHT_MIRRORS:
        mirrored = _load_sheet(source).transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        # The legacy dodge sheet contains the wind-up at the tail. Reorder it
        # into the spec's wind-up -> burst -> stop cadence after mirroring.
        if target.name == "dodge_right.png":
            reordered = Image.new("RGBA", (SHEET_W, SHEET_H), (0, 0, 0, 0))
            frame_order = [6, 7, 0, 3, 4, 5, 6, 7]
            for out_index, in_index in enumerate(frame_order):
                sx = (in_index % 4) * CELL_W
                sy = (in_index // 4) * CELL_H
                dx = (out_index % 4) * CELL_W
                dy = (out_index // 4) * CELL_H
                reordered.alpha_composite(
                    mirrored.crop((sx, sy, sx + CELL_W, sy + CELL_H)),
                    (dx, dy),
                )
            reordered.save(target, format="PNG")
        else:
            mirrored.save(target, format="PNG")
    else:
        shutil.copy2(source, target)


def _ensure_diagonal(target: Path, source: Path, direction: str) -> None:
    if target.exists():
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    _make_diagonal(_load_sheet(source), direction).save(target, format="PNG")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true", help="replace only generated diagonal outputs")
    args = parser.parse_args()

    for target_rel, source_rel in RIGHT_SOURCES.items():
        target = ASSET_DIR / target_rel
        source = ASSET_DIR / source_rel
        if args.force and target.exists():
            target.unlink()
        _ensure_right(target, source)

    for stem, (up_rel, down_rel) in DIAGONAL_SOURCES.items():
        for direction, source_rel in (("up_right", up_rel), ("down_right", down_rel)):
            target = ASSET_DIR / f"{stem}_{direction}.png"
            source = ASSET_DIR / source_rel
            if args.force and target.exists():
                target.unlink()
            _ensure_diagonal(target, source, direction)


if __name__ == "__main__":
    main()
