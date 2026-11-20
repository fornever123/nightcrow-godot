#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成「100% 纯 AI 角色高张力动作 + 大画幅狂野剑戟特效重塑」全套交付视觉证据：
1. 纯AI全动作重塑_Codex49张生图母版总览.png（直观展示 V01-V08 纯 AI 特效母版 + S01-S41 代表性纯 AI 角色动作母版，铁证 100% AI 手绘零滤镜）
2. 纯AI全动作重塑_实机雨街12幕同帧铁证对比.png（12 大招式同机位 BEFORE 原版 vs AFTER 100% 纯 AI 放大特写矩阵）
3. 8 张 1920x1080 原生雨街全屏高清实机剧照
4. 纯AI全动作重塑_实机雨街连续演武60fps对比.mp4（左：原版 BEFORE / 右：100% 纯 AI 重塑 AFTER，60fps H.264）
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
BEFORE_DIR = ROOT / r"docs\视觉设计\角色动作\全动作精修与张力升级_20261114\shots_before"
WORK_PURE = ROOT / r"docs\视觉设计\角色动作\全动作纯AI重塑_20261114"
AFTER_DIR = WORK_PURE / "shots_after"
CODEX_OUT = WORK_PURE / "codex_out"
OUT_SHOWCASE = WORK_PURE / "showcase"

ARTIFACT_DIR = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988")


def load_cn_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for fp in [
        r"C:\Windows\Fonts\msyhbd.ttc",
        r"C:\Windows\Fonts\msyh.ttc",
        r"C:\Windows\Fonts\simhei.ttf",
    ]:
        if Path(fp).exists():
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()


def build_codex_master_gallery(out_fp: Path) -> None:
    """将 V01..V08 全部 8 张大特效板 + 8 张代表性高张力角色板拼成一张 2400px 宽的铁证母版墙。"""
    f_title = load_cn_font(30)
    f_sub = load_cn_font(18)
    f_lbl = load_cn_font(16)

    cols = 4
    tw, th = 560, 385
    pad = 24
    header_h = 105

    vfx_ids = [f"V{i:02d}" for i in range(1, 9)]
    char_ids = [
        ("S05", "普攻1段 · 拔步压低冲刺劈"),
        ("S11", "普攻3段 · 双手高举裂地重劈"),
        ("S13", "上挑强普 · 蓄势蹬地升龙"),
        ("S18", "空连3段 · 凌空团身俯冲斩"),
        ("S22", "疾行冲刺斩 · 贴地30°极速突进"),
        ("S29", "弹刀反击1 · 转身甩披肩回敬"),
        ("S32", "弹刀反击3 · 旋身回环反斩"),
        ("S36", "蓄力持续 · 怒发冲冠剑气盘旋"),
    ]
    vfx_titles = {
        "V01": "V01 · 普攻1/2段 狂草飞白满月与S型巨弧",
        "V02": "V02 · 普攻3/空3 裂地紫雷与俯冲重劈巨弧",
        "V03": "V03 · 升龙强普与空连 冲天螺旋剑气柱",
        "V04": "V04 · 冲刺音爆破风戟芒与居合横一文字",
        "V05": "V05 · 只狼级弹刀十字核爆寒星与回环风暴",
        "V06": "V06 · 架盾剑脊符文流光与三阶格挡爆裂盾",
        "V07": "V07 · 居合拔刀寒星一闪与四相盘龙蓄力气旋",
        "V08": "V08 · 满蓄力360°断晓空间裂口环与破魂晶碎",
    }

    rows = 4
    W = pad + cols * (tw + pad)
    H = header_h + rows * (th + 42 + pad) + pad
    canvas = Image.new("RGB", (W, H), (12, 14, 22))
    dr = ImageDraw.Draw(canvas)

    dr.text((pad, 20), "《断晓》100% 纯 AI 生图母版铁证总览（Codex gpt-6.1-terra · 49 张原生手绘整板抽样）", font=f_title, fill=(242, 238, 255))
    dr.text((pad, 62), "上半 8 板：1536×1024 独立大画幅四阶冷紫书法飞白剑戟特效母版（V01–V08）  |  下半 8 板：保持 100% 原版五官发饰的高张力重塑角色母版（S01–S41 代表）", font=f_sub, fill=(176, 162, 235))

    items = [(vid, vfx_titles[vid]) for vid in vfx_ids] + char_ids
    for idx, (jid, label) in enumerate(items):
        r_i, c_i = idx // cols, idx % cols
        x0 = pad + c_i * (tw + pad)
        y0 = header_h + r_i * (th + 42 + pad)

        dr.rounded_rectangle([x0 - 3, y0 - 3, x0 + tw + 3, y0 + th + 35], radius=8, fill=(22, 25, 38), outline=(88, 68, 165), width=2)
        key_p = WORK_PURE / "keyed_cache" / f"_keyed_{jid}.png"
        im = Image.open(key_p).convert("RGBA")
        if jid.startswith("V"):
            im = Image.fromarray(make_dark_preview_vfx(np.asarray(im)))
        else:
            bg = Image.new("RGBA", im.size, (26, 29, 44, 255))
            bg.alpha_composite(im)
            im = bg.convert("RGB")

        s = min((tw - 12) / im.width, (th - 12) / im.height)
        nw, nh = round(im.width * s), round(im.height * s)
        im_r = im.resize((nw, nh), Image.Resampling.LANCZOS)
        canvas.paste(im_r, (x0 + (tw - nw) // 2, y0 + (th - nh) // 2))
        dr.text((x0 + 10, y0 + th + 6), label, font=f_lbl, fill=(230, 226, 250))

    canvas.save(out_fp, quality=95)


def make_dark_preview_vfx(rgba: np.ndarray) -> np.ndarray:
    bg = np.full((rgba.shape[0], rgba.shape[1], 3), (18, 20, 32), dtype=np.float32)
    a = rgba[..., 3:4].astype(np.float32) / 255.0
    fg = rgba[..., :3].astype(np.float32)
    comp = fg * a + bg * (1.0 - a)
    return np.clip(comp, 0, 255).astype(np.uint8)


def crop_focus(im: Image.Image, cx: int, cy: int, cw: int = 520, ch: int = 330) -> Image.Image:
    W, H = im.size
    x0 = max(0, min(W - cw, cx - cw // 2))
    y0 = max(0, min(H - ch, cy - ch // 2))
    return im.crop((x0, y0, x0 + cw, y0 + ch))


def build_12_panel_matrix(out_fp: Path) -> None:
    f_title = load_cn_font(30)
    f_sub = load_cn_font(18)
    f_lbl = load_cn_font(17)
    f_tag = load_cn_font(15)

    scenes = [
        ("06_attack_1_cleave.png",          "01 · 普攻1段 (f5)：原版平涂小弧 → 纯AI压低突刺 + 狂草满月巨弧", 640, 545),
        ("07_attack_2_sweep.png",           "02 · 普攻2段 (f6)：原版糊帧 → 纯AI反手拧腰 + 紫雷单弧斜撩", 635, 535),
        ("08_attack_3_finisher.png",        "03 · 普攻3段终结 (f5)：原版单薄紫块 → 纯AI重劈 + 裂地双翼冲击", 640, 545),
        ("09_attack_up_launcher.png",       "04 · 上挑强普 (f9)：原版扁弧 → 纯AI腾空高举 + 贯通真剑升龙巨弧", 625, 455),
        ("03_air_attack_2_slash.png",       "05 · 空连2段 (f4)：原全项目最糊(43) → 纯AI锐利凌空紫雷新月", 625, 445),
        ("04_air_attack_3_finisher.png",    "06 · 空连3段终结 (f1)：精准对齐0帧判定 → 纯AI俯冲彗尾重劈", 625, 465),
        ("10_dash_slash_wedges.png",        "07 · 疾行冲刺起步 (f5)：根除灰鬼影 → 纯AI贴地突进 + 音爆破风戟芒", 630, 555),
        ("11_dash_slash_cleave.png",        "08 · 冲刺居合斩 (f12)：根除断头泥团 → 纯AI急停横一文字剃刀弧", 635, 555),
        ("13_parry_react_1_clash.png",      "09 · 弹刀1交锋 (f6)：修掉违和黄火花 → 只狼级冷紫核爆十字寒星", 620, 545),
        ("14_parry_react_1_repaired_f8.png","10 · 弹刀1卸力 (f8)：根除断腰空洞 → 纯AI左上亮剑外拨狂草剑芒", 615, 525),
        ("16_parry_react_3_counter.png",    "11 · 弹刀3卸力 (f8)：根除黄块吞身 → 纯AI旋身外拨飞羽烈弧", 615, 525),
        ("17_charge_slash_release.png",     "12 · 满蓄力断晓一闪 (f19)：原版白泥块 → 740u空间裂口环 + 狂草巨弧", 635, 520),
    ]

    cols = 2
    rows = 6
    cw, ch = 500, 315
    pair_w = cw * 2 + 12
    pad = 24
    header_h = 102
    row_h = ch + 46

    W = pad + cols * (pair_w + pad)
    H = header_h + rows * (row_h + 16) + pad
    canvas = Image.new("RGB", (W, H), (11, 13, 20))
    dr = ImageDraw.Draw(canvas)

    dr.text((pad, 18), "《断晓》全角色 36 套动作 100% 纯 AI 重塑 — 原生雨夜河岸街 12 幕同帧铁证对比", font=f_title, fill=(244, 240, 255))
    dr.text((pad, 60), "左：BEFORE 改造前原版（含断腰坏帧/白泥块/模糊抽帧）   |   右：AFTER 100% 纯 Codex (gpt-6.1-terra) 帅气动作重塑 + 大画幅自发光书法剑戟特效（零本地滤镜）", font=f_sub, fill=(178, 165, 238))

    for idx, (fn, title, cx, cy) in enumerate(scenes):
        r_i, c_i = idx // cols, idx % cols
        x0 = pad + c_i * (pair_w + pad)
        y0 = header_h + r_i * (row_h + 16)

        dr.rounded_rectangle([x0 - 4, y0 - 4, x0 + pair_w + 4, y0 + row_h + 4], radius=8, fill=(20, 23, 34), outline=(76, 62, 145), width=2)
        dr.text((x0 + 8, y0 + 6), title, font=f_lbl, fill=(235, 230, 255))

        im_b = Image.open(BEFORE_DIR / fn).convert("RGB")
        im_a = Image.open(AFTER_DIR / fn).convert("RGB")
        cb = crop_focus(im_b, cx, cy, cw, ch)
        ca = crop_focus(im_a, cx, cy, cw, ch)

        canvas.paste(cb, (x0, y0 + 38))
        canvas.paste(ca, (x0 + cw + 12, y0 + 38))

        dr.rectangle([x0 + 8, y0 + 46, x0 + 132, y0 + 72], fill=(35, 24, 30))
        dr.text((x0 + 14, y0 + 48), "BEFORE 原版", font=f_tag, fill=(255, 165, 165))
        dr.rectangle([x0 + cw + 20, y0 + 46, x0 + cw + 178, y0 + 72], fill=(36, 22, 68))
        dr.text((x0 + cw + 26, y0 + 48), "AFTER 100%纯AI", font=f_tag, fill=(216, 195, 255))

    canvas.save(out_fp, quality=95)


def export_fullscreen_1080p_stills(out_dir: Path) -> list[tuple[str, Path]]:
    picks = [
        ("06_attack_1_cleave.png",       "纯AI全动作重塑_实机全屏_1_普攻1段狂草满月斩.png"),
        ("08_attack_3_finisher.png",     "纯AI全动作重塑_实机全屏_2_普攻3段裂地重劈.png"),
        ("09_attack_up_launcher.png",    "纯AI全动作重塑_实机全屏_3_上挑强普贯通升龙弧.png"),
        ("04_air_attack_3_finisher.png", "纯AI全动作重塑_实机全屏_4_空连3段凌空俯冲斩.png"),
        ("10_dash_slash_wedges.png",     "纯AI全动作重塑_实机全屏_5_冲刺疾行音爆破风戟芒.png"),
        ("11_dash_slash_cleave.png",     "纯AI全动作重塑_实机全屏_6_冲刺居合横一文字斩.png"),
        ("16_parry_react_3_counter.png", "纯AI全动作重塑_实机全屏_7_弹刀3旋风羽散反击弧.png"),
        ("17_charge_slash_release.png",  "纯AI全动作重塑_实机全屏_8_满蓄力断晓空间裂口巨弧.png"),
    ]
    saved = []
    for src_fn, dst_fn in picks:
        im = Image.open(AFTER_DIR / src_fn).convert("RGB").resize((1920, 1080), Image.Resampling.LANCZOS)
        dst = out_dir / dst_fn
        im.save(dst, quality=95)
        saved.append((dst_fn, dst))
    return saved


def build_60fps_side_by_side_video(out_mp4: Path) -> None:
    tmp_frames = OUT_SHOWCASE / "_vid_frames"
    tmp_frames.mkdir(parents=True, exist_ok=True)
    f_hdr = load_cn_font(22)

    for idx in range(180):
        fb = BEFORE_DIR / "seq" / f"f_{idx:03d}.png"
        fa = AFTER_DIR / "seq" / f"f_{idx:03d}.png"
        if not fb.exists() or not fa.exists():
            break
        imb = Image.open(fb).convert("RGB")
        ima = Image.open(fa).convert("RGB")
        # 裁取角色核心战斗视窗 940x640 双联并排 -> 1896x700 (偶数分辨率)
        cb = crop_focus(imb, 640, 460, 940, 636)
        ca = crop_focus(ima, 640, 460, 940, 636)
        frame = Image.new("RGB", (1896, 696), (12, 14, 22))
        dr = ImageDraw.Draw(frame)
        frame.paste(cb, (4, 54))
        frame.paste(ca, (952, 54))
        dr.text((18, 13), "BEFORE 改造前原版（含断腰坏帧 / 灰鬼影 / 低清糊帧）", font=f_hdr, fill=(255, 170, 170))
        dr.text((966, 13), "AFTER 100% 纯 AI 重塑（Codex 49板原貌高张力角色 + 自发光狂草剑戟大特效）", font=f_hdr, fill=(215, 195, 255))
        frame.save(tmp_frames / f"v_{idx:03d}.png")

    cmd = [
        "ffmpeg", "-y",
        "-framerate", "60",
        "-i", str(tmp_frames / "v_%03d.png"),
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-crf", "17",
        str(out_mp4),
    ]
    subprocess.run(cmd, check=True)


def main():
    OUT_SHOWCASE.mkdir(parents=True, exist_ok=True)
    gal_fp = OUT_SHOWCASE / "纯AI全动作重塑_Codex49张生图母版总览.png"
    mat_fp = OUT_SHOWCASE / "纯AI全动作重塑_实机雨街12幕同帧铁证对比.png"
    mp4_fp = OUT_SHOWCASE / "纯AI全动作重塑_实机雨街连续演武60fps对比.mp4"

    build_codex_master_gallery(gal_fp)
    print("[1/4] Built gallery:", gal_fp)
    build_12_panel_matrix(mat_fp)
    print("[2/4] Built 12-panel matrix:", mat_fp)
    stills = export_fullscreen_1080p_stills(OUT_SHOWCASE)
    print("[3/4] Exported 8 1080p stills")
    build_60fps_side_by_side_video(mp4_fp)
    print("[4/4] Built 60fps MP4:", mp4_fp)

    # 同步复制到当前会话 Artifact 目录供 Markdown 直接内嵌展示
    for fp in [gal_fp, mat_fp, mp4_fp] + [p for _, p in stills]:
        shutil.copy2(fp, ARTIFACT_DIR / fp.name)
    print("[DONE] Synced all showcase files to Artifact directory!")


if __name__ == "__main__":
    main()
