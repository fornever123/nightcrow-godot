#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线 · 站立层明暗规划（11-19 重构档返工）。

反重力版把 B1～B3、C1 的上半截整片压黑（窗全灭、楼没了形），整帧更暗更平。
这里改成：以用户认可过的 D2 图为底（C1 用旧图调到 D2 色调），上半截只做三件事——
  1. 细节减半（高频乘 0.5，楼的形和屋檐线都还在，能跳上去的屋顶仍看得清）；
  2. 整体压一档（约 ×0.72）并往夜雾色靠一点；
  3. 每张图上半截只留最亮的 1～2 扇暖窗，其余窗熄灯——主次靠"少数亮窗 + 人走那层最亮"。
人走的那一层（街面到二层步廊）原样不动。

用法：python tools/art/bg_value_plan.py
产物：assets/image/rain_street/ch1_1a_d2/{B1,B2,B3,C1}.png，检查图在 docs/_当前分支草稿/背景线/重构档_20261119/返工/
"""
from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(r"E:\00game\nightcrow-godot")
D2_BASE = ROOT / "docs" / "_当前分支草稿" / "背景线" / "重构档_20261119" / "改前备份"   # 用户认可过的 D2 站立层
OLD = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level"
DST = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_d2"
CHK = ROOT / "docs" / "_当前分支草稿" / "背景线" / "重构档_20261119" / "返工"

TOP_FULL = 0.40      # 这条线以上全量处理（占图高）
TOP_NONE = 0.60      # 这条线以下原样（二层步廊以下）
DETAIL_KEEP = 0.22   # 上半截高频保留多少
DARK = 0.6          # 上半截压暗系数
FOG = np.array([0.15, 0.16, 0.19])
FOG_MIX = 0.10
KEEP_WINDOWS = 2     # 上半截留几扇亮窗


def load(p: Path) -> tuple[np.ndarray, np.ndarray]:
    a = np.asarray(Image.open(p).convert("RGBA")).astype(np.float32) / 255.0
    return a[..., :3].copy(), a[..., 3].copy()


def match_color(src: np.ndarray, sa: np.ndarray, ref: np.ndarray, ra: np.ndarray, k: float = 0.85) -> np.ndarray:
    """旧图（偏蓝偏亮）按 D2 图的每通道均值 / 标准差对齐。"""
    ms, mr = sa > 0.5, ra > 0.5
    out = src.copy()
    for c in range(3):
        s, r = src[..., c][ms], ref[..., c][mr]
        t = (src[..., c] - s.mean()) / max(s.std(), 1e-4) * r.std() + r.mean()
        out[..., c] = src[..., c] * (1 - k) + t * k
    return np.clip(out, 0, 1)


def value_plan(rgb: np.ndarray, a: np.ndarray, code: str) -> np.ndarray:
    h, w = a.shape
    yy = np.arange(h, dtype=np.float32)[:, None] / h
    k = np.clip((TOP_NONE - yy) / (TOP_NONE - TOP_FULL), 0, 1)
    k = (k * k * (3 - 2 * k))[..., None]                      # 1 = 上半截，0 = 人走的那层

    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    warm = (lum > 0.36) & ((rgb[..., 0] - rgb[..., 2]) > 0.10) & (a > 0.5)
    # 上半截的亮窗：连通块按 面积 × 亮度 排序，留前 KEEP_WINDOWS 个
    lab, n = ndimage.label(ndimage.binary_dilation(warm, iterations=3))
    keep = np.zeros_like(warm)
    if n:
        idx = np.arange(1, n + 1)
        area = ndimage.sum(warm, lab, idx)
        cy = np.array([c[0] for c in ndimage.center_of_mass(warm, lab, idx)])
        bright = ndimage.mean(lum, lab, idx)
        upper = [(area[i] * bright[i], i + 1) for i in range(n) if area[i] > 60 and cy[i] < TOP_NONE * h * 0.95]
        upper.sort(reverse=True)
        for _, lid in upper[:KEEP_WINDOWS]:
            keep |= lab == lid
    keep_soft = cv2.GaussianBlur(ndimage.binary_dilation(keep, iterations=6).astype(np.float32), (0, 0), 4)[..., None]
    win_soft = cv2.GaussianBlur(ndimage.binary_dilation(warm, iterations=4).astype(np.float32), (0, 0), 3)[..., None]

    low = cv2.GaussianBlur(rgb, (0, 0), 2.2)
    det = rgb - low
    up = low + det * DETAIL_KEEP
    # 熄灯：上半截没被选中的暖窗，往周围墙色收（不是涂黑，窗格还在）
    wall = cv2.GaussianBlur(rgb, (0, 0), 9)
    off = win_soft * (1 - keep_soft)
    up = up * (1 - off) + (wall * 0.55 + up * 0.15) * off
    up = up * DARK
    up = up * (1 - FOG_MIX) + FOG * FOG_MIX
    up = up * (1 - keep_soft) + rgb * keep_soft                  # 留下的亮窗原样
    out = rgb * (1 - k) + up * k
    print(code, "上半截暖窗 %d 个，留 %d 个" % (n, min(KEEP_WINDOWS, len(upper) if n else 0)))
    return np.clip(out, 0, 1)


def save(code: str, rgb: np.ndarray, a: np.ndarray) -> None:
    Image.fromarray((np.dstack([rgb, a]) * 255).astype(np.uint8), "RGBA").save(DST / f"{code}.png")


def main() -> None:
    CHK.mkdir(parents=True, exist_ok=True)
    ref_rgb, ref_a = load(D2_BASE / "B3.png")
    sheet = []
    for code in ["B1", "B2", "B3", "C1"]:
        if code == "C1":
            rgb, a = load(OLD / "C1.png")
            rgb = match_color(rgb, a, ref_rgb, ref_a)
        else:
            rgb, a = load(D2_BASE / f"{code}.png")
        before = rgb.copy()
        out = value_plan(rgb, a, code)
        save(code, out, a)
        g = np.zeros((a.shape[0], a.shape[1] * 2, 3), np.float32) + np.array([0, 0.45, 0])
        g[:, : a.shape[1]] = before * a[..., None] + g[:, : a.shape[1]] * (1 - a[..., None])
        g[:, a.shape[1]:] = out * a[..., None] + g[:, a.shape[1]:] * (1 - a[..., None])
        sheet.append(cv2.resize(g, (1672, 470)))
    Image.fromarray((np.clip(np.vstack(sheet), 0, 1) * 255).astype(np.uint8)).save(CHK / "站立层_改前改后.jpg", quality=88)


if __name__ == "__main__":
    main()
