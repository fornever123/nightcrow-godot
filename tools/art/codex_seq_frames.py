"""Codex 序列帧表 → 游戏帧（角色动作线，11-06）。

绿底抠像（key_green.py）→ 按网格切格 → 统一缩放到跑步循环的身高 → 脚底钉在 pivotY、
头部中心按“起始朝左 / 结束朝右”从镜像偏移插值到原偏移 → 出 PNG + 帧条图 + 预览动图。
只写输出目录，不碰 battle.json。

用法：python tools/art/codex_seq_frames.py 原图.png 输出目录 --cols 3 --rows 2
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from key_green import key  # noqa: E402

RUN_DIR = ROOT / "assets/image/imports/framebaker/87da3608-35f3-4485-b16e-13e95071f7b2"
RUN_CANVAS = (520, 409)
RUN_PIVOT = (416, 397)  # run 帧的 pivot（battle.json）
CANVAS = (840, 430)     # 转身帧画布：剑朝两边都能伸出去
PIVOT = (420, 418)
DISPLAY = 0.41075794621026895  # battle.json sprite.displayScale


def bbox(a: np.ndarray, thr: int = 60):
    ys, xs = np.nonzero(a > thr)
    return xs.min(), ys.min(), xs.max(), ys.max()


def head_x(a: np.ndarray) -> float:
    """头部中心：角色最上面 22% 高度里不透明像素的横向重心（剑在腰部，不会被算进来）。"""
    x0, y0, x1, y1 = bbox(a)
    band = a[y0:y0 + int((y1 - y0) * 0.22)] > 60
    xs = np.nonzero(band)[1]
    return float(xs.mean())


def run_ref():
    im = Image.open(RUN_DIR / "run_intro_007.png").convert("RGBA")
    a = np.asarray(im)[..., 3]
    x0, y0, x1, y1 = bbox(a)
    return im, y1 - y0, head_x(a) - RUN_PIVOT[0]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--rows", type=int, default=2)
    ap.add_argument("--fps", type=float, default=25.2)  # 转向 fps 18 × playbackSpeed 1.4
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    keyed = out / "keyed.png"
    key(args.src, str(keyed))
    sheet = Image.open(keyed).convert("RGBA")
    W, H = sheet.size
    cw, ch = W // args.cols, H // args.rows
    # 按连通块切人：剑尖可能越过格线，所以每个连通块整块归给它重心所在的那一格
    from scipy import ndimage
    sa = np.asarray(sheet)
    lab, nlab = ndimage.label(ndimage.binary_dilation(sa[..., 3] > 30, iterations=2))
    owner = np.zeros(nlab + 1, int) - 1
    for k, sl in enumerate(ndimage.find_objects(lab), start=1):
        m = lab[sl] == k
        if m.sum() < 40:
            continue  # 零星噪点
        cy, cx = ndimage.center_of_mass(m)
        owner[k] = int((sl[0].start + cy) // ch) * args.cols + int((sl[1].start + cx) // cw)
    cells, report = [], []
    for i in range(args.rows * args.cols):
        keep = np.isin(lab, np.nonzero(owner == i)[0]) & (sa[..., 3] > 0)
        rgba = sa.copy()
        rgba[..., 3] = np.where(keep, sa[..., 3], 0)
        ys, xs = np.nonzero(keep)
        cell = Image.fromarray(rgba).crop((xs.min() - 4, ys.min() - 4, xs.max() + 5, ys.max() + 5))
        cells.append(cell)
        report.append({"cell": i, "crosses_grid": bool(xs.min() < (i % args.cols) * cw or xs.max() >= (i % args.cols + 1) * cw)})
    run_im, run_h, run_dx = run_ref()
    hs = []
    for cell in cells:
        x0, y0, x1, y1 = bbox(np.asarray(cell)[..., 3])
        hs.append(y1 - y0)
    scale = run_h / ((hs[0] + hs[-1]) / 2)
    n = len(cells)
    frames = []
    for i, cell in enumerate(cells):
        im = cell.resize((round(cell.width * scale), round(cell.height * scale)), Image.LANCZOS)
        a = np.asarray(im)[..., 3]
        x0, y0, x1, y1 = bbox(a)
        hx = head_x(a)
        t = i / (n - 1)
        want_dx = -run_dx * (1 - t) + run_dx * t  # 起始朝左 = 镜像偏移，结束朝右 = 原偏移
        ox = round(PIVOT[0] + want_dx - hx)
        oy = PIVOT[1] - y1
        canvas = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
        canvas.alpha_composite(im, (ox, oy)) if ox >= 0 and oy >= 0 else canvas.paste(im, (ox, oy), im)
        ca = np.asarray(canvas)[..., 3]
        lost = int((a > 60).sum() - (ca > 60).sum())
        canvas.save(out / f"turn_{i + 1:03d}.png")
        frames.append(canvas)
        report[i].update({"height_src": int(hs[i]), "height_game_px": round((y1 - y0) * DISPLAY, 1), "clipped_px": lost})
    json.dump({"scale": scale, "run_height": int(run_h), "run_head_dx": run_dx, "cells": report},
              open(out / "frames.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    # 帧条图（游戏 2 倍大小，灰底 + 地面线 + pivot 竖线）
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 16)
    z = DISPLAY * 2
    fw, fh = round(CANVAS[0] * z), round(CANVAS[1] * z)
    strip = Image.new("RGB", (fw * n, fh + 24), (58, 62, 70))
    d = ImageDraw.Draw(strip)
    for i, f in enumerate(frames):
        s = f.resize((fw, fh), Image.LANCZOS)
        strip.paste(s, (i * fw, 24), s)
        d.line([(i * fw, 24 + round(PIVOT[1] * z)), ((i + 1) * fw, 24 + round(PIVOT[1] * z))], fill=(120, 200, 140))
        d.line([(i * fw + round(PIVOT[0] * z), 24), (i * fw + round(PIVOT[0] * z), fh + 24)], fill=(90, 90, 110))
        d.text((i * fw + 4, 2), str(i + 1), fill=(255, 230, 120), font=font)
    strip.save(out / "帧条图_游戏2倍.png")

    # 预览：向左跑 2 圈 → 转身 → 向右跑 2 圈（run 循环 16 帧 @30fps，转身 @25.2fps），游戏 2 倍大小
    loop = [Image.open(RUN_DIR / f"run_intro_{k:03d}.png").convert("RGBA") for k in range(7, 23)]
    mp = (RUN_CANVAS[0] - RUN_PIVOT[0], RUN_PIVOT[1])  # 镜像后 run 帧的 pivot
    seq, dur = [], []
    for f in loop * 2:
        seq.append((ImageOps.mirror(f), mp)); dur.append(1000 / 30)
    for f in frames:
        seq.append((f, PIVOT)); dur.append(1000 / args.fps)
    for f in loop * 2:
        seq.append((f, RUN_PIVOT)); dur.append(1000 / 30)

    def render(fr, pv):
        """按 pivot 把任意画布的帧放到同一个预览位置（游戏 2 倍）。"""
        bg = Image.new("RGB", (fw, fh), (40, 44, 52))
        s = fr.resize((round(fr.width * z), round(fr.height * z)), Image.LANCZOS)
        bg.paste(s, (round((PIVOT[0] - pv[0]) * z), round((PIVOT[1] - pv[1]) * z)), s)
        ImageDraw.Draw(bg).line([(0, round(PIVOT[1] * z)), (fw, round(PIVOT[1] * z))], fill=(80, 110, 90))
        return bg

    imgs = [render(f, pv) for f, pv in seq]
    imgs[0].save(out / "预览_左跑转身右跑.gif", save_all=True, append_images=imgs[1:], duration=[round(x) for x in dur], loop=0)
    slow = [render(f, PIVOT) for f in frames]
    slow[0].save(out / "预览_转身慢放_4fps.gif", save_all=True, append_images=slow[1:], duration=250, loop=0)
    print(json.dumps({"scale": round(scale, 4), "cells": report}, ensure_ascii=False))


if __name__ == "__main__":
    main()
