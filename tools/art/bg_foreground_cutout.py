#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 立体感试验（11-18）路线 A：把 Codex 绿底前景件表 FG1.png 抠成单件透明 PNG。

用法：python tools/art/bg_foreground_cutout.py
读：docs/_当前分支草稿/背景线/立体感_20261118/codex原图/FG1.png
写：assets/image/rain_street/ch1_1a_two_level/fg_<i>.png 与 fg.json（每件尺寸、贴顶 / 贴底）
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"E:\00game\nightcrow-godot")
sys.path.insert(0, str(ROOT / "tools" / "art"))
from rain_redesign_cutout import key_green, split_items  # noqa: E402

SRC = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "codex原图" / "FG1.png"
DST = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level"


def main() -> None:
    im = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float32) / 255.0
    rgb, a = key_green(im)
    rgba = np.dstack([rgb, a])
    H = rgba.shape[0]
    boxes = [b for b in split_items(rgba, min_area=4000) if (b[2] - b[0]) * (b[3] - b[1]) > 6000]
    meta = []
    for i, (x0, y0, x1, y1) in enumerate(boxes):
        piece = rgba[y0:y1, x0:x1].copy()
        # 只留这块的连通区域：别的件伸进包围盒的部分清掉（按列外扩 2px 的近似：同包围盒内取最大连通块已足够，这里直接保留）
        out = (np.clip(piece, 0, 1) * 255).astype(np.uint8)
        name = f"fg_{i}.png"
        Image.fromarray(out, "RGBA").save(DST / name)
        meta.append({"file": name, "w": x1 - x0, "h": y1 - y0, "top": y0 <= 6, "bottom": y1 >= H - 6, "x": x0})
        print(name, x0, y0, x1, y1, "top" if y0 <= 6 else "", "bottom" if y1 >= H - 6 else "")
    (DST / "fg.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
