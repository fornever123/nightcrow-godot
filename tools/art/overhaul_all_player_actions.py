#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
全角色 36 套动作统一高清化 · 坏帧根除 · AI 书法刀光升级 · 作画张力微调管线 (V2 终审精修版)
(tools/art/overhaul_all_player_actions.py)

核心原则与 V2 显微镜级修复要点：
1. 100% 保持原版角色五官神貌与不对称发型，全局植入硬性「暖肤色保护盾 (R-B>=9)」与「直剑保护白名单」，
   彻底根绝肤色/剑身被误判为刀光导致的紫脸星芒或直剑变紫槌问题。
2. 根除全部历史坏帧与回归坏帧：
   - parry_react_1: f0..7 接入 11-06 签收帧，f8..15 全量采用 ai-hd 完好帧（根除 f7..9 断腰与 f10..11 断剑尖，星芒前移不挡脸）；
   - parry_react_2: 严禁误删灰调腿部像素，f3..4 保留 fixed 完好双腿、f5 无损修补残腰，仅对 f1,2,6 白刀影重绘书法紫弧；
   - parry_react_3: 全量融合 ai-hd 完好帧（根除 f5..7 吞身黄块、f8..9 裙侧悬浮条与 f13 边缘杂滴，f11 直剑 100% 笔直）；
   - dash_left / dash_left_video / dash_right / dash_right_video: 全序列融合 ai-hd 高清完整角色躯干，彻底消灭原视频
     f5 重影、f6 无头裤腿、f9/f10 悬浮巨型断头、f11/f12 泥褐糊团，配齐 AI 破风紫芒楔形与满弧书法刀光；
   - guard_start / parry: 全量接入 ai-hd 高清帧并完整染紫 f8, f9 下摆白刀弧；
   - charge_hold / charge_slash / death: 专项净除背景暗灰扫描线、扩边消除 T/B/L/R 一刀平裁、消除 f19 黑洞与白锯齿、
     f20..21 升级为紫白冲击轮廓帧、f22..41 升级为银紫冲击波气柱+冷紫星火（告别紫泥滩与黄方块）、death[19..24] 统一为冷紫鸦羽爆裂。
3. 画布贴边自动扩边留白 (Auto-Border Pad + SDF Taper)，根除 air_attack_3[0]、attack_2_recovery、draw 等边界硬截断。
4. 全招式（含非 syncAnimation 的 ranged_1）阶段边界刻度 100.000% 守恒的浮点 durationTicks 缓急重排 + 锁脚底锚点微调。
"""

from __future__ import annotations
import argparse
import base64
import copy
import io
import json
import math
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
BATTLE_JSON = ASSETS / "data" / "battle.json"
AI_HD_JSON = ASSETS / "data" / "ai-hd-visuals.json"

OUT_REL_ROOT = "image/desktop-actions-hd/overhaul_20261114"
OUT_ABS_ROOT = ASSETS / "image" / "desktop-actions-hd" / "overhaul_20261114"
DOC_OUT_DIR = ROOT / "docs" / "视觉设计" / "角色动作" / "全动作精修与张力升级_20261114"

V5_ASSETS_DIR = ROOT / "docs" / "视觉设计" / "角色动作" / "普攻1段与特效大改_20261113" / "v5_ai_assets"
V6_ASSETS_DIR = ROOT / "docs" / "视觉设计" / "角色动作" / "普攻1段与特效大改_20261113" / "v6_ai_assets"
REDRAW_1106_DIR = ROOT / "docs" / "视觉设计" / "角色动作" / "原帧重画_20261106"

sys.path.insert(0, str(Path(__file__).parent))
import recolor_slash as RS  # noqa: E402

V6_TO_WORLD = 409.0 / 427.0
TEXEL_DENSITY = 1.35

# 仅在这几个确有地面烟团的视频连段剪辑中剥离贴地白灰烟尘，绝不触碰弹刀/格挡/待机/移动等剪辑的腿部像素！
GROUND_DUST_CLIPS: Set[str] = {
    "attack_2", "attack_2_start", "attack_2_recovery",
    "attack_3", "strong_attack", "attack_up",
}

# 明确限定允许执行刀光重绘的帧集合（其余持直剑帧 100% 保护原版笔直发光符文剑与五官！）
SLASH_FRAME_WHITELIST: Dict[str, Set[int]] = {
    "guard_hit_1": set(),
    "guard_hit_2": set(),
    "guard_hit_3": set(),
    "parry_react_1": set(),
    "parry_react_2": {1, 2, 6},
    "parry_react_3": {0, 1, 2, 8, 9},
    "guard_start": {8, 9},
    "parry": {8, 9},
    "draw": set(range(21, 39)),
    "sheathe": set(range(8, 14)),
}


# ==============================================================================
# 1. AI 特效母版库加载
# ==============================================================================
class AIVfxLibrary:
    def __init__(self) -> None:
        self.v6_a1_frames: List[np.ndarray] = []
        for i in range(13):
            fp = V6_ASSETS_DIR / "attack_1" / f"a1_{i:02d}.png"
            if fp.exists():
                arr = np.array(Image.open(fp).convert("RGBA"))
                # 净除 a1_05..07 外弧右侧极细微孤立悬浮黑墨点 (area < 95)
                arr = self._clean_tiny_isolated_specks(arr, min_keep_area=95)
                self.v6_a1_frames.append(arr)

        self.dash_wedges: List[np.ndarray] = []
        for idx in [1, 2, 3]:
            fp = V5_ASSETS_DIR / "dash_step" / f"dash_{idx:02d}.png"
            if fp.exists():
                self.dash_wedges.append(self._extract_dash_wedge(fp, idx))

        self.feathers: List[np.ndarray] = []
        for i in range(8):
            fp = V5_ASSETS_DIR / "vfx" / f"feather_{i:02d}.png"
            if fp.exists():
                self.feathers.append(self._trim_rgba(np.array(Image.open(fp).convert("RGBA"))))

        self.hit_slashes: List[np.ndarray] = []
        for i in range(4):
            fp = V5_ASSETS_DIR / "vfx" / f"hit_slash_{i:02d}.png"
            if fp.exists():
                self.hit_slashes.append(self._trim_rgba(np.array(Image.open(fp).convert("RGBA"))))

        self.brush_lut = self._build_ai_brush_lut()

    @staticmethod
    def _clean_tiny_isolated_specks(arr: np.ndarray, min_keep_area: int = 95) -> np.ndarray:
        out = arr.copy()
        a = (out[..., 3] > 8).astype(np.uint8)
        n_c, lab, st, _ = cv2.connectedComponentsWithStats(a, connectivity=8)
        if n_c <= 2:
            return out
        for i in range(1, n_c):
            if st[i, cv2.CC_STAT_AREA] < min_keep_area:
                out[lab == i] = 0
        return out

    @staticmethod
    def _trim_rgba(arr: np.ndarray) -> np.ndarray:
        ys, xs = np.where(arr[..., 3] > 10)
        if len(xs) == 0:
            return arr
        return arr[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()

    @staticmethod
    def _extract_dash_wedge(fp: Path, idx: int) -> np.ndarray:
        arr = np.array(Image.open(fp).convert("RGBA")).astype(np.float32)
        h, w, _ = arr.shape
        yy, xx = np.mgrid[0:h, 0:w]
        if idx == 1:
            upper = (yy < 626) & ((xx + (yy - 585.0) * 0.9) < 462.0) & (xx < 448)
            lower = (xx <= 286) & (yy >= 750)
            keep = upper | lower
            arr[~keep] = 0.0
            fade = upper & (yy >= 606)
            arr[fade, 3] *= np.clip((626.0 - yy[fade]) / 20.0, 0.0, 1.0)
        elif idx == 2:
            upper = (yy < 672) & ((xx + (yy - 590.0) * 0.9) < 475.0) & (xx < 460)
            lower = (xx <= 244) & (yy >= 735)
            keep = upper | lower
            arr[~keep] = 0.0
        else:
            arr[~((xx <= 340) & (yy <= 748))] = 0.0
        out = np.clip(np.round(arr), 0, 255).astype(np.uint8)
        return AIVfxLibrary._trim_rgba(out)

    def _build_ai_brush_lut(self) -> np.ndarray:
        fp = V5_ASSETS_DIR / "attack_1" / "a1_05.png"
        lut = np.ones((128, 512), dtype=np.float32)
        if not fp.exists():
            return lut
        arr = np.array(Image.open(fp).convert("RGBA")).astype(np.float32)
        crop = arr[20:850, 880:1520]
        a = crop[..., 3] > 40
        if a.sum() < 500:
            return lut
        lum = (0.299 * crop[..., 0] + 0.587 * crop[..., 1] + 0.114 * crop[..., 2]) / 255.0
        blur = cv2.GaussianBlur(lum, (0, 0), 9.0)
        detail = np.clip((lum - blur) * 2.4, -0.38, 0.38)
        detail[~a] = 0.0
        return cv2.resize(detail, (512, 128), interpolation=cv2.INTER_LINEAR)


# ==============================================================================
# 2. 赛璐璐角色本体 2x 超采样高清精修器 + 暖肤色硬保护盾
# ==============================================================================
def compute_skin_shield(rgba: np.ndarray) -> np.ndarray:
    """
    精准锁定主角暖白/粉白皮肤像素（脸、颈、胸口、手、腿）：
    主角肤色为低饱和暖象牙白：R >= 135, B >= 115, 8 <= (R - B) <= 68 且 R >= G - 3；
    高饱和亮黄方块火花 (B < 100, R - B > 90) 绝不会被误判为皮肤！
    向外膨胀 4px 连带保护五官轮廓与挑染发丝交界，100% 杜绝紫脸或鼻尖星芒！
    """
    rgb = rgba[..., :3].astype(np.int16)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    a = rgba[..., 3]
    # 主角暖粉白肤色恒有 R > G + 7（粉桃色调），绝不匹配 G ≈ R 的柠檬淡黄像素火花！
    skin_raw = (a > 24) & (r >= 135) & (b >= 115) & ((r - g) >= 7) & ((r - b) >= 10) & ((r - b) <= 68)
    if not skin_raw.any():
        return skin_raw
    return cv2.dilate(skin_raw.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))) > 0


def decontaminate_alpha_fringe(rgba: np.ndarray) -> np.ndarray:
    out = rgba.copy()
    a = out[..., 3]
    solid = a >= 215
    fringe = (a > 0) & (a < 215)
    if not solid.any() or not fringe.any():
        return out
    rgb_solid = out[..., :3].copy()
    rgb_solid[~solid] = 0
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    dil_rgb = cv2.dilate(rgb_solid, k, iterations=2)
    dil_mask = cv2.dilate(solid.astype(np.uint8), k, iterations=2) > 0
    rep = fringe & dil_mask
    mx = out[..., :3].max(axis=-1).astype(np.int16)
    mn = out[..., :3].min(axis=-1).astype(np.int16)
    low_sat_fringe = rep & ((mx - mn) < 42) & (mx < 165)
    out[low_sat_fringe, :3] = dil_rgb[low_sat_fringe]
    out[a < 10] = 0
    return out


def enhance_cel_body_hd(rgba: np.ndarray, target_scale: float = 1.0, is_already_hd: bool = False) -> np.ndarray:
    if rgba is None or rgba.size == 0:
        return rgba
    clean = decontaminate_alpha_fringe(rgba)
    h0, w0 = clean.shape[:2]
    if h0 < 4 or w0 < 4:
        return clean

    work_scale = 1.35 if is_already_hd else 2.0
    w2, h2 = max(4, int(round(w0 * work_scale))), max(4, int(round(h0 * work_scale)))
    up = cv2.resize(clean, (w2, h2), interpolation=cv2.INTER_LANCZOS4)

    rgb = up[..., :3]
    alpha = up[..., 3].astype(np.float32) / 255.0
    alpha_sm = cv2.GaussianBlur(alpha, (0, 0), 0.65)
    alpha_out = np.clip((alpha_sm - 0.08) / 0.88, 0.0, 1.0)

    if not is_already_hd:
        smooth = cv2.bilateralFilter(rgb, d=5, sigmaColor=24, sigmaSpace=5)
        blur = cv2.GaussianBlur(smooth.astype(np.float32), (0, 0), 1.15)
        diff = smooth.astype(np.float32) - blur
        lum = smooth.max(axis=-1, keepdims=True).astype(np.float32)
        weight = np.where(diff < 0, 0.88, np.where(lum > 210, 0.35, 0.52))
        sharp_rgb = np.clip(smooth.astype(np.float32) + diff * weight, 0.0, 255.0)
    else:
        blur = cv2.GaussianBlur(rgb.astype(np.float32), (0, 0), 0.9)
        diff = rgb.astype(np.float32) - blur
        sharp_rgb = np.clip(rgb.astype(np.float32) + diff * 0.32, 0.0, 255.0)

    hsv = cv2.cvtColor(sharp_rgb.astype(np.uint8), cv2.COLOR_RGB2HSV).astype(np.float32)
    hue, sat, val = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    cool_mask = (hue >= 102) & (hue <= 160) & (sat >= 35)
    sat[cool_mask] = np.clip(sat[cool_mask] * 1.09, 0.0, 255.0)
    val[cool_mask] = np.clip(val[cool_mask] * 1.03, 0.0, 255.0)
    hsv[..., 1], hsv[..., 2] = sat, val
    vivid_rgb = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2RGB)

    res = np.dstack([vivid_rgb, np.clip(np.round(alpha_out * 255.0), 0, 255).astype(np.uint8)])
    res[res[..., 3] < 8] = 0

    out_w = max(2, int(round(w0 * target_scale)))
    out_h = max(2, int(round(h0 * target_scale)))
    if (out_w, out_h) != (w2, h2):
        interp = cv2.INTER_AREA if out_w < w2 else cv2.INTER_LANCZOS4
        res = cv2.resize(res, (out_w, out_h), interpolation=interp)
    return res


# ==============================================================================
# 3. 多层 AI 书法飞白刀光渲染器（含贴边防平裁磨圆 + 无黑洞模式）
# ==============================================================================
def pad_canvas_with_pivot(
    D: np.ndarray, ww: float, wh: float, wpx: float, wpy: float, pad_px: int
) -> Tuple[np.ndarray, float, float, float, float]:
    if pad_px <= 0:
        return D, ww, wh, wpx, wpy
    H0, W0 = D.shape[:2]
    sx, sy = ww / max(W0, 1), wh / max(H0, 1)
    Dp = cv2.copyMakeBorder(D, pad_px, pad_px, pad_px, pad_px, cv2.BORDER_CONSTANT, value=(0, 0, 0, 0))
    return Dp, ww + 2.0 * pad_px * sx, wh + 2.0 * pad_px * sy, wpx + pad_px * sx, wpy + pad_px * sy


def taper_clipped_mask_borders(mask_unpadded: np.ndarray, pad_px: int) -> np.ndarray:
    """
    若原图刀光贴靠上下左右画布边缘被一刀切平，扩边后将贴边直切口柔化磨圆为自然弧尖！
    """
    h, w = mask_unpadded.shape
    touches_t = mask_unpadded[:3, :].sum() > 14
    touches_b = mask_unpadded[-3:, :].sum() > 14
    touches_l = mask_unpadded[:, :3].sum() > 14
    touches_r = mask_unpadded[:, -3:].sum() > 14

    m_pad = np.pad(mask_unpadded, ((pad_px, pad_px), (pad_px, pad_px)), mode="constant", constant_values=False)
    if not (touches_t or touches_b or touches_l or touches_r):
        return m_pad

    # 对原贴边 12px 带做椭圆形开闭平滑，使直角硬切边收回成圆润弧线
    mf = m_pad.astype(np.float32)
    yy, xx = np.mgrid[0:m_pad.shape[0], 0:m_pad.shape[1]]
    edge_band = np.zeros_like(m_pad)
    if touches_t:
        edge_band |= (yy <= pad_px + 14)
    if touches_b:
        edge_band |= (yy >= pad_px + h - 15)
    if touches_l:
        edge_band |= (xx <= pad_px + 14)
    if touches_r:
        edge_band |= (xx >= pad_px + w - 15)

    sm = cv2.GaussianBlur(mf, (0, 0), 6.5)
    rounded = np.where(edge_band, sm > 0.56, m_pad)
    return rounded.astype(bool)


def render_ai_calligraphy_slash(
    slash_mask: np.ndarray,
    orig_rgba: np.ndarray,
    vfx_lib: AIVfxLibrary,
    seed: int = 0,
    add_star_tip: bool = True,
    solid_crescent: bool = False,
) -> np.ndarray:
    H, W = slash_mask.shape
    if slash_mask.sum() < 40:
        return np.zeros((H, W, 4), dtype=np.uint8)

    PAD2 = 32
    H2_inner, W2_inner = H * 2, W * 2
    m2_inner = cv2.resize(slash_mask.astype(np.uint8), (W2_inner, H2_inner), interpolation=cv2.INTER_NEAREST) > 0
    m2 = np.pad(m2_inner, ((PAD2, PAD2), (PAD2, PAD2)), mode="constant", constant_values=False)
    H2, W2 = m2.shape

    close_k = 31 if solid_crescent else 13
    m2_closed = cv2.morphologyEx(m2.astype(np.uint8), cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (close_k, close_k)))
    if solid_crescent:
        # 填平满蓄力巨弧笔触内部的细碎空洞（面积 < 26000），保留环绕人物的中央大圆孔！
        inv = (m2_closed == 0).astype(np.uint8)
        nh, lh, sh, _ = cv2.connectedComponentsWithStats(inv, connectivity=8)
        for hi in range(1, nh):
            hx, hy, hcw, hch, harea = sh[hi]
            touches_edge = (hx == 0) or (hy == 0) or (hx + hcw >= W2) or (hy + hch >= H2)
            if (not touches_edge) and harea < 26000:
                m2_closed[lh == hi] = 1
    sm_sigma = 8.5 if solid_crescent else 7.0
    sm_float = cv2.GaussianBlur(m2_closed.astype(np.float32), (0, 0), sm_sigma)
    S = (sm_float > 0.44).astype(np.uint8)
    if S.sum() < 80:
        S = m2.astype(np.uint8)

    n_cc, lab_cc, stats_cc, _ = cv2.connectedComponentsWithStats(S, connectivity=8)
    hull = np.zeros_like(S)
    tip_pt: Optional[Tuple[int, int]] = None
    max_area = 0
    cx_all, cy_all = W2 * 0.5, H2 * 0.5

    for i in range(1, n_cc):
        area = stats_cc[i, cv2.CC_STAT_AREA]
        if area < 90:
            S[lab_cc == i] = 0
            continue
        ys, xs = np.nonzero(lab_cc == i)
        pts = np.stack([xs, ys], axis=1).astype(np.int32)
        cv2.fillConvexPoly(hull, cv2.convexHull(pts), 1)
        if area > max_area:
            max_area = area
            cx_all, cy_all = float(xs.mean()), float(ys.mean())
            d2 = (xs - cx_all) ** 2 + (ys - cy_all) ** 2
            idx_far = int(np.argmax(d2))
            tip_pt = (int(xs[idx_far]), int(ys[idx_far]))

    if S.sum() < 60:
        return np.zeros((H, W, 4), dtype=np.uint8)

    border = (S > 0) & (cv2.erode(S, np.ones((3, 3), np.uint8)) == 0)
    d_to_outside_hull = cv2.distanceTransform((hull > 0).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    outer = border & (d_to_outside_hull <= 18.0)
    inner = border & (~outer)

    da = cv2.distanceTransform((~outer).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE) if outer.any() else np.full((H2, W2), 1e4, np.float32)
    if inner.sum() > 50:
        db = cv2.distanceTransform((~inner).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
        u = da / np.maximum(da + db, 1e-3)
    else:
        dm = cv2.distanceTransform(S, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
        thick = cv2.dilate(dm, np.ones((35, 35), np.uint8)) + 1e-3
        u = 0.60 * (1.0 - np.clip(dm / thick, 0.0, 1.0))
        da = np.minimum(da, u * 24.0)
    u = np.clip(u, 0.0, 1.0)

    yy, xx = np.mgrid[0:H2, 0:W2]
    theta = (np.arctan2(yy - cy_all, xx - cx_all) + math.pi) / (2.0 * math.pi)
    lut = vfx_lib.brush_lut
    lh, lw = lut.shape
    ui = np.clip((u * (lh - 1)).astype(np.int32), 0, lh - 1)
    ti = np.mod(((theta * 2.3 + (seed % 37) * 0.07) * lw).astype(np.int32), lw)
    ai_stroke = lut[ui, ti]

    orig_lum_in = cv2.resize(orig_rgba[..., :3].max(axis=-1).astype(np.float32), (W2_inner, H2_inner), interpolation=cv2.INTER_LINEAR)
    orig_lum = np.pad(orig_lum_in, ((PAD2, PAD2), (PAD2, PAD2)), mode="edge")
    lum_t = np.clip((orig_lum - 85.0) / 130.0, 0.45, 1.0)

    rng = np.random.default_rng(seed)
    noise_low = cv2.GaussianBlur(rng.standard_normal((H2, W2)).astype(np.float32), (0, 0), 11.0)
    noise_low /= (np.abs(noise_low).max() + 1e-6)

    if solid_crescent:
        # 满蓄力巨弧模式：内部 100% 饱满连贯不挖空洞，外刃纯白 -> 电光紫 -> 紫晶飞白！
        keep = S > 0
    else:
        cut_u = (0.62 + 0.34 * lum_t) + 0.13 * ai_stroke + 0.08 * noise_low
        keep = (S > 0) & ((u <= cut_u) | (da <= 13.0))
        keep = cv2.morphologyEx(keep.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)) > 0

    c_white = np.array([253, 250, 255], np.float32)
    c_lav   = np.array([224, 206, 255], np.float32)
    c_vio   = np.array([162, 114, 255], np.float32)
    c_royal = np.array([116,  68, 238], np.float32)
    c_ink   = np.array([ 72,  38, 164], np.float32)

    u_mod = np.clip(u + ai_stroke * 0.24, 0.0, 1.0)
    col = np.zeros((H2, W2, 3), np.float32)
    col[u_mod < 0.20] = c_lav
    col[(u_mod >= 0.20) & (u_mod < 0.54)] = c_vio
    col[(u_mod >= 0.54) & (u_mod < 0.80)] = c_royal
    col[u_mod >= 0.80] = c_ink

    ink_streak = (ai_stroke < -0.12) & (u > 0.30) & (u < 0.82)
    elec_streak = (ai_stroke > 0.12) & (u > 0.12) & (u < 0.55)
    col[ink_streak] = c_ink
    col[elec_streak] = c_lav

    core_w = (11.5 * (0.64 + 0.36 * lum_t)) * (1.0 + 0.16 * noise_low)
    col[da <= core_w] = c_white

    glow_mask = (~keep) & (da <= 11.0)
    alpha = np.zeros((H2, W2), np.float32)
    alpha[keep] = 0.99
    alpha[glow_mask] = np.clip((11.0 - da[glow_mask]) / 11.0, 0.0, 1.0) * 0.54
    col[glow_mask] = c_vio

    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.9)
    out2 = np.zeros((H2, W2, 4), dtype=np.uint8)
    out2[..., :3] = np.clip(np.round(col), 0, 255).astype(np.uint8)
    out2[..., 3] = np.clip(np.round(alpha * 255.0), 0, 255).astype(np.uint8)

    if add_star_tip and tip_pt is not None and max_area > 3500:
        out2 = draw_cold_violet_star(out2, tip_pt[0], tip_pt[1], radius=min(42.0, math.sqrt(max_area) * 0.23))

    out2_cropped = out2[PAD2:PAD2 + H2_inner, PAD2:PAD2 + W2_inner]
    return cv2.resize(out2_cropped, (W, H), interpolation=cv2.INTER_AREA)


def draw_cold_violet_star(canvas_rgba: np.ndarray, cx: float, cy: float, radius: float = 28.0) -> np.ndarray:
    h, w = canvas_rgba.shape[:2]
    star_im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(star_im)
    for ang, ln, wd, col in [
        (-18, 1.15, 0.13, (158, 118, 255, 235)),
        (72,  1.05, 0.13, (158, 118, 255, 235)),
        (27,  0.58, 0.10, (212, 194, 255, 225)),
        (117, 0.58, 0.10, (212, 194, 255, 225)),
    ]:
        rad = math.radians(ang)
        dx, dy = math.cos(rad) * radius * ln, math.sin(rad) * radius * ln
        nx, ny = -math.sin(rad) * radius * wd, math.cos(rad) * radius * wd
        d.polygon([(cx - dx, cy - dy), (cx + nx, cy + ny), (cx + dx, cy + dy), (cx - nx, cy - ny)], fill=col)
    r_core = max(2.5, radius * 0.18)
    d.ellipse([cx - r_core, cy - r_core, cx + r_core, cy + r_core], fill=(252, 249, 255, 255))
    base_im = Image.fromarray(canvas_rgba)
    base_im.alpha_composite(star_im)
    return np.array(base_im)


def composite_ai_feathers(
    canvas_rgba: np.ndarray,
    piv_px: Tuple[float, float],
    vfx_lib: AIVfxLibrary,
    count: int,
    seed: int,
    spread_dir: float = -1.0,
) -> np.ndarray:
    if not vfx_lib.feathers or count <= 0:
        return canvas_rgba
    rng = np.random.default_rng(seed)
    base = Image.fromarray(canvas_rgba)
    px, py = piv_px
    for k in range(count):
        f_arr = vfx_lib.feathers[(seed + k * 3) % len(vfx_lib.feathers)]
        fim = Image.fromarray(f_arr)
        target_sz = int(rng.integers(24, 38))
        scale = target_sz / max(fim.width, fim.height, 1)
        fim = fim.resize((max(4, int(fim.width * scale)), max(4, int(fim.height * scale))), Image.Resampling.LANCZOS)
        fim = fim.rotate(float(rng.uniform(-45.0, 45.0)), resample=Image.Resampling.BICUBIC, expand=True)
        ox = int(px + spread_dir * rng.uniform(35.0, 115.0) - fim.width // 2)
        oy = int(py - rng.uniform(55.0, 165.0) - fim.height // 2)
        if 0 <= ox < base.width - fim.width and 0 <= oy < base.height - fim.height:
            base.alpha_composite(fim, (ox, oy))
    return np.array(base)


# ==============================================================================
# 4. 坏帧清理与刀光/烟尘/蓄力冲击波/受击爆裂专项处理器
# ==============================================================================
def clean_stray_and_muddy_dust(
    rgba: np.ndarray,
    ground_y_px: float,
    strip_muddy_dust: bool = False,
) -> np.ndarray:
    out = rgba.copy()
    h, w = out.shape[:2]
    a = out[..., 3] > 12
    if a.sum() < 30:
        return out

    # Step A: 剥离孤立悬浮杂块/视频残丝
    n_cc, lab, stats, _ = cv2.connectedComponentsWithStats(a.astype(np.uint8), connectivity=8)
    if n_cc > 2:
        areas = stats[1:, cv2.CC_STAT_AREA]
        main_idx = 1 + int(np.argmax(areas))
        mx0, my0, mw, mh, _ = stats[main_idx]
        valid_boxes = [stats[li, :4] for li in range(1, n_cc) if stats[li, cv2.CC_STAT_AREA] >= 420]
        if not valid_boxes:
            valid_boxes.append((mx0, my0, mw, mh))

        for li in range(1, n_cc):
            area = stats[li, cv2.CC_STAT_AREA]
            if area >= 420:
                continue
            lx, ly, lw, lh, _ = stats[li]
            min_dist = 9999
            for vx, vy, vw, vh in valid_boxes:
                dx = max(0, vx - (lx + lw), lx - (vx + vw))
                dy = max(0, vy - (ly + lh), ly - (vy + vh))
                min_dist = min(min_dist, max(dx, dy))
            if area < 28 or (area < 260 and min_dist > 18) or (area < 420 and min_dist > 48):
                out[lab == li] = 0

    # Step B: 仅在明确指定的连段重击剪辑中剥离脚后泥灰团（带暖肤色保护盾！）
    if strip_muddy_dust:
        skin_shield = compute_skin_shield(out)
        rgb = out[..., :3].astype(np.int16)
        mx = rgb.max(axis=-1)
        mn = rgb.min(axis=-1)
        sat = mx - mn
        b_minus_r = rgb[..., 2] - rgb[..., 0]
        yy = np.arange(h)[:, None]
        mud_cand = (
            (out[..., 3] > 0)
            & (~skin_shield)
            & (yy >= max(0, int(ground_y_px - 58)))
            & (sat < 30)
            & (mx >= 82)
            & (mx <= 198)
            & (b_minus_r < 20)
        )
        n_m, lab_m, st_m, _ = cv2.connectedComponentsWithStats(mud_cand.astype(np.uint8), connectivity=8)
        trans = out[..., 3] < 24
        k5 = np.ones((5, 5), np.uint8)
        for i in range(1, n_m):
            x, y, cw, ch, area = st_m[i]
            if area < 95:
                continue
            comp = (lab_m[max(0, y - 2):min(h, y + ch + 2), max(0, x - 2):min(w, x + cw + 2)] == i).astype(np.uint8)
            ring = cv2.dilate(comp, k5) - comp
            tr_sub = trans[max(0, y - 2):min(h, y + ch + 2), max(0, x - 2):min(w, x + cw + 2)]
            ratio = (tr_sub & (ring > 0)).sum() / max(1, (ring > 0).sum())
            if ratio >= 0.48:
                out[lab_m == i] = 0

    return out


def detect_warm_sparks_only(base_rgba: np.ndarray) -> np.ndarray:
    """仅检测暖黄/橙色交锋火花（绝不触碰皮肤或刀光），供格挡受击与弹刀转冷紫星闪使用。"""
    h, w = base_rgba.shape[:2]
    r, g, b, a = (base_rgba[..., k].astype(np.int16) for k in range(4))
    warm = (a > 32) & (r > 205) & (g > 150) & ((r - b) > 45) & ((g - b) > 22)
    spark = np.zeros((h, w), dtype=bool)
    if warm.sum() >= 180:
        n_s, lab_s, st_s, _ = cv2.connectedComponentsWithStats(warm.astype(np.uint8), connectivity=8)
        for i in range(1, n_s):
            if st_s[i, cv2.CC_STAT_AREA] >= 160:
                spark |= (lab_s == i)
    return spark


def detect_universal_slash_and_spark(
    base_rgba: np.ndarray,
    ground_y_px: float,
    clip_key: str,
    frame_idx: int,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    精准识别白色/淡紫运动刀影与暖黄火花：
    - 全程强制应用 compute_skin_shield(base_rgba) 保护五官与全身皮肤；
    - 严格遵守 SLASH_FRAME_WHITELIST，持直剑静姿帧零误判！
    """
    h, w = base_rgba.shape[:2]
    spark = detect_warm_sparks_only(base_rgba)

    if clip_key in SLASH_FRAME_WHITELIST and frame_idx not in SLASH_FRAME_WHITELIST[clip_key]:
        return np.zeros((h, w), dtype=bool), spark

    skin_shield = compute_skin_shield(base_rgba)
    slash, dust, _, stray = RS.classify(base_rgba, ground_y_px, dash=False)
    if stray.any():
        base_rgba[stray] = 0
    if dust.any() and clip_key in GROUND_DUST_CLIPS:
        dust_clean = dust & (~skin_shield)
        dust_dil = cv2.dilate(dust_clean.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
        near_dust = dust_dil & (~skin_shield) & (base_rgba[..., 3] > 0) & ((base_rgba[..., :3].max(-1) - base_rgba[..., :3].min(-1)) < 44)
        base_rgba[dust_clean | near_dust] = 0

    slash &= (~skin_shield)

    extra_fx_clips = {
        "air_attack_1", "air_attack_3", "air_slash",
        "guard_start", "parry", "parry_react_2", "parry_react_3",
        "draw", "sheathe",
    }
    if clip_key in extra_fx_clips:
        rgb = base_rgba[..., :3].astype(np.int16)
        r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
        a = base_rgba[..., 3]
        mx = rgb.max(axis=-1)
        ch = mx - rgb.min(axis=-1)
        # 严格中性白 (|R-B|<=9) 或明显冷蓝紫 (B-R>=14)，100% 排除暖白皮肤！
        neutral_white = (ch <= 44) & (np.abs(r - b) <= 10) & (mx >= 152)
        cool_violet_arc = ((b - g) >= 24) & ((b - r) >= 12) & (mx >= 172)
        cand = (a > 24) & (~skin_shield) & (neutral_white | cool_violet_arc)

        # guard_start / parry f8,f9 的下摆白色宽弧紧贴双腿，直接捕获下半身中性白大块
        if clip_key in ("guard_start", "parry") and frame_idx in (8, 9):
            yy, xx = np.mgrid[0:h, 0:w]
            gs_cand = (a > 24) & (~skin_shield) & (ch <= 48) & (np.abs(r - b) <= 12) & (mx >= 145) & ((yy > int(h * 0.44)) | (xx < int(w * 0.56)))
            n_g, lab_g, st_g, _ = cv2.connectedComponentsWithStats(gs_cand.astype(np.uint8), connectivity=8)
            for gi in range(1, n_g):
                if st_g[gi, cv2.CC_STAT_AREA] >= 340:
                    slash |= (lab_g == gi)

        # draw[38] 右上剑尖残余白团专项捕获
        if clip_key == "draw" and frame_idx == 38:
            yy, xx = np.mgrid[0:h, 0:w]
            tip_cand = (a > 20) & (~skin_shield) & (xx > int(w * 0.72)) & (ch <= 52) & (mx >= 150)
            slash |= tip_cand

        n_c, lab_c, st_c, _ = cv2.connectedComponentsWithStats(cand.astype(np.uint8), connectivity=8)
        trans_pad = np.pad(a < 145, ((4, 4), (4, 4)), mode="constant", constant_values=True)
        k5 = np.ones((5, 5), np.uint8)
        min_area = 160 if clip_key in ("draw", "sheathe") else 380
        for i in range(1, n_c):
            x, y, cw, ch_box, area = st_c[i]
            if area < min_area:
                continue
            comp_full = (lab_c == i)
            sub = np.pad(comp_full[y:y + ch_box, x:x + cw].astype(np.uint8), ((4, 4), (4, 4)), mode="constant", constant_values=0)
            thick = float(cv2.distanceTransform(sub, cv2.DIST_L2, 3).max())
            ring = cv2.dilate(sub, k5) - sub
            tr_sub = trans_pad[y:y + ch_box + 8, x:x + cw + 8]
            ratio = (tr_sub & (ring > 0)).sum() / max(1, (ring > 0).sum())
            mean_mx = float(mx[comp_full].mean())
            if area >= 1200 and thick >= 10.5 and mean_mx >= 195.0 and (cw > 72 or ch_box > 72):
                slash |= comp_full
            elif thick >= 8.2 and ratio >= 0.22 and (cw > 54 or ch_box > 54):
                slash |= comp_full
            elif clip_key in ("draw", "sheathe") and area >= 140 and thick >= 3.2 and ratio >= 0.30 and mean_mx >= 175.0:
                slash |= comp_full

    if slash.any():
        rgb_s = base_rgba[..., :3].astype(np.int16)
        ch_s = rgb_s.max(axis=-1) - rgb_s.min(axis=-1)
        sl_dil = cv2.dilate(slash.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
        fringe_absorb = sl_dil & (~slash) & (~skin_shield) & (base_rgba[..., 3] > 0) & (ch_s <= 54) & (rgb_s.max(axis=-1) >= 122)
        slash |= fringe_absorb

    return slash, spark


def strip_dark_video_scanlines(D: np.ndarray) -> np.ndarray:
    """清除蓄力动画背景空域残留的半透明深灰视频压缩横条噪点 (mx < 68 & a < 205)，保留人物实体。"""
    out = D.copy()
    rgb = out[..., :3].astype(np.int16)
    mx = rgb.max(axis=-1)
    a = out[..., 3]
    solid_char = (a >= 210) & (mx >= 28)
    char_safe = cv2.dilate(solid_char.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))) > 0
    bg_noise = (~char_safe) & (a > 0) & (((a < 195) & (mx < 72)) | (a < 28))
    out[bg_noise] = 0
    return out


def process_charge_hold_frame(
    D: np.ndarray, ww: float, wh: float, wpx: float, wpy: float, idx: int, vfx_lib: AIVfxLibrary
) -> Tuple[np.ndarray, float, float, float, float]:
    """
    专项升级 charge_hold (0..23)：
    1. 净除背景半透明暗灰扫描线；
    2. 四周扩边 32px，消除上下边界 T189/B241 一刀硬平裁，磨圆为平滑冷紫能量旋涡环；
    3. 将 f0,f2 粗糙白马赛克环与全部黄色方块火花统一重绘为 2x SDF 亮芯冷紫旋涡 + 四芒星闪！
    """
    D = strip_dark_video_scanlines(D)
    H0, W0 = D.shape[:2]
    skin_shield = compute_skin_shield(D)
    rgb = D[..., :3].astype(np.int16)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    a = D[..., 3]
    mx = rgb.max(axis=-1)
    ch = mx - rgb.min(axis=-1)

    # 识别旋涡光环（纯白马赛克块 + 原生粗锯齿紫白环 + 底部青色亮边）与黄色方块火花
    yellow_spark = (a > 20) & (~skin_shield) & (r >= 145) & (g >= 110) & ((r - b) >= 24)
    cyan_edge = (a > 20) & (~skin_shield) & (g >= 150) & (b >= 150) & ((g - r) >= 25)
    white_ring = (a > 24) & (~skin_shield) & (ch <= 52) & (np.abs(r - b) <= 18) & (mx >= 155)
    purple_ring = (a > 24) & (~skin_shield) & ((b - g) >= 18) & (mx >= 125)

    # 保护中间持剑蓄力的人物实体像素（深色衣发 + 高饱和宝蓝紫饰 + 暖粉肤色 + 胸口小抹胸），消除矩形安全框白烟断边！
    px0 = wpx * (W0 / max(ww, 1e-4))
    py0 = wpy * (H0 / max(wh, 1e-4))
    yy0, xx0 = np.mgrid[0:H0, 0:W0]
    in_char_zone = (np.abs(xx0 - px0) < 62) & (yy0 > (py0 - 165)) & (yy0 <= (py0 + 14))
    vest_zone = (np.abs(xx0 - px0) < 26) & (yy0 > (py0 - 96)) & (yy0 < (py0 - 42))
    char_body_px = in_char_zone & (a > 36) & (
        skin_shield | vest_zone | (mx < 148) | ((ch >= 28) & ((b - r) >= -15))
    )
    char_box = cv2.dilate(char_body_px.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))) > 0
    ring_raw = (white_ring | purple_ring | cyan_edge) & (~char_box)

    # 过滤掉细碎杂块，保留面积 >= 90 的旋涡弧段
    n_r, lab_r, st_r, _ = cv2.connectedComponentsWithStats(ring_raw.astype(np.uint8), connectivity=8)
    vortex_unpad = np.zeros((H0, W0), dtype=bool)
    for ri in range(1, n_r):
        if st_r[ri, cv2.CC_STAT_AREA] >= 90:
            vortex_unpad |= (lab_r == ri)

    PAD = 32
    Dp, ww_p, wh_p, wpx_p, wpy_p = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
    vortex_mask = taper_clipped_mask_borders(vortex_unpad, PAD)
    spark_pad = np.pad(yellow_spark & (~char_box), ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)

    # 人物实体像素之外的一切旧版锯齿旋涡、柠檬黄残块与像素黑灰描边 100% 净除！
    char_pad = np.pad(char_box, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
    Dp[~char_pad] = 0

    # 用 2x SDF 平滑重绘丝滑旋涡能量环
    if vortex_mask.sum() >= 60:
        vortex_hd = render_ai_calligraphy_slash(
            vortex_mask, Dp, vfx_lib, seed=7100 + idx * 13, add_star_tip=False, solid_crescent=True
        )
        base_pil = Image.fromarray(Dp)
        base_pil.alpha_composite(Image.fromarray(vortex_hd))
        Dp = np.array(base_pil)

    # 将黄色方块火花替换为精致冷紫星闪
    if spark_pad.any():
        n_s, _, st_s, cent_s = cv2.connectedComponentsWithStats(spark_pad.astype(np.uint8), connectivity=8)
        for si in range(1, n_s):
            if st_s[si, cv2.CC_STAT_AREA] >= 18:
                rad = min(22.0, max(9.0, math.sqrt(st_s[si, cv2.CC_STAT_AREA]) * 0.95))
                Dp = draw_cold_violet_star(Dp, float(cent_s[si][0]), float(cent_s[si][1]), radius=rad)

    return Dp, ww_p, wh_p, wpx_p, wpy_p


def process_charge_slash_frame(
    D: np.ndarray, ww: float, wh: float, wpx: float, wpy: float, idx: int, vfx_lib: AIVfxLibrary
) -> Tuple[np.ndarray, float, float, float, float]:
    """
    专项分阶段精修 charge_slash (0..84)：
    - f0..19: 净除背景扫描线与 f18 右上灰烟，扩边 44px 磨圆贴边平裁，f14..19 开启 solid_crescent 消除黑洞与白锯齿；
    - f20..21: 2x SDF 平滑高反差冲击帧（深紫黑内核 + 炽白冷紫电光冲击外环）；
    - f22..41: 地面震波银紫气柱（扩边消除底部 B327 硬平裁，黄色方块火花全部转冷紫星闪，绝不染成紫泥滩！）；
    - f42..84: 纯净角色赛璐璐高清修复。
    """
    D = strip_dark_video_scanlines(D)
    H0, W0 = D.shape[:2]

    if idx == 18:
        # 净除 f18 右上孤立灰烟团
        yy, xx = np.mgrid[0:H0, 0:W0]
        ch0 = D[..., :3].max(-1).astype(np.int16) - D[..., :3].min(-1).astype(np.int16)
        D[(xx > int(W0 * 0.62)) & (yy < int(H0 * 0.42)) & (ch0 < 40)] = 0

    if idx <= 19:
        skin_shield = compute_skin_shield(D)
        px0 = wpx * (W0 / max(ww, 1e-4))
        py0 = wpy * (H0 / max(wh, 1e-4))
        yy0, xx0 = np.mgrid[0:H0, 0:W0]
        char_box = (np.abs(xx0 - px0) < 64) & (yy0 > (py0 - 172)) & (yy0 <= (py0 + 16))

        rgb = D[..., :3].astype(np.int16)
        r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
        a = D[..., 3]
        mx = rgb.max(axis=-1)
        ch = mx - rgb.min(axis=-1)
        yellow_sp = (a > 20) & (~skin_shield) & (~char_box) & (r >= 145) & (g >= 110) & ((r - b) >= 24)
        slash_unpad = (a > 24) & (~skin_shield) & (ch <= 52) & (np.abs(r - b) <= 16) & (mx >= 158)
        n_c, lab_c, st_c, _ = cv2.connectedComponentsWithStats(slash_unpad.astype(np.uint8), connectivity=8)
        clean_unpad = np.zeros((H0, W0), dtype=bool)
        for ci in range(1, n_c):
            if st_c[ci, cv2.CC_STAT_AREA] >= 80:
                clean_unpad |= (lab_c == ci)

        PAD = 44
        Dp, ww_p, wh_p, wpx_p, wpy_p = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
        char_pad = np.pad(char_box, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
        skin_pad = np.pad(skin_shield, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
        sp_pad = np.pad(yellow_sp, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)

        if clean_unpad.sum() >= 60:
            slash_pad = taper_clipped_mask_borders(clean_unpad, PAD)
            raw_pad = np.pad(clean_unpad | yellow_sp, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
            # 连同紧邻的像素灰黑描边与锯齿残屑一并清除（严格保护中央角色安全框 char_pad 与 skin_pad！）
            raw_dil = cv2.dilate(raw_pad.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (11, 11))) > 0
            outer_ring_crumbs = (~char_pad) & (~skin_pad) & (raw_dil | (Dp[..., :3].max(-1) < 125))
            Dp[(raw_pad | outer_ring_crumbs) & (~skin_pad)] = 0

            slash_hd = render_ai_calligraphy_slash(
                slash_pad, Dp, vfx_lib, seed=8200 + idx * 19,
                add_star_tip=(idx >= 9), solid_crescent=(idx >= 14),
            )
            base_pil = Image.fromarray(Dp)
            base_pil.alpha_composite(Image.fromarray(slash_hd))
            Dp = np.array(base_pil)
        elif sp_pad.any():
            sp_dil = cv2.dilate(sp_pad.astype(np.uint8), np.ones((7, 7), np.uint8)) > 0
            Dp[sp_dil & (~char_pad) & (~skin_pad)] = 0

        if sp_pad.any():
            n_s, _, st_s, cent_s = cv2.connectedComponentsWithStats(sp_pad.astype(np.uint8), connectivity=8)
            for si in range(1, n_s):
                if st_s[si, cv2.CC_STAT_AREA] >= 12:
                    rad = min(20.0, max(8.5, math.sqrt(st_s[si, cv2.CC_STAT_AREA]) * 0.95))
                    Dp = draw_cold_violet_star(Dp, float(cent_s[si][0]), float(cent_s[si][1]), radius=rad)
        return Dp, ww_p, wh_p, wpx_p, wpy_p

    elif idx in (20, 21):
        # 2 帧黑白反差冲击帧升级：2x SDF 丝滑暗夜紫黑剪影 + 炽白冷紫冲击光环！
        PAD = 32
        Dp, ww_p, wh_p, wpx_p, wpy_p = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
        HP, WP = Dp.shape[:2]
        m2 = cv2.resize((Dp[..., 3] > 30).astype(np.uint8), (WP * 2, HP * 2), interpolation=cv2.INTER_NEAREST)
        sm = cv2.GaussianBlur(m2.astype(np.float32), (0, 0), 4.2) > 0.45
        dist_in = cv2.distanceTransform(sm.astype(np.uint8), cv2.DIST_L2, 3)
        dist_out = cv2.distanceTransform((~sm).astype(np.uint8), cv2.DIST_L2, 3)

        out2 = np.zeros((HP * 2, WP * 2, 4), dtype=np.uint8)
        # 内部深邃暗紫墨核
        out2[sm] = [24, 13, 48, 248]
        # 冲击刃口炽白亮线 + 外圈冷紫电晕
        rim_white = sm & (dist_in <= 5.5)
        rim_vio = sm & (dist_in > 5.5) & (dist_in <= 13.0)
        glow_out = (~sm) & (dist_out <= 10.0)
        out2[rim_vio] = [156, 108, 255, 252]
        out2[rim_white] = [252, 248, 255, 255]
        out2[glow_out, :3] = [148, 98, 255]
        out2[glow_out, 3] = np.clip((10.0 - dist_out[glow_out]) / 10.0 * 165.0, 0, 255).astype(np.uint8)
        Dp = cv2.resize(out2, (WP, HP), interpolation=cv2.INTER_AREA)
        return Dp, ww_p, wh_p, wpx_p, wpy_p

    elif 22 <= idx <= 41:
        # 砸地银紫冲击波气柱 + 冷紫星火（精准锁定左侧俯蹲人物实体轮廓，彻底消除矩形白烟断边与全部柠檬黄方块！）
        skin_shield = compute_skin_shield(D)
        px0 = wpx * (W0 / max(ww, 1e-4))
        py0 = wpy * (H0 / max(wh, 1e-4))
        yy0, xx0 = np.mgrid[0:H0, 0:W0]
        rgb = D[..., :3].astype(np.int16)
        r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
        a = D[..., 3]
        mx = rgb.max(axis=-1)
        ch = mx - rgb.min(axis=-1)

        in_char_zone = (np.abs(xx0 - px0) < 68) & (yy0 > (py0 - 142)) & (yy0 <= (py0 + 16))
        vest_zone = (np.abs(xx0 - px0) < 28) & (yy0 > (py0 - 78)) & (yy0 < (py0 - 28))
        char_body_px = in_char_zone & (a > 36) & (
            skin_shield | vest_zone | (mx < 138) | ((ch >= 28) & ((b - r) >= -15))
        )
        char_box = cv2.dilate(char_body_px.astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))) > 0

        yellow_sp = (a > 20) & (~char_box) & (r >= 145) & (g >= 110) & ((r - b) >= 24)
        shock_white = (a > 24) & (~char_box) & (ch <= 52) & (np.abs(r - b) <= 18) & (mx >= 130)
        n_w, lab_w, st_w, _ = cv2.connectedComponentsWithStats(shock_white.astype(np.uint8), connectivity=8)
        plume_unpad = np.zeros((H0, W0), dtype=bool)
        for wi in range(1, n_w):
            if st_w[wi, cv2.CC_STAT_AREA] >= 90:
                plume_unpad |= (lab_w == wi)

        PAD = 28
        Dp, ww_p, wh_p, wpx_p, wpy_p = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
        HP, WP = Dp.shape[:2]

        plume_pad = taper_clipped_mask_borders(plume_unpad, PAD)
        char_pad = np.pad(char_box, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
        Dp[~char_pad] = 0

        if plume_pad.sum() >= 60:
            # 2x SDF 银白尖峰 -> 冰晶浅紫 -> 半透明烟紫气浪渲染（绝无硬边平底紫泥感！）
            m2 = cv2.resize(plume_pad.astype(np.uint8), (WP * 2, HP * 2), interpolation=cv2.INTER_NEAREST)
            sm = cv2.GaussianBlur(m2.astype(np.float32), (0, 0), 4.5) > 0.44
            din = cv2.distanceTransform(sm.astype(np.uint8), cv2.DIST_L2, 3)
            max_d = max(6.0, float(din.max()))
            t = np.clip(din / (max_d * 0.55), 0.0, 1.0)
            # 内核炽白银紫，外层通透淡紫雾
            col_in = np.array([250, 246, 255], np.float32)
            col_mid = np.array([198, 174, 255], np.float32)
            col_out = np.array([128, 96, 212], np.float32)
            pl2 = np.zeros((HP * 2, WP * 2, 4), dtype=np.float32)
            c_rgb = np.where(
                t[..., None] < 0.45,
                col_out + (col_mid - col_out) * (t[..., None] / 0.45),
                col_mid + (col_in - col_mid) * ((t[..., None] - 0.45) / 0.55),
            )
            pl2[sm, :3] = c_rgb[sm]
            # 底部最后 18px 做柔和接地消散渐变，告别贴地一刀切！
            yy2 = np.arange(HP * 2)[:, None]
            bot_y = int(np.where(sm)[0].max()) if sm.any() else HP * 2
            bot_fade = np.clip((bot_y - yy2 + 6.0) / 22.0, 0.28, 1.0)
            pl2[..., 3] = np.where(sm, (0.58 + 0.38 * t) * bot_fade * 255.0, 0.0)
            pl2[..., 3] = cv2.GaussianBlur(pl2[..., 3], (0, 0), 1.2)
            pl_rgba = cv2.resize(np.clip(pl2, 0, 255).astype(np.uint8), (WP, HP), interpolation=cv2.INTER_AREA)
            base_pil = Image.fromarray(Dp)
            base_pil.alpha_composite(Image.fromarray(pl_rgba))
            Dp = np.array(base_pil)

        sp_pad = np.pad(yellow_sp, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
        if sp_pad.any():
            n_s, _, st_s, cent_s = cv2.connectedComponentsWithStats(sp_pad.astype(np.uint8), connectivity=8)
            for si in range(1, n_s):
                if st_s[si, cv2.CC_STAT_AREA] >= 12:
                    rad = min(20.0, max(8.5, math.sqrt(st_s[si, cv2.CC_STAT_AREA]) * 0.95))
                    Dp = draw_cold_violet_star(Dp, float(cent_s[si][0]), float(cent_s[si][1]), radius=rad)

        return Dp, ww_p, wh_p, wpx_p, wpy_p

    return D, ww, wh, wpx, wpy


def upgrade_death_burst_frame(
    D: np.ndarray, ww: float, wh: float, wpx: float, wpy: float, idx: int, vfx_lib: AIVfxLibrary
) -> Tuple[np.ndarray, float, float, float, float]:
    """将 death[19..24] 外围粗糙纯白尖刺与脏橙黄火块统一升级为冷紫银白能量爆裂 + 夜鸦黑羽！"""
    H0, W0 = D.shape[:2]
    skin_shield = compute_skin_shield(D)
    px0 = wpx * (W0 / max(ww, 1e-4))
    py0 = wpy * (H0 / max(wh, 1e-4))
    yy0, xx0 = np.mgrid[0:H0, 0:W0]
    # 保护中心人物面部与躯干核心区，仅转化向外迸射的白色光刺与暖橙爆光
    face_core = (np.abs(xx0 - px0) < 34) & (yy0 > (py0 - 185)) & (yy0 < (py0 - 95))
    rgb = D[..., :3].astype(np.int16)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    a = D[..., 3]
    mx = rgb.max(axis=-1)
    ch = mx - rgb.min(axis=-1)

    warm_fire = (a > 20) & (~skin_shield) & ((r - b) >= 22) & (mx >= 115)
    white_spikes = (a > 24) & (~skin_shield) & (~face_core) & (ch <= 48) & (mx >= 175)
    burst_unpad = warm_fire | white_spikes

    PAD = 28
    Dp, ww_p, wh_p, wpx_p, wpy_p = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
    HP, WP = Dp.shape[:2]
    burst_pad = taper_clipped_mask_borders(burst_unpad, PAD)
    raw_pad = np.pad(burst_unpad, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
    Dp[raw_pad] = 0

    if burst_pad.sum() >= 80:
        m2 = cv2.resize(burst_pad.astype(np.uint8), (WP * 2, HP * 2), interpolation=cv2.INTER_NEAREST)
        sm = cv2.GaussianBlur(m2.astype(np.float32), (0, 0), 3.6) > 0.44
        din = cv2.distanceTransform(sm.astype(np.uint8), cv2.DIST_L2, 3)
        dout = cv2.distanceTransform((~sm).astype(np.uint8), cv2.DIST_L2, 3)
        b2 = np.zeros((HP * 2, WP * 2, 4), dtype=np.uint8)
        b2[sm] = [152, 104, 255, 245]
        b2[sm & (din >= 5.5)] = [248, 242, 255, 255]
        glow = (~sm) & (dout <= 9.0)
        b2[glow, :3] = [124, 72, 235]
        b2[glow, 3] = np.clip((9.0 - dout[glow]) / 9.0 * 145.0, 0, 255).astype(np.uint8)
        burst_rgba = cv2.resize(b2, (WP, HP), interpolation=cv2.INTER_AREA)
        base_pil = Image.fromarray(Dp)
        base_pil.alpha_composite(Image.fromarray(burst_rgba))
        Dp = np.array(base_pil)

    piv_p = (wpx_p * (WP / max(ww_p, 1e-4)), wpy_p * (HP / max(wh_p, 1e-4)))
    Dp = composite_ai_feathers(Dp, piv_p, vfx_lib, count=3, seed=9400 + idx * 23, spread_dir=1.0 if idx % 2 == 0 else -1.0)
    return Dp, ww_p, wh_p, wpx_p, wpy_p


# ==============================================================================
# 5. 左右冲刺全序列高清躯干 + AI 特效合成器（彻底消灭无头/悬浮断头/糊团坏帧）
# ==============================================================================
def strip_aihd_white_streaks(arr: np.ndarray) -> np.ndarray:
    """剥离 ai-hd 冲刺疾行帧上附带的旧版纯白速度线，完整保留高清角色本体与发光紫剑。"""
    out = arr.copy()
    skin_shield = compute_skin_shield(out)
    rgb = out[..., :3].astype(np.int16)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    a = out[..., 3]
    mx = rgb.max(axis=-1)
    ch = mx - rgb.min(axis=-1)
    white_streak = (a > 20) & (~skin_shield) & (ch <= 40) & (np.abs(r - b) <= 10) & (mx >= 182)
    n_c, lab_c, st_c, _ = cv2.connectedComponentsWithStats(white_streak.astype(np.uint8), connectivity=8)
    for ci in range(1, n_c):
        if st_c[ci, cv2.CC_STAT_AREA] >= 120:
            m = lab_c == ci
            m_dil = cv2.dilate(m.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
            fringe = m_dil & (~skin_shield) & (ch <= 50) & (mx >= 135)
            out[m | fringe] = 0
    return AIVfxLibrary._clean_tiny_isolated_specks(out, min_keep_area=120)


def build_clean_dash_frame(
    clip_key: str,
    idx: int,
    fd_orig: dict,
    sprite_cfg: dict,
    hd_map: Dict[int, Tuple[np.ndarray, float, float, float, float]],
    vfx_lib: AIVfxLibrary,
) -> Tuple[np.ndarray, float, float, float, float]:
    """
    针对 dash_left / dash_left_video (0..20) 与 dash_right / dash_right_video (0..34)：
    全程以 ai-hd 100% 完好无损的高清角色躯干为唯一人物底座，彻底根除原视频中的无头裤腿、悬浮巨型断头与泥褐糊团！
    """
    is_left = clip_key in ("dash_left", "dash_left_video")

    if is_left:
        # hd_map keys: [0, 3, 6, 9, 11, 14, 17, 20] (注意 sf=6 头部被白块遮挡，改用完好的 sf=3 疾冲躯干！)
        if idx <= 1:
            D, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[0]]
        elif idx <= 7:
            D_raw, ww, wh, wpx, wpy = hd_map[3]
            D = strip_aihd_white_streaks(D_raw)
        elif idx in (8, 9):
            D_raw, ww, wh, wpx, wpy = hd_map[9]
            D = D_raw.copy()
            # 将 sf=9 前方白色横扫刀弧升级为 AI 书法冷紫刀光
            skin_s = compute_skin_shield(D)
            rgb = D[..., :3].astype(np.int16)
            ch = rgb.max(-1) - rgb.min(-1)
            sl = (D[..., 3] > 24) & (~skin_s) & (ch <= 44) & (np.abs(rgb[..., 0] - rgb[..., 2]) <= 10) & (rgb.max(-1) >= 165)
            PAD = 28
            D, ww, wh, wpx, wpy = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
            sl_p = taper_clipped_mask_borders(sl, PAD)
            if sl_p.sum() >= 80:
                sl_hd = render_ai_calligraphy_slash(sl_p, D, vfx_lib, seed=5100 + idx, add_star_tip=True)
                raw_p = np.pad(sl, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
                D[raw_p] = 0
                bp = Image.fromarray(D)
                bp.alpha_composite(Image.fromarray(sl_hd))
                D = np.array(bp)
        elif idx in (10, 11, 12):
            # 采用 sf=11 超清蹲斩人物底座 + 原帧/sf=11 顶部满弧 AI 书法巨月牙！
            D_hd11, ww11, wh11, wpx11, wpy11 = hd_map[11]
            body_clean = strip_aihd_white_streaks(D_hd11)
            if idx == 10:
                # 提取原帧 f10 的超宽满月刀光遮罩，以世界锚点对齐叠加在高清蹲姿人物上方
                raw10, r_ww, r_wh, r_px, r_py = load_original_unpadded_base(sprite_cfg, fd_orig)
                sl10, _, _, _ = RS.classify(raw10, r_py * (raw10.shape[0] / max(r_wh, 1e-4)), dash=True)
                PAD = 36
                raw10_p, r_ww_p, r_wh_p, r_px_p, r_py_p = pad_canvas_with_pivot(raw10, r_ww, r_wh, r_px, r_py, PAD)
                sl10_p = taper_clipped_mask_borders(sl10, PAD)
                sl10_hd = render_ai_calligraphy_slash(sl10_p, raw10_p, vfx_lib, seed=5210, add_star_tip=True, solid_crescent=True)
                # 统一到 r_ww_p 画布并将高清人物按锚点贴合
                CW, CH = raw10_p.shape[1], raw10_p.shape[0]
                sx_c, sy_c = CW / r_ww_p, CH / r_wh_p
                bw_px = max(4, int(round(ww11 * sx_c)))
                bh_px = max(4, int(round(wh11 * sy_c)))
                b_resized = cv2.resize(body_clean, (bw_px, bh_px), interpolation=cv2.INTER_LANCZOS4)
                canvas = Image.new("RGBA", (CW + 80, CH + 80), (0, 0, 0, 0))
                ox_b = int(round(40 + (r_px_p - wpx11) * sx_c))
                oy_b = int(round(40 + (r_py_p - wpy11) * sy_c))
                canvas.alpha_composite(Image.fromarray(b_resized), (max(0, ox_b), max(0, oy_b)))
                canvas.alpha_composite(Image.fromarray(sl10_hd), (40, 40))
                D = np.array(canvas)
                ww = D.shape[1] / sx_c
                wh = D.shape[0] / sy_c
                wpx = r_px_p + 40.0 / sx_c
                wpy = r_py_p + 40.0 / sy_c
            else:
                # f11, f12：直接将 sf=11 高清顶弧升级为 AI 书法冷紫弧
                D = D_hd11.copy()
                ww, wh, wpx, wpy = ww11, wh11, wpx11, wpy11
                skin_s = compute_skin_shield(D)
                rgb = D[..., :3].astype(np.int16)
                ch = rgb.max(-1) - rgb.min(-1)
                sl = (D[..., 3] > 24) & (~skin_s) & (ch <= 44) & (np.abs(rgb[..., 0] - rgb[..., 2]) <= 10) & (rgb.max(-1) >= 165)
                PAD = 32
                D, ww, wh, wpx, wpy = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
                sl_p = taper_clipped_mask_borders(sl, PAD)
                if sl_p.sum() >= 80:
                    sl_hd = render_ai_calligraphy_slash(sl_p, D, vfx_lib, seed=5200 + idx, add_star_tip=True)
                    raw_p = np.pad(sl, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
                    D[raw_p] = 0
                    bp = Image.fromarray(D)
                    bp.alpha_composite(Image.fromarray(sl_hd))
                    D = np.array(bp)
                if idx == 12:
                    D, ww, wh, wpx, wpy = apply_foot_locked_micro_warp(D, ww, wh, wpx, wpy, (0.99, 1.01, -2.5, 0.0, 0.0), -1)
        else:
            # f13..20：平滑衔接 sf=14, 17, 20
            keys = [14, 17, 20]
            near_k = min(keys, key=lambda k: abs(k - idx))
            D, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[near_k]]
        return D, ww, wh, wpx, wpy

    else:
        # dash_right / dash_right_video: hd_map keys [0, 5, 10, 15, 19, 24, 29, 34]
        if idx <= 2:
            D, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[0]]
        elif idx <= 8:
            D_raw, ww, wh, wpx, wpy = hd_map[5]
            D = strip_aihd_white_streaks(D_raw)
        elif idx in (9, 10):
            D_raw, ww, wh, wpx, wpy = hd_map[10]
            D = D_raw.copy()
            skin_s = compute_skin_shield(D)
            rgb = D[..., :3].astype(np.int16)
            ch = rgb.max(-1) - rgb.min(-1)
            sl = (D[..., 3] > 24) & (~skin_s) & (ch <= 44) & (np.abs(rgb[..., 0] - rgb[..., 2]) <= 10) & (rgb.max(-1) >= 165)
            PAD = 28
            D, ww, wh, wpx, wpy = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
            sl_p = taper_clipped_mask_borders(sl, PAD)
            if sl_p.sum() >= 80:
                sl_hd = render_ai_calligraphy_slash(sl_p, D, vfx_lib, seed=6100 + idx, add_star_tip=True)
                raw_p = np.pad(sl, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
                D[raw_p] = 0
                bp = Image.fromarray(D)
                bp.alpha_composite(Image.fromarray(sl_hd))
                D = np.array(bp)
        elif idx in (11, 12, 13):
            # 采用 sf=15 超清蹲斩人物底座（隐去右上高举收势直剑刃避免与挥斩巨弧穿插）+ 原帧 f11..13 巨型满弧书法刀光！
            D_hd15, ww15, wh15, wpx15, wpy15 = hd_map[15]
            body15 = D_hd15.copy()
            Hb, Wb = body15.shape[:2]
            yy_b, xx_b = np.mgrid[0:Hb, 0:Wb]
            # 仅擦除右上角高举过头顶的收势直剑刃段 (x > 72%, y < 48%)，100% 保留人物头、发、手、身、双靴！
            body15[(xx_b > int(Wb * 0.72)) & (yy_b < int(Hb * 0.48))] = 0

            raw_f, r_ww, r_wh, r_px, r_py = load_original_unpadded_base(sprite_cfg, fd_orig)
            sl_f, _, _, _ = RS.classify(raw_f, r_py * (raw_f.shape[0] / max(r_wh, 1e-4)), dash=True)
            PAD = 36
            raw_p, r_ww_p, r_wh_p, r_px_p, r_py_p = pad_canvas_with_pivot(raw_f, r_ww, r_wh, r_px, r_py, PAD)
            sl_p = taper_clipped_mask_borders(sl_f, PAD)
            sl_hd = render_ai_calligraphy_slash(sl_p, raw_p, vfx_lib, seed=6200 + idx, add_star_tip=True, solid_crescent=(idx == 12))

            CW, CH = raw_p.shape[1], raw_p.shape[0]
            sx_c, sy_c = CW / r_ww_p, CH / r_wh_p
            bw_px = max(4, int(round(ww15 * sx_c * 0.92)))
            bh_px = max(4, int(round(wh15 * sy_c * 0.92)))
            b_resized = cv2.resize(body15, (bw_px, bh_px), interpolation=cv2.INTER_LANCZOS4)
            canvas = Image.new("RGBA", (CW + 80, CH + 80), (0, 0, 0, 0))
            ox_b = int(round(40 + (r_px_p - wpx15 * 0.92) * sx_c))
            oy_b = int(round(40 + (r_py_p - wpy15 * 0.92) * sy_c))
            canvas.alpha_composite(Image.fromarray(b_resized), (max(0, ox_b), max(0, oy_b)))
            canvas.alpha_composite(Image.fromarray(sl_hd), (40, 40))
            D = np.array(canvas)
            ww = D.shape[1] / sx_c
            wh = D.shape[0] / sy_c
            wpx = r_px_p + 40.0 / sx_c
            wpy = r_py_p + 40.0 / sy_c
        elif idx <= 21:
            near_k = 15 if idx <= 16 else 19
            D, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[near_k]]
        else:
            # dash_right f22..34 刹步尾烟帧：采用 hd_map[24,29,34] 扩边磨圆并将身后白浪染成银紫破风气浪，消除 B294/R101 硬裁切！
            keys = [24, 29, 34]
            near_k = min(keys, key=lambda k: abs(k - idx))
            D_raw, ww, wh, wpx, wpy = hd_map[near_k]
            D = D_raw.copy()
            H0, W0 = D.shape[:2]
            skin_s = compute_skin_shield(D)
            rgb = D[..., :3].astype(np.int16)
            ch = rgb.max(-1) - rgb.min(-1)
            yy0, xx0 = np.mgrid[0:H0, 0:W0]
            wake_unpad = (D[..., 3] > 20) & (~skin_s) & (xx0 > int(W0 * 0.36)) & (ch <= 42) & (rgb.max(-1) >= 165)
            PAD = 36
            D, ww, wh, wpx, wpy = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD)
            wake_p = taper_clipped_mask_borders(wake_unpad, PAD)
            raw_p = np.pad(wake_unpad, ((PAD, PAD), (PAD, PAD)), mode="constant", constant_values=False)
            D[raw_p] = 0
            if wake_p.sum() >= 80:
                wake_hd = render_ai_calligraphy_slash(wake_p, D, vfx_lib, seed=6300 + idx, add_star_tip=False)
                # 随帧号 22->34 自然淡出尾浪透明度
                fade_t = max(0.35, 1.0 - (idx - 22) / 16.0)
                wake_hd[..., 3] = (wake_hd[..., 3].astype(np.float32) * fade_t).astype(np.uint8)
                bp = Image.fromarray(D)
                bp.alpha_composite(Image.fromarray(wake_hd))
                D = np.array(bp)
        return D, ww, wh, wpx, wpy


# ==============================================================================
# 6. 锁死脚底锚点的角色动作微调引擎 + 全招式严格边界守恒 durationTicks 重排
# ==============================================================================
def get_sakuga_posture_params(clip_key: str, idx: int, total: int) -> Tuple[float, float, float, float, float]:
    sx, sy, tilt, dx, dy = 1.0, 1.0, 0.0, 0.0, 0.0

    if clip_key == "attack_1":
        curve = [
            (1.00, 1.00,  0.0,  0.0, 0.0),
            (1.01, 0.99, -0.6, -2.0, 0.0),
            (1.02, 0.98, -1.2, -4.0, 0.0),
            (1.03, 0.97, -2.0, -6.0, 0.0),
            (0.98, 1.03, -2.6, -8.0, 0.0),
            (1.05, 0.96,  2.8, 12.0, 0.0),
            (1.04, 0.97,  2.4, 16.0, 0.0),
            (1.02, 0.98,  1.6, 13.0, 0.0),
            (1.01, 0.99,  1.0,  9.0, 0.0),
            (1.00, 1.00,  0.5,  6.0, 0.0),
            (1.00, 1.00,  0.2,  3.5, 0.0),
            (1.00, 1.00,  0.0,  1.5, 0.0),
            (1.00, 1.00,  0.0,  0.0, 0.0),
        ]
        return curve[min(idx, len(curve) - 1)]

    elif clip_key in ("attack_2", "attack_2_start"):
        if idx <= 2:
            w = idx / 2.0
            return (1.0 + 0.03 * w, 1.0 - 0.03 * w, -1.8 * w, -5.0 * w, 0.0)
        elif idx <= 6:
            w = 1.0 - (idx - 3) / 4.0 * 0.35
            return (1.0 + 0.045 * w, 1.0 - 0.035 * w, 2.6 * w, 13.0 * w, 0.0)
        else:
            w = max(0.0, 1.0 - (idx - 6) / max(1, total - 1 - 6))
            return (1.0 + 0.015 * w, 1.0 - 0.01 * w, 1.2 * w, 8.0 * w, 0.0)

    elif clip_key == "attack_3":
        if idx == 0:
            return (1.03, 0.97, -2.2, -6.0, 0.0)
        elif idx <= 6:
            p = math.sin((idx - 1) / 5.0 * math.pi * 0.65 + 0.35)
            return (1.0 + 0.05 * p, 1.0 - 0.04 * p, 3.0 * p, 16.0 * p, 0.0)
        else:
            w = max(0.0, 1.0 - (idx - 6) / max(1, total - 1 - 6)) ** 1.4
            return (1.0 + 0.02 * w, 1.0 - 0.015 * w, 1.6 * w, 10.0 * w, 0.0)

    elif clip_key in ("strong_attack", "attack_up"):
        if 3 <= idx <= 7:
            w = (idx - 2) / 5.0
            return (1.0 + 0.045 * w, 1.0 - 0.045 * w, -1.8 * w, -4.0 * w, 0.0)
        elif 8 <= idx <= 13:
            w = math.sin((idx - 7) / 6.0 * math.pi)
            return (1.0 - 0.045 * w, 1.0 + 0.06 * w, -2.4 * w, 8.0 * w, -6.0 * w)
        elif idx > 13:
            w = max(0.0, 1.0 - (idx - 13) / max(1, total - 1 - 13))
            return (1.0, 1.0 + 0.015 * w, -0.8 * w, 4.0 * w, 0.0)

    elif clip_key in ("air_attack_1", "air_attack_2", "air_attack_3", "air_slash"):
        peak = 9 if clip_key in ("air_attack_1", "air_slash") else 4
        dist = idx - peak
        if dist < 0:
            w = max(0.0, 1.0 + dist / max(2.0, float(peak)))
            return (1.0 + 0.02 * w, 1.0 - 0.02 * w, -2.0 * w, -3.0 * w, 0.0)
        else:
            w = max(0.0, 1.0 - dist / max(3.0, float(total - peak)))
            return (1.0 + 0.04 * w, 1.0 - 0.03 * w, 2.8 * w, 9.0 * w, 2.0 * w)

    elif clip_key in ("dash_right_video", "dash_right", "dash_left_video", "dash_left"):
        if 1 <= idx <= 11:
            w = math.sin(min(1.0, idx / 9.0) * math.pi * 0.75 + 0.2)
            return (1.0 + 0.045 * w, 1.0 - 0.038 * w, 2.8 * w, 10.0 * w, 0.0)
        elif idx > 11:
            w = max(0.0, 1.0 - (idx - 11) / max(1, total - 1 - 11))
            return (1.0 + 0.015 * w, 1.0 - 0.012 * w, -1.2 * w, 4.0 * w, 0.0)

    elif clip_key == "jump":
        if idx <= 1:
            return (1.05, 0.94, 1.2, 0.0, 0.0)
        elif idx <= 5:
            w = 1.0 - (idx - 2) / 4.0 * 0.5
            return (1.0 - 0.045 * w, 1.0 + 0.055 * w, -1.5 * w, 0.0, -4.0 * w)
        return (1.0, 1.01, 0.0, 0.0, 0.0)

    elif clip_key == "fall":
        ang = 2.0 * math.pi * idx / max(1, total)
        return (1.0 - 0.015 * math.sin(ang), 1.02 + 0.018 * math.sin(ang), 1.4 * math.cos(ang), 0.0, 0.0)

    elif clip_key == "land":
        curve_l = [
            (0.98, 1.02,  0.5, 0.0, 0.0),
            (1.05, 0.93,  1.8, 2.0, 0.0),
            (1.06, 0.92,  2.0, 3.0, 0.0),
            (1.03, 0.96,  1.2, 2.0, 0.0),
            (0.99, 1.015, 0.2, 0.5, 0.0),
            (0.995,1.01,  0.0, 0.0, 0.0),
            (1.00, 1.00,  0.0, 0.0, 0.0),
            (1.00, 1.00,  0.0, 0.0, 0.0),
        ]
        return curve_l[min(idx, len(curve_l) - 1)]

    elif clip_key in ("turn_left_right", "turn_right_left"):
        mid = total // 2
        if idx < mid:
            w = (idx + 1) / max(1, mid)
            return (1.02 * w + (1 - w), 1.0 - 0.02 * w, -2.2 * w, -3.0 * w, 0.0)
        else:
            w = 1.0 - (idx - mid) / max(1, total - 1 - mid)
            return (1.0 + 0.025 * w, 1.0 - 0.02 * w, 2.4 * w, 4.0 * w, 0.0)

    elif clip_key == "guard_hold":
        ang = 2.0 * math.pi * idx / max(1, total)
        return (1.0 + 0.012 * math.sin(ang), 1.0 - 0.016 * math.sin(ang), 0.7 * math.sin(ang), 1.0 * math.cos(ang), 0.0)

    elif clip_key in ("guard_hit_1", "guard_hit_2", "guard_hit_3"):
        if idx <= 2:
            w = 1.0 - idx * 0.22
            return (1.04 * w + (1 - w), 1.0 - 0.04 * w, -2.5 * w, -7.5 * w, 0.0)
        else:
            w = max(0.0, 1.0 - (idx - 2) / max(1, min(10, total - 3)))
            return (1.0 + 0.015 * w, 1.0 - 0.015 * w, -1.0 * w, -3.5 * w, 0.0)

    elif clip_key in ("parry_react_1", "parry_react_2", "parry_react_3"):
        if idx <= 2:
            w = 1.0 - idx * 0.25
            return (1.03, 0.97, -1.8 * w, -4.5 * w, 0.0)
        elif 5 <= idx <= 10:
            w = math.sin((idx - 4) / 7.0 * math.pi)
            return (1.0 + 0.035 * w, 1.0 - 0.025 * w, 2.4 * w, 9.0 * w, 0.0)

    elif clip_key == "charge_slash":
        if 10 <= idx <= 18:
            w = (idx - 9) / 9.0
            return (1.0 + 0.04 * w, 1.0 - 0.04 * w, -2.2 * w, -5.0 * w, 0.0)
        elif 19 <= idx <= 30:
            w = math.sin((idx - 18) / 13.0 * math.pi)
            return (1.0 + 0.045 * w, 1.0 - 0.03 * w, 2.6 * w, 12.0 * w, 0.0)

    elif clip_key in ("draw", "sheathe"):
        peak = 36 if clip_key == "draw" else 11
        if abs(idx - peak) <= 4:
            w = 1.0 - abs(idx - peak) / 5.0
            return (1.0 + 0.025 * w, 1.0 - 0.02 * w, 1.6 * w, 4.0 * w, 0.0)

    return (sx, sy, tilt, dx, dy)


def apply_foot_locked_micro_warp(
    rgba: np.ndarray,
    world_w: float,
    world_h: float,
    world_px: float,
    world_py: float,
    params: Tuple[float, float, float, float, float],
    source_facing: int = 1,
) -> Tuple[np.ndarray, float, float, float, float]:
    sx_m, sy_m, tilt_deg, dx_w, dy_w = params
    if source_facing == -1:
        dx_w = -dx_w
        tilt_deg = -tilt_deg

    H, W = rgba.shape[:2]
    px_u = W / max(world_w, 1e-4)
    py_u = H / max(world_h, 1e-4)

    need_warp = (
        abs(sx_m - 1.0) > 1e-3
        or abs(sy_m - 1.0) > 1e-3
        or abs(tilt_deg) > 0.08
        or abs(dx_w) > 0.1
        or abs(dy_w) > 0.1
    )

    if need_warp:
        pad_x = int(math.ceil(W * 0.18 + abs(dx_w) * px_u + 24))
        pad_y = int(math.ceil(H * 0.18 + abs(dy_w) * py_u + 24))
        canvas = cv2.copyMakeBorder(rgba, pad_y, pad_y, pad_x, pad_x, cv2.BORDER_CONSTANT, value=(0, 0, 0, 0))
        piv_cx = world_px * px_u + pad_x
        piv_cy = world_py * py_u + pad_y

        rad = math.radians(tilt_deg)
        cos_a, sin_a = math.cos(rad), math.sin(rad)
        m00, m01 = cos_a * sx_m, -sin_a * sy_m
        m10, m11 = sin_a * sx_m,  cos_a * sy_m
        tx = piv_cx - (m00 * piv_cx + m01 * piv_cy)
        ty = piv_cy - (m10 * piv_cx + m11 * piv_cy)
        M = np.array([[m00, m01, tx], [m10, m11, ty]], dtype=np.float32)

        rgb_f = canvas[..., :3].astype(np.float32)
        a_f = canvas[..., 3:4].astype(np.float32) / 255.0
        pre = np.concatenate([rgb_f * a_f, a_f * 255.0], axis=-1)
        warped_pre = cv2.warpAffine(
            pre, M, (canvas.shape[1], canvas.shape[0]),
            flags=cv2.INTER_LANCZOS4, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0),
        )
        wa = np.clip(warped_pre[..., 3:4] / 255.0, 0.0, 1.0)
        wrgb = np.where(wa > 1e-3, warped_pre[..., :3] / np.maximum(wa, 1e-3), 0.0)
        rgba = np.concatenate([
            np.clip(np.round(wrgb), 0, 255).astype(np.uint8),
            np.clip(np.round(wa * 255.0), 0, 255).astype(np.uint8),
        ], axis=-1)

        world_w = rgba.shape[1] / px_u
        world_h = rgba.shape[0] / py_u
        world_px = (piv_cx / px_u) - dx_w
        world_py = (piv_cy / py_u) - dy_w

    ys, xs = np.where(rgba[..., 3] > 4)
    if len(xs) == 0:
        return rgba[:8, :8], 8.0 / px_u, 8.0 / py_u, 4.0 / px_u, 4.0 / py_u

    H_cur, W_cur = rgba.shape[:2]
    margin = 8
    x0 = max(0, int(xs.min()) - margin)
    y0 = max(0, int(ys.min()) - margin)
    x1 = min(W_cur, int(xs.max()) + 1 + margin)
    y1 = min(H_cur, int(ys.max()) + 1 + margin)

    cropped = rgba[y0:y1, x0:x1].copy()
    new_world_w = (x1 - x0) / px_u
    new_world_h = (y1 - y0) / py_u
    new_world_px = world_px - (x0 / px_u)
    new_world_py = world_py - (y0 / py_u)
    return cropped, new_world_w, new_world_h, new_world_px, new_world_py


def re_pace_duration_ticks(clip_key: str, frames: List[dict], moves_list: List[dict], sprite_cfg: dict) -> None:
    N = len(frames)
    if N < 3 or clip_key in ("charge_hold", "run", "idle", "death"):
        return

    orig_ticks = [float(f.get("durationTicks", 1.0)) for f in frames]

    # 纳入所有引用该动画的招式帧边界（含 syncAnimation=False 的 ranged_1 等），确保 ticks_before 零漂移！
    boundaries = {0, N}
    active_ranges: List[Tuple[int, int]] = []
    for mv in moves_list:
        if mv.get("animation") == clip_key:
            if mv.get("activeFrameStart") is not None:
                s = max(0, min(N, int(mv["activeFrameStart"])))
                boundaries.add(s)
            else:
                s = 0
            if mv.get("activeFrameEnd") is not None:
                e = max(0, min(N, int(mv["activeFrameEnd"]) + 1))
                boundaries.add(e)
            else:
                e = 0
            if mv.get("chainFrame") is not None:
                boundaries.add(max(0, min(N, int(mv["chainFrame"]))))
            if mv.get("syncAnimation", False):
                active_ranges.append((s, e))
            if mv.get("burstFrameStart") is not None:
                boundaries.add(max(0, min(N, int(mv["burstFrameStart"]))))
            if mv.get("burstFrameEnd") is not None:
                boundaries.add(max(0, min(N, int(mv["burstFrameEnd"]))))

    loco = sprite_cfg.get("locomotion", {})
    if clip_key == "turn_left_right":
        tr = loco.get("turnRight", {})
        boundaries.update([int(tr.get("flipFrame", 3)), int(tr.get("cancelFrame", 4))])
    elif clip_key == "turn_right_left":
        tl = loco.get("turnLeft", {})
        boundaries.update([int(tl.get("flipFrame", 2)), int(tl.get("cancelFrame", 3))])
    elif clip_key == "land":
        boundaries.update([int(loco.get("landingCancelFrame", 2)), int(loco.get("heavyLandingCancelFrame", 2))])

    sorted_b = sorted(boundaries)

    for b_idx in range(len(sorted_b) - 1):
        a, b = sorted_b[b_idx], sorted_b[b_idx + 1]
        seg_len = b - a
        if seg_len < 2:
            continue
        seg_sum = sum(orig_ticks[a:b])

        is_active = any(a >= rs and b <= re for rs, re in active_ranges)
        is_windup = any(b == rs and rs > 0 for rs, _ in active_ranges)
        is_post = any(a == re for _, re in active_ranges)

        if is_windup:
            weights = np.linspace(0.76, 1.05, seg_len)
            weights[-1] = 1.45
        elif is_active:
            weights = np.linspace(0.68, 1.12, seg_len)
            weights[0] = 0.62
            weights[-1] = 1.38
        elif is_post:
            weights = np.linspace(1.28, 0.86, seg_len)
        elif clip_key == "jump":
            weights = np.linspace(0.76, 1.24, seg_len)
        elif clip_key == "land":
            weights = np.array([1.28 if k == 0 else 0.92 for k in range(seg_len)], dtype=np.float64)
        else:
            weights = np.linspace(0.90, 1.10, seg_len)

        raw_new = np.array(orig_ticks[a:b], dtype=np.float64) * weights
        scaled = raw_new * (seg_sum / float(raw_new.sum()))
        rounded = [round(float(x), 4) for x in scaled]
        rounded[-1] = round(seg_sum - sum(rounded[:-1]), 4)
        for k in range(seg_len):
            frames[a + k]["durationTicks"] = max(0.15, rounded[k])


# ==============================================================================
# 7. 单剪辑完整合成管线
# ==============================================================================
def load_original_unpadded_base(sprite_cfg: dict, fd: dict) -> Tuple[Optional[np.ndarray], float, float, float, float]:
    if fd.get("blank", False):
        return None, 0.0, 0.0, 0.0, 0.0
    asset = fd.get("asset", "")
    if not asset:
        return None, 0.0, 0.0, 0.0, 0.0

    ov = sprite_cfg.get("assetOverride", {})
    fx_pad = int(sprite_cfg.get("assetFxPad", {}).get(asset, 0))
    if asset in ov or asset in sprite_cfg.get("assetFxBase", {}) or asset in sprite_cfg.get("assetCleanup", {}):
        D = RS.load_base(sprite_cfg, asset)
    else:
        full_p = ASSETS / asset
        D = np.array(Image.open(full_p).convert("RGBA"))

    H0, W0 = D.shape[:2]
    fw = float(fd.get("width", W0 + 2 * fx_pad))
    fh = float(fd.get("height", H0 + 2 * fx_pad))
    fpx = float(fd.get("pivotX", fw * 0.5))
    fpy = float(fd.get("pivotY", fh))

    sx = fw / float(W0 + 2 * fx_pad)
    sy = fh / float(H0 + 2 * fx_pad)
    world_w = W0 * sx
    world_h = H0 * sy
    world_px = fpx - fx_pad * sx
    world_py = fpy - fx_pad * sy
    return D, world_w, world_h, world_px, world_py


def load_ai_hd_pose_map(ai_hd_data: dict, clip_key: str) -> Dict[int, Tuple[np.ndarray, float, float, float, float]]:
    # 别名剪辑复用对应母版的 ai-hd 高清帧
    lookup_key = {
        "dash_left_video": "dash_left",
        "dash_right_video": "dash_right",
        "parry": "guard_start",
        "attack_up": "strong_attack",
        "air_slash": "air_attack_1",
    }.get(clip_key, clip_key)

    out = {}
    clip_entry = ai_hd_data.get("clips", {}).get(lookup_key, {})
    for fr in clip_entry.get("frames", []):
        sf = int(fr["sourceFrame"])
        fp = ASSETS / fr["asset"]
        if fp.exists():
            arr = np.array(Image.open(fp).convert("RGBA"))
            out[sf] = (
                arr,
                float(fr["width"]),
                float(fr["height"]),
                float(fr["pivotX"]),
                float(fr["pivotY"]),
            )
    return out


def blend_adjacent_hd_pose(
    pose_a: Tuple[np.ndarray, float, float, float, float],
    pose_b: Tuple[np.ndarray, float, float, float, float],
    t: float = 0.5,
) -> Tuple[np.ndarray, float, float, float, float]:
    arr_a, wa, ha, pxa, pya = pose_a
    arr_b, wb, hb, pxb, pyb = pose_b
    use_a = t <= 0.5
    base_arr, bw, bh, bpx, bpy = (arr_a, wa, ha, pxa, pya) if use_a else (arr_b, wb, hb, pxb, pyb)
    w_interp = wa * (1.0 - t) + wb * t
    scale_r = w_interp / max(bw, 1e-4)
    return base_arr.copy(), bw * scale_r, bh * scale_r, bpx * scale_r, bpy * scale_r


def add_guard_blade_shimmer(rgba: np.ndarray, phase_01: float) -> np.ndarray:
    out = rgba.copy()
    h, w = out.shape[:2]
    rgb = out[..., :3].astype(np.int16)
    a = out[..., 3] > 60
    xx = np.arange(w)[None, :]
    yy = np.arange(h)[:, None]
    blade = a & (xx > int(w * 0.52)) & (rgb[..., 2] > 145) & ((rgb[..., 2] - rgb[..., 1]) > 18)
    if blade.sum() < 40:
        return out
    ys, xs = np.where(blade)
    y_min, y_max = float(ys.min()), float(ys.max())
    band_y = y_max - phase_01 * (y_max - y_min)
    sigma = max(14.0, (y_max - y_min) * 0.16)
    glow = np.exp(-0.5 * ((yy - band_y) / sigma) ** 2) * blade.astype(np.float32)
    boost = glow[..., None] * np.array([75.0, 58.0, 95.0], dtype=np.float32)
    out[..., :3] = np.clip(out[..., :3].astype(np.float32) + boost, 0, 255).astype(np.uint8)
    if 0.72 <= phase_01 <= 0.95:
        tip_idx = int(np.argmin(ys))
        out = draw_cold_violet_star(out, float(xs[tip_idx]), float(ys[tip_idx]), radius=14.0)
    return out


def process_single_clip(
    clip_key: str,
    clip_dict: dict,
    sprite_cfg: dict,
    moves_list: List[dict],
    ai_hd_data: dict,
    vfx_lib: AIVfxLibrary,
    man_1106_parry1: dict,
) -> dict:
    new_clip = copy.deepcopy(clip_dict)
    frames = new_clip.get("frames", [])
    source_facing = int(new_clip.get("sourceFacing", 1))
    out_clip_dir = OUT_ABS_ROOT / clip_key
    out_clip_dir.mkdir(parents=True, exist_ok=True)

    hd_map = load_ai_hd_pose_map(ai_hd_data, clip_key)

    # ------------------------------------------------------------------
    # 特例 A：guard_hold 8 帧 12fps 蓄势呼吸流光循环
    # ------------------------------------------------------------------
    if clip_key == "guard_hold" and 0 in hd_map:
        base_arr, ww, wh, wpx, wpy = hd_map[0]
        base_hd = enhance_cel_body_hd(base_arr, target_scale=1.0, is_already_hd=True)
        expanded_frames = []
        for i in range(8):
            shimmered = add_guard_blade_shimmer(base_hd, phase_01=i / 8.0)
            params = get_sakuga_posture_params("guard_hold", i, 8)
            final_rgba, n_ww, n_wh, n_px, n_py = apply_foot_locked_micro_warp(
                shimmered, ww, wh, wpx, wpy, params, source_facing=source_facing
            )
            fn = f"frame_{i + 1:05d}.png"
            Image.fromarray(final_rgba).save(out_clip_dir / fn, optimize=False)
            expanded_frames.append({
                "asset": f"{OUT_REL_ROOT}/{clip_key}/{fn}",
                "width": round(n_ww, 3),
                "height": round(n_wh, 3),
                "pivotX": round(n_px, 3),
                "pivotY": round(n_py, 3),
                "durationTicks": 1.0,
            })
        new_clip["fps"] = 12.0
        new_clip["loop"] = True
        new_clip["frames"] = expanded_frames
        return new_clip

    # ------------------------------------------------------------------
    # 特例 B：attack_1 (V6 原貌角色 + 纯 AI 满月书法弧 + 去悬浮黑墨点)
    # ------------------------------------------------------------------
    if clip_key == "attack_1" and len(vfx_lib.v6_a1_frames) == len(frames):
        N = len(frames)
        for i in range(N):
            v6_arr = vfx_lib.v6_a1_frames[i].copy()
            if i in (5, 6, 7):
                v6_arr = composite_ai_feathers(
                    v6_arr, (580.0, 860.0), vfx_lib,
                    count=(3 if i == 5 else 2), seed=1100 + i, spread_dir=1.0,
                )
            ww = 1536.0 * V6_TO_WORLD
            wh = 960.0 * V6_TO_WORLD
            wpx = 580.0 * V6_TO_WORLD
            wpy = 860.0 * V6_TO_WORLD
            params = get_sakuga_posture_params("attack_1", i, N)
            mild_params = (
                1.0 + (params[0] - 1.0) * 0.65,
                1.0 + (params[1] - 1.0) * 0.65,
                params[2] * 0.65,
                params[3] * 0.35,
                params[4] * 0.35,
            )
            final_rgba, n_ww, n_wh, n_px, n_py = apply_foot_locked_micro_warp(
                v6_arr, ww, wh, wpx, wpy, mild_params, source_facing=1
            )
            tw = max(4, int(round(n_ww * TEXEL_DENSITY)))
            th = max(4, int(round(n_wh * TEXEL_DENSITY)))
            if (final_rgba.shape[1], final_rgba.shape[0]) != (tw, th):
                final_rgba = cv2.resize(final_rgba, (tw, th), interpolation=cv2.INTER_AREA)

            fn = f"frame_{i + 1:05d}.png"
            Image.fromarray(final_rgba).save(out_clip_dir / fn, optimize=False)
            fd = frames[i]
            fd.pop("blank", None)
            fd.pop("region", None)
            fd["asset"] = f"{OUT_REL_ROOT}/{clip_key}/{fn}"
            fd["width"] = round(n_ww, 3)
            fd["height"] = round(n_wh, 3)
            fd["pivotX"] = round(n_px, 3)
            fd["pivotY"] = round(n_py, 3)

        re_pace_duration_ticks(clip_key, frames, moves_list, sprite_cfg)
        return new_clip

    # ------------------------------------------------------------------
    # 其余 34 套动作精准精修管线
    # ------------------------------------------------------------------
    N = len(frames)
    full_ai_hd_clips = {"turn_right_left", "jump", "fall", "land", "air_attack_2", "guard_hit_1", "guard_start", "parry"}
    is_dash_clip = clip_key in ("dash_left", "dash_left_video", "dash_right", "dash_right_video")

    for i in range(N):
        fd = frames[i]
        orig_asset = fd.get("asset", "")

        # 0. 修复 death[61] 空白闪烁坏帧
        if fd.get("blank", False):
            if clip_key == "death" and 0 < i < N - 1:
                fd = copy.deepcopy(clip_dict["frames"][i - 1])
                frames[i] = fd
                orig_asset = fd.get("asset", "")
            else:
                continue

        is_already_hd = False
        skip_slash_recolor = False
        extra_slash_arc = False

        # 1. 左右冲刺全序列：100% 采用完好无损 ai-hd 躯干 + AI 破风楔形/满弧书法光
        if is_dash_clip and len(hd_map) > 0:
            D, ww, wh, wpx, wpy = build_clean_dash_frame(clip_key, i, fd, sprite_cfg, hd_map, vfx_lib)
            is_already_hd = True
            skip_slash_recolor = True

        # 2. charge_hold 专项旋涡净化扩边与火花重绘
        elif clip_key == "charge_hold":
            D0, ww0, wh0, wpx0, wpy0 = load_original_unpadded_base(sprite_cfg, fd)
            D, ww, wh, wpx, wpy = process_charge_hold_frame(D0, ww0, wh0, wpx0, wpy0, i, vfx_lib)
            skip_slash_recolor = True

        # 3. charge_slash 专项四阶段精修（无洞满月弧 + 冲击轮廓 + 银紫震波气柱）
        elif clip_key == "charge_slash":
            D0, ww0, wh0, wpx0, wpy0 = load_original_unpadded_base(sprite_cfg, fd)
            D, ww, wh, wpx, wpy = process_charge_slash_frame(D0, ww0, wh0, wpx0, wpy0, i, vfx_lib)
            skip_slash_recolor = True

        # 4. death 爆裂段专项冷紫鸦羽化，其余帧 100% 保护原貌五官
        elif clip_key == "death":
            D0, ww0, wh0, wpx0, wpy0 = load_original_unpadded_base(sprite_cfg, fd)
            if 19 <= i <= 24:
                D, ww, wh, wpx, wpy = upgrade_death_burst_frame(D0, ww0, wh0, wpx0, wpy0, i, vfx_lib)
            else:
                D, ww, wh, wpx, wpy = D0, ww0, wh0, wpx0, wpy0
            skip_slash_recolor = True

        # 5. parry_react_1：f0..7 为 11-06 签收帧；f8..15 全量采用完好无断剑的 ai-hd 帧 (sf=9,11,13,15)！
        elif clip_key == "parry_react_1":
            if i < 8:
                f_info = man_1106_parry1["frames"][i]
                p1106 = REDRAW_1106_DIR / "弹刀1_前8帧_带刀光" / "帧" / f_info["file"]
                raw_base, b_ww, b_wh, b_px, b_py = load_original_unpadded_base(sprite_cfg, fd)
                H0, W0 = raw_base.shape[:2]
                sx_o, sy_o = b_ww / W0, b_wh / H0
                pad_1106 = float(man_1106_parry1["pad"])
                D = np.array(Image.open(p1106).convert("RGBA"))
                ww = b_ww + 2.0 * pad_1106 * sx_o
                wh = b_wh + 2.0 * pad_1106 * sy_o
                wpx = b_px + pad_1106 * sx_o
                wpy = b_py + pad_1106 * sy_o
                if i == 6:
                    D = draw_cold_violet_star(D, D.shape[1] * 0.78, D.shape[0] * 0.52, radius=30.0)
            elif i == 8:
                D_hd, ww, wh, wpx, wpy = hd_map[9]
                D, ww, wh, wpx, wpy = apply_foot_locked_micro_warp(D_hd.copy(), ww, wh, wpx, wpy, (1.0, 1.0, -9.5, -3.0, 0.0), 1)
                extra_slash_arc = True
            else:
                keys = [9, 11, 13, 15]
                if i in hd_map:
                    D, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[i]]
                else:
                    prev_k = max([k for k in keys if k < i], default=9)
                    next_k = min([k for k in keys if k > i], default=15)
                    D, ww, wh, wpx, wpy = blend_adjacent_hd_pose(hd_map[prev_k], hd_map[next_k], (i - prev_k) / max(1, next_k - prev_k))
            is_already_hd = True
            skip_slash_recolor = True

        # 6. parry_react_2：f5 继承完好无损的 fixed f4 躯干做微收势（根除原版与旧修版的残腰断腿），仅 f1,2,6 重绘刀光！
        elif clip_key == "parry_react_2" and i == 5:
            fd_f4 = clip_dict["frames"][4]
            D4, ww4, wh4, wpx4, wpy4 = load_original_unpadded_base(sprite_cfg, fd_f4)
            H4, _ = D4.shape[:2]
            D4[:int(H4 * 0.14), :] = 0
            D, ww, wh, wpx, wpy = apply_foot_locked_micro_warp(D4, ww4, wh4, wpx4, wpy4, (0.99, 1.01, 2.2, 1.5, 0.0), 1)
            skip_slash_recolor = True

        # 7. parry_react_3：f3..19 全量融合完好无损 ai-hd 帧 (sf=3,5,8,11,14,16,19)，根除吞身、裙侧白条、断剑槌与边缘白滴！
        elif clip_key == "parry_react_3" and i >= 3 and len(hd_map) > 0:
            if i in (5, 6, 7):
                D_hd, ww, wh, wpx, wpy = hd_map[5]
                D = D_hd.copy()
                rot = 0.0 if i == 5 else (3.6 if i == 6 else 7.2)
                if rot > 0.0:
                    D, ww, wh, wpx, wpy = apply_foot_locked_micro_warp(D, ww, wh, wpx, wpy, (1.01, 0.99, rot, 2.0, 0.0), 1)
                if i == 7:
                    extra_slash_arc = True
                skip_slash_recolor = True
            elif i in (8, 9):
                D_hd, ww, wh, wpx, wpy = hd_map[8]
                D = D_hd.copy()
                # hd_map[8] 已自带 AI 精绘冷紫亮白刀弧且无裙侧杂条，仅点缀冷紫星芒，不挖破亮白刀芯！
                D = draw_cold_violet_star(D, D.shape[1] * 0.24, D.shape[0] * 0.18, radius=24.0)
                if i == 9:
                    D, ww, wh, wpx, wpy = apply_foot_locked_micro_warp(D, ww, wh, wpx, wpy, (1.0, 1.0, 2.2, 1.5, 0.0), 1)
                skip_slash_recolor = True
            else:
                keys = [3, 11, 14, 16, 19]
                near_k = min(keys, key=lambda k: abs(k - i))
                D, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[near_k]]
                skip_slash_recolor = True
            is_already_hd = True

        # 8. 全帧或高覆盖率原貌高清剪辑 (turn_right_left, jump, fall, land, air_attack_2, guard_hit_1, guard_start, parry)
        elif clip_key in full_ai_hd_clips and len(hd_map) > 0:
            if i in hd_map:
                D, ww, wh, wpx, wpy = [x.copy() if isinstance(x, np.ndarray) else x for x in hd_map[i]]
            else:
                prev_k = max([k for k in hd_map.keys() if k < i], default=min(hd_map.keys()))
                next_k = min([k for k in hd_map.keys() if k > i], default=max(hd_map.keys()))
                t_b = (i - prev_k) / max(1, next_k - prev_k)
                D, ww, wh, wpx, wpy = blend_adjacent_hd_pose(hd_map[prev_k], hd_map[next_k], t_b)
            is_already_hd = True
            skip_slash_recolor = clip_key not in ("guard_start", "parry") or (i not in (8, 9))

        # 9. 常规剪辑
        else:
            D, ww, wh, wpx, wpy = load_original_unpadded_base(sprite_cfg, fd)
            if D is None:
                continue
            if "desktop-actions-hd" in orig_asset or "imports/framebaker" in orig_asset:
                is_already_hd = True

        # ------------------------------------------------------------------
        # Step 1: 净化悬浮杂点与指定地面连段的泥灰块（绝不误伤弹刀/格挡腿部！）
        # ------------------------------------------------------------------
        H0, W0 = D.shape[:2]
        py_px = wpy * (H0 / max(wh, 1e-4))
        strip_mud = (clip_key in GROUND_DUST_CLIPS) and (not is_already_hd)
        D = clean_stray_and_muddy_dust(D, ground_y_px=py_px, strip_muddy_dust=strip_mud)

        # parry_react_2[3, 4] 顶部空域悬浮白竖条净除（头顶在 y>=22%，仅清 y<14%）
        if clip_key == "parry_react_2" and i in (3, 4) and not is_already_hd:
            D[:int(H0 * 0.14), :] = 0

        # ------------------------------------------------------------------
        # Step 2: 分离刀光与暖黄交锋火花（带贴边自动扩边磨圆！）
        # ------------------------------------------------------------------
        slash_layer_hd: Optional[np.ndarray] = None
        spark_centers: List[Tuple[float, float, float]] = []

        if skip_slash_recolor:
            # 即使跳过刀光重绘，格挡受击与弹刀原帧中的旧版暖黄火花仍净化为冷紫四芒星闪（不抠挖已自带 AI 紫白弧的 parry_react_3 f3+！）
            if clip_key in ("guard_hit_1", "guard_hit_2", "guard_hit_3", "parry_react_2"):
                sp_only = detect_warm_sparks_only(D)
                if sp_only.any():
                    n_sp, _, st_sp, cent_sp = cv2.connectedComponentsWithStats(sp_only.astype(np.uint8), connectivity=8)
                    for si in range(1, n_sp):
                        if st_sp[si, cv2.CC_STAT_AREA] >= 120:
                            r_sp = max(20.0, math.sqrt(st_sp[si, cv2.CC_STAT_AREA]) * 0.85)
                            spark_centers.append((float(cent_sp[si][0]), float(cent_sp[si][1]), r_sp))
                    D[sp_only] = 0
        else:
            slash_mask, spark_mask = detect_universal_slash_and_spark(D, py_px, clip_key, i)
            if spark_mask.any():
                n_sp, _, st_sp, cent_sp = cv2.connectedComponentsWithStats(spark_mask.astype(np.uint8), connectivity=8)
                for si in range(1, n_sp):
                    if st_sp[si, cv2.CC_STAT_AREA] >= 120:
                        r_sp = max(20.0, math.sqrt(st_sp[si, cv2.CC_STAT_AREA]) * 0.85)
                        spark_centers.append((float(cent_sp[si][0]), float(cent_sp[si][1]), r_sp))
                D[spark_mask] = 0

            if slash_mask.any():
                # 检测刀光是否逼近画布四周边界 (<=14px)：若是则自动四周扩边 38px 并磨圆切口，根绝一切贴边硬裁切！
                ys_s, xs_s = np.where(slash_mask)
                near_border = (
                    ys_s.min() <= 14 or ys_s.max() >= D.shape[0] - 15
                    or xs_s.min() <= 14 or xs_s.max() >= D.shape[1] - 15
                )
                if near_border:
                    PAD_B = 38
                    D, ww, wh, wpx, wpy = pad_canvas_with_pivot(D, ww, wh, wpx, wpy, PAD_B)
                    slash_work = taper_clipped_mask_borders(slash_mask, PAD_B)
                    raw_slash_pad = np.pad(slash_mask, ((PAD_B, PAD_B), (PAD_B, PAD_B)), mode="constant", constant_values=False)
                    spark_centers = [(cx + PAD_B, cy + PAD_B, sr) for cx, cy, sr in spark_centers]
                else:
                    slash_work = slash_mask
                    raw_slash_pad = slash_mask

                seed = (sum(clip_key.encode("utf-8")) * 131 + i * 17) % 9973
                slash_rgba = render_ai_calligraphy_slash(
                    slash_work, D, vfx_lib, seed=seed,
                    add_star_tip=(clip_key not in ("draw", "sheathe", "death")),
                )
                skin_now = compute_skin_shield(D)
                solid_body = (~raw_slash_pad) & (D[..., 3] > 24)
                body_safe = (cv2.dilate(solid_body.astype(np.uint8), np.ones((5, 5), np.uint8)) > 0) | skin_now
                D[raw_slash_pad & (~body_safe)] = 0
                slash_layer_hd = slash_rgba

        # Step 3: 角色本体 2x 赛璐璐超采样精修
        H_cur, W_cur = D.shape[:2]
        target_tex_scale = max(1.0, (ww * TEXEL_DENSITY) / max(W_cur, 1))
        body_hd = enhance_cel_body_hd(D, target_scale=target_tex_scale, is_already_hd=is_already_hd)
        TH, TW = body_hd.shape[:2]

        if slash_layer_hd is not None:
            sl_scaled = cv2.resize(slash_layer_hd, (TW, TH), interpolation=cv2.INTER_LANCZOS4)
            base_pil = Image.fromarray(body_hd)
            base_pil.alpha_composite(Image.fromarray(sl_scaled))
            body_hd = np.array(base_pil)

        # 修复中继帧 (parry_react_1[8], parry_react_3[7]) 点缀紧凑剑刃交锋紫芒（外移至前方剑身，100% 避开脸部！）
        if extra_slash_arc and vfx_lib.hit_slashes:
            hs = Image.fromarray(vfx_lib.hit_slashes[i % len(vfx_lib.hit_slashes)])
            hs_sz = int(min(TW, TH) * 0.40)
            hs = hs.resize((hs_sz, hs_sz), Image.Resampling.LANCZOS)
            base_pil = Image.fromarray(body_hd)
            ox = max(0, min(TW - hs_sz, int(TW * 0.12) if clip_key == "parry_react_1" else int(TW * 0.18)))
            oy = max(0, min(TH - hs_sz, int(TH * 0.14)))
            base_pil.alpha_composite(hs, (ox, oy))
            body_hd = np.array(base_pil)

        for scx, scy, sr in spark_centers:
            body_hd = draw_cold_violet_star(
                body_hd, scx * target_tex_scale, scy * target_tex_scale, radius=sr * target_tex_scale
            )
        if (clip_key == "sheathe" and i == 25) or (clip_key == "draw" and i == 37):
            body_hd = draw_cold_violet_star(body_hd, TW * 0.56, TH * 0.52, radius=24.0)

        # 为冲刺疾行帧 (f2..f8) 合成身后真实 AI 破风紫芒楔形流线
        if is_dash_clip and 2 <= i <= 8 and vfx_lib.dash_wedges:
            TH, TW = body_hd.shape[:2]
            ppw_x = TW / max(ww, 1e-4)
            ppw_y = TH / max(wh, 1e-4)
            w_arr = vfx_lib.dash_wedges[(i - 2) % len(vfx_lib.dash_wedges)]
            wim = Image.fromarray(w_arr)
            if source_facing == -1:
                wim = wim.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            sc_w = (142.0 * ppw_y) / max(wim.height, 1)
            wim = wim.resize((max(8, int(wim.width * sc_w)), max(8, int(wim.height * sc_w))), Image.Resampling.LANCZOS)
            extra_l = wim.width if source_facing == 1 else 0
            extra_r = wim.width if source_facing == -1 else 0
            padded = Image.new("RGBA", (TW + extra_l + extra_r, TH), (0, 0, 0, 0))
            if source_facing == 1:
                wx = max(0, int(wpx * ppw_x + extra_l - wim.width + 24.0 * ppw_x))
            else:
                wx = min(padded.width - wim.width, max(0, int(wpx * ppw_x - 24.0 * ppw_x)))
            wy = max(0, min(TH - wim.height, int(wpy * ppw_y - wim.height - 32.0 * ppw_y)))
            padded.alpha_composite(wim, (wx, wy))
            padded.alpha_composite(Image.fromarray(body_hd), (extra_l, 0))
            body_hd = np.array(padded)
            ww = body_hd.shape[1] / ppw_x
            wpx += extra_l / ppw_x

        # 重攻击/终结技峰值挥斩帧点缀 2 片真实 AI 夜鸦暗紫黑羽
        heavy_feather_frames = {
            "attack_3": (3, 4, 5),
            "strong_attack": (9, 10, 11),
            "attack_up": (9, 10, 11),
            "air_attack_3": (0, 1, 2),
            "dash_right_video": (11, 12),
            "dash_left_video": (10, 11),
            "charge_slash": (18, 19, 22),
            "parry_react_3": (8, 9),
        }
        if i in heavy_feather_frames.get(clip_key, ()):
            TH, TW = body_hd.shape[:2]
            piv_t = (wpx * (TW / max(ww, 1e-4)), wpy * (TH / max(wh, 1e-4)))
            body_hd = composite_ai_feathers(
                body_hd, piv_t, vfx_lib, count=2, seed=3300 + i * 19,
                spread_dir=(1.0 if source_facing == 1 else -1.0),
            )

        # Step 4: 锁脚底锚点的作画张力微调 + 紧致裁剪落盘
        params = get_sakuga_posture_params(clip_key, i, N)
        final_rgba, n_ww, n_wh, n_px, n_py = apply_foot_locked_micro_warp(
            body_hd, ww, wh, wpx, wpy, params, source_facing=source_facing
        )

        fn = f"frame_{i + 1:05d}.png"
        Image.fromarray(final_rgba).save(out_clip_dir / fn, optimize=False)

        fd.pop("blank", None)
        fd.pop("region", None)
        fd["asset"] = f"{OUT_REL_ROOT}/{clip_key}/{fn}"
        fd["width"] = round(n_ww, 3)
        fd["height"] = round(n_wh, 3)
        fd["pivotX"] = round(n_px, 3)
        fd["pivotY"] = round(n_py, 3)

    # Step 5: 全招式阶段边界严格守恒的浮点 durationTicks 节奏重排
    re_pace_duration_ticks(clip_key, frames, moves_list, sprite_cfg)
    return new_clip


# ==============================================================================
# 8. 新旧 1:1 实机比例同锚点对比核验大图生成器（含难例全覆盖 Part 3！）
# ==============================================================================
def render_World_frame_cell(
    rgba: np.ndarray,
    ww: float,
    wh: float,
    wpx: float,
    wpy: float,
    source_facing: int,
    cell_w: int = 320,
    cell_h: int = 280,
    zoom: float = 0.52,
) -> Image.Image:
    cell = Image.new("RGBA", (cell_w, cell_h), (20, 22, 31, 255))
    draw = ImageDraw.Draw(cell)
    ground_y = int(cell_h * 0.84)
    anchor_x = int(cell_w * 0.44)
    draw.line([(12, ground_y), (cell_w - 12, ground_y)], fill=(68, 74, 98, 255), width=1)
    draw.line([(anchor_x, ground_y - 10), (anchor_x, ground_y + 10)], fill=(115, 92, 185, 255), width=1)

    if rgba is None:
        draw.text((cell_w // 2 - 30, cell_h // 2), "[BLANK]", fill=(255, 90, 90, 255))
        return cell

    im = Image.fromarray(rgba)
    if source_facing == -1:
        im = im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        wpx = ww - wpx

    disp_w = max(2, int(round(ww * zoom)))
    disp_h = max(2, int(round(wh * zoom)))
    im_s = im.resize((disp_w, disp_h), Image.Resampling.LANCZOS)
    ox = int(round(anchor_x - wpx * zoom))
    oy = int(round(ground_y - wpy * zoom))
    cell.alpha_composite(im_s, (ox, oy))
    # 绘出贴图边界粉框以供零裁切核验
    draw.rectangle([ox, oy, ox + disp_w - 1, oy + disp_h - 1], outline=(210, 75, 145, 120), width=1)
    return cell


def load_live_before_rgba(sprite_cfg: dict, fd: dict) -> Optional[np.ndarray]:
    if fd.get("blank", False):
        return None
    asset = fd.get("asset", "")
    ov = sprite_cfg.get("assetOverride", {})
    if asset in ov:
        ov_p = ASSETS / ov[asset]
        if ov_p.exists():
            raw = base64.b64decode(ov_p.read_text(encoding="utf-8").strip())
            return np.array(Image.open(io.BytesIO(raw)).convert("RGBA"))
    full_p = ASSETS / asset
    if not full_p.exists():
        return None
    arr = np.array(Image.open(full_p).convert("RGBA"))
    for x, y, w, h in sprite_cfg.get("assetCleanup", {}).get(asset, []):
        arr[max(0, y):y + h, max(0, x):x + w] = 0
    return arr


def make_comparison_board(
    old_anims: dict,
    new_anims: dict,
    sprite_cfg: dict,
    sample_specs: List[Tuple[str, List[int]]],
    out_path: Path,
    title: str,
) -> None:
    cols = max(len(idxs) for _, idxs in sample_specs)
    cw, ch = 380, 240
    header_h = 44
    board_w = cols * cw + 180
    board_h = header_h + len(sample_specs) * 2 * ch
    board = Image.new("RGBA", (board_w, board_h), (15, 16, 24, 255))
    draw = ImageDraw.Draw(board)
    draw.text((16, 12), title, fill=(242, 236, 255, 255))

    for row_pair, (ck, idxs) in enumerate(sample_specs):
        z = 0.32 if ck in ("attack_1", "strong_attack", "dash_right_video", "charge_slash") else 0.46
        y_old = header_h + (row_pair * 2) * ch
        y_new = y_old + ch
        draw.rectangle([4, y_old + 4, 174, y_old + ch - 4], fill=(34, 28, 44, 255))
        draw.rectangle([4, y_new + 4, 174, y_new + ch - 4], fill=(28, 44, 38, 255))
        draw.text((12, y_old + ch // 2 - 14), f"{ck}\n[BEFORE 原版]", fill=(255, 175, 175, 255))
        draw.text((12, y_new + ch // 2 - 14), f"{ck}\n[AFTER 精修]", fill=(165, 255, 205, 255))

        sf_old = int(old_anims[ck].get("sourceFacing", 1))
        sf_new = int(new_anims[ck].get("sourceFacing", 1))
        for col_i, fi in enumerate(idxs):
            x0 = 180 + col_i * cw
            if fi < len(old_anims[ck]["frames"]):
                ofd = old_anims[ck]["frames"][fi]
                orgba = load_live_before_rgba(sprite_cfg, ofd)
                ow = float(ofd.get("width", 400))
                oh = float(ofd.get("height", 400))
                opx = float(ofd.get("pivotX", ow * 0.5))
                opy = float(ofd.get("pivotY", oh))
                ocell = render_World_frame_cell(orgba, ow, oh, opx, opy, sf_old, cw - 4, ch - 4, zoom=z)
                board.alpha_composite(ocell, (x0 + 2, y_old + 2))
                draw.text((x0 + 10, y_old + 8), f"f{fi}", fill=(220, 190, 190, 255))
            if fi < len(new_anims[ck]["frames"]):
                nfd = new_anims[ck]["frames"][fi]
                nrgba = np.array(Image.open(ASSETS / nfd["asset"]).convert("RGBA"))
                ncell = render_World_frame_cell(
                    nrgba, float(nfd["width"]), float(nfd["height"]),
                    float(nfd["pivotX"]), float(nfd["pivotY"]), sf_new, cw - 4, ch - 4, zoom=z,
                )
                board.alpha_composite(ncell, (x0 + 2, y_new + 2))
                dt = nfd.get("durationTicks", 1.0)
                draw.text((x0 + 10, y_new + 8), f"f{fi} (dt={dt:.2f})", fill=(185, 255, 215, 255))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    board.save(out_path)
    print(f"[OK] Saved comparison board -> {out_path}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pilot", action="store_true")
    ap.add_argument("--write-battle", action="store_true")
    ap.add_argument("--clips", nargs="*", default=None)
    args = ap.parse_args()

    battle = json.loads(BATTLE_JSON.read_text(encoding="utf-8"))
    ai_hd_data = json.loads(AI_HD_JSON.read_text(encoding="utf-8"))
    man_1106_parry1 = json.loads((REDRAW_1106_DIR / "弹刀1_前8帧_带刀光" / "帧" / "manifest.json").read_text(encoding="utf-8"))

    sprite_cfg = battle["characters"][0]["sprite"]
    anims = sprite_cfg["animations"]
    moves_list = battle["moves"]
    vfx_lib = AIVfxLibrary()

    DOC_OUT_DIR.mkdir(parents=True, exist_ok=True)
    backup_path = DOC_OUT_DIR / "backup_animations_before_overhaul.json"
    if not backup_path.exists():
        backup_path.write_text(json.dumps(anims, ensure_ascii=False, indent=2), encoding="utf-8")
    base_anims = json.loads(backup_path.read_text(encoding="utf-8"))

    if args.clips:
        target_clips = [k for k in args.clips if k in base_anims and not k.startswith("source_")]
        new_anims = copy.deepcopy(anims)
    elif args.pilot:
        target_clips = [
            "attack_1", "parry_react_1", "parry_react_2", "parry_react_3",
            "guard_start", "guard_hit_1", "guard_hit_2", "dash_left_video",
            "dash_right_video", "charge_hold", "charge_slash", "death",
        ]
        new_anims = copy.deepcopy(base_anims)
    else:
        target_clips = [k for k in base_anims.keys() if not k.startswith("source_")]
        new_anims = copy.deepcopy(base_anims)

    for idx_c, ck in enumerate(target_clips, 1):
        print(f"[{idx_c:02d}/{len(target_clips):02d}] Overhauling clip: {ck} (N={len(base_anims[ck]['frames'])}) ...", flush=True)
        new_anims[ck] = process_single_clip(
            ck, base_anims[ck], sprite_cfg, moves_list, ai_hd_data, vfx_lib, man_1106_parry1
        )

    pilot_samples = [
        ("attack_1",         [3, 4, 5, 6, 7, 9]),
        ("parry_react_1",    [2, 6, 8, 9, 10, 11]),
        ("parry_react_3",    [1, 5, 6, 8, 11, 13]),
        ("air_attack_2",     [0, 1, 2, 3, 6, 8]),
        ("dash_right_video", [5, 6, 9, 10, 11, 12]),
        ("strong_attack",    [6, 8, 9, 10, 11, 14]),
        ("guard_hold",       [0, 1, 2, 3, 5, 6]),
        ("charge_slash",     [4, 9, 19, 20, 22, 31]),
        ("death",            [0, 19, 20, 25, 61, 75]),
    ]
    valid_samples = [(ck, idxs) for ck, idxs in pilot_samples if ck in (target_clips if args.pilot else new_anims)]
    make_comparison_board(
        base_anims, new_anims, sprite_cfg, valid_samples,
        DOC_OUT_DIR / ("pilot_before_after.png" if args.pilot else "all_overhaul_key_before_after.png"),
        "All-Actions Overhaul V2: BEFORE vs AFTER (Skin Shield + Intact HD Dash/Parry Bodies + Zero-Hole Charge + Edge Unclip)",
    )

    if not args.pilot:
        part2_samples = [
            ("turn_right_left",  [0, 1, 2, 3, 4]),
            ("jump",             [0, 1, 3, 4, 6, 8]),
            ("land",             [0, 1, 2, 4, 5, 7]),
            ("attack_2",         [1, 2, 4, 5, 6, 10]),
            ("attack_3",         [0, 2, 4, 5, 6, 12]),
            ("air_attack_1",     [5, 8, 9, 10, 11, 14]),
            ("air_attack_3",     [0, 1, 3, 4, 8, 14]),
            ("dash_left_video",  [0, 5, 6, 9, 10, 11]),
            ("parry_react_2",    [0, 1, 2, 3, 4, 5]),
            ("guard_start",      [6, 7, 8, 9, 10, 11]),
            ("guard_hit_2",      [0, 1, 2, 3, 7, 11]),
            ("charge_hold",      [0, 1, 2, 3, 12, 23]),
            ("draw",             [23, 24, 30, 31, 37, 38]),
        ]
        make_comparison_board(
            base_anims, new_anims, sprite_cfg, part2_samples,
            DOC_OUT_DIR / "all_overhaul_key_before_after_part2.png",
            "All-Actions Overhaul V2 Part 2: Hard-Case Verification (Dash Left, Parry 2, Guard Start/Hit, Charge Hold, Iaido Draw)",
        )

    if args.write_battle and not args.pilot:
        for ck in target_clips:
            battle["characters"][0]["sprite"]["animations"][ck] = new_anims[ck]
        BATTLE_JSON.write_text(json.dumps(battle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"[DONE] Updated {len(target_clips)} active clips in {BATTLE_JSON}")


if __name__ == "__main__":
    main()
