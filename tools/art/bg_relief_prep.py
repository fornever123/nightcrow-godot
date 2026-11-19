#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 立体感试验（11-18）：Codex 出的深度图 / 法线图 → 和站立层原图像素对齐 → 拷进游戏素材目录。

用法：python tools/art/bg_relief_prep.py B1 [B2 ...]
读：docs/_当前分支草稿/背景线/立体感_20261118/codex原图/<代号>_depth.png、<代号>_normal.png
    docs/_当前分支草稿/背景线/第一章升级_20261118/1-1A上下两层街/codex原图/<代号>.png（对齐基准）
写：assets/image/rain_street/ch1_1a_two_level/<代号>_depth.png（灰度，1=近）、<代号>_normal.png（OpenGL 法线）
"""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(r"E:\00game\nightcrow-godot")
SRC = ROOT / "docs" / "_当前分支草稿" / "背景线" / "立体感_20261118" / "codex原图"
BASE = ROOT / "docs" / "_当前分支草稿" / "背景线" / "第一章升级_20261118" / "1-1A上下两层街" / "codex原图"
DST = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level"


def green_mask(a: np.ndarray) -> np.ndarray:
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    return (g > 150) & (r < 120) & (b < 120)


def edges(a: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(a, cv2.COLOR_RGB2GRAY)
    e = cv2.Canny(cv2.GaussianBlur(gray, (5, 5), 0), 40, 110).astype(np.float32)
    return cv2.GaussianBlur(e, (9, 9), 0)


def shift_of(base: np.ndarray, img: np.ndarray) -> tuple[float, float]:
    (dx, dy), resp = cv2.phaseCorrelate(edges(base), edges(img))
    return dx, dy


def prep(code: str) -> None:
    base = np.asarray(Image.open(BASE / f"{code}.png").convert("RGB"))
    h, w = base.shape[:2]
    gbase = green_mask(base)
    for kind in ("depth", "normal"):
        p = SRC / f"{code}_{kind}.png"
        if not p.exists():
            print(code, kind, "缺图")
            continue
        img = np.asarray(Image.open(p).convert("RGB").resize((w, h), Image.LANCZOS))
        # 用绿底轮廓对齐（两张图的绿底应当重合）
        gm = green_mask(img).astype(np.float32)
        (dx, dy), _ = cv2.phaseCorrelate(gbase.astype(np.float32), gm)
        iou_before = (gbase & (gm > 0)).sum() / max(1, (gbase | (gm > 0)).sum())
        M = np.float32([[1, 0, -dx], [0, 1, -dy]])
        img = cv2.warpAffine(img, M, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        gm2 = green_mask(img)
        iou = (gbase & gm2).sum() / max(1, (gbase | gm2).sum())
        hole = gm2 | gbase
        if kind == "depth":
            d = img.astype(np.float32).mean(2) / 255.0
            d[hole] = np.nan
            # 绿底处用邻近值填（灯光采样不会出现黑边）
            v = np.nan_to_num(d, nan=0.0)
            wgt = (~np.isnan(d)).astype(np.float32)
            k = (31, 31)
            fill = cv2.blur(v, k) / np.maximum(cv2.blur(wgt, k), 1e-3)
            d = np.where(np.isnan(d), fill, d)
            lo, hi = np.percentile(d[~hole], [2, 98])
            d = np.clip((d - lo) / max(1e-3, hi - lo), 0, 1)
            Image.fromarray((d * 255).astype(np.uint8), "L").save(DST / f"{code}_depth.png")
            # 3D 浮雕挤出用的“只留大形”版：先中值去掉细栏杆 / 灯杆这类细条，再大半径高斯，
            # 让楼面、步廊、后退的楼有起伏，细节靠原画和法线光，不被挤成糊块
            soft = cv2.medianBlur((d * 255).astype(np.uint8), 21).astype(np.float32) / 255.0
            soft = cv2.GaussianBlur(soft, (0, 0), 9)
            Image.fromarray((soft * 255).astype(np.uint8), "L").save(DST / f"{code}_depth_soft.png")
        else:
            n = img.astype(np.float32) / 255.0 * 2.0 - 1.0
            n[hole] = (0.0, 0.0, 1.0)
            n[..., 2] = np.maximum(n[..., 2], 0.15)
            n /= np.linalg.norm(n, axis=2, keepdims=True)
            Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8), "RGB").save(DST / f"{code}_normal.png")
        print(code, kind, f"位移 ({dx:+.1f},{dy:+.1f})", f"绿底重合 {iou_before:.3f} → {iou:.3f}")


if __name__ == "__main__":
    for c in sys.argv[1:] or ["B1"]:
        prep(c)
