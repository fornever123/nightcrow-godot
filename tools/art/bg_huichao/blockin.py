"""地图一第 1 处回潮区的构图草图（block-in）：只有大色块，位置按游戏规格。给 GPT 当“照这个布局画”的底稿。"""
import math, random
from PIL import Image, ImageDraw, ImageFilter

OUT = r"E:/00game/nightcrow-godot/docs/视觉设计/blockin/"
import os
os.makedirs(OUT, exist_ok=True)
W, H = 1672, 941
S = W / 1280.0                      # 游戏屏幕像素 → 草图像素


def gx(x_world):                    # 竞技场中心在屏幕中间；世界 2 单位 = 屏幕 1 像素
    return (640 + x_world / 2) * S


def gy(y_world):                    # 地面 580 → 屏幕 580；镜头中心世界 y 140 → 屏幕 360
    return ((y_world - 140) / 2 + 360) * S


im = Image.new("RGB", (W, H))
d = ImageDraw.Draw(im)
HOR = int(0.56 * H)

# 天空：上黑下亮的靛蓝
for y in range(H):
    t = min(1.0, y / HOR)
    c = (int(10 + 50 * t), int(14 + 62 * t), int(32 + 80 * t))
    d.line([(0, y), (W, y)], fill=c)
random.seed(3)
for _ in range(260):
    x, y = random.randrange(W), random.randrange(int(H * 0.5))
    v = random.randint(120, 220)
    d.point((x, y), fill=(v, v, v + 10))

# 巨环：斜着看的椭圆，断成几段，近（左）粗远（右）细，内侧一条青光
ring = Image.new("RGBA", (W, H), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring)
cx, cy, rx, ry, rot = 0.80 * W, 0.24 * H, 0.15 * W, 0.34 * H, math.radians(-22)
gaps = [(70, 88), (150, 160), (215, 232), (300, 312)]
for deg in range(0, 360, 1):
    if any(a <= deg < b for a, b in gaps):
        continue
    a = math.radians(deg)
    px, py = rx * math.cos(a), ry * math.sin(a)
    x = cx + px * math.cos(rot) - py * math.sin(rot)
    y = cy + px * math.sin(rot) + py * math.cos(rot)
    near = 0.5 + 0.5 * (-math.cos(a))           # 左边（a≈180°）是近侧
    thick = 10 + 26 * near
    shade = int(70 + 35 * near)
    rd.ellipse([x - thick / 2, y - thick / 2, x + thick / 2, y + thick / 2], fill=(shade, shade + 6, shade + 22, 255))
im.paste(ring, (0, 0), ring)
teal = Image.new("RGBA", (W, H), (0, 0, 0, 0))
td = ImageDraw.Draw(teal)
for deg in range(0, 360, 1):
    if any(a <= deg < b for a, b in gaps):
        continue
    a = math.radians(deg)
    px, py = (rx - 14) * math.cos(a), (ry - 14) * math.sin(a)
    x = cx + px * math.cos(rot) - py * math.sin(rot)
    y = cy + px * math.sin(rot) + py * math.cos(rot)
    td.ellipse([x - 3, y - 3, x + 3, y + 3], fill=(90, 210, 200, 200))
teal = teal.filter(ImageFilter.GaussianBlur(2))
im.paste(teal, (0, 0), teal)
# 几块断落的碎石
for (bx, by, s) in [(0.70, 0.52, 26), (0.75, 0.56, 18), (0.88, 0.50, 22), (0.66, 0.44, 14)]:
    d.rectangle([bx * W, by * H, bx * W + s * 1.4, by * H + s], fill=(80, 88, 108))
# 月亮：环外左上
mx, my, mr = 0.62 * W, 0.11 * H, 0.022 * H
d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(225, 230, 240))

# 远山：地平线上低矮的一条
pts = [(0, HOR + 10)]
random.seed(5)
x = 0
while x <= W:
    pts.append((x, HOR - random.randint(10, 46)))
    x += random.randint(40, 90)
pts += [(W, HOR + 10)]
d.polygon(pts, fill=(62, 76, 108))

# 云海：战斗带背后最亮、最安静
for y in range(HOR, int(0.80 * H)):
    t = (y - HOR) / (0.80 * H - HOR)
    v = 1 - abs(t - 0.35) * 1.2
    c = (int(78 + 40 * v), int(92 + 44 * v), int(128 + 44 * v))
    d.line([(0, y), (W, y)], fill=c)
# 环下的青色云顶
glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([0.62 * W, 0.46 * H, 0.98 * W, 0.66 * H], fill=(60, 150, 150, 110))
glow = glow.filter(ImageFilter.GaussianBlur(40))
im.paste(glow, (0, 0), glow)

# 右边中景：一条远去的断渡槽（拱的剪影）
ay0, ay1 = 0.47 * H, 0.60 * H
d.rectangle([0.52 * W, ay0, 0.74 * W, ay0 + 10], fill=(56, 66, 92))
for i in range(8):
    x0 = 0.52 * W + i * 0.0275 * W
    d.rectangle([x0, ay0, x0 + 9, ay1], fill=(56, 66, 92))

# 左边中景：石针 + 细高塔（暖灯一点）
d.polygon([(0.03 * W, 0.78 * H), (0.085 * W, 0.24 * H), (0.105 * W, 0.24 * H), (0.17 * W, 0.78 * H)], fill=(34, 40, 60))
d.rectangle([0.085 * W, 0.12 * H, 0.105 * W, 0.25 * H], fill=(30, 36, 54))
d.polygon([(0.08 * W, 0.12 * H), (0.095 * W, 0.06 * H), (0.11 * W, 0.12 * H)], fill=(30, 36, 54))
d.ellipse([0.091 * W, 0.135 * H, 0.099 * W, 0.15 * H], fill=(245, 175, 90))
d.polygon([(0.17 * W, 0.78 * H), (0.20 * W, 0.42 * H), (0.215 * W, 0.42 * H), (0.24 * W, 0.78 * H)], fill=(38, 45, 66))
d.line([(0.105 * W, 0.30 * H), (0.155 * W, 0.36 * H), (0.205 * W, 0.43 * H)], fill=(26, 30, 44), width=3)

# 透视桥面：远边（矮墙）y = 地面线上方一点，近边在下面
floor = gy(580)
far, near = floor - 0.045 * H, floor + 0.07 * H
for y in range(int(far), int(near)):
    t = (y - far) / (near - far)
    c = (int(52 + 34 * t), int(58 + 34 * t), int(76 + 34 * t))
    d.line([(0, y), (W, y)], fill=c)
random.seed(9)
x = 0
while x < W:                                   # 远边的矮墙残块
    w_ = random.randint(30, 70)
    h_ = random.choice([0, 14, 22, 30])
    if h_:
        d.rectangle([x, far - h_, x + w_, far], fill=(48, 54, 72))
    x += w_ + random.randint(20, 80)
d.line([(0, near), (W, near)], fill=(150, 160, 185), width=3)
d.rectangle([0, near, W, H], fill=(30, 34, 48))   # 桥的立面
for i in range(-1, 5):                         # 拱洞里露出下面的云
    ax = i * 0.29 * W + 0.12 * W
    d.ellipse([ax, near + 0.05 * H, ax + 0.2 * W, near + 0.5 * H], fill=(70, 82, 112))

# 平台：一层两块（左右）、二层两块（左右）、三层断塔（最右）；中间留空
def platform(x0, x1, y_world, support):
    top = gy(y_world)
    thick = 0.035 * H
    d.rectangle([gx(x0), top - 6, gx(x1), top + 4], fill=(120, 128, 150))     # 顶面（亮）
    d.rectangle([gx(x0), top + 4, gx(x1), top + thick], fill=(52, 58, 78))    # 正面
    if support == "arch":
        for sx in (x0 + 40, x1 - 80):
            d.rectangle([gx(sx), top + thick, gx(sx + 40), far], fill=(46, 52, 70))
        d.ellipse([gx(x0 + 80), top + thick + 6, gx(x1 - 80), far + 40], fill=(70, 82, 112))
    elif support == "columns":
        for sx in (x0 + 30, x1 - 70):
            d.rectangle([gx(sx), top + thick, gx(sx + 40), far], fill=(46, 52, 70))


platform(-1100, -700, 360, "arch")
platform(700, 1100, 360, "arch")
platform(-620, -360, 140, "columns")
platform(360, 620, 140, "columns")
# 三层：最右的断塔（实心，顶面在 L3）
tt = gy(-80)
d.rectangle([gx(1080), tt + 4, gx(1240), far], fill=(48, 54, 74))
d.rectangle([gx(1080), tt - 6, gx(1240), tt + 4], fill=(122, 130, 152))
d.ellipse([gx(1135), tt + 0.06 * H, gx(1185), tt + 0.14 * H], fill=(26, 30, 44))

# 前景：下两角近黑剪影、左上垂藤
d.polygon([(0, H), (0, 0.80 * H), (0.06 * W, 0.78 * H), (0.13 * W, 0.86 * H), (0.16 * W, H)], fill=(8, 9, 14))
d.polygon([(W, H), (W, 0.76 * H), (0.95 * W, 0.80 * H), (0.90 * W, 0.90 * H), (0.86 * W, H)], fill=(8, 9, 14))
for x0 in (0.02, 0.05, 0.09):
    d.line([(x0 * W, 0), (x0 * W + 6, 0.18 * H)], fill=(8, 9, 14), width=7)

im.save(OUT + "arena1_blockin.png")
print("saved", OUT + "arena1_blockin.png", "floor at", round(floor), "of", H)
