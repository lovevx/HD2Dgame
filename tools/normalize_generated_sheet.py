from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input")
    parser.add_argument("output")
    args = parser.parse_args()

    image = Image.open(args.input).convert("RGBA")
    image = image.resize((768, 320), Image.Resampling.NEAREST)
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    image.save(output, format="PNG")


if __name__ == "__main__":
    main()
