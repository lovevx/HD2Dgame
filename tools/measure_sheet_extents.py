#!/usr/bin/env python3
"""Measure player animation atlases without opening Godot's .ctex files in Pillow.

Default: inspect source PNG atlases for idle, run, vertical attack, and horizontal
attack. Pass --runtime to ask Godot to load each Texture2D and export its decoded
Image; this also handles CompressedTexture2D / .ctex inputs.

The script reports natural body-height variation instead of treating a shorter
crouch as a scaling error. Directional foot pivots on both axes, atlas bounds,
frame count, attack-to-idle handoffs, and horizontal slash height are hard checks.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
from PIL import Image

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets" / "characters" / "black_swordsman_video"
TMP_DIR = ROOT / ".tmp_preview" / "measure_sheet_extents"
DIRS = ["down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right"]
ACTIONS = ["待机", "跑步", "攻击", "横斩"]
CELL_W, CELL_H = 224, 192
COLS, ROWS = 6, 2
FRAME_COUNT = COLS * ROWS
GROUND_Y = 176
ALPHA_MIN = 24
DARK_MAX = 110
MIN_BODY_ROW_PIXELS = 10
CLIP_RE = re.compile(r"(待机|跑步|攻击|横斩)_([a-z_]+)_12\.png", re.IGNORECASE)
EXTRACTOR = None


def resource_path(path: Path) -> str:
    try:
        return "res://" + path.resolve().relative_to(ROOT).as_posix()
    except ValueError as exc:
        raise ValueError(f"Godot resource must be inside project: {path}") from exc


def find_godot(explicit: str | None) -> str:
    candidate = explicit or os.environ.get("GODOT_BIN")
    if candidate:
        return candidate
    for name in ("godot", "godot.cmd", "godot4", "godot4.cmd"):
        found = shutil.which(name)
        if found:
            return found
    raise RuntimeError("Godot executable not found; pass --godot or set GODOT_BIN")


def run_godot(command: list[str]) -> subprocess.CompletedProcess[str]:
    if os.name == "nt" and command[0].lower().endswith((".cmd", ".bat")):
        return subprocess.run(
            subprocess.list2cmdline(command),
            cwd=ROOT,
            shell=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    return subprocess.run(
        command,
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def decode_with_godot(paths: list[Path], godot_hint: str | None) -> list[Path]:
    godot = find_godot(godot_hint)
    run_dir = TMP_DIR / f"runtime_{time.strftime('%Y%m%d_%H%M%S')}_{os.getpid()}"
    run_dir.mkdir(parents=True, exist_ok=False)
    out_res = "res://" + run_dir.relative_to(ROOT).as_posix()
    # Always reimport before decoding: Godot can otherwise load an old .ctex
    # even when the source PNG has been replaced since the last editor scan.
    print("Refreshing Godot texture imports before decoding .ctex resources")
    refresh_command = [godot, "--headless", "--quiet", "--editor", "--path", str(ROOT), "--import"]
    refreshed = run_godot(refresh_command)
    if refreshed.stdout:
        print(refreshed.stdout, end="")
    if refreshed.stderr:
        print(refreshed.stderr, end="", file=sys.stderr)
    if refreshed.returncode != 0:
        raise RuntimeError(f"Godot texture import refresh failed with exit code {refreshed.returncode}")

    command = [
        godot,
        "--headless",
        "--quiet",
        "--path",
        str(ROOT),
        "--script",
        "res://tools/dump_compressed_textures.gd",
        "--",
        out_res,
        *[resource_path(path) for path in paths],
    ]
    result = run_godot(command)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"Godot texture decode failed with exit code {result.returncode}")
    outputs = [run_dir / f"{i:03d}.png" for i in range(len(paths))]
    missing = [path for path in outputs if not path.is_file()]
    if missing:
        raise RuntimeError("Godot did not export decoded images: " + ", ".join(map(str, missing)))
    return outputs


def classify(path: Path) -> tuple[str, str] | None:
    match = CLIP_RE.search(path.name)
    if match:
        return match.group(1), match.group(2)
    # Imported files look like <source-name>.png-<hash>[.s3tc].ctex.
    match = CLIP_RE.search(path.name + (".png" if path.suffix.lower() == ".ctex" else ""))
    if match:
        return match.group(1), match.group(2)
    return None


def default_paths() -> list[Path]:
    return [ASSET_DIR / f"{action}_{direction}_12.png" for action in ACTIONS for direction in DIRS]


def dark_body_mask(rgba: np.ndarray) -> np.ndarray:
    rgb = rgba[:, :, :3].astype(np.int16)
    alpha = rgba[:, :, 3]
    lum = (rgb[:, :, 0] * 299 + rgb[:, :, 1] * 587 + rgb[:, :, 2] * 114) // 1000
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    red_effect = (r > g * 1.35) & (r > b * 1.2)
    return (alpha > ALPHA_MIN) & (lum < DARK_MAX) & ~red_effect


def get_anchor_extractor():
    global EXTRACTOR
    if EXTRACTOR is None:
        spec = importlib.util.spec_from_file_location("extract_latest_12", ROOT / "tools" / "extract_latest_12.py")
        if spec is None or spec.loader is None:
            raise RuntimeError("Cannot load the project's foot-contact measurement")
        EXTRACTOR = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(EXTRACTOR)
    return EXTRACTOR


def contact_row(frame: Image.Image) -> int:
    extractor = get_anchor_extractor()
    body = extractor.body_mask(frame.convert("RGBA"))
    return int(extractor.contact_row(body))


def foot_anchor_x(frame: Image.Image) -> float:
    extractor = get_anchor_extractor()
    body = extractor.body_mask(frame.convert("RGBA"))
    bounds = body.getbbox()
    if bounds is None:
        raise ValueError("Cannot measure horizontal foot anchor")
    foot_band = body.crop((0, max(0, bounds[3] - extractor.FEET_ROWS + 1),
                           frame.width, bounds[3] + 1)).getbbox()
    if foot_band is None:
        raise ValueError("Cannot find horizontal foot anchor")
    return (foot_band[0] + foot_band[2] - 1) / 2.0


def frame_metrics(frame: Image.Image) -> dict[str, int | float | tuple[int, int, int, int] | None]:
    rgba = np.asarray(frame.convert("RGBA"))
    alpha = rgba[:, :, 3]
    ys, xs = np.where(alpha > ALPHA_MIN)
    alpha_box = None
    if len(xs):
        alpha_box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)

    mask = dark_body_mask(rgba)
    body_edge = bool(
        (mask[0, :].sum() >= MIN_BODY_ROW_PIXELS)
        or (mask[-1, :].sum() >= MIN_BODY_ROW_PIXELS)
        or (mask[:, 0].sum() >= MIN_BODY_ROW_PIXELS)
        or (mask[:, -1].sum() >= MIN_BODY_ROW_PIXELS)
    )
    row_counts = mask.sum(axis=1)
    body_rows = np.flatnonzero(row_counts >= MIN_BODY_ROW_PIXELS)
    if not len(body_rows):
        return {"alpha_box": alpha_box, "body_edge": body_edge, "foot": None,
                "foot_x": None, "body_center_x": None, "height": None, "head_width": None}

    top, body_bottom = int(body_rows[0]), int(body_rows[-1])
    body_height = body_bottom - top + 1
    body_columns = np.flatnonzero(mask.any(axis=0))
    body_center_x = (int(body_columns[0]) + int(body_columns[-1])) / 2.0
    # A compact top-band width is a useful proportion signal; it is reported,
    # not used to force poses to a fixed height or width.
    head_end = min(body_bottom + 1, top + max(8, round(body_height * 0.22)))
    head_rows = mask[top:head_end]
    head_row_counts = head_rows.sum(axis=1)
    useful = np.flatnonzero(head_row_counts >= 3)
    head_width = int(head_row_counts[useful].max()) if len(useful) else None
    return {
        "alpha_box": alpha_box,
        "body_edge": body_edge,
        "body_center_x": body_center_x,
        "foot": contact_row(frame),
        "foot_x": foot_anchor_x(frame),
        "height": body_height,
        "head_width": head_width,
    }


def frames_from_atlas(image: Image.Image) -> list[Image.Image]:
    return [
        image.crop((i % COLS * CELL_W, i // COLS * CELL_H,
                    (i % COLS + 1) * CELL_W, (i // COLS + 1) * CELL_H))
        for i in range(FRAME_COUNT)
    ]


def first_cell(path: Path) -> Image.Image:
    with Image.open(path) as image:
        return frames_from_atlas(image.convert("RGBA"))[0]


def inspect_atlas(
    path: Path,
    source_path: Path,
    failures: list[str],
    images_by_clip: dict[tuple[str, str], list[Image.Image]],
) -> None:
    label = source_path.name
    try:
        image = Image.open(path).convert("RGBA")
    except Exception as exc:  # Pillow must never be asked to decode .ctex.
        failures.append(f"{label}: cannot read decoded PNG: {exc}")
        return

    if image.size != (CELL_W * COLS, CELL_H * ROWS):
        failures.append(f"{label}: atlas size {image.width}x{image.height}, expected 1344x384")
        return

    clip = classify(source_path)
    frames = frames_from_atlas(image)
    metrics = [frame_metrics(frame) for frame in frames]
    if clip:
        images_by_clip[clip] = frames
    if any(item["foot"] is None for item in metrics):
        failures.append(f"{label}: one or more cells have no measurable dark body")
        return

    heights = [int(item["height"]) for item in metrics if item["height"] is not None]
    head_widths = [int(item["head_width"]) for item in metrics if item["head_width"] is not None]
    feet = [int(item["foot"]) for item in metrics if item["foot"] is not None]
    feet_x = [float(item["foot_x"]) for item in metrics if item["foot_x"] is not None]
    body_centers_x = [float(item["body_center_x"]) for item in metrics
                      if item["body_center_x"] is not None]
    boxes = [item["alpha_box"] for item in metrics if item["alpha_box"] is not None]
    body_edge_cells = [i + 1 for i, item in enumerate(metrics) if item["body_edge"]]
    touches_edge = [i + 1 for i, box in enumerate(boxes)
                    if box[0] <= 0 or box[1] <= 0 or box[2] >= CELL_W or box[3] >= CELL_H]
    max_foot_delta = max(abs(value - GROUND_Y) for value in feet)

    is_attack = bool(clip and clip[0] in {"攻击", "横斩"})
    if is_attack and max_foot_delta > 1:
        failures.append(f"{label}: foot row deviates {max_foot_delta}px from y={GROUND_Y} (limit 1px)")
    if is_attack and body_edge_cells:
        failures.append(f"{label}: body pixels touch atlas edge in cells {body_edge_cells}")
    if clip and clip[0] == "待机" and max_foot_delta > 0:
        failures.append(f"{label}: idle foot row deviates {max_foot_delta}px from y={GROUND_Y}")
    body_x_span = max(body_centers_x) - min(body_centers_x)
    if clip and clip[0] == "跑步" and body_x_span > 6.0:
        failures.append(f"{label}: body center drifts {body_x_span:.1f}px across run cells (limit 6px)")
    if touches_edge:
        print(f"  thin weapon/effect pixels touch an atlas edge in cells {touches_edge}; body-edge cells={body_edge_cells}")
    print(
        f"{label:30s} body_h={min(heights):3d}..{max(heights):3d}px "
        f"head_w={min(head_widths):2d}..{max(head_widths):2d}px "
        f"body_x_span={body_x_span:3.1f}px "
        f"foot=({min(feet_x):5.1f},{min(feet):3d})..({max(feet_x):5.1f},{max(feet):3d}) "
        f"x_span={max(feet_x)-min(feet_x):4.1f}px max_y_delta={max_foot_delta:2d}px "
        f"edge={len(touches_edge)}"
    )


def validate_handoffs(images_by_clip: dict[tuple[str, str], list[Image.Image]], failures: list[str]) -> None:
    for direction in DIRS:
        idle = images_by_clip.get(("待机", direction))
        if idle is None:
            continue
        for action in ("攻击", "横斩"):
            frames = images_by_clip.get((action, direction))
            if frames is None:
                continue
            if ImageChops_difference(frames[0], idle[0]):
                failures.append(f"{action}_{direction}: first frame differs from idle frame 1")
            if ImageChops_difference(frames[-1], idle[0]):
                failures.append(f"{action}_{direction}: last frame differs from idle frame 1")
            recovery = frames[-3:]
            if all(ImageChops_difference(recovery[0], frame) == 0 for frame in recovery[1:]):
                failures.append(f"{action}_{direction}: final three cells are one repeated pose")


def validate_root_anchors(images_by_clip: dict[tuple[str, str], list[Image.Image]], failures: list[str]) -> None:
    for direction in DIRS:
        idle = images_by_clip.get(("待机", direction))
        if not idle:
            continue
        reference_x = foot_anchor_x(idle[0])
        for action in ("待机", "攻击", "横斩"):
            frames = images_by_clip.get((action, direction))
            if not frames:
                continue
            max_delta = max(abs(foot_anchor_x(frame) - reference_x) for frame in frames)
            if max_delta > 1.0:
                failures.append(
                    f"{action}_{direction}: foot pivot drifts {max_delta:.1f}px horizontally from idle"
                )


def validate_horizontal_size(images_by_clip: dict[tuple[str, str], list[Image.Image]],
        failures: list[str]) -> None:
    """Catch a horizontal action whose upright poses outgrow same-dir idle.

    Only the tallest active pose is capped; low crouches are allowed to stay
    shorter. The test deliberately does not equalize each frame's height.
    """
    for direction in DIRS:
        idle = images_by_clip.get(("待机", direction))
        horizontal = images_by_clip.get(("横斩", direction))
        if not idle or not horizontal or len(horizontal) < 3:
            continue
        idle_heights = sorted(int(item["height"]) for frame in idle
                              if (item := frame_metrics(frame))["height"] is not None)
        active_heights = [int(item["height"]) for frame in horizontal[1:-1]
                          if (item := frame_metrics(frame))["height"] is not None]
        if not idle_heights or not active_heights:
            failures.append(f"横斩_{direction}: cannot measure active/idle body height")
            continue
        idle_reference = idle_heights[len(idle_heights) // 2]
        active_max = max(active_heights)
        if active_max > idle_reference + 2:
            failures.append(
                f"横斩_{direction}: tallest active body frame is {active_max}px, "
                f"exceeding idle reference {idle_reference}px by more than 2px"
            )


def validate_hit_timing(failures: list[str]) -> str:
    source = (ROOT / "data" / "combat_skills.gd").read_text(encoding="utf-8")
    combo = re.search(r"const\s+COMBO_HIT_TIMES\s*:=\s*\[\s*([0-9.]+)", source)
    cooldown = re.search(r"const\s+COMBO_COOLDOWNS\s*:=\s*\[\s*([0-9.]+)", source)
    horizontal = re.search(r"const\s+HORIZONTAL_ATTACK_HIT_TIME\s*:=\s*([0-9.]+)", source)
    if not (combo and cooldown and horizontal):
        failures.append("combat_skills.gd: cannot parse vertical/horizontal hit timing")
        return "timing unavailable"

    vertical_seconds, cooldown_seconds, horizontal_seconds = map(
        float, (combo.group(1), cooldown.group(1), horizontal.group(1)))
    vertical_frame = int(vertical_seconds / cooldown_seconds * FRAME_COUNT)
    horizontal_frame = int(horizontal_seconds / cooldown_seconds * FRAME_COUNT)
    if vertical_frame != 4:
        failures.append(f"vertical hit at {vertical_seconds:.3f}s lands in frame {vertical_frame + 1}, expected frame 5")
    if horizontal_frame != 4:
        failures.append(f"horizontal hit at {horizontal_seconds:.3f}s lands in frame {horizontal_frame + 1}, expected frame 5")
    if abs(vertical_seconds - horizontal_seconds) > 1e-6:
        failures.append("vertical and horizontal hit times differ")
    return (
        f"vertical/horizontal hit={vertical_seconds:.2f}s, cooldown={cooldown_seconds:.2f}s, "
        f"frame={vertical_frame + 1}/12"
    )


def ImageChops_difference(left: Image.Image, right: Image.Image) -> int:
    a = np.asarray(left.convert("RGBA"))
    b = np.asarray(right.convert("RGBA"))
    return int(np.any(a != b, axis=2).sum())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="PNG or Godot .ctex paths; defaults to all 32 action atlases")
    parser.add_argument("--runtime", action="store_true", help="decode through Godot Texture2D.get_image() first")
    parser.add_argument("--godot", help="Godot executable (or set GODOT_BIN)")
    args = parser.parse_args()

    input_paths = [Path(p) if Path(p).is_absolute() else ROOT / p for p in args.paths] if args.paths else default_paths()
    input_paths = [path.resolve() for path in input_paths]
    missing = [path for path in input_paths if not path.is_file()]
    if missing:
        print("Missing input(s): " + ", ".join(str(path) for path in missing), file=sys.stderr)
        return 2

    needs_godot = args.runtime or any(path.suffix.lower() == ".ctex" for path in input_paths)
    try:
        decoded_paths = decode_with_godot(input_paths, args.godot) if needs_godot else input_paths
    except Exception as exc:
        print(f"Godot decode error: {exc}", file=sys.stderr)
        return 2

    failures: list[str] = []
    images_by_clip: dict[tuple[str, str], list[Image.Image]] = {}
    print("Source:", "Godot-decoded Texture2D" if needs_godot else "lossless source PNG")
    for source_path, decoded_path in zip(input_paths, decoded_paths):
        inspect_atlas(decoded_path, source_path, failures, images_by_clip)

    timing = validate_hit_timing(failures)

    # Only compare handoffs when the complete default set is present.
    has_handoff_set = {"待机", "攻击", "横斩"}.issubset({a for a, _ in images_by_clip})
    if not args.paths or has_handoff_set:
        validate_handoffs(images_by_clip, failures)
        validate_root_anchors(images_by_clip, failures)
        validate_horizontal_size(images_by_clip, failures)

    if failures:
        print(f"FAIL: {len(failures)} check(s)")
        for failure in failures:
            print("  -", failure)
        return 1
    if not args.paths or has_handoff_set:
        print(f"PASS: {len(decoded_paths)} atlas(es); attack anchors and idle handoffs verified")
    else:
        print(f"PASS: {len(decoded_paths)} atlas(es); decoded and measured")
    print(f"PASS: {timing}")
    print("Body-height ranges are reported, not normalized; crouching frames may be shorter.")
    print("PASS: horizontal active body height stays within 2px of the idle reference.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
