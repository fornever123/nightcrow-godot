"""从 v4 成片里切出一个循环（12 帧 @24fps = 0.5 秒），抠像、对齐、落盘，并做循环预览。

- 用轮廓自相似找出最稳的起点（见 docs 里的周期测量：k=12 帧时平均 IoU 最高）
- 每帧按头部中心横向对齐 → 原地跑
- 输出 RGBA 帧 + frames.json（pivot）+ 检查条图 + 3 圈循环预览 mp4（深色底）

用法：python tools/art/make_run_loop_v4.py
"""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from video_to_run_frames import align_horizontal, matte, union_bbox, extract  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
VIDEO = ROOT / "docs" / "视觉设计" / "角色动作" / "跑步重做_20261102" / "即梦_跑步_v4.mp4"
OUT = ROOT / "docs" / "视觉设计" / "角色动作" / "跑步重做_20261102" / "v4_frames"
FPS = 24.0
PERIOD = 12          # 帧；24fps 下 0.5 秒一个循环
SCAN_START, SCAN_END = 0.4, 3.3


def masks_of(frames):
    return [np.asarray(f.split()[3]) > 128 for f in frames]


def find_window(frames) -> int:
    m = masks_of(frames)
    n = len(m)
    best, best_score = 0, -1.0
    for start in range(10, n - PERIOD - 1):
        score = 0.0
        for j in range(start, start + PERIOD):
            a, b = m[j], m[j + PERIOD] if j + PERIOD < n else m[j]
            inter, uni = (a & b).sum(), (a | b).sum()
            score += inter / uni if uni else 0
        score /= PERIOD
        if score > best_score:
            best, best_score = start, score
    print(f"最稳起点：第 {best} 帧，与该循环下一遍的平均 IoU {best_score:.3f}")
    return best


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="v4loop_") as tmp:
        srcs = extract(VIDEO, FPS, SCAN_START, SCAN_END, Path(tmp))
        allmat = [matte(Image.open(p).convert("RGBA"), 26, 64) for p in srcs]
        start = find_window(allmat)
        loop = allmat[start:start + PERIOD]

        bx0, by0, bx1, by1 = union_bbox(loop)
        rough = [im.crop((bx0, by0, bx1, by1)) for im in loop]
        aligned, base_x = align_horizontal(rough)
        x0, y0, x1, y1 = union_bbox(aligned)
        pad = 6
        x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
        x1, y1 = min(aligned[0].width, x1 + pad), min(aligned[0].height, y1 + pad)
        cropped = [im.crop((x0, y0, x1, y1)) for im in aligned]
        pivot_x, pivot_y = float(base_x - x0), float(y1 - y0)

        (OUT / "frames").mkdir(parents=True, exist_ok=True)
        meta = []
        for i, im in enumerate(cropped, 1):
            name = f"frame_{i:04d}.png"
            im.save(OUT / "frames" / name)
            meta.append({"asset": name, "width": im.width, "height": im.height,
                         "pivotX": round(pivot_x, 2), "pivotY": round(pivot_y, 2),
                         "durationTicks": 1, "sourceFrame": start + i - 1})
        (OUT / "frames.json").write_text(json.dumps(
            {"fps": FPS, "periodFrames": PERIOD, "video": str(VIDEO.name),
             "crop": [x0, y0, x1, y1], "frames": meta},
            ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"{len(cropped)} 帧 → {OUT / 'frames'}，裁剪 {x1 - x0}x{y1 - y0}，pivot=({pivot_x:.0f},{pivot_y:.0f})")

        # 3 圈循环预览（深色底，方便看节奏和脚底）
        prev = Path(tmp) / "prev"
        prev.mkdir()
        bg = (27, 28, 34, 255)
        idx = 0
        for _ in range(3):
            for im in cropped:
                canvas = Image.new("RGBA", (im.width + 40, im.height + 40), bg)
                canvas.alpha_composite(im, (20, 26))
                canvas.convert("RGB").save(prev / f"p_{idx:03d}.png")
                idx += 1
        out_mp4 = OUT / "v4_循环预览_3圈.mp4"
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-framerate", "24", "-i", str(prev / "p_%03d.png"),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", str(out_mp4),
        ], check=False)
        print(f"循环预览：{out_mp4}")


if __name__ == "__main__":
    main()
