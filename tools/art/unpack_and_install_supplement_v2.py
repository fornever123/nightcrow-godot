#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将即梦 Seedance 2.0 Fast VIP (v2) 生成的 7 条高清动作视频（+ 现成未接线的 attack_2_recovery 与 guard_hold 8帧呼吸升级）
通过「#7FA88F 线性光学去绿溢解混 + 实机 idle 等高刚体对齐 + R3 刀光自发光校准」解包为 10 套高质量 PNG 序列帧，
落盘至 assets/image/desktop-actions-hd/supplement_v2_20261117/ 并注册进 assets/data/battle.json (characters[0].sprite.animations)。
严守 §4 边界：绝不修改 battle.moves 与任何 source_* 剪辑。
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
BATTLE_JSON = ASSETS / "data" / "battle.json"
WORK_DIR = ROOT / r"docs\视觉设计\角色动作\动作补齐_即梦v2_20261117"
VID_DIR = WORK_DIR / "即梦成片_v2"
STAGE_REL = "image/desktop-actions-hd/supplement_v2_20261117"
STAGE_DIR = ASSETS / STAGE_REL


def measure_strict_character_box(rgba: np.ndarray) -> tuple[float, float, float]:
    """
    精准提取纯人物躯干与双靴（剔除刀光、尘土与细长伸出的剑刃），
    返回 (top_y, bot_y, spine_cx)（单位：当前图像素）。
    """
    al = rgba[..., 3]
    rgb = rgba[..., :3].astype(np.float32)
    luma = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    vio = rgb[..., 2] - rgb[..., 1]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    is_slash = (luma > 205) | ((mn > 165) & ((mx - mn) < 40)) | ((vio > 38) & (luma > 95))
    solid = (al > 150) & (~is_slash)

    m_thick = cv2.morphologyEx(solid.astype(np.uint8), cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    if m_thick.sum() < 60:
        m_thick = solid.astype(np.uint8)
    n_c, lbl, st, _ = cv2.connectedComponentsWithStats(m_thick, 8)
    if n_c > 1:
        j = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        _, txs = np.where(lbl == j)
    else:
        _, txs = np.where(solid)

    torso_cx = float(np.median(txs)) if len(txs) > 0 else rgba.shape[1] * 0.5
    h_im, w_im = al.shape
    x_lo = max(0, int(round(torso_cx - 140)))
    x_hi = min(w_im, int(round(torso_cx + 140)))
    corridor = np.zeros_like(solid)
    corridor[:, x_lo:x_hi] = solid[:, x_lo:x_hi]
    n2, l2, s2, _ = cv2.connectedComponentsWithStats(corridor.astype(np.uint8), 8)
    clean_body = np.zeros_like(solid)
    for ci in range(1, n2):
        if s2[ci, cv2.CC_STAT_AREA] >= 25:
            clean_body |= (l2 == ci)
    if clean_body.sum() < 50:
        clean_body = solid

    bys, bxs = np.where(clean_body)
    top_y = float(bys.min())
    # 靴底严格在脊柱正下方 ±68px 内测量，避免低垂斜指地面的剑尖（如 f09/f10）被误判为脚底导致人物悬空
    foot_zone = clean_body[:, max(0, int(round(torso_cx - 68))):min(w_im, int(round(torso_cx + 68)))]
    f_ys, _ = np.where(foot_zone)
    bot_y = float(f_ys.max()) if len(f_ys) >= 10 else float(bys.max())
    bh = max(bot_y - top_y, 1.0)
    spine_band = (bys >= top_y + 0.22 * bh) & (bys <= top_y + 0.62 * bh)
    spine_cx = float(np.median(bxs[spine_band])) if spine_band.sum() >= 20 else torso_cx
    return top_y, bot_y, spine_cx


def measure_ingame_idle_reference(anims: dict) -> tuple[float, float]:
    """测量现役 idle f00 的真实站立像素身高 (406px) 与躯干脊柱偏移 (-14px)，确保新旧动作 100% 等高零跳位。"""
    f0 = anims["idle"]["frames"][0]
    im = np.array(Image.open(ASSETS / f0["asset"]).convert("RGBA"))
    ty, by, scx = measure_strict_character_box(im)
    stand_h = float(by - ty + 1.0)
    spine_offset = float(scx - float(f0["pivotX"]))
    return stand_h, spine_offset


def unmix_sage_green_frame(
    rgb_u8: np.ndarray,
    keep_slash_glow: bool = False,
    trim_giant_hit_ring: bool = False,
    taper_horizontal_beam: bool = False,
) -> tuple[np.ndarray, np.ndarray]:
    """
    针对即梦 #7FA88F (约 RGB 127, 168, 143) 灰绿纯色底做高精度无绿边线性光学解混：
    - 返回 (rgba_u8 [H,W,4], solid_char_mask [H,W] bool)
    - 实心人物内部 100% alpha=255 零透底（孔洞填充严格限定在非发光角色主体上，绝不把剑气横线围出的背景误填实心）；
    - 抑制 H.264 灰绿压缩振铃（绿色占优像素严禁用颜色距离抬高 alpha，根除浅底灰雾边）；
    - 抗锯齿边缘、冷白受击闪光、刹步烟尘与电光紫刀光还原连续 0%..100% 半透明并彻底消除绿溢！
    """
    rgb = rgb_u8.astype(np.float32)
    # 采样四角边缘估计当前帧精确背景色 B
    corners = np.concatenate([
        rgb[:24, :60].reshape(-1, 3),
        rgb[:24, -60:].reshape(-1, 3),
        rgb[-24:, :60].reshape(-1, 3),
        rgb[-24:, -60:].reshape(-1, 3),
    ], axis=0)
    bg = np.median(corners, axis=0)  # ~ [127, 168, 143]

    diff = rgb - bg[None, None, :]
    dist_l2 = np.sqrt(np.sum(diff * diff, axis=-1))
    dist_max = np.max(np.abs(diff), axis=-1)

    luma = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    bg_luma = float(0.299 * bg[0] + 0.587 * bg[1] + 0.114 * bg[2])
    vio = rgb[..., 2] - rgb[..., 1]

    # 背景典型特征：G 显著高于 R 和 B (bg_g - bg_r ≈ +41, bg_g - bg_b ≈ +25)
    # 角色与刀光（黑/白/暖肤/蓝紫）均满足 G <= max(R, 0.45*R + 0.55*B) + 2
    bg_excess_g = max(float(bg[1] - (0.55 * bg[0] + 0.45 * bg[2])), 18.0)
    obs_excess_g = rgb[..., 1] - (0.55 * rgb[..., 0] + 0.45 * rgb[..., 2])

    # 由绿色超量估计背景占比 (1 - alpha_green)
    bg_frac_from_g = np.clip(obs_excess_g / bg_excess_g, 0.0, 1.0)
    alpha_g = 1.0 - bg_frac_from_g

    # 颜色距离仅允许作用于「明显非灰绿底色相」或「极亮高光 (luma > bg_luma + 34)」像素，
    # 严禁作用于 H.264 在刀光外围产生的深浅灰绿振铃块（根除浅底灰边！）
    non_green_or_bright = (obs_excess_g < bg_excess_g * 0.34) | (luma > bg_luma + 34.0)
    alpha_d = np.where(
        non_green_or_bright,
        np.clip((dist_l2 - 14.0) / 36.0, 0.0, 1.0),
        0.0,
    )
    alpha = np.maximum(alpha_g, alpha_d)

    # 压平纯背景与 H.264 灰绿压缩底噪
    pure_bg = (
        (dist_max < 11.5)
        | ((obs_excess_g > bg_excess_g * 0.68) & (luma < bg_luma + 26.0))
        | ((dist_l2 < 18.0) & (obs_excess_g > bg_excess_g * 0.52))
    )
    alpha[pure_bg] = 0.0

    # 区分高亮度白闪/紫刀光 vs 实体人物：孔洞填充【只】在实体人物连通域上执行，
    # 彻底杜绝横向剑气触达左右画框时把下半屏背景误判为人物内部孔洞！
    is_fx_glow = ((luma > 212.0) & (dist_l2 > 55.0)) | (keep_slash_glow & (vio > 26.0) & (luma > 92.0))
    body_seed_raw = (
        ((alpha_g > 0.80) | ((dist_l2 > 44.0) & (obs_excess_g < 4.0)))
        & (~is_fx_glow)
    ).astype(np.uint8) * 255
    k3 = np.ones((3, 3), np.uint8)
    body_closed = cv2.morphologyEx(body_seed_raw, cv2.MORPH_CLOSE, k3)

    # 只保留主体人物连通域（及紧邻主体的剑刃部件），再从四边全部边界像素 flood-fill 外部背景
    n_b, lbl_b, stats_b, _ = cv2.connectedComponentsWithStats((body_closed > 0).astype(np.uint8))
    body_main = np.zeros_like(body_closed)
    cx_m, cy_m = rgb.shape[1] * 0.5, rgb.shape[0] * 0.55
    if n_b > 1:
        main_lbl = 1 + int(np.argmax(stats_b[1:, cv2.CC_STAT_AREA]))
        cy_arr, cx_arr = np.where(lbl_b == main_lbl)
        cy_m, cx_m = float(np.median(cy_arr)), float(np.median(cx_arr))
        for cc_i in range(1, n_b):
            area_i = int(stats_b[cc_i, cv2.CC_STAT_AREA])
            if cc_i == main_lbl or area_i >= 180:
                body_main[lbl_b == cc_i] = 255

    ff = body_main.copy()
    h_im, w_im = ff.shape
    ff_mask = np.zeros((h_im + 2, w_im + 2), np.uint8)
    for bx in range(0, w_im, 8):
        if ff[0, bx] == 0:
            cv2.floodFill(ff, ff_mask, (bx, 0), 255)
        if ff[h_im - 1, bx] == 0:
            cv2.floodFill(ff, ff_mask, (bx, h_im - 1), 255)
    for by in range(0, h_im, 8):
        if ff[by, 0] == 0:
            cv2.floodFill(ff, ff_mask, (0, by), 255)
        if ff[by, w_im - 1] == 0:
            cv2.floodFill(ff, ff_mask, (w_im - 1, by), 255)
    # 严禁将手臂/剑身围出的灰绿背景空隙判入 char_core（obs_excess_g 必须显著低于灰绿底！）
    char_core = ((body_main | cv2.bitwise_not(ff)) > 0) & (~is_fx_glow) & (obs_excess_g < bg_excess_g * 0.36)
    char_interior = cv2.erode(char_core.astype(np.uint8) * 255, k3) > 0
    k9 = np.ones((9, 9), np.uint8)
    char_halo = cv2.dilate(char_core.astype(np.uint8) * 255, k9) > 0

    if trim_giant_hit_ring:
        yy, xx = np.ogrid[: rgb.shape[0], : rgb.shape[1]]
        rad = np.sqrt((xx - cx_m) ** 2 + (yy - cy_m) ** 2)
        ring_fade = np.clip((150.0 - rad) / 45.0, 0.0, 1.0)
        fx_only = (~char_core) & (alpha > 0)
        alpha[fx_only] *= ring_fade[fx_only]

    if keep_slash_glow:
        # 角色轮廓 4px 以外的纯刀光区：剥离原视频赛璐璐黑灰描边与细碎外风线，只保留饱满冷白锋与电光紫尾纱（100% 匹配 R3 char_light 自发光阈值！）
        slash_strength = np.clip(
            np.maximum((luma - (bg_luma + 24.0)) / 44.0, (vio - 26.0) / 32.0),
            0.0,
            1.0,
        )
        outside_body = ~char_halo
        alpha[outside_body] = np.minimum(alpha[outside_body], slash_strength[outside_body])

    if taper_horizontal_beam:
        # K 远程剑气挥出瞬间，真实飞行弹体由游戏内 WaveProjectile 承担，角色自身贴图保留身前饱满新月弧并柔化超长贯穿横线
        _, xx = np.ogrid[: rgb.shape[0], : rgb.shape[1]]
        dx = xx - cx_m
        horiz_taper = np.where(
            dx < 0.0,
            np.clip((dx + 145.0) / 55.0, 0.0, 1.0),
            np.clip((265.0 - dx) / 70.0, 0.0, 1.0),
        )
        fx_only = (~char_core) & (alpha > 0)
        alpha = np.where(fx_only, alpha * horiz_taper, alpha)

    alpha[char_interior] = 1.0
    alpha = np.where(alpha < 0.04, 0.0, alpha)

    # 线性反解前景颜色 F = (C - (1 - a)*B) / a
    safe_a = np.maximum(alpha[..., None], 0.08)
    fg = (rgb - (1.0 - alpha[..., None]) * bg[None, None, :]) / safe_a
    fg = np.clip(fg, 0.0, 255.0)

    # 边缘与半透明像素彻底消绿溢 (Despill)：令 G 不超过 max(R, 0.45*R + 0.55*B)
    edge_or_semi = (alpha > 0.0) & (~char_interior)
    cap_g = np.maximum(fg[..., 0], 0.45 * fg[..., 0] + 0.55 * fg[..., 2])
    fg[..., 1] = np.where(edge_or_semi, np.minimum(fg[..., 1], cap_g), fg[..., 1])

    if keep_slash_glow:
        # 对齐 R3 刀光自发光色域 (char_light.gdshader slash_emissive)，让冷白锋与电光紫尾纱免黑描边且通透发亮
        sl_mask = (alpha > 0.05) & (~char_interior) & ((fg[..., 2] - fg[..., 1] > 14.0) | (luma > 180.0))
        if np.any(sl_mask):
            vio_veil = sl_mask & (luma < 215.0)
            alpha[vio_veil] = np.clip(alpha[vio_veil] * 0.90, 0.0, 0.95)
            fg[..., 0] = np.where(sl_mask, np.clip(fg[..., 0] * 1.12 + 28.0, 145, 255), fg[..., 0])
            fg[..., 1] = np.where(sl_mask & (luma < 220.0), np.clip(fg[..., 1] * 0.92 + 12.0, 75, 235), fg[..., 1])
            fg[..., 2] = np.where(sl_mask, np.clip(fg[..., 2] * 1.18 + 38.0, 222, 255), fg[..., 2])

    fg[alpha <= 0.0] = 0.0
    out_rgba = np.zeros((rgb.shape[0], rgb.shape[1], 4), dtype=np.uint8)
    out_rgba[..., :3] = np.round(fg).astype(np.uint8)
    out_rgba[..., 3] = np.round(alpha * 255.0).astype(np.uint8)

    # 剔除孤立碎点（如受击脚下脱离人物的细小杂斑 < 260px；保留刹步烟尘与连体刀光）
    n_a, lbl_a, stats_a, _ = cv2.connectedComponentsWithStats((out_rgba[..., 3] > 10).astype(np.uint8))
    for cc_i in range(1, n_a):
        area_i = int(stats_a[cc_i, cv2.CC_STAT_AREA])
        touches_body = bool(np.any(char_halo & (lbl_a == cc_i)))
        thresh = 68 if (touches_body or keep_slash_glow) else 260
        if area_i < thresh:
            out_rgba[lbl_a == cc_i] = 0

    return out_rgba, char_core


def read_video_frame_rgb(vp: Path, fi: int) -> np.ndarray:
    cap = cv2.VideoCapture(str(vp))
    cap.set(cv2.CAP_PROP_POS_FRAMES, fi)
    ok, bgr = cap.read()
    cap.release()
    if not ok or bgr is None:
        raise RuntimeError(f"Failed to read frame {fi} from {vp}")
    return cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)


def measure_vid_standing_calibration(vp: Path, stand_fi: int) -> tuple[float, float, float]:
    """从该视频自身的待机站立帧测量严格净人物 (vid_stand_h, vid_foot_y, vid_spine_cx)。"""
    rgb = read_video_frame_rgb(vp, stand_fi)
    rgba, _ = unmix_sage_green_frame(rgb, keep_slash_glow=False)
    ty, by, scx = measure_strict_character_box(rgba)
    return float(by - ty + 1.0), float(by), float(scx)


def export_video_clip(
    clip_key: str,
    vp: Path,
    frame_indices: list[int],
    stand_fi: int,
    ingame_stand_h: float,
    idle_spine_offset: float,
    pivot_mode: str,  # "ground_fixed" | "body_bottom" | "air_flip_cast"
    keep_slash_glow: bool = False,
    trim_giant_hit_ring: bool = False,
    taper_horizontal_beam: bool = False,
    strip_floor_specks_below_foot: bool = False,
    cap_max_height_to_idle: bool = False,
    fps: float = 24.0,
    loop: bool = False,
    hold_last: bool = True,
) -> dict:
    vid_h, vid_foot_y, _ = measure_vid_standing_calibration(vp, stand_fi)
    base_scale = ingame_stand_h / vid_h

    out_dir = STAGE_DIR / clip_key
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    frames_meta = []

    for out_idx, fi in enumerate(frame_indices):
        rgb = read_video_frame_rgb(vp, fi)
        rgba, _ = unmix_sage_green_frame(
            rgb,
            keep_slash_glow=keep_slash_glow,
            trim_giant_hit_ring=trim_giant_hit_ring,
            taper_horizontal_beam=taper_horizontal_beam,
        )
        if strip_floor_specks_below_foot:
            # 清除原视频脚底基准线以下残留的小白点/地面短白线（如 V1 f40 脚底白短竖条）
            y_cut = int(round(vid_foot_y + 4))
            if y_cut < rgba.shape[0]:
                rgba[y_cut:, :, :] = 0
            low_band = rgba[int(round(vid_foot_y - 16)):y_cut, :, :]
            low_luma = 0.299 * low_band[..., 0] + 0.587 * low_band[..., 1] + 0.114 * low_band[..., 2]
            low_band[low_luma > 200] = 0

        ty_v, by_v, scx_v = measure_strict_character_box(rgba)
        cur_vid_h = float(by_v - ty_v + 1.0)
        scale = base_scale
        if cap_max_height_to_idle and cur_vid_h * base_scale > ingame_stand_h:
            # 消除即梦首尾帧过渡中段轻微推镜导致的人物蹿高（如 V6 f41..f57）
            scale = ingame_stand_h / cur_vid_h

        pil = Image.fromarray(rgba)
        bb = pil.getbbox()
        if not bb:
            bb = (600, 300, 680, 612)
        pad = 6
        x0 = max(0, bb[0] - pad)
        y0 = max(0, bb[1] - pad)
        x1 = min(pil.width, bb[2] + pad)
        y1 = min(pil.height, bb[3] + pad)
        cropped = pil.crop((x0, y0, x1, y1))

        nw = max(4, round(cropped.width * scale))
        nh = max(4, round(cropped.height * scale))
        resized = cropped.resize((nw, nh), Image.Resampling.LANCZOS)

        # 在缩放后的最终贴图上直接复测脊柱中心与最低鞋跟，杜绝任何取整误差！
        ty_r, by_r, scx_r = measure_strict_character_box(np.array(resized))

        if pivot_mode == "ground_fixed":
            # 脚底 100% 踩死地面线 (bot=0.0)，脊柱中心严格对齐 idle 的 idle_spine_offset (-14px)！
            px = scx_r - idle_spine_offset
            py = by_r
        elif pivot_mode == "air_flip_cast":
            # K 远程剑气：仅空翻腾空帧 (out_idx 1, 2) 保留真实离地高度，其余帧严格踩死地面且脊柱对齐 idle（零回弹闪移！）
            px = scx_r - idle_spine_offset
            if out_idx in (1, 2):
                py = (vid_foot_y - y0) * scale
            else:
                py = by_r
        else:  # "body_bottom" (用于空中击飞 LAUNCHED 与空中急坠下劈 air_plunge)
            px = scx_r - idle_spine_offset
            py = by_r

        fn = f"frame_{out_idx:05d}.png"
        resized.save(out_dir / fn)
        rel_asset = f"{STAGE_REL}/{clip_key}/{fn}"
        frames_meta.append({
            "asset": rel_asset,
            "width": nw,
            "height": nh,
            "pivotX": round(float(px), 3),
            "pivotY": round(float(py), 3),
            "durationTicks": 1,
        })

    return {
        "name": clip_key,
        "fps": fps,
        "loop": loop,
        "holdLast": hold_last,
        "effectsBaked": True,
        "sourceFacing": 1,
        "frames": frames_meta,
    }


def build_attack2_settle_from_existing(cur_anims: dict, ingame_stand_h: float, idle_spine_offset: float) -> dict:
    """
    将现成 attack_2_recovery (#16..29 收剑回正段) 整理为 attack_2_settle：
    - 修正原帧 display width/height 缩放比（消除此前漏乘 sx/sy 导致的 -66px 悬空与 16% 缩水！）；
    - 每帧脚底严格锁死地面线 (bot=0.0)，脊柱中心严格对齐 idle，尾帧身高精确对齐 406px！
    """
    src_frames = cur_anims["attack_2_recovery"]["frames"][16:30]
    out_dir = STAGE_DIR / "attack_2_settle"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # 先按最后一帧 (#29 站立回正帧) 标定等高系数，确保收完招回到 idle 时身高 0.0px 无缝衔接
    fm_last = src_frames[-1]
    im_last = Image.open(ASSETS / fm_last["asset"]).convert("RGBA")
    w_last = round(float(fm_last.get("width", im_last.width)))
    h_last = round(float(fm_last.get("height", im_last.height)))
    im_last_disp = im_last.resize((w_last, h_last), Image.Resampling.LANCZOS)
    ty_l, by_l, _ = measure_strict_character_box(np.array(im_last_disp))
    norm_k = ingame_stand_h / max(float(by_l - ty_l + 1.0), 1.0)

    frames_meta = []
    for idx, fm in enumerate(src_frames):
        src_fp = ASSETS / fm["asset"]
        im = Image.open(src_fp).convert("RGBA")
        # 还原原帧配置的显示分辨率并乘上 idle 等高校准系数
        disp_w = max(4, round(float(fm.get("width", im.width)) * norm_k))
        disp_h = max(4, round(float(fm.get("height", im.height)) * norm_k))
        im_disp = im.resize((disp_w, disp_h), Image.Resampling.LANCZOS)

        bb = im_disp.getbbox()
        if bb:
            x0, y0 = max(0, bb[0] - 6), max(0, bb[1] - 6)
            x1, y1 = min(im_disp.width, bb[2] + 6), min(im_disp.height, bb[3] + 6)
            im_c = im_disp.crop((x0, y0, x1, y1))
        else:
            im_c = im_disp

        ty_c, by_c, scx_c = measure_strict_character_box(np.array(im_c))
        px = scx_c - idle_spine_offset
        py = by_c

        fn = f"frame_{idx:05d}.png"
        im_c.save(out_dir / fn)
        frames_meta.append({
            "asset": f"{STAGE_REL}/attack_2_settle/{fn}",
            "width": im_c.width,
            "height": im_c.height,
            "pivotX": round(float(px), 3),
            "pivotY": round(float(py), 3),
            "durationTicks": int(fm.get("durationTicks", 1)),
        })
    return {
        "name": "普攻2段收招",
        "fps": 24.0,
        "loop": False,
        "holdLast": True,
        "effectsBaked": True,
        "sourceFacing": 1,
        "frames": frames_meta,
    }


def build_guard_hold_breathing(cur_anims: dict, ingame_stand_h: float, idle_spine_offset: float) -> dict:
    """将只有 1 帧死图的 guard_hold 升级为 8 帧 @ 12fps 锁死双脚锚点且与 idle 100% 等高的架刀呼吸循环。"""
    orig_clip = cur_anims["guard_hold"]
    parry_last_fp = ASSETS / "image/desktop-actions-hd/r3_true_slash_20261115/parry/frame_00011.png"
    raw_im = Image.open(parry_last_fp).convert("RGBA")
    ty0, by0, _ = measure_strict_character_box(np.array(raw_im))
    gk = ingame_stand_h / max(float(by0 - ty0 + 1.0), 1.0)
    base_im = raw_im.resize((max(4, round(raw_im.width * gk)), max(4, round(raw_im.height * gk))), Image.Resampling.LANCZOS)
    _, base_py, base_scx = measure_strict_character_box(np.array(base_im))
    base_px = base_scx - idle_spine_offset

    out_dir = STAGE_DIR / "guard_hold"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    phases = np.linspace(0, 2 * np.pi, 8, endpoint=False)
    frames_meta = []
    W, H = base_im.size
    foot_band_y = round(base_py - 46)

    for idx, ph in enumerate(phases):
        breath = float(np.sin(ph))
        sy = 1.0 + 0.014 * breath
        sx = 1.0 - 0.007 * breath
        canvas = Image.new("RGBA", (W + 8, H + 10), (0, 0, 0, 0))
        upper = base_im.crop((0, 0, W, foot_band_y))
        lower = base_im.crop((0, foot_band_y, W, H))
        uw = max(2, round(upper.width * sx))
        uh = max(2, round(upper.height * sy))
        upper_r = upper.resize((uw, uh), Image.Resampling.LANCZOS)
        ox = 4 + round((W - uw) * 0.5)
        oy = 6 + (foot_band_y - uh)
        canvas.alpha_composite(lower, (4, 6 + foot_band_y))
        canvas.alpha_composite(upper_r, (ox, oy))

        fn = f"frame_{idx:05d}.png"
        canvas.save(out_dir / fn)
        frames_meta.append({
            "asset": f"{STAGE_REL}/guard_hold/{fn}",
            "width": canvas.width,
            "height": canvas.height,
            "pivotX": round(base_px + 4.0, 3),
            "pivotY": round(base_py + 6.0, 3),
            "durationTicks": 1,
        })

    new_clip = dict(orig_clip)
    new_clip["fps"] = 12.0
    new_clip["loop"] = True
    new_clip["effectsBaked"] = True
    new_clip["frames"] = frames_meta
    return new_clip


def make_xray_boards(installed: dict[str, dict]) -> None:
    """生成 #141620 暗底与 #CDD3E2 浅亮底双背景 X 光核验图，确保零绿边、零残块、100% 同比例。"""
    f_h = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 24)
    f_t = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 16)

    samples = [
        ("hurt_light", 2, "01 小受击 hurt_light (f02)"),
        ("hurt_heavy", 1, "02 大受击 hurt_heavy (f01 强震)"),
        ("hurt_heavy", 6, "03 大受击 hurt_heavy (f06 滑退)"),
        ("hurt_launch", 5, "04 空中击飞 hurt_launch (f05)"),
        ("down", 2, "05 倒地平躺 down (f02)"),
        ("getup", 4, "06 单膝撑起 getup (f04)"),
        ("ranged_cast", 2, "07 K远程空翻 ranged_cast (f02)"),
        ("ranged_cast", 7, "08 K远程新月斩 ranged_cast (f07)"),
        ("air_plunge_slam", 4, "09 急坠下劈 air_plunge (f04)"),
        ("attack_1_settle", 4, "10 普攻1收招 a1_settle (f04)"),
        ("run_stop", 2, "11 跑步急停 run_stop (f02)"),
        ("guard_hold", 2, "12 架刀呼吸 guard_hold (f02)"),
    ]

    for mode, bg_col, cell_col, txt_col, out_fn in [
        ("dark", (14, 16, 24, 255), (20, 22, 32, 255), (240, 236, 255, 255), "解包核验_暗底12宫格.png"),
        ("light", (188, 196, 214, 255), (208, 214, 228, 255), (24, 24, 42, 255), "解包核验_亮底零绿边12宫格.png"),
    ]:
        cw, ch = 410, 330
        cols, rows = 4, 3
        pad, top_h = 14, 66
        board = Image.new("RGBA", (cols * cw + (cols + 1) * pad, top_h + rows * ch + (rows + 1) * pad), bg_col)
        dr = ImageDraw.Draw(board)
        dr.text((18, 16), f"即梦 v2 动作补齐 · 解包质量与角色一致性核验 ({mode.upper()})", font=f_h, fill=txt_col)

        for i, (ck, fi, title) in enumerate(samples):
            r, c = divmod(i, cols)
            x0 = pad + c * (cw + pad)
            y0 = top_h + pad + r * (ch + pad)
            cell = Image.new("RGBA", (cw, ch), cell_col)
            fm = installed[ck]["frames"][min(fi, len(installed[ck]["frames"]) - 1)]
            sp = Image.open(ASSETS / fm["asset"]).convert("RGBA")
            s = min(0.88, (cw - 32) / max(sp.width, 1), (ch - 56) / max(sp.height, 1))
            sp_r = sp.resize((max(4, round(sp.width * s)), max(4, round(sp.height * s))), Image.Resampling.LANCZOS)
            cell.alpha_composite(sp_r, ((cw - sp_r.width) // 2, 36 + (ch - 44 - sp_r.height) // 2))
            board.alpha_composite(cell, (x0, y0))
            dr = ImageDraw.Draw(board)
            dr.rectangle([x0, y0, x0 + cw - 1, y0 + ch - 1], outline=(112, 86, 198, 255), width=2)
            dr.text((x0 + 10, y0 + 8), title, font=f_t, fill=txt_col)

        board.convert("RGB").save(WORK_DIR / out_fn)


def main() -> None:
    STAGE_DIR.mkdir(parents=True, exist_ok=True)
    WORK_DIR.mkdir(parents=True, exist_ok=True)

    battle = json.loads(BATTLE_JSON.read_text(encoding="utf-8"))
    anims = battle["characters"][0]["sprite"]["animations"]

    backup_fp = WORK_DIR / "backup_animations_before_supplement_v2.json"
    if not backup_fp.exists():
        backup_fp.write_text(json.dumps(anims, ensure_ascii=False, indent=2), encoding="utf-8")

    ingame_stand_h, idle_spine_offset = measure_ingame_idle_reference(anims)
    print(f"In-game idle reference: standing height = {ingame_stand_h:.1f}px, spine_offset = {idle_spine_offset:+.1f}px")

    new_clips: dict[str, dict] = {}

    # 1. 小受击 hurt_light (8f @ 24fps：从 f41 起取，彻底避开 f40 两腿间地面残余白短线)
    new_clips["hurt_light"] = export_video_clip(
        "hurt_light",
        VID_DIR / "V1_小受击.mp4",
        [41, 42, 43, 44, 45, 47, 49, 51],
        stand_fi=54,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="ground_fixed",
        strip_floor_specks_below_foot=True,
        fps=24.0,
    )

    # 2. 大受击 hurt_heavy (12f @ 24fps：避开 f8..f10 卡通大爆星黑边残角，取 f11..f32 干净弓身犁地强滑退)
    new_clips["hurt_heavy"] = export_video_clip(
        "hurt_heavy",
        VID_DIR / "V2_大受击.mp4",
        [11, 12, 13, 14, 16, 18, 20, 22, 25, 28, 30, 32],
        stand_fi=4,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="ground_fixed",
        trim_giant_hit_ring=True,
        fps=24.0,
    )

    # 3. 空中击飞 hurt_launch (11f @ 24fps：避开 f19..f22/f34/f36 触地烟尘帧，保持纯空中干净受击翻转)
    new_clips["hurt_launch"] = export_video_clip(
        "hurt_launch",
        VID_DIR / "V3_击飞倒地起身.mp4",
        [11, 12, 14, 16, 18, 25, 27, 29, 31, 33, 38],
        stand_fi=78,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="body_bottom",
        fps=24.0,
    )

    # 4. 倒地平躺 down (6f @ 10fps loop)
    new_clips["down"] = export_video_clip(
        "down",
        VID_DIR / "V3_击飞倒地起身.mp4",
        [40, 43, 46, 49, 52, 54],
        stand_fi=78,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="ground_fixed",
        fps=10.0,
        loop=True,
    )

    # 5. 倒地撑起起身 getup (10f @ 24fps)
    new_clips["getup"] = export_video_clip(
        "getup",
        VID_DIR / "V3_击飞倒地起身.mp4",
        [56, 58, 60, 62, 65, 68, 70, 72, 75, 78],
        stand_fi=78,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="ground_fixed",
        fps=24.0,
    )

    # 6. K键远程空翻剑气 ranged_cast (14f @ 24fps：空翻帧保留离地，其余帧踩死地面且脊柱对齐 idle 零闪移)
    new_clips["ranged_cast"] = export_video_clip(
        "ranged_cast",
        VID_DIR / "V4_K键远程空翻剑气.mp4",
        [7, 9, 11, 23, 28, 32, 35, 36, 37, 44, 49, 54, 59, 64],
        stand_fi=70,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="air_flip_cast",
        keep_slash_glow=True,
        taper_horizontal_beam=True,
        fps=24.0,
    )

    # 7. S+J 空中急坠下劈砸地 air_plunge_slam (12f @ 24fps：0..3 空中双手举剑急坠 + 4..11 触地新月竖劈跪地插剑)
    new_clips["air_plunge_slam"] = export_video_clip(
        "air_plunge_slam",
        VID_DIR / "V5_空中急坠下劈砸地.mp4",
        [14, 18, 22, 25, 27, 29, 31, 33, 36, 42, 50, 58],
        stand_fi=66,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="body_bottom",
        keep_slash_glow=True,
        fps=24.0,
    )

    # 8. 普攻1段收招回待机 attack_1_settle (8f @ 24fps：从 V6 f31 右下低垂剑位无缝承接 attack_1 f12，顺势收剑回左后侧待机)
    new_clips["attack_1_settle"] = export_video_clip(
        "attack_1_settle",
        VID_DIR / "V6_普攻1段收招回待机.mp4",
        [31, 35, 39, 43, 48, 53, 59, 65],
        stand_fi=65,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="ground_fixed",
        cap_max_height_to_idle=True,
        fps=24.0,
    )

    # 9. 跑步急停收步回待机 run_stop (8f @ 36fps)
    new_clips["run_stop"] = export_video_clip(
        "run_stop",
        VID_DIR / "V7_跑步急停收步回待机.mp4",
        [2, 6, 10, 15, 21, 28, 60, 66],
        stand_fi=66,
        ingame_stand_h=ingame_stand_h,
        idle_spine_offset=idle_spine_offset,
        pivot_mode="ground_fixed",
        cap_max_height_to_idle=True,
        fps=36.0,
    )

    # 10. 普攻2段收招 attack_2_settle + 架刀呼吸循环 guard_hold (8f @ 12fps)
    new_clips["attack_2_settle"] = build_attack2_settle_from_existing(anims, ingame_stand_h, idle_spine_offset)
    new_clips["guard_hold"] = build_guard_hold_breathing(anims, ingame_stand_h, idle_spine_offset)

    for ck, clip_obj in new_clips.items():
        anims[ck] = clip_obj
        print(f"  [INSTALLED] {ck:20s}: {len(clip_obj['frames']):2d}f @ {clip_obj['fps']}fps")

    BATTLE_JSON.write_text(json.dumps(battle, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    make_xray_boards(new_clips)
    print("All 11 clips unpacked, installed into battle.json, and X-ray boards generated!")


if __name__ == "__main__":
    main()
