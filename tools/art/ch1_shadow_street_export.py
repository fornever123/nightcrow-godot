"""导出第一章「影街与司辰母钟楼」全部 24 张商业厚涂背景（首批 7 张 + 方案 A 扩充 17 张）至游戏正式分层目录。

源目录：
- 首批 7 张：docs/视觉设计/地图规划/第一章成图_20261114/成图16x9_*.png
- 扩充 17 张：docs/视觉设计/地图规划/第一章扩充A_20261114/成图16x9_A*.png
目标目录：assets/image/rain_street/ch1_shadow_street/ + manifest.json

处理要点（严格对齐《剧情与主题规划.md》与入口街 0.75 分层标杆）：
1. 地面脚底行（ground_px）逐张按石砌路缘高度精确标定对齐世界 floor_y = 580.0，确保左/中/右三拼块路缘与湿石板面零落差贯通。
2. 12 张 #00FF00 纯绿底拼块执行预乘去绿溢色抠空（透出游戏内 5 层实时暗云、闪电、0.12 司辰母钟楼天际线与冒烟停鸦中景楼群）。
3. 底部统一向下延展 116px 湿青黑石板暗部护基（覆盖至世界 y ≈ 865，严守禁海、禁水淹铁律）。
4. 室内/塔内/天光裂隙整屏房间向上延展暗色穹顶/浓云，高跳零穿帮。
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SRC_INIT = ROOT / "docs" / "视觉设计" / "地图规划" / "第一章成图_20261114"
SRC_BATCH_A = ROOT / "docs" / "视觉设计" / "地图规划" / "第一章扩充A_20261114"
DST_DIR = ROOT / "assets" / "image" / "rain_street" / "ch1_shadow_street"

APRONS_PX = 116
TOP_EXT_INDOOR_PX = 180

SPECS = [
    # ---- 1-1A 灯影空轿街（左/中/右 三屏全异）----
    {"id": "s1_1a_left", "dir": "A", "src": "成图16x9_A01_1-1A左拼块_书报钟亭与暗拱长街.png", "ground_frac": 0.867, "mode": "cutout"},
    {"id": "s1_1a_center", "dir": "I", "src": "成图16x9_01_1-1_无人夜宴街.png", "ground_frac": 0.870, "mode": "outdoor_sky", "sky_cut_max_y": 250},
    {"id": "s1_1a_right", "dir": "A", "src": "成图16x9_A02_1-1A右拼块_停摆茶座外廊与石阶.png", "ground_frac": 0.892, "mode": "cutout"},
    # ---- 1-1B 停摆电车雨站（首段 50% 轮换新关卡）----
    {"id": "s1_1b_left", "dir": "A", "src": "成图16x9_A12_1-1B左拼块_停摆电车雨站_西月台与559站钟.png", "ground_frac": 0.890, "mode": "cutout"},
    {"id": "s1_1b_right", "dir": "A", "src": "成图16x9_A13_1-1B右拼块_停摆电车雨站_车厢影群与东天桥.png", "ground_frac": 0.874, "mode": "cutout"},
    # ---- 1-2A 飞鸦玻璃花房顶（左/中/右 三屏全异高空屋脊）----
    {"id": "s1_2a_left", "dir": "A", "src": "成图16x9_A03_1-2A左拼块_铅皮高脊与群鸦烟囱林.png", "ground_frac": 0.868, "mode": "cutout"},
    {"id": "s1_2a_center", "dir": "I", "src": "成图16x9_02_1-2A_飞鸦玻璃花房顶.png", "ground_frac": 0.778, "mode": "outdoor_sky", "sky_cut_max_y": 290},
    {"id": "s1_2a_right", "dir": "A", "src": "成图16x9_A04_1-2A右拼块_铜制通风塔与碎裂温室翼.png", "ground_frac": 0.851, "mode": "cutout"},
    # ---- 1-2B 百表当铺夹巷（左/中/右 三屏全异多墙窄巷）----
    {"id": "s1_2b_left", "dir": "A", "src": "成图16x9_A05_1-2B左拼块_发条修配窄门与过街石梁.png", "ground_frac": 0.894, "mode": "cutout"},
    {"id": "s1_2b_center", "dir": "I", "src": "成图16x9_03_1-2B_百表当铺夹巷.png", "ground_frac": 0.866, "mode": "outdoor_sky", "sky_cut_max_y": 220},
    {"id": "s1_2b_right", "dir": "A", "src": "成图16x9_A06_1-2B右拼块_挂表铁栈桥与暗巷深井.png", "ground_frac": 0.870, "mode": "cutout"},
    # ---- 1-3A 逆影铸铁飞廊（左/中/右 三屏全异跨街高架铁桥）----
    {"id": "s1_3a_left", "dir": "A", "src": "成图16x9_A07_1-3A左拼块_双层铆接高架西引桥.png", "ground_frac": 0.866, "mode": "cutout"},
    {"id": "s1_3a_center", "dir": "I", "src": "成图16x9_04_1-3A_逆影铸铁飞廊.png", "ground_frac": 0.867, "mode": "outdoor_sky", "sky_cut_max_y": 240},
    {"id": "s1_3a_right", "dir": "A", "src": "成图16x9_A08_1-3A右拼块_信号灯笼桥台与逆影石墩.png", "ground_frac": 0.864, "mode": "cutout"},
    # ---- 1-3B 司辰铸钟残廊（左/中/右 三屏全异皇家铸钟工坊）----
    {"id": "s1_3b_left", "dir": "A", "src": "成图16x9_A09_1-3B左拼块_断裂音叉架与铸钟熔炉冷室.png", "ground_frac": 0.863, "mode": "indoor"},
    {"id": "s1_3b_center", "dir": "I", "src": "成图16x9_05_1-3B_司辰铸钟残廊.png", "ground_frac": 0.864, "mode": "indoor"},
    {"id": "s1_3b_right", "dir": "A", "src": "成图16x9_A10_1-3B右拼块_巨型钟锤滑轨与试音残钟厅.png", "ground_frac": 0.865, "mode": "indoor"},
    # ---- 1-3C 司辰母钟楼正门前庭（收束新节点：万表校时阶 + 青铜总枢巨门）----
    {"id": "s1_3c_left", "dir": "A", "src": "成图16x9_A16_1-3C左拼块_司辰母钟楼正门前庭_万表校时阶.png", "ground_frac": 0.872, "mode": "cutout"},
    {"id": "s1_3c_right", "dir": "A", "src": "成图16x9_A17_1-3C右拼块_司辰母钟楼正门前庭_青铜总枢巨门.png", "ground_frac": 0.879, "mode": "cutout"},
    # ---- 1-4 司辰母钟楼登顶长阶（下段巨钟背影 + 上段母钟擒纵天轴）----
    {"id": "s1_4_center", "dir": "I", "src": "成图16x9_06_1-4_巨钟背影盘旋阶.png", "ground_frac": 0.865, "mode": "indoor"},
    {"id": "s1_4_upper", "dir": "A", "src": "成图16x9_A11_1-4上段_母钟擒纵天轴与临顶盘旋阶.png", "ground_frac": 0.867, "mode": "indoor"},
    # ---- J1 岔路街口 / S1 无主校时表坊（中场休整室） / E1 漏光校晷小广场（破晓乱入试刀场）----
    {"id": "j_fork_center", "dir": "I", "src": "成图16x9_07_J1J2_街口高低分流岔路.png", "ground_frac": 0.868, "mode": "outdoor_sky", "sky_cut_max_y": 240},
    {"id": "s1_rest_center", "dir": "A", "src": "成图16x9_A14_S1_无主校时表坊_肉鸽中场休整室.png", "ground_frac": 0.859, "mode": "indoor"},
    {"id": "e1_court_center", "dir": "A", "src": "成图16x9_A15_E1_漏光校晷小广场_破晓乱入与同道试刀场.png", "ground_frac": 0.867, "mode": "indoor"},
]


def _chroma_key_green_cutout(rgb: np.ndarray, ground_px: float) -> np.ndarray:
    """对 #00FF00 纯绿底站立层拼块执行高精度去溢色抠空，地面行以下保持 100% 实心不透明。"""
    f = rgb.astype(np.float32) / 255.0
    r, g, b = f[:, :, 0], f[:, :, 1], f[:, :, 2]
    max_rb = np.maximum(r, b)
    alpha = 1.0 - np.clip((g - max_rb - 0.11) / 0.24, 0.0, 1.0)
    # 抑制绿幕边缘溢色（暖白灯 max_rb == r >= g、冷灰蓝石材 max_rb == b >= g 均完全不受损）
    f[:, :, 1] = np.minimum(g, max_rb)
    # 地面石板行以下强制实心不透明，杜绝任何高光反光误判
    gy = max(0, min(rgb.shape[0], int(round(ground_px)) - 4))
    alpha[gy:, :] = 1.0
    out_rgb = (np.clip(f, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    out_a = (np.clip(alpha, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return np.dstack([out_rgb, out_a])


def _extract_outdoor_sky_alpha(rgb: np.ndarray, max_y: int) -> np.ndarray:
    """将首批室外整屏成图顶部无建筑的冷灰蓝阴云天平滑抠透。"""
    h, w, _ = rgb.shape
    alpha = np.ones((h, w), dtype=np.float32)
    if max_y <= 0:
        return alpha

    f = rgb.astype(np.float32) / 255.0
    r, g, b = f[:, :, 0], f[:, :, 1], f[:, :, 2]
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b

    top_band = f[:18, :, :]
    top_lum = lum[:18, :]
    sky_candidates = top_band[top_lum > np.percentile(top_lum, 45)]
    sky_ref = np.median(sky_candidates, axis=0) if sky_candidates.size else np.array([0.14, 0.17, 0.24], dtype=np.float32)

    sub = f[:max_y, :, :]
    dist = np.linalg.norm(sub - sky_ref[None, None, :], axis=2)
    gx = np.abs(np.diff(lum[:max_y, :], axis=1, prepend=lum[:max_y, :1]))
    gy = np.abs(np.diff(lum[:max_y, :], axis=0, prepend=lum[:1, :]))
    grad = np.hypot(gx, gy)

    is_sky_like = (dist < 0.095) & (grad < 0.032) & (lum[:max_y, :] > 0.075) & (b[:max_y, :] >= r[:max_y, :] * 0.95)
    col_sky = np.zeros((max_y, w), dtype=np.float32)
    for x in range(w):
        col = is_sky_like[:, x]
        run_solid = 0
        stop_y = 0
        for y in range(max_y):
            if col[y]:
                run_solid = 0
                stop_y = y + 1
            else:
                run_solid += 1
                if run_solid >= 4:
                    break
        if stop_y > 0:
            col_sky[:stop_y, x] = 1.0

    sky_mask_img = Image.fromarray((col_sky * 255.0).clip(0, 255).astype(np.uint8), mode="L")
    sky_mask_blur = np.array(sky_mask_img.filter(ImageFilter.GaussianBlur(radius=5.5)), dtype=np.float32) / 255.0

    top_ramp = np.linspace(0.0, 1.0, 26, dtype=np.float32)[:, None]
    sub_alpha = (1.0 - sky_mask_blur).clip(0.0, 1.0)
    sub_alpha[:26, :] = np.minimum(sub_alpha[:26, :], top_ramp)
    alpha[:max_y, :] = sub_alpha
    return alpha


def _harmonize_side_seams(rgba: np.ndarray, edge_px: int = 14) -> np.ndarray:
    """在左右边缘 14px 对实心像素做极轻暗石柱收口过渡，消除不同拼块横向拼接时的微弱色阶跳变。"""
    out = rgba.astype(np.float32)
    pier_tone = np.array([15.0, 18.0, 27.0], dtype=np.float32)
    ramp_l = np.linspace(0.42, 0.0, edge_px, dtype=np.float32)[None, :, None]
    ramp_r = np.linspace(0.0, 0.42, edge_px, dtype=np.float32)[None, :, None]
    out[:, :edge_px, :3] = out[:, :edge_px, :3] * (1.0 - ramp_l) + pier_tone * ramp_l
    out[:, -edge_px:, :3] = out[:, -edge_px:, :3] * (1.0 - ramp_r) + pier_tone * ramp_r
    return np.clip(out, 0.0, 255.0).astype(np.uint8)


def _extend_bottom_apron(rgba: np.ndarray, apron_px: int) -> np.ndarray:
    """向下延展湿青黑石板暗部基座，彻底覆盖原河道区域，消除底边黑条与水面。"""
    h, w, _ = rgba.shape
    src_strip = rgba[h - apron_px : h, :, :3][::-1, :, :].astype(np.float32)
    strip_img = Image.fromarray(src_strip.clip(0, 255).astype(np.uint8), mode="RGB").filter(
        ImageFilter.GaussianBlur(radius=2.2)
    )
    apron_rgb = np.array(strip_img, dtype=np.float32)
    fade = np.linspace(0.92, 0.34, apron_px, dtype=np.float32)[:, None, None]
    slate_floor = np.array([10.0, 13.0, 21.0], dtype=np.float32)[None, None, :]
    apron_rgb = apron_rgb * fade + slate_floor * (1.0 - fade)
    apron_a = np.full((apron_px, w, 1), 255.0, dtype=np.float32)
    apron = np.concatenate([apron_rgb, apron_a], axis=2).clip(0, 255).astype(np.uint8)
    return np.concatenate([rgba, apron], axis=0)


def _extend_indoor_vault(rgba: np.ndarray, ext_px: int) -> np.ndarray:
    """室内/钟楼内部/天光穹窿关卡向上延展暗色拱顶与浓云，高跳时不露硬切边。"""
    _, w, _ = rgba.shape
    top_strip = rgba[:ext_px, :, :3][::-1, :, :].astype(np.float32)
    blur_img = Image.fromarray(top_strip.clip(0, 255).astype(np.uint8), mode="RGB").filter(
        ImageFilter.GaussianBlur(radius=4.0)
    )
    vault_rgb = np.array(blur_img, dtype=np.float32)
    fade = np.linspace(0.32, 0.94, ext_px, dtype=np.float32)[:, None, None]
    dark_vault = np.array([9.0, 10.0, 16.0], dtype=np.float32)[None, None, :]
    vault_rgb = vault_rgb * fade + dark_vault * (1.0 - fade)
    vault_a = np.full((ext_px, w, 1), 255.0, dtype=np.float32)
    vault = np.concatenate([vault_rgb, vault_a], axis=2).clip(0, 255).astype(np.uint8)
    return np.concatenate([vault, rgba], axis=0)


def main() -> None:
    DST_DIR.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, dict] = {}
    for sp in SPECS:
        base_dir = SRC_BATCH_A if sp["dir"] == "A" else SRC_INIT
        src_path = base_dir / sp["src"]
        im = Image.open(src_path).convert("RGB")
        rgb = np.array(im, dtype=np.uint8)
        h0, w0, _ = rgb.shape
        ground_px = float(h0) * float(sp["ground_frac"])
        mode = sp["mode"]

        if mode == "cutout":
            rgba = _chroma_key_green_cutout(rgb, ground_px)
            indoor_flag = False
        elif mode == "indoor":
            alpha = np.full((h0, w0), 255, dtype=np.uint8)
            rgba = np.dstack([rgb, alpha])
            rgba = _extend_indoor_vault(rgba, TOP_EXT_INDOOR_PX)
            ground_px += float(TOP_EXT_INDOOR_PX)
            indoor_flag = True
        else:
            alpha_f = _extract_outdoor_sky_alpha(rgb, int(sp.get("sky_cut_max_y", 240)))
            rgba = np.dstack([rgb, (alpha_f * 255.0).clip(0, 255).astype(np.uint8)])
            indoor_flag = False

        rgba = _harmonize_side_seams(rgba, 14)
        rgba = _extend_bottom_apron(rgba, APRONS_PX)
        out_name = f"{sp['id']}.png"
        out_path = DST_DIR / out_name
        Image.fromarray(rgba, mode="RGBA").save(out_path)

        manifest[sp["id"]] = {
            "tex": f"res://assets/image/rain_street/ch1_shadow_street/{out_name}",
            "width_px": int(rgba.shape[1]),
            "height_px": int(rgba.shape[0]),
            "ground_px": round(ground_px, 2),
            "indoor": indoor_flag,
            "mode": mode,
        }
        print(f"[OK] {out_name:18s}: {rgba.shape[1]}x{rgba.shape[0]}, ground_px={ground_px:6.1f}, mode={mode}")

    manifest_path = DST_DIR / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Manifest written ({len(manifest)} assets) -> {manifest_path}")


if __name__ == "__main__":
    main()
