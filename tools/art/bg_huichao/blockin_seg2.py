"""第 2 段画布：左边 1/4 = 实战定调图（已画好）的最右一段，右边 3/4 = 下一段路的构图草图。
GPT 只重画草图部分、让它接上左边的画。比例和定调图一致（定调图 1 像素 = 游戏 0.88 屏幕像素）。"""
import random
from PIL import Image, ImageDraw, ImageFilter

P = r"E:/00game/nightcrow-godot/"
OUT = P + "docs/视觉设计/blockin/"
key = Image.open(P + "docs/视觉设计/keyart/gameplay_frame_v2.webp").convert("RGB")
W, H = key.size                                  # 1672 × 941
KEEP = W // 4                                    # 左边保留的已画部分宽度
im = Image.new("RGB", (W, H))
im.paste(key.crop((W - KEEP, 0, W, H)), (0, 0))
d = ImageDraw.Draw(im)
X0 = KEEP                                        # 草图从这里开始

WALK = 659                                       # 定调图里角色站立线（桥面中间）
FAR, NEAR = 621, 706                             # 桥面远边 / 近边
def above(screen_px):                            # 游戏里高出地面多少屏幕像素 → 定调图像素
    return WALK - screen_px / 0.88

# 天空（接定调图的颜色，往右略亮一点点）、星
HOR = int(0.50 * H)
for y in range(H):
    t = min(1.0, y / HOR)
    c = (int(12 + 46 * t), int(18 + 58 * t), int(38 + 76 * t))
    d.line([(X0, y), (W, y)], fill=c)
random.seed(4)
for _ in range(200):
    x, y = random.randrange(X0, W), random.randrange(int(H * 0.45))
    v = random.randint(120, 220)
    d.point((x, y), fill=(v, v, v + 10))
# 远山：两层
for layer, (top, col) in enumerate([(70, (58, 72, 104)), (36, (44, 54, 82))]):
    random.seed(10 + layer)
    pts = [(X0, HOR + 30)]
    x = X0
    while x <= W:
        pts.append((x, HOR + 20 - random.randint(10, top)))
        x += random.randint(40, 100)
    pts.append((W, HOR + 30))
    d.polygon(pts, fill=col)
# 云海：战斗带背后亮、安静
for y in range(HOR + 20, FAR):
    t = (y - HOR) / (FAR - HOR)
    v = 1 - abs(t - 0.45) * 1.3
    c = (int(70 + 40 * v), int(84 + 44 * v), int(118 + 44 * v))
    d.line([(X0, y), (W, y)], fill=c)

# 中景地标：鸦信社驿塔（石针 + 细高塔 + 暖灯 + 绳桥），在画布 62% 处
cx = int(0.62 * W)
d.polygon([(cx - 110, FAR), (cx - 18, 230), (cx + 18, 230), (cx + 120, FAR)], fill=(32, 38, 58))
d.rectangle([cx - 16, 110, cx + 16, 236], fill=(28, 34, 52))
d.polygon([(cx - 24, 112), (cx, 50), (cx + 24, 112)], fill=(28, 34, 52))
d.ellipse([cx - 6, 124, cx + 6, 138], fill=(245, 175, 90))
for wy in (170, 200):
    d.rectangle([cx - 3, wy, cx + 3, wy + 8], fill=(230, 160, 80))
d.polygon([(cx + 150, FAR), (cx + 190, 380), (cx + 205, 380), (cx + 240, FAR)], fill=(36, 43, 64))
d.line([(cx + 16, 260), (cx + 110, 330), (cx + 196, 382)], fill=(24, 28, 40), width=3)
# 更远的一段断渡槽（在驿塔右后方）
ay = 470
d.rectangle([cx + 260, ay, W, ay + 9], fill=(60, 70, 96))
for i in range(6):
    x0 = cx + 270 + i * 46
    d.rectangle([x0, ay, x0 + 8, ay + 90], fill=(60, 70, 96))

# 桥面：和定调图同一个透视带，接上左边
for y in range(FAR, NEAR):
    t = (y - FAR) / (NEAR - FAR)
    c = (int(50 + 30 * t), int(56 + 30 * t), int(74 + 30 * t))
    d.line([(X0, y), (W, y)], fill=c)
random.seed(12)
x = X0
while x < W:
    w_ = random.randint(30, 70)
    h_ = random.choice([0, 16, 24, 32])
    if h_:
        d.rectangle([x, FAR - h_, x + w_, FAR], fill=(46, 52, 70))
    x += w_ + random.randint(20, 90)
for (px, pw) in [(0.40, 50), (0.78, 40)]:       # 几块水洼（亮一点）
    d.ellipse([px * W, FAR + 30, px * W + pw * 3, FAR + 52], fill=(96, 120, 140))
d.rectangle([X0, NEAR, W, H], fill=(30, 34, 48))
for i in range(3):
    ax = X0 + 120 + i * 430
    d.ellipse([ax, NEAR + 60, ax + 300, NEAR + 420], fill=(66, 78, 108))

# 这段路上的两个平台（中间留空）：一层的断墙（实心），二层的木脚手平台（靠石柱撑着）
l1 = above(110)                                   # 一层：高出地面 110 屏幕像素
l2 = above(220)                                   # 二层：高出地面 220 屏幕像素
d.rectangle([0.30 * W, l1 + 6, 0.40 * W, FAR + 10], fill=(52, 58, 78))      # 断墙正面
d.rectangle([0.30 * W, l1 - 6, 0.40 * W, l1 + 6], fill=(120, 128, 150))     # 顶面
d.rectangle([0.80 * W, l2 - 5, 0.95 * W, l2 + 5], fill=(120, 112, 100))     # 木平台顶面
d.rectangle([0.80 * W, l2 + 5, 0.95 * W, l2 + 22], fill=(70, 62, 56))
for sx in (0.815, 0.925):
    d.rectangle([sx * W, l2 + 22, sx * W + 22, FAR], fill=(46, 52, 70))

# 前景：右下一块近黑剪影
d.polygon([(W, H), (W, 0.74 * H), (0.93 * W, 0.80 * H), (0.88 * W, 0.92 * H), (0.85 * W, H)], fill=(8, 9, 14))

im.save(OUT + "seg2_canvas.png")
print("saved; keep", KEEP, "L1 y", round(l1), "L2 y", round(l2))
