"""修复 black_swordsman_new 攻击图集的近空坏帧（2026-09-20）。

诊断（tools/diagnose_anim_sheets.py）：attack_down.png 与 attack_left.png
的第 7 帧（0 基，行2列2）本体消失只剩刀尖，播放时表现为一帧闪没。
修法：把干净的第 6 帧复制过去当"顿帧"，不打断挥刀节奏。

先备份原文件到 tools/backups/anim_fix_20260920/，再原位修补，
最后内置自检（坏帧像素数应与来源帧一致量级）。

用法: python tools/fix_broken_attack_frames.py
"""
import os
import shutil
import sys
from PIL import Image

DST = "assets/characters/black_swordsman_new"
BACKUP = "tools/backups/anim_fix_20260920"
COLS, ROWS = 6, 2
ALPHA_MIN = 24
TARGETS = ["attack_down.png", "attack_left.png"]
BROKEN_IDX, DONOR_IDX = 7, 6


def opaque_count(cell: Image.Image) -> int:
    a = cell.getchannel("A").point(lambda v: 255 if v > ALPHA_MIN else 0)
    return sum(1 for p in a.getdata() if p)


os.makedirs(BACKUP, exist_ok=True)
failed = False
for f in TARGETS:
    path = os.path.join(DST, f)
    shutil.copy2(path, os.path.join(BACKUP, f))
    im = Image.open(path).convert("RGBA")
    cw, ch = im.width // COLS, im.height // ROWS
    box = lambda i: ((i % COLS) * cw, (i // COLS) * ch, ((i % COLS) + 1) * cw, ((i // COLS) + 1) * ch)
    donor = im.crop(box(DONOR_IDX))
    before = opaque_count(im.crop(box(BROKEN_IDX)))
    im.paste(donor, (box(BROKEN_IDX)[0], box(BROKEN_IDX)[1]))
    im.save(path)
    # 自检：重新读盘统计
    re = Image.open(path).convert("RGBA")
    after = opaque_count(re.crop(box(BROKEN_IDX)))
    ok = after >= opaque_count(donor) * 0.98
    print(f"{f}: 坏帧 {before}px -> {after}px  {'OK' if ok else 'FAIL'}")
    failed |= not ok

sys.exit(1 if failed else 0)
