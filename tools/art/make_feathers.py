#!/usr/bin/env python3
"""大招「绝影」的羽毛贴图（3 种，和鸦翼同款配色：根部黑 → 羽尖深蓝紫 → 亮紫，边缘一道白紫高光）。
用法：python tools/art/make_feathers.py [输出目录=assets/image/ult]"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/image/ult"
SS = 4
W, H = 200, 80


def lerp(a, b, t):
    return tuple(int(x + (y - x) * t) for x, y in zip(a, b))


def grad(t):
    stops = [(0.0, (12, 8, 22)), (0.45, (22, 14, 50)), (0.72, (52, 30, 170)), (0.9, (140, 70, 240)), (1.0, (200, 170, 255))]
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if t <= t1:
            return lerp(c0, c1, (t - t0) / max(t1 - t0, 1e-6))
    return stops[-1][1]


def feather(seed, curve, width, notches):
    rng = random.Random(seed)
    w, h = W * SS, H * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    n = 60
    top, bot = [], []
    for i in range(n + 1):
        t = i / n
        x = (0.04 + 0.92 * t) * w
        cy = h * 0.5 + math.sin(t * math.pi) * curve * h
        half = width * h * (math.sin(math.pi * min(1.0, t * 1.08)) ** 0.7) * (0.55 + 0.45 * t)
        # 羽枝缺口：外缘偶尔凹进去一点
        nt = 1.0 - (0.35 if any(abs(t - k) < 0.025 for k in notches) else 0.0)
        top.append((x, cy - half * nt))
        bot.append((x, cy + half * (0.8 if t > 0.5 else 1.0)))
    # 按 x 方向渐变上色：逐列竖条
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).polygon(top + bot[::-1], fill=255)
    col = Image.new("RGBA", (w, h))
    cd = ImageDraw.Draw(col)
    for x in range(w):
        cd.line([(x, 0), (x, h)], fill=grad(min(1.0, max(0.0, (x / w - 0.04) / 0.92))) + (255,))
    img.paste(col, (0, 0), mask)
    # 羽枝细纹 + 羽轴
    for i in range(26):
        t = 0.15 + 0.8 * i / 26
        x = (0.04 + 0.92 * t) * w
        cy = h * 0.5 + math.sin(t * math.pi) * curve * h
        d.line([(x, cy), (x + w * 0.03, top[int(t * n)][1] + 4 * SS)], fill=(255, 255, 255, 26), width=SS)
    d.line([(top[i][0], h * 0.5 + math.sin(i / n * math.pi) * curve * h) for i in range(n + 1)], fill=(200, 180, 255, 120), width=2 * SS)
    # 上缘一道白紫高光
    d.line(top[int(n * 0.45):], fill=(225, 210, 255, 200), width=2 * SS)
    # 外轮廓：细紫色描边
    edge = mask.filter(ImageFilter.MaxFilter(2 * SS + 1))
    rim = Image.new("RGBA", (w, h), (150, 90, 255, 0))
    rim.putalpha(edge.point(lambda v: int(v * 0.9)))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(rim)
    out.alpha_composite(img)
    return out.resize((W, H), Image.LANCZOS)


for k, (seed, curve, width, notches) in enumerate([(1, -0.08, 0.3, [0.6, 0.78]), (2, 0.1, 0.36, [0.5]), (3, -0.14, 0.26, [0.7, 0.85, 0.92])]):
    f = feather(seed, curve, width, notches)
    f.save(f"{OUT}/feather_{k + 1}.png")
    print("saved", f"{OUT}/feather_{k + 1}.png", f.size)
