#!/usr/bin/env python3
"""Rebuild the 8-way vertical slash from its 64-frame source and align both attacks.

The vertical clip keeps a single per-direction scale, samples the first clear
slash at the same clip frame in all directions, adds three original recovery
poses, and uses the idle atlas pose for both handoffs. Horizontal active frames
share one per-direction scale, capped so their tallest body pose matches that
direction's idle reference. Both attacks use the idle foot pivot for X/Y alignment.
"""
from __future__ import annotations

import argparse
import importlib.util
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman_video"
BACKUP_DIR = ROOT / "tools" / "backups" / "attack_recovery_20260924"
PREVIEW_DIR = ROOT / ".tmp_preview" / "attack_recovery_20260924"
CELL_W, CELL_H = 224, 192
COLS, ROWS = 6, 2
FRAME_COUNT = COLS * ROWS
GROUND_Y = 176
MIN_BODY_ROW_PIXELS = 10
DIRS = ["down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right"]

# Contact is frame 5 (zero based index 4) in every vertical-slash clip.
# Front/back variants show the blade crossing the body at source 12; side views
# reach that same pose one source frame later.
CONTACT_SOURCE = {
    "down": 12,
    "down_left": 12,
    "down_right": 12,
    "left": 13,
    "right": 13,
    "up": 12,
    "up_left": 12,
    "up_right": 12,
}


def load_extractor():
    spec = importlib.util.spec_from_file_location("extract_latest_12", ROOT / "tools" / "extract_latest_12.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot import tools/extract_latest_12.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def split_atlas(image: Image.Image) -> list[Image.Image]:
    return [
        image.crop((i % COLS * CELL_W, i // COLS * CELL_H,
                    (i % COLS + 1) * CELL_W, (i // COLS + 1) * CELL_H))
        for i in range(FRAME_COUNT)
    ]


def move_to_ground(cell: Image.Image, extractor) -> tuple[Image.Image, int]:
    """Translate a frame to the foot row; preserve its original pixel scale."""
    moved = cell
    total_dy = 0
    for _ in range(2):
        contact = extractor.contact_row(extractor.body_mask(moved))
        if contact < 0:
            raise ValueError("Could not find a body/foot contact row")
        dy = GROUND_Y - contact
        if dy == 0:
            break
        translated = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        translated.paste(moved, (0, dy))
        moved = translated
        total_dy += dy
    final_contact = extractor.contact_row(extractor.body_mask(moved))
    if abs(final_contact - GROUND_Y) > 1:
        raise ValueError(f"Foot alignment failed: row {final_contact}, expected {GROUND_Y}")
    return moved, total_dy


def foot_anchor_x(cell: Image.Image, extractor) -> float:
    mask = extractor.body_mask(cell)
    bounds = mask.getbbox()
    if bounds is None:
        raise ValueError("Could not find a body anchor")
    foot_band = mask.crop((0, max(0, bounds[3] - extractor.FEET_ROWS + 1),
        cell.width, bounds[3] + 1)).getbbox()
    if foot_band is None:
        raise ValueError("Could not find a foot anchor")
    return (foot_band[0] + foot_band[2] - 1) / 2.0


def body_height(cell: Image.Image, extractor) -> int:
    mask = extractor.body_mask(cell)
    bounds = mask.getbbox()
    if bounds is None:
        raise ValueError("Could not find horizontal-slash body bounds")
    pixels = mask.load()
    body_rows = [
        y for y in range(mask.height)
        if sum(pixels[x, y] > 0 for x in range(mask.width)) >= MIN_BODY_ROW_PIXELS
    ]
    if not body_rows:
        return bounds[3] - bounds[1]
    return body_rows[-1] - body_rows[0] + 1


def scale_about_foot(cell: Image.Image, scale: float, target_x: float,
        extractor) -> Image.Image:
    """Apply one clip-wide scale while holding its foot/root pivot in place."""
    if scale <= 0.0:
        raise ValueError(f"Invalid horizontal scale {scale}")
    source_x = foot_anchor_x(cell, extractor)
    source_y = extractor.contact_row(extractor.body_mask(cell))
    if source_y < 0:
        raise ValueError("Could not find a foot row before scaling")
    size = (max(1, round(cell.width * scale)), max(1, round(cell.height * scale)))
    scaled = cell.resize(size, Image.Resampling.LANCZOS)
    dx = round(target_x - source_x * scale)
    dy = round(GROUND_Y - source_y * scale)
    out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    out.paste(scaled, (dx, dy), scaled)
    aligned, _ = move_to_ground(out, extractor)
    aligned, _ = move_to_anchor_x(aligned, target_x, extractor)
    return aligned


def move_to_anchor_x(cell: Image.Image, target_x: float, extractor) -> tuple[Image.Image, int]:
    """Translate a frame so its foot pivot matches the same-direction idle pivot."""
    source_x = foot_anchor_x(cell, extractor)
    wanted = round(target_x - source_x)
    step = 1 if wanted > 0 else -1
    for correction in range(abs(wanted) + 1):
        dx = wanted - step * correction
        if dx == 0:
            shifted = cell
        else:
            shifted = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            shifted.paste(cell, (dx, 0))
        before = cell.getchannel("A").point(lambda v: 255 if v > extractor.ALPHA_MIN else 0).tobytes().count(255)
        after = shifted.getchannel("A").point(lambda v: 255 if v > extractor.ALPHA_MIN else 0).tobytes().count(255)
        if before == after and abs(foot_anchor_x(shifted, extractor) - target_x) <= 1.0:
            return shifted, dx
    raise ValueError(
        f"Cannot align foot root from x={source_x:.1f} to x={target_x:.1f} "
        f"without clipping cell content; bbox={cell.getchannel('A').getbbox()}"
    )


def get_fixed_scales(extractor) -> tuple[Image.Image, dict[str, float]]:
    idle_sheet, idle_data = extractor.scan_sheet("待机")
    if idle_sheet is None:
        raise FileNotFoundError("Missing original 64-frame idle source")
    idle_frames = idle_data[0]
    scales: dict[str, float] = {}
    for direction in DIRS:
        heights = [
            box[3] - box[1] + 1
            for index in range(*extractor.REF_FRAMES)
            if (box := idle_frames[index].get(direction)) is not None
        ]
        if not heights:
            raise ValueError(f"No idle scale reference for {direction}")
        heights.sort()
        median_height = heights[len(heights) // 2]
        scales[direction] = extractor.TARGET_H / float(median_height)
    return idle_sheet, scales


def make_vertical_frames(extractor, source, source_frames, idle_atlas, scale: float,
        direction: str, anchor_x: float):
    contact = CONTACT_SOURCE[direction]
    picks: list[int | None] = [None, 8, 9, 10, contact, contact + 1, contact + 2,
                               contact + 3, contact + 4, 43, 45, None]
    frames: list[Image.Image] = []
    shifts_y: list[int] = []
    shifts_x: list[int] = []
    for index, source_index in enumerate(picks):
        if source_index is None:
            # Exact first/last-frame handoff to this direction's idle clip.
            cell = idle_atlas.copy()
            shift_y = 0
            shift_x = 0
        else:
            bounds = source_frames[source_index].get(direction)
            if bounds is None:
                raise ValueError(f"Source frame {source_index} has no {direction} sprite")
            sprite, foot_y, foot_x = extractor.frame_anchor(source, bounds, scale, use_feet=True)
            cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
            cell.alpha_composite(sprite, (round(anchor_x - foot_x), round(GROUND_Y - foot_y)))
            cell, shift_y = move_to_ground(cell, extractor)
            cell, shift_x = move_to_anchor_x(cell, anchor_x, extractor)
        frames.append(cell)
        shifts_y.append(shift_y)
        shifts_x.append(shift_x)
    return frames, picks, shifts_y, shifts_x


def make_atlas(frames: list[Image.Image]) -> Image.Image:
    atlas = Image.new("RGBA", (CELL_W * COLS, CELL_H * ROWS), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, ((index % COLS) * CELL_W, (index // COLS) * CELL_H))
    return atlas


def use_lossless_import(path: Path) -> None:
    """Keep attack and idle handoff pixels identical after Texture2D import."""
    text = path.read_text(encoding="utf-8")
    text = text.replace("compress/mode=2", "compress/mode=0")
    text = text.replace("mipmaps/generate=true", "mipmaps/generate=false")
    path.write_text(text, encoding="utf-8")


def make_overview(action: str, atlases: dict[str, Image.Image], labels: dict[str, list[str]],
        anchors_x: dict[str, float]) -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGBA", (12 * CELL_W, 8 * 208), (38, 42, 49, 255))
    draw = ImageDraw.Draw(image)
    for row, direction in enumerate(DIRS):
        draw.text((3, row * 208 + 2), direction, fill="white")
        for index, frame in enumerate(split_atlas(atlases[direction])):
            x, y = index * CELL_W, row * 208 + 16
            image.alpha_composite(frame, (x, y))
            draw.text((x + 3, y + 2), labels[direction][index], fill=(255, 240, 0, 255))
            draw.rectangle((x, y, x + CELL_W - 1, y + CELL_H - 1), outline=(91, 98, 108, 255))
            draw.line((x + round(anchors_x[direction]), y, x + round(anchors_x[direction]),
                y + CELL_H - 1), fill=(50, 160, 255, 255))
            draw.line((x, y + GROUND_Y, x + CELL_W - 1, y + GROUND_Y), fill=(245, 80, 80, 255))
    image.convert("RGB").save(PREVIEW_DIR / f"{action}_8dir.png")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="build x/y-aligned previews without changing source atlases")
    args = parser.parse_args()

    extractor = load_extractor()
    idle_source, scales = get_fixed_scales(extractor)
    attack_source, attack_data = extractor.scan_sheet("攻击")
    if attack_source is None:
        raise FileNotFoundError("Missing original 64-frame attack source")
    attack_frames = attack_data[0]

    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    if not args.dry_run:
        BACKUP_DIR.mkdir(parents=True, exist_ok=True)
        (BACKUP_DIR / ".gdignore").write_text(
            "Backup snapshots are source archives, not runtime Godot resources.\n",
            encoding="utf-8",
        )
    report: list[str] = ["Vertical slash source frame picks; scale is fixed per direction from idle:"]
    vertical_atlases: dict[str, Image.Image] = {}
    horizontal_atlases: dict[str, Image.Image] = {}
    vertical_labels: dict[str, list[str]] = {}
    horizontal_labels: dict[str, list[str]] = {}
    anchors_x: dict[str, float] = {}
    idle_atlases: dict[str, Image.Image] = {}

    for direction in DIRS:
        vertical_path = ASSET_DIR / f"攻击_{direction}_12.png"
        horizontal_path = ASSET_DIR / f"横斩_{direction}_12.png"
        idle_path = ASSET_DIR / f"待机_{direction}_12.png"
        if not all(path.is_file() for path in (vertical_path, horizontal_path, idle_path)):
            raise FileNotFoundError(f"Missing attack or idle atlas for {direction}")

        if not args.dry_run:
            for output_path in (vertical_path, horizontal_path, idle_path):
                backup_path = BACKUP_DIR / output_path.name
                if not backup_path.exists():
                    shutil.copy2(output_path, backup_path)
            for import_path in (vertical_path.with_suffix(".png.import"),
                                horizontal_path.with_suffix(".png.import"),
                                idle_path.with_suffix(".png.import")):
                backup_path = BACKUP_DIR / (import_path.name + ".bak")
                if import_path.exists() and not backup_path.exists():
                    shutil.copy2(import_path, backup_path)

        idle_frames = split_atlas(Image.open(idle_path).convert("RGBA"))
        idle_y_aligned: list[Image.Image] = []
        idle_y_shifts: list[int] = []
        for idle_frame in idle_frames:
            aligned, shift = move_to_ground(idle_frame, extractor)
            idle_y_aligned.append(aligned)
            idle_y_shifts.append(shift)
        anchor_x = foot_anchor_x(idle_y_aligned[0], extractor)
        anchors_x[direction] = anchor_x
        idle_frames_aligned: list[Image.Image] = []
        idle_x_shifts: list[int] = []
        for idle_frame in idle_y_aligned:
            aligned, shift = move_to_anchor_x(idle_frame, anchor_x, extractor)
            idle_frames_aligned.append(aligned)
            idle_x_shifts.append(shift)
        idle_atlas_image = make_atlas(idle_frames_aligned)
        idle_atlases[direction] = idle_atlas_image
        idle_atlas = idle_frames_aligned[0]
        vertical_frames, picks, vertical_y_shifts, vertical_x_shifts = make_vertical_frames(
            extractor, attack_source, attack_frames, idle_atlas, scales[direction], direction, anchor_x)
        vertical_atlases[direction] = make_atlas(vertical_frames)
        vertical_labels[direction] = ["idle" if pick is None else str(pick) for pick in picks]

        original_horizontal = split_atlas(Image.open(horizontal_path).convert("RGBA"))
        idle_heights = sorted(body_height(frame, extractor) for frame in idle_frames_aligned)
        idle_reference_height = idle_heights[len(idle_heights) // 2]
        # A few horizontal poses were taller than this direction's idle. Apply
        # one fixed scale to all ten active frames so none outgrows the idle
        # reference. Lower crouches remain lower; no frame is resized alone.
        horizontal_body_max = max(body_height(frame, extractor) for frame in original_horizontal[1:-1])
        horizontal_scale = min(1.0, idle_reference_height / float(horizontal_body_max))
        horizontal_frames: list[Image.Image] = []
        horizontal_shifts: list[int] = []
        horizontal_x_shifts: list[int] = []
        for index, frame in enumerate(original_horizontal):
            if index in (0, FRAME_COUNT - 1):
                # Exact horizontal/vertical/idle transitions.
                horizontal_frames.append(idle_atlas.copy())
                horizontal_shifts.append(0)
                horizontal_x_shifts.append(0)
            else:
                # All ten action poses share this one directional factor. This
                # corrects the horizontal source's oversized head/body render
                # scale without changing natural crouch height from pose to pose.
                scaled = scale_about_foot(frame, horizontal_scale, anchor_x, extractor)
                translated, shift = move_to_ground(scaled, extractor)
                translated, dx = move_to_anchor_x(translated, anchor_x, extractor)
                horizontal_frames.append(translated)
                horizontal_shifts.append(shift)
                horizontal_x_shifts.append(dx)
        horizontal_atlases[direction] = make_atlas(horizontal_frames)
        horizontal_labels[direction] = [
            "idle" if index in (0, FRAME_COUNT - 1)
            else f"{index + 1} ×{horizontal_scale:.2f}"
            for index in range(FRAME_COUNT)
        ]

        report.append(
            f"{direction:11s} scale={scales[direction]:.4f} anchor_x={anchor_x:.1f} "
            f"contact=frame5/source{CONTACT_SOURCE[direction]} vertical={picks} "
            f"vertical-y={vertical_y_shifts} vertical-x={vertical_x_shifts} "
            f"horizontal-idle-height={idle_reference_height} "
            f"horizontal-body-max={horizontal_body_max} "
            f"horizontal-scale={horizontal_scale:.3f} "
            f"horizontal-y={horizontal_shifts} "
            f"horizontal-x={horizontal_x_shifts} idle-y={idle_y_shifts} idle-x={idle_x_shifts}"
        )

    for direction in DIRS:
        if not args.dry_run:
            idle_atlases[direction].save(ASSET_DIR / f"待机_{direction}_12.png", format="PNG")
            vertical_atlases[direction].save(ASSET_DIR / f"攻击_{direction}_12.png", format="PNG")
            horizontal_atlases[direction].save(ASSET_DIR / f"横斩_{direction}_12.png", format="PNG")
            use_lossless_import(ASSET_DIR / f"攻击_{direction}_12.png.import")
            use_lossless_import(ASSET_DIR / f"横斩_{direction}_12.png.import")
            use_lossless_import(ASSET_DIR / f"待机_{direction}_12.png.import")

    make_overview("攻击", vertical_atlases, vertical_labels, anchors_x)
    make_overview("横斩", horizontal_atlases, horizontal_labels, anchors_x)
    (PREVIEW_DIR / "report.txt").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    print(f"\nMode: {'dry-run (assets unchanged)' if args.dry_run else 'assets written'}")
    if not args.dry_run:
        print(f"Backups: {BACKUP_DIR}")
    print(f"Previews: {PREVIEW_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
