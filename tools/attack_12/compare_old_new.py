# -*- coding: utf-8 -*-
"""新旧攻击图集对比图：旧 24 帧(攻击_*_24.png) vs 新 12 帧(攻击_*_12.png)。
用法: python tools/attack_12/compare_old_new.py
"""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT / "assets" / "characters" / "black_swordsman_video"
OUT = ROOT / ".tmp_preview" / "attack12"
DIRS = ["down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right"]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    scalar = 1.15
    pad = 10
    lab = 30
    per_dir = Image.new("RGBA", (2600, 300), (13, 17, 30, 255))
    rows_imgs = []
    r, c = 0, 0
    big = None
    for d in DIRS:
        old = DIR / f"攻击_{d}_24.png"
        new = DIR / f"攻击_{d}_12.png"
        if not old.exists() or not new.exists():
            continue
        oi = Image.open(old).convert("RGBA")
        ni = Image.open(new).convert("RGBA")
        ow, oh = oi.size
        nw_, nh_ = ni.size
        os_ = (int(ow * scalar), int(oh * scalar))
        ns_ = (int(nw_ * scalar), int(nh_ * scalar))
        oo = oi.resize(os_, Image.Resampling.BILINEAR)
        nn = ni.resize(ns_, Image.Resampling.BILINEAR)
        W = os_[0] + ns_[0] + pad * 3
        H = max(os_[1], ns_[1]) + lab + pad * 2
        strip = Image.new("RGBA", (W, H), (13, 17, 30, 255))
        st = ImageDraw.Draw(strip)
        st.text((pad, 4), f"{d}  旧24帧(x1.15)", fill=(255, 200, 100))
        st.text((pad + os_[0] + pad, 4), "新12帧(x1.15, 0.8s@15fps)", fill=(120, 230, 160))
        strip.alpha_composite(oo, (pad, lab))
        strip.alpha_composite(nn, (pad * 2 + os_[0], lab))
        fp = OUT / f"compare_{d}.png"
        strip.save(fp)

    # 8 方向九宫格总览
    cellw, cellh = 620, 250
    grid = Image.new("RGBA", (cellw * 2, cellh * 4 + 20), (13, 17, 30, 255))
    for i, d in enumerate(DIRS):
        fp = OUT / f"compare_{d}.png"
        if not fp.exists():
            continue
        im = Image.open(fp).convert("RGBA")
        im.thumbnail((cellw - 14, cellh - 14), Image.Resampling.BILINEAR)
        grid.alpha_composite(im, (6 + (i % 2) * cellw, 10 + (i // 2) * cellh))
    grid.save(OUT / "compare_all_8dirs.png")
    print("done ->", OUT / "compare_all_8dirs.png")


if __name__ == "__main__":
    main()