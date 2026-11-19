#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 3D 街体贴图整理（11-19）：Codex 原图 → 无缝平铺 → assets/image/rain_street/street3d/

- floor_cobble / deck_top / wall_stone：去低频明暗（照明不均）→ 半幅错位 + 十字接缝羽化，四边无缝；1024²。
- deck_face：抠绿成透明 → 左右两端交叉羽化，横向无缝；1024×256。
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(Path(__file__).parent))
from rain_redesign_cutout import key_green  # noqa: E402

ROOT = Path(r"E:\00game\nightcrow-godot")
SRC = ROOT / "docs" / "_当前分支草稿" / "背景线" / "3D街体_20261119" / "贴图原图"
DST = ROOT / "assets" / "image" / "rain_street" / "street3d"


def flatten_light(a: np.ndarray, r: int) -> np.ndarray:
    """除掉大尺度明暗（暗角、偏光），只留石头本身的颜色变化。"""
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    low = np.asarray(im.filter(ImageFilter.GaussianBlur(r))).astype(np.float32) / 255.0
    mean = a.reshape(-1, 3).mean(0)
    return np.clip(a / np.maximum(low, 0.03) * mean, 0, 1)


def seamless(a: np.ndarray, band: float = 0.18) -> np.ndarray:
    h, w, _ = a.shape
    sh = np.roll(np.roll(a, h // 2, 0), w // 2, 1)     # 原图的四边移到中间十字
    yy, xx = np.mgrid[0:h, 0:w]
    dx = np.abs(xx - w / 2) / (w * band)
    dy = np.abs(yy - h / 2) / (h * band)
    m = np.clip(np.minimum(dx, dy), 0, 1)[..., None]  # 十字附近用原图（原图那里是连续的），其余用错位图
    m = m * m * (3 - 2 * m)
    return sh * m + a * (1 - m)


def tile_square(name: str) -> None:
    im = Image.open(SRC / f"{name}.png").convert("RGB")
    s = min(im.size)
    im = im.crop(((im.width - s) // 2, (im.height - s) // 2, (im.width - s) // 2 + s, (im.height - s) // 2 + s)).resize((1024, 1024), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32) / 255.0
    a = flatten_light(a, 120)
    a = seamless(a)
    Image.fromarray((a * 255).astype(np.uint8)).save(DST / f"{name}.png")
    print(name, "ok", a.mean(axis=(0, 1)).round(3))


def strip(name: str, size=(1024, 256)) -> None:
    im = Image.open(SRC / f"{name}.png").convert("RGB").resize(size, Image.LANCZOS)
    rgb = np.asarray(im).astype(np.float32) / 255.0
    a, out = key_green(rgb)[1], key_green(rgb)[0]
    rgba = np.dstack([out, a])
    w = rgba.shape[1]
    b = int(w * 0.12)                                  # 两端各 12% 交叉羽化：右端渐变成左端
    t = np.linspace(0, 1, b)[None, :, None]
    head = rgba[:, :b].copy()
    rgba[:, w - b:] = rgba[:, w - b:] * (1 - t) + head * t
    rgba = rgba[:, : w - b]
    rows = np.where(rgba[..., 3].mean(1) > 0.08)[0]    # 只留有东西的那几行（Codex 常把长条画在画幅中间）
    rgba = rgba[rows.min(): rows.max() + 1]
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").resize(size, Image.LANCZOS)
    img.save(DST / f"{name}.png")
    print(name, "ok", "alpha", float((rgba[..., 3] > 0.5).mean()))


def bay_strip(name: str, h_out=512) -> None:
    """柱拱长条：按柱子中心截成整数个开间（首尾都是半根柱子），横向平铺就严丝合缝，不靠羽化。"""
    rgb = np.asarray(Image.open(SRC / f"{name}.png").convert("RGB")).astype(np.float32) / 255.0
    out, a = key_green(rgb)
    rows = np.where(a.mean(1) > 0.08)[0]
    out, a = out[rows.min(): rows.max() + 1], a[rows.min(): rows.max() + 1]
    h = a.shape[0]
    band = a[int(h * 0.72): int(h * 0.9)].mean(0)          # 柱身那一段：有柱子的列不透明
    solid = band > 0.5
    cols, x = [], 0
    while x < len(solid):
        if solid[x]:
            x0 = x
            while x < len(solid) and solid[x]:
                x += 1
            if x - x0 > 10:
                cols.append((x0 + x) // 2)
        x += 1
    c0, c1 = cols[0], cols[-1]
    if c0 < 8:                                               # 贴边的半根柱子中心不可信，往里取一根
        c0 = cols[1]
    if len(solid) - c1 < 8:
        c1 = cols[-2]
    rgba = np.dstack([out, a])[:, c0:c1]
    w = int(round(rgba.shape[1] * h_out / h))
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").resize((w, h_out), Image.LANCZOS).save(DST / f"{name}.png")
    print(name, "bays", len(cols), "cut", c0, c1, "->", w, "x", h_out)


def cutout(name: str) -> list:
    """立体道具：抠绿 → 按透明列切成单件 → 各自裁到外框。"""
    rgb = np.asarray(Image.open(SRC / f"{name}.png").convert("RGB")).astype(np.float32) / 255.0
    out, a = key_green(rgb)
    cols = a.max(0) > 0.5
    parts, x = [], 0
    w = len(cols)
    while x < w:
        if cols[x]:
            x0 = x
            while x < w and cols[x]:
                x += 1
            if x - x0 > 24:
                parts.append((x0, x))
        x += 1
    saved = []
    for i, (x0, x1) in enumerate(parts):
        sub_a = a[:, x0:x1]
        rows = np.where(sub_a.max(1) > 0.5)[0]
        y0, y1 = rows.min(), rows.max() + 1
        rgba = np.dstack([out[y0:y1, x0:x1], a[y0:y1, x0:x1]])
        nm = name if len(parts) == 1 else f"{name}_{i}"
        Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(DST / f"{nm}.png")
        c = rgba[..., :3]
        warm = np.clip((c[..., 0] - 0.45) / 0.3, 0, 1) * np.clip((c[..., 0] - c[..., 2] - 0.08) / 0.2, 0, 1)
        if warm.mean() > 0.002:    # 自发光遮罩：只留暖色亮处（窗里的灯），石框不发光
            em = np.dstack([c * warm[..., None], rgba[..., 3:]])
            Image.fromarray((np.clip(em, 0, 1) * 255).astype(np.uint8), "RGBA").save(DST / f"{nm}_emit.png")
        saved.append((nm, x1 - x0, y1 - y0))
    print(name, saved)
    return saved


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    for n in ["floor_cobble", "deck_top", "wall_stone", "u2_floor", "u2_roof"]:
        if (SRC / f"{n}.png").exists():
            tile_square(n)
    if (SRC / "deck_face.png").exists():
        strip("deck_face")
    for n in ["u2_balustrade"]:
        if (SRC / f"{n}.png").exists():
            strip(n)
    if (SRC / "u2p_arcade_front.png").exists():
        bay_strip("u2p_arcade_front")
    if (SRC / "u2p_arcade_back.png").exists():
        strip("u2p_arcade_back", (1536, 512))
    for n in ["prop_lamp", "prop_bollard", "u2_windows", "u2_doors", "u2p_house_a", "u2p_house_b", "u2p_house_c"]:
        if (SRC / f"{n}.png").exists():
            cutout(n)


if __name__ == "__main__":
    main()
