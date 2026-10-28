"""雨夜河岸街：导出给 GPT 照着画的结构参考图（阶段二）。

画面 = 一块竞技场的一段，横竖等比（1 世界单位 = SCALE 像素）：
  楼的大形（灰）、能站的面（亮黄线）、灯（暖色点）、街面 / 挡墙 / 河。
  图里不放文字、不放人，免得 GPT 把它们画进去。
用法：python make_rain_street_ref.py <layout.json> <输出.png>
目前只做“钟楼广场左半边”这一张试验图；楼的造型写在下面 MASSING 里（布局 JSON 只管能站的面）。
"""
import sys, json
from PIL import Image, ImageDraw, ImageFilter

LAYOUT, OUT = sys.argv[1], sys.argv[2]
L = json.load(open(LAYOUT, encoding="utf-8"))
SEC = L["sections"][0]
X0, X1, Y0, Y1 = -2450, 260, -700, 826          # 这张图覆盖的世界范围（相对封印中心）
W, H = 1672, 941
S = W / (X1 - X0)
FLOOR = 580

SKY_T, SKY_B = (66, 74, 92), (104, 114, 134)
FAR = (124, 132, 150)
NEAR, NEAR2, ROOF, WIN = (42, 46, 56), (48, 52, 63), (32, 35, 43), (24, 26, 32)
STREET, WALL, RIVER = (74, 79, 90), (38, 42, 51), (26, 29, 37)
WALK, LAMP = (255, 212, 0), (255, 184, 96)


def X(x): return (x - X0) * S
def Y(y): return (y - Y0) * S
def P(pts): return [(X(x), Y(y)) for x, y in pts]


img = Image.new("RGB", (W, H))
d = ImageDraw.Draw(img)
for y in range(H):
    k = y / H
    d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * k) for a, b in zip(SKY_T, SKY_B)))
d.ellipse([X(-560), Y(-640), X(-440), Y(-520)], fill=(226, 228, 232))           # 月亮

# 远处雾里的城市（很淡，只交代纵深）
far = [(-2450, 330), (-2300, 300), (-2200, 300), (-2180, 220), (-2140, 220), (-2120, 300), (-1700, 320), (-1500, 280),
       (-1480, 160), (-1440, 160), (-1420, 280), (-1000, 300), (-760, 250), (-700, 120), (-660, 60), (-620, 120),
       (-560, 250), (-300, 300), (260, 300), (260, 600), (-2450, 600)]
d.polygon(P(far), fill=FAR)
d.ellipse([X(-860), Y(-40), X(-500), Y(320)], fill=FAR)                          # 远处大教堂的穹顶

# 巷子深处的后排楼（比近景亮一档，雾里）
d.rectangle([X(-1560), Y(-180), X(-1440), Y(FLOOR)], fill=(78, 84, 98))
d.polygon(P([(-1560, -180), (-1500, -300), (-1440, -180)]), fill=(78, 84, 98))


def windows(x0, x1, ys, n, w=46, h=150, col=WIN):
    for k in range(n):
        cx = x0 + (k + 0.5) * (x1 - x0) / n
        for y in ys:
            d.rectangle([X(cx - w / 2), Y(y - h + w / 2), X(cx + w / 2), Y(y)], fill=col)
            d.pieslice([X(cx - w / 2), Y(y - h), X(cx + w / 2), Y(y - h + w)], 180, 360, fill=col)


def door(cx, w=110, h=240):
    d.rectangle([X(cx - w / 2), Y(FLOOR - h + w / 2), X(cx + w / 2), Y(FLOOR)], fill=WIN)
    d.pieslice([X(cx - w / 2), Y(FLOOR - h), X(cx + w / 2), Y(FLOOR - h + w)], 180, 360, fill=WIN)


# ---- B1 窄高联排楼：阶梯山墙 + 一组烟囱 ----
d.rectangle([X(-2400), Y(-330), X(-1980), Y(FLOOR)], fill=NEAR)
steps = [(-2400, -330), (-2400, -380), (-2350, -380), (-2350, -430), (-2290, -430), (-2290, -480), (-2240, -480), (-2240, -520),
         (-2140, -520), (-2140, -480), (-2090, -480), (-2090, -430), (-2030, -430), (-2030, -380), (-1980, -380), (-1980, -330)]
d.polygon(P(steps), fill=NEAR)
d.rectangle([X(-2060), Y(-560), X(-2010), Y(-380)], fill=ROOF)
windows(-2380, -2000, [250, -20], 2, 54, 190)
windows(-2380, -2000, [-370 + 330], 0)
door(-2190)

# ---- B2 角楼：方身 + 圆锥塔帽（塔帽下一圈石檐能站） ----
d.rectangle([X(-1980), Y(-300), X(-1560), Y(FLOOR)], fill=NEAR2)
d.polygon(P([(-1920, -300), (-1770, -680), (-1620, -300)]), fill=ROOF)
d.rectangle([X(-1790), Y(-700), X(-1750), Y(-660)], fill=ROOF)
windows(-1960, -1580, [240, -60], 3, 40, 160)
door(-1770, 100, 230)

# ---- B3 宽联排：陡屋顶 + 两扇老虎窗 + 中间一个凸窗 ----
d.rectangle([X(-1440), Y(10), X(-900), Y(FLOOR)], fill=NEAR)
d.polygon(P([(-1460, 10), (-1300, -300), (-1040, -300), (-880, 10)]), fill=ROOF)
for cx in (-1300, -1060):
    d.rectangle([X(cx - 40), Y(-200), X(cx + 40), Y(-90)], fill=NEAR2)
    d.polygon(P([(cx - 50, -200), (cx, -260), (cx + 50, -200)]), fill=ROOF)
d.rectangle([X(-1380), Y(-360), X(-1340), Y(-220)], fill=ROOF)
d.polygon(P([(-1205, 250), (-1075, 250), (-1085, 520), (-1195, 520)]), fill=NEAR2)   # 凸窗
d.rectangle([X(-1180), Y(280), X(-1100), Y(480)], fill=WIN)
windows(-1430, -1210, [250], 2, 44, 150)
windows(-1070, -910, [250], 1, 44, 150)
windows(-1430, -910, [-40], 4, 40, 150)
door(-1320)
door(-1000, 100, 220)

# ---- B4 窄店面楼：阶梯山墙，底层是店面 ----
d.rectangle([X(-900), Y(-200), X(-620), Y(FLOOR)], fill=NEAR2)
d.polygon(P([(-900, -200), (-900, -250), (-850, -250), (-850, -300), (-670, -300), (-670, -250), (-620, -250), (-620, -200)]), fill=NEAR2)
d.rectangle([X(-860), Y(430), X(-680), Y(FLOOR)], fill=WIN)                      # 店面橱窗
windows(-890, -630, [250, -30], 2, 44, 150)

# ---- 钟楼（右边露一半，冲出画面上沿） ----
d.rectangle([X(-260), Y(-720), X(260), Y(FLOOR)], fill=(46, 50, 61))
d.ellipse([X(-110), Y(-560), X(110), Y(-340)], fill=(150, 52, 44))             # 朱红钟面
d.rectangle([X(-50), Y(-40), X(50), Y(200)], fill=(150, 52, 44))                 # 朱红彩窗
door(0, 150, 300)

# ---- 广场边的石拱廊桥（三层）：桥下透出远景 ----
d.rectangle([X(-640), Y(30), X(-300), Y(90)], fill=NEAR2)
d.pieslice([X(-610), Y(60), X(-330), Y(300)], 180, 360, fill=FAR)

# ---- 能站的面：石阶（实心）+ 所有单向平台；平台画出能看懂的形状，顶面一律亮黄 ----
for x0, x1, y, kind in SEC["blocks"]:
    if x1 < X0 or x0 > X1:
        continue
    for i in range(3):
        sy = y + (FLOOR - y) * i / 3
        inset = (x1 - x0) * 0.12 * (2 - i)
        d.rectangle([X(x0 + inset), Y(sy), X(x1 - inset), Y(FLOOR)], fill=(70, 74, 84))
    d.line([(X(x0 + (x1 - x0) * 0.24), Y(y)), (X(x1 - (x1 - x0) * 0.24), Y(y))], fill=WALK, width=6)
for x0, x1, y, kind in SEC["platforms"]:
    if x1 < X0 or x0 > X1:
        continue
    if kind in ("balcony", "ring"):
        d.rectangle([X(x0), Y(y), X(x1), Y(y + 16)], fill=(58, 62, 72))
        for bx in range(int(x0) + 30, int(x1), 120):
            d.polygon(P([(bx, y + 16), (bx + 24, y + 16), (bx, y + 50)]), fill=(58, 62, 72))
        d.line([(X(x0), Y(y - 50)), (X(x1), Y(y - 50))], fill=(18, 20, 24), width=3)    # 栏杆扶手
        for bx in range(int(x0), int(x1), 22 if kind == "balcony" else 40):
            d.line([(X(bx), Y(y - 50)), (X(bx), Y(y))], fill=(18, 20, 24), width=2 if kind == "balcony" else 4)
    elif kind == "bridge":
        d.rectangle([X(x0), Y(y), X(x1), Y(y + 26)], fill=(64, 68, 78))
        d.line([(X(x0), Y(y - 40)), (X(x1), Y(y - 40))], fill=(64, 68, 78), width=4)
    elif kind in ("eave", "ridge"):
        d.polygon(P([(x0 - 20, y + 36), (x0, y), (x1, y), (x1 + 20, y + 36)]), fill=ROOF)
    d.line([(X(x0), Y(y)), (X(x1), Y(y))], fill=WALK, width=6)

# ---- 灯 ----
for x, y, kind in SEC["lamps"]:
    if x < X0 or x > X1:
        continue
    if kind == "street":
        d.rectangle([X(x - 5), Y(y - 130), X(x + 5), Y(y)], fill=(16, 16, 20))
        d.ellipse([X(x - 22), Y(y - 168), X(x + 22), Y(y - 124)], fill=LAMP)
    else:
        d.ellipse([X(x - 16), Y(y - 130), X(x + 16), Y(y - 98)], fill=LAMP)

# ---- 街面 / 河岸挡墙 / 河 ----
d.rectangle([0, Y(FLOOR), W, Y(FLOOR + 26)], fill=STREET)
d.rectangle([0, Y(FLOOR + 26), W, Y(FLOOR + 96)], fill=WALL)
d.rectangle([0, Y(FLOOR + 96), W, H], fill=RIVER)

img.filter(ImageFilter.GaussianBlur(0.6)).save(OUT)
print("saved", OUT, img.size)
