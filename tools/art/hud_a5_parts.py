"""把用户选定的 HUD 方案 A5 拆成游戏用的部件（左上：十字 + 血条 + 绝影条）。

源图 docs/视觉设计/UI/HUD方案_20261106/HUD方案A5_精修.png 是纯黑底，用亮度算透明度。
输出 assets/image/ui/hud/，都是游戏里大小的 2 倍（SCALE = 0.4），combat_hud.gd 按一半大小画。

    python tools/art/hud_a5_parts.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/视觉设计/UI/HUD方案_20261106/HUD方案A5_精修.png"
OUT = ROOT / "assets/image/ui/hud"
SCALE = 0.4

# 以下坐标都是源图像素
SLOT = (246, 411, 1435, 478)                  # 血条槽
SLOT_RADIUS = 28
CELLS = [(619, 743), (754, 869), (880, 995), (1006, 1124), (1134, 1254)]   # 绝影五格的左右
CELL_Y = (604, 680)
CELL_RADIUS = 16
FRAME_BOX = (0, 20, 1672, 870)
NUMBER = (428, 232, 945, 352)                 # “18 / 100”，游戏里实时画
LABEL_ULT = (240, 584, 524, 714)              # “绝影”
LABEL_KEYS = (1334, 590, 1596, 704)           # “J+K”
FEATHERS = [(215, 290), (260, 170), (330, 110), (400, 90), (470, 25), (478, 60), (440, 130), (396, 180),
        (534, 180), (470, 205), (400, 245), (340, 292), (292, 332), (240, 342)]


def rounded_mask(size, box, radius, blur=0.0):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius, fill=255)
    if blur > 0.0:
        m = m.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(m, dtype=np.float32) / 255.0


def polygon_mask(size, points, blur=0.0):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    if blur > 0.0:
        m = m.filter(ImageFilter.GaussianBlur(blur))
    return np.asarray(m, dtype=np.float32) / 255.0


def clear_box(alpha, box):
    x0, y0, x1, y1 = box
    alpha[y0:y1, x0:x1] = 0.0


def save(rgb, alpha, box, name):
    """裁切、预乘后缩小，避免透明边发黑。"""
    x0, y0, x1, y1 = box
    a = np.clip(alpha[y0:y1, x0:x1], 0.0, 1.0)
    pre = np.dstack([np.clip(rgb[y0:y1, x0:x1], 0.0, 255.0) * a[..., None], a * 255.0]).astype(np.float32)
    w, h = round((x1 - x0) * SCALE), round((y1 - y0) * SCALE)
    bands = [Image.fromarray(pre[..., i], "F").resize((w, h), Image.LANCZOS) for i in range(4)]
    small = np.dstack([np.asarray(b) for b in bands])
    al = np.clip(small[..., 3], 0.0, 255.0)
    col = small[..., :3] / np.maximum(al[..., None] / 255.0, 1e-3)
    out = np.dstack([np.clip(col, 0.0, 255.0), al]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(OUT / name)
    print(f"{name}: {w}x{h}  src_box={box}")


def tile_strip(rgb, x0, x1, y0, y1, total, keep_left=None):
    """把 x0..x1 这段来回镜像铺到 total 宽；keep_left 是不铺、原样保留的左端起点。"""
    seg = rgb[y0:y1, x0:x1]
    both = np.concatenate([seg, seg[:, ::-1]], axis=1)
    reps = total // both.shape[1] + 2
    strip = np.concatenate([both] * reps, axis=1)
    if keep_left is None:
        return strip[:, :total]
    head = rgb[y0:y1, keep_left:x0]
    return np.concatenate([head, strip], axis=1)[:, :total]


def build_digits():
    """数字图集：和 A5 的数字一样的银色粗斜体。数字是实时变的，A5 里只有 1、8、0，所以整套自己渲染。"""
    glyphs = "0123456789/"
    size = 61
    font = ImageFont.truetype("C:/Windows/Fonts/timesbi.ttf", size)
    cell_w, cell_h, pad = 51, 75, 5
    atlas = np.zeros((cell_h, cell_w * len(glyphs), 4), dtype=np.float32)
    advances = []
    # 上亮、中间一道暗、再亮、下面压暗
    stops = [(0.0, 255), (0.34, 214), (0.5, 136), (0.56, 246), (0.78, 188), (1.0, 112)]
    ramp = np.interp(np.linspace(0.0, 1.0, cell_h), [s[0] for s in stops], [s[1] for s in stops])
    for i, ch in enumerate(glyphs):
        fill = Image.new("L", (cell_w, cell_h), 0)
        edge = Image.new("L", (cell_w, cell_h), 0)
        ImageDraw.Draw(fill).text((pad, 2), ch, font=font, fill=255)
        ImageDraw.Draw(edge).text((pad, 2), ch, font=font, fill=255, stroke_width=2, stroke_fill=255)
        f = np.asarray(fill, dtype=np.float32) / 255.0
        e = np.asarray(edge.filter(ImageFilter.GaussianBlur(0.8)), dtype=np.float32) / 255.0
        grey = ramp[:, None] * f
        alpha = np.maximum(f, e * 0.8)
        cell = np.dstack([grey, grey, grey * 1.02, alpha * 255.0])
        atlas[:, i * cell_w:(i + 1) * cell_w] = cell
        advances.append(round(font.getlength(ch) / 2.0, 1))
    Image.fromarray(np.clip(atlas, 0, 255).astype(np.uint8), "RGBA").save(OUT / "digits.png")
    print("digits.png cell", cell_w, cell_h, "pad", pad, "advance(game px)", dict(zip(glyphs, advances)))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rgb = np.asarray(Image.open(SRC).convert("RGB"), dtype=np.float32).copy()
    h, w, _ = rgb.shape
    size = (w, h)
    lum = rgb.max(axis=2)

    # 透明度：亮的不透明，暗的按亮度淡出（紫光晕）；紧贴亮部的暗部（金属的阴影面）不透明
    soft = np.clip(lum / 60.0, 0.0, 1.0)
    near = np.asarray(Image.fromarray(((lum >= 60) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)),
            dtype=np.float32) / 255.0
    alpha = np.maximum(soft, near * np.clip(lum / 4.0, 0.0, 1.0))
    # 鸦羽本身接近黑色，整片算不透明，羽毛之间纯黑的缝留透明
    alpha = np.maximum(alpha, polygon_mask(size, FEATHERS, 1.5) * np.clip((lum - 2.0) / 3.0, 0.0, 1.0))
    # 文字另外处理
    keep_alpha = alpha.copy()
    keep_rgb = rgb.copy()
    clear_box(alpha, NUMBER)
    clear_box(alpha, LABEL_ULT)
    clear_box(alpha, LABEL_KEYS)

    # 血条槽挖空，只留从十字伸进来的银尖；槽和红血单独出图，画在框下面
    x0, y0, x1, y1 = SLOT
    hollow = rounded_mask(size, SLOT, SLOT_RADIUS, 1.0)
    silver = np.clip((rgb.min(axis=2) - 70.0) / 60.0, 0.0, 1.0)
    silver[:, 300:] = 0.0
    frame_alpha = alpha * (1.0 - hollow) + silver * hollow

    # 绝影五格改成没亮的样子，亮的单独出图
    frame_rgb = rgb.copy()
    cell_masks = []
    for cx0, cx1 in CELLS:
        box = (cx0, CELL_Y[0], cx1, CELL_Y[1])
        m = rounded_mask(size, box, CELL_RADIUS, 1.0)
        cell_masks.append((box, m))
        dark = rgb * 0.0 + np.array([9.0, 7.0, 15.0], dtype=np.float32)
        dark += rgb * np.array([0.05, 0.03, 0.09], dtype=np.float32)
        frame_rgb = frame_rgb * (1.0 - m[..., None]) + dark * m[..., None]
        frame_alpha = np.maximum(frame_alpha, m)

    save(frame_rgb, frame_alpha, FRAME_BOX, "frame.png")

    for i, (box, m) in enumerate(cell_masks):
        save(rgb, m, box, f"cell_{i}.png")

    # 空槽：用红血右边的暗纹铺满
    sw, sh = x1 - x0, y1 - y0
    slot_rgb = np.zeros_like(rgb)
    slot_rgb[y0:y1, x0:x1] = tile_strip(rgb, 560, 1380, y0, y1, sw)
    save(slot_rgb, rounded_mask(size, SLOT, SLOT_RADIUS, 0.8), SLOT, "slot.png")

    # 红血：保留左端原样，中段来回铺满整条，这样血量多少都是同一种质感
    fill_rgb = np.zeros_like(rgb)
    fill_rgb[y0:y1, x0:x1] = tile_strip(rgb, 300, 440, y0, y1, sw, keep_left=x0)
    save(fill_rgb, rounded_mask(size, SLOT, SLOT_RADIUS, 0.8), SLOT, "fill.png")

    # 文字
    save(keep_rgb, keep_alpha, LABEL_ULT, "label_ult.png")
    save(keep_rgb, keep_alpha, LABEL_KEYS, "label_keys.png")
    build_digits()


if __name__ == "__main__":
    main()
