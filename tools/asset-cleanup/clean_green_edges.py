"""Remove Nightcrow green-screen fringe into separate PNGs.

Source files stay untouched. Key-colored edge pixels lose their alpha.
Other pixels only have a green spill pulled down. Width, height, and the
alpha of real character pixels stay the same.
"""
from pathlib import Path
import hashlib
import json

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/image/characters/nightcrow'
OUTPUT = ROOT / 'assets/image/cleaned/nightcrow'


def is_key(r, g, b, a):
    if a == 0:
        return False
    return g >= 70 and r < 110 and b < 110 and g - max(r, b) >= 28


def clean(image):
    original = image.convert('RGBA')
    width, height = original.size
    src = original.load()
    out = Image.new('RGBA', (width, height))
    dst = out.load()
    removed = 0
    despilled = 0
    for y in range(height):
        for x in range(width):
            r, g, b, a = src[x, y]
            if is_key(r, g, b, a):
                neighbor_clear = a < 180
                if not neighbor_clear:
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            if dx == dy == 0:
                                continue
                            xx, yy = x + dx, y + dy
                            if xx < 0 or yy < 0 or xx >= width or yy >= height or src[xx, yy][3] < 48:
                                neighbor_clear = True
                if neighbor_clear:
                    dst[x, y] = (0, 0, 0, 0)
                    removed += 1
                    continue
            if a and g - max(r, b) > 6:
                g = max(r, b)
                despilled += 1
            dst[x, y] = (r, g, b, a)
    # Give fully transparent pixels a nearby character color so filtering cannot pick up green.
    colors = [[dst[x, y][:3] if dst[x, y][3] else None for x in range(width)] for y in range(height)]
    for _ in range(4):
        nxt = [row[:] for row in colors]
        for y in range(height):
            for x in range(width):
                if colors[y][x] is not None:
                    continue
                total = [0, 0, 0]
                count = 0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dx == dy == 0:
                            continue
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < width and 0 <= yy < height and colors[yy][xx] is not None:
                            pixel = colors[yy][xx]
                            total[0] += pixel[0]
                            total[1] += pixel[1]
                            total[2] += pixel[2]
                            count += 1
                if count:
                    nxt[y][x] = (total[0] // count, total[1] // count, total[2] // count)
        colors = nxt
    for y in range(height):
        for x in range(width):
            if dst[x, y][3] == 0 and colors[y][x] is not None:
                dst[x, y] = (*colors[y][x], 0)
    for y in range(height):
        for x in range(width):
            r, g, b, a = src[x, y]
            nr, ng, nb, na = dst[x, y]
            if a == 0:
                if na != 0:
                    raise RuntimeError(f'alpha added at {x},{y}')
                continue
            if is_key(r, g, b, a):
                continue
            if na != a:
                raise RuntimeError(f'alpha changed at {x},{y}')
            if g - max(r, b) <= 6 and (nr, ng, nb) != (r, g, b):
                raise RuntimeError(f'color changed at {x},{y}')
    return out, removed, despilled


def comparison(before, after):
    before, after = before.convert('RGBA'), after.convert('RGBA')
    size = (before.width * 4, before.height * 4)
    board = Image.new('RGB', (size[0] * 2 + 60, size[1] + 58), '#20212c')
    draw = ImageDraw.Draw(board)
    draw.text((20, 15), 'Before: green screen fringe', fill='white')
    draw.text((size[0] + 40, 15), 'After: key pixels removed', fill='white')
    for index, img in enumerate((before, after)):
        layer = Image.new('RGBA', img.size, '#20212c')
        layer.alpha_composite(img)
        board.paste(layer.convert('RGB').resize(size, Image.Resampling.NEAREST), (20 + index * (size[0] + 20), 38))
    board.save(ROOT / 'docs/green-edge-comparison.png')


def main():
    entries = []
    removed = 0
    despilled = 0
    for source in sorted(SOURCE.rglob('*.png')):
        before = Image.open(source)
        after, gone, tinted = clean(before)
        target = OUTPUT / source.relative_to(SOURCE)
        target.parent.mkdir(parents=True, exist_ok=True)
        after.save(target)
        entries.append({
            'source': source.relative_to(ROOT / 'assets').as_posix(),
            'cleaned': target.relative_to(ROOT / 'assets').as_posix(),
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'key_pixels_removed': gone,
            'spill_pixels_despilled': tinted,
        })
        removed += gone
        despilled += tinted
        if source.relative_to(SOURCE).as_posix() == 'idle/frame_0001.png':
            comparison(before, after)
    report = {
        'method': 'delete green-key edge pixels; despill remaining green excess; keep source files',
        'dimensions_unchanged': True,
        'character_alpha_unchanged': True,
        'frames': len(entries),
        'key_pixels_removed': removed,
        'spill_pixels_despilled': despilled,
        'files': entries,
    }
    (ROOT / 'docs/green-edge-cleanup.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'GREEN_EDGE_CLEANUP: {len(entries)} frames / {removed} key pixels removed / {despilled} despilled')


if __name__ == '__main__':
    main()
