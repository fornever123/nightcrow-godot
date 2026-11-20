#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 12 种高帅度刀光特效样板 (D01..D12) + 原版 + 初版重画样板 组装成高分辨率评审画廊：
1. 12种高帅度刀光样板_雨夜实机同帧12宫格总览.png（顶部含原版/初版基准对比 + 3×4 实机雨夜街同帧特写）
2. 实机特写_板A_D01至D04.png / 实机特写_板B_D05至D08.png / 实机特写_板C_D09至D12.png（2×2 超清实机大图）
3. 12种高帅度刀光样板_纯净暗底12宫格高清细节总览.png（1:1 世界坐标 + 脚底红点与 385px 等高线核验）
4. 12种高帅度刀光样板_浮空白城亮底可读性检验.png（检验第三章纯白亮底下的暗核剪影对比度）
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Tuple

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
WORK_DIR = ROOT / r"docs\视觉设计\角色动作\特效样板12方向_20261115"
SHOT_DIR = ROOT / ".runtime" / "vfx_12styles_shots"
OUT_DIR = WORK_DIR / "验收画廊"
BRAIN_DIR = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988")


def load_cn_font(size: int = 20) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for fp in [r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if Path(fp).exists():
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()


def crop_rain_focus(shot_fp: Path, crop_box: Tuple[int, int, int, int] = (340, 255, 1060, 675)) -> Image.Image:
    """裁取 1280x720 实机雨夜街中『角色 + 满月大刀光 + 右侧暖光门洞 + 脚下积水倒影』黄金构图区 (720x420)"""
    im = Image.open(shot_fp).convert("RGB")
    return im.crop(crop_box)


def render_world_tile(fd: dict, box_w: int, box_h: int, ax: int, ay: int, bg_rgb: Tuple[int, int, int], guide_dark: bool = False) -> Image.Image:
    canvas = Image.new("RGBA", (box_w, box_h), (*bg_rgb, 255))
    draw = ImageDraw.Draw(canvas)
    line_col = (150, 162, 188, 170) if guide_dark else (68, 86, 118, 175)
    sub_col = (175, 186, 208, 130) if guide_dark else (55, 70, 96, 125)
    # 脚底水平基线 & 头顶等高线（核验 12 种方向角色大小 100% 恒定）
    draw.line([(0, ay), (box_w, ay)], fill=line_col, width=1)
    draw.line([(0, ay - 385), (box_w, ay - 385)], fill=sub_col, width=1)
    draw.line([(ax, 0), (ax, box_h)], fill=sub_col, width=1)

    im = Image.open(ASSETS / fd["asset"]).convert("RGBA")
    ww, wh = round(float(fd["width"])), round(float(fd["height"]))
    if im.size != (ww, wh):
        im = im.resize((ww, wh), Image.Resampling.LANCZOS)
    px, py = round(float(fd["pivotX"])), round(float(fd["pivotY"]))
    canvas.alpha_composite(im, (ax - px, ay - py))
    draw.ellipse([ax - 4, ay - 4, ax + 4, ay + 4], fill=(255, 72, 88, 235))
    return canvas.convert("RGB")


def draw_badge(im: Image.Image, code: str, title: str, subtitle: str, f_code, f_title, f_sub, dark_text: bool = False) -> Image.Image:
    rgba = im.convert("RGBA")
    ov = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    if dark_text:
        d.rounded_rectangle([10, 10, min(rgba.width - 10, 520), 74], radius=8, fill=(255, 255, 255, 218), outline=(145, 120, 215, 220), width=2)
        d.rounded_rectangle([18, 18, 88, 50], radius=6, fill=(108, 52, 205, 245))
        d.text((27, 20), code, fill=(255, 255, 255, 255), font=f_code)
        d.text((98, 16), title, fill=(26, 22, 42, 255), font=f_title)
        d.text((98, 45), subtitle, fill=(78, 72, 108, 255), font=f_sub)
    else:
        d.rounded_rectangle([10, 10, min(rgba.width - 10, 520), 74], radius=8, fill=(12, 14, 24, 212), outline=(136, 96, 235, 210), width=2)
        d.rounded_rectangle([18, 18, 88, 50], radius=6, fill=(126, 62, 232, 245))
        d.text((27, 20), code, fill=(255, 255, 255, 255), font=f_code)
        d.text((98, 16), title, fill=(244, 246, 255, 255), font=f_title)
        d.text((98, 45), subtitle, fill=(182, 194, 224, 255), font=f_sub)
    return Image.alpha_composite(rgba, ov).convert("RGB")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((WORK_DIR / "manifest_12styles.json").read_text(encoding="utf-8"))
    styles = manifest["styles"]

    f_hdr = load_cn_font(28)
    f_hdr_sub = load_cn_font(18)
    f_code = load_cn_font(20)
    f_title = load_cn_font(20)
    f_sub = load_cn_font(14)

    # ── 1. 雨夜实机同帧 12 宫格总览（含顶部 原版 vs 初版重画 基准条） ──
    tw, th = 720, 420
    pad = 12
    cols, rows = 3, 4
    W = pad + cols * (tw + pad)
    header_h = 84
    base_row_h = th + pad + 10
    H = header_h + base_row_h + rows * (th + pad) + pad

    board_rain = Image.new("RGB", (W, H), (11, 13, 20))
    dr = ImageDraw.Draw(board_rain)
    dr.text((20, 14), "《断晓》主角普攻满月斩 (attack_1 f05) · 12 种高帅度刀光特效样板实机横评", fill=(245, 247, 255), font=f_hdr)
    dr.text((20, 50), "100% 纯 AI 角色+特效一体同格生成  |  原帧 1:1 人物等高与外弧跨度锁死  |  Godot 4.7.2 Forward+ 雨夜街原生光影与积水倒影直拍", fill=(176, 190, 222), font=f_hdr_sub)

    # 顶部基准行：左=原版未重画，中=初版重画样板，右=说明卡
    orig_tile = draw_badge(crop_rain_focus(SHOT_DIR / "00_orig_f5.png"), "原版", "原始未重画刀光 (Baseline)", "早期单薄条带 + 噪点，对比基准", f_code, f_title, f_sub)
    pilot_tile = draw_badge(crop_rain_focus(SHOT_DIR / "00_pilot_f5.png"), "初版", "上一轮初版重画样板", "顺滑紫白丝带（受旧参考图束缚，样式偏常规）", f_code, f_title, f_sub)
    info_card = Image.new("RGB", (tw, th), (20, 22, 34))
    di = ImageDraw.Draw(info_card)
    di.rounded_rectangle([8, 8, tw - 8, th - 8], radius=12, outline=(98, 76, 175), width=2)
    f_info_t = load_cn_font(22)
    f_info_b = load_cn_font(16)
    di.text((28, 28), "选型指南（可单选，也可任选 2 种融合！）", fill=(238, 228, 255), font=f_info_t)
    lines = [
        "• 板A (D01-D04)：次元裂口 / 扳机社折雷 / 5:59碎时星轨 / 错位切帧",
        "• 板B (D05-D08)：九日狂墨 / 夜鸦刃羽流 / 不死斩妖炎 / 极简双弦居合",
        "• 板C (D09-D12)：双层音爆环 / 五剑残影扇 / 哥特黑曜棱镜 / 蚀日反转",
        "",
        "★ 全章通吃提示：",
        "   D01 / D05 / D06 / D07 / D11 / D12 自带黑曜/浓墨暗核，",
        "   在第一章暗夜雨街与第三章【浮空白城】纯白亮底下均极致清晰！",
        "★ 组合示例：",
        "   如「D01 纯黑次元裂口 + D06 夜鸦尾羽」或「D05 狂墨 + D02 紫雷」！",
    ]
    yy = 74
    for ln in lines:
        di.text((28, yy), ln, fill=(202, 212, 238), font=f_info_b)
        yy += 33

    y_base = header_h
    for ci, tile in enumerate([orig_tile, pilot_tile, info_card]):
        x0 = pad + ci * (tw + pad)
        board_rain.paste(tile, (x0, y_base))
        dr.rectangle([x0, y_base, x0 + tw - 1, y_base + th - 1], outline=(70, 78, 110), width=2)

    y_grid0 = header_h + base_row_h
    for idx, st in enumerate(styles):
        r, c = divmod(idx, cols)
        x0 = pad + c * (tw + pad)
        y0 = y_grid0 + r * (th + pad)
        shot_fp = SHOT_DIR / f"{st['code'].lower()}_rain.png"
        tile = draw_badge(crop_rain_focus(shot_fp), st["code"], st["title"], st["subtitle"], f_code, f_title, f_sub)
        board_rain.paste(tile, (x0, y0))
        dr.rectangle([x0, y0, x0 + tw - 1, y0 + th - 1], outline=(112, 84, 196), width=2)

    p_rain_all = OUT_DIR / "12种高帅度刀光样板_雨夜实机同帧12宫格总览.png"
    board_rain.save(p_rain_all)

    # ── 2. 板A / 板B / 板C 分组 2×2 超清实机大图（方便在轮播里放大细看） ──
    groups = [
        ("实机特写_板A_D01至D04.png", "板A · 空间裂口与几何爆发系 (D01–D04)", styles[0:4]),
        ("实机特写_板B_D05至D08.png", "板B · 东方狂墨、鸦羽与妖炎系 (D05–D08)", styles[4:8]),
        ("实机特写_板C_D09至D12.png", "板C · 音爆激波、残影剑与蚀日系 (D09–D12)", styles[8:12]),
    ]
    gw, gh = 860, 500
    for g_fname, g_title, g_items in groups:
        gW = pad + 2 * (gw + pad)
        gH = 68 + 2 * (gh + pad) + pad
        gb = Image.new("RGB", (gW, gH), (12, 14, 22))
        gd = ImageDraw.Draw(gb)
        gd.text((18, 16), f"《断晓》实机放大特写 · {g_title}", fill=(244, 247, 255), font=f_hdr)
        for i, st in enumerate(g_items):
            rr, cc = divmod(i, 2)
            xx = pad + cc * (gw + pad)
            yy = 68 + rr * (gh + pad)
            cropped = crop_rain_focus(SHOT_DIR / f"{st['code'].lower()}_rain.png", (310, 235, 1100, 695)).resize((gw, gh), Image.Resampling.LANCZOS)
            badged = draw_badge(cropped, st["code"], st["title"], st["subtitle"], f_code, f_title, f_sub)
            gb.paste(badged, (xx, yy))
            gd.rectangle([xx, yy, xx + gw - 1, yy + gh - 1], outline=(120, 90, 210), width=2)
        gb.save(OUT_DIR / g_fname)

    # ── 3. 纯净暗底 & 第三章纯白亮底 1:1 世界坐标高清细节总览（含 385px 等高线核验） ──
    bw_full, bh_full = 1140, 640
    ax_full, ay_full = 415, 585
    dw, dh = 760, 426  # 等比缩放到 2280 宽 3×4 总览板
    for bg_rgb, is_light, out_name, main_t, sub_t in [
        (
            (18, 20, 30),
            False,
            "12种高帅度刀光样板_纯净暗底12宫格高清细节总览.png",
            "《断晓》12 种高帅度刀光样板 · 纯净暗底 1:1 原画细节与人物等高核验",
            "红点 = 脚底 Pivot 世界锚点  |  上横线 = 385px 角色标准身高线（核验 12 款人物高度 100% 严丝合缝）",
        ),
        (
            (240, 242, 249),
            True,
            "12种高帅度刀光样板_浮空白城亮底可读性检验.png",
            "《断晓》12 种高帅度刀光样板 · 第三章【浮空白城】纯白亮底对比度检验",
            "检验纯白强光舞台下的剪影辨识度：带黑曜/浓墨/暗紫内核的款式在白底与暗夜下均具备顶级视觉冲击力",
        ),
    ]:
        sW = pad + cols * (dw + pad)
        sH = header_h + rows * (dh + pad) + pad
        sb = Image.new("RGB", (sW, sH), (225, 229, 238) if is_light else (11, 13, 20))
        sd = ImageDraw.Draw(sb)
        sd.text((20, 14), main_t, fill=(24, 22, 38) if is_light else (245, 247, 255), font=f_hdr)
        sd.text((20, 50), sub_t, fill=(75, 80, 108) if is_light else (176, 190, 222), font=f_hdr_sub)
        for idx, st in enumerate(styles):
            r, c = divmod(idx, cols)
            x0 = pad + c * (dw + pad)
            y0 = header_h + r * (dh + pad)
            wt = render_world_tile(st, bw_full, bh_full, ax_full, ay_full, bg_rgb, guide_dark=is_light)
            wt_s = wt.resize((dw, dh), Image.Resampling.LANCZOS)
            wt_b = draw_badge(wt_s, st["code"], st["title"], f"{st['subtitle']}  (角色对齐 IoU {st['char_iou']:.2f})", f_code, f_title, f_sub, dark_text=is_light)
            sb.paste(wt_b, (x0, y0))
            sd.rectangle([x0, y0, x0 + dw - 1, y0 + dh - 1], outline=(145, 130, 198) if is_light else (96, 76, 175), width=2)
        sb.save(OUT_DIR / out_name)

    # 同步复制到 Artifact 目录供直接内嵌展示
    for fn in [
        "12种高帅度刀光样板_雨夜实机同帧12宫格总览.png",
        "实机特写_板A_D01至D04.png",
        "实机特写_板B_D05至D08.png",
        "实机特写_板C_D09至D12.png",
        "12种高帅度刀光样板_纯净暗底12宫格高清细节总览.png",
        "12种高帅度刀光样板_浮空白城亮底可读性检验.png",
    ]:
        shutil.copy2(OUT_DIR / fn, BRAIN_DIR / fn)
        print("Copied artifact image ->", BRAIN_DIR / fn)


if __name__ == "__main__":
    main()
