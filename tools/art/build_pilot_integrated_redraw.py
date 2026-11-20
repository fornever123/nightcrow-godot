#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 4 张「原帧 1:1 角色+高颜值特效一体重画」样板分板（普攻1段全 13 帧 + 弹刀1后 8 帧，连同 11-06 弹刀1前 8 帧）
解包映射回原帧同尺寸世界坐标画布、实装进 battle.json（仅改 attack_1 与 parry_react_1，其余不动），
并输出逐帧同锚点等比例对比大图（带脚底锚点线与头顶等高标尺线）及原速/慢放对比 GIF。
"""
from __future__ import annotations

import copy
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets"
BATTLE_JSON = ASSETS / "data" / "battle.json"
BACKUP_JSON = ROOT / r"docs\视觉设计\角色动作\全动作精修与张力升级_20261114\backup_animations_before_overhaul.json"
WORK_ROOT = ROOT / r"docs\视觉设计\角色动作\原帧一体重画_20261115"
REDRAW_1106_P1 = ROOT / r"docs\视觉设计\角色动作\原帧重画_20261106\弹刀1_前8帧_带刀光\帧"
OUT_REL_ROOT = "image/desktop-actions-hd/redraw_20261115"
OUT_ABS_ROOT = ASSETS / "image" / "desktop-actions-hd" / "redraw_20261115"
CMP_DIR = WORK_ROOT / "验收对比"


def run_unpack(sheet_dir: Path, broken_frames: str = "") -> dict:
    gen_fp = sheet_dir / "重画_原图.png"
    lay_fp = sheet_dir / "输入_排版.json"
    out_frames = sheet_dir / "帧"
    cmd = [
        sys.executable,
        str(ROOT / "tools" / "art" / "codex_redraw_map_cv2.py"),
        str(gen_fp),
        str(lay_fp),
        str(out_frames),
    ]
    if broken_frames:
        cmd.extend(["--broken-frames", broken_frames])
    proc = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(proc.stdout.decode("utf-8", errors="replace").strip(), flush=True)
    return json.loads((out_frames / "manifest.json").read_text(encoding="utf-8"))


def render_world_frame(fd: dict, box_w: int, box_h: int, ax: int, ay: int, bg_rgb=(24, 26, 36), draw_guides: bool = True) -> Image.Image:
    canvas = Image.new("RGBA", (box_w, box_h), (*bg_rgb, 255))
    draw = ImageDraw.Draw(canvas)
    if draw_guides:
        # 脚底水平基线与头顶 385px 参考身高线，一眼核验人物大小 100% 恒定零跳变
        draw.line([(0, ay), (box_w, ay)], fill=(70, 90, 120, 180), width=1)
        draw.line([(0, ay - 385), (box_w, ay - 385)], fill=(60, 75, 95, 110), width=1)
        draw.line([(ax, 0), (ax, box_h)], fill=(70, 90, 120, 120), width=1)

    im = Image.open(ASSETS / fd["asset"]).convert("RGBA")
    ww, wh = round(float(fd["width"])), round(float(fd["height"]))
    if im.size != (ww, wh):
        im = im.resize((ww, wh), Image.Resampling.LANCZOS)
    px, py = round(float(fd["pivotX"])), round(float(fd["pivotY"]))
    ox, oy = ax - px, ay - py
    canvas.alpha_composite(im, (ox, oy))
    if draw_guides:
        draw.ellipse([ax - 3, ay - 3, ax + 3, ay + 3], fill=(255, 80, 90, 230))
    return canvas.convert("RGB")


def load_cn_font(size: int = 18) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for fp in [r"C:\Windows\Fonts\msyhbd.ttc", r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if Path(fp).exists():
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()


def build_strip_comparison(title: str, orig_frames: List[dict], new_frames: List[dict], box_w: int, box_h: int, ax: int, ay: int, cols_per_block: int, dst_png: Path) -> None:
    f_hdr = load_cn_font(20)
    f_lbl = load_cn_font(15)
    n = len(orig_frames)
    blocks = (n + cols_per_block - 1) // cols_per_block
    header_h = 46
    row_lbl_h = 28
    block_h = row_lbl_h + box_h * 2 + 12
    W = cols_per_block * box_w
    H = header_h + blocks * block_h

    board = Image.new("RGB", (W, H), (16, 18, 26))
    draw = ImageDraw.Draw(board)
    draw.text((16, 10), f"{title}  (上排: 原帧  |  下排: 1:1 角色+高颜值特效一体重画  |  红点=脚底Pivot锚点, 上横线=385px等高标尺)", fill=(235, 240, 255), font=f_hdr)

    for b in range(blocks):
        y0 = header_h + b * block_h
        i_start = b * cols_per_block
        i_end = min(n, i_start + cols_per_block)
        for k, idx in enumerate(range(i_start, i_end)):
            x0 = k * box_w
            draw.text((x0 + 8, y0 + 4), f"f{idx:02d}  (上:原来  /  下:新版)", fill=(185, 200, 230), font=f_lbl)
            im_old = render_world_frame(orig_frames[idx], box_w, box_h, ax, ay)
            im_new = render_world_frame(new_frames[idx], box_w, box_h, ax, ay)
            board.paste(im_old, (x0, y0 + row_lbl_h))
            board.paste(im_new, (x0, y0 + row_lbl_h + box_h + 2))
            draw.rectangle([x0, y0 + row_lbl_h, x0 + box_w - 1, y0 + row_lbl_h + box_h * 2 + 2], outline=(48, 54, 74), width=1)

    CMP_DIR.mkdir(parents=True, exist_ok=True)
    board.save(dst_png)


def build_side_by_side_gif(orig_clip: dict, new_clip: dict, box_w: int, box_h: int, ax: int, ay: int, dst_gif_real: Path, dst_gif_slow: Path) -> None:
    fps = float(orig_clip.get("fps", 24))
    o_frames = orig_clip["frames"]
    n_frames = new_clip["frames"]
    pil_frames = []
    durations_real = []
    durations_slow = []

    for i in range(len(o_frames)):
        im_l = render_world_frame(o_frames[i], box_w, box_h, ax, ay)
        im_r = render_world_frame(n_frames[i], box_w, box_h, ax, ay)
        pair = Image.new("RGB", (box_w * 2 + 4, box_h + 30), (16, 18, 26))
        d = ImageDraw.Draw(pair)
        d.text((12, 6), f"LEFT: Original f{i:02d}", fill=(180, 190, 210))
        d.text((box_w + 16, 6), f"RIGHT: 1:1 Co-Generated AI Redraw f{i:02d}", fill=(225, 195, 255))
        pair.paste(im_l, (0, 30))
        pair.paste(im_r, (box_w + 4, 30))
        pil_frames.append(pair)
        ticks = int(n_frames[i].get("durationTicks", 2))
        ms = max(30, round(ticks * (1000.0 / 60.0)))
        durations_real.append(ms)
        durations_slow.append(ms * 3)

    CMP_DIR.mkdir(parents=True, exist_ok=True)
    pil_frames[0].save(dst_gif_real, save_all=True, append_images=pil_frames[1:], duration=durations_real, loop=0)
    pil_frames[0].save(dst_gif_slow, save_all=True, append_images=pil_frames[1:], duration=durations_slow, loop=0)


def main() -> None:
    # 1. 解包 4 张分板
    m01 = run_unpack(WORK_ROOT / "01_普攻1段_f0_f4")
    m02 = run_unpack(WORK_ROOT / "02_普攻1段_f5_f8_带刀光")
    m03 = run_unpack(WORK_ROOT / "03_普攻1段_f9_f12")
    m04 = run_unpack(WORK_ROOT / "04_弹刀1_后8帧_f8_f15", broken_frames="8,9")

    # 2. 读取干净原始备份动画 + 当前 battle.json
    backup_anims = json.loads(BACKUP_JSON.read_text(encoding="utf-8"))
    battle_data = json.loads(BATTLE_JSON.read_text(encoding="utf-8"))
    anims = copy.deepcopy(backup_anims)

    # 3. 装配 attack_1 (全 13 帧 f0..f12)
    atk1_dir = OUT_ABS_ROOT / "attack_1"
    atk1_dir.mkdir(parents=True, exist_ok=True)
    atk1_map: Dict[int, Tuple[Path, dict]] = {}
    for s_name, m in [("01_普攻1段_f0_f4", m01), ("02_普攻1段_f5_f8_带刀光", m02), ("03_普攻1段_f9_f12", m03)]:
        for fr in m["frames"]:
            atk1_map[int(fr["frame"])] = (WORK_ROOT / s_name / "帧" / fr["file"], fr)

    for i, fd in enumerate(anims["attack_1"]["frames"]):
        src_png, m_fr = atk1_map[i]
        fn = f"frame_{i + 1:05d}.png"
        shutil.copy2(src_png, atk1_dir / fn)
        pad = float(m_fr["pivot_shift"])
        fd.pop("blank", None)
        fd.pop("empty", None)
        fd.pop("region", None)
        fd["asset"] = f"{OUT_REL_ROOT}/attack_1/{fn}"
        fd["width"] = m_fr["width"]
        fd["height"] = m_fr["height"]
        fd["pivotX"] = round(float(fd["pivotX"]) + pad, 3)
        fd["pivotY"] = round(float(fd["pivotY"]) + pad, 3)

    # 4. 装配 parry_react_1 (全 16 帧：f0..f7 复用 11-06 钦定带刀光前 8 帧 + f8..f15 本次一体重画后 8 帧)
    p1_dir = OUT_ABS_ROOT / "parry_react_1"
    p1_dir.mkdir(parents=True, exist_ok=True)
    m_1106 = json.loads((REDRAW_1106_P1 / "manifest.json").read_text(encoding="utf-8"))
    p1_map: Dict[int, Tuple[Path, dict]] = {}
    for fr in m_1106["frames"]:
        p1_map[int(fr["frame"])] = (REDRAW_1106_P1 / fr["file"], fr)
    for fr in m04["frames"]:
        p1_map[int(fr["frame"])] = (WORK_ROOT / "04_弹刀1_后8帧_f8_f15" / "帧" / fr["file"], fr)

    for i, fd in enumerate(anims["parry_react_1"]["frames"]):
        src_png, m_fr = p1_map[i]
        fn = f"frame_{i + 1:05d}.png"
        shutil.copy2(src_png, p1_dir / fn)
        pad = float(m_fr["pivot_shift"])
        fd.pop("blank", None)
        fd.pop("empty", None)
        fd.pop("region", None)
        fd["asset"] = f"{OUT_REL_ROOT}/parry_react_1/{fn}"
        fd["width"] = m_fr["width"]
        fd["height"] = m_fr["height"]
        fd["pivotX"] = round(float(fd["pivotX"]) + pad, 3)
        fd["pivotY"] = round(float(fd["pivotY"]) + pad, 3)

    # 5. 写回 battle.json（仅替换 characters[0].sprite.animations）
    battle_data["characters"][0]["sprite"]["animations"] = anims
    BATTLE_JSON.write_text(json.dumps(battle_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Updated battle.json (attack_1 13f + parry_react_1 16f mounted cleanly).", flush=True)

    # 6. 生成 1:1 同世界锚点逐帧对比条图与 GIF
    build_strip_comparison(
        "普攻1段 (attack_1 全 13 帧 · 0跳帧)",
        backup_anims["attack_1"]["frames"],
        anims["attack_1"]["frames"],
        box_w=960, box_h=540, ax=270, ay=475, cols_per_block=4,
        dst_png=CMP_DIR / "对比_普攻1段_全13帧_原帧vs一体重画.png",
    )
    build_strip_comparison(
        "弹刀反击1 (parry_react_1 全 16 帧 · 前8帧 11-06 + 后8帧 11-15 坏帧修复)",
        backup_anims["parry_react_1"]["frames"],
        anims["parry_react_1"]["frames"],
        box_w=540, box_h=540, ax=270, ay=480, cols_per_block=4,
        dst_png=CMP_DIR / "对比_弹刀1_全16帧_原帧vs一体重画.png",
    )
    build_side_by_side_gif(
        backup_anims["attack_1"], anims["attack_1"],
        box_w=960, box_h=540, ax=270, ay=475,
        dst_gif_real=CMP_DIR / "动图_普攻1段_原速对比.gif",
        dst_gif_slow=CMP_DIR / "动图_普攻1段_3倍慢放对比.gif",
    )
    build_side_by_side_gif(
        backup_anims["parry_react_1"], anims["parry_react_1"],
        box_w=480, box_h=540, ax=240, ay=480,
        dst_gif_real=CMP_DIR / "动图_弹刀1_原速对比.gif",
        dst_gif_slow=CMP_DIR / "动图_弹刀1_3倍慢放对比.gif",
    )
    print(f"Saved comparison boards & GIFs to {CMP_DIR}", flush=True)


if __name__ == "__main__":
    main()
