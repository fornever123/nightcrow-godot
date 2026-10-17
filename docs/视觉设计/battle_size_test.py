# 1920x1080 战场同屏对比：同一角色在不同显示尺寸下的画面占位。
# 仅用于设计判断，不修改源图。
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = r"C:\Users\MECHREVO\Desktop\实际应用到游戏的序列帧"
OUT = os.path.join(HERE, "art")

W, H = 1920, 1080
GROUND_Y = 812
SIZES = [220, 320, 420, 520]

SKY_TOP = (14, 15, 34)
SKY_BOT = (42, 34, 71)
MID = (35, 36, 69)
GROUND = (60, 56, 102)
EDGE = (124, 111, 191)
PLAT = (74, 68, 120)


def load(rel):
    im = Image.open(os.path.join(SRC, rel)).convert("RGBA")
    bbox = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    return im.crop(bbox)


def fit(im, target_h):
    s = target_h / im.height
    return im.resize((max(1, round(im.width * s)), target_h), Image.LANCZOS)


def make_bg():
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / H
        d.line(
            [(0, y), (W, y)],
            fill=(
                round(SKY_TOP[0] + (SKY_BOT[0] - SKY_TOP[0]) * t),
                round(SKY_TOP[1] + (SKY_BOT[1] - SKY_TOP[1]) * t),
                round(SKY_TOP[2] + (SKY_BOT[2] - SKY_TOP[2]) * t),
            ),
        )
    # 中景柱
    for x in (300, 700, 1180, 1560):
        d.rectangle([x, 190, x + 56, GROUND_Y], fill=MID)
    # 站立层
    d.rectangle([0, GROUND_Y, W, H], fill=GROUND)
    d.rectangle([0, GROUND_Y, W, GROUND_Y + 5], fill=EDGE)
    # 悬浮平台
    for x, y in ((430, 520), (1320, 470)):
        d.rectangle([x, y, x + 240, y + 26], fill=PLAT)
        d.rectangle([x, y, x + 240, y + 4], fill=EDGE)
    return bg.convert("RGBA")


def mock(h):
    bg = make_bg()
    hero = fit(load(r"空中普攻第一段\frame_00013.png"), h)
    # 左侧角色，脚底贴地
    bg.alpha_composite(hero, (330, GROUND_Y - h + 6))

    # 右侧敌人占位（同高）
    d = ImageDraw.Draw(bg)
    ex, ew = 1080, max(60, round(h * 0.5))
    d.rounded_rectangle(
        [ex, GROUND_Y - h, ex + ew, GROUND_Y],
        radius=int(ew * 0.4), fill=(42, 27, 24), outline=(227, 192, 138), width=3,
    )
    d.rectangle([ex + ew // 4, GROUND_Y - h + int(h * 0.18), ex + ew * 3 // 4, GROUND_Y - h + int(h * 0.18) + 12],
                fill=(194, 84, 60))

    # 地面参考线与尺寸标注
    d.line([(0, GROUND_Y), (W, GROUND_Y)], fill=EDGE, width=2)
    d.line([(40, GROUND_Y - h), (40, GROUND_Y)], fill=(255, 209, 102), width=3)
    d.text((52, GROUND_Y - h - 6), f"{h}px", fill=(255, 209, 102))
    return bg.convert("RGB")


tiles = [mock(s).resize((960, 540), Image.LANCZOS) for s in SIZES]
grid = Image.new("RGB", (1920, 1080), (10, 10, 18))
for i, t in enumerate(tiles):
    grid.paste(t, ((i % 2) * 960, (i // 2) * 540))
grid.save(os.path.join(OUT, "battle-size-compare.png"))
print("对比图已生成", grid.size, "左上/右上/左下/右下 =", SIZES)
