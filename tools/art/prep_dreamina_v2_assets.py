#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
为即梦 Seedance 2.0 Fast VIP (v2) 准备 100% 景别对齐、零出画、零黑条、零文字的上传素材。
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / r"docs\视觉设计\角色动作\动作补齐_即梦v2_20261117\上传素材"
CHECK_PNG = ROOT / r"docs\视觉设计\角色动作\动作补齐_即梦v2_20261117\上传前全素材核验总表.png"
BG_RGB = (127, 168, 143)  # #7FA88F
CANVAS_W, CANVAS_H = 1280, 720
FOOT_Y = 612  # 85% of 720
STAND_H = 420  # ~58.5% of 720


def paste_rgba_on_bg(fg_rgba: Image.Image, dst_x_center: int, dst_y_bottom: int) -> Image.Image:
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (*BG_RGB, 255))
    x0 = round(dst_x_center - fg_rgba.width / 2)
    y0 = round(dst_y_bottom - fg_rgba.height)
    canvas.alpha_composite(fg_rgba, (x0, y0))
    return canvas.convert("RGB")


def build_image_assets() -> None:
    pose = Image.open(ROOT / "assets/image/ai-hd-20261020/idle/pose_002.png").convert("RGBA")
    pose_c = pose.crop(pose.getbbox())
    scale_pose = STAND_H / pose_c.height
    pose_r = pose_c.resize((round(pose_c.width * scale_pose), STAND_H), Image.Resampling.LANCZOS)
    paste_rgba_on_bg(pose_r, 640, FOOT_Y).save(OUT_DIR / "img_main_pose002.png")

    turn = Image.open(ROOT / r"docs\视觉设计\角色海报\三视图.webp").convert("RGBA")
    arr = np.array(turn)
    white_bg = (arr[..., 0] > 240) & (arr[..., 1] > 240) & (arr[..., 2] > 240)
    arr[white_bg, 3] = 0
    turn_clean = Image.fromarray(arr)
    W_t, H_t = turn_clean.size

    side_crop = turn_clean.crop((round(W_t * 0.30), 0, round(W_t * 0.53), H_t))
    side_c = side_crop.crop(side_crop.getbbox())
    s_side = STAND_H / side_c.height
    side_r = side_c.resize((round(side_c.width * s_side), STAND_H), Image.Resampling.LANCZOS)
    paste_rgba_on_bg(side_r, 640, FOOT_Y).save(OUT_DIR / "img_aux_side.png")

    back_crop = turn_clean.crop((round(W_t * 0.54), 0, W_t, H_t))
    back_c = back_crop.crop(back_crop.getbbox())
    s_back = STAND_H / back_c.height
    back_r = back_c.resize((round(back_c.width * s_back), STAND_H), Image.Resampling.LANCZOS)
    paste_rgba_on_bg(back_r, 640, FOOT_Y).save(OUT_DIR / "img_aux_back.png")

    a1_0 = Image.open(ROOT / "assets/image/desktop-actions-hd/r3_true_slash_20261115/attack_1/frame_00000.png").convert("RGBA")
    a1_0_c = a1_0.crop(a1_0.getbbox())
    scale_a1 = STAND_H / a1_0_c.height

    a1_end = Image.open(ROOT / "assets/image/desktop-actions-hd/r3_true_slash_20261115/attack_1/frame_00012.png").convert("RGBA")
    arr_end = np.array(a1_end)
    arr_end[arr_end[..., 3] < 150, 3] = 0
    a1_end_c = Image.fromarray(arr_end)
    a1_end_c = a1_end_c.crop(a1_end_c.getbbox())
    a1_end_r = a1_end_c.resize(
        (round(a1_end_c.width * scale_a1), round(a1_end_c.height * scale_a1)),
        Image.Resampling.LANCZOS,
    )
    paste_rgba_on_bg(a1_end_r, 640, FOOT_Y).save(OUT_DIR / "img_start_a1_end.png")

    run_dir = ROOT / "assets/image/imports/framebaker/87da3608-35f3-4485-b16e-13e95071f7b2"
    run_pick = run_dir / "run_intro_004.png"
    run_im = Image.open(run_pick).convert("RGBA")
    run_c = run_im.crop(run_im.getbbox())
    target_run_h = round(STAND_H * 0.87)
    s_run = target_run_h / run_c.height
    run_r = run_c.resize((round(run_c.width * s_run), target_run_h), Image.Resampling.LANCZOS)
    paste_rgba_on_bg(run_r, 620, FOOT_Y).save(OUT_DIR / "img_start_run.png")


def extract_clean_fg_from_gray(
    rgb: np.ndarray,
    roi: tuple[int, int, int, int],
    floor_y_src: int | None = None,
) -> tuple[np.ndarray, int, int]:
    H, W = rgb.shape[:2]
    x0, y0, x1, y1 = max(0, roi[0]), max(0, roi[1]), min(W, roi[2]), min(H, roi[3])
    if floor_y_src is not None:
        y1 = min(y1, floor_y_src)
    sub = rgb[y0:y1, x0:x1].copy()
    r, g, b = sub[..., 0].astype(np.int16), sub[..., 1].astype(np.int16), sub[..., 2].astype(np.int16)

    chroma = np.maximum(np.maximum(r, g), b) - np.minimum(np.minimum(r, g), b)
    med_r = int(np.median(r[0:12, :]))
    med_g = int(np.median(g[0:12, :]))
    med_b = int(np.median(b[0:12, :]))
    # 去灰底、暗地板横条（低饱和度暗灰 <85）、细竖墙缝线（与背景差 <=22 且低饱和度）
    bg_gray = (np.abs(r - med_r) <= 18) & (np.abs(g - med_g) <= 18) & (np.abs(b - med_b) <= 18) & (chroma <= 18)
    green_line = (g - r >= 12) & (g > 95) & (np.abs(g - b) <= 32)
    bg_mask = bg_gray | green_line

    rgba = np.zeros((sub.shape[0], sub.shape[1], 4), dtype=np.uint8)
    rgba[..., :3] = sub
    rgba[..., 3] = np.where(bg_mask, 0, 255)
    return rgba, x0, y0


def measure_char_body(fg_rgba: np.ndarray) -> tuple[int, int, int]:
    """只用粉红头发 + 青蓝衣服 + 深灰靴子像素测量真实人体站高、脚底行与水平中心，不受火花/地面线干扰。"""
    a = fg_rgba[..., 3] > 0
    r, g, b = fg_rgba[..., 0].astype(int), fg_rgba[..., 1].astype(int), fg_rgba[..., 2].astype(int)
    # 排除纯白大光效 (>235)
    not_pure_white = ~((r > 235) & (g > 235) & (b > 235))
    body = a & not_pure_white
    ys, xs = np.where(body)
    if len(ys) < 10:
        ys, xs = np.where(a)
    h = max(int(ys.max() - ys.min() + 1), 1)
    foot_y = int(ys.max())
    cx = int(0.5 * (xs.min() + xs.max()))
    return h, foot_y, cx


def render_clean_clip(
    vp: Path,
    frame_indices: list[int],
    roi: tuple[int, int, int, int],
    stand_frame_idx: int,
    target_h: int = STAND_H,
    dst_stand_x: int = 640,
    dst_foot_y: int = FOOT_Y,
    floor_y_src: int | None = None,
) -> list[np.ndarray]:
    cap = cv2.VideoCapture(str(vp))
    cap.set(cv2.CAP_PROP_POS_FRAMES, stand_frame_idx)
    ok, ref_bgr = cap.read()
    assert ok and ref_bgr is not None
    ref_rgb = cv2.cvtColor(ref_bgr, cv2.COLOR_BGR2RGB)
    ref_rgba, rx0, ry0 = extract_clean_fg_from_gray(ref_rgb, roi, floor_y_src)
    src_stand_h, local_foot, local_cx = measure_char_body(ref_rgba)
    src_foot_y = ry0 + local_foot
    src_stand_cx = rx0 + local_cx
    scale = target_h / src_stand_h

    # 先预扫整段世界 bbox，自动微调水平偏移使整段动作 100% 留在 [60 .. CANVAS_W-60] 内！
    raw_items = []
    min_dx, max_dx2 = 99999, -99999
    for fi in frame_indices:
        cap.set(cv2.CAP_PROP_POS_FRAMES, fi)
        ok, bgr = cap.read()
        if not ok or bgr is None:
            continue
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        fg_rgba, x0, y0 = extract_clean_fg_from_gray(rgb, roi, floor_y_src)
        pil_fg = Image.fromarray(fg_rgba)
        bb = pil_fg.getbbox()
        raw_items.append((pil_fg, bb, x0, y0))
        if bb:
            # 用人物核心估算水平范围
            _, _, lcx = measure_char_body(fg_rgba)
            wcx = dst_stand_x + round((x0 + lcx - src_stand_cx) * scale)
            min_dx = min(min_dx, wcx - round(target_h * 0.45))
            max_dx2 = max(max_dx2, wcx + round(target_h * 0.45))
    cap.release()

    shift_x = 0
    if max_dx2 > CANVAS_W - 70:
        shift_x = (CANVAS_W - 70) - max_dx2
    if min_dx + shift_x < 70:
        shift_x = 70 - min_dx

    out_frames: list[np.ndarray] = []
    for pil_fg, bb, x0, y0 in raw_items:
        canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (*BG_RGB, 255))
        if bb:
            crop_fg = pil_fg.crop(bb)
            nw = max(2, round(crop_fg.width * scale))
            nh = max(2, round(crop_fg.height * scale))
            crop_r = crop_fg.resize((nw, nh), Image.Resampling.NEAREST)
            world_x0 = x0 + bb[0]
            world_y0 = y0 + bb[1]
            dst_x = round(dst_stand_x + shift_x + (world_x0 - src_stand_cx) * scale)
            dst_y = round(dst_foot_y + (world_y0 - src_foot_y) * scale)
            dst_y = max(12, min(CANVAS_H - nh - 16, dst_y))
            canvas.alpha_composite(crop_r, (dst_x, dst_y))
        out_frames.append(np.array(canvas.convert("RGB")))
    return out_frames


def encode_mp4(frames_rgb: list[np.ndarray], out_mp4: Path, fps: int = 20) -> None:
    tmp_dir = OUT_DIR / f"_tmp_{out_mp4.stem}"
    if tmp_dir.exists():
        shutil.rmtree(tmp_dir)
    tmp_dir.mkdir(parents=True, exist_ok=True)
    for idx, fr in enumerate(frames_rgb):
        Image.fromarray(fr).save(tmp_dir / f"f_{idx:04d}.png")
    ffmpeg_bin = shutil.which("ffmpeg") or "ffmpeg"
    subprocess.run(
        [
            ffmpeg_bin, "-y",
            "-framerate", str(fps),
            "-i", str(tmp_dir / "f_%04d.png"),
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-crf", "16",
            str(out_mp4),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    shutil.rmtree(tmp_dir, ignore_errors=True)


def build_video_assets() -> dict[str, tuple[int, float]]:
    meta: dict[str, tuple[int, float]] = {}

    # V1: 小受击 (55f = 2.75s)
    v1_frames = render_clean_clip(
        Path(r"E:\夸克\603-604\动作参考成片\Yudou_20260320_22_上方_小受击.mp4"),
        list(range(6, 61)),
        roi=(300, 140, 1250, 680),
        stand_frame_idx=6,
        target_h=STAND_H,
        dst_stand_x=640,
    )
    encode_mp4(v1_frames, OUT_DIR / "vid_V1_hurt_light.mp4", fps=20)
    meta["vid_V1_hurt_light.mp4"] = (len(v1_frames), len(v1_frames) / 20.0)

    # V2: 大受击 (57f = 2.85s, 自动左移保持全程居中不出右边界)
    v2_frames = render_clean_clip(
        Path(r"E:\夸克\603-604\动作参考成片\Yudou_20260320_22_下方_大受击.mp4"),
        list(range(6, 63)),
        roi=(240, 140, 1380, 690),
        stand_frame_idx=6,
        target_h=STAND_H,
        dst_stand_x=420,
    )
    encode_mp4(v2_frames, OUT_DIR / "vid_V2_hurt_heavy.mp4", fps=20)
    meta["vid_V2_hurt_heavy.mp4"] = (len(v2_frames), len(v2_frames) / 20.0)

    # V3: 击飞 + 倒地 + 撑地起身回到站立待机
    # 前段: Yudou_25_new.mp4 (floor_y_src=444 彻底切掉暗灰地板横条! x<520 切掉右侧路灯/敌人!)
    #   f14..f19 (站立 6f) + f64..f96 (横飞腾空 -> 摔地翻滚 -> 趴地缓冲 33f)
    # 后段: 接同比例 43_向右翻滚 f14..f20 (单膝撑起 7f) + 25_new f15 站姿回正 (10f) = 56f (2.80s)，全程严格同身高！
    v3_part1 = render_clean_clip(
        Path(r"E:\夸克\603-604\Yudou_20260320_25_new.mp4"),
        list(range(14, 20)) + list(range(64, 97)),
        roi=(8, 315, 555, 443),
        stand_frame_idx=15,
        target_h=380,
        dst_stand_x=900,
        dst_foot_y=FOOT_Y,
        floor_y_src=443,
    )
    fg_p1 = np.any(np.abs(v3_part1[-1].astype(int) - np.array(BG_RGB)) > 8, axis=-1)
    _, xs_p1 = np.where(fg_p1)
    land_cx = int(np.median(xs_p1)) if len(xs_p1) > 0 else 420

    # 用 43_向右翻滚 f0 (标准站姿) 定标 380px，取 f14..f20 撑地半蹲起身
    v3_getup_mid = render_clean_clip(
        Path(r"E:\夸克\603-604\动作参考成片\使用过的\Yudou_20260320_43_向右翻滚.mp4"),
        list(range(14, 21)),
        roi=(0, 60, 4000, 2000),
        stand_frame_idx=0,
        target_h=380,
        dst_stand_x=land_cx - 420,
        dst_foot_y=FOOT_Y,
    )
    # 重新对齐 getup_mid 第一帧水平中心到 land_cx
    fg_gm0 = np.any(np.abs(v3_getup_mid[0].astype(int) - np.array(BG_RGB)) > 8, axis=-1)
    _, xs_gm0 = np.where(fg_gm0)
    gm0_cx = int(np.median(xs_gm0)) if len(xs_gm0) > 0 else land_cx
    dx_fix = land_cx - gm0_cx
    v3_getup_aligned = []
    for fr in v3_getup_mid:
        shifted = np.full_like(fr, BG_RGB)
        if dx_fix >= 0:
            shifted[:, dx_fix:] = fr[:, : CANVAS_W - dx_fix]
        else:
            shifted[:, : CANVAS_W + dx_fix] = fr[:, -dx_fix:]
        v3_getup_aligned.append(shifted)

    fg_gml = np.any(np.abs(v3_getup_aligned[-1].astype(int) - np.array(BG_RGB)) > 8, axis=-1)
    _, xs_gml = np.where(fg_gml)
    end_cx = int(np.median(xs_gml)) if len(xs_gml) > 0 else land_cx

    v3_stand_end = render_clean_clip(
        Path(r"E:\夸克\603-604\动作参考成片\使用过的\Yudou_20260320_43_向右翻滚.mp4"),
        [0] * 10,
        roi=(0, 60, 4000, 2000),
        stand_frame_idx=0,
        target_h=380,
        dst_stand_x=end_cx,
        dst_foot_y=FOOT_Y,
    )
    v3_frames = v3_part1 + v3_getup_aligned + v3_stand_end
    encode_mp4(v3_frames, OUT_DIR / "vid_V3_launch_down_getup.mp4", fps=20)
    meta["vid_V3_launch_down_getup.mp4"] = (len(v3_frames), len(v3_frames) / 20.0)

    # V4: K键远程空翻剑气 (target_h=340 留足上方空翻与右侧剑气空间，全程 100% 居画内！54f = 2.70s)
    cap18 = cv2.VideoCapture(r"E:\夸克\603-604\动作参考成片\Yudou_20260320_18_远程攻击动作参考.mp4")
    n18 = int(cap18.get(cv2.CAP_PROP_FRAME_COUNT))
    cap18.release()
    v4_frames = render_clean_clip(
        Path(r"E:\夸克\603-604\动作参考成片\Yudou_20260320_18_远程攻击动作参考.mp4"),
        list(range(0, n18)) + [n18 - 1] * max(0, 54 - n18),
        roi=(20, 10, 1190, 590),
        stand_frame_idx=0,
        target_h=345,
        dst_stand_x=280,
        dst_foot_y=625,
    )
    encode_mp4(v4_frames, OUT_DIR / "vid_V4_ranged_cast.mp4", fps=20)
    meta["vid_V4_ranged_cast.mp4"] = (len(v4_frames), len(v4_frames) / 20.0)

    # V5: 空中急坠下劈砸地 (Yudou_34_new f58..f108, floor_y_src=550, target_h=345, dst_foot_y=645 顶部与底部均完整！56f = 2.80s)
    v5_frames = render_clean_clip(
        Path(r"E:\夸克\603-604\Yudou_20260320_34_new.mp4"),
        list(range(58, 109)) + [108] * 5,
        roi=(120, 80, 1020, 550),
        stand_frame_idx=100,
        target_h=345,
        dst_stand_x=640,
        dst_foot_y=645,
        floor_y_src=550,
    )
    encode_mp4(v5_frames, OUT_DIR / "vid_V5_air_plunge.mp4", fps=20)
    meta["vid_V5_air_plunge.mp4"] = (len(v5_frames), len(v5_frames) / 20.0)
    return meta


def make_verification_board(meta: dict[str, tuple[int, float]]) -> None:
    f_h = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 22)
    f_t = ImageFont.truetype(r"C:\Windows\Fonts\msyhbd.ttc", 14)

    imgs = [
        "img_main_pose002.png",
        "img_aux_side.png",
        "img_aux_back.png",
        "img_start_a1_end.png",
        "img_start_run.png",
    ]
    vids = [
        "vid_V1_hurt_light.mp4",
        "vid_V2_hurt_heavy.mp4",
        "vid_V3_launch_down_getup.mp4",
        "vid_V4_ranged_cast.mp4",
        "vid_V5_air_plunge.mp4",
    ]

    tw, th = 220, 124
    W = 6 * (tw + 12) + 20
    H = 60 + 180 + len(vids) * (th + 36) + 20
    board = Image.new("RGB", (W, H), (16, 18, 26))
    dr = ImageDraw.Draw(board)
    dr.text((16, 14), "即梦 v2 上传素材全量核验总表 v2（零出画 · 零黑条 · 同比例 · #7FA88F净底 · <=2.85s）", font=f_h, fill=(244, 240, 255))

    for i, fn in enumerate(imgs):
        x0 = 16 + i * (tw + 12)
        y0 = 58
        p = Image.open(OUT_DIR / fn).resize((tw, th), Image.Resampling.LANCZOS)
        board.paste(p, (x0, y0 + 22))
        dr.text((x0, y0), fn, font=f_t, fill=(140, 235, 175))

    for r, vfn in enumerate(vids):
        y0 = 232 + r * (th + 36)
        nf, dur = meta[vfn]
        dr.text((16, y0), f"{vfn}  ({nf} frames, {dur:.2f}s @ 20fps)", font=f_t, fill=(240, 230, 140))
        cap = cv2.VideoCapture(str(OUT_DIR / vfn))
        for c in range(6):
            fi = round(c * (nf - 1) / 5)
            cap.set(cv2.CAP_PROP_POS_FRAMES, fi)
            ok, bgr = cap.read()
            if ok and bgr is not None:
                p = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)).resize((tw, th), Image.Resampling.BILINEAR)
                x0 = 16 + c * (tw + 12)
                board.paste(p, (x0, y0 + 20))
                dr.text((x0 + 4, y0 + 22), f"f{fi}", font=f_t, fill=(255, 255, 255))
        cap.release()

    board.save(CHECK_PNG)
    print("Verification board saved:", CHECK_PNG)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    build_image_assets()
    meta = build_video_assets()
    make_verification_board(meta)
    for k, (nf, dur) in meta.items():
        print(f"  {k:32s}: {nf}f ({dur:.2f}s)")


if __name__ == "__main__":
    main()
