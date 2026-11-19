#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 1-1A 上下两层街：把 Codex 绿底原图抠成透明站立层，量街面行、步廊行、暖灯位置（2026-11-18）。

用法：py tools/art/ch1_1a_two_level_cutout.py
读：docs/_当前分支草稿/背景线/第一章升级_20261118/1-1A上下两层街/codex原图/A*.png
写：assets/image/rain_street/ch1_1a_two_level/A*.png 与 tiles.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(r"E:\00game\nightcrow-godot")
sys.path.insert(0, str(ROOT / "tools" / "art"))
from rain_redesign_cutout import key_green, purple_ratio, split_items, full_row  # noqa: E402

SRC = ROOT / "docs" / "_当前分支草稿" / "背景线" / "第一章升级_20261118" / "1-1A上下两层街" / "codex原图"
DST = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level"


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    meta = {}
    for fp in sorted(SRC.glob("[BC]?.png")):
        code = fp.stem
        pim = Image.open(fp).convert("RGB")
        src_size = list(pim.size)
        if pim.size[1] != 941:
            pim = pim.resize((round(pim.size[0] * 941 / pim.size[1]), 941), Image.LANCZOS)
        im = np.asarray(pim).astype(np.float32) / 255.0
        rgb, a = key_green(im)
        rgba = np.concatenate([rgb, a[..., None]], axis=2)
        info = {"src": fp.name, "src_size": src_size, "purple": round(purple_ratio(rgb, a), 5)}
        info["street_row"] = full_row(rgba)
        y0 = max(0, info["street_row"] - 30)
        seg = rgba[y0:, :, :3]
        seg[..., 1] = np.minimum(seg[..., 1], (seg[..., 0] + seg[..., 2]) * 0.5 + 0.02)
        r, g, b, al = rgba[..., 0], rgba[..., 1], rgba[..., 2], rgba[..., 3]
        warm = (r > 0.5) & (r > b + 0.18) & (al > 0.5)
        info["lights"] = [[round((x0 + x1) / 2), round((y0 + y1) / 2), max(x1 - x0, y1 - y0)]
                          for (x0, y0, x1, y1) in split_items(rgba, min_area=8, mask=warm, k=2)]
        info["size"] = [rgba.shape[1], rgba.shape[0]]
        Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(DST / f"{code}.png")
        meta[code] = info
        print(code, {k: v for k, v in info.items() if k != "lights"}, len(info["lights"]), "lights")
    old = {}
    if (DST / "tiles.json").exists():
        old = json.loads((DST / "tiles.json").read_text(encoding="utf-8"))
    for code, info in meta.items():    # 手量的台面 / 裁切保留
        for k in ("platforms", "crop", "deck_row", "scale", "street_row"):
            if k in old.get(code, {}):
                info[k] = old[code][k]
    (DST / "tiles.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
