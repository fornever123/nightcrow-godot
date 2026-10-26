"""第 2 处回潮区：三张灰度构图缩略图（A 绳索斜线 / B 环下孤塔 / C 渡槽来水）。
游戏屏幕坐标 1280×720，地面站立线 580；天空和巨环用已定的天空层真像素（转灰度），其余是 5 档明度色块。"""
import math, random
from PIL import Image, ImageDraw, ImageFont, ImageOps, ImageFilter

P = r"E:/00game/nightcrow-godot/"
OUT = P + "docs/视觉设计/blockin/"
W, H, FLOOR = 1280, 720, 580
FAR, NEAR = 548, 622                      # 桥面远边 / 近边（和定调图一致）
L1, L2, L3 = 470, 360, 250                # 三层平台顶面

sky_src = Image.open(P + "docs/视觉设计/layers/cloud_causeway/01_sky_ring_from_keyart.png").convert("RGB")
sk = sky_src.resize((round(sky_src.size[0] * H / sky_src.size[1]), H), Image.LANCZOS)
SKY = ImageOps.grayscale(sk.crop((sk.size[0] - W, 0, sk.size[0], H)))

ch = Image.open(P + "assets/image/ai-hd-20261020/idle/pose_001.png").convert("RGBA")
ch = ch.crop(ch.getbbox())
ch = ch.resize((round(ch.size[0] * 98 / ch.size[1]), 98), Image.LANCZOS)
CH_A = ch.split()[3]


def base():
    im = SKY.copy()
    d = ImageDraw.Draw(im)
    # 远山（低反差）
    random.seed(1)
    pts, x = [(0, 470)], 0
    while x <= W:
        pts.append((x, 430 - random.randint(0, 34)))
        x += random.randint(50, 110)
    pts.append((W, 470))
    d.polygon(pts, fill=78)
    # 云海：中间最亮最安静，顶线起伏
    for y in range(440, FAR):
        t = (y - 440) / (FAR - 440)
        d.line([(0, y), (W, y)], fill=int(118 + 26 * (1 - abs(t - 0.4))))
    random.seed(2)
    for i in range(14):
        cx, cy, r = random.randint(0, W), random.randint(430, 470), random.randint(30, 70)
        d.ellipse([cx - r, cy - r * 0.5, cx + r, cy + r * 0.5], fill=132)
    return im, d


def deck(d, puddles):
    for y in range(FAR, NEAR):
        t = (y - FAR) / (NEAR - FAR)
        d.line([(0, y), (W, y)], fill=int(48 + 22 * t))
    random.seed(7)
    x = 0
    while x < W:                              # 远边矮墙：2～3 块一组，留长缺口
        for _ in range(random.randint(2, 3)):
            w_, h_ = random.randint(18, 40), random.randint(12, 34)
            d.rectangle([x, FAR - h_, x + w_, FAR], fill=36)
            x += w_ + random.randint(2, 8)
        x += random.randint(120, 260)
    for (px, pw, ph) in puddles:              # 水洼（不规则，倒影亮）
        d.ellipse([px, FAR + 22, px + pw, FAR + 22 + ph], fill=175)
        d.ellipse([px + pw * 0.3, FAR + 18, px + pw * 0.8, FAR + 30], fill=150)
    d.rectangle([0, NEAR, W, H], fill=14)     # 桥立面
    for ax in (120, 470, 820, 1170):
        d.ellipse([ax - 95, NEAR + 30, ax + 95, NEAR + 300], fill=34)
    d.line([(0, NEAR), (W, NEAR)], fill=95, width=2)


def plat(d, x0, x1, top, body=28, thick=26):
    d.rectangle([x0, top + 4, x1, top + thick], fill=body)
    d.rectangle([x0, top - 4, x1, top + 4], fill=92)        # 亮顶边


def heroes(im, spots):
    for x, fy in spots:
        sil = Image.new("L", CH_A.size, 10)
        im.paste(sil, (x, fy - 98), CH_A)


def fg(d, left=True, right=True, ivy=True):
    if left:
        d.polygon([(0, H), (0, 600), (40, 590), (110, 640), (150, H)], fill=4)
    if right:
        d.polygon([(W, H), (W, 590), (1230, 610), (1180, 680), (1150, H)], fill=4)
    if ivy:
        for x0 in (20, 52, 80):
            d.line([(x0, 0), (x0 + 8, 130)], fill=4, width=6)


# ---- A 绳索斜线 ----
A, d = base()
d.polygon([(0, 560), (0, 300), (60, 300), (60, 330), (130, 330), (130, 360), (230, 360), (260, 560)], fill=30)  # 左缘断拱廊
for ax in (40, 150):
    d.ellipse([ax, 400, ax + 70, 520], fill=70)
d.polygon([(430, 470), (470, 200), (520, 200), (560, 470)], fill=52)          # 驿塔石针（中景，底部没入云）
d.rectangle([478, 120, 512, 205], fill=48)
d.polygon([(470, 122), (495, 80), (520, 122)], fill=48)
d.ellipse([489, 132, 501, 144], fill=230)                                      # 暖灯
d.polygon([(960, 470), (985, 330), (1005, 330), (1030, 470)], fill=58)        # 巨环下的小石针
d.line([(512, 210), (700, 280), (860, 318), (990, 334)], fill=40, width=3)     # 斜下绳桥
for bx, by in [(600, 230), (690, 255), (780, 285)]:
    d.polygon([(bx, by), (bx + 10, by - 4), (bx + 4, by + 3)], fill=20)
plat(d, 40, 300, L1)                     # 一层：拱廊断梁（左）
plat(d, 950, 1180, L1)                   # 一层：倒下的柱段（右）
plat(d, 260, 420, L2)                    # 二层：拱廊上层断段
deck(d, [(640, 150, 22), (900, 110, 18)])
fg(d)
heroes(A, [(600, FLOOR), (150, L1), (320, L2)])

# ---- B 环下孤塔 ----
B, d = base()
d.polygon([(0, 560), (0, 220), (90, 200), (180, 230), (260, 260), (330, 330), (400, 360), (420, 560)], fill=26)  # 坍塌门楼
d.ellipse([110, 380, 250, 560], fill=60)                                       # 门洞透云
plat(d, 150, 390, L2, body=26)                                                  # 门楼顶 = 二层
d.polygon([(970, 470), (1000, 330), (1030, 300), (1060, 330), (1090, 470)], fill=40)  # 环下孤塔（逆光暗剪影）
d.rectangle([1014, 230, 1046, 310], fill=36)
d.polygon([(1006, 232), (1030, 190), (1054, 232)], fill=36)
d.ellipse([1024, 244, 1036, 256], fill=230)
plat(d, 470, 640, L1)                    # 一层：门楼掉下来的拱石（左中）
plat(d, 1100, 1260, L1)                  # 一层：断石碑（右）
deck(d, [(980, 120, 26), (600, 80, 14)])
d.line([(1030, FAR + 24), (1030, NEAR - 6)], fill=200, width=4)                  # 环—塔—水洼 竖光轴
fg(d, ivy=False)
heroes(B, [(720, FLOOR), (230, L2), (520, L1)])

# ---- C 渡槽来水 ----
C, d = base()
d.polygon([(330, 160), (430, 150), (1080, 450), (1040, 480), (980, 470)], fill=34)  # 斜向沉入云海的巨大断渡槽
for i in range(5):
    x = 420 + i * 125
    y = 190 + i * 58
    d.rectangle([x, y + 10, x + 26, min(470, y + 180)], fill=34)
    d.ellipse([x + 30, y + 30, x + 110, y + 130], fill=70)
d.line([(1060, 452), (1068, 540)], fill=210, width=5)                           # 断口泻下的细瀑
d.ellipse([1040, 520, 1100, 548], fill=190)
plat(d, 100, 380, L1)                    # 一层：掉到桥面上的槽段（平顶带积水）
d.rectangle([180, L1 - 3, 300, L1 + 1], fill=170)
plat(d, 860, 1020, L2)                   # 二层：槽墩顶
d.rectangle([900, L2 + 26, 980, FAR], fill=30)
deck(d, [(1000, 150, 24), (560, 90, 16)])
fg(d)
heroes(C, [(620, FLOOR), (220, L1), (900, L2)])

font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 30)
sheet = Image.new("L", (W, (H + 50) * 3), 255)
for i, (im, name) in enumerate([(A, "A 绳索斜线：驿塔在左，绳桥斜落到巨环下的小石针"),
                                (B, "B 环下孤塔：驿塔在巨环正下方，环—塔—水洼一条竖光轴；左边坍塌门楼"),
                                (C, "C 渡槽来水：巨大断渡槽斜沉进云海，断口细瀑落进水洼")]):
    sheet.paste(im, (0, i * (H + 50) + 50))
    ImageDraw.Draw(sheet).text((12, i * (H + 50) + 8), name, fill=0, font=font)
    im.save(OUT + f"arena2_thumb_{'ABC'[i]}.png")
sheet.save(OUT + "arena2_thumbs.png")
print("ok")
