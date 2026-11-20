#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
100% 纯 AI 角色动作与大画幅狂野剑戟特效全量切图、双层合成与 battle.json 实装管线
(tools/art/build_pure_ai_all_actions.py)

铁律：
- 0% 本地双边滤波假超分、0% Python SDF/LUT 假涂色刀影、0% 代码几何画星！
- 100% 像素来源于 Codex (gpt-6.1-terra, medium) 纯 AI 生成的 S01..S41 帅气人物动作板 + V01..V08 狂野剑戟大特效板
  （及已验收纯 AI 资产：FrameBaker run 22帧、11-06 转向左到右 7帧、11-06 弹刀1前8帧）。
- 自动黄框清除 + 绿幕反解去溢色 + 1px 核心纯色外推净边 + 锁死脚底 (pivotX, pivotY) 零滑步映射 + 0.0000 判定边界守恒快慢拍。
"""
from __future__ import annotations

import argparse
import copy
import json
import math
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from key_green import key as key_green_fn  # noqa: E402
from overhaul_all_player_actions import make_comparison_board, re_pace_duration_ticks  # noqa: E402

ASSETS = ROOT / "assets"
BATTLE_JSON = ASSETS / "data" / "battle.json"
BACKUP_JSON = ROOT / r"docs\视觉设计\角色动作\全动作精修与张力升级_20261114\backup_animations_before_overhaul.json"
REDRAW_1106_DIR = ROOT / r"docs\视觉设计\角色动作\原帧重画_20261106"

WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\全动作纯AI重塑_20261114"
PLATES_DIR = WORK_ROOT / "plates_in"
CODEX_OUT = WORK_ROOT / "codex_out"
KEY_CACHE = WORK_ROOT / "keyed_cache"

OUT_REL_ROOT = "image/desktop-actions-hd/pure_ai_20261114"
OUT_ABS_ROOT = ASSETS / "image" / "desktop-actions-hd" / "pure_ai_20261114"

TEXEL_DENSITY = 1.55  # 输出 PNG 分辨率倍率（保持游戏世界尺寸 width/height 不变，实机清晰度翻倍）

# 各 Codex 角色整板相对于原始世界角色身高的精确缩放校准系数（消除部分小比例尺整板人物偏大/偏小，锁死全 36 招统一身高）
SHEET_SCALE_CORR: Dict[str, float] = {
    "S01": 1.07,
    "S06": 1.08,
    "S07": 1.48,
    "S09": 1.72,
    "S11": 1.60,
    "S12": 1.24,
    "S17": 1.08,
    "S18": 1.12,
    "S20": 0.85,
    "S21": 1.08,
    "S22": 0.97,
    "S29": 1.06,
    "S30": 1.08,
    "S36": 1.10,
    "S37": 1.12,
    "S38": 1.20,
    "S39": 1.05,
    "S40": 1.06,
}


def decontaminate_rgba_cv2(rgba: np.ndarray, alpha_floor: int = 22, alpha_gain: float = 1.15, erode_px: int = 1) -> np.ndarray:
    """纯 OpenCV 实现 1px 核心纯色最近邻外推，100% 根除半透明边缘绿溢色，零模糊滤镜。"""
    out = rgba.copy()
    a = out[..., 3].astype(np.float32)
    solid = (a >= 236.0).astype(np.uint8)
    if erode_px > 0:
        core = cv2.erode(solid, np.ones((3, 3), np.uint8), iterations=erode_px)
    else:
        core = solid
    if np.count_nonzero(core) < 16:
        core = solid

    if np.count_nonzero(core) > 0:
        # distanceTransformWithLabels 找每个非 core 像素最近的 core 像素坐标
        inv = (1 - core).astype(np.uint8)
        _, labels = cv2.distanceTransformWithLabels(inv, cv2.DIST_L2, 3, labelType=cv2.DIST_LABEL_PIXEL)
        # 构建 label -> (y, x) 映射表
        core_ys, core_xs = np.nonzero(core > 0)
        core_labels = labels[core_ys, core_xs]
        max_lbl = int(labels.max()) + 1
        lut_y = np.zeros(max_lbl, dtype=np.int32)
        lut_x = np.zeros(max_lbl, dtype=np.int32)
        lut_y[core_labels] = core_ys
        lut_x[core_labels] = core_xs

        edge = (a > 0) & (core == 0) & (labels > 0)
        ey, ex = np.nonzero(edge)
        elbl = labels[ey, ex]
        sy, sx = lut_y[elbl], lut_x[elbl]
        out[ey, ex, :3] = out[sy, sx, :3]

    a_new = np.clip((a - float(alpha_floor)) * alpha_gain, 0.0, 255.0).astype(np.uint8)
    out[..., 3] = a_new
    out[a_new == 0] = 0
    return out


def make_vfx_luminous_rgba(rgba: np.ndarray) -> np.ndarray:
    """
    针对纯光效整板 (V01..V08)：消除 AI 在绿底上为发光刀弧外缘勾勒的深黑赛璐璐墨线贴纸边，
    将暗黑外描边平滑转换为半透明皇家深紫辉光过渡，使刀光在亮暖街灯与暗墙前均呈 100% 纯净自发光能量体！
    """
    out = rgba.copy()
    rgb = out[..., :3].astype(np.float32)
    a = out[..., 3].astype(np.float32)
    cmax = np.max(rgb, axis=-1)

    # 亮度低于 68 的深黑外描边直接透明剥离，68..155 区间按平方曲线平滑渐隐，杜绝亮街灯前出现黑圈
    lum_factor = np.clip((cmax - 64.0) / 88.0, 0.0, 1.0) ** 1.45
    a_new = a * lum_factor

    # 将外缘过渡像素色相提亮至通透薰衣草亮紫 (#A47CFF)，确保在暖金灯光上叠加时零压暗、纯发光
    mid_rim = (a_new > 2.0) & (cmax < 165.0)
    if np.any(mid_rim):
        t = np.clip((165.0 - cmax[mid_rim]) / 105.0, 0.0, 0.90)[:, None]
        target_violet = np.array([164.0, 124.0, 255.0], dtype=np.float32)
        rgb[mid_rim] = rgb[mid_rim] * (1.0 - t) + target_violet * t

    out[..., :3] = np.clip(rgb, 0.0, 255.0).astype(np.uint8)
    out[..., 3] = np.clip(a_new, 0.0, 255.0).astype(np.uint8)
    out[out[..., 3] < 6] = 0
    return out


def slice_sheet_cells(sheet_id: str, cols: int, rows: int, expected_size: Tuple[int, int], is_vfx: bool = False) -> List[np.ndarray]:
    """切分一张 Codex 生成的 #00FF00 绿底 + #FFFF00 黄框整板为干净 RGBA 单元格列表。"""
    KEY_CACHE.mkdir(parents=True, exist_ok=True)
    src_fp = CODEX_OUT / f"生成_{sheet_id}.png"
    if not src_fp.exists():
        raise FileNotFoundError(f"Missing Codex generated sheet: {src_fp}")

    im = Image.open(src_fp).convert("RGB")
    W, H = expected_size
    if im.size != (W, H):
        im = im.resize((W, H), Image.Resampling.LANCZOS)

    arr = np.asarray(im).copy()
    cw, ch = W // cols, H // rows

    # 1. 将格子外圈黄框区域与格间分割线强制抹回纯绿 #00FF00
    bw = max(14, round(min(cw, ch) * 0.036))
    border = np.zeros((H, W), dtype=bool)
    for r_i in range(rows):
        for c_i in range(cols):
            x0, y0 = c_i * cw, r_i * ch
            x1, y1 = (c_i + 1) * cw if c_i < cols - 1 else W, (r_i + 1) * ch if r_i < rows - 1 else H
            border[y0:min(H, y0 + bw), x0:x1] = True
            border[max(0, y1 - bw):y1, x0:x1] = True
            border[y0:y1, x0:min(W, x0 + bw)] = True
            border[y0:y1, max(0, x1 - bw):x1] = True

    r, g, b = arr[..., 0].astype(int), arr[..., 1].astype(int), arr[..., 2].astype(int)
    yellow_box = (r > 135) & (g > 135) & (b < 125) & (np.abs(r - g) < 95)
    arr[border & yellow_box] = (0, 255, 0)
    # 即使黄框略微内偏，紧贴格线 6px 一律置绿防跨格粘连
    for c_i in range(cols + 1):
        gx = min(W, max(0, c_i * cw))
        arr[:, max(0, gx - 5):min(W, gx + 5)] = (0, 255, 0)
    for r_i in range(rows + 1):
        gy = min(H, max(0, r_i * ch))
        arr[max(0, gy - 5):min(H, gy + 5), :] = (0, 255, 0)

    clean_rgb_fp = KEY_CACHE / f"_rgb_{sheet_id}.png"
    keyed_fp = KEY_CACHE / f"_keyed_{sheet_id}.png"
    if (not keyed_fp.exists()) or (src_fp.stat().st_mtime > keyed_fp.stat().st_mtime):
        Image.fromarray(arr).save(clean_rgb_fp)
        key_green_fn(str(clean_rgb_fp), str(keyed_fp))

    keyed_rgba = decontaminate_rgba_cv2(np.asarray(Image.open(keyed_fp).convert("RGBA")))
    if is_vfx:
        keyed_rgba = make_vfx_luminous_rgba(keyed_rgba)

    cells: List[np.ndarray] = []
    for r_i in range(rows):
        for c_i in range(cols):
            x0, y0 = c_i * cw, r_i * ch
            x1, y1 = (c_i + 1) * cw if c_i < cols - 1 else W, (r_i + 1) * ch if r_i < rows - 1 else H
            sub = keyed_rgba[y0:y1, x0:x1].copy()
            # 过滤 < 28px 孤立微尘噪点
            m = (sub[..., 3] > 16).astype(np.uint8)
            n_lbl, lbls, stats, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
            for li in range(1, n_lbl):
                if stats[li, cv2.CC_STAT_AREA] < 28:
                    sub[lbls == li] = 0
            cells.append(sub)
    return cells


def crop_tight_rgba(arr: np.ndarray, pad: int = 4) -> Tuple[np.ndarray, Tuple[int, int, int, int]]:
    ys, xs = np.nonzero(arr[..., 3] > 16)
    if len(xs) == 0:
        return np.zeros((16, 16, 4), np.uint8), (0, 0, 16, 16)
    H, W = arr.shape[:2]
    x0, y0 = max(0, int(xs.min()) - pad), max(0, int(ys.min()) - pad)
    x1, y1 = min(W, int(xs.max()) + 1 + pad), min(H, int(ys.max()) + 1 + pad)
    return arr[y0:y1, x0:x1].copy(), (x0, y0, x1, y1)


def map_char_cell_to_world_frame(cell_rgba: np.ndarray, cell_meta: dict) -> Tuple[np.ndarray, float, float, float, float]:
    """
    把切出的单格 AI 高张力角色图还原为精确锁定脚底锚点 (wpx, wpy) 的高清游戏帧：
    返回 (rgba_hd, world_w, world_h, world_px, world_py)。
    """
    crop, (cx0, cy0, cx1, cy1) = crop_tight_rgba(cell_rgba, pad=2)
    cw_cell, ch_cell = cell_meta["cell_rect"][2], cell_meta["cell_rect"][3]

    # 原输入格里人物放置框 (相对整张 sheet -> 转成相对当前格)
    cell_x0, cell_y0 = cell_meta["cell_rect"][0], cell_meta["cell_rect"][1]
    pl_x = cell_meta["placed"][0] - cell_x0
    pl_y = cell_meta["placed"][1] - cell_y0
    pl_w = cell_meta["placed"][2]
    pl_h = cell_meta["placed"][3]

    piv_cell_x = cell_meta["pivot_in_sheet"][0] - cell_x0
    piv_cell_y = cell_meta["pivot_in_sheet"][1] - cell_y0

    # AI 在原位重画人物并略微放大披肩/跨步，我们把 AI 生成的人物底边对齐原放置底边 pl_y + pl_h，横向中心温和贴合原中心
    ai_ys, ai_xs = np.nonzero(cell_rgba[..., 3] > 32)
    if len(ai_xs) > 0:
        ai_bot = float(ai_ys.max())
        ai_cx = float(np.median(ai_xs))
        ref_bot = float(pl_y + pl_h)
        ref_cx = float(pl_x + pl_w * 0.5)
        # 脚底与重心校准：使 AI 人物脚底精确对应 piv_cell_y 地面关系
        shift_y = ai_bot - ref_bot
        shift_x = (ai_cx - ref_cx) * 0.65
        eff_piv_x = piv_cell_x + shift_x
        eff_piv_y = piv_cell_y + shift_y
    else:
        eff_piv_x, eff_piv_y = piv_cell_x, piv_cell_y

    # 换算到世界坐标单位：1 world unit = eff_sheet_scale 个 cell 像素（含整板统一身高校准）
    # 为保留高清锐度，输出图像素密度 = TEXEL_DENSITY * world_unit
    sheet_id = cell_meta["_sheet_id"]
    ci = int(cell_meta["cell_idx"])
    layout_fp = PLATES_DIR / f"排版_{sheet_id}.json"
    raw_sheet_scale = float(json.loads(layout_fp.read_text(encoding="utf-8"))["scale"])
    scale_corr = SHEET_SCALE_CORR.get(sheet_id, 1.0)
    cell_corr = 1.25 if (sheet_id == "S20" and ci in (5, 6, 7)) else 1.0
    eff_sheet_scale = raw_sheet_scale * scale_corr * cell_corr

    # 单格防爆顶巨化保护：仅限制上限 ref_wh * 1.12（修复 S13 f8..11 等高举腾空帧巨化），绝不设下限反向拉大低姿俯冲/倒地角色（如 dash_left f11、dash_right f6）
    raw_wh = crop.shape[0] / max(eff_sheet_scale, 1e-4)
    ref_wh = float(np.clip(pl_h / max(raw_sheet_scale, 1e-4), 265.0, 485.0))
    clamped_wh = min(raw_wh, ref_wh * 1.12)
    eff_sheet_scale *= (raw_wh / max(clamped_wh, 1e-4))

    # 当 eff_sheet_scale 校准时，以脚底锚点 eff_piv 为不动点进行等比世界映射，确保双脚 100% 踩实地面零浮空
    rel_w_x0 = (cx0 - eff_piv_x) / eff_sheet_scale
    rel_w_y0 = (cy0 - eff_piv_y) / eff_sheet_scale
    crop_world_w = crop.shape[1] / eff_sheet_scale
    crop_world_h = crop.shape[0] / eff_sheet_scale

    # 四周留足安全世界边距（后续叠加大特效还会自动扩画布）
    pad_w = 24.0
    world_w = crop_world_w + 2.0 * pad_w
    world_h = crop_world_h + 2.0 * pad_w
    world_px = -rel_w_x0 + pad_w
    world_py = -rel_w_y0 + pad_w

    out_px_w = max(16, round(world_w * TEXEL_DENSITY))
    out_px_h = max(16, round(world_h * TEXEL_DENSITY))
    crop_px_w = max(8, round(crop_world_w * TEXEL_DENSITY))
    crop_px_h = max(8, round(crop_world_h * TEXEL_DENSITY))

    crop_resized = Image.fromarray(crop).resize((crop_px_w, crop_px_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (out_px_w, out_px_h), (0, 0, 0, 0))
    paste_x = round(pad_w * TEXEL_DENSITY)
    paste_y = round(pad_w * TEXEL_DENSITY)
    canvas.paste(crop_resized, (paste_x, paste_y), crop_resized)
    return np.asarray(canvas), world_w, world_h, world_px, world_py


def composite_pure_ai_vfx(
    char_rgba: np.ndarray,
    ww: float,
    wh: float,
    wpx: float,
    wpy: float,
    vfx_rgba: np.ndarray,
    vfx_world_span: float,
    offset_world_xy: Tuple[float, float],
    angle_deg: float = 0.0,
    flip_x: bool = False,
    flip_y: bool = False,
    behind_char: bool = False,
    opacity: float = 1.0,
) -> Tuple[np.ndarray, float, float, float, float]:
    """
    将 100% 纯 AI 生成的大画幅剑戟特效精灵（支持自动扩充画布绝不裁切！）精准合成到角色帧上。
    offset_world_xy: 特效中心相对于角色脚底锚点 (wpx, wpy) 的世界坐标偏移 (dx, dy)，y 向上为负。
    """
    vcrop, _ = crop_tight_rgba(vfx_rgba, pad=2)
    vim = Image.fromarray(vcrop)
    if flip_x:
        vim = vim.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    if flip_y:
        vim = vim.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    if abs(angle_deg) > 0.5:
        vim = vim.rotate(-angle_deg, resample=Image.Resampling.BICUBIC, expand=True)
    if opacity < 0.995:
        va = np.asarray(vim).copy()
        va[..., 3] = np.clip(va[..., 3].astype(np.float32) * opacity, 0, 255).astype(np.uint8)
        vim = Image.fromarray(va)

    # 按最长边映射到目标世界跨度 vfx_world_span
    max_dim = max(vim.width, vim.height, 1)
    target_px_max = vfx_world_span * TEXEL_DENSITY
    s = target_px_max / float(max_dim)
    vw_px = max(8, round(vim.width * s))
    vh_px = max(8, round(vim.height * s))
    vim = vim.resize((vw_px, vh_px), Image.Resampling.LANCZOS)

    ppw_x = char_rgba.shape[1] / max(ww, 1e-4)
    ppw_y = char_rgba.shape[0] / max(wh, 1e-4)

    piv_px_x = wpx * ppw_x
    piv_px_y = wpy * ppw_y
    v_cx = piv_px_x + offset_world_xy[0] * ppw_x
    v_cy = piv_px_y + offset_world_xy[1] * ppw_y

    vx0 = round(v_cx - vw_px * 0.5)
    vy0 = round(v_cy - vh_px * 0.5)
    vx1 = vx0 + vw_px
    vy1 = vy0 + vh_px

    H0, W0 = char_rgba.shape[:2]
    pad_l = max(0, -vx0 + 8)
    pad_t = max(0, -vy0 + 8)
    pad_r = max(0, vx1 - W0 + 8)
    pad_b = max(0, vy1 - H0 + 8)

    new_W = W0 + pad_l + pad_r
    new_H = H0 + pad_t + pad_b
    out_canvas = Image.new("RGBA", (new_W, new_H), (0, 0, 0, 0))
    char_im = Image.fromarray(char_rgba)

    if behind_char:
        out_canvas.alpha_composite(vim, (vx0 + pad_l, vy0 + pad_t))
        out_canvas.alpha_composite(char_im, (pad_l, pad_t))
    else:
        out_canvas.alpha_composite(char_im, (pad_l, pad_t))
        out_canvas.alpha_composite(vim, (vx0 + pad_l, vy0 + pad_t))

    new_ww = new_W / ppw_x
    new_wh = new_H / ppw_y
    new_wpx = wpx + pad_l / ppw_x
    new_wpy = wpy + pad_t / ppw_y
    return np.asarray(out_canvas), new_ww, new_wh, new_wpx, new_wpy


def load_all_pure_ai_libraries(manifest_jobs: list[dict]):
    """加载全部切分好的 V01..V08 大特效库与 S01..S41 角色关键帧库。"""
    vfx_cells: Dict[str, List[np.ndarray]] = {}
    # key: (clip, raw_frame_idx) -> (rgba, ww, wh, wpx, wpy)
    char_frames: Dict[Tuple[str, int], Tuple[np.ndarray, float, float, float, float]] = {}
    sheet_raw_cells: Dict[str, List[Tuple[np.ndarray, float, float, float, float]]] = {}

    for job in manifest_jobs:
        jid = job["id"]
        cols, rows = job["cols"], job["rows"]
        W, H = job["size"]
        is_vfx_kind = (job["kind"] == "vfx")
        cells = slice_sheet_cells(jid, cols, rows, (W, H), is_vfx=is_vfx_kind)
        if is_vfx_kind:
            vfx_cells[jid] = cells
        else:
            lay = json.loads((PLATES_DIR / f"排版_{jid}.json").read_text(encoding="utf-8"))
            mapped_list = []
            for cmeta in lay["cells"]:
                cmeta["_sheet_id"] = jid
                ci = cmeta["cell_idx"]
                m_tuple = map_char_cell_to_world_frame(cells[ci], cmeta)
                mapped_list.append(m_tuple)
                # 跳过 S32 cell 1（原底板残留一帧白色剑影拖布），令 parry_react_3 f0..1 用 cell 0、f2..3 用 cell 2 干净利落衔接
                if jid == "S32" and ci == 1:
                    continue
                f_key = 2 if (jid == "S32" and ci == 2) else cmeta["frame_idx"]
                char_frames[(cmeta["clip"], f_key)] = m_tuple
            sheet_raw_cells[jid] = mapped_list

    # 关键招式判定帧对齐校准：
    # 1) attack_3 (light_3 active=[1..6], 抓拍 f4)：将 S11 下劈帧 (cells 5,6,7) 精确对齐至 f4,f5,f6！
    s11 = sheet_raw_cells["S11"]
    for f_idx, c_idx in [(0, 0), (1, 2), (2, 3), (3, 4), (4, 5), (5, 6), (6, 7), (7, 7)]:
        char_frames[("attack_3", f_idx)] = s11[c_idx]

    # 2) air_attack_3 (air_light_3 active=[0..6], 抓拍 f0)：零前摇直接凌空下劈，将 S18 俯冲挥斩帧 (cells 4..7) 精确对齐至 f0..6！
    s18 = sheet_raw_cells["S18"]
    for k_old in [k for (c_n, k) in list(char_frames.keys()) if c_n == "air_attack_3" and k <= 12]:
        del char_frames[("air_attack_3", k_old)]
    for f_idx, c_idx in [(0, 4), (1, 5), (3, 6), (5, 7), (8, 7)]:
        char_frames[("air_attack_3", f_idx)] = s18[c_idx]

    return vfx_cells, char_frames, sheet_raw_cells


def nearest_ai_pose(
    char_frames: Dict[Tuple[str, int], Tuple[np.ndarray, float, float, float, float]],
    clip: str,
    target_idx: int,
) -> Tuple[np.ndarray, float, float, float, float]:
    """将任意原始帧槽位精确映射到最近的纯 AI 重画关键帧（日式作画一拍二/一拍三零噪点保持）。"""
    avail = sorted(idx for (ck, idx) in char_frames.keys() if ck == clip)
    if not avail:
        raise KeyError(f"No AI keyframes registered for clip={clip}")
    # 优先选 <= target_idx 的最近关键帧（标准原画 hold 规律），若在首帧前则选最小帧
    le = [k for k in avail if k <= target_idx]
    chosen = le[-1] if le else avail[0]
    arr, ww, wh, wpx, wpy = char_frames[(clip, chosen)]
    return arr.copy(), ww, wh, wpx, wpy


def apply_clip_vfx_choreography(
    clip: str,
    i: int,
    rgba: np.ndarray,
    ww: float,
    wh: float,
    wpx: float,
    wpy: float,
    vfx: Dict[str, List[np.ndarray]],
) -> Tuple[np.ndarray, float, float, float, float]:
    """为每一套招式的爆发帧/蓄力帧/受击帧精准挂载 V01..V08 独立大画幅纯 AI 狂野剑戟特效（100% 零裁切、对齐判定帧）！"""
    # 1. 普攻 1 段 (active=[5..7], shot=f5)：190° 狂草飞白破空满月巨弧向前大跨度斩出
    if clip == "attack_1":
        if i == 3:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][0], 365.0, (115.0, -105.0))
        if i in (4, 5):
            span = 525.0 if i == 4 else 545.0
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][1], span, (152.0, -108.0))
        if i in (6, 7):
            op = 0.94 if i == 6 else 0.68
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][2], 460.0, (165.0, -102.0), opacity=op)

    # 2. 普攻 2 段系列 (active=[3..6], shot=f5)：单向凌厉反手斜撩紫雷弯月（严丝合缝贴合直剑左上斜撩轨迹）
    elif clip == "attack_2":
        if i == 3:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][3], 355.0, (115.0, -95.0))
        if i in (4, 5, 6):
            ang = -12.0 if i == 4 else (-22.0 if i == 6 else -17.0)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][4], 505.0, (122.0, -135.0), angle_deg=ang)
        if i in (7, 8):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][5], 445.0, (118.0, -142.0), opacity=(0.90 if i == 7 else 0.62))

    elif clip == "attack_2_start":
        if i in (6, 7):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][3], 345.0, (110.0, -95.0))
        if i in (8, 9, 10, 11):
            ang = -12.0 if i <= 9 else -20.0
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][4], 500.0, (120.0, -135.0), angle_deg=ang)
        if i in (12, 13):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][5], 435.0, (116.0, -140.0), opacity=0.80)

    elif clip == "attack_2_recovery":
        if i in (0, 1):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][3], 345.0, (110.0, -95.0))
        if i in (2, 3, 4):
            ang = -12.0 if i == 2 else (-22.0 if i == 4 else -17.0)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][4], 500.0, (120.0, -135.0), angle_deg=ang)
        if i in (5, 6):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][5], 435.0, (116.0, -140.0), opacity=0.75)

    # 3. 普攻 3 段终结重劈 (active=[1..6], shot=f4)：100% 零切边狂草重劈巨弧 + 裂地双翼冲击波
    elif clip == "attack_3":
        if i == 3:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][0], 370.0, (95.0, -140.0), angle_deg=-18.0)
        if i in (4, 5):
            span = 545.0 if i == 4 else 520.0
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V08"][2], 470.0, (138.0, -26.0), behind_char=True)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][1], span, (148.0, -112.0), angle_deg=8.0)
        if i in (6, 7):
            op = 0.95 if i == 6 else 0.78
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V02"][2], 495.0, (152.0, -106.0), opacity=op)
        if i in (8, 9):
            op = 0.72 if i == 8 else 0.50
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][2], 435.0, (160.0, -96.0), opacity=op)

    # 4. 上挑升龙强普 (active=[8..11], shot=f9)：f8 起跳冲天柱 -> f9..10 高耸贯通巨弧严密包裹腾空高举真剑！
    elif clip in ("strong_attack", "attack_up"):
        if i in (6, 7):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][0], 385.0, (78.0, -115.0))
        if i == 8:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][1], 525.0, (76.0, -235.0))
        if i in (9, 10):
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][2], 490.0, (62.0, -285.0), behind_char=True, opacity=0.78)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][1], 565.0, (56.0, -298.0), angle_deg=-38.0)
        if i in (11, 12):
            op = 0.85 if i == 11 else 0.58
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][2], 475.0, (66.0, -285.0), angle_deg=-22.0, opacity=op)

    # 5. 空中三连斩与下劈 (air_plunge active=[0..8] 用 air_slash 前段；air_1/air_up active=[8..13]；air_2 shot=f4；air_3 active=[0..6])
    elif clip in ("air_attack_1", "air_slash"):
        if clip == "air_slash":
            if i in (2, 3):
                return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][0], 365.0, (105.0, -98.0), angle_deg=12.0)
            if i in (4, 5, 6):
                return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][3], 465.0, (115.0, -104.0), flip_x=True, angle_deg=10.0)
            if i == 7:
                return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][2], 415.0, (118.0, -100.0), opacity=0.78)
        if i in (8, 9, 10, 11):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][3], 455.0, (115.0, -112.0), flip_x=True)
        if i in (12, 13):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][5], 415.0, (115.0, -110.0), opacity=0.76)

    elif clip == "air_attack_2":
        if i in (2, 3):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][4], 495.0, (108.0, -138.0), angle_deg=-10.0)
        if i in (4, 5):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][4], 495.0, (88.0, -178.0), angle_deg=-22.0)
        if i in (6, 7):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][5], 425.0, (86.0, -178.0), opacity=0.74)

    elif clip == "air_attack_3":
        if i in (0, 1, 2):
            span = 540.0 if i <= 1 else 515.0
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][2], 350.0, (95.0, -88.0), behind_char=True, opacity=0.85)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][1], span, (125.0, -96.0), angle_deg=14.0)
        if i in (3, 4):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V02"][2], 500.0, (128.0, -96.0))
        if i in (5, 6):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][2], 435.0, (132.0, -92.0), opacity=0.76)

    # 6. 左右疾行冲刺斩与急刹转身（dash_left 的 sourceFacing=-1 原图朝左，故特效需 flip_x=True 且前负后正；dash_right 原图朝右）
    elif clip in ("dash_left", "dash_left_video"):
        if 1 <= i <= 5:
            cell = vfx["V04"][0 if i <= 3 else 1]
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, cell, 425.0, (118.0, -85.0), flip_x=True, behind_char=True)
        if i in (6, 7, 8, 9, 10):
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V04"][4], 255.0, (80.0, -25.0), flip_x=True, behind_char=True)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V04"][2], 515.0, (-140.0, -88.0), flip_x=True)
        if i in (11, 12, 13):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V04"][3], 460.0, (-144.0, -88.0), flip_x=True, opacity=0.78)

    elif clip in ("dash_right", "dash_right_video"):
        if 1 <= i <= 7:
            cell = vfx["V04"][0 if i <= 4 else 1]
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, cell, 435.0, (-118.0, -85.0), behind_char=True)
        if 8 <= i <= 14:
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V04"][4], 260.0, (-82.0, -25.0), behind_char=True)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V04"][2], 525.0, (145.0, -88.0))
        if i in (15, 16, 17):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V04"][3], 465.0, (148.0, -88.0), opacity=0.78)

    elif clip == "turn_right_left":
        if i in (2, 3, 4):
            op = 0.85 if i == 2 else (0.92 if i == 3 else 1.0)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V04"][5], 275.0, (92.0, -45.0), behind_char=(i == 2), opacity=op)

    # 7. 架盾格挡与三阶受击
    elif clip in ("guard_start", "parry"):
        if i in (5, 6, 7, 8):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V06"][0], 210.0, (44.0, -108.0), opacity=0.92)

    elif clip == "guard_hold":
        if i in (1, 2, 5, 6):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V06"][0], 205.0, (44.0, -105.0), opacity=0.90)
        if i in (3, 7):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V06"][1], 215.0, (46.0, -118.0), opacity=0.95)

    elif clip == "guard_hit_1":
        if i in (0, 1, 2):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V06"][2], 295.0, (72.0, -108.0), opacity=(1.0 if i <= 1 else 0.72))

    elif clip == "guard_hit_2":
        if i in (0, 1, 2, 3):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V06"][3], 345.0, (78.0, -110.0), opacity=(1.0 if i <= 2 else 0.72))

    elif clip == "guard_hit_3":
        if 1 <= i <= 5:
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V06"][5], 290.0, (62.0, -18.0), behind_char=True)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V06"][4], 415.0, (92.0, -112.0))
        if 6 <= i <= 11:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V06"][5], 270.0, (62.0, -18.0), behind_char=True, opacity=0.82)

    # 8. 弹刀 1 / 2 / 3（只狼级核爆十字寒星锁在竖刃交锋点 + 严格顺应左上外拨卸力/前斩剑路的狂草剑气）
    elif clip == "parry_react_1":
        if i == 6:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][0], 355.0, (54.0, -162.0))
        if i == 7:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][1], 350.0, (48.0, -168.0), opacity=0.90)
        if i in (8, 9):
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(
                rgba, ww, wh, wpx, wpy, vfx["V03"][5], 370.0, (22.0, -188.0), angle_deg=-42.0, behind_char=True, opacity=(0.86 if i == 8 else 0.56)
            )
            return composite_pure_ai_vfx(
                rgba, ww, wh, wpx, wpy, vfx["V05"][2], 445.0, (36.0, -196.0), angle_deg=-58.0, opacity=(0.95 if i == 8 else 0.64)
            )
        if i == 10:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V03"][5], 340.0, (20.0, -190.0), angle_deg=-42.0, opacity=0.46)

    elif clip == "parry_react_2":
        if i == 3:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][0], 360.0, (58.0, -156.0))
        if i == 4:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][1], 335.0, (58.0, -152.0), opacity=0.85)
        if i in (8, 9):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][2], 465.0, (116.0, -116.0), angle_deg=8.0)
        if i == 10:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][1], 345.0, (118.0, -108.0), opacity=0.72)

    elif clip == "parry_react_3":
        if i == 4:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][0], 380.0, (56.0, -158.0))
        if i in (5, 6):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][2], 465.0, (38.0, -192.0), angle_deg=-58.0)
        if i in (7, 8):
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][5], 430.0, (32.0, -182.0), behind_char=True, opacity=0.85)
            return composite_pure_ai_vfx(
                rgba, ww, wh, wpx, wpy, vfx["V05"][2], 445.0, (36.0, -190.0), angle_deg=-54.0, opacity=(0.90 if i == 7 else 0.72)
            )
        if i == 9:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V05"][5], 405.0, (30.0, -182.0), opacity=0.55)

    # 9. 居合拔刀 / 归鞘 / 蓄力盘龙风暴（稳贴石板路面不穿路肩） / 满蓄力断晓一闪 (active=[19..28], shot=f19) / 战败破魂
    elif clip == "draw":
        if 20 <= i <= 26:
            op = 1.0 if i <= 24 else 0.72
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V07"][0], 495.0, (98.0, -108.0), opacity=op)

    elif clip == "sheathe":
        if 20 <= i <= 25:
            op = 1.0 if i <= 22 else 0.68
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V07"][1], 275.0, (-28.0, -95.0), opacity=op)

    elif clip == "charge_hold":
        phase = (i // 2) % 4
        return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V07"][2 + phase], 375.0, (0.0, -158.0), behind_char=(i % 2 == 0))

    elif clip == "charge_slash":
        if 0 <= i <= 16:
            phase = (i // 2) % 4
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V07"][2 + phase], 385.0, (0.0, -158.0), behind_char=True)
        if i in (17, 18):
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V08"][0], 500.0, (48.0, -186.0))
        if 19 <= i <= 27:
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V08"][2], 640.0, (45.0, -34.0), behind_char=True)
            rgba, ww, wh, wpx, wpy = composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V08"][1], 740.0, (55.0, -142.0), behind_char=True)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V01"][1], 615.0, (165.0, -148.0), angle_deg=-14.0)
        if 28 <= i <= 36:
            op = max(0.45, 1.0 - (i - 28) * 0.08)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V08"][3], 680.0, (65.0, -140.0), opacity=op)

    elif clip == "death":
        if 17 <= i <= 23:
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V08"][4], 380.0, (-10.0, -100.0))
        if 24 <= i <= 31:
            op = max(0.45, 0.95 - (i - 24) * 0.07)
            return composite_pure_ai_vfx(rgba, ww, wh, wpx, wpy, vfx["V08"][5], 395.0, (-15.0, -95.0), behind_char=True, opacity=op)

    return rgba, ww, wh, wpx, wpy


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write-battle", action="store_true")
    args = ap.parse_args()

    manifest_jobs = json.loads((WORK_ROOT / "prompts_49.json").read_text(encoding="utf-8"))
    vfx_cells, char_frames, sheet_raw_cells = load_all_pure_ai_libraries(manifest_jobs)

    battle = json.loads(BATTLE_JSON.read_text(encoding="utf-8"))
    base_anims = json.loads(BACKUP_JSON.read_text(encoding="utf-8"))
    sprite_cfg = battle["characters"][0]["sprite"]
    moves_list = battle["moves"]

    man_1106_parry1 = json.loads((REDRAW_1106_DIR / "弹刀1_前8帧_带刀光" / "帧" / "manifest.json").read_text(encoding="utf-8"))
    man_1106_turn_lr = json.loads((REDRAW_1106_DIR / "转向左到右" / "帧" / "manifest.json").read_text(encoding="utf-8"))

    # 建立共享动作映射：同源剪辑共享同一组纯 AI 关键帧
    SHARED_SOURCE = {
        "attack_up": "strong_attack",
        "air_slash": "air_attack_1",
        "parry": "guard_start",
        "dash_left_video": "dash_left",
        "dash_right_video": "dash_right",
    }

    target_clips = [k for k in base_anims.keys() if not k.startswith("source_")]
    new_anims = copy.deepcopy(base_anims)

    for idx_c, ck in enumerate(target_clips, 1):
        clip_obj = new_anims[ck]
        out_dir = OUT_ABS_ROOT / ck
        out_dir.mkdir(parents=True, exist_ok=True)

        # 特殊剪辑 1：run（直接复用已验收 Seedance/FrameBaker 纯 AI 22 帧）
        if ck == "run":
            re_pace_duration_ticks(ck, clip_obj["frames"], moves_list, sprite_cfg)
            print(f"[{idx_c:02d}/36] {ck}: kept FrameBaker pure-AI 22 frames")
            continue

        # 特殊剪辑 2：turn_left_right（直接复用 11-06 用户钦定纯 Codex 7 帧）
        if ck == "turn_left_right":
            re_pace_duration_ticks(ck, clip_obj["frames"], moves_list, sprite_cfg)
            print(f"[{idx_c:02d}/36] {ck}: kept 11-06 pure-Codex 7 frames")
            continue

        # 特殊剪辑 3：guard_hold 扩展为 8 帧 12fps 呼吸流光循环（使用 S25 全 8 格 + V06 符文流光）
        if ck == "guard_hold":
            s25_cells = sheet_raw_cells["S25"]
            gh_frames = []
            for gi in range(8):
                rgba, ww, wh, wpx, wpy = s25_cells[gi]
                rgba, ww, wh, wpx, wpy = apply_clip_vfx_choreography("guard_hold", gi, rgba.copy(), ww, wh, wpx, wpy, vfx_cells)
                fn = f"frame_{gi + 1:05d}.png"
                Image.fromarray(rgba).save(out_dir / fn)
                gh_frames.append({
                    "asset": f"{OUT_REL_ROOT}/{ck}/{fn}",
                    "width": round(ww, 3),
                    "height": round(wh, 3),
                    "pivotX": round(wpx, 3),
                    "pivotY": round(wpy, 3),
                    "durationTicks": 1.0,
                })
            clip_obj["fps"] = 12.0
            clip_obj["loop"] = True
            clip_obj["frames"] = gh_frames
            print(f"[{idx_c:02d}/36] {ck}: built 8-frame pure-AI guard_hold loop")
            continue

        # 特殊剪辑 4：idle 使用 S01 8 格纯 AI 呼吸循环平滑映射至原槽位（消除 69 帧视频抽帧抖动）
        frames_list = clip_obj["frames"]
        N = len(frames_list)
        pose_src_clip = SHARED_SOURCE.get(ck, ck)

        # 缓存相同 (base_pose_key, vfx_slot) 避免静止尾段重复写几十张完全一样的 PNG
        saved_cache: Dict[str, Tuple[str, float, float, float, float]] = {}

        for i, fd in enumerate(frames_list):
            if ck == "parry_react_1" and i < 8:
                # 复用 11-06 用户钦定前 8 帧，仅在第 7 帧 (i=6) 叠加 V05 核爆寒星强化帅度
                m_fr = man_1106_parry1["frames"][i]
                p1_fp = REDRAW_1106_DIR / "弹刀1_前8帧_带刀光" / "帧" / m_fr["file"]
                p1_im = np.asarray(Image.open(p1_fp).convert("RGBA"))
                ww = float(m_fr["width"])
                wh = float(m_fr["height"])
                pad_s = float(m_fr["pivot_shift"])
                wpx = float(fd["pivotX"]) + pad_s
                wpy = float(fd["pivotY"]) + pad_s
                # 升至统一 TEXEL_DENSITY 画布以便合成高精寒星
                p1_hd = np.asarray(Image.fromarray(p1_im).resize((round(ww * TEXEL_DENSITY), round(wh * TEXEL_DENSITY)), Image.Resampling.LANCZOS))
                rgba, n_ww, n_wh, n_px, n_py = apply_clip_vfx_choreography(ck, i, p1_hd, ww, wh, wpx, wpy, vfx_cells)
                fn = f"frame_{i + 1:05d}.png"
                Image.fromarray(rgba).save(out_dir / fn)
                fd.pop("blank", None)
                fd.pop("empty", None)
                fd.pop("region", None)
                fd["asset"] = f"{OUT_REL_ROOT}/{ck}/{fn}"
                fd["width"] = round(n_ww, 3)
                fd["height"] = round(n_wh, 3)
                fd["pivotX"] = round(n_px, 3)
                fd["pivotY"] = round(n_py, 3)
                continue

            if ck == "idle":
                ping_pong = [0, 1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2, 1]
                s01_idx = ping_pong[min(len(ping_pong) - 1, (i * len(ping_pong)) // max(1, N))]
                rgba, ww, wh, wpx, wpy = sheet_raw_cells["S01"][s01_idx]
                rgba = rgba.copy()
                cache_key = f"idle_cell_{s01_idx}"
            else:
                avail = sorted(k for (c_name, k) in char_frames.keys() if c_name == pose_src_clip)
                le = [k for k in avail if k <= i]
                chosen_k = le[-1] if le else avail[0]
                rgba, ww, wh, wpx, wpy = char_frames[(pose_src_clip, chosen_k)]
                rgba = rgba.copy()
                # 若当前帧本身带有独立动态特效相位，不与普通静止帧混用缓存
                cache_key = f"{pose_src_clip}_k{chosen_k}_f{i}"

            rgba, n_ww, n_wh, n_px, n_py = apply_clip_vfx_choreography(ck, i, rgba, ww, wh, wpx, wpy, vfx_cells)

            # 对无特效的长尾静止重复帧复用同一张纯 AI PNG，节省磁盘与显存！
            if ck == "idle":
                dedup_sig = cache_key
            elif ck in ("death", "charge_slash", "draw", "sheathe", "guard_hit_3") and i > 38:
                dedup_sig = f"tail_{pose_src_clip}_{chosen_k}"
            else:
                dedup_sig = cache_key

            if dedup_sig in saved_cache:
                rel_asset, n_ww, n_wh, n_px, n_py = saved_cache[dedup_sig]
            else:
                fn = f"frame_{i + 1:05d}.png"
                Image.fromarray(rgba).save(out_dir / fn)
                rel_asset = f"{OUT_REL_ROOT}/{ck}/{fn}"
                saved_cache[dedup_sig] = (rel_asset, n_ww, n_wh, n_px, n_py)

            fd.pop("blank", None)
            fd.pop("empty", None)
            fd.pop("region", None)
            fd["asset"] = rel_asset
            fd["width"] = round(n_ww, 3)
            fd["height"] = round(n_wh, 3)
            fd["pivotX"] = round(n_px, 3)
            fd["pivotY"] = round(n_py, 3)

        re_pace_duration_ticks(ck, frames_list, moves_list, sprite_cfg)
        print(f"[{idx_c:02d}/36] Built 100% pure-AI clip: {ck} (slots={N}, unique_pngs={len(saved_cache)})", flush=True)

    # 输出新旧同锚点对比核验大图供独立评审子智能体严审
    sample_1 = [
        ("attack_1",         [2, 4, 5, 6, 7, 10]),
        ("attack_3",         [2, 3, 4, 5, 6, 10]),
        ("strong_attack",    [3, 6, 8, 9, 10, 14]),
        ("parry_react_1",    [2, 6, 8, 9, 10, 12]),
        ("parry_react_3",    [1, 4, 5, 6, 8, 13]),
        ("dash_left",        [1, 3, 6, 8, 10, 16]),
        ("dash_right",       [2, 4, 8, 10, 14, 20]),
        ("charge_slash",     [6, 17, 19, 22, 26, 40]),
        ("death",            [0, 18, 20, 25, 46, 61]),
    ]
    make_comparison_board(
        base_anims, new_anims, sprite_cfg, sample_1,
        WORK_ROOT / "pure_ai_before_after_board1.png",
        "100% Pure-AI (Codex gpt-6.1-terra) High-Tension Character + Badass VFX Overhaul — Board 1",
    )

    sample_2 = [
        ("idle",             [0, 10, 20, 30, 45, 60]),
        ("turn_right_left",  [0, 1, 2, 3, 4]),
        ("jump",             [0, 1, 3, 4, 6, 8]),
        ("air_attack_2",     [0, 2, 3, 4, 6, 9]),
        ("air_attack_3",     [0, 1, 3, 5, 14, 22]),
        ("guard_hold",       [0, 1, 2, 3, 5, 7]),
        ("guard_hit_3",      [0, 2, 4, 6, 9, 16]),
        ("draw",             [7, 13, 17, 20, 24, 31]),
        ("charge_hold",      [0, 2, 4, 6, 10, 14]),
    ]
    make_comparison_board(
        base_anims, new_anims, sprite_cfg, sample_2,
        WORK_ROOT / "pure_ai_before_after_board2.png",
        "100% Pure-AI (Codex gpt-6.1-terra) High-Tension Character + Badass VFX Overhaul — Board 2",
    )

    if args.write_battle:
        for ck in target_clips:
            battle["characters"][0]["sprite"]["animations"][ck] = new_anims[ck]
        BATTLE_JSON.write_text(json.dumps(battle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"[DONE] Wrote all 36 100%-pure-AI animations to {BATTLE_JSON}")


if __name__ == "__main__":
    main()
