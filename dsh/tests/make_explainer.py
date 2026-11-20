from PIL import Image, ImageDraw, ImageFont
import math

OUT = r"E:/00game/nightcrow-godot/dsh/docs/错拍-讲解图.png"
FB = r"C:/Windows/Fonts/msyhbd.ttc"
FR = r"C:/Windows/Fonts/msyh.ttc"

W, H = 1280, 720
img = Image.new("RGB", (W, H), (7, 8, 15))
d = ImageDraw.Draw(img, "RGBA")

f_h = ImageFont.truetype(FB, 32)
f_m = ImageFont.truetype(FB, 21)
f_s = ImageFont.truetype(FR, 18)
f_n = ImageFont.truetype(FB, 17)

GROUND = 446

# 背景雨
for i in range(150):
    x = (i * 149) % W
    y = 80 + (i * 97) % 330
    d.line([(x, y), (x - 7, y + 24)], fill=(118, 138, 178, 22), width=1)
d.rectangle([0, GROUND, W, H], fill=(13, 15, 24, 255))
d.line([(0, GROUND), (W, GROUND)], fill=(76, 84, 112, 255), width=2)


def figure(cx, feet, body, edge, h, w, face, ghost=False, glow=None):
    head_r = h * 0.10
    head_y = feet - h + head_r * 1.15
    if glow:
        for k in range(3):
            g = 10 + k * 8
            d.ellipse([cx - w * 0.8 - g, feet - h - g, cx + w * 0.8 + g, feet + 6 + g],
                      outline=(*glow[:3], 34 - k * 8), width=2)
    # 腿
    lw = max(7, int(h * 0.055))
    d.line([(cx - w * 0.20, feet - h * 0.30), (cx - w * 0.30, feet)], fill=body, width=lw)
    d.line([(cx + w * 0.20, feet - h * 0.30), (cx + w * 0.30, feet)], fill=body, width=lw)
    # 披风
    d.polygon([
        (cx - w * 0.55, feet - h * 0.72),
        (cx - w * 1.00, feet - h * 0.08),
        (cx - w * 0.44, feet - h * 0.02),
        (cx - w * 0.10, feet - h * 0.44),
    ], fill=(*body[:3], max(0, body[3] - 25)))
    # 躯干
    d.polygon([
        (cx - w * 0.50, feet - h * 0.28),
        (cx + w * 0.50, feet - h * 0.28),
        (cx + w * 0.34, feet - h * 0.76),
        (cx - w * 0.34, feet - h * 0.76),
    ], fill=body, outline=edge, width=2)
    # 脖子 + 头
    d.line([(cx, feet - h * 0.76), (cx, feet - h * 0.84)], fill=edge, width=3)
    d.ellipse([cx - head_r, head_y - head_r, cx + head_r, head_y + head_r], fill=body, outline=edge, width=2)
    # 刀
    hx, hy = cx + w * 0.36 * face, feet - h * 0.60
    d.line([(hx, hy), (hx + 82 * face, hy - 52)], fill=(232, 234, 246, 240), width=4)
    d.line([(hx, hy), (hx + 82 * face, hy - 52)], fill=(126, 152, 226, 110), width=1)
    if ghost:
        for k in range(26):
            a0 = math.tau * k / 26
            a1 = a0 + math.tau / 52
            d.arc([cx - w * 0.95, feet - h - 16, cx + w * 0.95, feet + 8],
                  math.degrees(a0), math.degrees(a1), fill=edge, width=2)


def tag(x, y, text, color, font=f_m, bg=(8, 10, 18, 236)):
    tw = d.textlength(text, font=font)
    d.rounded_rectangle([x - 8, y - 6, x + tw + 10, y + 30], 7, fill=bg, outline=(*color[:3], 150), width=1)
    d.text((x, y), text, font=font, fill=color)


def arrow(x0, y0, x1, y1, color, width=2):
    d.line([x0, y0, x1, y1], fill=color, width=width)
    ang = math.atan2(y1 - y0, x1 - x0)
    for k in (0.5, -0.5):
        d.line([x1, y1, x1 - 13 * math.cos(ang + k), y1 - 13 * math.sin(ang + k)], fill=color, width=width)


# 标题
d.text((40, 22), "你的刀，砍不到「现在」", font=f_h, fill=(243, 241, 251))
d.text((40, 68), "每个敌人都有两个：走在前面的紫色影子，和慢半拍的黑色身体。", font=f_m, fill=(188, 186, 204))

# 玩家
PX = 186
figure(PX, GROUND, (30, 38, 70, 255), (140, 205, 255, 255), 152, 42, 1, glow=(120, 190, 255, 255))
tag(PX - 22, GROUND - 26, "你", (150, 210, 255, 255), f_n)

# 影子（未来）与本体（过去）
GX, BX = 636, 846
figure(GX, GROUND, (146, 108, 250, 132), (204, 170, 255, 255), 168, 48, -1, ghost=True, glow=(170, 130, 255, 255))
figure(BX, GROUND, (34, 36, 60, 255), (132, 124, 172, 255), 168, 48, -1)

# 刀光弧：玩家 → 影子
pts = []
for i in range(25):
    t = i / 24
    pts.append((PX + 60 + (GX - PX - 96) * t, 352 - 74 * math.sin(math.pi * t)))
d.line(pts, fill=(206, 166, 255, 190), width=4)
d.line(pts, fill=(255, 252, 255, 110), width=1)
arrow(pts[-3][0], pts[-3][1], GX - 6, 300, (214, 176, 255, 235), 2)

# 打本体的叉
d.line([(BX - 30, 286), (BX + 30, 350)], fill=(255, 86, 86, 240), width=5)
d.line([(BX + 30, 286), (BX - 30, 350)], fill=(255, 86, 86, 240), width=5)

# 上方两个标签
tag(470, 116, "它 0.6 秒后 · 砍这里", (206, 168, 255, 255), f_m)
arrow(640, 152, GX + 4, 236, (184, 146, 255, 190), 2)
tag(760, 172, "它 0.6 秒前 · 砍不中", (255, 132, 132, 255), f_m)
arrow(880, 208, BX + 6, 258, (255, 110, 110, 190), 2)

# 两个之间的时间
d.line([(GX + 46, GROUND - 34), (BX - 50, GROUND - 34)], fill=(206, 182, 255, 170), width=2)
for k in range(7):
    x = GX + 46 + (BX - 50 - GX - 46) * (k / 6)
    d.ellipse([x - 2.5, GROUND - 36.5, x + 2.5, GROUND - 31.5], fill=(224, 206, 255, 220))
d.text((BX - 34, GROUND - 44), "0.6 秒", font=f_n, fill=(214, 196, 255))

# 敌人朝左走


# 底部
by = 512
d.rectangle([0, by - 8, W, H], fill=(10, 11, 19, 255))
d.line([(0, by - 8), (W, by - 8)], fill=(58, 56, 84, 255), width=1)
d.text((40, by + 16), "砍中一下，紫色就往黑色身上靠一格", font=f_h, fill=(238, 230, 250))

steps = ["0.60", "0.50", "0.40", "0.30", "0.20", "0.10", "0.00"]
bx0, bw = 44, 118
for i, s in enumerate(steps):
    x = bx0 + i * bw
    col = (146, 118, 250, 235) if i < 6 else (240, 244, 255, 255)
    d.rounded_rectangle([x, by + 72, x + bw - 16, by + 116], 8, fill=(*col[:3], 40), outline=col, width=2)
    d.text((x + 22, by + 82), s, font=f_n, fill=col)
    if i < 6:
        d.text((x + bw - 10, by + 86), "→", font=f_n, fill=(146, 136, 186))
d.text((40, by + 134), "靠到 0.00：两个合成一个，刀光变白、伤害 ×1.5 —— 这叫「合拍」，你追上了时间。", font=f_m, fill=(232, 228, 242))
d.text((40, by + 176), "敌人砍你的时候正好反过来：影子先举刀（你能提前 0.6 秒看见），但真正伤到你的是黑色那刀。", font=f_s, fill=(158, 158, 180))

img.save(OUT)
print("saved", OUT, img.size)

