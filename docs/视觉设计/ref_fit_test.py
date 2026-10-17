# 把 380 px 角色合成进参考视频的遗迹场景，对比原画 / 轻度像素化 / 像素化 + 描边。
# 仅用于设计判断，参考帧来自视频截图，源角色图不修改。
import os
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = r"C:\Users\MECHREVO\Desktop\实际应用到游戏的序列帧"
OUT = os.path.join(HERE, "art")

bg = Image.open(os.path.join(HERE, "ref", "ref-ruins.jpg")).convert("RGBA")
bg = bg.resize((1920, 1080), Image.LANCZOS)
FLOOR = 768  # 参考场景石板路的行走线（1080 坐标）
HERO_H = 380


def hero_src():
    im = Image.open(os.path.join(SRC, r"空中普攻第一段\frame_00013.png")).convert("RGBA")
    return im.crop(im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())


def fit(im, h):
    s = h / im.height
    return im.resize((round(im.width * s), h), Image.LANCZOS)


def pixelize(im, block):
    """把角色降到 1/block 分辨率再最近邻放回：硬边像素块，颜色量化减少 AI 涂抹感。"""
    small = im.resize((max(1, im.width // block), max(1, im.height // block)), Image.LANCZOS)
    a = small.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    rgb = small.convert("RGB").quantize(colors=48, method=Image.Quantize.MEDIANCUT).convert("RGB")
    small = rgb.convert("RGBA")
    small.putalpha(a)
    return small.resize((small.width * block, small.height * block), Image.NEAREST)


def rim(im, color=(214, 236, 230, 255), width=3):
    """外轮廓光：向外扩一圈，让深色角色从深色背景里分离。"""
    a = im.getchannel("A")
    grown = a.filter(ImageFilter.MaxFilter(width * 2 + 1))
    ring = Image.new("RGBA", im.size, color)
    ring.putalpha(grown)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.alpha_composite(ring)
    out.alpha_composite(im)
    return out


base = fit(hero_src(), HERO_H)
variants = [
    ("原画", base),
    ("轻度像素化 · 块 3px", pixelize(base, 3)),
    ("像素化 3px + 轮廓光", rim(pixelize(base, 3))),
]

tiles = []
for name, h in variants:
    canvas = bg.copy()
    canvas.alpha_composite(h, (520, FLOOR - h.height + 6))
    tiles.append(canvas.convert("RGB"))

# 1) 三联整图（缩到 1/2 便于浏览）
strip = Image.new("RGB", (960 * 3, 540), (10, 10, 10))
for i, t in enumerate(tiles):
    strip.paste(t.resize((960, 540), Image.LANCZOS), (i * 960, 0))
strip.save(os.path.join(OUT, "ref-fit-compare.png"))

# 2) 角色特写（原尺寸裁切），看像素化后的画法是否和场景笔触一致
crops = [t.crop((470, FLOOR - HERO_H - 40, 1130, FLOOR + 30)) for t in tiles]
cw = sum(c.width for c in crops)
closeup = Image.new("RGB", (cw, crops[0].height), (10, 10, 10))
x = 0
for c in crops:
    closeup.paste(c, (x, 0))
    x += c.width
closeup.save(os.path.join(OUT, "ref-fit-closeup.png"))
print("saved", strip.size, closeup.size)
