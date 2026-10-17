# 背景明度 × 色相 可读性测试：380 px 角色合成到不同背景上。
# 仅用于设计判断，不修改源图。
import os
from PIL import Image, ImageDraw, ImageFont
import colorsys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = r"C:\Users\MECHREVO\Desktop\实际应用到游戏的序列帧"
OUT = os.path.join(HERE, "art")
HERO_H = 380

im = Image.open(os.path.join(SRC, r"空中普攻第一段\frame_00013.png")).convert("RGBA")
im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
s = HERO_H / im.height
hero = im.resize((round(im.width * s), HERO_H), Image.LANCZOS)

# 行：色相；列：明度
HUES = [
    ("紫（与角色同色）", 0.75, 0.30),
    ("中性灰", 0.0, 0.0),
    ("青灰", 0.52, 0.22),
    ("琥珀（紫的补色）", 0.10, 0.38),
]
VALUES = [0.12, 0.28, 0.44, 0.60, 0.76]

CW, CH = 640, 470
grid = Image.new("RGB", (CW * len(VALUES), CH * len(HUES) + 60), (12, 12, 18))
d = ImageDraw.Draw(grid)
try:
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 26)
except OSError:
    font = ImageFont.load_default()

for c, v in enumerate(VALUES):
    d.text((c * CW + 20, 16), f"背景明度 {round(v * 100)}%", fill=(220, 214, 240), font=font)

for r, (name, h, sat) in enumerate(HUES):
    for c, v in enumerate(VALUES):
        rgb = tuple(round(x * 255) for x in colorsys.hsv_to_rgb(h, sat, v))
        cell = Image.new("RGBA", (CW, CH), rgb + (255,))
        cell.alpha_composite(hero, ((CW - hero.width) // 2, CH - HERO_H - 30))
        grid.paste(cell.convert("RGB"), (c * CW, 60 + r * CH))
    d.text((20, 60 + r * CH + 16), name, fill=(255, 255, 255), font=font,
           stroke_width=3, stroke_fill=(0, 0, 0))

grid.save(os.path.join(OUT, "bg-value-hue-test.png"))
small = grid.resize((grid.width // 2, grid.height // 2), Image.LANCZOS)
small.save(os.path.join(OUT, "bg-value-hue-test-small.png"))
print("saved", grid.size)
