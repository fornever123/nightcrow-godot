#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
构建「真·刀光（人剑光一体·扇形扫掠半透明残影）」1 张 4 款验证小样的输入底板与排版元数据：
1. 从 d08.png 精确剥离右侧双细弦，得到 100% 纯净无旧白月亮块的 attack_1 f05 高清主角+笔直长剑（clean_actor_f05.png）。
2. 在深暗灰摄影棚底 (#141620) 上构建 1536x1024 2x2 四宫格（输入_真刀光底板_f05四格.png）：
   - 绘制极淡 (峰值约 22%) 的「真实剑道极坐标扇形扫掠导引纱」：
     前锋底边与主角手中笔直长剑轴线 100% 共线延伸（剑气延展直刃），外弧以肩腕为圆心顺滑扫向左上起刀位并渐隐归零，
     彻底废除违反物理规律的“两头尖中间鼓弯月亮牛角包”！
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
D08_PATH = ROOT / "assets" / "image" / "desktop-actions-hd" / "vfx_12styles_preview" / "d08.png"
PREV_MANIFEST = ROOT / r"docs\视觉设计\角色动作\特效样板12方向_20261115\manifest_12styles.json"
OUT_DIR = ROOT / r"docs\视觉设计\角色动作\真刀光样板_20261115"
BG_RGB = (20, 22, 32)  # #141620 深暗灰摄影棚底


def extract_clean_actor_and_sword() -> tuple[Image.Image, dict]:
    man = json.loads(PREV_MANIFEST.read_text(encoding="utf-8"))
    st_d08 = next(s for s in man["styles"] if s["code"] == "D08")
    im = Image.open(D08_PATH).convert("RGBA")
    arr = np.asarray(im).copy()
    H, W = arr.shape[:2]
    px, py = float(st_d08["pivotX"]), float(st_d08["pivotY"])

    # 在 d08.png 中：
    # 角色身高范围为 [py - 390 .. py + 28]，横向 [px - 190 .. px + 140]；
    # 手中笔直长剑从护手 (约 px + 125, py - 104) 沿直线指向剑尖 (约 px + 362, py - 52)。
    # 其余上方弧弦 (y < py - 392)、右侧回环弦 (x > px + 372)、以及剑刃上方的内圈细弦全部剔除！
    yy, xx = np.ogrid[:H, :W]
    in_body = (xx >= px - 210) & (xx <= px + 150) & (yy >= py - 392) & (yy <= py + 32)

    # 精确提取完整剑身：在 d08.png 中剑刃位于 y >= py - 105 (内圈细弦在 y <= py - 76 且 x > px + 265 处向上弯起)，
    # 用剑脊真实起止点 (px + 118, py - 94) -> (px + 352, py - 38) 建立完整剑身走廊，保证实体长剑 100% 饱满笔直！
    x0_s, y0_s = px + 118.0, py - 94.0
    x1_s, y1_s = px + 352.0, py - 38.0
    dx_s, dy_s = x1_s - x0_s, y1_s - y0_s
    len_sq = dx_s * dx_s + dy_s * dy_s
    t_proj = ((xx - x0_s) * dx_s + (yy - y0_s) * dy_s) / len_sq
    near_x = x0_s + np.clip(t_proj, 0.0, 1.0) * dx_s
    near_y = y0_s + np.clip(t_proj, 0.0, 1.0) * dy_s
    dist_blade = np.hypot(xx - near_x, yy - near_y)
    half_w = np.where(t_proj < 0.18, 24.0, np.where(t_proj < 0.88, 12.5, 8.0))
    in_sword = (t_proj >= -0.05) & (t_proj <= 1.0) & (dist_blade <= half_w)

    keep = in_body | in_sword
    arr[..., 3] = np.where(keep, arr[..., 3], 0)

    # 保留最大连通域（角色+手中长剑一体），彻底清零任何残余断弦碎点
    mask = (arr[..., 3] > 20).astype(np.uint8)
    n_lbl, lbls, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if n_lbl > 1:
        areas = stats[1:, cv2.CC_STAT_AREA]
        main_lbl = 1 + int(np.argmax(areas))
        arr[..., 3] = np.where(lbls == main_lbl, arr[..., 3], 0)

    arr[arr[..., 3] == 0, :3] = 0
    return Image.fromarray(arr), {
        "width": W,
        "height": H,
        "pivotX": px,
        "pivotY": py,
        "hilt": [x0_s, y0_s],
        "sword_tip": [x1_s, y1_s],
    }


def make_fan_guide_overlay(W: int, H: int, px: float, py: float, hilt: list[float], tip: list[float]) -> np.ndarray:
    """
    构建符合真实剑道物理的「透视椭圆极坐标扇形扫掠导引层」(RGBA)：
    - 挥砍旋转中心设在角色前肩胸轴线附近，使当前右下剑身恰好落在结束角 theta_end；
    - 剑气沿笔直剑身自然向前延展约 155px（对齐原攻击判定前缘），形成笔直锋利的【前锋亮刃边】；
    - 从 theta_end 逆推回左上起刀角 theta_start，透视横向拉伸 rx > ry，透明度按角度平滑衰减至 0%！
    """
    hx, hy = hilt
    tx, ty = tip
    ux, uy = tx - hx, ty - hy
    ulen = math.hypot(ux, uy)
    ux /= ulen
    uy /= ulen

    # 挥砍圆心设在角色胸肩上方，使【护手内轨迹】干净掠过头顶上方留白（绝不糊成雷达披萨饼贴脸！），
    # 同时右下【前锋边】与手中笔直长剑 100% 共线向前顺畅延展成流线剑芒，左上【起刀尾】收尖渐隐归零！
    cx = px + 18.0
    cy = py - 245.0

    # 横版透视椭圆比：横向舒展凌厉，纵向紧凑有速度张力
    aspect_y = 0.66
    yy, xx = np.mgrid[:H, :W].astype(np.float32)
    dx = xx - cx
    dy = (yy - cy) / aspect_y

    # 剑尖在椭圆极坐标中的角度与半径
    theta_tip = math.atan2((ty - cy) / aspect_y, tx - cx)   # 约 +0.66 rad (+38 度)
    theta_hilt = math.atan2((hy - cy) / aspect_y, hx - cx)
    r_tip_phys = math.hypot(tx - cx, (ty - cy) / aspect_y)
    r_hilt_phys = math.hypot(hx - cx, (hy - cy) / aspect_y)

    # 刀光外锋沿剑尖轨迹向外自然延展（横向极具破空感），内缘从剑身前 1/3 处起算，保持角色周身干净通透！
    r_out_peak = r_tip_phys + 165.0
    r_in_base = max(r_hilt_phys + 85.0, r_out_peak * 0.54)

    theta_end = theta_tip + 0.04
    theta_start = -2.05  # 左上高处起刀位，向后收束消散
    span = theta_end - theta_start

    ang = np.arctan2(dy, dx)
    d_theta = theta_end - ang
    d_theta = np.where(d_theta < -math.pi, d_theta + 2 * math.pi, d_theta)
    prog = 1.0 - (d_theta / span)  # 0.0 (左上起刀尾) -> 1.0 (右下当前剑刃前锋)
    p_cl = np.clip(prog, 0.0, 1.0)

    rad = np.hypot(dx, dy)
    # 外弧如满弓顺滑渐变，并在右下前锋处顺着笔直剑刃方向锐利收束（拒绝垂直钝切披萨边，也拒绝倒钩牛角包！）
    r_out_curve = r_out_peak * (0.76 + 0.24 * np.sin(p_cl * math.pi * 0.62))
    # 内弧在左上尾端贴近外弧收成极细破风尖丝，在右下前段刚好接住剑身中段！
    r_in_curve = r_out_curve - (r_out_curve - r_in_base) * (np.sin(p_cl * math.pi * 0.72) ** 0.85)

    # 右下前锋严格以【手中笔直长剑所在直线】为下边界：刀光全部在剑刃挥过的上方/前方扇面，绝不穿到剑刃下方悬空！
    # 剑直线方程：法向量指向挥砍后上方（左上）
    blade_nx = -(ty - hy) / ulen
    blade_ny = (tx - hx) / ulen
    # 确保法向量指向上方 (ny < 0)
    if blade_ny > 0:
        blade_nx, blade_ny = -blade_nx, -blade_ny
    signed_above_blade = (xx - hx) * blade_nx + (yy - hy) * blade_ny  # >= 0 表示在剑刃挥砍轨迹侧（上方）
    along_blade_fwd = (xx - hx) * ux + (yy - hy) * uy

    in_sector = (
        (d_theta >= -0.08)
        & (d_theta <= span)
        & (rad <= r_out_curve)
        & (rad >= r_in_curve)
        & ((signed_above_blade >= -4.0) | (yy < hy - 45.0))
    )

    norm_r = np.clip((rad - r_in_curve) / np.maximum(r_out_curve - r_in_curve, 1.0), 0.0, 1.0)
    along_fade = p_cl ** 1.75
    radial_profile = 0.18 + 0.82 * (norm_r ** 2.2)
    # 紧贴剑身延长线的炽亮前锋导引带
    lead_strip = np.exp(-((np.maximum(signed_above_blade, 0.0) / 14.0) ** 2)) * (
        (along_blade_fwd >= 0.0) & (rad <= r_out_curve + 6.0) & (signed_above_blade >= -5.0)
    )

    alpha_f = np.where(in_sector, np.clip(along_fade * radial_profile * 0.18 + lead_strip * 0.24, 0.0, 0.30), 0.0)
    guide = np.zeros((H, W, 4), dtype=np.uint8)
    whiteness = np.clip((norm_r ** 3.0) * 0.65 + lead_strip * 0.85, 0.0, 1.0)
    guide[..., 0] = (155 + 90 * whiteness).astype(np.uint8)
    guide[..., 1] = (95 + 145 * whiteness).astype(np.uint8)
    guide[..., 2] = 255
    guide[..., 3] = (alpha_f * 255).astype(np.uint8)
    return guide


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    actor_im, info = extract_clean_actor_and_sword()
    actor_fp = OUT_DIR / "clean_actor_f05.png"
    actor_im.save(actor_fp)

    guide_arr = make_fan_guide_overlay(
        info["width"], info["height"], info["pivotX"], info["pivotY"], info["hilt"], info["sword_tip"]
    )
    comp = Image.fromarray(guide_arr)
    comp.alpha_composite(actor_im)

    # 计算总有效包围盒（含扇形导引与角色）
    comp_arr = np.asarray(comp)
    ys, xs = np.nonzero(comp_arr[..., 3] > 6)
    bx0, by0 = max(0, int(xs.min()) - 14), max(0, int(ys.min()) - 14)
    bx1, by1 = min(info["width"], int(xs.max()) + 15), min(info["height"], int(ys.max()) + 15)
    bw, bh = bx1 - bx0, by1 - by0

    # 排入 1536x1024 的 2x2 四宫格（单格 768x512，四周留足 48px 安全边距防贴黄框）
    grid_W, grid_H = 1536, 1024
    cols, rows = 2, 2
    cw, ch = grid_W // cols, grid_H // rows
    pad_x, pad_y = 54, 42
    scale = min((cw - 2 * pad_x) / bw, (ch - 2 * pad_y) / bh)
    pw, ph = round(bw * scale), round(bh * scale)

    crop_comp = comp.crop((bx0, by0, bx1, by1)).resize((pw, ph), Image.Resampling.LANCZOS)
    crop_actor = actor_im.crop((bx0, by0, bx1, by1)).resize((pw, ph), Image.Resampling.LANCZOS)
    crop_actor.save(OUT_DIR / "scaled_clean_actor_cell.png")

    sheet = Image.new("RGBA", (grid_W, grid_H), (*BG_RGB, 255))
    frames_meta = []
    for idx in range(4):
        rr, cc = divmod(idx, cols)
        cx0, cy0 = cc * cw, rr * ch
        ox = cx0 + (cw - pw) // 2
        oy = cy0 + (ch - ph) // 2 + 8
        sheet.alpha_composite(crop_comp, (ox, oy))
        frames_meta.append({
            "cell_idx": idx,
            "code": f"S{idx + 1}",
            "cell": [cx0, cy0, cw, ch],
            "placed": [ox, oy, pw, ph],
            "bbox": [bx0, by0, bx1, by1],
            "orig_size": [info["width"], info["height"]],
            "orig_pivot": [info["pivotX"], info["pivotY"]],
        })

    sheet_rgb = sheet.convert("RGB")
    draw = ImageDraw.Draw(sheet_rgb)
    for rr in range(rows):
        for cc in range(cols):
            x0, y0 = cc * cw, rr * ch
            draw.rectangle([x0 + 1, y0 + 1, x0 + cw - 2, y0 + ch - 2], outline=(255, 255, 0), width=3)

    in_sheet_fp = OUT_DIR / "输入_真刀光底板_f05四格.png"
    sheet_rgb.save(in_sheet_fp)

    layout = {
        "clip": "attack_1_f05_true_slash",
        "bg_rgb": list(BG_RGB),
        "scale": scale,
        "size": [grid_W, grid_H],
        "cols": cols,
        "rows": rows,
        "frames": frames_meta,
    }
    (OUT_DIR / "输入_排版.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared {in_sheet_fp} | scale={scale:.4f}, placed={pw}x{ph}, bbox={[bx0, by0, bx1, by1]}")


if __name__ == "__main__":
    main()
