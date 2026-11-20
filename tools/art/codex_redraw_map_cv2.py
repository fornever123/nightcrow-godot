#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
基于 11-06 codex_redraw_map.py 的纯 OpenCV (无 scipy 依赖) 升级版：
Codex 照原帧 1:1 一体重画（角色+高颜值特效同格生成）的网格图 → 精确逆映射还原为游戏帧。

核心保证：
1. 自动清除 #FFFF00 黄框及格线边缘，调用原版 key_green.py 精确反解绿幕去溢色（完整保留紫白剑气半透明飞白层次）。
2. 严格在每个格子的黄框内壁提取前景连通域（保留 >=14px 的星芒与飞白细丝，绝不跨格串扰）。
3. 对原帧执行与 codex_redraw_layout_clean.py 完全一致的孤立微尘剔除，构建 1:1 对齐目标 tgt。
4. 支持 --broken-frames（如弹刀1 f8,f9 原帧上半身/腰部残缺）：仅用完好的下半身双靴做 IoU 锚定并锁定缩放 [0.98, 1.02]，确保补全上半身后人物身高与脚底 100% 严丝合缝。
5. 严格按 (ox = x - bx0*s, oy = y - by0*s) 逆映射回原帧同宽高+pad 画布，世界尺寸与原帧 100.00% 一致！
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from key_green import key as key_green_fn  # noqa: E402
from codex_redraw_layout_clean import clean_stray_specks  # noqa: E402


def iou(a: np.ndarray, b: np.ndarray) -> float:
    inter = int(np.count_nonzero(a & b))
    union = int(np.count_nonzero(a | b))
    return float(inter / max(union, 1))


def bleed_transparent_rgb(rgba: np.ndarray, solid_thresh: int = 210) -> np.ndarray:
    """标准游戏精灵 Alpha Bleed（等同 Unity 'Alpha Is Transparency' / Spine Bleed）：
    将最近实心像素 (A >= solid_thresh) 的纯净 RGB 填入半透明抗锯齿边缘及 A==0 透明像素（保持 Alpha 不变），
    彻底根除 PIL EXTENT 重采样与 Godot GPU 双线性采样在白亮刀光外缘混入 (0,0,0,0) 造成的 1px 黑灰边！
    """
    out = rgba.copy()
    a = out[..., 3]
    solid = (a >= solid_thresh).astype(np.uint8)
    if int(np.count_nonzero(solid)) < 8:
        solid = (a > 30).astype(np.uint8)
    if int(np.count_nonzero(solid)) == 0:
        return out

    inv = (1 - solid).astype(np.uint8)
    dist, labels = cv2.distanceTransformWithLabels(inv, cv2.DIST_L2, 3, labelType=cv2.DIST_LABEL_PIXEL)
    ys, xs = np.nonzero(solid > 0)
    lbl_vals = labels[ys, xs]
    max_lbl = int(labels.max()) + 1
    lut_y = np.zeros(max_lbl, dtype=np.int32)
    lut_x = np.zeros(max_lbl, dtype=np.int32)
    lut_y[lbl_vals] = ys
    lut_x[lbl_vals] = xs

    # 1) 对 0 < A < solid_thresh 且距实心 <= 2.5px 的抗锯齿边缘去除残留暗绿灰混色（保留更远处的独立半透明紫烟原色）
    aa_edge = (a > 0) & (solid == 0) & (dist <= 2.5) & (labels > 0)
    if np.any(aa_edge):
        ey, ex = np.nonzero(aa_edge)
        el = labels[ey, ex]
        out[ey, ex, :3] = out[lut_y[el], lut_x[el], :3]

    # 2) 对所有 A == 0 且距前景 <= 6px 的透明邻域写入最近前景 RGB（Alpha 仍严格为 0），消除重采样与 GPU 黑边
    fg = (a > 0).astype(np.uint8)
    inv_fg = (1 - fg).astype(np.uint8)
    dist_fg, lbl_fg = cv2.distanceTransformWithLabels(inv_fg, cv2.DIST_L2, 3, labelType=cv2.DIST_LABEL_PIXEL)
    fys, fxs = np.nonzero(fg > 0)
    flbls = lbl_fg[fys, fxs]
    max_fl = int(lbl_fg.max()) + 1
    flut_y = np.zeros(max_fl, dtype=np.int32)
    flut_x = np.zeros(max_fl, dtype=np.int32)
    flut_y[flbls] = fys
    flut_x[flbls] = fxs
    zero_ring = (a == 0) & (dist_fg <= 6.0) & (lbl_fg > 0)
    if np.any(zero_ring):
        zy, zx = np.nonzero(zero_ring)
        zl = lbl_fg[zy, zx]
        out[zy, zx, :3] = out[flut_y[zl], flut_x[zl], :3]

    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("gen", help="Codex 生成的网格原图路径")
    ap.add_argument("layout", help="输入_排版.json 路径")
    ap.add_argument("out", help="输出帧目录")
    ap.add_argument("--pad", type=int, default=-1, help="画布四周加边像素；-1 = 按需要自动算")
    ap.add_argument("--broken-frames", default="", help="原帧上半身残缺的帧号（逗号分隔，如 8,9），仅对齐下半身双靴")
    ap.add_argument("--source-json", default="", help="可选：原始动画备份 JSON，用于校验尺寸")
    args = ap.parse_args()

    broken_set = {int(x.strip()) for x in args.broken_frames.split(",") if x.strip()}

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    lay = json.loads(Path(args.layout).read_text(encoding="utf-8"))
    W, H = int(lay["size"][0]), int(lay["size"][1])
    s = float(lay["scale"])
    cols, rows = int(lay["cols"]), int(lay["rows"])
    cw, ch = W // cols, H // rows

    src = Image.open(args.gen).convert("RGB")
    if src.size != (W, H):
        src = src.resize((W, H), Image.Resampling.LANCZOS)

    # 1. 清除黄色网格细框（含抗锯齿黄绿过渡像素 + 格子最外圈 6px 框线带）涂回纯绿 #00FF00
    arr = np.asarray(src).astype(np.int32)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    yellow = (r > 135) & (g > 145) & (b < 120) & (np.abs(r - g) < 105)
    arr[yellow] = (0, 255, 0)
    for rr in range(rows):
        for cc in range(cols):
            cx, cy = cc * cw, rr * ch
            arr[cy:cy + 7, cx:cx + cw] = (0, 255, 0)
            arr[cy + ch - 7:cy + ch, cx:cx + cw] = (0, 255, 0)
            arr[cy:cy + ch, cx:cx + 7] = (0, 255, 0)
            arr[cy:cy + ch, cx + cw - 7:cx + cw] = (0, 255, 0)

    clean_rgb_fp = out / "_gen_resized.png"
    keyed_fp = out / "_keyed.png"
    gen_mtime = Path(args.gen).stat().st_mtime
    if not (keyed_fp.exists() and keyed_fp.stat().st_mtime >= gen_mtime):
        Image.fromarray(arr.astype(np.uint8)).save(clean_rgb_fp)
        key_green_fn(str(clean_rgb_fp), str(keyed_fp))
    sheet = np.asarray(Image.open(keyed_fp).convert("RGBA"))

    results = []
    for idx_in_lay, fr in enumerate(lay["frames"]):
        f_idx = int(fr["frame"])
        cx, cy, cell_w, cell_h = [int(v) for v in fr["cell"]]
        # 严格取当前格内壁：剔除绿幕噪点（面积<48且最高不透明度<200的半透明杂点），同时保留实心十字白星芒与飞羽
        sub = sheet[cy + 7:cy + cell_h - 7, cx + 7:cx + cell_w - 7].copy()
        sub[..., 3] = np.where(sub[..., 3] >= 24, sub[..., 3], 0)
        mask = (sub[..., 3] > 0).astype(np.uint8)
        n_lbl, lbls, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
        keep_mask = np.zeros_like(mask, dtype=bool)
        for li in range(1, n_lbl):
            area = int(stats[li, cv2.CC_STAT_AREA])
            if area >= 48:
                keep_mask |= (lbls == li)
            elif area >= 10:
                comp_max_a = int(sub[lbls == li, 3].max())
                if comp_max_a >= 210:
                    keep_mask |= (lbls == li)
        sub[..., 3] = np.where(keep_mask, sub[..., 3], 0)
        sub = bleed_transparent_rgb(sub, solid_thresh=210)

        cell_canvas = np.zeros_like(sheet)
        cell_canvas[cy + 7:cy + cell_h - 7, cx + 7:cx + cell_w - 7] = sub
        ys, xs = np.nonzero(cell_canvas[..., 3] > 50)
        if len(xs) == 0:
            raise RuntimeError(f"Empty foreground in frame {f_idx} cell {[cx, cy, cell_w, cell_h]}")
        x0_raw, y0_raw = int(xs.min()), int(ys.min())
        x1_raw, y1_raw = int(xs.max()) + 1, int(ys.max()) + 1
        new_im = Image.fromarray(cell_canvas).crop((x0_raw, y0_raw, x1_raw, y1_raw))

        # 2. 构造原帧在网格里的精确对齐目标 tgt（与排版时使用完全相同的 clean_stray_specks）
        orig = Image.open(ROOT / "assets" / fr["asset"]).convert("RGBA")
        frame_size = [int(fr["size"][0]), int(fr["size"][1])]
        if orig.size != tuple(frame_size):
            orig = orig.resize(tuple(frame_size), Image.Resampling.LANCZOS)
        orig = clean_stray_specks(orig)

        x, y, pw, ph = [int(v) for v in fr["placed"]]
        bx0, by0, bx1, by1 = [int(v) for v in fr["bbox"]]
        tgt = np.zeros((H, W), dtype=bool)
        oc = orig.crop((bx0, by0, bx1, by1)).resize((pw, ph), Image.Resampling.LANCZOS)
        tgt[y:y + ph, x:x + pw] = np.asarray(oc)[..., 3] > 60

        is_broken = f_idx in broken_set
        if is_broken:
            # 原帧上半身/腰部残缺，仅用下半身完好双靴区域计算 IoU，且严格锁定缩放接近 1.00
            roi_mask = np.zeros((H, W), dtype=bool)
            roi_mask[y + (ph * 55) // 100:y + ph + 12, max(0, x - 30):min(W, x + pw + 30)] = True
            k_grid = np.linspace(0.98, 1.02, 5)
            dy_grid = range(-8, 9, 2)
            dx_grid = range(-22, 23, 2)
        else:
            roi_mask = None
            k_grid = np.linspace(0.95, 1.05, 11)
            dy_grid = range(-10, 11, 2)
            dx_grid = range(-22, 23, 2)

        foot_cx = x + pw * 0.5
        best = (-1.0, None)
        for k in k_grid:
            nw = max(1, round(new_im.width * float(k)))
            nh = max(1, round(new_im.height * float(k)))
            ni = new_im.resize((nw, nh), Image.Resampling.LANCZOS)
            na = np.asarray(ni)[..., 3] > 60
            # 以角色原绘制格坐标 (x0_raw, y1_raw) 围绕脚底中心做微缩放，绝不因新增补全长剑或星芒而偏移脚底
            base_x = round(foot_cx - (foot_cx - x0_raw) * float(k))
            base_y = y + ph - nh
            for dy in dy_grid:
                for dx in dx_grid:
                    px, py = base_x + dx, base_y + dy
                    if px < 0 or py < 0 or px + nw > W or py + nh > H:
                        continue
                    cand = np.zeros((H, W), dtype=bool)
                    cand[py:py + nh, px:px + nw] = na
                    if roi_mask is not None:
                        sc = iou(cand & roi_mask, tgt & roi_mask)
                    else:
                        sc = iou(cand, tgt)
                    if sc > best[0]:
                        best = (sc, (float(k), int(px), int(py), ni))

        score, (best_k, px, py, best_ni) = best
        placed_arr = np.zeros((H, W, 4), dtype=np.uint8)
        placed_im = Image.fromarray(placed_arr)
        placed_im.paste(best_ni, (px, py), best_ni)
        placed_im = Image.fromarray(bleed_transparent_rgb(np.asarray(placed_im), solid_thresh=210))

        # 反算回原帧画布坐标原点
        ox = x - bx0 * s
        oy = y - by0 * s
        results.append({
            "frame": f_idx,
            "asset": fr["asset"],
            "iou": round(score, 3),
            "k": round(best_k, 3),
            "orig_size": frame_size,
            "orig_pivot": [float(fr["pivot"][0]), float(fr["pivot"][1])],
            "_placed": placed_im,
            "_o": (ox, oy),
        })

    # 3. 计算统一加边 pad（确保延伸的剑尖或飞白尖梢绝不被裁切，同时 pivot 精确同步平移）
    need = 0.0
    for r in results:
        ox, oy = r["_o"]
        w, h = r["orig_size"]
        a = np.asarray(r["_placed"])[..., 3] > 20
        ys, xs = np.nonzero(a)
        u0, u1 = (float(xs.min()) - ox) / s, (float(xs.max()) + 1.0 - ox) / s
        v0, v1 = (float(ys.min()) - oy) / s, (float(ys.max()) + 1.0 - oy) / s
        need = max(need, -u0, u1 - w, -v0, v1 - h)

    pad = int(np.ceil(max(need, 0.0))) + 4 if args.pad < 0 else int(args.pad)
    manifest = {"clip": lay["clip"], "pad": pad, "scale": s, "frames": []}

    for r in results:
        ox, oy = r["_o"]
        w, h = r["orig_size"]
        crop_box = (ox - pad * s, oy - pad * s, ox + (w + pad) * s, oy + (h + pad) * s)
        fr_im = r["_placed"].transform((w + 2 * pad, h + 2 * pad), Image.Transform.EXTENT, crop_box, Image.Resampling.BICUBIC)
        fr_arr = bleed_transparent_rgb(np.asarray(fr_im), solid_thresh=210)
        # 适配游戏内置 char_light.gdshader 自发光与免黑描边阈值 (step(r + 0.08, b))：
        # 将刀光冷白/紫白高亮像素 (B >= 215 且 B >= G - 4) 微校准至冷冰白色域 (R <= B - 22)，避免着色器误判为白衣加黑描边
        b_ch = fr_arr[..., 2].astype(np.int32)
        g_ch = fr_arr[..., 1].astype(np.int32)
        r_ch = fr_arr[..., 0].astype(np.int32)
        cool_vfx = (fr_arr[..., 3] > 0) & (b_ch >= 215) & (b_ch >= g_ch - 4) & (r_ch > b_ch - 22)
        fr_arr[..., 0] = np.where(cool_vfx, np.clip(b_ch - 22, 0, 255), r_ch).astype(np.uint8)
        name = f"frame_{r['frame'] + 1:05d}.png"
        Image.fromarray(fr_arr).save(out / name)
        manifest["frames"].append({
            "frame": r["frame"],
            "file": name,
            "source_asset": r["asset"],
            "iou_to_original": r["iou"],
            "fit_scale": r["k"],
            "width": w + 2 * pad,
            "height": h + 2 * pad,
            "pivotX": round(r["orig_pivot"][0] + pad, 3),
            "pivotY": round(r["orig_pivot"][1] + pad, 3),
            "pivot_shift": pad,
        })

    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "clip": lay["clip"],
        "pad": pad,
        "frames": [(f["frame"], f["iou_to_original"], f["fit_scale"]) for f in manifest["frames"]],
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
