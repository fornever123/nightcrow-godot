"""把即梦成片（v5 / v6）切成游戏用的跑步循环，并导出成修改器能吃的 FrameBaker 包。

做的事：
1. 从 mp4 按 24fps 抽帧，按色彩距离抠掉 #7FA88F 底
2. 每帧按"角色实际高度"缩放到统一高度（v5 和 v6 的角色大小不一样，不统一就一大一小）
3. 按头部中心横向对齐、按脚底对齐竖向落盘 → 原地循环
4. 写 FrameBaker 导入格式（meta{}+frames[]）的 .frames.json，PNG 统一画布
5. 打 ZIP，供 `POST /api/framebaker/import`

用法：
  python tools/art/build_run_from_takes.py --spec v5:8 v6:8 --out DIR
  （v5:8 = 从 v5 取一个 8 帧的循环；可以多个源拼起来）
"""
from __future__ import annotations

import argparse
import json
import sys
import tempfile
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from video_to_run_frames import extract, matte  # noqa: E402

TAKES = {
    "v5": ROOT / "docs" / "视觉设计" / "角色动作" / "跑步重做_20261102" / "即梦_跑步_v5.mp4",
    "v6": ROOT / "docs" / "视觉设计" / "角色动作" / "跑步重做_20261102" / "即梦_跑步_v6.mp4",
    "v4": ROOT / "docs" / "视觉设计" / "角色动作" / "跑步重做_20261102" / "即梦_跑步_v4.mp4",
}
TARGET_FPS = 24.0

# 每个源里，循环最稳的那一段（起点秒数, 周期帧数）。
# v5 / v6 的起点是搜出来的：让 v5→v6 的接缝和 v6→v5 的循环接缝轮廓最接近
# （seam IoU 0.667 / 0.757，比相邻帧平均 0.647 还高）。
WINDOWS = {
    "v5": (1.292, 8),
    "v6": (2.092, 8),
    "v4": (1.15, 12),
}


def body_metrics(img: Image.Image) -> tuple[float, float, float, float]:
    """返回 (头顶y, 脚底y, 头部中心x, 全宽)。"""
    a = np.asarray(img.split()[3]) > 128
    ys, xs = np.nonzero(a)
    top, bottom = float(ys.min()), float(ys.max())
    head_cut = top + (bottom - top) * 0.18
    head_x = float(np.median(xs[ys <= head_cut]))
    return top, bottom, head_x, float(xs.max() - xs.min())


def load_cycle(name: str, frames_wanted: int, tmp: Path) -> list[Image.Image]:
    start_s, period = WINDOWS[name]
    dur = period / TARGET_FPS + 0.05
    work = tmp / name
    work.mkdir(parents=True, exist_ok=True)
    srcs = extract(TAKES[name], TARGET_FPS, start_s, start_s + dur, work)
    got = [matte(Image.open(p).convert("RGBA"), 26, 64) for p in srcs]
    if len(got) < period:
        raise SystemExit(f"{name} 只抽到 {len(got)} 帧，少于周期 {period}")
    got = got[:period]
    if frames_wanted != period:  # 重采样成需要的张数（保持首尾相接）
        idx = [round(i * period / frames_wanted) % period for i in range(frames_wanted)]
        got = [got[i] for i in idx]
    return got


def normalize(frames: list[Image.Image], target_h: float) -> tuple[list[Image.Image], float, float]:
    """统一角色高度 + 头部中心 x + 脚底 y，再按并集外框裁成统一画布。

    返回（帧, 共同原点 x, 共同原点 y）。
    """
    metrics = [body_metrics(f) for f in frames]
    heights = [b - t for t, b, _, _ in metrics]
    scale = target_h / float(np.median(heights))

    # 先放到一块足够大的临时画布（剑往身后伸很长，别裁掉）
    big_w, big_h = int(target_h * 3.0), int(target_h * 2.0)
    ref_head_x, ref_foot_y = int(target_h * 1.2), int(target_h * 1.6)

    # 关键：整条��列只用一套偏移（按中位数），不能逐帧把脚底钉死，
    # 否则跑步的上下起伏会被抹平，看起来像滑行。
    head_xs, foot_ys = [], []
    scaled = []
    for f, (top, bottom, head_x, _) in zip(frames, metrics):
        g = f.resize((round(f.width * scale), round(f.height * scale)), Image.LANCZOS)
        scaled.append(g)
        _, gb, ghx, _ = body_metrics(g)
        head_xs.append(ghx)
        foot_ys.append(gb)
    dx = int(round(ref_head_x - float(np.median(head_xs))))
    dy = int(round(ref_foot_y - float(np.median(foot_ys))))
    staged = []
    for g in scaled:
        cell = Image.new("RGBA", (big_w, big_h), (0, 0, 0, 0))
        cell.alpha_composite(g, (dx, dy))
        staged.append(cell)

    boxes = []
    for im in staged:
        bb = im.split()[3].point(lambda v: 255 if v > 24 else 0).getbbox()
        if bb:
            boxes.append(bb)
    x0 = min(b[0] for b in boxes) - 8
    y0 = min(b[1] for b in boxes) - 8
    x1 = max(b[2] for b in boxes) + 8
    y1 = max(b[3] for b in boxes) + 8
    cropped = [im.crop((x0, y0, x1, y1)) for im in staged]
    return cropped, float(ref_head_x - x0), float(ref_foot_y - y0)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", nargs="+", required=True, help="v5:8 v6:8 —— 源:帧数")
    ap.add_argument("--height", type=float, default=340.0, help="角色统一高度（像素）")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    out = (ROOT / args.out) if not Path(args.out).is_absolute() else Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    frames: list[Image.Image] = []
    with tempfile.TemporaryDirectory(prefix="takes_") as tmp:
        for spec in args.spec:
            name, count = spec.split(":")
            frames += load_cycle(name, int(count), Path(tmp))

    frames, origin_x, origin_y = normalize(frames, args.height)
    cell_w, cell_h = frames[0].size

    names = []
    for i, f in enumerate(frames, 1):
        fn = f"run_merged_{i:03d}.png"
        f.save(out / fn)
        names.append(fn)

    metadata = {
        "meta": {
            "app": "FrameBaker", "format": "sequence", "fps": TARGET_FPS,
            "count": len(frames), "cellWidth": cell_w, "cellHeight": cell_h,
            "originX": origin_x, "originY": origin_y,
            "axisName": "跑步_v5v6_" + "_".join(s.replace(":", "") for s in args.spec),
            "note": "v5/v6 合体，抠像 + 统一高度 + 头部对齐 + 脚底对齐",
        },
        "frames": [
            {"file": fn, "x": 0, "y": 0, "w": cell_w, "h": cell_h, "duration": 1}
            for fn in names
        ],
    }
    (out / "run_merged.frames.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")

    zip_path = out / "run_merged_framebaker.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for fn in names:
            zf.write(out / fn, fn)
        zf.write(out / "run_merged.frames.json", "run_merged.frames.json")

    print(f"{len(frames)} 帧 → {out}")
    print(f"画布 {cell_w}x{cell_h}，共同原点 ({origin_x:.0f}, {origin_y:.0f})")
    print(f"ZIP：{zip_path}")


if __name__ == "__main__":
    main()
