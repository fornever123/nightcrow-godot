#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
组装「真·刀光 R1–R4（1.0x 原长直剑 + 同心挥砍半透明残影）」雨夜街实机 2×2 超清大图、
1:1 原画半透明细节板、以及「之前被否的假月亮贴纸 vs 真·刀光」直观对比板。
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Tuple

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
WORK_DIR = ROOT / r"docs\视觉设计\角色动作\真刀光样板_20261115"
SHOT_DIR = ROOT / ".runtime" / "true_slash_shots"
PREV_SHOT_DIR = ROOT / ".runtime" / "vfx_12styles_shots"
OUT_DIR = WORK_DIR / "验收画廊"
BRAIN_DIR = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988")


def load_cn_font(size: int = 20) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for fp in [r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if Path(fp).exists():
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()


def draw_badge(
    im: Image.Image,
    code: str,
    title: str,
    subtitle: str,
    f_code,
    f_title,
    f_sub,
    accent: Tuple[int, int, int] = (128, 62, 236),
) -> Image.Image:
    rgba = im.convert("RGBA")
    ov = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    d.rounded_rectangle([12, 12, min(rgba.width - 12, 680), 78], radius=8, fill=(10, 12, 22, 214), outline=(*accent, 215), width=2)
    d.rounded_rectangle([20, 20, 86, 54], radius=6, fill=(*accent, 245))
    d.text((30, 22), code, fill=(255, 255, 255, 255), font=f_code)
    d.text((98, 18), title, fill=(245, 247, 255, 255), font=f_title)
    d.text((98, 48), subtitle, fill=(182, 194, 224, 255), font=f_sub)
    return Image.alpha_composite(rgba, ov).convert("RGB")


def render_world_tile(fd: dict, box_w: int, box_h: int, ax: int, ay: int, bg_rgb: Tuple[int, int, int]) -> Image.Image:
    canvas = Image.new("RGBA", (box_w, box_h), (*bg_rgb, 255))
    draw = ImageDraw.Draw(canvas)
    draw.line([(0, ay), (box_w, ay)], fill=(65, 82, 114, 165), width=1)
    draw.line([(0, ay - 385), (box_w, ay - 385)], fill=(52, 66, 92, 120), width=1)
    draw.line([(ax, 0), (ax, box_h)], fill=(52, 66, 92, 120), width=1)

    im = Image.open(ASSETS / fd["asset"]).convert("RGBA")
    ww, wh = round(float(fd["width"])), round(float(fd["height"]))
    if im.size != (ww, wh):
        im = im.resize((ww, wh), Image.Resampling.LANCZOS)
    px, py = round(float(fd["pivotX"])), round(float(fd["pivotY"]))
    canvas.alpha_composite(im, (ax - px, ay - py))
    draw.ellipse([ax - 4, ay - 4, ax + 4, ay + 4], fill=(255, 72, 88, 235))
    return canvas.convert("RGB")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((WORK_DIR / "manifest_true_slash.json").read_text(encoding="utf-8"))
    v2_styles = manifest["v2_styles"]

    f_hdr = load_cn_font(28)
    f_hdr_sub = load_cn_font(17)
    f_code = load_cn_font(19)
    f_title = load_cn_font(20)
    f_sub = load_cn_font(14)

    pad = 14
    gw, gh = 880, 510
    W = pad + 2 * (gw + pad)
    H = 84 + 2 * (gh + pad) + pad

    # 1. 核心主看版：R1-R4 雨夜街 Forward+ 实机四宫格
    b_rain = Image.new("RGB", (W, H), (11, 13, 20))
    dr = ImageDraw.Draw(b_rain)
    dr.text((20, 14), "《断晓》真·刀光样板 (R1–R4) · 雨夜街 Forward+ 实机同帧直拍", fill=(246, 248, 255), font=f_hdr)
    dr.text(
        (20, 50),
        "1.0x 原长黑银直剑锁死 + 100% 同心圆弧破空挥砍残影 + 暗棚无损连续半透明解混（石墙砖纹透过紫光尾纱清晰可见！）",
        fill=(176, 192, 224),
        font=f_hdr_sub,
    )

    for i, st in enumerate(v2_styles):
        rr, cc = divmod(i, 2)
        xx = pad + cc * (gw + pad)
        yy = 84 + rr * (gh + pad)
        shot = Image.open(SHOT_DIR / f"{st['code'].lower()}_rain.png").convert("RGB")
        cropped = shot.crop((310, 235, 1100, 695)).resize((gw, gh), Image.Resampling.LANCZOS)
        badged = draw_badge(cropped, st["code"], st["title"], st["subtitle"], f_code, f_title, f_sub)
        b_rain.paste(badged, (xx, yy))
        dr.rectangle([xx, yy, xx + gw - 1, yy + gh - 1], outline=(120, 90, 215), width=2)

    fn_rain = "真刀光样板_修正版R1至R4_雨夜实机四宫格.png"
    b_rain.save(OUT_DIR / fn_rain)
    shutil.copy2(OUT_DIR / fn_rain, BRAIN_DIR / fn_rain)

    # 2. 纯净暗底 1:1 世界坐标细节与 385px 身高标尺核验板
    b_dark = Image.new("RGB", (W, H), (11, 13, 20))
    dd = ImageDraw.Draw(b_dark)
    dd.text((20, 14), "《断晓》真·刀光样板 (R1–R4) · 1:1 原画半透明光纱细节与原长直剑核验", fill=(246, 248, 255), font=f_hdr)
    dd.text(
        (20, 50),
        "红点 = 脚底 Pivot 锚点  |  上横线 = 385px 标准身高线  |  上排 R1/R2 立劈扇面残影，下排 R3/R4 满弓斜横斩",
        fill=(176, 192, 224),
        font=f_hdr_sub,
    )

    for i, st in enumerate(v2_styles):
        rr, cc = divmod(i, 2)
        xx = pad + cc * (gw + pad)
        yy = 84 + rr * (gh + pad)
        wt = render_world_tile(st, 1140, 660, 415, 595, (18, 20, 30)).resize((gw, gh), Image.Resampling.LANCZOS)
        badged = draw_badge(wt, st["code"], st["title"], st["subtitle"], f_code, f_title, f_sub)
        b_dark.paste(badged, (xx, yy))
        dd.rectangle([xx, yy, xx + gw - 1, yy + gh - 1], outline=(100, 80, 185), width=2)

    fn_dark = "真刀光样板_修正版R1至R4_暗底原画细节四宫格.png"
    b_dark.save(OUT_DIR / fn_dark)
    shutil.copy2(OUT_DIR / fn_dark, BRAIN_DIR / fn_dark)

    # 3. 直观问题根治对照条（左：上一轮被否的绿幕实心弯月亮贴纸 D11 / 中：R1 同心流丝斩 / 右：R2 双阶疾风斩）
    d11_fp = PREV_SHOT_DIR / "d11_rain.png"
    if d11_fp.exists():
        cw3, ch3 = 600, 365
        W3 = pad + 3 * (cw3 + pad)
        H3 = 80 + ch3 + pad
        b_cmp = Image.new("RGB", (W3, H3), (11, 13, 20))
        dc = ImageDraw.Draw(b_cmp)
        dc.text((20, 14), "根因修正前后实机一眼对照：为什么上一轮不像刀光 vs 现在的真·挥砍刀光", fill=(246, 248, 255), font=load_cn_font(25))
        dc.text((20, 48), "告别『短剑戳实心弯月亮贴纸』：恢复 1.0x 原长直剑 + 同心挥砍残影 + 真半透明紫光渐变尾纱", fill=(176, 192, 224), font=load_cn_font(16))

        cmp_items = [
            (d11_fp, "旧版", "上一轮被否（绿幕实心月亮贴纸）", "短剑与弯月亮脱节、实心不透底、塞窗花杂物", (185, 52, 68)),
            (SHOT_DIR / "r2_rain.png", "R2", "立劈扇面·双阶高打击疾风斩", "1.0x原长直剑 + 饱满白锋 + 半透明紫纱尖尾", (128, 62, 236)),
            (SHOT_DIR / "r3_rain.png", "R3", "满弓前冲·月华流光破空斩", "1.0x原长直剑 + 圆润前冲剑气肚 + 蝉翼紫纱", (46, 152, 108)),
        ]
        for idx, (fp, cd, tt, sb, acc) in enumerate(cmp_items):
            xx = pad + idx * (cw3 + pad)
            yy = 80
            sh = Image.open(fp).convert("RGB").crop((310, 235, 1100, 695)).resize((cw3, ch3), Image.Resampling.LANCZOS)
            bd = draw_badge(sh, cd, tt, sb, load_cn_font(17), load_cn_font(17), load_cn_font(12), accent=acc)
            b_cmp.paste(bd, (xx, yy))
            dc.rectangle([xx, yy, xx + cw3 - 1, yy + ch3 - 1], outline=acc, width=2)

        fn_cmp = "真刀光样板_根因修正前后实机三联对照.png"
        b_cmp.save(OUT_DIR / fn_cmp)
        shutil.copy2(OUT_DIR / fn_cmp, BRAIN_DIR / fn_cmp)

    print("Saved v2 showcase ->", OUT_DIR)


if __name__ == "__main__":
    main()
