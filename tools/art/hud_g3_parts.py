"""把用户 11-17 选定的 HUD 方案 G3「钟楼指针」拆成游戏用的部件（左上：十字表轴 + 血条 + 绝影条）。

源图 docs/视觉设计/UI/HUD方案_20261117/HUD方案G3_钟楼指针.png 是纯黑底，用亮度算透明度。
输出 assets/image/ui/hud/（覆盖原来 A5 拆出来的同名部件），都是游戏里大小的 2 倍（SCALE = 0.4），
combat_hud.gd 按一半大小画。数字图集和 A5 时一样自己渲染（数字是实时变的）。

    python tools/art/hud_g3_parts.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from hud_a5_parts import build_digits, clear_box, polygon_mask, rounded_mask, save

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/视觉设计/UI/HUD方案_20261117/HUD方案G3_钟楼指针.png"

# 以下坐标都是源图像素（1672×941）
SLOT = (268, 406, 1452, 476)                  # 血槽内腔
SLOT_RADIUS = 34
CELLS = [(636, 762), (767, 889), (894, 1016), (1023, 1143), (1151, 1275)]   # 绝影五格内腔的左右
CELL_Y = (591, 665)
CELL_RADIUS = 14
FRAME_BOX = (0, 40, 1672, 900)
NUMBER = (452, 215, 940, 345)                 # “18 / 100”，游戏里实时画
LABEL_ULT = (285, 565, 545, 705)              # “绝影”
FEATHERS = [(240, 395), (245, 262), (300, 190), (370, 130), (450, 85), (540, 60), (522, 110), (470, 160),
        (432, 200), (450, 214), (444, 232), (400, 270), (350, 320), (312, 370), (292, 395)]


def main():
    out = ROOT / "assets/image/ui/hud"
    out.mkdir(parents=True, exist_ok=True)
    rgb = np.asarray(Image.open(SRC).convert("RGB"), dtype=np.float32).copy()
    h, w, _ = rgb.shape
    size = (w, h)
    lum = rgb.max(axis=2)

    # 透明度：亮的不透明，暗的按亮度淡出；紧贴亮部的暗部（金属阴影面）不透明
    soft = np.clip(lum / 60.0, 0.0, 1.0)
    near = np.asarray(Image.fromarray(((lum >= 60) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)),
            dtype=np.float32) / 255.0
    alpha = np.maximum(soft, near * np.clip(lum / 4.0, 0.0, 1.0))
    # 鸦羽是深蓝黑，整片算不透明，羽毛之间纯黑的缝留透明
    alpha = np.maximum(alpha, polygon_mask(size, FEATHERS, 1.5) * np.clip((lum - 2.0) / 3.0, 0.0, 1.0))
    keep_alpha = alpha.copy()
    keep_rgb = rgb.copy()
    clear_box(alpha, NUMBER)
    clear_box(alpha, LABEL_ULT)

    # 血槽挖空（表轴环紧贴槽的左端，留着）；槽和红血单独出图，画在框下面
    x0, y0, x1, y1 = SLOT
    hollow = rounded_mask(size, SLOT, SLOT_RADIUS, 1.0)
    frame_alpha = alpha * (1.0 - hollow)

    # 绝影五格改成没亮的样子，亮的单独出图
    frame_rgb = rgb.copy()
    cell_masks = []
    for cx0, cx1 in CELLS:
        box = (cx0, CELL_Y[0], cx1, CELL_Y[1])
        m = rounded_mask(size, box, CELL_RADIUS, 1.0)
        cell_masks.append((box, m))
        dark = rgb * 0.0 + np.array([8.0, 9.0, 14.0], dtype=np.float32)
        dark += rgb * np.array([0.04, 0.03, 0.08], dtype=np.float32)
        frame_rgb = frame_rgb * (1.0 - m[..., None]) + dark * m[..., None]
        frame_alpha = np.maximum(frame_alpha, m)

    save(frame_rgb, frame_alpha, FRAME_BOX, "frame.png")
    for i, (box, m) in enumerate(cell_masks):
        save(rgb, m, box, f"cell_{i}.png")

    # 空槽：红血右边就是原图的空槽（带分钟刻度），原样用；被红血盖住的左段用右边那段镜像补上
    red_end = 510
    slot_rgb = np.zeros_like(rgb)
    slot_rgb[y0:y1, x0:x1] = rgb[y0:y1, x0:x1]
    span = red_end - x0
    slot_rgb[y0:y1, x0:red_end] = rgb[y0:y1, red_end:red_end + span][:, ::-1]
    save(slot_rgb, rounded_mask(size, SLOT, SLOT_RADIUS, 0.8), SLOT, "slot.png")

    # 红血：左端原样，中段来回镜像铺满整条，血量多少都是同一种质感
    seg = rgb[y0:y1, 300:450]
    both = np.concatenate([seg, seg[:, ::-1]], axis=1)
    strip = np.concatenate([both] * ((x1 - x0) // both.shape[1] + 2), axis=1)
    fill_rgb = np.zeros_like(rgb)
    fill_rgb[y0:y1, x0:x1] = np.concatenate([rgb[y0:y1, x0:300], strip], axis=1)[:, :x1 - x0]
    save(fill_rgb, rounded_mask(size, SLOT, SLOT_RADIUS, 0.8), SLOT, "fill.png")

    save(keep_rgb, keep_alpha, LABEL_ULT, "label_ult.png")
    build_digits()


if __name__ == "__main__":
    main()
