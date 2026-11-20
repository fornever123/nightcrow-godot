#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将深暗灰摄影棚底 (#141620) 生成的「真·刀光 v2 (R1–R4)」与「v1 (S1–S4)」解包为高通透半透明世界坐标帧：
1. 用角色躯干+头部模板匹配 (TM_CCOEFF_NORMED) 将每格角色以亚像素级精度锁死到 clean_actor_f05 (385px 身高 100% 恒定)。
2. 角色本体与 1.0x 黑银符文直剑保持 100% 实心不透明（护手与黑银剑脊绝不漏底）；
   外部刀光区域采用【暗棚光学线性解混】C_obs = bg * (1 - alpha) + fg * alpha，还原 0%..100% 连续柔顺半透明光纱。
3. 针对外部刀光像素校准至 char_light.gdshader 的 OL_TAP 免描边与 slash_emissive 自发光色域，确保雨夜街实机晶莹通透。
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from codex_redraw_map_cv2 import bleed_transparent_rgb  # noqa: E402

WORK_DIR = ROOT / r"docs\视觉设计\角色动作\真刀光样板_20261115"
STAGE_REL = "image/desktop-actions-hd/true_slash_preview"
STAGE_ABS = ROOT / "assets" / "image" / "desktop-actions-hd" / "true_slash_preview"

V2_META = [
    ("R1", "胧村正 · 拔刀同心弧流丝斩", "1.0x 原长直剑 + 十余道与外弧严格平行同心的高速破空拉丝"),
    ("R2", "死亡细胞/空洞 · 双阶高打击疾风斩", "1.0x 原长直剑 + 饱满炽白月刃高光锋带 + 通透电光紫破风尖尾"),
    ("R3", "绝区零星见雅 · 满弓月华流光斩", "1.0x 原长直剑 + 前冲圆润满弓白锋相切汇入剑尖 + 蝉翼渐变紫纱"),
    ("R4", "鬼泣次元居合 · 双弦真空切风浪", "1.0x 原长直剑 + 外圈极亮切风主弧 + 内侧同心激波副弧与真空薄雾"),
]

V1_META = [
    ("S1", "极简细锋 · 蝉翼紫纱残影 (v1)", "早期试画对照：极细冷白外弦 + 大面积轻薄紫雾"),
    ("S2", "密集拉丝 · 扇面疾斩 (v1)", "早期试画对照：高密度扇面拉丝"),
    ("S3", "极简双线 · 空气切口 (v1)", "早期试画对照：克制细弦空气切线"),
    ("S4", "紫墨扫掠 · 飞白尾丝 (v1)", "早期试画对照：半透明紫墨扫掠尾"),
]


def load_fleck_free_actor() -> np.ndarray:
    actor_im = Image.open(WORK_DIR / "clean_actor_f05.png").convert("RGBA")
    lay_v1 = json.loads((WORK_DIR / "输入_排版.json").read_text(encoding="utf-8"))
    fr0 = lay_v1["frames"][0]
    W, H = int(fr0["orig_size"][0]), int(fr0["orig_size"][1])
    px, py = float(fr0["orig_pivot"][0]), float(fr0["orig_pivot"][1])
    hx, hy = px + 118.0, py - 94.0
    tx, ty = px + 352.0, py - 38.0

    ac_arr = np.asarray(actor_im).copy()
    yy_a, xx_a = np.ogrid[:H, :W]
    dx_s, dy_s = tx - hx, ty - hy
    lsq = dx_s * dx_s + dy_s * dy_s
    tp = ((xx_a - hx) * dx_s + (yy_a - hy) * dy_s) / lsq
    nx_u, ny_u = dy_s / math.sqrt(lsq), -dx_s / math.sqrt(lsq)
    signed_above = (xx_a - hx) * nx_u + (yy_a - hy) * ny_u
    fleck = (tp > 0.35) & (tp < 0.96) & (signed_above > 5.2) & (xx_a > px + 200)
    ac_arr[..., 3] = np.where(fleck, 0, ac_arr[..., 3])
    return ac_arr


def unmix_dark_studio_cell(
    cell_rgb: np.ndarray,
    actor_rgba_full: np.ndarray,
    placed: list[int],
    bbox: list[int],
    protect_full_sword: bool,
) -> tuple[Image.Image, float, float]:
    ch, cw = cell_rgb.shape[:2]
    work = cell_rgb.copy()

    inner_border = np.concatenate([
        work[10:28, 10:cw - 10].reshape(-1, 3),
        work[ch - 28:ch - 10, 10:cw - 10].reshape(-1, 3),
        work[10:ch - 10, 10:36].reshape(-1, 3),
    ], axis=0)
    lums = inner_border.mean(axis=1)
    dark_samples = inner_border[lums <= np.percentile(lums, 45)]
    bg = np.median(dark_samples, axis=0).astype(np.float32)

    work[:8, :] = np.round(bg).astype(np.uint8)
    work[ch - 8:, :] = np.round(bg).astype(np.uint8)
    work[:, :8] = np.round(bg).astype(np.uint8)
    work[:, cw - 8:] = np.round(bg).astype(np.uint8)

    bx0, by0, bx1, by1 = bbox
    pw, ph = placed[2], placed[3]
    actor_crop = Image.fromarray(actor_rgba_full).crop((bx0, by0, bx1, by1)).resize((pw, ph), Image.Resampling.LANCZOS)
    actor_cell_arr = np.asarray(actor_crop)

    # 仅用左侧人物躯干头靴做跨格刚体对齐模板（不受右侧刀光影响）
    tpl_w = min(pw, round(pw * 0.40))
    tpl_rgba = actor_cell_arr[:, :tpl_w]
    ta = tpl_rgba[..., 3:4].astype(np.float32) / 255.0
    tpl_u8 = np.clip(tpl_rgba[..., :3].astype(np.float32) * ta + bg * (1.0 - ta), 0, 255).astype(np.uint8)

    tys, txs = np.nonzero(tpl_rgba[..., 3] > 40)
    ty0, ty1 = int(tys.min()), int(tys.max()) + 1
    tx0, tx1 = int(txs.min()), int(txs.max()) + 1
    tpl_patch = tpl_u8[ty0:ty1, tx0:tx1]
    ph_p, pw_p = tpl_patch.shape[:2]

    best_corr = -1.0
    best_fit = (1.0, placed[0], placed[1])
    for k in np.linspace(0.93, 1.07, 29):
        sw = max(8, round(pw_p * float(k)))
        sh = max(8, round(ph_p * float(k)))
        if sw >= cw - 16 or sh >= ch - 16:
            continue
        scaled_tpl = cv2.resize(tpl_patch, (sw, sh), interpolation=cv2.INTER_AREA if k < 1.0 else cv2.INTER_CUBIC)
        res = cv2.matchTemplate(work, scaled_tpl, cv2.TM_CCOEFF_NORMED)
        _, max_val, _, max_loc = cv2.minMaxLoc(res)
        if max_val > best_corr:
            cand_ox = round(max_loc[0] - tx0 * float(k))
            cand_oy = round(max_loc[1] - ty0 * float(k))
            best_corr = float(max_val)
            best_fit = (float(k), int(cand_ox), int(cand_oy))

    best_k, fit_ox, fit_oy = best_fit
    target_ox, target_oy = placed[0], placed[1]
    dst_x_grid, dst_y_grid = np.meshgrid(np.arange(cw, dtype=np.float32), np.arange(ch, dtype=np.float32))
    map_x = fit_ox + (dst_x_grid - target_ox) * best_k
    map_y = fit_oy + (dst_y_grid - target_oy) * best_k
    aligned_rgb = cv2.remap(
        work,
        map_x,
        map_y,
        interpolation=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=tuple(int(round(v)) for v in bg),
    )

    # 实心保护遮罩：v2 完整保护人物 + 1.0x 原长黑银符文剑（防黑银剑格被暗底减法镂空！）
    char_alpha_map = np.zeros((ch, cw), dtype=np.float32)
    solid_src = actor_cell_arr.copy()
    if not protect_full_sword:
        solid_src[:, max(0, tpl_w - 6):, 3] = 0
    y_a0, y_a1 = max(0, target_oy), min(ch, target_oy + ph)
    x_a0, x_a1 = max(0, target_ox), min(cw, target_ox + pw)
    char_alpha_map[y_a0:y_a1, x_a0:x_a1] = (
        solid_src[y_a0 - target_oy:y_a1 - target_oy, x_a0 - target_ox:x_a1 - target_ox, 3].astype(np.float32) / 255.0
    )

    char_dil = cv2.dilate((char_alpha_map > 0.2).astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
    rgb_f = aligned_rgb.astype(np.float32)
    darker_ink = char_dil & (rgb_f.mean(axis=2) < float(bg.mean()) - 6.0)

    # 暗棚光学解混
    diff = np.maximum(0.0, rgb_f - bg[None, None, :])
    denom = np.maximum(255.0 - bg[None, None, :], 1.0)
    a_raw = np.max(diff / denom, axis=2)
    violet_chroma = np.maximum(0.0, (rgb_f[..., 2] - bg[2]) - 0.65 * np.abs(rgb_f[..., 1] - bg[1])) / 165.0
    a_opt = np.maximum(a_raw, violet_chroma)

    noise_floor = 0.026
    a_slash = np.clip((a_opt - noise_floor) / (1.0 - noise_floor), 0.0, 1.0)
    a_slash = np.where(a_slash < 0.12, a_slash * (a_slash / 0.12) ** 0.35, a_slash)

    edge_fade = np.ones((ch, cw), dtype=np.float32)
    for d in range(10):
        f = d / 10.0
        edge_fade[d, :] = np.minimum(edge_fade[d, :], f)
        edge_fade[ch - 1 - d, :] = np.minimum(edge_fade[ch - 1 - d, :], f)
        edge_fade[:, d] = np.minimum(edge_fade[:, d], f)
        edge_fade[:, cw - 1 - d] = np.minimum(edge_fade[:, cw - 1 - d], f)
    a_slash *= edge_fade

    safe_a = np.maximum(a_slash[..., None], 0.045)
    unmixed_fg = np.clip(bg[None, None, :] + (rgb_f - bg[None, None, :]) / safe_a, 0.0, 255.0)

    solid_w = np.clip(np.maximum(char_alpha_map, darker_ink.astype(np.float32) * 0.92), 0.0, 1.0)
    final_a = np.clip(np.maximum(solid_w, a_slash), 0.0, 1.0)
    final_rgb = solid_w[..., None] * rgb_f + (1.0 - solid_w[..., None]) * unmixed_fg

    fg_mask = (final_a > 0.015).astype(np.uint8)
    n_lbl, lbls, stats, _ = cv2.connectedComponentsWithStats(fg_mask, connectivity=8)
    keep = np.zeros_like(fg_mask, dtype=bool)
    for li in range(1, n_lbl):
        area = int(stats[li, cv2.CC_STAT_AREA])
        if area >= 24 or float(final_a[lbls == li].max()) >= 0.25:
            keep |= (lbls == li)
    final_a = np.where(keep, final_a, 0.0)

    out_rgba = np.zeros((ch, cw, 4), dtype=np.uint8)
    out_rgba[..., :3] = np.clip(np.round(final_rgb), 0, 255).astype(np.uint8)
    out_rgba[..., 3] = np.clip(np.round(final_a * 255.0), 0, 255).astype(np.uint8)
    out_rgba = bleed_transparent_rgb(out_rgba, solid_thresh=180)
    return Image.fromarray(out_rgba), round(best_corr, 4), round(best_k, 4)


def unpack_sheet(
    lay_fp: Path,
    gen_fp: Path,
    meta_list: list[tuple[str, str, str]],
    actor_arr: np.ndarray,
    protect_full_sword: bool,
) -> list[dict]:
    lay = json.loads(lay_fp.read_text(encoding="utf-8"))
    W, H = int(lay["size"][0]), int(lay["size"][1])
    s = float(lay["scale"])
    src = Image.open(gen_fp).convert("RGB")
    if src.size != (W, H):
        src = src.resize((W, H), Image.Resampling.LANCZOS)
    src_arr = np.asarray(src)

    raw_items = []
    for idx, (code, title, subtitle) in enumerate(meta_list):
        fr = lay["frames"][idx]
        cx0, cy0, cw, ch = [int(v) for v in fr["cell"]]
        placed_global = [int(v) for v in fr["placed"]]
        placed_local = [placed_global[0] - cx0, placed_global[1] - cy0, placed_global[2], placed_global[3]]
        bbox = [int(v) for v in fr["bbox"]]

        cell_rgb = src_arr[cy0:cy0 + ch, cx0:cx0 + cw]
        cell_rgba_im, corr, best_k = unmix_dark_studio_cell(
            cell_rgb, actor_arr, placed_local, bbox, protect_full_sword=protect_full_sword
        )

        sheet_placed = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        sheet_placed.paste(cell_rgba_im, (cx0, cy0))

        ox = placed_global[0] - bbox[0] * s
        oy = placed_global[1] - bbox[1] * s
        raw_items.append({
            "code": code,
            "title": title,
            "subtitle": subtitle,
            "corr": corr,
            "fit_scale": best_k,
            "scale": s,
            "orig_size": [int(fr["orig_size"][0]), int(fr["orig_size"][1])],
            "orig_pivot": [float(fr["orig_pivot"][0]), float(fr["orig_pivot"][1])],
            "_placed": sheet_placed,
            "_o": (ox, oy),
        })

    need = 0.0
    for r in raw_items:
        ox, oy = r["_o"]
        w, h = r["orig_size"]
        a = np.asarray(r["_placed"])[..., 3] > 8
        ys, xs = np.nonzero(a)
        u0, u1 = (float(xs.min()) - ox) / s, (float(xs.max()) + 1.0 - ox) / s
        v0, v1 = (float(ys.min()) - oy) / s, (float(ys.max()) + 1.0 - oy) / s
        need = max(need, -u0, u1 - w, -v0, v1 - h)

    pad = int(np.ceil(max(need, 0.0))) + 6
    out_styles: list[dict] = []

    for r in raw_items:
        ox, oy = r["_o"]
        w, h = r["orig_size"]
        crop_box = (ox - pad * s, oy - pad * s, ox + (w + pad) * s, oy + (h + pad) * s)
        fr_im = r["_placed"].transform((w + 2 * pad, h + 2 * pad), Image.Transform.EXTENT, crop_box, Image.Resampling.BICUBIC)
        fr_arr = bleed_transparent_rgb(np.asarray(fr_im), solid_thresh=180)

        H_fr, W_fr = fr_arr.shape[:2]
        actor_pad = np.zeros((H_fr, W_fr), dtype=bool)
        actor_pad[pad:pad + h, pad:pad + w] = actor_arr[..., 3] > 80
        if not protect_full_sword:
            yy_grid, xx_grid = np.ogrid[:H_fr, :W_fr]
            piv_x = float(r["orig_pivot"][0]) + pad
            piv_y = float(r["orig_pivot"][1]) + pad
            actor_pad &= (xx_grid <= piv_x + 115)

        r_ch = fr_arr[..., 0].astype(np.int32)
        g_ch = fr_arr[..., 1].astype(np.int32)
        b_ch = fr_arr[..., 2].astype(np.int32)

        in_vfx = (~actor_pad) & (fr_arr[..., 3] > 0)
        vfx_white = in_vfx & (np.maximum(g_ch, b_ch) >= 185) & (np.minimum(r_ch, np.minimum(g_ch, b_ch)) >= 135)
        b_boost = np.maximum(b_ch, np.minimum(255, np.maximum(r_ch, g_ch) + 14))
        b_ch = np.where(vfx_white, np.maximum(b_boost, 226), b_ch)
        r_ch = np.where(vfx_white, np.minimum(r_ch, b_ch - 16), r_ch)
        g_ch = np.where(vfx_white, np.minimum(g_ch, b_ch - 42), g_ch)

        vfx_vio = in_vfx & (~vfx_white) & (b_ch >= 110) & (b_ch >= g_ch + 12)
        scale_up = np.where(b_ch < 168, 168.0 / np.maximum(b_ch, 1), 1.0)
        b_v = np.clip(np.round(b_ch * scale_up), 168, 255).astype(np.int32)
        r_v = np.minimum(np.clip(np.round(r_ch * scale_up), 0, 255).astype(np.int32), b_v - 16)
        g_v = np.minimum(np.clip(np.round(g_ch * scale_up), 0, 255).astype(np.int32), b_v - 42)
        b_ch = np.where(vfx_vio, b_v, b_ch)
        r_ch = np.where(vfx_vio, np.maximum(r_v, 0), r_ch)
        g_ch = np.where(vfx_vio, np.maximum(g_v, 0), g_ch)

        fr_arr[..., 0] = r_ch.astype(np.uint8)
        fr_arr[..., 1] = g_ch.astype(np.uint8)
        fr_arr[..., 2] = b_ch.astype(np.uint8)
        fr_arr = bleed_transparent_rgb(fr_arr, solid_thresh=180)

        fname = f"{r['code'].lower()}.png"
        Image.fromarray(fr_arr).save(STAGE_ABS / fname)
        out_styles.append({
            "code": r["code"],
            "title": r["title"],
            "subtitle": r["subtitle"],
            "asset": f"{STAGE_REL}/{fname}",
            "width": w + 2 * pad,
            "height": h + 2 * pad,
            "pivotX": round(r["orig_pivot"][0] + pad, 3),
            "pivotY": round(r["orig_pivot"][1] + pad, 3),
            "corr": r["corr"],
            "fit_scale": r["fit_scale"],
        })
        print(f"{r['code']} {r['title']}: corr={r['corr']:.4f}, scale={r['fit_scale']:.4f}, size={w + 2 * pad}x{h + 2 * pad}")

    return out_styles


def main() -> None:
    STAGE_ABS.mkdir(parents=True, exist_ok=True)
    actor_arr = load_fleck_free_actor()

    v2_styles = unpack_sheet(
        WORK_DIR / "输入_排版_v2.json",
        WORK_DIR / "生图_真刀光_v2_R1至R4.png",
        V2_META,
        actor_arr,
        protect_full_sword=True,
    )
    v1_styles = unpack_sheet(
        WORK_DIR / "输入_排版.json",
        WORK_DIR / "生图_真刀光_S1至S4.png",
        V1_META,
        actor_arr,
        protect_full_sword=False,
    )

    manifest = {
        "clip": "attack_1",
        "frame_index": 5,
        "styles": v2_styles + v1_styles,
        "v2_styles": v2_styles,
        "v1_styles": v1_styles,
    }
    (WORK_DIR / "manifest_true_slash.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Unpacked R1-R4 + S1-S4 -> {STAGE_ABS}")


if __name__ == "__main__":
    main()
