#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""将大纵深双路线样板素材（R1 2D四层 + R2 3D HD-2D PBR材质）做精准去绿消溢与 PBR 派生，
输出到 assets/image/rain_street/depth_lab_20261118/。
"""
from __future__ import annotations

import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(r"E:\00game\nightcrow-godot")
RAW = ROOT / "docs" / "_当前分支草稿" / "背景线" / "大纵深重构_20261118" / "raw"
OUT = ROOT / "assets" / "image" / "rain_street" / "depth_lab_20261118"


def chroma_key_green(img: Image.Image, spill_strength: float = 1.0) -> Image.Image:
    """高洁净度 #00FF00 绿幕消溢抠图，保留暗部细节与抗锯齿柔边。"""
    arr = np.asarray(img.convert("RGBA"), dtype=np.float32) / 255.0
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    rb_max = np.maximum(r, b)
    green_dom = g - rb_max

    # 软透明过渡带：green_dom > 0.24 判纯绿幕，< 0.08 判不透明前景
    alpha = 1.0 - np.clip((green_dom - 0.08) / 0.16, 0.0, 1.0)
    # 顺手清除极亮偏绿噪点
    alpha = np.where((g > 0.55) & (green_dom > 0.14), 0.0, alpha)

    # 绿色消溢（把边缘残留绿光压回 R/B 平均亮度）
    spill = np.maximum(0.0, g - rb_max * 1.02)
    g_clean = g - spill * (0.92 * spill_strength)
    out = np.stack([r, np.clip(g_clean, 0.0, 1.0), b, alpha], axis=-1)
    res = Image.fromarray((np.clip(out, 0.0, 1.0) * 255.0).astype(np.uint8), "RGBA")
    return res


def make_normal_and_roughness(
    img: Image.Image,
    out_normal: Path,
    out_rough: Path,
    strength: float = 2.6,
    rough_lo: float = 0.22,
    rough_hi: float = 0.78,
    invert_rough: bool = True,
) -> None:
    """从手绘厚涂漫反射图衍生光滑大形 PBR 法线图 + 湿润粗糙度图。"""
    gray = np.asarray(img.convert("L").filter(ImageFilter.GaussianBlur(radius=1.2)), dtype=np.float32) / 255.0
    # 周期边界梯度，保证无缝贴图法线也无缝
    gx = (np.roll(gray, -1, axis=1) - np.roll(gray, 1, axis=1)) * 0.5 * strength
    gy = (np.roll(gray, -1, axis=0) - np.roll(gray, 1, axis=0)) * 0.5 * strength
    nx = -gx
    ny = -gy
    nz = np.ones_like(gray)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-6
    n_rgb = np.stack([(nx / norm) * 0.5 + 0.5, (ny / norm) * 0.5 + 0.5, (nz / norm) * 0.5 + 0.5], axis=-1)
    Image.fromarray((np.clip(n_rgb, 0.0, 1.0) * 255.0).astype(np.uint8), "RGB").save(out_normal)

    # 亮石面较光滑湿润（低粗糙度），暗石缝较粗糙
    r_val = (1.0 - gray) if invert_rough else gray
    r_map = rough_lo + np.clip(r_val, 0.0, 1.0) * (rough_hi - rough_lo)
    Image.fromarray((np.clip(r_map, 0.0, 1.0) * 255.0).astype(np.uint8), "L").save(out_rough)


def make_window_emission(img: Image.Image, out_emit: Path) -> None:
    """提取哥特立面图里的暖白/淡金窗户作为 3D 自发光遮罩（零蓝/零紫干扰）。"""
    arr = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    warm = np.clip((r - b) * 2.2, 0.0, 1.0)
    lum = 0.299 * r + 0.587 * g + 0.114 * b
    mask = np.clip((lum - 0.36) / 0.28, 0.0, 1.0) * warm
    emit = arr * mask[..., None] * 1.45
    Image.fromarray((np.clip(emit, 0.0, 1.0) * 255.0).astype(np.uint8), "RGB").save(out_emit)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    meta: dict = {}

    # 1. R1 远景天光+母钟楼（不透明）
    p_far = RAW / "r1_far_sky_tower.png"
    if p_far.exists():
        im = Image.open(p_far).convert("RGB").resize((1672, 941), Image.Resampling.LANCZOS)
        im.save(OUT / "r1_far_sky_tower.png")
        meta["r1_far_sky_tower"] = {"w": 1672, "h": 941}

    # 2. R1 中远景深渊城群（绿幕抠空上天）
    p_mid = RAW / "r1_mid_city_abyss.png"
    if p_mid.exists():
        im = Image.open(p_mid).resize((1672, 941), Image.Resampling.LANCZOS)
        keyed = chroma_key_green(im, spill_strength=1.0)
        keyed.save(OUT / "r1_mid_city_abyss.png")
        meta["r1_mid_city_abyss"] = {"w": 1672, "h": 941}

    # 3. R1 玩法层高架石桥与门楼（绿幕抠空天空与桥洞）
    p_play = RAW / "r1_play_viaduct.png"
    if p_play.exists():
        im = Image.open(p_play).resize((1672, 941), Image.Resampling.LANCZOS)
        keyed = chroma_key_green(im, spill_strength=1.0)
        keyed.save(OUT / "r1_play_viaduct.png")
        # 检测路面行号：找 y=64%..82% 中间横向不透明度最高的连续带
        a = np.asarray(keyed)[..., 3] > 180
        row_cov = a.mean(axis=1)
        band = np.where((np.arange(941) >= int(941 * 0.62)) & (np.arange(941) <= int(941 * 0.84)) & (row_cov > 0.90))[0]
        ground_px = float(band[0] + min(24, max(8, len(band) // 3))) if len(band) > 0 else 690.0
        meta["r1_play_viaduct"] = {"w": 1672, "h": 941, "ground_px": round(ground_px, 1), "road_band": [int(band[0]), int(band[-1])] if len(band) > 0 else [660, 745]}

    # 4. R1 最前景压框剪影（绿幕抠空 + 轻微离焦）
    p_fg = RAW / "r1_fg_frame.png"
    if p_fg.exists():
        im = Image.open(p_fg).resize((1672, 941), Image.Resampling.LANCZOS)
        keyed = chroma_key_green(im, spill_strength=1.1)
        # 轻度高斯离焦，营造真镜头前景景深
        keyed = keyed.filter(ImageFilter.GaussianBlur(radius=2.2))
        keyed.save(OUT / "r1_fg_frame.png")
        meta["r1_fg_frame"] = {"w": 1672, "h": 941}

    # 5. R2 3D HD-2D 无缝 PBR 材质集
    for name, strength, r_lo, r_hi in [
        ("r2_tex_cobble", 3.2, 0.14, 0.62),      # 湿石板：石面反光强、石缝粗糙
        ("r2_tex_facade", 2.4, 0.45, 0.86),
        ("r2_tex_stone_trim", 2.8, 0.42, 0.84),
    ]:
        src = RAW / f"{name}.png"
        if src.exists():
            im = Image.open(src).convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
            im.save(OUT / f"{name}.png")
            make_normal_and_roughness(
                im,
                OUT / f"{name}_normal.png",
                OUT / f"{name}_rough.png",
                strength=strength,
                rough_lo=r_lo,
                rough_hi=r_hi,
            )
            if name == "r2_tex_facade":
                make_window_emission(im, OUT / f"{name}_emit.png")
            meta[name] = {"w": 1024, "h": 1024}

    (OUT / "meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("DEPTH_LAB_ASSETS_READY:", json.dumps(meta, ensure_ascii=False))


if __name__ == "__main__":
    main()
