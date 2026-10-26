"""Import the 2026-10-26 authored charge action without resampling source pixels.

Full RGB/transparent source PNGs are archived byte-for-byte. Runtime copies only
trim empty canvas borders; pivots retain full-canvas coordinates. No generation.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageFilter
from statistics import median
import copy
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path('C:/Users/MECHREVO/Desktop/实际应用到游戏的序列帧/蓄力及蓄力攻击_20261026')
REPORT = ROOT / 'docs/charge-actions-20261026.json'


def body_center(path):
    """Measure a dark connected torso, excluding bright blade/dust pixels."""
    im = Image.open(path).convert('RGBA').resize((640, 360), Image.Resampling.BILINEAR)
    r, g, b = im.convert('RGB').split()
    maximum = ImageChops.lighter(ImageChops.lighter(r, g), b)
    mask = ImageChops.multiply(maximum.point(lambda x: 255 if x < 165 else 0),
        im.getchannel('A').point(lambda x: 255 if x > 180 else 0))
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
    width, height = mask.size
    pixels = mask.tobytes()
    seen, largest = set(), []
    for origin, alpha in enumerate(pixels):
        if not alpha or origin in seen:
            continue
        stack, component = [origin], []
        seen.add(origin)
        while stack:
            index = stack.pop()
            component.append(index)
            for next_index in (index-1, index+1, index-width, index+width):
                if next_index < 0 or next_index >= len(pixels) or next_index in seen or not pixels[next_index]:
                    continue
                if abs(next_index-index) == 1 and next_index//width != index//width:
                    continue
                seen.add(next_index)
                stack.append(next_index)
        if len(component) > len(largest):
            largest = component
    if len(largest) < 20:
        raise ValueError(f'No measurable body: {path.name}')
    xs, ys = [i % width for i in largest], [i // width for i in largest]
    return median(xs)*2, (min(ys)+max(ys))


def smooth(values):
    return [median(values[max(0,i-1):min(len(values),i+2)]) for i in range(len(values))]


def apply_saved_binding(config, record=None):
    if record is None:
        if not REPORT.exists():
            return
        record = json.loads(REPORT.read_text(encoding='utf-8'))
    sprite = next(c for c in config['characters'] if c['id'] == 'player')['sprite']
    sprite['animations'].update(copy.deepcopy(record['animations']))
    sprite.update(chargeAnimation='charge_hold', chargeAnimated=True)
    if 'preloadAnimations' in sprite and 'charge_hold' not in sprite['preloadAnimations']:
        sprite['preloadAnimations'].append('charge_hold')
    charge = next(m for m in config['moves'] if m['id'] == 'charge_1')
    charge.update(copy.deepcopy(record['movePatch']))


def main():
    config_path = ROOT / 'assets/data/battle.json'
    before = ROOT / '.runtime/charge-20261026/battle.before.json'
    before.parent.mkdir(parents=True, exist_ok=True)
    if not before.exists():
        shutil.copy2(config_path, before)
    info = json.loads((SOURCE/'序列帧信息.json').read_text(encoding='utf-8-sig'))
    files = sorted((SOURCE/'02_完整透明序列帧').glob('*.png'))
    if len(files) != 145:
        raise ValueError('Expected all 145 full source frames')
    archive = ROOT/'source-art/charge-20261026'
    for origin_name, archive_name in [('01_原视频序列帧','original'),('02_完整透明序列帧','transparent')]:
        destination = archive/archive_name
        destination.mkdir(parents=True,exist_ok=True)
        for path in sorted((SOURCE/origin_name).glob('*.png')):
            shutil.copy2(path,destination/path.name)
    for name in ['序列帧信息.json','说明.txt']:
        shutil.copy2(SOURCE/name,archive/name)
    config = json.loads(config_path.read_text(encoding='utf-8-sig'))
    sprite = next(c for c in config['characters'] if c['id'] == 'player')['sprite']
    # Same 168 world-pixel body height as the current character; PNGs not resized.
    physical_scale = 168.0 / 186.0
    logical_scale = physical_scale / float(sprite['displayScale'])
    centers = [body_center(path) for path in files[60:]]
    center_x = smooth([c[0] for c in centers])
    center_y = smooth([c[1] for c in centers])
    root_x, root_y, farthest = [], [], 0.0
    for i, (cx, cy) in enumerate(zip(center_x,center_y)):
        # The video's later camera recentering must not move the game actor back.
        farthest = max(farthest, cx-center_x[0])
        root_x.append(round(farthest*physical_scale,5))
        # Authored short hop only; crouched recovery stays on the real floor.
        rise = min(0.0, cy + (520.0-center_y[0]) - 520.0) if 5 <= i <= 19 else 0.0
        root_y.append(round(rise*physical_scale,5))
    animations, measurements = {}, []
    for key, folder, start, end, name in [
        ('charge_hold','hold-spin',36,60,'蓄力 · 转圈循环'),
        ('charge_slash','release',60,145,'蓄力释放 · 起跳下劈')]:
        runtime = ROOT/'assets/image/charge-20261026'/folder
        runtime.mkdir(parents=True,exist_ok=True)
        frames = []
        for local, source_index in enumerate(range(start,end)):
            source = files[source_index]
            im = Image.open(source).convert('RGBA')
            box = im.getbbox()
            if not box:
                box = (0,0,1,1)
            left,top,right,bottom = box
            crop = (max(0,left-2),max(0,top-2),min(1280,right+2),min(720,bottom+2))
            # Lossless trim of transparent borders only. Includes all baked FX.
            cropped = im.crop(crop)
            output = runtime/f'frame_{local+1:05d}.png'
            cropped.save(output)
            assert cropped.tobytes() == im.crop(crop).tobytes()
            cx = 276.0 if key == 'charge_hold' else center_x[local]
            py = 520.0 if key == 'charge_hold' else 520.0 + root_y[local]/physical_scale
            frame = {'asset':output.relative_to(ROOT/'assets').as_posix(),
                'width':round(cropped.width*logical_scale,5),'height':round(cropped.height*logical_scale,5),
                'pivotX':round((cx-crop[0])*logical_scale,5),'pivotY':round((py-crop[1])*logical_scale,5),
                'durationTicks':max(1,round(info['durations'][source_index]*60)),
                'sourceFrame':source_index+1,'sourceCanvas':{'width':1280,'height':720},
                'sourceCrop':list(crop)}
            frames.append(frame)
            measurements.append({'sourceFrame':source_index+1,'sourceSha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                'runtimeAsset':frame['asset'],'sourceCrop':list(crop)})
        clip = {'name':name,'fps':60.0,'frames':frames,'loop':key=='charge_hold','loopFrame':0,
            'holdLast':True,'sourceFacing':1,'effectsBaked':True,
            'sourceName':'蓄力及蓄力攻击_20261026','sourceFrameStart':start,'sourceFrameEnd':end-1,
            'sourceDuration':sum(f['durationTicks'] for f in frames)/60,
            'source':{'collection':'charge-20261026','firstFrame':start+1,'lastFrame':end},
            'runtimeCoordinateScale':logical_scale,'runtimeAnchor':'original feet; release tracked body; no resampling'}
        if key == 'charge_slash':
            clip.update(rootMotionX=root_x,rootMotionY=root_y,rootMotionSmooth=True)
        animations[key] = clip
    release = animations['charge_slash']
    elapsed = lambda count:sum(f['durationTicks'] for f in release['frames'][:count])/60
    move_patch = {'name':'蓄力 · 起跳下劈','animation':'charge_slash','animationSpeed':1.0,'syncAnimation':True,
        'activeFrameStart':19,'activeFrameEnd':28,'chainFrame':54,
        'duration':elapsed(85),'activeStart':elapsed(19),'activeEnd':elapsed(29),'chainOpen':elapsed(54),
        'minHold':.35,'maxHold':2.5,'effect':'','lunge':0,
        'hitbox':{'x':125,'y':-85,'width':300,'height':190},
        'startupSpeed':1.0,'activeSpeed':1.0,'recoverySpeed':1.0,'tailSpeed':1.0,'moveCancelDelay':0}
    record = {'collection':'charge-20261026','source':str(SOURCE),'count':145,'runtimeFrameCount':len(measurements),
        'sourceCanvas':[1280,720],'physicalSourceScale':physical_scale,'animations':animations,
        'movePatch':move_patch,'frames':measurements,
        'note':'All 145 source frames archived byte-for-byte; charging uses source37-60 spin only, source1-36 preparation excluded from playback. Runtime only crops transparent borders; no pixels resampled.'}
    REPORT.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    apply_saved_binding(config,record)
    config_path.write_text(json.dumps(config,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'CHARGE_IMPORTED: {len(files)} original frames; spin=source37-60 / {animations["charge_hold"]["sourceDuration"]:.1f}s loop; release={elapsed(85):.6f}s; hop={min(root_y):.1f}px advance={max(root_x):.1f}px')


if __name__ == '__main__':
    main()
