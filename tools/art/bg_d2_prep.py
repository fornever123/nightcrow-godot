#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · D2 三层景深：把 bg_d2_codex.py 的原图处理进游戏素材。
- B1～B3：缩回 1672×941、抠绿成透明天空；和旧图比对轮廓（能走的结构不准挪），出叠图供肉眼查；
- far：远景长条，左右交叉羽化成无缝；
- fg：前景构件抠绿、按透明列切成单件。
产物：assets/image/rain_street/ch1_1a_d2/
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from rain_redesign_cutout import key_green  # noqa: E402

ROOT = Path(r"E:\00game\nightcrow-godot")
SRC = ROOT / "docs" / "_当前分支草稿" / "背景线" / "D2三层_20261119" / "原图"
CHK = ROOT / "docs" / "_当前分支草稿" / "背景线" / "D2三层_20261119" / "对齐检查"
OLD = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level"
DST = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_d2"


def tile(code: str) -> None:
    im = Image.open(SRC / f"{code}.png").convert("RGB").resize((1672, 941), Image.LANCZOS)
    rgb = np.asarray(im).astype(np.float32) / 255.0
    out, a = key_green(rgb)
    rgba = np.dstack([out, a])
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(DST / f"{code}.png")
    old = np.asarray(Image.open(OLD / f"{code}.png").convert("RGBA")).astype(np.float32) / 255.0
    ma, mb = old[..., 3] > 0.5, a > 0.5
    iou = (ma & mb).sum() / max(1, (ma | mb).sum())
    # 每列最上面一个不透明像素（楼的天际线）差多少
    def sky(m):
        has = m.any(0)
        top = np.argmax(m, 0).astype(float)
        top[~has] = np.nan
        return top
    d = np.abs(sky(ma) - sky(mb))
    # 叠图：旧图红、新图青，对齐处是灰
    lo = old[..., :3].mean(2)
    ln = out.mean(2)
    chk = np.dstack([lo, ln, ln])
    CHK.mkdir(parents=True, exist_ok=True)
    Image.fromarray((np.clip(chk * 1.6, 0, 1) * 255).astype(np.uint8)).save(CHK / f"{code}_旧红新青.jpg", quality=88)
    print(code, "轮廓 IoU %.3f" % iou, "天际线偏差 中位 %.0f px / 90%% %.0f px" % (np.nanmedian(d), np.nanpercentile(d, 90)))


def behind(name: str) -> None:
    """房子后面的夜城天际线：抠绿 → 左右交叉羽化成无缝。"""
    im = Image.open(SRC / f"{name}.png").convert("RGB").resize((2400, 800), Image.LANCZOS)
    rgb = np.asarray(im).astype(np.float32) / 255.0
    out, a = key_green(rgb)
    rgba = np.dstack([out, a])
    w = rgba.shape[1]
    b = int(w * 0.12)
    t = np.linspace(0, 1, b)[None, :, None]
    rgba[:, w - b:] = rgba[:, w - b:] * (1 - t) + rgba[:, :b] * t
    rgba = rgba[:, : w - b]
    Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(DST / f"{name}.png")
    top = np.argmax(rgba[..., 3] > 0.5, 0)
    print(name, rgba.shape, "天际线行 最高 %d 中位 %d" % (top.min(), int(np.median(top))))


def street() -> None:
    im = Image.open(SRC / "street.png").convert("RGB").resize((2048, 512), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)[40:]          # 去掉最上面那道墙脚线：接在原画自带的街沿下面
    w = a.shape[1]
    b = int(w * 0.12)
    t = np.linspace(0, 1, b)[None, :, None]
    a[:, w - b:] = a[:, w - b:] * (1 - t) + a[:, :b] * t
    a = a[:, : w - b]
    # 画死在长条里的暖光斑和真实路灯位置对不上（平铺后一眼看出重复）：暖色亮处推回中性灰石色，光由游戏里每盏灯的柔光给
    c = a / 255.0
    lum = c @ np.array([0.299, 0.587, 0.114])
    warm = np.clip((c[..., 0] - c[..., 2]) * 5.0, 0, 1)
    base = np.minimum(lum, 0.2)
    flat = np.dstack([base * 0.98, base, base * 1.03])
    c = c * (1 - warm[..., None] * 0.85) + flat * (warm[..., None] * 0.85)
    a = c * 255.0
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(DST / "street.png")
    print("street", a.shape)


def far() -> None:
    im = Image.open(SRC / "far.png").convert("RGB").resize((2400, 800), Image.LANCZOS)
    a = np.asarray(im).astype(np.float32)
    w = a.shape[1]
    b = int(w * 0.12)
    t = np.linspace(0, 1, b)[None, :, None]
    a[:, w - b:] = a[:, w - b:] * (1 - t) + a[:, :b] * t
    a = a[:, : w - b]
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(DST / "far.png")
    print("far", a.shape)


def fg() -> None:
    rgb = np.asarray(Image.open(SRC / "fg.png").convert("RGB")).astype(np.float32) / 255.0
    out, a = key_green(rgb)
    cols = a.max(0) > 0.5
    parts, x, w = [], 0, len(cols)
    while x < w:
        if cols[x]:
            x0 = x
            while x < w and cols[x]:
                x += 1
            if x - x0 > 24:
                parts.append((x0, x))
        x += 1
    for i, (x0, x1) in enumerate(parts):
        rows = np.where(a[:, x0:x1].max(1) > 0.5)[0]
        y0, y1 = rows.min(), rows.max() + 1
        rgba = np.dstack([out[y0:y1, x0:x1], a[y0:y1, x0:x1]])
        Image.fromarray((np.clip(rgba, 0, 1) * 255).astype(np.uint8), "RGBA").save(DST / f"fg_{i}.png")
        print("fg_%d" % i, x1 - x0, y1 - y0)


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    for c in ["B1", "B2", "B3"]:
        if (SRC / f"{c}.png").exists():
            tile(c)
    if (SRC / "far.png").exists():
        far()
    if (SRC / "street.png").exists():
        street()
    for n in ["behind_a", "behind_b"]:
        if (SRC / f"{n}.png").exists():
            behind(n)
    if (SRC / "fg.png").exists():
        fg()


if __name__ == "__main__":
    main()
