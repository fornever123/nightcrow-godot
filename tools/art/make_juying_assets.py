#!/usr/bin/env python3
"""大招「绝影」的两张 AI 素材 → 游戏用图（只用 Pillow，不需要 numpy / opencv）。
用法：python tools/art/make_juying_assets.py [源目录=tools/art/src/ult/juying] [输出目录=assets/image/ult]
  cutin.png（品红底立绘）→ cutin.png：只抠和画面边缘连通的品红 + 几乎纯品红的小块（剑光、眼睛的紫离纯品红远，不会被抠），
                          边缘 2px 按品红距离给半透明并反解前景色（去粉边）。
  title.png（白纸黑墨「绝影」）→ title.png：墨迹当遮罩，白→浅紫竖向渐变字 + 深墨细描边 + 紫色外光（和旧题字同一套样式）。
                                 seal.png：从题字左半边取「绝」字，做成朱红小方印（游戏里晚几帧盖下去）。"""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SRC = sys.argv[1] if len(sys.argv) > 1 else "tools/art/src/ult/juying"
OUT = sys.argv[2] if len(sys.argv) > 2 else "assets/image/ult"
MAGENTA = (255, 0, 255)


def magenta_dist(px):
    r, g, b = px[:3]
    return math.sqrt((255 - r) ** 2 + g ** 2 + (255 - b) ** 2) / 255.0


def make_cutin():
    im = Image.open(os.path.join(SRC, "cutin.png")).convert("RGB")
    w, h = im.size
    src = im.load()
    dist = [[0.0] * w for _ in range(h)]
    cand = Image.new("L", (w, h), 0)
    cp = cand.load()
    for y in range(h):
        row = dist[y]
        for x in range(w):
            d = magenta_dist(src[x, y])
            row[x] = d
            if d < 0.32:
                cp[x, y] = 255
    # 和画面边缘连通的候选 = 背景（灌成 128）
    seeds = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    for s in seeds:
        if cp[s] == 255:
            ImageDraw.floodfill(cand, s, 128)
    bg = Image.new("L", (w, h), 0)
    bp = bg.load()
    for y in range(h):
        row = dist[y]
        for x in range(w):
            if cp[x, y] == 128 or row[x] < 0.12:
                bp[x, y] = 255
    ring = ImageChops.subtract(bg.filter(ImageFilter.MaxFilter(5)), bg)
    rp = ring.load()
    out = im.convert("RGBA")
    op = out.load()
    for y in range(h):
        row = dist[y]
        for x in range(w):
            if bp[x, y]:
                op[x, y] = (0, 0, 0, 0)
            elif rp[x, y]:
                a = min(max((row[x] - 0.30) / 0.45, 0.0), 1.0)
                if a <= 0.0:
                    op[x, y] = (0, 0, 0, 0)
                    continue
                r, g, b = src[x, y]
                fg = [min(max((c - m * (1.0 - a)) / a, 0.0), 255.0) for c, m in zip((r, g, b), MAGENTA)]
                op[x, y] = (int(fg[0]), int(fg[1]), int(fg[2]), int(a * 255))
    box = out.getbbox()
    out.save(os.path.join(OUT, "cutin.png"))
    print("cutin", out.size, "content bbox", box)


def ink_mask(im):
    # 墨越黑越不透明；纸色（≥235）完全透明
    gray = im.convert("L")
    return gray.point(lambda v: int(min(max((235 - v) / 175.0, 0.0), 1.0) * 255))


def make_title():
    src = Image.open(os.path.join(SRC, "title.png")).convert("RGB")
    mask = ink_mask(src)
    box = mask.point(lambda v: 255 if v > 40 else 0).getbbox()
    mask = mask.crop(box)
    W, H = 1280, 560
    k = min((W - 120) / mask.width, (H - 80) / mask.height)
    mask = mask.resize((int(mask.width * k), int(mask.height * k)), Image.LANCZOS)
    m = Image.new("L", (W, H), 0)
    m.paste(mask, ((W - mask.width) // 2, (H - mask.height) // 2))
    glow_m = m.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(14))
    glow = Image.new("RGBA", (W, H), (164, 135, 255, 0))
    glow.putalpha(glow_m.point(lambda a: int(a * 0.85)))
    edge = Image.new("RGBA", (W, H), (27, 21, 38, 255))
    edge.putalpha(m.filter(ImageFilter.MaxFilter(9)))
    fill = Image.new("RGBA", (W, H))
    fp = fill.load()
    for y in range(H):
        t = y / (H - 1)
        col = (int(255 - 34 * t), int(252 - 42 * t), int(242 + 13 * t), 255)
        for x in range(W):
            fp[x, y] = col
    fill.putalpha(m)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    img = Image.alpha_composite(img, glow)
    img = Image.alpha_composite(img, edge)
    img = Image.alpha_composite(img, fill)
    img.save(os.path.join(OUT, "title.png"))
    print("title", img.size)
    # 印章：取左半边的「绝」
    full = ink_mask(src)
    fb = full.point(lambda v: 255 if v > 40 else 0).getbbox()
    mid = (fb[0] + fb[2]) // 2
    left = full.crop((fb[0], fb[1], mid, fb[3]))
    lb = left.point(lambda v: 255 if v > 40 else 0).getbbox()
    glyph = left.crop(lb)
    S = 128
    gk = 92 / max(glyph.width, glyph.height)
    glyph = glyph.resize((max(1, int(glyph.width * gk)), max(1, int(glyph.height * gk))), Image.LANCZOS)
    seal = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(seal)
    sd.rounded_rectangle((5, 5, S - 5, S - 5), 10, fill=(200, 52, 44, 240))
    txt = Image.new("RGBA", glyph.size, (255, 236, 220, 255))
    txt.putalpha(glyph)
    seal.alpha_composite(txt, ((S - glyph.width) // 2, (S - glyph.height) // 2))
    rnd = random.Random(7)
    sp = seal.load()
    for y in range(S):
        for x in range(S):
            if rnd.random() < 0.06:
                r, g, b, a = sp[x, y]
                sp[x, y] = (r, g, b, 0)
    seal = seal.rotate(-6, resample=Image.BICUBIC, expand=True)
    seal.save(os.path.join(OUT, "seal.png"))
    print("seal", seal.size)


if __name__ == "__main__":
    make_cutin()
    make_title()
