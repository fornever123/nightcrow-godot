"""Rebuild the joined foreground from the preserved left and prepared right PNGs.
Run from any cwd: python tools/art/build_rain_street_complete.py
Green original, approved original and repaired right source remain unchanged.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
left = Image.open(ROOT / 'assets/image/rain_street/near_plaza_left.png').convert('RGBA')
right = Image.open(ROOT / 'source-art/rain-right-20261028/near_right_prepared.png').convert('RGBA')
assert left.size == (1672, 941) and right.size == (1417, 941)
combined = Image.new('RGBA', (3089, 941))
combined.alpha_composite(left, (0, 0))
combined.alpha_composite(right, (1672, -1))
combined.save(ROOT / 'assets/image/rain_street/near_plaza_complete_20261028.png')
