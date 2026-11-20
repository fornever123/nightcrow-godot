"""量一下几张站立候选帧的实际画质：锐度（Laplacian 方差）、有效像素密度、边缘半透明比例。

只读。
输出：控制台 + .runtime/action-audit/stand_quality.csv

用法：python tools/art/stand_quality.py
"""
from __future__ import annotations

import csv
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / ".runtime" / "action-audit"

CANDIDATES = [
    ("in-game idle", "assets/image/desktop-actions/待机/frame_00001.png"),
    ("ai-hd idle 001", "assets/image/ai-hd-20261020/idle/pose_001.png"),
    ("ai-hd idle 002", "assets/image/ai-hd-20261020/idle/pose_002.png"),
    ("原片 idle", "assets/image/characters/nightcrow/idle/frame_0001.png"),
    ("cleaned idle", "assets/image/cleaned/nightcrow/idle/frame_0001.png"),
    ("selected 00014", "assets/image/selected-original/mmh3_action_00014/character/frame_00001.png"),
    ("run first frame", "assets/image/desktop-actions/跑步/frame_00001.png"),
]


def metrics(path: Path) -> dict:
    img = Image.open(path).convert("RGBA")
    a = np.asarray(img).astype(np.float32)
    alpha = a[..., 3] / 255.0
    lum = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) * alpha
    body = alpha > 0.9
    if body.sum() < 100:
        return {}
    ys, xs = np.nonzero(body)
    h = ys.max() - ys.min() + 1
    l = lum[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    # Laplacian 方差，按角色高度归一化（缩放到 400px 高再算，便于横比）
    crop = Image.fromarray(np.clip(l, 0, 255).astype(np.uint8))
    scale = 400.0 / crop.height
    crop = crop.resize((max(1, round(crop.width * scale)), 400), Image.LANCZOS)
    g = np.asarray(crop).astype(np.float32)
    lap = (4 * g[1:-1, 1:-1] - g[:-2, 1:-1] - g[2:, 1:-1] - g[1:-1, :-2] - g[1:-1, 2:])
    semi = float(((alpha > 0.05) & (alpha < 0.95)).sum()) / max(1, int((alpha > 0.05).sum()))
    return {
        "w": img.width,
        "h": img.height,
        "char_h": int(h),
        "sharp": round(float(lap.var()), 1),
        "semi_alpha": round(semi, 4),
        "bytes_per_1k_px": round(path.stat().st_size / (img.width * img.height) * 1000, 1),
    }


def main() -> None:
    rows = []
    for label, rel in CANDIDATES:
        p = ROOT / rel
        m = metrics(p)
        rows.append({"name": label, **m, "path": rel})
    rows.sort(key=lambda r: r.get("sharp", 0), reverse=True)
    OUT.mkdir(parents=True, exist_ok=True)
    with (OUT / "stand_quality.csv").open("w", encoding="utf-8-sig", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"{'name':16} {'尺寸':>11} {'角色高':>7} {'锐度':>10} {'半透明边':>9} {'B/千像素':>9}")
    for r in rows:
        print(f"{r['name']:16} {r['w']:>5}x{r['h']:<5} {r['char_h']:>7} {r['sharp']:>10} "
              f"{r['semi_alpha']:>9} {r['bytes_per_1k_px']:>9}")


if __name__ == "__main__":
    main()
