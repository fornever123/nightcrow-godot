#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""拼装「改前 vs 路线1(2D四层大纵深) vs 路线2(3D真HD-2D街道)」实机并排对比图、
整帧明度/对比/饱和/蓝红比/底部17%死黑带量化指标表，以及 3 路同屏走动对比 MP4 视频。
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(r"E:\00game\nightcrow-godot")
BASE = ROOT / "docs" / "_当前分支草稿" / "背景线" / "大纵深重构_20261118"
MODES = [
    ("base", "改前（现游戏 1-1A）"),
    ("r1", "路线1：2D四层断崖大纵深 + 透视湿桥"),
    ("r2", "路线2：Godot 3D子视口 真HD-2D街道"),
]


def load_font(size: int = 24) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for p in [
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
    ]:
        if Path(p).exists():
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def measure_frame(img_path: Path) -> dict:
    arr = np.asarray(Image.open(img_path).convert("RGB"), dtype=np.float32) / 255.0
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    cmax = np.maximum(np.maximum(r, g), b)
    cmin = np.minimum(np.minimum(r, g), b)
    sat = np.where(cmax > 1e-4, (cmax - cmin) / np.maximum(cmax, 1e-4), 0.0)
    h = arr.shape[0]
    bot17 = lum[int(h * 0.83) :, :]
    # 检测违规紫色占比（色相 255..320 且饱和度 > 0.25，不含角色本身小面积）
    mean_r = float(r.mean())
    mean_b = float(b.mean())
    return {
        "lum_mean": round(float(lum.mean()), 3),
        "lum_std": round(float(lum.std()), 3),
        "sat_mean": round(float(sat.mean()), 3),
        "br_ratio": round(mean_b / max(mean_r, 1e-4), 2),
        "bot17_lum": round(float(bot17.mean()), 3),
        "dark08_pct": round(float((lum < 0.08).mean() * 100.0), 1),
    }


def make_comparison_grids() -> dict:
    font = load_font(22)
    font_sm = load_font(17)
    metrics_all: dict = {}

    for x_tag in ["x2800", "x3500", "x4200"]:
        W, H = 960, 540
        # 2x2 网格：左上改前、右上路线1、左下路线2、右下说明+指标卡
        canvas = Image.new("RGB", (W * 2, H * 2), (14, 15, 18))
        d = ImageDraw.Draw(canvas)
        positions = [(0, 0), (W, 0), (0, H)]
        metrics_all[x_tag] = {}

        for (code, label), (ox, oy) in zip(MODES, positions):
            p = BASE / f"实机_{code}" / f"{x_tag}.png"
            if not p.exists():
                continue
            m = measure_frame(p)
            metrics_all[x_tag][code] = m
            im = Image.open(p).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
            canvas.paste(im, (ox, oy))
            d.rectangle([(ox + 10, oy + 10), (ox + W - 10, oy + 72)], fill=(10, 11, 14))
            d.text((ox + 18, oy + 14), label, fill=(245, 245, 248), font=font)
            stat = (
                f"亮度 {m['lum_mean']:.2f} | 对比 {m['lum_std']:.2f} | 饱和 {m['sat_mean']:.2f} | "
                f"蓝红比 {m['br_ratio']:.2f} | 底部17%亮度 {m['bot17_lum']:.3f}"
            )
            d.text((ox + 18, oy + 44), stat, fill=(210, 214, 224), font=font_sm)

        # 右下角汇总指标对比卡
        ox, oy = W, H
        d.rectangle([(ox + 24, oy + 24), (ox + W - 24, oy + H - 24)], fill=(20, 22, 27), outline=(70, 76, 90), width=2)
        d.text((ox + 44, oy + 42), f"量化对比（机位 {x_tag} · 原生 Forward+）", fill=(250, 240, 215), font=font)
        yy = oy + 96
        for code, label in MODES:
            m = metrics_all[x_tag].get(code, {})
            if not m:
                continue
            d.text((ox + 44, yy), label, fill=(235, 238, 245), font=font_sm)
            yy += 28
            d.text(
                (ox + 56, yy),
                f"整帧亮度 {m['lum_mean']:.3f}   对比(std) {m['lum_std']:.3f}   饱和 {m['sat_mean']:.3f}",
                fill=(185, 195, 210),
                font=font_sm,
            )
            yy += 26
            d.text(
                (ox + 56, yy),
                f"蓝红比 B/R {m['br_ratio']:.2f}   底部17%亮度 {m['bot17_lum']:.3f}   暗部<0.08占比 {m['dark08_pct']:.1f}%",
                fill=(185, 195, 210),
                font=font_sm,
            )
            yy += 46
        canvas.save(BASE / f"实机三路并排_{x_tag}.jpg", quality=92)

    (BASE / "metrics.json").write_text(json.dumps(metrics_all, ensure_ascii=False, indent=2), encoding="utf-8")
    return metrics_all


def make_walk_video() -> None:
    font = load_font(22)
    frames_dir = BASE / "walk_side_by_side_frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    W, H = 640, 360
    # 3 路横排 1920x420（顶部 60px 标题条，下方 3 路 640x360 并排，肉眼一眼看穿动起来时的视差/景深/立体感！）
    total = 72
    for fi in range(total):
        canvas = Image.new("RGB", (W * 3, H + 52), (12, 13, 16))
        d = ImageDraw.Draw(canvas)
        ok = True
        for idx, (code, label) in enumerate(MODES):
            fp = BASE / f"实机_{code}" / "walk_frames" / f"f_{fi:03d}.png"
            if not fp.exists():
                ok = False
                break
            im = Image.open(fp).convert("RGB").resize((W, H), Image.Resampling.LANCZOS)
            canvas.paste(im, (idx * W, 52))
            d.text((idx * W + 16, 12), label, fill=(242, 244, 248), font=font)
        if ok:
            canvas.save(frames_dir / f"sbs_{fi:03d}.png")

    out_mp4 = BASE / "实机三路并排走动对比.mp4"
    cmd = [
        "ffmpeg", "-y", "-framerate", "24",
        "-i", str(frames_dir / "sbs_%03d.png"),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
        str(out_mp4),
    ]
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("WALK_VIDEO_SAVED:", out_mp4)


def main() -> None:
    metrics = make_comparison_grids()
    make_walk_video()
    print("REPORT_DONE:", json.dumps(metrics.get("x3500", {}), ensure_ascii=False))


if __name__ == "__main__":
    main()
