"""Import the desktop sequences, keeping every real transition frame.

Frozen copies at the head and tail of a clip are not transitions, so those
long holds shrink to nothing. Slow follow-through, recovery, stride, and air
frames stay, and playback speed is set so a jump shows each of them once.
Desktop files and the original character sources are left unchanged.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DESKTOP = Path(r'C:\Users\MECHREVO\Desktop\新建文件夹\序列帧')
OUT = ROOT / 'assets/image/cleaned/nightcrow'
BATTLE = ROOT / 'assets/data/battle.json'
TARGET = 168
AIR_TIME = 0.28 + 0.20
LAND_TIME = 0.15

# Inclusive source frame numbers. Attack 3 drops only the identical idle
# copies before the windup and after the recovery. Jump drops the idle
# padding and keeps crouch, leap, air, and landing. Run drops the idle
# padding and keeps the stride, including the short in-betweens.
CLIPS = {
    # Source frames 1-9 are the long raise. The light attack starts as the sword comes forward.
    'attack_1': ('三段攻击的第一段', 10, 22),
    # The uppercut still needs the overhead frames the light attack no longer plays.
    'attack_up': ('三段攻击的第一段', 4, 14),
    'attack_2': ('三段攻击第二段有后摇', 1, 37),
    'attack_3': ('三段a第三段', 11, 44),
    'jump': ('跳跃', 33, 86),
    'fall': ('跳跃', 42, 78),
    'land': ('跳跃', 79, 86),
    # 1-27 of the run folder is the standing sway. 28-35 lead into the stride
    # and play once; the loop starts at source frame 36.
    'idle': ('待机', 1, 35),
    'run': ('跑步', 28, 97),
}


def files_of(folder):
    return sorted((DESKTOP / folder).glob('*.png'))


def measure(image):
    px = image.load()
    width, height = image.size
    counts = [0] * width
    for y in range(height):
        for x in range(width):
            if px[x, y][3] >= 40:
                counts[x] += 1
    peak = max(counts) or 1
    dense = [x for x, count in enumerate(counts) if count >= max(18, peak * 0.45)]
    if not dense:
        dense = [x for x, count in enumerate(counts) if count > 0]
    torso_x = sorted(dense)[len(dense) // 2]
    head = None
    for y in range(height):
        run = best = 0
        for x in range(max(0, torso_x - 90), min(width, torso_x + 90)):
            if px[x, y][3] >= 40:
                run += 1
                best = max(best, run)
            else:
                run = 0
        if best >= 10:
            head = y
            break
    bottoms = {}
    threshold = max(10, int(peak * 0.18))
    for x, count in enumerate(counts):
        if count < threshold:
            continue
        for y in range(height - 1, -1, -1):
            if px[x, y][3] >= 40:
                bottoms.setdefault((y // 10) * 10, []).append(x)
                break
    solid = {key: value for key, value in bottoms.items() if len(value) >= 14}
    if not solid:
        solid = bottoms or {height - 10: [torso_x]}
    ground = max(solid)
    return torso_x, ground + 9, head if head is not None else 0


def smooth(values, limit):
    cleaned = []
    for index, value in enumerate(values):
        window = sorted(values[max(0, index - 2):index + 3])
        middle = window[len(window) // 2]
        cleaned.append(value if abs(value - middle) <= limit else middle)
    return cleaned


def standing_scale(folder, index):
    image = Image.open(files_of(folder)[index - 1]).convert('RGBA')
    _torso, foot, head = measure(image)
    return TARGET / max(1, foot - head)


def prepare(name, folder, first, last, scale):
    chosen = files_of(folder)[first - 1:last]
    images = [Image.open(source).convert('RGBA') for source in chosen]
    measured = [measure(image) for image in images]
    xs = smooth([item[0] for item in measured], 48)
    ys = smooth([item[1] for item in measured], 40)
    placed = []
    min_x = min_y = 10 ** 9
    max_x = max_y = -10 ** 9
    for image, foot_x, foot_y in zip(images, xs, ys):
        bbox = image.getbbox()
        placed.append((image, foot_x, foot_y, bbox))
        min_x = min(min_x, bbox[0] - foot_x)
        max_x = max(max_x, bbox[2] - foot_x)
        min_y = min(min_y, bbox[1] - foot_y)
        max_y = max(max_y, bbox[3] - foot_y)
    pad = 4
    min_x -= pad
    min_y -= pad
    max_x += pad
    max_y += pad
    folder_out = OUT / name
    if folder_out.exists():
        for old in folder_out.glob('*.png'):
            old.unlink()
    folder_out.mkdir(parents=True, exist_ok=True)
    frames = []
    for index, (image, foot_x, foot_y, _bbox) in enumerate(placed, start=1):
        crop = image.crop((
            int(round(foot_x + min_x)),
            int(round(foot_y + min_y)),
            int(round(foot_x + max_x)),
            int(round(foot_y + max_y)),
        ))
        resized = crop.resize(
            (max(1, round(crop.width * scale)), max(1, round(crop.height * scale))),
            Image.Resampling.BOX,
        )
        resized = harden(resized)
        resized.save(folder_out / f'frame_{index:04d}.png')
        frames.append({
            'asset': f'image/cleaned/nightcrow/{name}/frame_{index:04d}.png',
            'width': resized.width,
            'height': resized.height,
            'pivotX': round(-min_x * scale, 3),
            'pivotY': round(-min_y * scale, 3),
        })
    return frames


def harden(image):
    """Drop the pale halo BOX resize leaves around hard-edged art."""
    image = image.copy()
    px = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = px[x, y]
            if alpha < 200:
                px[x, y] = (0, 0, 0, 0)
            elif alpha < 255:
                px[x, y] = (red, green, blue, 255)
    return image


def sync(move, count, fps):
    move['duration'] = count / fps
    move['activeStart'] = move['activeFrameStart'] / fps
    move['activeEnd'] = (move['activeFrameEnd'] + 1) / fps
    move['chainOpen'] = move['chainFrame'] / fps


def main():
    attack_scale = standing_scale('三段攻击第二段有后摇', 37)
    jump_scale = standing_scale('跳跃', 86)
    run_scale = standing_scale('跑步', 97)
    idle_scale = standing_scale('待机', 1)
    print(f'scale attack {attack_scale:.4f} jump {jump_scale:.4f} run {run_scale:.4f} idle {idle_scale:.4f}')
    clips = {}
    for name, (folder, first, last) in CLIPS.items():
        if folder == '跳跃':
            scale = jump_scale
        elif folder == '跑步':
            # Same scale as standing, so the lead-in frames match the idle clip.
            scale = idle_scale
        elif folder == '待机':
            scale = idle_scale
        else:
            scale = attack_scale
        clips[name] = prepare(name, folder, first, last, scale)
        print(name, len(clips[name]), 'from', first, last)

    battle = json.loads(BATTLE.read_text(encoding='utf-8'))
    animations = next(actor for actor in battle['characters'] if actor['id'] == 'player')['sprite']['animations']
    fps = {
        'attack_1': 36,
        'attack_2': 36,
        'attack_3': 36,
        # One pass across the rise, the fall, and the landing timer.
        'jump': round(len(clips['jump']) / (AIR_TIME + LAND_TIME), 3),
        'fall': 48,
        'land': round(len(clips['land']) / LAND_TIME, 3),
        'run': 24,
        'attack_up': 36,
        'idle': 12,
    }
    for name, frames in clips.items():
        animations[name] = animations.get(name, {'loop': False, 'holdLast': True})
        animations[name]['frames'] = frames
        animations[name]['fps'] = fps[name]
        animations[name]['loop'] = name in ('run', 'idle')
        animations[name]['holdLast'] = True
        if name == 'run':
            # Source 36 is the first stride. Frames before that play once, then the cycle repeats.
            animations[name]['loopFrame'] = 36 - 28
        elif 'loopFrame' in animations[name]:
            animations[name].pop('loopFrame', None)
    moves = {move['id']: move for move in battle['moves']}
    # Clip starts at source frame 10, so index 3 is source frame 13, the thrust.
    moves['light_1'].update(activeFrameStart=3, activeFrameEnd=3, chainFrame=6)
    # Frames 13-16 are the forward thrust. The raise before that still plays.
    moves['light_2'].update(activeFrameStart=12, activeFrameEnd=15, chainFrame=22)
    # Frames 8-10 are the downward slash. Index 2 stays the overhead charge pose.
    moves['light_3'].update(activeFrameStart=7, activeFrameEnd=9, chainFrame=18)
    moves['charge_1'].update(activeFrameStart=7, activeFrameEnd=9, chainFrame=14)
    # Source frames 4-6, the sword at its highest.
    moves['up_strike'].update(animation='attack_up', activeFrameStart=0, activeFrameEnd=2, chainFrame=6)
    moves['air_up'].update(activeFrameStart=3, activeFrameEnd=3, chainFrame=6)
    for move in battle['moves']:
        if not move.get('syncAnimation'):
            continue
        clip_name = move['animation']
        sync(move, len(animations[clip_name]['frames']), fps[clip_name] * move.get('animationSpeed', 1))
    BATTLE.write_text(json.dumps(battle, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('battle.json updated', {name: fps[name] for name in fps})

    preview = ROOT / '.runtime/review/imported'
    preview.mkdir(parents=True, exist_ok=True)
    for name in ('attack_1', 'attack_2', 'attack_3', 'jump', 'run'):
        frames = clips[name]
        step = 1 if len(frames) <= 40 else 2
        shown = list(enumerate(frames))[::step]
        cell_w = max(frame['width'] for frame in frames) + 8
        cell_h = max(frame['height'] for frame in frames) + 16
        cols = 8
        rows = (len(shown) + cols - 1) // cols
        board = Image.new('RGB', (cols * cell_w + 8, rows * cell_h + 8), (24, 26, 34))
        draw = ImageDraw.Draw(board)
        for slot, (index, frame) in enumerate(shown):
            image = Image.open(ROOT / 'assets' / frame['asset']).convert('RGBA')
            row, col = divmod(slot, cols)
            origin_x = 4 + col * cell_w
            origin_y = 4 + row * cell_h
            board.paste(image, (origin_x + 2, origin_y + 2), image)
            foot_y = origin_y + 2 + int(round(frame['pivotY']))
            draw.line((origin_x, foot_y, origin_x + cell_w - 6, foot_y), fill=(180, 90, 90))
            draw.text((origin_x + 4, origin_y + cell_h - 12), str(index + 1), fill=(230, 230, 240))
        board.thumbnail((1400, 1600), Image.Resampling.BOX)
        board.save(preview / f'{name}.png')
        print('preview', name, board.size)


if __name__ == '__main__':
    main()
