#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
解包全部 24 张 R3 深暗灰摄影棚底 (#141620) 图集 (S01..S24)，并完整组装、挂载主角「朔」全部 16 套战斗挥斩招式
（及 5 套共享别名剪辑 air_slash / strong_attack / dash_right / dash_left / guard_start）：
1. 全方向通用的 #141620 暗棚光学线性解混 + TM_CCOEFF_NORMED 亚像素角色刚体对齐（锁死 385px 恒定身高与零脚底漂移）。
2. 利用每格专属 body_rgba_XX.png 100% 保护黑衣短发与 1.0× 原长黑银符文直剑实心不透明，外部 R3 刀光实现 0%..100% 蝉翼连续半透明。
3. 外部刀光像素对齐 char_light.gdshader 的 OL_TAP 免描边与 slash_emissive 自发光色域（B >= 168..226, B-G >= 42, B-R >= 16）。
4. 100% 保持 battle.json 原有 fps / loop / durationTicks / source_* 剪辑零改动。
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from codex_redraw_map_cv2 import bleed_transparent_rgb  # noqa: E402
import overhaul_all_player_actions as OV  # noqa: E402

ASSETS = ROOT / "assets"
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\R3全招式真刀光_20261115"
BACKUP_ORIG_FP = ROOT / r"docs\视觉设计\角色动作\全动作精修与张力升级_20261114\backup_animations_before_overhaul.json"
V2_MANIFEST_FP = ROOT / r"docs\视觉设计\角色动作\真刀光样板_20261115\manifest_true_slash.json"

STAGE_REL_ROOT = "image/desktop-actions-hd/r3_true_slash_20261115"
STAGE_ABS_ROOT = ASSETS / "image" / "desktop-actions-hd" / "r3_true_slash_20261115"


def unmix_single_cell_to_world(
    cell_rgb: np.ndarray,
    body_rgba: np.ndarray,
    placed_cell: list[int],
    orig_pivot: list[float],
    scale: float,
) -> tuple[np.ndarray, float, float, float, float, float, float]:
    """
    将单格 #141620 暗底生图解混并还原回 1:1 世界像素坐标系：
    返回 (trimmed_rgba, world_w, world_h, world_px, world_py, best_corr, best_k)
    """
    ch, cw = cell_rgb.shape[:2]
    work = cell_rgb.copy()

    # 1. 四周内侧采样暗棚底色（35% 暗分位中值，不受任意方向刀光干扰）
    inner_border = np.concatenate([
        work[10:26, 10:cw - 10].reshape(-1, 3),
        work[ch - 26:ch - 10, 10:cw - 10].reshape(-1, 3),
        work[10:ch - 10, 10:28].reshape(-1, 3),
        work[10:ch - 10, cw - 28:cw - 10].reshape(-1, 3),
    ], axis=0)
    lums = inner_border.mean(axis=1)
    dark_samples = inner_border[lums <= np.percentile(lums, 35)]
    bg = np.median(dark_samples, axis=0).astype(np.float32)

    # 抹除四周 8px 黄框线
    bg_u8 = np.round(bg).astype(np.uint8)
    work[:8, :] = bg_u8
    work[ch - 8:, :] = bg_u8
    work[:, :8] = bg_u8
    work[:, cw - 8:] = bg_u8

    local_ox, local_oy, pw, ph = [int(v) for v in placed_cell]
    orig_px, orig_py = float(orig_pivot[0]), float(orig_pivot[1])

    body_cell_im = Image.fromarray(body_rgba).resize((pw, ph), Image.Resampling.LANCZOS)
    body_cell_arr = np.asarray(body_cell_im)

    # 2. 基于「去刀光纯人物剪影」跨模态匹配 (TM_CCOEFF_NORMED)，彻底免疫局部刀光遮挡与重绘阴影差异！
    # 在生图 work 中：#141620 底色与电光紫/冷白外圈刀光均不具有暗墨线 (lum < bg-5) 或暖肤/灰褐丝袜色相
    w_f0 = work.astype(np.float32)
    bg_dist0 = np.max(np.abs(w_f0 - bg[None, None, :]), axis=2)
    is_dark_ink0 = (w_f0.mean(axis=2) < float(bg.mean()) - 4.8) | (w_f0[..., 2] < float(bg[2]) - 5.8)
    is_warm_or_dark_cloth0 = (bg_dist0 > 9.5) & (
        is_dark_ink0
        | ((w_f0[..., 0] >= w_f0[..., 2] - 4.0) & (w_f0.max(axis=2) < 235.0))
        | ((w_f0.max(axis=2) < 120.0) & ((w_f0[..., 2] - w_f0[..., 1]) < 28.0))
    )
    gen_char_sil = cv2.morphologyEx(
        is_warm_or_dark_cloth0.astype(np.uint8) * 255,
        cv2.MORPH_CLOSE,
        cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)),
    )
    # 剔除四周孤立小点并模糊成平滑概率场供亚像素相关匹配
    gen_sil_f = cv2.GaussianBlur(gen_char_sil.astype(np.float32) / 255.0, (0, 0), 2.2)

    # 清理模板人物遮罩：仅保留真正属于人物躯干头靴的主连通域（过滤原视频残留边角碎块）
    tpl_bin_raw = (body_cell_arr[..., 3] > 80).astype(np.uint8)
    # 同时排除模板里贴近 #141620 暗灰的旧刀光外缘残壳
    tpl_rgb_f = body_cell_arr[..., :3].astype(np.float32)
    tpl_not_ghost = (np.max(np.abs(tpl_rgb_f - bg[None, None, :]), axis=2) > 7.5) | (
        (tpl_rgb_f.mean(axis=2) < float(bg.mean()) - 4.5)
    )
    tpl_bin_full = (tpl_bin_raw > 0) & tpl_not_ghost
    piv_cx = orig_px * scale
    piv_cy = orig_py * scale
    yy_c, xx_c = np.mgrid[0:ph, 0:pw].astype(np.float32)
    tpl_core_box = tpl_bin_full & (np.abs(xx_c - piv_cx) <= max(65.0, 145.0 * scale)) & (yy_c >= piv_cy - 415.0 * scale) & (yy_c <= piv_cy + 28.0 * scale)
    tpl_bin = tpl_core_box if int(tpl_core_box.sum()) >= 300 else tpl_bin_full

    ys_t, xs_t = np.nonzero(tpl_bin)
    if len(xs_t) >= 64:
        ty0, ty1 = int(ys_t.min()), int(ys_t.max()) + 1
        tx0, tx1 = int(xs_t.min()), int(xs_t.max()) + 1
        tpl_sil_patch = cv2.GaussianBlur(tpl_bin[ty0:ty1, tx0:tx1].astype(np.float32), (0, 0), 2.2)
        ph_p, pw_p = tpl_sil_patch.shape[:2]

        best_corr = -1.0
        best_fit = (1.0, local_ox, local_oy)
        max_dx = max(28, round(cw * 0.09))
        max_dy = max(28, round(ch * 0.09))
        for k in np.linspace(0.93, 1.07, 29):
            sw = max(8, round(pw_p * float(k)))
            sh = max(8, round(ph_p * float(k)))
            if sw >= cw - 16 or sh >= ch - 16:
                continue
            scaled_tpl = cv2.resize(tpl_sil_patch, (sw, sh), interpolation=cv2.INTER_AREA if k < 1.0 else cv2.INTER_CUBIC)
            res = cv2.matchTemplate(gen_sil_f, scaled_tpl, cv2.TM_CCOEFF_NORMED)
            # 仅在导引位置合理邻域内搜索峰值，彻底杜绝跨格误跳
            exp_mx = round(local_ox + tx0 * float(k))
            exp_my = round(local_oy + ty0 * float(k))
            rx0 = max(0, exp_mx - max_dx)
            ry0 = max(0, exp_my - max_dy)
            rx1 = min(res.shape[1], exp_mx + max_dx + 1)
            ry1 = min(res.shape[0], exp_my + max_dy + 1)
            if rx1 <= rx0 or ry1 <= ry0:
                continue
            sub_res = res[ry0:ry1, rx0:rx1]
            _, max_val, _, max_loc = cv2.minMaxLoc(sub_res)
            if max_val > best_corr:
                cand_ox = round((rx0 + max_loc[0]) - tx0 * float(k))
                cand_oy = round((ry0 + max_loc[1]) - ty0 * float(k))
                best_corr = float(max_val)
                best_fit = (float(k), int(cand_ox), int(cand_oy))

        best_k, fit_ox, fit_oy = best_fit
        if best_corr < 0.52:
            best_k, fit_ox, fit_oy = 1.0, local_ox, local_oy
    else:
        best_corr = 1.0
        best_k, fit_ox, fit_oy = 1.0, local_ox, local_oy

    dst_x_grid, dst_y_grid = np.meshgrid(np.arange(cw, dtype=np.float32), np.arange(ch, dtype=np.float32))
    map_x = fit_ox + (dst_x_grid - local_ox) * best_k
    map_y = fit_oy + (dst_y_grid - local_oy) * best_k
    aligned_rgb = cv2.remap(
        work,
        map_x,
        map_y,
        interpolation=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=tuple(int(round(v)) for v in bg),
    )

    # 3. 直接在生图 aligned_rgb 上自提取 100% 严丝合缝的人物+1.0×黑银直剑实心遮罩（彻底根除旧底图暗块与靴子错位漏底！）
    rgb_f = aligned_rgb.astype(np.float32)
    bg_dist = np.max(np.abs(rgb_f - bg[None, None, :]), axis=2)

    # 粗空间保护包络：用完整未截宽的 tpl_bin_full 向外宽容膨胀，100% 覆盖大跨步右靴与剑尖！
    coarse_prior = np.zeros((ch, cw), dtype=np.uint8)
    y_a0, y_a1 = max(0, local_oy), min(ch, local_oy + ph)
    x_a0, x_a1 = max(0, local_ox), min(cw, local_ox + pw)
    coarse_prior[y_a0:y_a1, x_a0:x_a1] = tpl_bin_full[
        y_a0 - local_oy:y_a1 - local_oy, x_a0 - local_ox:x_a1 - local_ox
    ].astype(np.uint8)
    coarse_env = cv2.dilate(coarse_prior, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (55, 55))) > 0

    # A) 纯正中性暗墨描边、黑衣、黑靴、黑银剑柄（B 通道显著低于 #141620 的 B=32，且排除 B-G>=12 的深靛紫刀光内晕！）
    dark_ink_or_cloth = (rgb_f[..., 2] < float(bg[2]) - 8.0) & ((rgb_f[..., 2] - rgb_f[..., 1]) <= 11.5)
    # B) 暖肤色、褐灰丝袜、银灰甲饰（非电光紫高色度，且明显区别于 #141620 棚底）
    warm_skin_or_stocking = coarse_env & (bg_dist > 11.5) & (
        (rgb_f[..., 0] >= rgb_f[..., 2] - 2.0)
        | ((rgb_f.max(axis=2) < 135.0) & ((rgb_f[..., 2] - rgb_f[..., 1]) < 16.0))
    )

    seed_solid = ((dark_ink_or_cloth & coarse_env) | warm_skin_or_stocking).astype(np.uint8) * 255
    closed_solid = cv2.morphologyEx(seed_solid, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))) > 0
    inv_u8 = (~closed_solid).astype(np.uint8)
    h_ff, w_ff = inv_u8.shape
    ff_mask = np.zeros((h_ff + 2, w_ff + 2), np.uint8)
    ff_work = inv_u8.copy()
    cv2.floodFill(ff_work, ff_mask, (0, 0), 2)
    filled_solid = closed_solid | (ff_work != 2)

    is_pure_studio_bg = (bg_dist <= 8.0) & (~dark_ink_or_cloth)
    solid_char_bool = filled_solid & (~is_pure_studio_bg)
    # 仅保留真正与人物核心躯干相连的大连通域（彻底排除身外任何细碎暗纹）
    char_touch_zone = cv2.dilate(coarse_prior, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21))) > 0
    n_sc, lbl_sc, st_sc, _ = cv2.connectedComponentsWithStats(solid_char_bool.astype(np.uint8), connectivity=8)
    clean_solid_bool = np.zeros_like(solid_char_bool)
    for ci in range(1, n_sc):
        comp = lbl_sc == ci
        if st_sc[ci, cv2.CC_STAT_AREA] >= 180 and np.any(comp & char_touch_zone):
            clean_solid_bool |= comp

    char_alpha_map = cv2.GaussianBlur(clean_solid_bool.astype(np.float32), (0, 0), 0.65)
    darker_ink = clean_solid_bool & dark_ink_or_cloth

    # 4. #141620 暗棚光学线性解混
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

    cell_rgba = np.zeros((ch, cw, 4), dtype=np.uint8)
    cell_rgba[..., :3] = np.clip(np.round(final_rgb), 0, 255).astype(np.uint8)
    cell_rgba[..., 3] = np.clip(np.round(final_a * 255.0), 0, 255).astype(np.uint8)
    cell_rgba = bleed_transparent_rgb(cell_rgba, solid_thresh=180)

    # 5. 将完整单格按 1/scale 还原回 1:1 世界像素（绝不因原图小画框裁断饱满 R3 刀光！）
    world_cw = max(8, round(cw / scale))
    world_ch = max(8, round(ch / scale))
    world_im = Image.fromarray(cell_rgba).resize((world_cw, world_ch), Image.Resampling.BICUBIC)
    world_arr = bleed_transparent_rgb(np.asarray(world_im), solid_thresh=180)

    char_mask_world = np.asarray(
        Image.fromarray((char_alpha_map * 255.0).astype(np.uint8)).resize((world_cw, world_ch), Image.Resampling.BILINEAR)
    ) > 85

    # 6. char_light.gdshader OL_TAP 免描边与 slash_emissive 色域校准
    r_ch = world_arr[..., 0].astype(np.int32)
    g_ch = world_arr[..., 1].astype(np.int32)
    b_ch = world_arr[..., 2].astype(np.int32)

    in_vfx = (~char_mask_world) & (world_arr[..., 3] > 0)
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

    world_arr[..., 0] = r_ch.astype(np.uint8)
    world_arr[..., 1] = g_ch.astype(np.uint8)
    world_arr[..., 2] = b_ch.astype(np.uint8)

    world_px = local_ox / scale + orig_px
    world_py = local_oy / scale + orig_py

    # 紧致裁剪空白透明边以节省显存
    ys_a, xs_a = np.nonzero(world_arr[..., 3] > 2)
    if len(xs_a) > 0:
        tx0 = max(0, int(xs_a.min()) - 8)
        ty0 = max(0, int(ys_a.min()) - 8)
        tx1 = min(world_cw, int(xs_a.max()) + 9)
        ty1 = min(world_ch, int(ys_a.max()) + 9)
        world_arr = world_arr[ty0:ty1, tx0:tx1].copy()
        world_px -= tx0
        world_py -= ty0

    world_arr = bleed_transparent_rgb(world_arr, solid_thresh=180)
    h_out, w_out = world_arr.shape[:2]
    return world_arr, float(w_out), float(h_out), round(world_px, 3), round(world_py, 3), round(best_corr, 4), round(best_k, 4)


def make_clean_aihd_pose_frame(hd_entry: tuple) -> tuple[np.ndarray, float, float, float, float]:
    """从 ai-hd 姿态提取无白道、无脚底白三角块的纯净 1:1 世界帧（零模糊滤镜）。"""
    arr, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_entry]
    clean = OV.strip_aihd_white_streaks(arr)
    hb, wb = clean.shape[:2]
    yy_b, xx_b = np.mgrid[0:hb, 0:wb]
    rgb_b = clean[..., :3].astype(np.int16)
    clean[(yy_b > hb - 28) & (rgb_b.min(-1) >= 210)] = 0
    im_1x = Image.fromarray(clean).resize((max(4, round(ww)), max(4, round(wh))), Image.Resampling.LANCZOS)
    out_arr = bleed_transparent_rgb(np.asarray(im_1x), solid_thresh=180)
    return out_arr, float(out_arr.shape[1]), float(out_arr.shape[0]), round(float(wpx), 3), round(float(wpy), 3)


def make_clean_orig_nonslash_frame(
    sprite_cfg: dict,
    fd_orig: dict,
    clip_key: str,
    strip_remnant_slash: bool = False,
) -> tuple[np.ndarray, float, float, float, float]:
    """将无刀光起收招帧输出为独立干净 1:1 PNG（去除地面泥灰烟团与紧致裁剪空白）。"""
    D0, ww, wh, wpx, wpy = OV.load_original_unpadded_base(sprite_cfg, fd_orig)
    H0, W0 = D0.shape[:2]
    sx, sy = W0 / max(ww, 1e-4), H0 / max(wh, 1e-4)
    px0, py0 = wpx * sx, wpy * sy
    strip_dust = (clip_key in OV.GROUND_DUST_CLIPS) or (clip_key in ("attack_2", "attack_3"))
    D_clean = OV.clean_stray_and_muddy_dust(D0.copy(), ground_y_px=py0, strip_muddy_dust=strip_dust)
    yy0, xx0 = np.mgrid[0:H0, 0:W0]
    if clip_key in ("attack_2", "attack_3"):
        D_clean[(xx0 < px0 - 185 * sx) | (xx0 > px0 + 700 * sx)] = 0

    if strip_remnant_slash:
        rgb = D_clean[..., :3].astype(np.int16)
        mx = rgb.max(-1)
        ch = mx - rgb.min(-1)
        skin_s = (
            OV.compute_skin_shield(D_clean)
            & (np.abs(xx0 - px0) < 54 * sx)
            & (yy0 > py0 - 325 * sy)
            & (yy0 < py0 - 52 * sy)
            & (rgb.min(-1) < 224)
        )
        vest_z = (np.abs(xx0 - px0) < 26 * sx) & (yy0 > py0 - 226 * sy) & (yy0 < py0 - 180 * sy)
        rem = (D_clean[..., 3] > 20) & (~skin_s) & (~vest_z) & (mx >= 165) & (ch <= 48)
        D_clean[rem] = 0

    D_clean = OV.AIVfxLibrary._clean_tiny_isolated_specks(D_clean, min_keep_area=55)
    im_1x = Image.fromarray(D_clean).resize((max(4, round(ww)), max(4, round(wh))), Image.Resampling.LANCZOS)
    arr_1x = np.asarray(im_1x)

    ys, xs = np.nonzero(arr_1x[..., 3] > 4)
    px_1x, py_1x = float(wpx), float(wpy)
    if len(xs) > 0:
        bx0 = max(0, int(xs.min()) - 6)
        by0 = max(0, int(ys.min()) - 6)
        bx1 = min(arr_1x.shape[1], int(xs.max()) + 7)
        by1 = min(arr_1x.shape[0], int(ys.max()) + 7)
        arr_1x = arr_1x[by0:by1, bx0:bx1].copy()
        px_1x -= bx0
        py_1x -= by0

    arr_1x = bleed_transparent_rgb(arr_1x, solid_thresh=180)
    return arr_1x, float(arr_1x.shape[1]), float(arr_1x.shape[0]), round(px_1x, 3), round(py_1x, 3)


def save_stage_frame(
    clip_key: str,
    fi: int,
    arr: np.ndarray,
    ww: float,
    wh: float,
    px: float,
    py: float,
    duration_ticks: int,
) -> dict[str, Any]:
    cdir = STAGE_ABS_ROOT / clip_key
    cdir.mkdir(parents=True, exist_ok=True)
    fname = f"frame_{fi:05d}.png"
    Image.fromarray(arr).save(cdir / fname)
    return {
        "asset": f"{STAGE_REL_ROOT}/{clip_key}/{fname}",
        "width": round(ww, 3) if ww % 1 else int(ww),
        "height": round(wh, 3) if wh % 1 else int(wh),
        "pivotX": round(px, 3),
        "pivotY": round(py, 3),
        "durationTicks": duration_ticks,
    }


def copy_existing_hd_frame(
    clip_key: str,
    fi: int,
    src_fd: dict[str, Any],
    duration_ticks: int,
) -> dict[str, Any]:
    cdir = STAGE_ABS_ROOT / clip_key
    cdir.mkdir(parents=True, exist_ok=True)
    fname = f"frame_{fi:05d}.png"
    shutil.copy2(ASSETS / src_fd["asset"], cdir / fname)
    return {
        "asset": f"{STAGE_REL_ROOT}/{clip_key}/{fname}",
        "width": src_fd["width"],
        "height": src_fd["height"],
        "pivotX": src_fd["pivotX"],
        "pivotY": src_fd["pivotY"],
        "durationTicks": duration_ticks,
    }


def main() -> None:
    STAGE_ABS_ROOT.mkdir(parents=True, exist_ok=True)

    battle_fp = ASSETS / "data/battle.json"
    battle = json.loads(battle_fp.read_text(encoding="utf-8"))
    sprite_cfg = battle["characters"][0]["sprite"]
    cur_anims = sprite_cfg["animations"]

    backup_r3_fp = WORK_ROOT / "backup_animations_before_r3.json"
    if not backup_r3_fp.exists():
        backup_r3_fp.write_text(json.dumps(cur_anims, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"Backed up current battle.json animations -> {backup_r3_fp.name}")

    orig_anims = json.loads(BACKUP_ORIG_FP.read_text(encoding="utf-8"))
    ai_hd_data = json.loads((ASSETS / "data/ai-hd-visuals.json").read_text(encoding="utf-8"))
    sheets_index = json.loads((WORK_ROOT / "sheets_index.json").read_text(encoding="utf-8"))

    # 1. 解包全部 24 张 R3 生图 -> unpacked[(clip_key, frame_idx)] = (arr, ww, wh, px, py)
    unpacked: dict[tuple[str, int], tuple[np.ndarray, float, float, float, float]] = {}
    unpack_stats: list[dict[str, Any]] = []

    for item in sheets_index:
        sid = item["sheet_id"]
        s_dir = WORK_ROOT / item["dir"]
        lay = json.loads((s_dir / "输入_排版.json").read_text(encoding="utf-8"))
        gen_fp = s_dir / "生图_R3.png"
        if not gen_fp.exists():
            raise FileNotFoundError(f"Missing generated sheet: {gen_fp}")

        W_s, H_s = int(lay["size"][0]), int(lay["size"][1])
        scale = float(lay["scale"])
        gen_im = Image.open(gen_fp).convert("RGB")
        if gen_im.size != (W_s, H_s):
            gen_im = gen_im.resize((W_s, H_s), Image.Resampling.LANCZOS)
        gen_arr = np.asarray(gen_im)

        corrs = []
        for fr in lay["frames"]:
            cx0, cy0, cw, ch = [int(v) for v in fr["cell"]]
            cell_rgb = gen_arr[cy0:cy0 + ch, cx0:cx0 + cw]
            body_rgba = np.asarray(Image.open(s_dir / fr["body_rgba_file"]).convert("RGBA"))
            arr_w, ww, wh, px, py, corr, best_k = unmix_single_cell_to_world(
                cell_rgb, body_rgba, fr["placed_cell"], fr["orig_pivot"], scale
            )
            unpacked[(fr["clip"], int(fr["frame_idx"]))] = (arr_w, ww, wh, px, py)
            corrs.append(corr)
            unpack_stats.append({
                "sheet_id": sid,
                "clip": fr["clip"],
                "frame_idx": int(fr["frame_idx"]),
                "corr": corr,
                "fit_scale": best_k,
                "world_size": [round(ww), round(wh)],
            })
        print(
            f"[UNPACK {sid}] {item['clip']:17s} ({len(corrs)}f) | "
            f"corr min={min(corrs):.4f} avg={sum(corrs)/len(corrs):.4f}"
        )

    # 载入已批准定稿的 R3 母本帧 (attack_1 f05)
    v2_manifest = json.loads(V2_MANIFEST_FP.read_text(encoding="utf-8"))
    r3_master_meta = next(st for st in v2_manifest["v2_styles"] if st["code"] == "R3")

    # 预备份 redraw_20261115 纯净非刀光帧字典（若当前已是 r3_true_slash，可从 backup_r3_fp 取）
    prev_anims = json.loads(backup_r3_fp.read_text(encoding="utf-8"))

    primary_16 = [
        "attack_1", "attack_2", "attack_3", "attack_up",
        "air_attack_1", "air_attack_2", "air_attack_3",
        "dash_right_video", "dash_left_video",
        "parry", "guard_hit_1", "guard_hit_2", "guard_hit_3",
        "parry_react_1", "parry_react_2", "parry_react_3",
    ]

    for ck in primary_16:
        orig_frames = orig_anims[ck]["frames"]
        cur_frames = cur_anims[ck]["frames"]
        prev_frames = prev_anims[ck]["frames"]
        n_f = len(cur_frames)
        hd_map = OV.load_ai_hd_pose_map(ai_hd_data, ck)
        new_frames: list[dict[str, Any]] = []

        for fi in range(n_f):
            dt = int(cur_frames[fi]["durationTicks"])

            # 1) 直接命中本轮 R3 解包帧
            if (ck, fi) in unpacked:
                arr_u, ww, wh, px, py = unpacked[(ck, fi)]
                new_frames.append(save_stage_frame(ck, fi, arr_u, ww, wh, px, py, dt))
                continue

            # 2) attack_1 f05 -> 直接挂载 R3 母本 r3.png
            if ck == "attack_1" and fi == 5:
                new_frames.append(copy_existing_hd_frame(ck, fi, r3_master_meta, dt))
                continue

            # 3) attack_1 与 parry_react_1 的非刀光帧 -> 沿用已高清重画的 redraw_20261115 帧
            if ck in ("attack_1", "parry_react_1"):
                p_fd = prev_frames[fi]
                if "redraw_20261115" in str(p_fd.get("asset", "")):
                    new_frames.append(copy_existing_hd_frame(ck, fi, p_fd, dt))
                    continue

            # 4) dash_right_video 非直出过渡/收势帧（避免原视频坏帧，100% 纯 AI 高清帧）
            if ck == "dash_right_video":
                if fi == 2:
                    arr_u, ww, wh, px, py = unpacked[(ck, 1)]
                    new_frames.append(save_stage_frame(ck, fi, arr_u, ww, wh, px, py, dt))
                    continue
                if fi == 5:
                    arr_u, ww, wh, px, py = unpacked[(ck, 4)]
                    new_frames.append(save_stage_frame(ck, fi, arr_u, ww, wh, px, py, dt))
                    continue
                if fi == 7:
                    arr_u, ww, wh, px, py = unpacked[(ck, 6)]
                    new_frames.append(save_stage_frame(ck, fi, arr_u, ww, wh, px, py, dt))
                    continue
                k_pick = 0 if fi == 0 else (15 if fi <= 18 else 19)
                arr_h, ww, wh, px, py = make_clean_aihd_pose_frame(hd_map[k_pick])
                new_frames.append(save_stage_frame(ck, fi, arr_h, ww, wh, px, py, dt))
                continue

            # 5) dash_left_video 非直出过渡/收势帧（避免原视频坏帧，100% 纯 AI 高清帧）
            if ck == "dash_left_video":
                if fi == 3:
                    arr_u, ww, wh, px, py = unpacked[(ck, 2)]
                    new_frames.append(save_stage_frame(ck, fi, arr_u, ww, wh, px, py, dt))
                    continue
                if fi == 5:
                    arr_u, ww, wh, px, py = unpacked[(ck, 4)]
                    new_frames.append(save_stage_frame(ck, fi, arr_u, ww, wh, px, py, dt))
                    continue
                if fi == 7:
                    arr_u, ww, wh, px, py = unpacked[(ck, 6)]
                    new_frames.append(save_stage_frame(ck, fi, arr_u, ww, wh, px, py, dt))
                    continue
                k_pick = 0 if fi == 0 else (17 if fi <= 18 else 20)
                arr_h, ww, wh, px, py = make_clean_aihd_pose_frame(hd_map[k_pick])
                new_frames.append(save_stage_frame(ck, fi, arr_h, ww, wh, px, py, dt))
                continue

            # 6) parry / guard_hit_1 / parry_react_3 的纯立姿/架盾起收招帧 -> 采用纯净 ai-hd 姿态
            if ck in ("parry", "guard_hit_1", "parry_react_3") and len(hd_map) > 0:
                nearest_k = min(hd_map.keys(), key=lambda k: abs(k - fi))
                # parry_react_3 避开带白团的 k=8
                if ck == "parry_react_3" and nearest_k == 8:
                    nearest_k = 11
                arr_h, ww, wh, px, py = make_clean_aihd_pose_frame(hd_map[nearest_k])
                new_frames.append(save_stage_frame(ck, fi, arr_h, ww, wh, px, py, dt))
                continue

            # 7) 其余无刀光起收招帧 -> 净除烟尘与残余白点后独立成帧
            strip_rem = (ck == "attack_3" and fi in (12, 26))
            arr_o, ww, wh, px, py = make_clean_orig_nonslash_frame(sprite_cfg, orig_frames[fi], ck, strip_remnant_slash=strip_rem)
            new_frames.append(save_stage_frame(ck, fi, arr_o, ww, wh, px, py, dt))

        cur_anims[ck]["frames"] = new_frames
        print(f"[INSTALLED] {ck:18s} -> {len(new_frames)} frames")

    # 同步更新 5 套共享别名剪辑（保持各自帧长与 durationTicks 100% 不变）
    alias_pairs = [
        ("air_slash", "air_attack_1"),
        ("dash_left", "dash_left_video"),
        ("guard_start", "parry"),
    ]
    for alias_k, src_k in alias_pairs:
        if alias_k in cur_anims:
            af_list = cur_anims[alias_k]["frames"]
            sf_list = cur_anims[src_k]["frames"]
            for i in range(min(len(af_list), len(sf_list))):
                dt = af_list[i]["durationTicks"]
                af_list[i] = dict(sf_list[i])
                af_list[i]["durationTicks"] = dt
            print(f"[SYNC ALIAS] {alias_k:17s} <- {src_k} ({len(af_list)}f)")

    # strong_attack (32f: 前 31 帧同 attack_up，最后 1 帧收势独立干净化)
    if "strong_attack" in cur_anims:
        sa_frames = cur_anims["strong_attack"]["frames"]
        au_frames = cur_anims["attack_up"]["frames"]
        for i in range(min(len(sa_frames), len(au_frames))):
            dt = sa_frames[i]["durationTicks"]
            sa_frames[i] = dict(au_frames[i])
            sa_frames[i]["durationTicks"] = dt
        if len(sa_frames) > len(au_frames):
            for i in range(len(au_frames), len(sa_frames)):
                dt = sa_frames[i]["durationTicks"]
                arr_o, ww, wh, px, py = make_clean_orig_nonslash_frame(
                    sprite_cfg, orig_anims["strong_attack"]["frames"][i], "strong_attack"
                )
                sa_frames[i] = save_stage_frame("strong_attack", i, arr_o, ww, wh, px, py, dt)
        print(f"[SYNC ALIAS] {'strong_attack':17s} <- attack_up ({len(sa_frames)}f)")

    # dash_right (35f: 前 22 帧同 dash_right_video，22..34 采用纯净 ai-hd 滑停收招帧)
    if "dash_right" in cur_anims:
        dr_frames = cur_anims["dash_right"]["frames"]
        drv_frames = cur_anims["dash_right_video"]["frames"]
        hd_dr = OV.load_ai_hd_pose_map(ai_hd_data, "dash_right_video")
        for i in range(min(len(dr_frames), len(drv_frames))):
            dt = dr_frames[i]["durationTicks"]
            dr_frames[i] = dict(drv_frames[i])
            dr_frames[i]["durationTicks"] = dt
        arr_tail, ww_t, wh_t, px_t, py_t = make_clean_aihd_pose_frame(hd_dr[19])
        for i in range(len(drv_frames), len(dr_frames)):
            dt = dr_frames[i]["durationTicks"]
            dr_frames[i] = save_stage_frame("dash_right", i, arr_tail, ww_t, wh_t, px_t, py_t, dt)
        print(f"[SYNC ALIAS] {'dash_right':17s} <- dash_right_video ({len(dr_frames)}f)")

    battle_fp.write_text(json.dumps(battle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (WORK_ROOT / "unpack_r3_stats.json").write_text(json.dumps(unpack_stats, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"All 16 combat moves + 5 aliases mounted into {battle_fp}!")


if __name__ == "__main__":
    main()
