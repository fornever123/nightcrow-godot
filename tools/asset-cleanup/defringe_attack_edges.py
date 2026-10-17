"""Pull pale rims off Nightcrow attack frames.

The playable attack cuts keep a 1px edge that is lighter than the body
behind it, which reads as a white outline. Originals under
assets/image/characters stay untouched. Alpha stays unchanged.
"""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "assets/image/cleaned/nightcrow"
CLIPS = ("attack_1", "attack_2", "attack_3", "attack_up")


def defringe(image: Image.Image) -> tuple[Image.Image, int]:
    src = image.convert("RGBA")
    width, height = src.size
    px = src.load()
    out = src.copy()
    dst = out.load()
    changed = 0

    def opaque(x: int, y: int) -> bool:
        return 0 <= x < width and 0 <= y < height and px[x, y][3] > 200

    for y in range(height):
        for x in range(width):
            r, g, b, a = px[x, y]
            if a < 200:
                continue
            inward = []
            touches_clear = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if opaque(x + dx, y + dy):
                    continue
                touches_clear = True
                for step in (1, 2):
                    ix, iy = x - dx * step, y - dy * step
                    if opaque(ix, iy):
                        inward.append(px[ix, iy])
            if not touches_clear or not inward:
                continue
            ir = sum(c[0] for c in inward) / len(inward)
            ig = sum(c[1] for c in inward) / len(inward)
            ib = sum(c[2] for c in inward) / len(inward)
            edge_lum = (r + g + b) / 3
            inner_lum = (ir + ig + ib) / 3
            # Bright costume and the sword stay; only a pale rim on a dark body moves.
            if inner_lum < 95 and edge_lum > inner_lum + 12:
                dst[x, y] = (int(ir), int(ig), int(ib), a)
                changed += 1
    return out, changed


def main() -> None:
    frames = 0
    pixels = 0
    for clip in CLIPS:
        folder = TARGET / clip
        for path in sorted(folder.glob("*.png")):
            before = Image.open(path)
            after, changed = defringe(before)
            if after.size != before.size:
                raise RuntimeError(f"size changed: {path}")
            after.save(path)
            frames += 1
            pixels += changed
    print(f"ATTACK_DEFRINGE: {frames} frames / {pixels} rim pixels")


if __name__ == "__main__":
    main()
