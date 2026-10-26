import os, sys
from PIL import Image

PROJ = r"E:/00game/nightcrow-godot/docs/视觉设计/layers/cloud_causeway/"
OUT = r"E:/00game/nightcrow-godot/docs/视觉设计/work/keyed/"
os.makedirs(OUT, exist_ok=True)

FILES = {
    "05_ground_v1": "7.webp",
    "07_platforms_v1": "8.webp",
    "06_tower_v1": "9.webp",
    "04_mid_b_v1": "10.webp",
    "03_mid_a_v1": "11.webp",
    "02_clouds_v1": "12.webp",
    "08_foreground_v1": "13.webp",
}


def key_magenta(im):
    """洋红抠图：alpha 按“洋红程度”估计，再把边缘像素里混进去的洋红减掉。"""
    px = im.convert("RGB").get_flattened_data()
    out = []
    pink = 0
    for R, G, B in px:
        d = (min(R, B) - G) / 255.0
        a = 1.0 - (d - 0.15) / 0.7
        if a >= 1.0:
            out.append((R, G, B, 255))
            continue
        if a <= 0.003:
            out.append((0, 0, 0, 0))
            continue
        r = (R / 255.0 - (1 - a)) / a
        g = (G / 255.0) / a
        b = (B / 255.0 - (1 - a)) / a
        r, g, b = [min(1.0, max(0.0, v)) for v in (r, g, b)]
        if r > g + 0.25 and b > g + 0.25:
            pink += 1
        out.append((int(r * 255), int(g * 255), int(b * 255), int(a * 255)))
    o = Image.new("RGBA", im.size)
    o.putdata(out)
    return o, pink


def key_black(im):
    """黑底云：亮度当 alpha，颜色除回去（滤色叠加的等价透明图）。"""
    px = im.convert("RGB").get_flattened_data()
    out = []
    for R, G, B in px:
        m = max(R, G, B)
        if m < 6:
            out.append((0, 0, 0, 0))
            continue
        a = m / 255.0
        out.append((int(R / a), int(G / a), int(B / a), m))
    o = Image.new("RGBA", im.size)
    o.putdata(out)
    return o


for name, src in FILES.items():
    im = Image.open(PROJ + name + ".webp")   # 原图已存档在 layers/cloud_causeway/
    if name.startswith("02_clouds"):
        o = key_black(im)
        pink = 0
    else:
        o, pink = key_magenta(im)
    o.save(OUT + name + ".png")
    print(name, im.size, "bbox", o.getbbox(), "pink-left", pink)
