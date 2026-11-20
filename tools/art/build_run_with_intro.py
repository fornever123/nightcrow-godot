"""给跑步加起跑过渡：从 v6 的起跑段取几帧放在循环前面，循环靠 loopFrame 接上。

为什么要这么做：游戏里 idle→run 是直接切剪辑的，character_view 每次切到 run 都会把
clock 归零、从第 0 帧播。所以只要把「起跑过渡」放在剪辑最前面、把 loopFrame 设成过渡帧数，
就会自然地「先起跑一次、之后循环」，不用改战斗线的代码。

用法：python tools/art/build_run_with_intro.py --intro-count 6 --fps 30
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
from video_to_run_frames import extract, matte, union_bbox  # noqa: E402
from build_run_from_takes import TAKES, WINDOWS, body_metrics, normalize  # noqa: E402

FPS_SRC = 24.0
TARGET_H = 340.0
INTRO_WINDOW = (0.55, 1.75)   # v6 里「起跑加速」这一段（秒）


def load_loop(tmp: Path) -> list[Image.Image]:
    out = []
    for name, count in (("v5", 8), ("v6", 8)):
        start_s, period = WINDOWS[name]
        work = tmp / f"loop_{name}"
        work.mkdir(parents=True, exist_ok=True)
        srcs = extract(TAKES[name], FPS_SRC, start_s, start_s + period / FPS_SRC + 0.05, work)
        out += [matte(Image.open(p).convert("RGBA"), 26, 64) for p in srcs][:period]
    return out


def load_intro(tmp: Path) -> list[Image.Image]:
    work = tmp / "intro"
    work.mkdir(parents=True, exist_ok=True)
    srcs = extract(TAKES["v6"], FPS_SRC, INTRO_WINDOW[0], INTRO_WINDOW[1], work)
    return [matte(Image.open(p).convert("RGBA"), 26, 64) for p in srcs]


def mask(img: Image.Image) -> np.ndarray:
    return np.asarray(img.split()[3]) > 128


def iou(a: np.ndarray, b: np.ndarray) -> float:
    u = (a | b).sum()
    return float((a & b).sum() / u) if u else 0.0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--intro-count", type=int, default=6)
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--out", default=".runtime/action-audit/run_with_intro")
    args = ap.parse_args()

    out_dir = ROOT / args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="intro_") as tmp:
        tmp_path = Path(tmp)
        loop = load_loop(tmp_path)
        intro_raw = load_intro(tmp_path)
        # 先按循环那套统一缩放/偏移处理全部帧，保证高度、脚底一致
        frames_all, origin_x, origin_y = normalize(loop + intro_raw, TARGET_H)
        loop_frames = frames_all[:len(loop)]
        intro_frames = frames_all[len(loop):]

        # 找起跑段里和循环第 0 帧最像的那一帧，作为过渡的终点
        m_loop0 = mask(loop_frames[0])
        scores = [iou(mask(f), m_loop0) for f in intro_frames]
        end = int(np.argmax(scores))
        start = max(0, end - args.intro_count + 1)
        picked = intro_frames[start:end + 1]
        print(f"起跑段 {len(intro_frames)} 帧，挑第 {start}–{end} 帧（终点与循环首帧 IoU {scores[end]:.3f}）")

        frames = picked + loop_frames
        loop_frame = len(picked)
        cell_w, cell_h = frames[0].size

    names = []
    for i, f in enumerate(frames, 1):
        fn = f"run_intro_{i:03d}.png"
        f.save(out_dir / fn)
        names.append(fn)

    meta = {
        "meta": {
            "app": "FrameBaker", "format": "sequence", "fps": args.fps,
            "count": len(frames), "cellWidth": cell_w, "cellHeight": cell_h,
            "originX": origin_x, "originY": origin_y,
            "axisName": f"跑步_起跑过渡{loop_frame}帧_再加循环",
            "note": f"前 {loop_frame} 帧是起跑过渡，loopFrame={loop_frame}；后面 {len(loop_frames)} 帧是 v5+v6 合体循环",
        },
        "frames": [{"file": n, "x": 0, "y": 0, "w": cell_w, "h": cell_h, "duration": 1} for n in names],
    }
    (out_dir / "run_intro.frames.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2),
                                                   encoding="utf-8")
    zip_path = out_dir / "run_intro_framebaker.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for n in names:
            zf.write(out_dir / n, n)
        zf.write(out_dir / "run_intro.frames.json", "run_intro.frames.json")

    print(f"{len(frames)} 帧（过渡 {loop_frame} + 循环 {len(frames) - loop_frame}）→ {out_dir}")
    print(f"画布 {cell_w}x{cell_h}，原点 ({origin_x:.0f}, {origin_y:.0f})，loopFrame={loop_frame}")
    print(f"ZIP：{zip_path}")


if __name__ == "__main__":
    main()
