"""Codex 照原帧重画的网格图 → 还原成和原帧一一对应的游戏帧（角色动作线，11-06）。

输入：Codex 出的图、排版记录（输入_排版.json，由排版时写出：每帧原 bbox、在网格里的位置、统一缩放）。
步骤：绿底抠像 → 按连通块把人物归到格子 → 每格用 alpha IoU 搜一个小的缩放 + 平移，贴回原帧在网格里的位置 →
按排版反算回原帧画布（同宽高、同 pivot；新剑伸出原画布时四周统一加边，pivot 跟着平移）→ 出 PNG + 清单。
不碰 battle.json。

用法：python tools/art/codex_redraw_map.py 生成图.png 输入_排版.json 输出目录 [--pad 0]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from key_green import key  # noqa: E402


def iou(a: np.ndarray, b: np.ndarray) -> float:
    return float((a & b).sum() / max((a | b).sum(), 1))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("gen")
    ap.add_argument("layout")
    ap.add_argument("out")
    ap.add_argument("--pad", type=int, default=-1, help="画布四周加边像素；-1 = 按需要自动算")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    lay = json.load(open(args.layout, encoding="utf-8"))
    W, H = lay["size"]
    s = float(lay["scale"])
    src = Image.open(args.gen).convert("RGB")
    if src.size != (W, H):
        src = src.resize((W, H), Image.LANCZOS)
    if lay.get("boxes"):
        # 黄色方格框（#FFFF00）当背景：红绿都高、蓝低的像素一律涂回纯绿，再交给绿幕抠像
        a = np.asarray(src).astype(int)
        r, g, b = a[..., 0], a[..., 1], a[..., 2]
        yellow = (r > 150) & (g > 150) & (b < 110) & (np.abs(r - g) < 90)
        a[yellow] = (0, 255, 0)
        src = Image.fromarray(a.astype(np.uint8))
    src.save(out / "_gen_resized.png")
    key(str(out / "_gen_resized.png"), str(out / "keyed.png"))
    sheet = np.asarray(Image.open(out / "keyed.png").convert("RGBA"))
    cols = int(lay["cols"])
    cw, ch = W // cols, H // int(lay["rows"])
    lab, n = ndimage.label(ndimage.binary_dilation(sheet[..., 3] > 30, iterations=2))
    owner = np.full(n + 1, -1)
    for k, sl in enumerate(ndimage.find_objects(lab), start=1):
        m = lab[sl] == k
        if m.sum() < 40:
            continue
        cy, cx = ndimage.center_of_mass(m)
        owner[k] = int((sl[0].start + cy) // ch) * cols + int((sl[1].start + cx) // cw)

    results, frames_rgba = [], []
    for n, fr in enumerate(lay["frames"]):
        i = fr["frame"]
        # 格子序号按排版里的位置算（只排了一段帧时，格子序号 ≠ 剪辑里的帧号）
        cell = fr.get("cell")
        n_cell = (cell[1] // ch) * cols + cell[0] // cw if cell else n
        keep = np.isin(lab, np.nonzero(owner == n_cell)[0]) & (sheet[..., 3] > 0)
        new = sheet.copy()
        new[..., 3] = np.where(keep, sheet[..., 3], 0)
        ys, xs = np.nonzero(new[..., 3] > 60)
        new_im = Image.fromarray(new).crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
        # 原帧在网格里的样子（作对齐目标）
        orig = Image.open(ROOT / "assets" / fr["asset"]).convert("RGBA")
        info = fr
        x, y, pw, ph = info["placed"]
        bx0, by0, bx1, by1 = info["bbox"]
        frame_size = info.get("size") or [orig.width, orig.height]
        if orig.size != tuple(frame_size):
            orig = orig.resize(tuple(frame_size), Image.LANCZOS)
        tgt = np.zeros((H, W), bool)
        oc = orig.crop((bx0, by0, bx1, by1)).resize((pw, ph), Image.LANCZOS)
        tgt[y:y + ph, x:x + pw] = np.asarray(oc)[..., 3] > 60
        # 搜缩放 + 平移：先用脚底和横向中心对上，再在小范围里找 IoU 最大
        best = (-1.0, None)
        for k in np.linspace(0.9, 1.1, 11):
            ni = new_im.resize((max(1, round(new_im.width * k)), max(1, round(new_im.height * k))), Image.LANCZOS)
            na = np.asarray(ni)[..., 3] > 60
            base_x = x + pw // 2 - ni.width // 2
            base_y = y + ph - ni.height
            for dy in range(-12, 13, 3):
                for dx in range(-24, 25, 3):
                    px, py = base_x + dx, base_y + dy
                    if px < 0 or py < 0 or px + ni.width > W or py + ni.height > H:
                        continue
                    cand = np.zeros((H, W), bool)
                    cand[py:py + ni.height, px:px + ni.width] = na
                    sc = iou(cand, tgt)
                    if sc > best[0]:
                        best = (sc, (k, px, py, ni))
        score, (k, px, py, ni) = best
        placed = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        placed.paste(ni, (px, py), ni)
        # 反算回原帧画布：原帧像素 (u, v) 在网格里 = (x + (u - bx0) * s, y + (v - by0) * s)
        ox, oy = x - bx0 * s, y - by0 * s
        results.append({"frame": i, "asset": fr["asset"], "iou": round(score, 3), "k": round(float(k), 3),
                        "orig_size": list(frame_size), "_placed": placed, "_o": (ox, oy)})
        frames_rgba.append(placed)

    # 统一加边：新剑可能比原画布宽
    need = 0
    for r in results:
        ox, oy = r["_o"]
        w, h = r["orig_size"]
        a = np.asarray(r["_placed"])[..., 3] > 30
        ys, xs = np.nonzero(a)
        u0, u1 = (xs.min() - ox) / s, (xs.max() - ox) / s
        v0, v1 = (ys.min() - oy) / s, (ys.max() - oy) / s
        need = max(need, -u0, u1 - w, -v0, v1 - h)
    pad = int(np.ceil(max(need, 0))) + 2 if args.pad < 0 else args.pad
    manifest = {"pad": pad, "scale": s, "frames": []}
    for r in results:
        ox, oy = r["_o"]
        w, h = r["orig_size"]
        crop_box = (ox - pad * s, oy - pad * s, ox + (w + pad) * s, oy + (h + pad) * s)
        fr_im = r["_placed"].transform((w + 2 * pad, h + 2 * pad), Image.EXTENT, crop_box, Image.BICUBIC)
        name = f"frame_{r['frame'] + 1:05d}.png"
        fr_im.save(out / name)
        manifest["frames"].append({"frame": r["frame"], "file": name, "source_asset": r["asset"], "iou_to_original": r["iou"],
                                   "fit_scale": r["k"], "width": w + 2 * pad, "height": h + 2 * pad, "pivot_shift": pad})
    json.dump(manifest, open(out / "manifest.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(json.dumps({"pad": pad, "frames": [(f["frame"], f["iou_to_original"], f["fit_scale"]) for f in manifest["frames"]]}))


if __name__ == "__main__":
    main()
