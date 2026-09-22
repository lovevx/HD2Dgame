"""把选好的 24 帧导出成总览图：每个动作一张，8 个朝向 × 24 帧的网格（带地面线）。

输入：assets/characters/black_swordsman_video/<动作>_<方向>_24.png（select_frames_24.py 产出）
输出：.tmp_preview/video_frames/overview_<动作>.png

用法: python tools/make_frame_overview.py [动作名...]
"""
import os
import sys
from PIL import Image, ImageDraw

SRC = "assets/characters/black_swordsman_video"
TMP = ".tmp_preview/video_frames"
DIRS = ["down", "down_left", "down_right", "left", "right", "up", "up_left", "up_right"]
ACTIONS = ["待机", "行走", "跑步", "攻击", "直踹", "受击", "闪避", "死亡"]
COLS, SCALE = 6, 0.45


def main():
    targets = [a for a in ACTIONS if not sys.argv[1:] or a in sys.argv[1:]]
    os.makedirs(TMP, exist_ok=True)
    for action in targets:
        cw = 224 if action == "攻击" else 192
        ch = 192 if action == "攻击" else 160
        tile_w, tile_h = int(cw * SCALE), int(ch * SCALE)
        sheet = Image.new("RGB", (tile_w * 24 + 60, tile_h * 8 + 8), (245, 245, 245))
        d = ImageDraw.Draw(sheet)
        for r, dname in enumerate(DIRS):
            path = os.path.join(SRC, "%s_%s_24.png" % (action, dname))
            if not os.path.exists(path):
                continue
            atlas = Image.open(path).convert('RGBA')
            for k in range(24):
                cell = atlas.crop(((k % COLS) * cw, (k // COLS) * ch,
                                   (k % COLS + 1) * cw, (k // COLS + 1) * ch))
                cell = cell.resize((tile_w, tile_h), Image.LANCZOS)
                bg = Image.new("RGBA", cell.size, (250, 250, 250, 255))
                bg.alpha_composite(cell)
                x = 60 + k * tile_w
                y = r * tile_h
                sheet.paste(bg.convert('RGB'), (x, y))
                d.line([(x, y + tile_h - int(16 * SCALE)), (x + tile_w, y + tile_h - int(16 * SCALE))],
                       fill=(210, 120, 120))
            d.text((4, r * tile_h + tile_h // 2 - 6), dname, fill=(40, 40, 40))
        out = os.path.join(TMP, "overview_%s.png" % action)
        sheet.save(out)
        print("saved", out, sheet.size)


main()
