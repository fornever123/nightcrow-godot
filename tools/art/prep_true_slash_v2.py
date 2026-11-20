#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建修正版导引底板 输入_真刀光底板_v2.png（用于获批硬上限内的最后 1 次生图 2/2）：
彻底修复 v1 的两处几何问题（实体剑被拉长成 2.2 倍 + 右下 90° 硬折角把线条聚成折扇骨）：
- 实体符文直剑严格锁死 1.0x 原长 (clean_actor_f05.png 原位覆盖在最上层，剑尖清晰明确止于 tx, ty)！
- 上排两格 (R1, R2) 采用【立劈直刃扇形同心残影导引 (Type B)】：
  外弧精准止于 1.0x 真实剑尖 (tx, ty)，内弧止于剑格护手前缘，刀光从整条真实剑刃背侧呈 100% 同心圆弧向上扫掠渐隐；
- 下排两格 (R3, R4) 采用【斜横斩 3D 透视满弓流线导引 (Type A)】：
  外弧向右前方饱满破空甩出后以 C2 圆润切线平滑顺接入 1.0x 真实剑尖与剑刃（零 90° 死折角、零倒钩 V 口）。
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
WORK_DIR = ROOT / r"docs\视觉设计\角色动作\真刀光样板_20261115"
BG_RGB = (20, 22, 32)


def cubic(p0: np.ndarray, p1: np.ndarray, p2: np.ndarray, p3: np.ndarray, t: np.ndarray) -> np.ndarray:
    u = 1.0 - t
    return (u ** 3) * p0 + 3.0 * (u ** 2) * t * p1 + 3.0 * u * (t ** 2) * p2 + (t ** 3) * p3


def rasterize_ribbon_guide(
    W: int,
    H: int,
    p_out: np.ndarray,
    p_in: np.ndarray,
    hx: float,
    hy: float,
    tx: float,
    ty: float,
    mode: str,
) -> np.ndarray:
    """用高密度参数网格平滑光栅化连续半透明同心刀光导引纱（无离散条纹伪影）。"""
    n_t = p_out.shape[0]
    n_r = 96
    r_vals = np.linspace(0.0, 1.0, n_r, dtype=np.float32)

    acc_w = np.zeros((H, W), dtype=np.float32)
    acc_r = np.zeros((H, W), dtype=np.float32)
    acc_t = np.zeros((H, W), dtype=np.float32)

    t_vals = np.linspace(0.0, 1.0, n_t, dtype=np.float32)
    # shape: (n_r, n_t, 2)
    pts = (1.0 - r_vals[:, None, None]) * p_in[None, :, :] + r_vals[:, None, None] * p_out[None, :, :]
    xs = np.round(pts[..., 0]).astype(np.int32)
    ys = np.round(pts[..., 1]).astype(np.int32)
    valid = (xs >= 0) & (xs < W) & (ys >= 0) & (ys < H)

    rr_grid = np.broadcast_to(r_vals[:, None], (n_r, n_t))[valid]
    tt_grid = np.broadcast_to(t_vals[None, :], (n_r, n_t))[valid]
    xv = xs[valid]
    yv = ys[valid]

    np.add.at(acc_w, (yv, xv), 1.0)
    np.add.at(acc_r, (yv, xv), rr_grid)
    np.add.at(acc_t, (yv, xv), tt_grid)

    mask = acc_w > 0
    r_map = np.zeros((H, W), dtype=np.float32)
    t_map = np.zeros((H, W), dtype=np.float32)
    r_map[mask] = acc_r[mask] / acc_w[mask]
    t_map[mask] = acc_t[mask] / acc_w[mask]

    # 对稀疏空隙做极轻微闭运算与高斯平滑，形成 100% 丝滑连续的光学导引层
    mask_u8 = (mask.astype(np.uint8)) * 255
    mask_closed = cv2.morphologyEx(mask_u8, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    r_blur = cv2.GaussianBlur(r_map, (7, 7), 1.8)
    t_blur = cv2.GaussianBlur(t_map, (7, 7), 1.8)
    w_blur = cv2.GaussianBlur((mask.astype(np.float32)), (7, 7), 1.8)
    valid_s = (mask_closed > 0) & (w_blur > 0.05)

    r_s = np.where(valid_s, np.clip(r_blur / np.maximum(w_blur, 0.05), 0.0, 1.0), 0.0)
    t_s = np.where(valid_s, np.clip(t_blur / np.maximum(w_blur, 0.05), 0.0, 1.0), 0.0)

    # 下边界保护：不越过实体剑身下沿直线
    yy, xx = np.mgrid[:H, :W].astype(np.float32)
    ux, uy = tx - hx, ty - hy
    ulen = math.hypot(ux, uy)
    nx, ny = -uy / ulen, ux / ulen
    if ny > 0:
        nx, ny = -nx, -ny
    above_blade = (xx - hx) * nx + (yy - hy) * ny
    valid_s &= (above_blade >= -2.0) | (yy < hy - 25.0)

    # 沿弧进度亮度：左上尾端 (t=0) 轻柔渐隐归零，中前段主刀肚 (t=0.58..0.96) 饱满明亮
    along = np.sin(np.clip(t_s, 0.0, 1.0) ** 1.28 * math.pi * 0.58)
    if mode == "streaks":
        # 微弱同心弧流线暗示（100% 沿圆弧方向，绝非折扇辐射！）
        mod = 0.84 + 0.16 * np.sin(r_s * math.pi * 7.0)
    elif mode == "double_wave":
        # 外锋 + 内侧第二道同心激波弦暗示
        second_rib = 0.35 * np.exp(-((r_s - 0.56) ** 2) / (2 * 0.06 ** 2))
        mod = np.clip(0.75 + second_rib, 0.0, 1.15)
    else:
        mod = 1.0

    radial = (0.15 + 0.85 * (r_s ** 2.0)) * mod
    alpha_f = np.where(valid_s, np.clip(along * radial * 0.23, 0.0, 0.25), 0.0)
    alpha_f = cv2.GaussianBlur(alpha_f, (5, 5), 1.1)

    guide = np.zeros((H, W, 4), dtype=np.uint8)
    whiteness = np.clip(r_s ** 2.6, 0.0, 1.0)
    guide[..., 0] = (152 + 95 * whiteness).astype(np.uint8)
    guide[..., 1] = (86 + 154 * whiteness).astype(np.uint8)
    guide[..., 2] = 255
    guide[..., 3] = np.clip(np.round(alpha_f * 255.0), 0, 255).astype(np.uint8)
    return guide


def main() -> None:
    actor_im = Image.open(WORK_DIR / "clean_actor_f05.png").convert("RGBA")
    lay_v1 = json.loads((WORK_DIR / "输入_排版.json").read_text(encoding="utf-8"))
    fr0 = lay_v1["frames"][0]
    W, H = int(fr0["orig_size"][0]), int(fr0["orig_size"][1])
    px, py = float(fr0["orig_pivot"][0]), float(fr0["orig_pivot"][1])
    hx, hy = px + 118.0, py - 94.0
    tx, ty = px + 352.0, py - 38.0

    # 清除剑脊上方约 8px 处残留的一小撮青灰杂点，确保 1.0x 实体长剑刃口笔直如尺
    ac_arr = np.asarray(actor_im).copy()
    yy_a, xx_a = np.ogrid[:H, :W]
    dx_s, dy_s = tx - hx, ty - hy
    lsq = dx_s * dx_s + dy_s * dy_s
    tp = ((xx_a - hx) * dx_s + (yy_a - hy) * dy_s) / lsq
    nx_u, ny_u = dy_s / math.sqrt(lsq), -dx_s / math.sqrt(lsq)  # 指向剑脊上方 (ny_u < 0)
    signed_above = (xx_a - hx) * nx_u + (yy_a - hy) * ny_u
    fleck = (tp > 0.35) & (tp < 0.96) & (signed_above > 5.2) & (xx_a > px + 200)
    ac_arr[..., 3] = np.where(fleck, 0, ac_arr[..., 3])
    actor_im = Image.fromarray(ac_arr)

    t = np.linspace(0.0, 1.0, 900, dtype=np.float32)[:, None]

    # Type B (R1, R2): 立劈直刃同心扇面残影（外弧精准止于 1.0x 剑尖 tx, ty，内弧止于剑格前缘，零拉长剑身！）
    p_out_B = cubic(
        np.array([px - 48.0, py - 372.0], dtype=np.float32),
        np.array([px + 275.0, py - 372.0], dtype=np.float32),
        np.array([px + 432.0, py - 165.0], dtype=np.float32),
        np.array([tx + 2.0, ty + 1.0], dtype=np.float32),
        t,
    )
    p_in_B = cubic(
        np.array([px - 48.0, py - 372.0], dtype=np.float32),
        np.array([px + 178.0, py - 328.0], dtype=np.float32),
        np.array([px + 278.0, py - 168.0], dtype=np.float32),
        np.array([hx + 34.0, hy + 8.0], dtype=np.float32),
        t,
    )

    # Type A (R3, R4): 斜横斩 3D 透视满弓流线（前肚破空甩出后圆润相切汇入 1.0x 真实剑尖与剑脊，零折角、零倒钩！）
    p_out_A = cubic(
        np.array([px - 92.0, py - 366.0], dtype=np.float32),
        np.array([px + 378.0, py - 382.0], dtype=np.float32),
        np.array([px + 548.0, py - 46.0], dtype=np.float32),
        np.array([tx - 8.0, ty + 1.0], dtype=np.float32),
        t,
    )
    p_in_A = cubic(
        np.array([px - 92.0, py - 366.0], dtype=np.float32),
        np.array([px + 248.0, py - 340.0], dtype=np.float32),
        np.array([px + 372.0, py - 96.0], dtype=np.float32),
        np.array([hx + 52.0, hy + 13.0], dtype=np.float32),
        t,
    )

    cell_specs = [
        ("R1", p_out_B, p_in_B, "streaks"),
        ("R2", p_out_B, p_in_B, "smooth"),
        ("R3", p_out_A, p_in_A, "smooth"),
        ("R4", p_out_A, p_in_A, "double_wave"),
    ]

    comps: list[Image.Image] = []
    union_alpha = np.zeros((H, W), dtype=np.uint8)
    for _, po, pi, md in cell_specs:
        g_arr = rasterize_ribbon_guide(W, H, po, pi, hx, hy, tx, ty, md)
        c_im = Image.fromarray(g_arr)
        c_im.alpha_composite(actor_im)
        comps.append(c_im)
        union_alpha = np.maximum(union_alpha, np.asarray(c_im)[..., 3])

    ys, xs = np.nonzero(union_alpha > 4)
    bx0, by0 = max(0, int(xs.min()) - 20), max(0, int(ys.min()) - 18)
    bx1, by1 = min(W, int(xs.max()) + 28), min(H, int(ys.max()) + 20)
    bw, bh = bx1 - bx0, by1 - by0

    grid_W, grid_H = 1536, 1024
    cols, rows = 2, 2
    cw, ch = grid_W // cols, grid_H // rows
    pad_x, pad_y = 56, 44
    scale = min((cw - 2 * pad_x) / bw, (ch - 2 * pad_y) / bh)
    pw, ph = round(bw * scale), round(bh * scale)

    sheet = Image.new("RGBA", (grid_W, grid_H), (*BG_RGB, 255))
    frames_meta = []
    for idx, (code, _, _, _) in enumerate(cell_specs):
        rr, cc = divmod(idx, cols)
        cx0, cy0 = cc * cw, rr * ch
        ox = cx0 + (cw - pw) // 2
        oy = cy0 + (ch - ph) // 2 + 6
        crop_c = comps[idx].crop((bx0, by0, bx1, by1)).resize((pw, ph), Image.Resampling.LANCZOS)
        sheet.alpha_composite(crop_c, (ox, oy))
        frames_meta.append({
            "cell_idx": idx,
            "code": code,
            "cell": [cx0, cy0, cw, ch],
            "placed": [ox, oy, pw, ph],
            "bbox": [bx0, by0, bx1, by1],
            "orig_size": [W, H],
            "orig_pivot": [px, py],
        })

    sheet_rgb = sheet.convert("RGB")
    draw = ImageDraw.Draw(sheet_rgb)
    for rr in range(rows):
        for cc in range(cols):
            x0, y0 = cc * cw, rr * ch
            draw.rectangle([x0 + 1, y0 + 1, x0 + cw - 2, y0 + ch - 2], outline=(255, 255, 0), width=3)

    out_fp = WORK_DIR / "输入_真刀光底板_v2.png"
    sheet_rgb.save(out_fp)
    layout_v2 = {
        "clip": "attack_1_f05_true_slash_v2",
        "bg_rgb": list(BG_RGB),
        "scale": scale,
        "size": [grid_W, grid_H],
        "cols": cols,
        "rows": rows,
        "frames": frames_meta,
    }
    (WORK_DIR / "输入_排版_v2.json").write_text(json.dumps(layout_v2, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared v2 -> {out_fp} | scale={scale:.4f}, placed={pw}x{ph}")


if __name__ == "__main__":
    main()
