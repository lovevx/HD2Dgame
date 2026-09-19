"""Quantify foot movement across walk frames and stance width in idle frames."""
from PIL import Image

DIR = r"e:\godotproject\hd-2d\assets\characters\black_swordsman"
CELL_W, CELL_H = 192, 160
FOOT_TOP = CELL_H - 34  # bottom 34px band

def foot_stats(name, band_top):
    img = Image.open(rf"{DIR}\{name}").convert("RGBA")
    print(f"=== {name} (foot band y={band_top}-{CELL_H}) ===")
    rows = []
    for r in range(2):
        for c in range(4):
            cell = img.crop((c * CELL_W, r * CELL_H, (c + 1) * CELL_W, (r + 1) * CELL_H))
            px = cell.load()
            xs, ys = [], []
            for y in range(band_top, CELL_H):
                for x in range(CELL_W):
                    if px[x, y][3] > 10:
                        xs.append(x)
                        ys.append(y)
            if not xs:
                print(f"  frame[{r},{c}] no pixels in foot band")
                rows.append((0, 0, 0))
                continue
            cx = sum(xs) / len(xs)
            minx, maxx = min(xs), max(xs)
            spread = maxx - minx
            rows.append((cx, spread, min(xs)))
            print(f"  frame[{r},{c}] footCX={cx:6.1f} spread={spread:3d} minX={min(xs):3d} maxX={max(xs):3d}")
    return rows

for name in ["walk_up.png", "walk_down.png", "walk_side.png", "idle_up.png", "idle_down.png", "idle.png"]:
    foot_stats(name, FOOT_TOP)

# body width reference at torso (y 70-110) for stance comparison
print()
print("=== torso width reference ===")
for name in ["idle_up.png", "walk_up.png", "walk_down.png"]:
    img = Image.open(rf"{DIR}\{name}").convert("RGBA")
    cell = img.crop((0, 0, CELL_W, CELL_H))
    px = cell.load()
    xs = [x for y in range(70, 112) for x in range(CELL_W) if px[x, y][3] > 10]
    print(f"{name}: torso width = {max(xs) - min(xs) + 1}px (x{min(xs)}-{max(xs)})" if xs else "empty")