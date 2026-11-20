"""即梦视频 → 游戏用帧：切段、抽帧、抠掉纯色底、统一裁剪、算 pivot、拼检查图。

流程
1. ffmpeg 按目标帧率从 mp4 抽 PNG（只抽 [t0, t1] 这一段）
2. 每帧按"到背景色的距离"做 alpha（背景 #7FA88F，越远越实），边缘羽化 2px，
   再用 3×3 邻域把孤立噪点清掉
3. 所有帧用同一个并集外框裁剪（保证帧间不位移），留 pad
4. pivotX = 每帧"最下面 12% 身体条带"的水平中位（落地点），pivotY = 并集外框底边
5. 输出 frames/*.png（RGBA）+ frames.json（name/width/height/pivotX/pivotY）+ 检查条图

用法：
  python tools/art/video_to_run_frames.py --video X.mp4 --out DIR --fps 24 --start 1.2 --end 3.2
  预览不写盘：加 --dry
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
BG = np.array([0x7F, 0xA8, 0x8F], dtype=np.float32)
FFMPEG = "ffmpeg"


def extract(video: Path, fps: float, start: float, end: float, work: Path) -> list[Path]:
    dur = max(0.05, end - start)
    out = work / "src_%04d.png"
    cmd = [
        FFMPEG, "-hide_banner", "-loglevel", "error", "-y",
        "-ss", f"{start:.3f}", "-t", f"{dur:.3f}", "-i", str(video),
        "-vf", f"fps={fps}", str(out),
    ]
    subprocess.run(cmd, check=True)
    files = sorted(work.glob("src_*.png"))
    if not files:
        raise SystemExit(f"没抽到帧：{video} [{start}-{end}]")
    return files


def matte(img: Image.Image, t0: float, t1: float, feather: int = 2) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    dist = np.sqrt(((a - BG) ** 2).sum(axis=2))
    alpha = np.clip((dist - t0) / max(1e-3, t1 - t0), 0.0, 1.0)
    # 3×3 邻域：邻域里实心像素不足 2 个的当噪点清掉
    pad = np.pad(alpha, 1, mode="edge")
    neigh = sum(
        pad[1 + dy:1 + dy + alpha.shape[0], 1 + dx:1 + dx + alpha.shape[1]]
        for dy in (-1, 0, 1) for dx in (-1, 0, 1)
    )
    alpha = np.where(neigh < 2.0, 0.0, alpha)
    if feather > 0:
        from PIL import ImageFilter
        m = Image.fromarray((alpha * 255).astype(np.uint8), "L")
        m = m.filter(ImageFilter.GaussianBlur(feather * 0.5))
        alpha = np.asarray(m).astype(np.float32) / 255.0
    rgba = np.dstack([a, alpha * 255.0]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def union_bbox(imgs: list[Image.Image], thresh: int = 24) -> tuple[int, int, int, int]:
    boxes = []
    for im in imgs:
        al = im.split()[3].point(lambda v: 255 if v > thresh else 0)
        bb = al.getbbox()
        if bb:
            boxes.append(bb)
    if not boxes:
        raise SystemExit("所有帧都是空的，抠像参数不对")
    return (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))


def head_center(img: Image.Image, band: float = 0.18) -> float:
    """头部中心 x：取角色最上面 band 高度的身体（头发那块），不受剑和腿影响。

    用来把每帧横向对齐成"原地跑"；脚底那条带子会被悬下来的剑尖污染，不能用。
    """
    a = np.asarray(img.split()[3]).astype(np.float32) / 255.0
    ys, xs = np.nonzero(a > 0.5)
    if len(ys) == 0:
        return img.width / 2
    y0, y1 = ys.min(), ys.max()
    cut = y0 + (y1 - y0) * band
    sel = xs[ys <= cut]
    return float(np.median(sel)) if len(sel) else float(np.median(xs))


def align_horizontal(frames: list[Image.Image]) -> tuple[list[Image.Image], float]:
    """按头部中心把每帧横向挪回去，得到原地循环。返回（对齐后的帧, 基准 x）。"""
    centers = [head_center(f) for f in frames]
    target = float(np.median(centers))
    out = []
    for f, cx in zip(frames, centers):
        dx = int(round(target - cx))
        if dx == 0:
            out.append(f)
            continue
        canvas = Image.new("RGBA", f.size, (0, 0, 0, 0))
        canvas.alpha_composite(f, (dx, 0))
        out.append(canvas)
    return out, target


def strip(frames: list[Image.Image], out: Path, pivot_xs: list[float], pivot_y: float,
          scale: float = 1.0) -> None:
    if abs(scale - 1.0) > 1e-6:
        frames = [f.resize((max(1, round(f.width * scale)), max(1, round(f.height * scale))),
                           Image.LANCZOS) for f in frames]
        pivot_xs = [p * scale for p in pivot_xs]
        pivot_y *= scale
    pad, lh = 8, 36
    w = max(f.width for f in frames)
    h = max(f.height for f in frames)
    sheet = Image.new("RGBA", ((w + pad) * len(frames), h + lh + pad), (26, 26, 32, 255))
    dr = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/consolea.ttf", 14)
    except OSError:
        font = ImageFont.load_default()
    for i, im in enumerate(frames):
        x = i * (w + pad)
        sheet.alpha_composite(im, (x + (w - im.width) // 2, lh))
        dr.text((x + 3, 2), f"#{i + 1} pivot={pivot_xs[i]:.0f}", font=font, fill=(150, 220, 255, 255))
        dr.line([(x + (w - im.width) // 2 + pivot_xs[i], lh), (x + (w - im.width) // 2 + pivot_xs[i],
                 lh + h)], fill=(190, 130, 255, 90))
        dr.line([(x, 0), (x, h + lh)], fill=(70, 70, 84, 255))
    sheet.save(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--fps", type=float, default=24.0)
    ap.add_argument("--start", type=float, default=0.0)
    ap.add_argument("--end", type=float, default=None)
    ap.add_argument("--t0", type=float, default=26.0, help="小于这个色彩距离算背景")
    ap.add_argument("--t1", type=float, default=64.0, help="大于这个色彩距离算实心")
    ap.add_argument("--pad", type=int, default=6)
    ap.add_argument("--keep-drift", action="store_true",
                    help="不做原地对齐（默认会按头部中心把横移消掉）")
    ap.add_argument("--dry", action="store_true", help="只在临时目录跑一遍，看检查图")
    ap.add_argument("--strip-scale", type=float, default=1.0, help="检查条图的缩放，长条太宽时调小")
    args = ap.parse_args()

    video = Path(args.video)
    if not video.is_absolute():
        video = ROOT / video
    end = args.end if args.end is not None else args.start + 2.0
    out_dir = (ROOT / args.out) if not args.dry else Path(tempfile.mkdtemp(prefix="runframes_"))

    with tempfile.TemporaryDirectory(prefix="v2f_") as tmp:
        srcs = extract(video, args.fps, args.start, end, Path(tmp))
        raw = [Image.open(p).convert("RGBA") for p in srcs]
        matted = [matte(im, args.t0, args.t1) for im in raw]
        # 先粗裁到并集外框，再按头部中心对齐成原地跑，最后按对齐后的并集重新裁一次
        bx0, by0, bx1, by1 = union_bbox(matted)
        rough = [im.crop((bx0, by0, bx1, by1)) for im in matted]
        if args.keep_drift:
            aligned, base_x = rough, bx0
        else:
            aligned, base_x = align_horizontal(rough)
        x0, y0, x1, y1 = union_bbox(aligned)
        x0 = max(0, x0 - args.pad); y0 = max(0, y0 - args.pad)
        x1 = min(aligned[0].width, x1 + args.pad); y1 = min(aligned[0].height, y1 + args.pad)
        cropped = [im.crop((x0, y0, x1, y1)) for im in aligned]
        pivot_x = float(base_x - x0)
        pivot_y = float(y1 - y0)

        if args.dry:
            p = Path(out_dir) / "check_strip.png"
            strip(cropped, p, [pivot_x] * len(cropped), pivot_y, args.strip_scale)
            cov = np.mean([np.asarray(im.split()[3]).mean() / 255 for im in cropped])
            print(f"[dry] {len(cropped)} 帧，裁剪 {x1 - x0}x{y1 - y0}，pivot=({pivot_x:.0f},{pivot_y:.0f})，"
                  f"平均不透明覆盖 {cov:.1%}")
            print(f"[dry] 检查图：{p}")
            return

        (out_dir / "frames").mkdir(parents=True, exist_ok=True)
        meta = []
        for i, im in enumerate(cropped, 1):
            name = f"frame_{i:04d}.png"
            im.save(out_dir / "frames" / name)
            meta.append({
                "asset": name,
                "width": im.width,
                "height": im.height,
                "pivotX": round(pivot_x, 2),
                "pivotY": round(pivot_y, 2),
                "durationTicks": 1,
                "sourceFrame": i - 1,
            })
        (out_dir / "frames.json").write_text(
            json.dumps({"fps": args.fps, "crop": [x0, y0, x1, y1], "frames": meta},
                       ensure_ascii=False, indent=2), encoding="utf-8")
        strip(cropped, out_dir / "check_strip.png", [pivot_x] * len(cropped), pivot_y, args.strip_scale)
        print(f"{len(cropped)} 帧 → {out_dir / 'frames'}，裁剪 {x1 - x0}x{y1 - y0}")
        print(f"检查图：{out_dir / 'check_strip.png'}")


if __name__ == "__main__":
    sys.exit(main())

