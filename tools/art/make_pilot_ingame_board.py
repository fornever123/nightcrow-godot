#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
合成「原版实机 vs 1:1 角色+特效一体重画实机」原生 Forward+ 雨街同帧对比图板与 60fps H.264 对比视频。
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OLD_DIR = ROOT / ".runtime" / "pilot_shots_old"
NEW_DIR = ROOT / ".runtime" / "pilot_shots_new"
OUT_DIR = ROOT / r"docs\视觉设计\角色动作\原帧一体重画_20261115\验收对比"


def load_cn_font(size: int = 18) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for fp in [r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if Path(fp).exists():
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()

SHOTS = [
    ("01_attack1_f4_windup.png", "普攻1段 f04 (起势直剑+钩芒)"),
    ("02_attack1_f5_slash_peak.png", "普攻1段 f05 (横向满月爆发)"),
    ("03_attack1_f6_slash_split.png", "普攻1段 f06 (狂草飞白满月)"),
    ("04_attack1_f7_slash_tail.png", "普攻1段 f07 (下半弯月消散)"),
    ("05_attack1_f10_follow.png", "普攻1段 f10 (低姿收剑定势)"),
    ("06_parry1_f2_slash.png", "弹刀反击1 f02 (11-06 反击刀光)"),
    ("07_parry1_f6_clash.png", "弹刀反击1 f06 (迎刃十字星闪)"),
    ("08_parry1_f8_repaired.png", "弹刀反击1 f08 (修复半身残缺坏帧)"),
    ("09_parry1_f9_repaired_arc.png", "弹刀反击1 f09 (修复断腰+甩剑流光)"),
    ("10_parry1_f12_pose.png", "弹刀反击1 f12 (直剑亮剑定势)"),
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    # 角色特写裁剪区域 (1280x720 中围绕角色与横向大刀光: x=330..1050, y=220..650 -> 720x430)
    crop_box = (330, 220, 1050, 650)
    cw, ch = crop_box[2] - crop_box[0], crop_box[3] - crop_box[1]

    f_hdr = load_cn_font(20)
    f_lbl = load_cn_font(16)
    rows = len(SHOTS)
    hdr = 48
    row_h = ch + 34
    board = Image.new("RGB", (cw * 2 + 16, hdr + rows * row_h), (14, 16, 24))
    d = ImageDraw.Draw(board)
    d.text((16, 12), "Godot 4.7.2 Forward+ 雨夜实机同帧 1:1 对比  (左: 原版序列帧  |  右: 1:1 角色+高颜值特效一体重画)", fill=(238, 242, 255), font=f_hdr)

    for idx, (fn, label) in enumerate(SHOTS):
        im_o = Image.open(OLD_DIR / fn).convert("RGB").crop(crop_box)
        im_n = Image.open(NEW_DIR / fn).convert("RGB").crop(crop_box)
        y0 = hdr + idx * row_h
        d.text((12, y0 + 4), f"【原来】 {label}", fill=(180, 192, 215), font=f_lbl)
        d.text((cw + 20, y0 + 4), f"【新版 1:1 一体重画】 {label}", fill=(228, 198, 255), font=f_lbl)
        board.paste(im_o, (4, y0 + 28))
        board.paste(im_n, (cw + 12, y0 + 28))

    board.save(OUT_DIR / "实机同帧对比_10幕特写长卷.png")

    # 保存几张完整 1280x720 上下或左右实机大图
    for fn, out_name in [
        ("02_attack1_f5_slash_peak.png", "实机全屏_普攻1段f05_满月爆发.png"),
        ("03_attack1_f6_slash_split.png", "实机全屏_普攻1段f06_飞白满月.png"),
        ("08_parry1_f8_repaired.png", "实机全屏_弹刀1f08_坏帧补全.png"),
        ("09_parry1_f9_repaired_arc.png", "实机全屏_弹刀1f09_断腰补全甩剑弧.png"),
    ]:
        shutil.copy2(NEW_DIR / fn, OUT_DIR / out_name)

    # 合成左右同屏 60fps MP4 视频（原速 + 0.35x 慢放两段连播）
    seq_pair_dir = ROOT / ".runtime" / "pilot_seq_pairs"
    seq_pair_dir.mkdir(parents=True, exist_ok=True)
    old_seq = sorted((OLD_DIR / "seq").glob("f_*.png"))
    new_seq = sorted((NEW_DIR / "seq").glob("f_*.png"))
    n_seq = min(len(old_seq), len(new_seq))
    out_idx = 0
    # 第一遍：60fps 真实原速；第二遍：每帧重复 3 次 = 0.33x 逐帧慢放看清每一帧刀光与脚底锚点
    for pass_i, repeat_k in [(1, 1), (2, 3)]:
        tag = "1.0x REAL SPEED" if repeat_k == 1 else "0.33x SLOW-MO"
        for i in range(n_seq):
            lo = Image.open(old_seq[i]).convert("RGB").crop((310, 180, 1070, 680))
            rn = Image.open(new_seq[i]).convert("RGB").crop((310, 180, 1070, 680))
            pw, ph = lo.size
            frame_im = Image.new("RGB", (pw * 2 + 8, ph + 36), (14, 16, 24))
            fd = ImageDraw.Draw(frame_im)
            fd.text((12, 8), f"ORIGINAL  ({tag} · tick {i:02d})", fill=(185, 195, 215))
            fd.text((pw + 20, 8), f"1:1 CO-GENERATED AI REDRAW  ({tag} · tick {i:02d})", fill=(230, 198, 255))
            frame_im.paste(lo, (0, 36))
            frame_im.paste(rn, (pw + 8, 36))
            for _ in range(repeat_k):
                frame_im.save(seq_pair_dir / f"p_{out_idx:04d}.png")
                out_idx += 1

    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg and out_idx > 0:
        mp4_out = OUT_DIR / "实机雨街_原速与慢放同屏对比_60fps.mp4"
        subprocess.run([
            ffmpeg, "-y", "-framerate", "60",
            "-i", str(seq_pair_dir / "p_%04d.png"),
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16",
            str(mp4_out),
        ], check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        print("Saved MP4:", mp4_out)


if __name__ == "__main__":
    main()
