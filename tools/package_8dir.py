"""八方向打包：校验 37 张 768x320 图集并生成 player_frames.tres。

每动作只画 5 个视角（up/down/right/up_right/down_right），
left/up_left/down_left 的 clip 复用右侧系图集，运行时由 player_visual.gd 的 flip_h 镜像。
锚点验收：脚底 y=144（±2），任一格超差则不写 .tres（游戏继续用旧图集）。
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/characters/black_swordsman'
CELL_W, CELL_H = 192, 160
FOOT_Y, FOOT_TOL = 144, 3
MIN_ROW_PX = 5  # 一行至少这么多不透明像素才算"身体行"，用于剥离细刀线/光点
# 只有落地动作才校验脚底锚点；剃/受击/死亡允许离地或倒地
GROUNDED_ACTIONS = {'idle', 'walk', 'attack', 'stab', 'heavy', 'guard'}
# 身高一致性只查移动/待机：攻击的举刀过头、下蹲、重斩都会合法地改变轮廓高度
HEIGHT_CHECK_ACTIONS = {'idle', 'walk'}
# 同一图集内身体高度波动上限。脚底固定时，头顶波动就是"弹动"幅度：
# 4px 已相当于真人走路起伏（身高约 3%），超过就会看着一蹦一蹦。
HEIGHT_TOL = 4

DIRS = ['up', 'up_right', 'right', 'down_right', 'down', 'down_left', 'left', 'up_left']
# 每个朝向用哪张唯一图集（view 后缀）；左侧三向复用右侧图集，镜像由运行时 flip_h 完成
VIEW_FOR_DIR = {
    'up': 'up', 'up_right': 'up_right', 'right': 'right', 'down_right': 'down_right',
    'down': 'down', 'down_left': 'down_right', 'left': 'right', 'up_left': 'up_right',
}

# 每个动作的 5 张唯一图集（相对 OUT 的路径，无扩展名）
ACTIONS = {
    'idle':   ['idle_up', 'idle_down', 'idle_right', 'idle_up_right', 'idle_down_right'],
    'walk':   ['walk_up', 'walk_down', 'walk_right', 'walk_up_right', 'walk_down_right'],
    'attack': ['attack_up', 'attack_down', 'attack_right', 'attack_up_right', 'attack_down_right'],
    'stab':   ['combo_norm/stab_up', 'combo_norm/stab_down', 'combo_norm/stab_right',
               'combo_norm/stab_up_right', 'combo_norm/stab_down_right'],
    'heavy':  ['combo_norm/heavy_up', 'combo_norm/heavy_down', 'combo_norm/heavy_right',
               'combo_norm/heavy_up_right', 'combo_norm/heavy_down_right'],
    'dodge':  ['dodge_up', 'dodge_down', 'dodge_right', 'dodge_up_right', 'dodge_down_right'],
    'guard':  ['guard_up', 'guard_down', 'guard_right', 'guard_up_right', 'guard_down_right'],
}
LOOP_ACTIONS = {'idle', 'walk', 'guard'}
# 剃的帧节奏：蓄力慢 → 爆发快 → 骤停慢，speed=10 时整段 0.8s
DODGE_RHYTHM = [0.8, 1.2, 1.2, 0.4, 0.6, 0.7, 1.3, 1.8]

SHEETS = {}
for action, views in ACTIONS.items():
    for view in views:
        SHEETS[view] = action

failures: list[str] = []


def body_rows(cell):
    """剥离细刀线后的身体行区间（含头到脚）；无内容返回 None。
    刀尖/刀光只有 1~3px 宽，用"整行像素数阈值"排除，避免把刀尖当成脚底。"""
    px = cell.split()[3].load()
    rows = [y for y in range(CELL_H)
            if sum(1 for x in range(CELL_W) if px[x, y] > 10) >= MIN_ROW_PX]
    return (rows[0], rows[-1]) if rows else None


def verify_sheet(name, action):
    path = OUT / f'{name}.png'
    if not path.exists():
        failures.append(f'缺失图集: {name}.png')
        return None
    img = Image.open(path).convert('RGBA')
    if img.size != (CELL_W * 4, CELL_H * 2):
        failures.append(f'{name}.png 尺寸应为 768x320，实际 {img.size[0]}x{img.size[1]}')
        return None
    grounded = action in GROUNDED_ACTIONS
    heights = []
    for r in range(2):
        for c in range(4):
            cell = img.crop((c * CELL_W, r * CELL_H, (c + 1) * CELL_W, (r + 1) * CELL_H))
            rows = body_rows(cell)
            if rows is None:
                failures.append(f'{name}.png 帧[{r},{c}] 全透明')
                continue
            top, foot = rows
            heights.append(foot - top + 1)
            if grounded and abs(foot - FOOT_Y) > FOOT_TOL:
                failures.append(f'{name}.png 帧[{r},{c}] 脚底 y={foot}（应为 {FOOT_Y}±{FOOT_TOL}）')
    if action in HEIGHT_CHECK_ACTIONS and heights and max(heights) - min(heights) > HEIGHT_TOL:
        failures.append(f'{name}.png 身体高度波动 {max(heights) - min(heights)}px'
                        f'（{min(heights)}~{max(heights)}，上限 {HEIGHT_TOL}px）')
    return img


# 1) 校验全部图集
images = {}
for name in SHEETS:
    img = verify_sheet(name, SHEETS[name])
    if img is not None:
        images[name] = img

# 单张通用图集（hit/death，八方向复用）
for name in ['hit', 'death']:
    if (OUT / f'{name}.png').exists():
        img = verify_sheet(name, name)
        if img is not None:
            images[name] = img
    else:
        failures.append(f'缺失图集: {name}.png')

if failures:
    print('PACK8DIR_FAILURES:')
    for f in failures:
        print('  -', f)
    print(f'共 {len(failures)} 处问题，未生成 player_frames.tres（游戏继续使用旧图集）')
    raise SystemExit(1)

# 2) 生成 .tres
all_names = list(SHEETS) + ['hit', 'death']
resource = ['[gd_resource type="SpriteFrames" format=3]', '']
for idx, name in enumerate(all_names, 1):
    resource.append(f'[ext_resource type="Texture2D" path="res://assets/characters/black_swordsman/{name}.png" id="{idx}"]')
resource.append('')

for name in all_names:
    for i in range(8):
        resource.append(f'[sub_resource type="AtlasTexture" id="{name.replace("/", "_")}_{i}"]')
        resource.append(f'atlas = ExtResource("{all_names.index(name) + 1}")')
        resource.append(f'region = Rect2({i % 4 * CELL_W}, {i // 4 * CELL_H}, {CELL_W}, {CELL_H})')
        resource.append('')

clips = []


def add_clip(name, sheet, indices, loop=True, durations=None):
    parts = []
    for n, i in enumerate(indices):
        duration = durations[n] if durations else 1.0
        parts.append('{"duration": %s, "texture": SubResource("%s_%d")}' % (duration, sheet.replace('/', '_'), i))
    clips.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": 10.0}' % (', '.join(parts), str(loop).lower(), name))


for action, views in ACTIONS.items():
    loop = action in LOOP_ACTIONS
    durations = DODGE_RHYTHM if action == 'dodge' else None
    for d in DIRS:
        sheet = next((v for v in views if v.endswith('_' + VIEW_FOR_DIR[d])), None)
        if sheet is None:
            failures.append(f'{action} 缺少 {d} 所需图集（后缀 _{VIEW_FOR_DIR[d]}）')
            continue
        add_clip(f'{action}_{d}', sheet, range(8), loop=loop, durations=durations)

# hit/death：单张图集，八方向 clip 齐全，左侧三向运行时镜像
for action in ['hit', 'death']:
    for d in DIRS:
        add_clip(f'{action}_{d}', action, range(8), loop=False)

EXPECTED_CLIPS = len(ACTIONS) * len(DIRS) + 2 * len(DIRS)  # 7 动作 + hit/death，各 8 方向
if failures or len(clips) != EXPECTED_CLIPS:
    if len(clips) != EXPECTED_CLIPS:
        failures.append(f'clip 数量 {len(clips)}，应为 {EXPECTED_CLIPS}')
    print('PACK8DIR_FAILURES:')
    for f in failures:
        print('  -', f)
    print('未生成 player_frames.tres（游戏继续使用现有图集）')
    raise SystemExit(1)

resource += ['[resource]', 'animations = [\n' + ',\n'.join(clips) + '\n]']
(OUT / 'player_frames.tres').write_text('\n'.join(resource) + '\n', encoding='utf-8')
print(f'PACK8DIR_OK: 校验通过 {len(all_names)} 张图集，生成 {len(clips)} 个 clip（8 方向 × 7 动作 + hit/death）。')
