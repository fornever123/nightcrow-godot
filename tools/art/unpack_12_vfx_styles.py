#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 3 张「12 种高帅度刀光特效样板」(板A D01-D04 / 板B D05-D08 / 板C D09-D12)
从 1536x1024 绿幕四宫格精确解包、去绿幕溢色、按【角色本体 ROI】1:1 锚定回 attack_1 f05 世界坐标，
产出 assets/image/desktop-actions-hd/vfx_12styles_preview/d01.png .. d12.png 与 manifest_12styles.json。
"""
from __future__ import annotations

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
from codex_redraw_map_cv2 import bleed_transparent_rgb, iou  # noqa: E402

WORK_DIR = ROOT / r"docs\视觉设计\角色动作\特效样板12方向_20261115"
STAGE_REL = "image/desktop-actions-hd/vfx_12styles_preview"
STAGE_ABS = ROOT / "assets" / "image" / "desktop-actions-hd" / "vfx_12styles_preview"

STYLE_META = [
    # 板A
    ("D01", "次元断空·纯黑空间裂口", "黑紫裂面 + 冰白锋线十字星芒", "生图_板A_D01至D04.png", 0),
    ("D02", "扳机社折角·超音速紫雷锯刃", "今石洋之折线雷电 + 折角爆闪", "生图_板A_D01至D04.png", 1),
    ("D03", "刹那断晷·5:59碎时几何星轨", "司辰钟盘刻度弧 + 碎时紫晶棱片", "生图_板A_D01至D04.png", 2),
    ("D04", "错位断层·超速空间切帧", "黑紫冰白横向错层切帧断层", "生图_板A_D01至D04.png", 3),
    # 板B
    ("D05", "九日狂墨·枯笔浓墨夹紫电", "狂草飞白浓墨包夹炽白紫电核", "生图_板B_D05至D08.png", 0),
    ("D06", "夜鸦千本·刃羽风暴流", "朔专属黑曜紫晶鸦羽利刃风暴", "生图_板B_D05至D08.png", 1),
    ("D07", "不死妖炎·黑紫怨灵涡流", "只狼不死斩式深渊黑紫气焰涡流", "生图_板B_D05至D08.png", 2),
    ("D08", "极简居合·双弦一线天", "双层极细冰白紫弦 + 破风紫刃丝", "生图_板B_D05至D08.png", 3),
    # 板C
    ("D09", "双层音爆·破风激波环斩", "剑锷音爆环 + 折面冰蓝紫破风激波", "生图_板C_D09至D12.png", 0),
    ("D10", "千刃残像·剑影扇面连斩", "半透明紫光弧内嵌五柄笔直残影剑", "生图_板C_D09至D12.png", 1),
    ("D11", "黑曜棱镜·哥特琉璃切面", "归晓大教堂银黑哥特雕纹 + 紫晶棱面", "生图_板C_D09至D12.png", 2),
    ("D12", "断晓蚀日·外黑内白日蚀反转", "黑紫日冕雷焰包裹纯白日蚀核心", "生图_板C_D09至D12.png", 3),
]


def load_keyed_sheet(sheet_name: str, W: int, H: int, cols: int, rows: int) -> np.ndarray:
    gen_fp = WORK_DIR / sheet_name
    cache_dir = WORK_DIR / "_keyed_cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    stem = gen_fp.stem
    clean_rgb_fp = cache_dir / f"{stem}_clean.png"
    keyed_fp = cache_dir / f"{stem}_keyed.png"

    cw, ch = W // cols, H // rows
    src = Image.open(gen_fp).convert("RGB")
    if src.size != (W, H):
        src = src.resize((W, H), Image.Resampling.LANCZOS)

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

    gen_mtime = gen_fp.stat().st_mtime
    if not (keyed_fp.exists() and keyed_fp.stat().st_mtime >= gen_mtime):
        Image.fromarray(arr.astype(np.uint8)).save(clean_rgb_fp)
        key_green_fn(str(clean_rgb_fp), str(keyed_fp))
    return np.asarray(Image.open(keyed_fp).convert("RGBA"))


def main() -> None:
    lay = json.loads((WORK_DIR / "输入_排版.json").read_text(encoding="utf-8"))
    W, H = int(lay["size"][0]), int(lay["size"][1])
    s = float(lay["scale"])
    cols, rows = int(lay["cols"]), int(lay["rows"])

    STAGE_ABS.mkdir(parents=True, exist_ok=True)
    sheet_cache: dict[str, np.ndarray] = {}

    orig_fr0 = lay["frames"][0]
    orig_im = Image.open(ROOT / "assets" / orig_fr0["asset"]).convert("RGBA")
    frame_size = [int(orig_fr0["size"][0]), int(orig_fr0["size"][1])]
    if orig_im.size != tuple(frame_size):
        orig_im = orig_im.resize(tuple(frame_size), Image.Resampling.LANCZOS)
    orig_im = clean_stray_specks(orig_im)

    raw_items = []
    for code, title, subtitle, sheet_name, cell_idx in STYLE_META:
        if sheet_name not in sheet_cache:
            sheet_cache[sheet_name] = load_keyed_sheet(sheet_name, W, H, cols, rows)
        sheet = sheet_cache[sheet_name]
        fr = lay["frames"][cell_idx]
        cx, cy, cell_w, cell_h = [int(v) for v in fr["cell"]]

        sub = sheet[cy + 7:cy + cell_h - 7, cx + 7:cx + cell_w - 7].copy()
        sub[..., 3] = np.where(sub[..., 3] >= 20, sub[..., 3], 0)
        mask = (sub[..., 3] > 0).astype(np.uint8)
        n_lbl, lbls, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
        keep_mask = np.zeros_like(mask, dtype=bool)
        for li in range(1, n_lbl):
            area = int(stats[li, cv2.CC_STAT_AREA])
            if area >= 36:
                keep_mask |= (lbls == li)
            elif area >= 8:
                if int(sub[lbls == li, 3].max()) >= 190:
                    keep_mask |= (lbls == li)
        sub[..., 3] = np.where(keep_mask, sub[..., 3], 0)
        sub = bleed_transparent_rgb(sub, solid_thresh=210)

        cell_canvas = np.zeros_like(sheet)
        cell_canvas[cy + 7:cy + cell_h - 7, cx + 7:cx + cell_w - 7] = sub
        ys, xs = np.nonzero(cell_canvas[..., 3] > 45)
        x0_raw, y0_raw = int(xs.min()), int(ys.min())
        x1_raw, y1_raw = int(xs.max()) + 1, int(ys.max()) + 1
        new_im = Image.fromarray(cell_canvas).crop((x0_raw, y0_raw, x1_raw, y1_raw))

        x, y, pw, ph = [int(v) for v in fr["placed"]]
        bx0, by0, bx1, by1 = [int(v) for v in fr["bbox"]]
        tgt = np.zeros((H, W), dtype=bool)
        oc = orig_im.crop((bx0, by0, bx1, by1)).resize((pw, ph), Image.Resampling.LANCZOS)
        tgt[y:y + ph, x:x + pw] = np.asarray(oc)[..., 3] > 60

        # 严格用左侧角色本体区域（排除上方刀光尾尖 y < y+68，仅对齐头发+躯干+双腿双靴）做全局精确 1:1 锚定！
        rx0, rx1 = max(0, x - 24), min(W, x + 252)
        ry0, ry1 = max(0, y + 68), min(H, y + ph + 24)
        tgt_roi = tgt[ry0:ry1, rx0:rx1]
        rw, rh = rx1 - rx0, ry1 - ry0

        # 取左侧角色列 (x0_raw .. x0_raw + 230) 的脚底 y 作为初始基准，彻底免疫刀光上下延伸高度差异
        na_full = (np.asarray(new_im)[..., 3] > 60).astype(np.uint8)
        char_col_w = min(new_im.width, 220)
        c_ys, c_xs = np.nonzero(na_full[:, :char_col_w] > 0)
        char_boot_rel_y = int(c_ys.max()) + 1 if len(c_ys) > 0 else new_im.height
        foot_cx = x + (float(fr["pivot"][0]) - bx0) * s

        best = (-1.0, None)
        for k in np.linspace(0.86, 1.08, 45):
            nw = max(1, round(new_im.width * float(k)))
            nh = max(1, round(new_im.height * float(k)))
            na_s = cv2.resize(na_full, (nw, nh), interpolation=cv2.INTER_NEAREST) > 0
            base_x = round(foot_cx - (foot_cx - x0_raw) * float(k))
            base_y = round((y + ph) - char_boot_rel_y * float(k))
            for dy in range(-22, 23, 2):
                py = base_y + dy
                for dx in range(-28, 29, 2):
                    px = base_x + dx
                    # 计算与 [rx0:rx1, ry0:ry1] 的交集切片，极速算角色本体 IoU
                    ix0, ix1 = max(rx0, px), min(rx1, px + nw)
                    iy0, iy1 = max(ry0, py), min(ry1, py + nh)
                    if ix1 <= ix0 or iy1 <= iy0:
                        continue
                    cand_roi = np.zeros((rh, rw), dtype=bool)
                    cand_roi[iy0 - ry0:iy1 - ry0, ix0 - rx0:ix1 - rx0] = na_s[iy0 - py:iy1 - py, ix0 - px:ix1 - px]
                    sc = iou(cand_roi, tgt_roi)
                    if sc > best[0]:
                        best = (sc, (float(k), int(px), int(py)))

        score, (best_k, px, py) = best
        best_ni = new_im.resize(
            (max(1, round(new_im.width * best_k)), max(1, round(new_im.height * best_k))),
            Image.Resampling.LANCZOS,
        )
        placed_im = Image.fromarray(np.zeros((H, W, 4), dtype=np.uint8))
        placed_im.paste(best_ni, (px, py), best_ni)
        placed_im = Image.fromarray(bleed_transparent_rgb(np.asarray(placed_im), solid_thresh=210))

        ox = x - bx0 * s
        oy = y - by0 * s
        raw_items.append({
            "code": code,
            "title": title,
            "subtitle": subtitle,
            "sheet": sheet_name,
            "cell_idx": cell_idx,
            "char_iou": round(score, 3),
            "fit_scale": round(best_k, 3),
            "orig_size": frame_size,
            "orig_pivot": [float(fr["pivot"][0]), float(fr["pivot"][1])],
            "_placed": placed_im,
            "_o": (ox, oy),
        })

    need = 0.0
    for r in raw_items:
        ox, oy = r["_o"]
        w, h = r["orig_size"]
        a = np.asarray(r["_placed"])[..., 3] > 18
        ys, xs = np.nonzero(a)
        u0, u1 = (float(xs.min()) - ox) / s, (float(xs.max()) + 1.0 - ox) / s
        v0, v1 = (float(ys.min()) - oy) / s, (float(ys.max()) + 1.0 - oy) / s
        need = max(need, -u0, u1 - w, -v0, v1 - h)

    pad = int(np.ceil(max(need, 0.0))) + 6
    manifest = {
        "clip": "attack_1",
        "frame_index": 5,
        "pad": pad,
        "scale": s,
        "styles": [],
    }

    for r in raw_items:
        ox, oy = r["_o"]
        w, h = r["orig_size"]
        crop_box = (ox - pad * s, oy - pad * s, ox + (w + pad) * s, oy + (h + pad) * s)
        fr_im = r["_placed"].transform((w + 2 * pad, h + 2 * pad), Image.Transform.EXTENT, crop_box, Image.Resampling.BICUBIC)
        fr_arr = bleed_transparent_rgb(np.asarray(fr_im), solid_thresh=210)

        # 1) 去除绿底高亮光晕残留青绿偏色（如 D08 极细发光外弦）：将 G 偏高高亮青白光晕拉回纯净冰蓝白
        r_ch = fr_arr[..., 0].astype(np.int32)
        g_ch = fr_arr[..., 1].astype(np.int32)
        b_ch = fr_arr[..., 2].astype(np.int32)
        cyan_spill = (fr_arr[..., 3] > 0) & (g_ch > b_ch) & (b_ch >= 165)
        b_ch = np.where(cyan_spill, np.minimum(255, g_ch + 8), b_ch)
        g_ch = np.where(cyan_spill, np.minimum(g_ch, (r_ch + b_ch) // 2 + 4), g_ch)

        # 2) 适配游戏内置 char_light.gdshader 自发光阈值 (slash_emissive: c.b >= 0.6, c.b - c.g >= 0.15, c.b - c.r >= 0.05)
        #    仅针对【角色躯干框以外】的刀光亮白/冰白区域校准至冷晶紫白 (#EFD5FF 级: B>=220, R<=B-16, G<=B-42)，
        #    使其在暗夜雨街 100% 触发自发光免受白衣 hi_knee 压灰，同时绝不触碰角色白衣/发带，也绝不改动纯黑裂口/浓墨暗核！
        H_fr, W_fr = fr_arr.shape[:2]
        yy_grid, xx_grid = np.ogrid[:H_fr, :W_fr]
        piv_x = float(r["orig_pivot"][0]) + pad
        piv_y = float(r["orig_pivot"][1]) + pad
        in_char_body = (
            (xx_grid >= piv_x - 185)
            & (xx_grid <= piv_x + 68)
            & (yy_grid >= piv_y - 390)
            & (yy_grid <= piv_y + 28)
        )
        vfx_bright = (~in_char_body) & (fr_arr[..., 3] > 0) & (np.maximum(g_ch, b_ch) >= 195) & (np.minimum(r_ch, np.minimum(g_ch, b_ch)) >= 150)
        b_boost = np.maximum(b_ch, np.minimum(255, np.maximum(r_ch, g_ch) + 12))
        b_ch = np.where(vfx_bright, np.maximum(b_boost, 224), b_ch)
        r_ch = np.where(vfx_bright, np.minimum(r_ch, b_ch - 16), r_ch)
        g_ch = np.where(vfx_bright, np.minimum(g_ch, b_ch - 42), g_ch)

        # 角色框边缘若有刀光冷白也保持免黑描边 (R <= B - 22)
        cool_vfx = (~in_char_body) & (fr_arr[..., 3] > 0) & (b_ch >= 210) & (b_ch >= g_ch - 6) & (r_ch > b_ch - 18)
        r_ch = np.where(cool_vfx, np.clip(b_ch - 18, 0, 255), r_ch)

        fr_arr[..., 0] = r_ch.astype(np.uint8)
        fr_arr[..., 1] = g_ch.astype(np.uint8)
        fr_arr[..., 2] = b_ch.astype(np.uint8)
        fr_arr = bleed_transparent_rgb(fr_arr, solid_thresh=210)

        fname = f"{r['code'].lower()}.png"
        Image.fromarray(fr_arr).save(STAGE_ABS / fname)
        manifest["styles"].append({
            "code": r["code"],
            "title": r["title"],
            "subtitle": r["subtitle"],
            "asset": f"{STAGE_REL}/{fname}",
            "width": w + 2 * pad,
            "height": h + 2 * pad,
            "pivotX": round(r["orig_pivot"][0] + pad, 3),
            "pivotY": round(r["orig_pivot"][1] + pad, 3),
            "char_iou": r["char_iou"],
            "fit_scale": r["fit_scale"],
        })
        print(f"{r['code']} {r['title']}: char_iou={r['char_iou']:.3f}, scale={r['fit_scale']:.3f}, size={w + 2 * pad}x{h + 2 * pad}")

    (WORK_DIR / "manifest_12styles.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved 12 unpacked styles -> {STAGE_ABS}")


if __name__ == "__main__":
    main()
