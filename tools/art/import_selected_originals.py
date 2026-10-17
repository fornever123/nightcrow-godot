"""Build losslessly cropped runtime copies from the user-selected original PNGs.

Requires Pillow. Source art is never resized, painted or overwritten. Display
dimensions and pivots live in the shared battle.json, as in the existing editor.
"""
from pathlib import Path
import copy
import hashlib
import json
import statistics
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/game-ready-sequences'
TARGET = ROOT / 'assets/image/selected-original'
CONFIG = ROOT / 'assets/data/battle.json'
SPECS = {
    'mmh3_action_00014': (168 / 342, 738, None),
    'mmh3_拔刀40': (168 / 453, 995, None),
    'mmh3_左侧格挡_v5': (168 / 720, 1066, None),
    '空中a': (168 / 492, 1056, 795),
    'mmh3_冲刺攻击_v2': (0.43, 832, None),
    'mmh3_死亡_v1': (168 / 496, 1460, 856),
}


def main():
    source_manifest = json.loads((SOURCE / 'manifest.json').read_text(encoding='utf-8'))
    assert source_manifest['variant'] == 'original_edited'
    segments = json.loads((Path(__file__).with_name('selected-original-segments.json')).read_text(encoding='utf-8-sig'))['groups']
    original_config = CONFIG.read_bytes()
    config = json.loads(original_config.decode('utf-8-sig'))
    backup = ROOT / 'assets/data/backups/before-selected-original-20261017.json'
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists():
        backup.write_bytes(original_config)
    TARGET.mkdir(parents=True, exist_ok=True)
    (TARGET / '.gdignore').write_text('', encoding='utf-8')
    frame_sets = {}
    transforms = []
    for action in source_manifest['animations']:
        name = action['name']
        factor, floor, fixed_x = SPECS[name]
        raw_roots = []
        for i in range(1, action['frames'] + 1):
            with Image.open(SOURCE / name / '05-character' / f'frame_{i:05d}.png') as im:
                alpha = im.getchannel('A').point(lambda a: 255 if a > 128 else 0)
                box = alpha.getbbox() or im.getchannel('A').getbbox()
                if not box:
                    raw_roots.append(raw_roots[-1] if raw_roots else (fixed_x or im.width/2, floor))
                    continue
                y = box[3] if name == 'mmh3_死亡_v1' else floor
                band = alpha.crop((0, max(0, y - 18), im.width, min(im.height, y + 2))).getbbox()
                x = fixed_x if fixed_x is not None else ((band[0] + band[2]) / 2 if band else (box[0] + box[2]) / 2)
                raw_roots.append((x, y))
        roots = [(statistics.median([r[0] for r in raw_roots[max(0, i-1):i+2]]), r[1]) for i, r in enumerate(raw_roots)]
        layers = {'character': [], 'effects': []}
        for stage, key in [('05-character', 'character'), ('05-effects', 'effects')]:
            output_dir = TARGET / name / key
            output_dir.mkdir(parents=True, exist_ok=True)
            for i, (root_x, root_y) in enumerate(roots, 1):
                filename = f'frame_{i:05d}.png'
                source = SOURCE / name / stage / filename
                with Image.open(source) as im:
                    box = im.getchannel('A').getbbox()
                    if not box:
                        layers[key].append({'blank': True, 'durationTicks': 1})
                        continue
                    box = (max(0, box[0]-2), max(0, box[1]-2), min(im.width, box[2]+2), min(im.height, box[3]+2))
                    cropped = im.crop(box)
                    target = output_dir / filename
                    cropped.save(target, compress_level=6)
                    assert cropped.tobytes() == im.crop(box).tobytes()
                    descriptor = {'asset': target.relative_to(ROOT / 'assets').as_posix(),
                                  'width': round(max(1, cropped.width * factor), 4),
                                  'height': round(max(1, cropped.height * factor), 4),
                                  'pivotX': round((root_x-box[0])*factor, 4),
                                  'pivotY': round((root_y-box[1])*factor, 4),
                                  'durationTicks': 1}
                    layers[key].append(descriptor)
                    transforms.append({'asset': descriptor['asset'], 'source': source.relative_to(ROOT).as_posix(),
                                       'crop': list(box), 'foot': [root_x, root_y], 'displayScale': factor,
                                       'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
        frame_sets[name] = layers
        print('Prepared', action['frames'], 'source frames', flush=True)

    player = next(c for c in config['characters'] if c['id'] == 'player')
    sprite = player['sprite']
    animations = sprite['animations']
    effects = sprite.setdefault('effects', {})
    library = {}
    def clip(name, start, end, title, loop=False):
        fx_key = 'original_fx_' + title
        frames = copy.deepcopy(frame_sets[name]['character'][start-1:end])
        fx_frames = copy.deepcopy(frame_sets[name]['effects'][start-1:end])
        effects[fx_key] = {'fps': 24, 'loop': False, 'holdLast': False, 'frames': fx_frames}
        has_fx = any(not f.get('blank') for f in fx_frames)
        return {'name': title, 'fps': 24, 'loop': loop, 'holdLast': True,
                'effectsBaked': False, 'overlayEffect': fx_key if has_fx else '',
                'source': {'collection': 'selected-original-20261017', 'animation': name,
                           'firstFrame': start, 'lastFrame': end}, 'frames': frames}

    for group in segments:
        for segment in group['segments']:
            key = '原版_' + segment['name']
            entry = clip(group['source'], segment['start'], segment['end'], segment['name'], '待机' in segment['name'])
            entry['description'] = segment['description']
            animations[key] = entry
            library[segment['name']] = entry

    aliases = {'idle': 'action_00014_待机01', 'attack_1': 'action_00014_普攻01',
               'attack_2': 'action_00014_普攻02', 'attack_3': 'action_00014_普攻03',
               'charge_slash': 'action_00014_普攻08', 'attack_up': 'action_00014_普攻06',
               'air_slash': '空中a_普攻01', 'death': '死亡_完整动作'}
    for key, original in aliases.items():
        animations[key] = copy.deepcopy(library[original])
    # The saved idle FX contains video matte remnants, not an intentional attack.
    # Keep the original layered source/library, but display only the idle character.
    animations['idle']['overlayEffect'] = ''
    animations['parry'] = clip('mmh3_左侧格挡_v5', 6, 24, '格挡起架')
    animations['parry']['playDuringParry'] = True
    sprite['chargeAnimation'] = 'charge_slash'
    sprite['chargeFrame'] = 2
    sprite['preloadAnimations'] = ['idle', 'run', 'jump', 'fall', 'land', 'attack_1', 'attack_2', 'attack_3', 'charge_slash', 'attack_up', 'air_slash', 'parry']
    sprite['filter'] = 'linear'
    sprite['displayScale'] = 1
    sprite['idle'] = animations['idle']['frames'][0]['asset']
    bindings = {
        'light_1': ('attack_1', 1, 5, 7, 10, '一段 · 下切'),
        'light_2': ('attack_2', 1, 3, 6, 13, '二段 · 横扫'),
        'light_3': ('attack_3', 1, 1, 6, 23, '三段 · 回旋斩'),
        'charge_1': ('charge_slash', 1, 11, 16, 22, '蓄力 · 前压重斩'),
        'up_strike': ('attack_up', 1.4, 11, 17, 24, '上挑 · 回旋挑斩'),
        'air_up': ('air_slash', 1.25, 9, 13, 16, '空中挥斩'),
        'parry_1': ('parry', 1.6, 8, 15, 17, '格挡 · 弹刀'),
    }
    for move in config['moves']:
        if move['id'] not in bindings:
            continue
        animation, speed, begin, end, chain, title = bindings[move['id']]
        move.update(animation=animation, animationSpeed=speed, activeFrameStart=begin,
                    activeFrameEnd=end, chainFrame=chain, syncAnimation=True, name=title, effect='')
        fps = animations[animation]['fps'] * speed
        move.update(duration=len(animations[animation]['frames'])/fps,
                    activeStart=begin/fps, activeEnd=(end+1)/fps, chainOpen=chain/fps)
    # Physics remains responsible for movement; filmed canvas translation was removed
    # from pivots. The normal 168px player and its collision geometry are unchanged.
    config['metadata']['description'] = 'Godot 木桩训练场；已接入用户修改的非3px原版动作。'
    CONFIG.write_text(json.dumps(config, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    report = {'source': 'art/game-ready-sequences', 'pixelation': 'none', 'runtimeCopies': len(transforms),
              'sourceFrames': source_manifest['logical_frames'], 'libraryClips': len(library),
              'bindings': {key: list(value) for key, value in bindings.items()}, 'transforms': transforms}
    (ROOT / 'docs/selected-original-import.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('BOUND', len(bindings), 'moves;', len(library), 'library clips;', len(transforms), 'lossless crops', flush=True)


if __name__ == '__main__':
    main()
