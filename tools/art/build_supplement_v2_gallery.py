#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
组装即梦 v2 主角动作补齐与角色一致性验收画廊：
1. 改前vs改后_雨夜实机六组同机位并排对比.png
2. 角色一致性实机同框总表_旧动作vs新11套动作.png
3. 新旧动作一镜到底_雨夜实机60fps演武.mp4 (60fps H.264)
并同步复制到当前会话 Artifact 目录供报告直接内嵌。
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
WORK_DIR = ROOT / r"docs\视觉设计\角色动作\动作补齐_即梦v2_20261117"
SHOT_DIR = WORK_DIR / "实机验收"
ART_DIR = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988")


def crop_focus_with_hud_inset(full_im: Image.Image, cx_ratio: float = 0.50, cy_ratio: float = 0.69, crop_w: int = 620, crop_h: int = 360) -> Image.Image:
    """截取角色实机焦点区域（保留雨夜湿石板倒影与打光），并在左上角附带真实 HUD 缩略角标证明原生实机。"""
    W, H = full_im.size
    cx = round(W * cx_ratio)
    cy = round(H * cy_ratio)
    x0 = max(0, min(W - crop_w, cx - crop_w // 2))
    y0 = max(0, min(H - crop_h, cy - crop_h // 2))
    sub = full_im.crop((x0, y0, x0 + crop_w, y0 + crop_h)).copy()
    # 附带左上角真实 G3 钟楼指针 HUD 实拍缩略窗
    hud_crop = full_im.crop((8, 8, 344, 180)).resize((152, 78), Image.Resampling.LANCZOS)
    sub.paste(hud_crop, (8, 36))
    dr = ImageDraw.Draw(sub)
    dr.rectangle([8, 36, 8 + 152, 36 + 78], outline=(130, 118, 175), width=1)
    return sub


def build_before_after_board() -> Path:
    f_h = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 26)
    f_s = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 17)
    f_b = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 14)

    pairs = [
        (
            "01 挨轻刀受击 (LAUNCHED 轻硬直)",
            "before_01_hurt_light.png",
            "【改前】无受击帧，挨刀直接播普通起跳 jump",
            "01_after_hurt_light.png",
            "【改后】专属 hurt_light 压身横剑咬牙微退",
        ),
        (
            "02 挨重刀滑退 (LAUNCHED 强击退)",
            "before_02_hurt_heavy.png",
            "【改前】无强受击帧，后退时播空中下落/倒跑",
            "02_after_hurt_heavy.png",
            "【改后】专属 hurt_heavy 弓背横剑双靴犁地滑退",
        ),
        (
            "03 重击倒地与起身 (State.DOWN)",
            "before_04_down_squished_idle.png",
            "【改前】无倒地帧，把站立 idle 压扁成 1.25×0.72 纸片",
            "04_after_down.png",
            "【改后】真实平躺 down (1:1 比例) 接单膝拄剑起身 getup",
        ),
        (
            "04 K 键远程剑气 (ranged_1)",
            "before_06_ranged_reused_attack1.png",
            "【改前】直接复用 J 键普攻1斜劈，与水平剑气波脱节",
            "06b_after_ranged_slash.png",
            "【改后】专属 ranged_cast 前空翻接饱满电光紫新月斩",
        ),
        (
            "05 空中 S+J 急坠下劈 (air_plunge)",
            "before_07_plunge_reused_air1.png",
            "【改前】复用普通空中斜挥，触地无砸地重量感",
            "07b_after_plunge_slam.png",
            "【改后】专属 air_plunge_slam 双手举剑急坠+满月竖劈插剑",
        ),
        (
            "06 奔跑松键急停 (run -> idle 过渡)",
            "before_10_run_hardcut_idle.png",
            "【改前】松键瞬间无惯性缓冲，直接硬切回死板待机",
            "10_after_run_stop.png",
            "【改后】专属 run_stop 前脚蹬地扬尘刹步回待机 (0延迟打断)",
        ),
    ]

    cw, ch = 460, 270
    pair_w = cw * 2 + 12
    cols, rows = 2, 3
    pad, top_h = 18, 76
    W = cols * pair_w + (cols + 1) * pad
    H = top_h + rows * (ch + 44) + (rows + 1) * pad

    board = Image.new("RGB", (W, H), (14, 16, 24))
    dr = ImageDraw.Draw(board)
    dr.text(
        (pad, 14),
        "《断晓》即梦 Seedance 2.0 (v2) 主角动作补齐 · 雨夜实机改前 vs 改后同机位对比（Forward+ 含 HUD）",
        font=f_h,
        fill=(242, 238, 255),
    )
    dr.text(
        (pad, 48),
        "全部在同一 scenes/rain_street.tscn 原生窗口同坐标直拍（严禁 --headless，Panku 隐藏），直观对比旧版占位假动作 vs 新版专属动作",
        font=f_b,
        fill=(182, 188, 214),
    )

    for idx, (group_title, bf_fn, bf_cap, af_fn, af_cap) in enumerate(pairs):
        r, c = divmod(idx, cols)
        gx = pad + c * (pair_w + pad)
        gy = top_h + pad + r * (ch + 44 + pad)
        dr.text((gx + 4, gy), group_title, font=f_s, fill=(216, 196, 255))

        for side_i, (fn, cap, border_col, tag_bg) in enumerate([
            (bf_fn, bf_cap, (150, 74, 84), (92, 32, 42)),
            (af_fn, af_cap, (118, 92, 235), (48, 34, 108)),
        ]):
            sx = gx + side_i * (cw + 12)
            sy = gy + 30
            im_full = Image.open(SHOT_DIR / fn).convert("RGB")
            foc = crop_focus_with_hud_inset(im_full, crop_w=620, crop_h=364).resize((cw, ch), Image.Resampling.LANCZOS)
            board.paste(foc, (sx, sy))
            dr.rectangle([sx, sy, sx + cw - 1, sy + ch - 1], outline=border_col, width=2)
            dr.rectangle([sx + 1, sy + 1, sx + cw - 2, sy + 28], fill=tag_bg)
            dr.text((sx + 8, sy + 5), cap, font=f_b, fill=(246, 244, 255))

    out_p = SHOT_DIR / "改前vs改后_雨夜实机六组同机位并排对比.png"
    board.save(out_p, quality=95)
    return out_p


def build_consistency_12grid() -> Path:
    f_h = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 26)
    f_t = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 16)
    f_b = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 14)

    items = [
        ("00_old_idle.png", "【旧动作基准】待机 idle (pose_002)", (68, 138, 118)),
        ("00_old_attack1.png", "【旧动作基准】普攻1段 attack_1 (R3)", (68, 138, 118)),
        ("01_after_hurt_light.png", "【新·即梦V1】小受击 hurt_light", (132, 96, 238)),
        ("02_after_hurt_heavy.png", "【新·即梦V2】大受击犁地 hurt_heavy", (132, 96, 238)),
        ("03_after_hurt_launch.png", "【新·即梦V3】空中击飞 hurt_launch", (132, 96, 238)),
        ("04_after_down.png", "【新·即梦V3】倒地平躺 down", (132, 96, 238)),
        ("05_after_getup.png", "【新·即梦V3】单膝拄剑起身 getup", (132, 96, 238)),
        ("06a_after_ranged_flip.png", "【新·即梦V4】K远程前空翻蓄势", (132, 96, 238)),
        ("06b_after_ranged_slash.png", "【新·即梦V4】K远程电光紫新月斩", (132, 96, 238)),
        ("07b_after_plunge_slam.png", "【新·即梦V5】S+J急坠满月竖劈插剑", (132, 96, 238)),
        ("08_after_attack1_settle.png", "【新·即梦V6】普攻1旋腕收剑回待机", (132, 96, 238)),
        ("10_after_run_stop.png", "【新·即梦V7】跑步蹬地扬尘刹步", (132, 96, 238)),
    ]

    cw, ch = 440, 275
    cols, rows = 4, 3
    pad, top_h = 16, 76
    W = cols * cw + (cols + 1) * pad
    H = top_h + rows * ch + (rows + 1) * pad

    board = Image.new("RGB", (W, H), (14, 16, 24))
    dr = ImageDraw.Draw(board)
    dr.text(
        (pad, 14),
        "《断晓》角色一致性 1:1 实机同框检验 · 旧动作基准 (绿框) vs 即梦 v2 新增动作 (紫框)",
        font=f_h,
        fill=(242, 238, 255),
    )
    dr.text(
        (pad, 48),
        "统一锁死 2.8 头身比例、单侧白挑染刘海、蓝紫渐变发梢、黑鸦羽肩、黑白百褶短裙、过膝长靴与 1.0× 黑银紫晶直剑，零换人割裂感",
        font=f_b,
        fill=(182, 188, 214),
    )

    for idx, (fn, title, col) in enumerate(items):
        r, c = divmod(idx, cols)
        x0 = pad + c * (cw + pad)
        y0 = top_h + pad + r * (ch + pad)
        im_full = Image.open(SHOT_DIR / fn).convert("RGB")
        foc = crop_focus_with_hud_inset(im_full, crop_w=580, crop_h=362).resize((cw, ch), Image.Resampling.LANCZOS)
        board.paste(foc, (x0, y0))
        dr.rectangle([x0, y0, x0 + cw - 1, y0 + ch - 1], outline=col, width=3)
        dr.rectangle([x0 + 2, y0 + 2, x0 + cw - 3, y0 + 30], fill=(18, 20, 32))
        dr.text((x0 + 10, y0 + 5), title, font=f_t, fill=(244, 242, 255))

    out_p = SHOT_DIR / "角色一致性实机同框总表_旧动作vs新11套动作.png"
    board.save(out_p, quality=95)
    return out_p


def encode_showcase_mp4() -> Path:
    seq_dir = SHOT_DIR / "seq"
    frames = sorted(seq_dir.glob("f_*.png"))
    if not frames:
        raise RuntimeError(f"No sequence frames found in {seq_dir}")
    out_mp4 = SHOT_DIR / "新旧动作一镜到底_雨夜实机60fps演武.mp4"

    ffmpeg_exe = shutil.which("ffmpeg")
    if not ffmpeg_exe:
        try:
            import imageio_ffmpeg
            ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
        except Exception:
            ffmpeg_exe = None

    if ffmpeg_exe:
        cmd = [
            ffmpeg_exe, "-y",
            "-framerate", "60",
            "-i", str(seq_dir / "f_%03d.png"),
            "-c:v", "libx264",
            "-preset", "slow",
            "-crf", "17",
            "-pix_fmt", "yuv420p",
            str(out_mp4),
        ]
        subprocess.run(cmd, check=True)
    else:
        import cv2
        im0 = cv2.imread(str(frames[0]))
        h, w = im0.shape[:2]
        vw = cv2.VideoWriter(str(out_mp4), cv2.VideoWriter_fourcc(*"mp4v"), 60.0, (w, h))
        for fp in frames:
            vw.write(cv2.imread(str(fp)))
        vw.release()
    return out_mp4


def main() -> None:
    p1 = build_before_after_board()
    p2 = build_consistency_12grid()
    p3 = encode_showcase_mp4()

    # 同步复制全部报告配图与实机录像到会话 Artifact 目录
    ART_DIR.mkdir(parents=True, exist_ok=True)
    to_copy = [
        p1,
        p2,
        p3,
        WORK_DIR / "解包核验_暗底12宫格.png",
        WORK_DIR / "解包核验_亮底零绿边12宫格.png",
    ]
    for src in to_copy:
        if src.exists():
            shutil.copy2(src, ART_DIR / src.name)
            print("Copied to Artifact dir:", src.name)


if __name__ == "__main__":
    main()
