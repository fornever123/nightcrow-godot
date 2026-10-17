"""Archive prepared first-four-second PNGs and bind state-driven locomotion.

No resizing or pixelation: runtime copies only trim transparent margins. Rebuild
with no arguments after the prepared source PNGs have been archived in Git.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'art/game-ready-sequences/locomotion-first4'
TARGET = ROOT / 'assets/image/selected-original/locomotion-first4'
NAME = 'mmh3_前4秒_试跑'
SCALE = 168 / 720
SEGMENTS = {'jump': (37, 42, 24), 'fall': (43, 46, 20),
            'land': (47, 50, 4 / .15), 'run': (67, 71, 16)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepared-frames', type=Path)
    parser.add_argument('--source-video', type=Path)
    args = parser.parse_args()
    SOURCE.mkdir(parents=True, exist_ok=True)
    TARGET.mkdir(parents=True, exist_ok=True)
    if args.prepared_frames:
        assert args.source_video and args.source_video.is_file()
        paths = sorted(args.prepared_frames.glob('frame_*.png'))
        assert len(paths) == 107
        for p in paths:
            shutil.copy2(p, SOURCE / p.name)
        provenance = {'name': NAME, 'status': 'selected_for_game', 'pixelation': 'none',
                      'frames': 107, 'fps': 24, 'sourceVideo': args.source_video.name,
                      'videoSha256': hashlib.sha256(args.source_video.read_bytes()).hexdigest(),
                      'processing': 'Gray plate removal; no generated, resized or repainted character art.',
                      'files': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}}
        (SOURCE / 'manifest.json').write_text(json.dumps(provenance, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    provenance = json.loads((SOURCE / 'manifest.json').read_text(encoding='utf-8'))
    frames, transforms = [], []
    # Per-frame body anchors remove the filmed travel. The game's physics alone
    # moves the actor through the scene; a sword tip must not become the feet.
    roots = []
    for i in range(1, 108):
        p = SOURCE / f'frame_{i:05d}.png'
        assert hashlib.sha256(p.read_bytes()).hexdigest() == provenance['files'][p.name]
        with Image.open(p).convert('RGBA') as im:
            box = im.getchannel('A').getbbox()
            body = im.getchannel('A').point(lambda a: 255 if a > 200 else 0)
            # Head and shoulders locate the torso, excluding the long blade.
            top = body.crop((box[0], box[1], box[2], box[1] + min(260, (box[3]-box[1])//2)))
            head = top.getbbox()
            x = box[0] + (head[0]+head[2])/2
            region = im.crop((max(0,int(x)-220), box[1], min(im.width,int(x)+220), box[3]))
            pixels = region.load()
            ys = [y for y in range(region.height) for xx in range(region.width)
                  if pixels[xx,y][3] > 200 and max(pixels[xx,y][:3]) < 115]
            y = box[1] + max(ys) + 1
            roots.append((x,y))
    for i, (root_x, root_y) in enumerate(roots, 1):
        p = SOURCE / f'frame_{i:05d}.png'
        with Image.open(p).convert('RGBA') as im:
            box = im.getchannel('A').getbbox()
            crop = im.crop(box)
            target = TARGET / p.name
            crop.save(target, compress_level=6)
            frame = {'asset': target.relative_to(ROOT/'assets').as_posix(),
                     'width': round(crop.width*SCALE,4), 'height': round(crop.height*SCALE,4),
                     'pivotX': round((root_x-box[0])*SCALE,4),
                     'pivotY': round((root_y-box[1])*SCALE,4), 'durationTicks': 1}
            frames.append(frame)
            transforms.append({'source': p.relative_to(ROOT).as_posix(), 'asset': frame['asset'],
                               'crop': list(box), 'foot': [root_x,root_y], 'displayScale': SCALE,
                               'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
    config_path = ROOT/'assets/data/battle.json'
    config = json.loads(config_path.read_text(encoding='utf-8-sig'))
    sprite = next(c for c in config['characters'] if c['id']=='player')['sprite']
    for key,(start,end,fps) in SEGMENTS.items():
        sprite['animations'][key] = {'name': {'run':'跑步','jump':'起跳','fall':'下落','land':'落地'}[key],
            'fps': fps, 'loop': key=='run', 'holdLast': True, 'effectsBaked': True,
            'source': {'collection':'locomotion-first4-20261018','animation':NAME,
                       'firstFrame':start,'lastFrame':end}, 'frames': frames[start-1:end]}
    sprite['animations']['jump']['fullSequence'] = False
    sprite['animations']['原版_前4秒完整预览'] = {'fps':24, 'loop':True, 'holdLast':True,
        'effectsBaked':True, 'source': {'animation': NAME}, 'frames': frames}
    config['metadata']['description'] = 'Godot 木桩训练场；非3px原版攻击及前4秒跑步、起跳、下落、落地。'
    config_path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (ROOT/'docs/first4-locomotion-import.json').write_text(json.dumps(
        {'source': str(SOURCE.relative_to(ROOT)), 'sourceFrames':107,
         'segments': SEGMENTS,'transforms': transforms},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('FIRST4_IMPORTED: 107 lossless crops; run/jump/fall/land bound')


if __name__ == '__main__':
    main()
