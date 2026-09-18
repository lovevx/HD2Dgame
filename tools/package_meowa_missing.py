"""Pack the 5 newly generated Meowa GIFs (idle/hit/death/guard/dodge) into
192x160 4-col x 2-row Godot sheets and regenerate player_frames.tres.
Keeps existing walk/attack atlases and the foot-anchor (96,144) convention."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
GIFS = ROOT / 'art/meowa/missing'
OUT = ROOT / 'assets/characters/black_swordsman'
OUT.mkdir(parents=True, exist_ok=True)
CELL_W, CELL_H = 192, 160
ANCHOR = (96, 144)

# 剃的生成结果前 3 帧朝向与后面的冲刺帧不一致，按美术要求水平翻转对齐。
# 单元中心 x=96 正好是脚底锚点，翻转不改变锚点位置。
MIRROR_FRAMES = {'dodge': [0, 1, 2]}

def gif_for(action):
    manifest = next((GIFS / action).rglob('final_outputs.json'))
    outputs = json.loads(manifest.read_text(encoding='utf-8'))['outputs']
    return Path(next(x['path'] for x in outputs if x['mime_type'] == 'image/gif'))

def pack(action):
    gif = Image.open(gif_for(action))
    assert gif.n_frames == 8
    sheet = Image.new('RGBA', (CELL_W * 4, CELL_H * 2))
    for i in range(8):
        gif.seek(i)
        frame = gif.convert('RGBA')
        if i in MIRROR_FRAMES.get(action, []):
            frame = frame.transpose(Image.FLIP_LEFT_RIGHT)
        x, y = 0, 0  # animation canvas already matches the 192x160 cell exactly
        cell = Image.new('RGBA', (CELL_W, CELL_H))
        cell.paste(frame, (x, y))
        sheet.paste(cell, ((i % 4) * CELL_W, (i // 4) * CELL_H))
    out_png = OUT / f'{action}.png'
    sheet.save(out_png)
    return out_png

# ordered new actions and the extra texture ids (1-6 walk/attack already exist)
NEW = ['idle', 'hit', 'death', 'guard', 'dodge', 'dodge_up', 'dodge_down']
packed = {a: pack(a) for a in NEW}

# existing atlases
EXIST = ['walk_side', 'walk_down', 'walk_up', 'attack_side', 'attack_down', 'attack_up']  # ids 1..6

# ext_resource id mapping: 1..6 existing, 7.. new
def ext_id(action):
    return EXIST.index(action) + 1 if action in EXIST else NEW.index(action) + 7

resource = ['[gd_resource type="SpriteFrames" format=3]', '']
for idx, name in enumerate(EXIST + NEW, 1):
    resource.append(f'[ext_resource type="Texture2D" path="res://assets/characters/black_swordsman/{name}.png" id="{idx}"]')
resource.append('')

# atlas sub-resources for every sheet (8 cells each)
for name in EXIST + NEW:
    for i in range(8):
        resource.append(f'[sub_resource type="AtlasTexture" id="{name}_{i}"]')
        resource.append(f'atlas = ExtResource("{ext_id(name)}")')
        resource.append(f'region = Rect2({i % 4 * CELL_W}, {i // 4 * CELL_H}, {CELL_W}, {CELL_H})')
        resource.append('')

clips = []
def add_clip(name, source, indices, loop=True, speed=10.0, durations=None):
    parts = []
    for n, i in enumerate(indices):
        duration = durations[n] if durations else 1.0
        parts.append('{"duration": %s, "texture": SubResource("%s_%d")}' % (duration, source, i))
    clips.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}' % (', '.join(parts), str(loop).lower(), name, speed))

walk_dir = {'up': 'walk_up', 'down': 'walk_down', 'left': 'walk_side', 'right': 'walk_side'}
att_dir = {'up': 'attack_up', 'down': 'attack_down', 'left': 'attack_side', 'right': 'attack_side'}

for d in ['up', 'down', 'left', 'right']:
    add_clip('idle_' + d, 'idle', range(8), loop=True)          # new breathing idle
for d in ['up', 'down', 'left', 'right']:
    add_clip('walk_' + d, walk_dir[d], range(8), loop=True)
for d in ['up', 'down', 'left', 'right']:
    add_clip('attack_' + d, att_dir[d], range(8), loop=False)
for action in ['hit', 'death']:
    for d in ['up', 'down', 'left', 'right']:
        add_clip(action + '_' + d, action, range(8), loop=False)
# 剃的帧节奏：蓄力下蹲放慢、爆发帧缩短，用不等长时长拉出爆发对比。
# 合计 8.0，speed=10 时整段仍为 0.8 秒，与 player_visual.gd 的 CLIP_LEN 一致。
DODGE_RHYTHM = [0.8, 1.2, 1.2, 0.4, 0.6, 0.7, 1.3, 1.8]
# 左右复用侧向图集（源图朝左，仅右侧镜像）；上下各有独立图集，不镜像
dodge_atlas = {'up': 'dodge_up', 'down': 'dodge_down', 'left': 'dodge', 'right': 'dodge'}
for d in ['up', 'down', 'left', 'right']:
    add_clip('dodge_' + d, dodge_atlas[d], range(8), loop=False, durations=DODGE_RHYTHM)
for d in ['up', 'down', 'left', 'right']:
    add_clip('guard_' + d, 'guard', range(8), loop=True)

resource += ['[resource]', 'animations = [\n' + ',\n'.join(clips) + '\n]']
(OUT / 'player_frames.tres').write_text('\n'.join(resource) + '\n', encoding='utf-8')
print('Packed sheets:', ', '.join(packed))
print(f'Tres now has {len(clips)} clips.')