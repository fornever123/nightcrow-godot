#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""背景线重构档（2026-11-19）后处理脚本：
1. 备份原有 ch1_1a_d2/B1..B3.png 到 改前备份/
2. 将 Codex 重绘的 B1 / B2 / B3 / C1 抠绿消溢、做轮廓 IoU 校验、测量明暗梯度与细节密度“最高/中位”比
3. 处理有厚度的石街沿 street_thick.png（左右 12% 交叉羽化无缝平铺）
4. 输出进 assets/image/rain_street/ch1_1a_d2/
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from rain_redesign_cutout import key_green  # noqa: E402

ROOT = Path(r"E:\00game\nightcrow-godot")
BASE = ROOT / "docs" / "_当前分支草稿" / "背景线" / "重构档_20261119"
SRC = BASE / "原图"
BAK = BASE / "改前备份"
CHK = BASE / "对齐检查"
OLD = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_two_level"
DST = ROOT / "assets" / "image" / "rain_street" / "ch1_1a_d2"


def detail_density_ratio(rgb: np.ndarray, alpha: np.ndarray) -> tuple[float, float, float]:
    """按行测量细节密度（梯度均值）的最高/中位比，以及上半部40% vs 下半活动带亮度。"""
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    gx = np.abs(np.diff(lum, axis=1, prepend=lum[:, :1]))
    gy = np.abs(np.diff(lum, axis=0, prepend=lum[:1, :]))
    grad = gx + gy
    mask = alpha > 0.5
    row_d = []
    for y in range(rgb.shape[0]):
        m = mask[y]
        if m.sum() > 80:
            row_d.append(float(grad[y, m].mean()))
    if not row_d:
        return 1.0, 0.0, 0.0
    arr_d = np.array(row_d)
    ratio = float(np.percentile(arr_d, 98) / max(np.median(arr_d), 1e-5))
    h = rgb.shape[0]
    top_m = mask[: int(h * 0.42)]
    bot_m = mask[int(h * 0.55) : int(h * 0.90)]
    lum_top = float(lum[: int(h * 0.42)][top_m].mean()) if top_m.any() else 0.0
    lum_bot = float(lum[int(h * 0.55) : int(h * 0.90)][bot_m].mean()) if bot_m.any() else 0.0
    return ratio, lum_top, lum_bot


def process_tile(code: str) -> None:
    p = SRC / f"{code}.png"
    if not p.exists():
        print(f"SKIP {code}: missing")
        return
    # 备份旧版
    BAK.mkdir(parents=True, exist_ok=True)
    if (DST / f"{code}.png").exists() and not (BAK / f"{code}.png").exists():
        shutil.copy2(DST / f"{code}.png", BAK / f"{code}.png")

    im = Image.open(p).convert("RGB").resize((1672, 941), Image.Resampling.LANCZOS)
    rgb = np.asarray(im, dtype=np.float32) / 255.0
    out, a = key_green(rgb)

    # 温和校准顶部 40% 暗雾梯度（仅在顶部仍然偏亮时柔和压一档，绝不破坏暖窗质感）
    ratio, lum_top, lum_bot = detail_density_ratio(out, a)
    if lum_top > lum_bot * 0.72:
        yy = np.linspace(0.0, 1.0, out.shape[0])[:, None, None]
        # 顶部 0..42% 温和压暗收进夜雾，活动带 54% 以下 100% 保持原样
        k_top = np.clip((yy - 0.05) / 0.48, 0.0, 1.0)
        k_top = k_top * k_top * (3.0 - 2.0 * k_top)
        att = 0.56 + 0.44 * k_top
        # 保留极少数暖色窗灯不被压暗
        warm = np.clip((out[..., 0] - out[..., 2]) * 3.5, 0.0, 1.0)[..., None]
        out = out * (att + (1.0 - att) * warm * 0.55)
        ratio, lum_top, lum_bot = detail_density_ratio(out, a)

    rgba = np.dstack([np.clip(out, 0, 1), np.clip(a, 0, 1)])
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(DST / f"{code}.png")

    # 轮廓 IoU 比对（相对 two_level 原图，保证能走的结构丝毫不挪）
    old = np.asarray(Image.open(OLD / f"{code}.png").convert("RGBA"), dtype=np.float32) / 255.0
    ma, mb = old[..., 3] > 0.5, a > 0.5
    iou = float((ma & mb).sum() / max(1, (ma | mb).sum()))
    CHK.mkdir(parents=True, exist_ok=True)
    lo = old[..., :3].mean(2)
    ln = out.mean(2)
    chk = np.dstack([lo, ln, ln])
    Image.fromarray((np.clip(chk * 1.6, 0, 1) * 255).astype(np.uint8)).save(CHK / f"{code}_旧红新青.jpg", quality=88)
    print(f"{code}: IoU={iou:.3f} | detail_max/med={ratio:.2f} | lum_top={lum_top:.3f} vs lum_bot={lum_bot:.3f}")


def process_street_thick() -> None:
    p = SRC / "street_thick.png"
    if not p.exists():
        print("SKIP street_thick: missing")
        return
    im = Image.open(p).convert("RGB").resize((2048, 512), Image.Resampling.LANCZOS)
    a = np.asarray(im, dtype=np.float32)
    w = a.shape[1]
    b = int(w * 0.12)
    t = np.linspace(0.0, 1.0, b)[None, :, None]
    a[:, w - b :] = a[:, w - b :] * (1.0 - t) + a[:, :b] * t
    a = a[:, : w - b]
    # 压平贴图里可能画死的局部暖光斑，让真实灯位在运行时打亮湿石板
    c = a / 255.0
    lum = c @ np.array([0.299, 0.587, 0.114])
    warm = np.clip((c[..., 0] - c[..., 2]) * 4.5, 0.0, 1.0)
    flat = np.dstack([lum * 0.99, lum, lum * 1.02])
    c = c * (1.0 - warm[..., None] * 0.55) + flat * (warm[..., None] * 0.55)
    Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8)).save(DST / "street_thick.png")
    print("street_thick ready:", c.shape)


def main() -> None:
    DST.mkdir(parents=True, exist_ok=True)
    for code in ["B1", "B2", "B3", "C1"]:
        process_tile(code)
    process_street_thick()


if __name__ == "__main__":
    main()
