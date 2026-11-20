#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 Forward+ 雨夜河岸街抓拍的全部 16 套 R3 战斗挥斩招式实机截图与 300 帧 60fps 序列帧组装为：
1. R3全招式_地面与空中连段实机八宫格.png (attack_1..3, attack_up, air_attack_1..3, dash_right)
2. R3全招式_冲刺格挡弹反实机八宫格.png (dash_left, parry, guard_hit_1..3, parry_react_1..3)
3. R3全招式_暗底原画高清细节16宫格.png (16 招峰值解包帧在 #141620 暗底上的高清原画细节展示)
4. R3全招式_雨夜实机60fps演武连招.mp4 (H.264 60fps 实机连招视频)
并同步复制到当前会话 Artifact 目录供直接嵌入验收报告。
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
SHOT_DIR = ROOT / ".runtime" / "r3_all_moves_shots"
DOC_OUT = ROOT / r"docs\视觉设计\角色动作\R3全招式真刀光_20261115"
ARTIFACT_DIR = Path(r"C:\Users\MECHREVO\.gemini\antigravity\brain\d6f86b03-464d-4b7b-9d5c-aaecf15e0988")

FONT_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"
FONT_REG = r"C:\Windows\Fonts\msyh.ttc"

MOVES_16 = [
    ("01_attack_1.png", "attack_1", 5, "01 普攻1段 (attack_1 f05)", "1.0x 原长直剑 + 满弓冷白主锋 + 蝉翼紫纱母本"),
    ("02_attack_2.png", "attack_2", 4, "02 普攻2段 (attack_2 f04)", "压身贴地反撩横扫满弓亮锋与半透明紫雾"),
    ("03_attack_3.png", "attack_3", 4, "03 普攻3段 (attack_3 f04)", "大弧度升龙上撩斩 + 零烟尘块干净透底"),
    ("04_attack_up.png", "attack_up", 9, "04 上挑强普 (attack_up f09)", "高耸升龙满月挑飞弧 + 柔顺渐变电光紫尾纱"),
    ("05_air_attack_1.png", "air_attack_1", 12, "05 空中1段 (air_attack_1 f12)", "腾空斜劈修长冷白切风锋线与通透紫纱"),
    ("06_air_attack_2.png", "air_attack_2", 8, "06 空中2段 (air_attack_2 f08)", "12帧全量AI重绘 · 空中旋身回环满月光弧"),
    ("07_air_attack_3.png", "air_attack_3", 0, "07 空中3段 (air_attack_3 f00)", "空中终结大满月斩 · 圆润完整无贴边硬切"),
    ("08_dash_right_video.png", "dash_right_video", 12, "08 右冲刺斩 (dash_right f12)", "修复无头坏帧 · 拔刀满月升斩与破风紫纱"),
    ("09_dash_left_video.png", "dash_left_video", 11, "09 左冲刺斩 (dash_left f11)", "修复无头坏帧 · 左向疾刺拔刀满弓月华斩"),
    ("10_parry.png", "parry", 8, "10 格挡架剑 (parry f08)", "由左下撩剑立盾 · 优雅冷白上挑弧锋"),
    ("11_guard_hit_1.png", "guard_hit_1", 1, "11 格挡受击1 (guard_hit_1 f01)", "竖刃卸力冷白月牙冲击弧 · 净除旧黄块火花"),
    ("12_guard_hit_2.png", "guard_hit_2", 5, "12 格挡受击2 (guard_hit_2 f05)", "原长直剑上段卸力切风弧与轻透紫雾"),
    ("13_guard_hit_3.png", "guard_hit_3", 10, "13 格挡受击3 (guard_hit_3 f10)", "重击滑步破风卸力弯弧与电光紫气浪"),
    ("14_parry_react_1.png", "parry_react_1", 2, "14 弹刀反击1 (parry_react_1 f02)", "撩剑弹反圆润冷白锋弧与半透明紫纱"),
    ("15_parry_react_2.png", "parry_react_2", 9, "15 弹刀反击2 (parry_react_2 f09)", "修复残腰截断 · 旋身反斩顺滑满弓月华"),
    ("16_parry_react_3.png", "parry_react_3", 9, "16 弹刀反击3 (parry_react_3 f09)", "修复吞身黄团 · 左上高处斜劈满弓切风斩"),
]


def load_font(path: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(path, size)


def make_rain_8grid(items: list[tuple], header_title: str, out_name: str) -> Path:
    """将 8 张 1280x720 实机雨夜截图排为 2列x4行 高清特写展板（聚焦角色与刀光核心区）。"""
    f_h1 = load_font(FONT_BOLD, 30)
    f_t = load_font(FONT_BOLD, 21)
    f_sub = load_font(FONT_REG, 16)

    cw, ch = 880, 440
    cols, rows = 2, 4
    pad = 18
    top_h = 76
    W = cols * cw + (cols + 1) * pad
    H = top_h + rows * ch + (rows + 1) * pad

    board = Image.new("RGB", (W, H), (13, 15, 23))
    draw = ImageDraw.Draw(board)
    draw.text((pad + 6, 20), header_title, font=f_h1, fill=(242, 238, 255))

    for idx, (shot_fn, _ck, _fi, title, sub) in enumerate(items):
        r, c = divmod(idx, cols)
        x0 = pad + c * (cw + pad)
        y0 = top_h + pad + r * (ch + pad)

        im = Image.open(SHOT_DIR / shot_fn).convert("RGB")
        # 1280x720 中精准聚焦角色全身（头顶至战靴）、满弓刀光与运河水面紫光倒影 (760x380 -> 2:1)
        crop_box = (270, 290, 1030, 670) if _ck.startswith("air_") else (270, 340, 1030, 720)
        crop = im.crop(crop_box).resize((cw, ch), Image.Resampling.LANCZOS)
        board.paste(crop, (x0, y0))

        # 顶部半透明深色标题条
        bar = Image.new("RGBA", (cw, 62), (10, 12, 20, 196))
        board_rgba = board.convert("RGBA")
        board_rgba.alpha_composite(bar, (x0, y0))
        board = board_rgba.convert("RGB")
        draw = ImageDraw.Draw(board)
        draw.rectangle([x0, y0, x0 + cw - 1, y0 + ch - 1], outline=(128, 96, 215), width=2)
        draw.text((x0 + 14, y0 + 8), title, font=f_t, fill=(248, 244, 255))
        draw.text((x0 + 14, y0 + 36), sub, font=f_sub, fill=(196, 182, 240))

    doc_fp = DOC_OUT / out_name
    art_fp = ARTIFACT_DIR / out_name
    board.save(doc_fp)
    shutil.copy2(doc_fp, art_fp)
    return art_fp


def make_dark_studio_16grid(out_name: str) -> Path:
    """将 16 招峰值解包世界帧贴在纯净 #141620 暗底上，检验半透明紫纱、冷白满弓锋与 1.0x 原长直剑细节。"""
    f_h1 = load_font(FONT_BOLD, 30)
    f_t = load_font(FONT_BOLD, 18)

    cw, ch = 440, 340
    cols, rows = 4, 4
    pad = 14
    top_h = 74
    W = cols * cw + (cols + 1) * pad
    H = top_h + rows * ch + (rows + 1) * pad

    board = Image.new("RGBA", (W, H), (14, 16, 24, 255))
    draw = ImageDraw.Draw(board)
    draw.text(
        (pad + 6, 20),
        "R3 满弓月华流光斩 · 全部 16 套战斗招式解包原画细节总览 (#141620 暗棚底检验半透明渐变与 1.0x 直剑)",
        font=f_h1,
        fill=(242, 238, 255),
    )

    stage_dir = ASSETS / "image" / "desktop-actions-hd" / "r3_true_slash_20261115"
    for idx, (_shot_fn, ck, fi, title, _sub) in enumerate(MOVES_16):
        r, c = divmod(idx, cols)
        x0 = pad + c * (cw + pad)
        y0 = top_h + pad + r * (ch + pad)

        cell = Image.new("RGBA", (cw, ch), (20, 22, 32, 255))
        fr_fp = stage_dir / ck / f"frame_{fi:05d}.png"
        sp = Image.open(fr_fp).convert("RGBA")
        bb = sp.getbbox()
        if bb:
            sp = sp.crop((max(0, bb[0] - 12), max(0, bb[1] - 12), min(sp.width, bb[2] + 12), min(sp.height, bb[3] + 12)))
        s = min(0.85, (cw - 36) / max(sp.width, 1), (ch - 58) / max(sp.height, 1))
        sp_r = sp.resize((max(4, round(sp.width * s)), max(4, round(sp.height * s))), Image.Resampling.LANCZOS)
        cell.alpha_composite(sp_r, ((cw - sp_r.width) // 2, 38 + (ch - 44 - sp_r.height) // 2))
        board.alpha_composite(cell, (x0, y0))

        draw = ImageDraw.Draw(board)
        draw.rectangle([x0, y0, x0 + cw - 1, y0 + ch - 1], outline=(112, 86, 198, 255), width=2)
        draw.text((x0 + 10, y0 + 8), title, font=f_t, fill=(238, 232, 255, 255))

    out_rgb = board.convert("RGB")
    doc_fp = DOC_OUT / out_name
    art_fp = ARTIFACT_DIR / out_name
    out_rgb.save(doc_fp)
    shutil.copy2(doc_fp, art_fp)
    return art_fp


def make_light_bg_16grid(out_name: str) -> Path:
    """将 16 招峰值解包世界帧贴在浅冷灰白底 (#CDD3E2) 上，验证零暗块残边、黑靴实心与亮底可读性。"""
    f_h1 = load_font(FONT_BOLD, 30)
    f_t = load_font(FONT_BOLD, 18)

    cw, ch = 440, 340
    cols, rows = 4, 4
    pad = 14
    top_h = 74
    W = cols * cw + (cols + 1) * pad
    H = top_h + rows * ch + (rows + 1) * pad

    board = Image.new("RGBA", (W, H), (186, 194, 212, 255))
    draw = ImageDraw.Draw(board)
    draw.text(
        (pad + 6, 20),
        "R3 满弓月华流光斩 · 亮底通透度与零残边 X 光检验 (#CDD3E2 亮底验证黑靴实心与紫纱半透明)",
        font=f_h1,
        fill=(22, 24, 38),
    )

    stage_dir = ASSETS / "image" / "desktop-actions-hd" / "r3_true_slash_20261115"
    for idx, (_shot_fn, ck, fi, title, _sub) in enumerate(MOVES_16):
        r, c = divmod(idx, cols)
        x0 = pad + c * (cw + pad)
        y0 = top_h + pad + r * (ch + pad)

        cell = Image.new("RGBA", (cw, ch), (205, 211, 226, 255))
        fr_fp = stage_dir / ck / f"frame_{fi:05d}.png"
        sp = Image.open(fr_fp).convert("RGBA")
        bb = sp.getbbox()
        if bb:
            sp = sp.crop((max(0, bb[0] - 12), max(0, bb[1] - 12), min(sp.width, bb[2] + 12), min(sp.height, bb[3] + 12)))
        s = min(0.85, (cw - 36) / max(sp.width, 1), (ch - 58) / max(sp.height, 1))
        sp_r = sp.resize((max(4, round(sp.width * s)), max(4, round(sp.height * s))), Image.Resampling.LANCZOS)
        cell.alpha_composite(sp_r, ((cw - sp_r.width) // 2, 38 + (ch - 44 - sp_r.height) // 2))
        board.alpha_composite(cell, (x0, y0))

        draw = ImageDraw.Draw(board)
        draw.rectangle([x0, y0, x0 + cw - 1, y0 + ch - 1], outline=(105, 82, 185, 255), width=2)
        draw.text((x0 + 10, y0 + 8), title, font=f_t, fill=(28, 24, 48, 255))

    out_rgb = board.convert("RGB")
    doc_fp = DOC_OUT / out_name
    art_fp = ARTIFACT_DIR / out_name
    out_rgb.save(doc_fp)
    shutil.copy2(doc_fp, art_fp)
    return art_fp


def encode_60fps_video(out_name: str) -> Path:
    seq_dir = SHOT_DIR / "seq"
    doc_mp4 = DOC_OUT / out_name
    art_mp4 = ARTIFACT_DIR / out_name
    if doc_mp4.exists() and doc_mp4.stat().st_size > 1_000_000:
        shutil.copy2(doc_mp4, art_mp4)
        return art_mp4
    ffmpeg_bin = shutil.which("ffmpeg") or "ffmpeg"
    cmd = [
        ffmpeg_bin, "-y",
        "-framerate", "60",
        "-i", str(seq_dir / "f_%03d.png"),
        "-c:v", "libx264",
        "-pix_fmt", "yuv420p",
        "-crf", "17",
        "-preset", "fast",
        str(doc_mp4),
    ]
    subprocess.run(cmd, check=True)
    shutil.copy2(doc_mp4, art_mp4)
    return art_mp4


def main() -> None:
    DOC_OUT.mkdir(parents=True, exist_ok=True)
    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

    p1 = make_rain_8grid(
        MOVES_16[:8],
        "R3 满弓月华流光斩 · 实机雨夜验收展板 A（普攻1-3 / 上挑强普 / 空中1-3 / 右冲刺斩）",
        "R3全招式_地面与空中连段实机八宫格.png",
    )
    p2 = make_rain_8grid(
        MOVES_16[8:],
        "R3 满弓月华流光斩 · 实机雨夜验收展板 B（左冲刺斩 / 格挡架剑 / 格挡受击1-3 / 弹刀反击1-3）",
        "R3全招式_冲刺格挡弹反实机八宫格.png",
    )
    p3 = make_dark_studio_16grid("R3全招式_暗底原画高清细节16宫格.png")
    p3b = make_light_bg_16grid("R3全招式_亮底通透无残边16宫格.png")
    p4 = encode_60fps_video("R3全招式_雨夜实机60fps演武连招.mp4")

    print("Showcase assets built:")
    for p in (p1, p2, p3, p3b, p4):
        print(" ->", p)


if __name__ == "__main__":
    main()
