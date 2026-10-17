# 推荐背景方案的明度结构示意：远景软、暗；中景细描边；站立层最亮、粗描边。
# 380 px 角色合成。仅用于设计判断，不是正式美术。
import os
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = r"C:\Users\MECHREVO\Desktop\实际应用到游戏的序列帧"
OUT = os.path.join(HERE, "art")
W, H = 1920, 1080
FLOOR = 800
HERO_H = 380

OUTLINE = (35, 44, 49)


def hero():
    im = Image.open(os.path.join(SRC, r"空中普攻第一段\frame_00013.png")).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
    s = HERO_H / im.height
    return im.resize((round(im.width * s), HERO_H), Image.LANCZOS)


# ── 远景：软边、暗、冷 ──
far = Image.new("RGB", (W, H))
d = ImageDraw.Draw(far)
for y in range(H):
    t = y / H
    d.line([(0, y), (W, y)], fill=(round(30 + 22 * t), round(38 + 24 * t), round(48 + 24 * t)))
for x, w, h in ((80, 140, 420), (330, 90, 560), (560, 180, 380), (1260, 120, 600), (1480, 200, 420), (1760, 110, 520)):
    d.rectangle([x, FLOOR - h, x + w, FLOOR], fill=(50, 62, 72))
    d.polygon([(x, FLOOR - h), (x + w // 2, FLOOR - h - 90), (x + w, FLOOR - h)], fill=(50, 62, 72))
far = far.filter(ImageFilter.GaussianBlur(7))
canvas = far.convert("RGBA")

# ── 中景：赛璐璐 + 细描边 + 两档阴影 ──
mid = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(mid)
for x in (250, 1610):
    d.rectangle([x, 150, x + 70, FLOOR], fill=(86, 102, 108), outline=OUTLINE, width=3)
    d.rectangle([x + 44, 150, x + 70, FLOOR], fill=(68, 82, 88))
    d.rectangle([x - 18, 128, x + 88, 152], fill=(96, 112, 118), outline=OUTLINE, width=3)
# 高窗 + 暖色局部光
for x in (60, 1720):
    d.rectangle([x, 260, x + 130, 640], fill=(58, 70, 76), outline=OUTLINE, width=3)
    d.pieslice([x, 195, x + 130, 325], 180, 360, fill=(58, 70, 76), outline=OUTLINE, width=3)
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([1640, 220, 1960, 700], fill=(232, 165, 75, 90))
glow = glow.filter(ImageFilter.GaussianBlur(60))
canvas.alpha_composite(glow)
d.rectangle([1735, 300, 1835, 620], fill=(232, 165, 75), outline=OUTLINE, width=3)
d.line([(1785, 300), (1785, 620)], fill=OUTLINE, width=3)
d.line([(1735, 460), (1835, 460)], fill=OUTLINE, width=3)
canvas.alpha_composite(mid)

# ── 站立层：最亮、粗描边、硬阴影 ──
d = ImageDraw.Draw(canvas)
d.rectangle([0, FLOOR, W, H], fill=(122, 135, 144))
d.rectangle([0, FLOOR + 34, W, H], fill=(96, 108, 116))
d.line([(0, FLOOR), (W, FLOOR)], fill=OUTLINE, width=6)
d.line([(0, FLOOR + 34), (W, FLOOR + 34)], fill=OUTLINE, width=3)
for x in range(0, W, 240):
    d.line([(x, FLOOR + 34), (x, H)], fill=OUTLINE, width=3)
for x, y in ((560, 470), (1240, 420)):
    d.rectangle([x, y, x + 260, y + 40], fill=(122, 135, 144), outline=OUTLINE, width=5)
    d.rectangle([x + 5, y + 26, x + 255, y + 36], fill=(96, 108, 116))

# ── 角色 ──
h = hero()
canvas.alpha_composite(h, (360, FLOOR - HERO_H + 8))

# ── 前景剪影：链条 ──
d = ImageDraw.Draw(canvas)
for x in (1880, 1910):
    for y in range(0, 420, 36):
        d.ellipse([x - 12, y, x + 12, y + 30], outline=(16, 20, 24), width=7)

canvas = canvas.convert("RGB")
canvas.save(os.path.join(OUT, "bg-recommended-mock.png"))
canvas.convert("L").save(os.path.join(OUT, "bg-recommended-mock-gray.png"))
print("saved")
