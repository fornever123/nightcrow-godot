#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 影 2 远景素材入库：tower.png 抠绿裁边、sky.png 原样 → assets/image/rain_street/ying2/。
用法：python tools/art/bg_ying2_cutout.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"E:\00game\nightcrow-godot")
sys.path.insert(0, str(ROOT / "tools" / "art"))
from rain_redesign_cutout import key_green  # noqa: E402

S = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "影2素材"
D = ROOT / "assets" / "image" / "rain_street" / "ying2"

if __name__ == "__main__":
    D.mkdir(parents=True, exist_ok=True)
    im = np.asarray(Image.open(S / "tower.png").convert("RGB")).astype(np.float32) / 255
    rgb, a = key_green(im)
    ys, xs = np.where(a > 0.05)
    x0, x1, y0, y1 = xs.min() - 4, xs.max() + 5, ys.min(), ys.max() + 1
    out = (np.clip(np.dstack([rgb, a]), 0, 1) * 255).astype(np.uint8)[y0:y1, x0:x1]
    Image.fromarray(out, "RGBA").save(D / "tower.png")
    Image.open(S / "sky.png").convert("RGB").save(D / "sky.png")
    print("tower", out.shape)
    # 墨烟带：按行分 4 条（每条之间是整行绿）
    im = np.asarray(Image.open(S / "ink.png").convert("RGB")).astype(np.float32) / 255
    rgb, a = key_green(im)
    rows = (a > 0.08).mean(axis=1) > 0.002
    bands, y = [], 0
    while y < len(rows):
        if rows[y]:
            y0 = y
            while y < len(rows) and rows[y]:
                y += 1
            if y - y0 > 30:
                bands.append((max(0, y0 - 6), min(len(rows), y + 6)))
        y += 1
    for i, (y0, y1) in enumerate(bands[:4]):
        cols = np.where((a[y0:y1] > 0.05).any(axis=0))[0]
        x0, x1 = max(0, cols.min() - 6), min(a.shape[1], cols.max() + 7)
        piece = (np.clip(np.dstack([rgb, a]), 0, 1) * 255).astype(np.uint8)[y0:y1, x0:x1]
        Image.fromarray(piece, "RGBA").save(D / f"ink_{i}.png")
        print(f"ink_{i}", piece.shape)
