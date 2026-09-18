"""Pack declared Meowa frames for Godot, without resampling pixel art."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'art/meowa/black_swordsman_fourdir'
OLD = ROOT / 'art/meowa/black_swordsman_20260916/deliverables'
OUTPUT = ROOT / 'assets/characters/black_swordsman'
OUTPUT.mkdir(parents=True, exist_ok=True)

def generated_gif(folder):
    manifest = next((SOURCE / folder).rglob('final_outputs.json'))
    outputs = json.loads(manifest.read_text(encoding='utf-8'))['outputs']
    return Path(next(x['path'] for x in outputs if x['mime_type'] == 'image/gif'))

sources = {
    'walk_side': (OLD / 'walk.gif', (72, 125)),
    'walk_down': (generated_gif('walk_down'), (72, 127)),
    'walk_up': (generated_gif('walk_up'), (72, 127)),
    'attack_side': (OLD / 'attack.gif', (112, 138)),
    'attack_down': (generated_gif('attack_down'), (96, 140)),
    'attack_up': (generated_gif('attack_up_retry'), (96, 139)),
}
resource = ['[gd_resource type="SpriteFrames" format=3]', '']
for i, name in enumerate(sources, 1):
    resource.append(f'[ext_resource type="Texture2D" path="res://assets/characters/black_swordsman/{name}.png" id="{i}"]')
resource.append('')
for texture_id, (name, (source, anchor)) in enumerate(sources.items(), 1):
    animation = Image.open(source)
    assert animation.n_frames == 8
    sheet = Image.new('RGBA', (192 * 4, 160 * 2))
    for index in range(8):
        animation.seek(index)
        frame = animation.convert('RGBA')
        x, y = 96 - anchor[0], 144 - anchor[1]
        bounds = frame.getbbox()
        assert bounds and bounds[0] + x >= 0 and bounds[1] + y >= 0
        assert bounds[2] + x <= 192 and bounds[3] + y <= 160
        # Source canvases can exceed a cell after translation; only transparent
        # margins are discarded. The bounds assertions protect visible pixels.
        cell = Image.new('RGBA', (192, 160))
        cell.paste(frame, (x, y))
        sheet.paste(cell, ((index % 4) * 192, (index // 4) * 160))
        resource.extend([
            f'[sub_resource type="AtlasTexture" id="{name}_{index}"]',
            f'atlas = ExtResource("{texture_id}")',
            f'region = Rect2({index % 4 * 192}, {index // 4 * 160}, 192, 160)', '',
        ])
    sheet.save(OUTPUT / f'{name}.png')

clips = []
for direction in ['up', 'down', 'left', 'right']:
    source = 'walk_side' if direction in ['left', 'right'] else 'walk_' + direction
    for action, indices, loop in [('idle', [3], True), ('walk', range(8), True)]:
        frames = ', '.join('{"duration": 1.0, "texture": SubResource("%s_%d")}' % (source, i) for i in indices)
        clips.append('{"frames": [%s], "loop": %s, "name": &"%s_%s", "speed": 10.0}' % (frames, str(loop).lower(), action, direction))
for direction in ['up', 'down', 'left', 'right']:
    source = 'attack_side' if direction in ['left', 'right'] else 'attack_' + direction
    frames = ', '.join('{"duration": 1.0, "texture": SubResource("%s_%d")}' % (source, i) for i in range(8))
    clips.append('{"frames": [%s], "loop": false, "name": &"attack_%s", "speed": 10.0}' % (frames, direction))
resource += ['[resource]', 'animations = [\n' + ',\n'.join(clips) + '\n]']
(OUTPUT / 'player_frames.tres').write_text('\n'.join(resource) + '\n', encoding='utf-8')
print('Packed 6 atlases; 4 idle, 4 walk and 4 attack clips.')
