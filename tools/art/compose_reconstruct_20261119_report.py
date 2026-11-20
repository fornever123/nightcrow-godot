#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 2026-11-19 背景重构档的：
1. 改前（D2三层_20261119/默认_全段） vs 改后（重构档_20261119/实机_改后）同机位高清并排图
2. 半屏缩小并排图（检验缩到半屏是否一眼看出明显提升）
3. 全套量化指标（亮度均值/标准差、<0.06死黑占比、B/R偏蓝比、底部17%亮度、每行细节密度最高/中位比、上下亮度梯度）
"""
from __future__ import annotations

import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(r"E:\00game\nightcrow-godot")
OLD_DIR = ROOT / "docs" / "_当前分支草稿" / "背景线" / "D2三层_20261119" / "默认_全段"
NEW_DIR = ROOT / "docs" / "_当前分支草稿" / "背景线" / "重构档_20261119" / "实机_改后"
OUT_DIR = ROOT / "docs" / "_当前分支草稿" / "背景线" / "重构档_20261119"


def load_font(size: int = 20):
    for p in [r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def measure(img_path: Path) -> dict:
    arr = np.asarray(Image.open(img_path).convert("RGB"), dtype=np.float32) / 255.0
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    h = arr.shape[0]
    gx = np.abs(np.diff(lum, axis=1, prepend=lum[:, :1]))
    gy = np.abs(np.diff(lum, axis=0, prepend=lum[:1, :]))
    grad = gx + gy
    row_d = grad[int(h * 0.08) : int(h * 0.85)].mean(axis=1)
    detail_ratio = float(np.percentile(row_d, 98) / max(np.median(row_d), 1e-5))
    lum_top = float(lum[: int(h * 0.38)].mean())
    lum_mid = float(lum[int(h * 0.48) : int(h * 0.82)].mean())
    bot17 = float(lum[int(h * 0.83) :].mean())
    return {
        "lum_mean": round(float(lum.mean()), 3),
        "lum_std": round(float(lum.std()), 3),
        "dead06_pct": round(float((lum < 0.06).mean() * 100.0), 1),
        "br_ratio": round(float(b.mean() / max(r.mean(), 1e-4)), 2),
        "bot17_lum": round(bot17, 3),
        "detail_ratio": round(detail_ratio, 2),
        "lum_top": round(lum_top, 3),
        "lum_mid": round(lum_mid, 3),
    }


def main() -> None:
    font = load_font(20)
    font_sm = load_font(15)
    spots = ["x02300", "x03300", "x06500", "x07500"]
    report: dict = {}

    # 1. 三组高清并排（2560 x 720*3）
    W, H = 1280, 720
    big = Image.new("RGB", (W * 2, H * len(spots)), (12, 13, 16))
    db = ImageDraw.Draw(big)

    # 2. 半屏缩小并排（640*2 x 360*len）
    WS, HS = 640, 360
    small = Image.new("RGB", (WS * 2, HS * len(spots)), (12, 13, 16))
    ds = ImageDraw.Draw(small)

    for idx, sp in enumerate(spots):
        p_old = OLD_DIR / f"{sp}.png"
        p_new = NEW_DIR / f"{sp}.png"
        if not (p_old.exists() and p_new.exists()):
            continue
        mo = measure(p_old)
        mn = measure(p_new)
        report[sp] = {"old": mo, "new": mn}

        im_o = Image.open(p_old).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
        im_n = Image.open(p_new).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
        big.paste(im_o, (0, idx * H))
        big.paste(im_n, (W, idx * H))
        for col, (tag, m) in enumerate([("改前（D2 默认）", mo), ("改后（重构档）", mn)]):
            ox, oy = col * W, idx * H
            db.rectangle([(ox + 8, oy + 8), (ox + W - 8, oy + 62)], fill=(10, 11, 14))
            db.text((ox + 16, oy + 11), f"{sp} · {tag}", fill=(248, 245, 236), font=font)
            stat = (
                f"亮度 {m['lum_mean']:.3f} | 对比 {m['lum_std']:.3f} | 死黑<0.06 {m['dead06_pct']:.1f}% | "
                f"B/R {m['br_ratio']:.2f} | 底17% {m['bot17_lum']:.3f} | 细节比 {m['detail_ratio']:.2f} | 上/下 {m['lum_top']:.2f}/{m['lum_mid']:.2f}"
            )
            db.text((ox + 16, oy + 38), stat, fill=(210, 215, 224), font=font_sm)

        small.paste(im_o.resize((WS, HS), Image.Resampling.LANCZOS), (0, idx * HS))
        small.paste(im_n.resize((WS, HS), Image.Resampling.LANCZOS), (WS, idx * HS))
        ds.rectangle([(6, idx * HS + 6), (260, idx * HS + 32)], fill=(10, 11, 14))
        ds.text((12, idx * HS + 9), f"{sp} 改前（D2 默认）", fill=(240, 240, 245), font=font_sm)
        ds.rectangle([(WS + 6, idx * HS + 6), (WS + 260, idx * HS + 32)], fill=(10, 11, 14))
        ds.text((WS + 12, idx * HS + 9), f"{sp} 改后（重构档）", fill=(245, 232, 195), font=font_sm)

    big.save(OUT_DIR / "改前改后_全段高清并排.jpg", quality=92)
    small.save(OUT_DIR / "改前改后_半屏缩小并排.jpg", quality=92)
    (OUT_DIR / "metrics.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("RECONSTRUCT_REPORT_DONE:", json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
