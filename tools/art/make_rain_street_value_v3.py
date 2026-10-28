"""雨夜河岸街：明暗草图 v3（结构参考图）。

v2 的问题会被 GPT 原样画出来（它几乎照抄草图），所以草图本身要先“设计好”：
  - 每栋楼的窗都不一样：双联尖窗 / 窄长条窗 / 小圆窗 / 方格窗 / 不对称高低窗，不再平均复制同一种
  - 体块有起伏：凸窗、扶壁、檐口线、钟楼的钟楼框和角柱
  - 屋顶分受光面和背光面（月光在右上）：右坡亮、左坡暗；楼的右边缘一条亮边
  - 整体比 v2 亮一档，颜色在冷灰里分出深青蓝（暗部）和银白（受光面）
  - 仍然只有少数暖光窗；钟楼的朱红是唯一焦点；街面一层最暗最静
  - 能站的面和 v1 / v2 完全一样（同一份布局数据），细黄线标出
用法：python make_rain_street_value_v3.py <layout.json> <输出.png>
"""
import sys, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

LAYOUT, OUT = sys.argv[1], sys.argv[2]
SEC = json.load(open(LAYOUT, encoding="utf-8"))["sections"][0]
X0, X1, Y0, Y1 = -2450, 260, -700, 826
W, H = 1672, 941
S = W / (X1 - X0)
FLOOR = 580


def X(x): return (x - X0) * S
def Y(y): return (y - Y0) * S
def P(pts): return [(X(x), Y(y)) for x, y in pts]


def mask():
    m = Image.new("L", (W, H), 0)
    return m, ImageDraw.Draw(m)


def vgrad(top_col, bot_col, y_top, y_bot):
    t = np.clip((np.arange(H)[:, None] - Y(y_top)) / max(Y(y_bot) - Y(y_top), 1), 0, 1)[..., None]
    a, b = np.array(top_col, np.float32), np.array(bot_col, np.float32)
    return np.broadcast_to(a * (1 - t) + b * t, (H, W, 3)).copy()


def solid(c):
    return np.full((H, W, 3), c, np.float32)


def paste(c, m, blur=0.6):
    mm = m.filter(ImageFilter.GaussianBlur(blur)) if blur else m
    a = np.asarray(mm, np.float32)[..., None] / 255.0
    img[:] = img * (1 - a) + c * a


# ---------------------------------------------------------------- 天空 / 月亮 / 远景
img = vgrad((14, 20, 34), (60, 74, 98), -700, 520)
m, d = mask(); d.ellipse([X(-700), Y(-800), X(-300), Y(-360)], fill=120); paste(solid((140, 154, 182)), m, 70)
m, d = mask(); d.ellipse([X(-560), Y(-640), X(-440), Y(-520)], fill=255); paste(solid((226, 230, 236)), m, 1.0)
m, d = mask()                                                    # 一缕被月光照亮的云
d.ellipse([X(-900), Y(-560), X(-560), Y(-500)], fill=140); d.ellipse([X(-430), Y(-600), X(-120), Y(-545)], fill=120)
paste(solid((92, 106, 134)), m, 18)
m, d = mask()                                                    # 远景：低平的城市 + 三座塔 + 一座穹顶，全在雾里
far = [(-2450, 330), (-2260, 320), (-2240, 210), (-2215, 120), (-2190, 210), (-2170, 320), (-1700, 310), (-1520, 300),
       (-1500, 170), (-1470, 90), (-1440, 170), (-1420, 300), (-900, 290), (-760, 280), (-560, 290), (-300, 300),
       (260, 300), (260, 700), (-2450, 700)]
d.polygon(P(far), fill=255); d.ellipse([X(-840), Y(40), X(-560), Y(320)], fill=255)
d.rectangle([X(-715), Y(-10), X(-685), Y(60)], fill=255)
paste(vgrad((82, 94, 118), (92, 104, 128), 100, 600), m, 1.6)
m, d = mask(); d.rectangle([0, Y(240), W, Y(620)], fill=150); paste(solid((98, 112, 136)), m, 45)

# 巷子深处的后排楼（雾里，中间调）
m, d = mask()
d.rectangle([X(-1560), Y(-150), X(-1440), Y(FLOOR)], fill=255)
d.polygon(P([(-1560, -150), (-1500, -290), (-1440, -150)]), fill=255)
paste(vgrad((96, 108, 130), (56, 64, 80), -300, 560), m, 1.2)


# ---------------------------------------------------------------- 楼体
def facade(poly_or_rect, top_y, top_col, bot_col):
    m, d = mask()
    if isinstance(poly_or_rect, tuple):
        x0, y0, x1, y1 = poly_or_rect
        d.rectangle([X(x0), Y(y0), X(x1), Y(y1)], fill=255)
    else:
        d.polygon(P(poly_or_rect), fill=255)
    paste(vgrad(top_col, bot_col, top_y, FLOOR), m)


def lit_edge(x, y0, y1, w=14):
    """楼的右边缘：月光照到的一条亮边（往里渐暗）"""
    for i in range(4):
        m, d = mask()
        d.rectangle([X(x - w * (i + 1) / 4), Y(y0), X(x), Y(y1)], fill=60)
        paste(solid((150, 162, 186)), m, 1.0)


def roof(apex, left, right, base_y):
    """坡屋顶：左坡背光，右坡受光"""
    m, d = mask(); d.polygon(P([left, apex, (apex[0], base_y)]), fill=255); paste(solid((20, 24, 33)), m)
    m, d = mask(); d.polygon(P([apex, right, (apex[0], base_y)]), fill=255)
    paste(vgrad((112, 126, 150), (52, 60, 78), apex[1], base_y), m)
    m, d = mask(); d.line(P([apex, right]), fill=255, width=4); paste(solid((200, 210, 228)), m, 0.6)


def band(x0, x1, y, h=12):
    """檐口 / 腰线：上沿受光"""
    m, d = mask(); d.rectangle([X(x0), Y(y), X(x1), Y(y + h)], fill=255); paste(solid((30, 35, 46)), m, 0.4)
    m, d = mask(); d.line([(X(x0), Y(y)), (X(x1), Y(y))], fill=255, width=2); paste(solid((150, 162, 186)), m, 0.4)


GLASS, SHEEN, WARM = (12, 15, 22), (58, 70, 92), (236, 170, 90)


def lancet(cx, bottom, w, h, lit=False):
    m, d = mask()
    d.rectangle([X(cx - w / 2), Y(bottom - h + w / 2), X(cx + w / 2), Y(bottom)], fill=255)
    d.pieslice([X(cx - w / 2), Y(bottom - h), X(cx + w / 2), Y(bottom - h + w)], 180, 360, fill=255)
    paste(solid(WARM if lit else GLASS), m, 0.5)
    if not lit:
        m, d = mask(); d.line([(X(cx + w * 0.3), Y(bottom - h + w * 0.6)), (X(cx + w * 0.3), Y(bottom - 6))], fill=255, width=2)
        paste(solid(SHEEN), m, 0.5)


def square(cx, bottom, w, h, lit=False):
    m, d = mask(); d.rectangle([X(cx - w / 2), Y(bottom - h), X(cx + w / 2), Y(bottom)], fill=255)
    paste(solid(WARM if lit else GLASS), m, 0.5)
    m, d = mask()                                                # 窗格：十字
    d.line([(X(cx), Y(bottom - h)), (X(cx), Y(bottom))], fill=255, width=2)
    d.line([(X(cx - w / 2), Y(bottom - h * 0.55)), (X(cx + w / 2), Y(bottom - h * 0.55))], fill=255, width=2)
    paste(solid((34, 38, 48) if not lit else (150, 96, 44)), m, 0.4)


def oculus(cx, cy, r, lit=False):
    m, d = mask(); d.ellipse([X(cx - r), Y(cy - r), X(cx + r), Y(cy + r)], fill=255)
    paste(solid(WARM if lit else GLASS), m, 0.5)


# B1 阶梯山墙的窄高楼（偏蓝灰）
steps = [(-2400, -330), (-2400, -380), (-2350, -380), (-2350, -430), (-2290, -430), (-2290, -480), (-2240, -480), (-2240, -520),
         (-2140, -520), (-2140, -480), (-2090, -480), (-2090, -430), (-2030, -430), (-2030, -380), (-1980, -380), (-1980, -330),
         (-1980, FLOOR), (-2400, FLOOR)]
facade(steps, -520, (88, 99, 120), (17, 20, 28))
m, d = mask(); d.line(P([(-2140, -520), (-2140, -480), (-2090, -480), (-2090, -430), (-2030, -430), (-2030, -380), (-1980, -380)]), fill=255, width=4)
paste(solid((200, 210, 228)), m, 0.6)
m, d = mask(); d.rectangle([X(-2070), Y(-580), X(-2015), Y(-380)], fill=255); paste(solid((24, 28, 38)), m)   # 烟囱
m, d = mask(); d.line([(X(-2015), Y(-580)), (X(-2015), Y(-380))], fill=255, width=3); paste(solid((170, 182, 204)), m)
lit_edge(-1980, -330, 300)
band(-2400, -1980, 330); band(-2400, -1980, 50)
oculus(-2190, -440, 30)
lancet(-2275, 0, 56, 220, lit=True)                              # 三层：一扇高大的尖窗（亮）
square(-2075, -80, 50, 70)
lancet(-2300, 290, 44, 210); lancet(-2240, 290, 44, 210)         # 二层：双联尖窗
lancet(-2050, 270, 24, 170)                                      # 二层：一条窄窗
lancet(-2290, FLOOR, 110, 250)                                   # 门
square(-2060, 470, 50, 70)

# B2 圆锥塔帽的角楼（偏青灰），两角有扶壁
facade((-1980, -300, -1560, FLOOR), -300, (80, 94, 112), (15, 20, 27))
roof((-1770, -690), (-1925, -300), (-1615, -300), -300)
m, d = mask(); d.rectangle([X(-1792), Y(-720), X(-1748), Y(-680)], fill=255); paste(solid((24, 28, 38)), m)
for bx in (-1980, -1585):                                       # 扶壁
    m, d = mask(); d.rectangle([X(bx), Y(-300), X(bx + 25), Y(FLOOR)], fill=255); paste(vgrad((96, 108, 128), (20, 24, 32), -300, FLOOR), m)
lit_edge(-1560, -300, 400)
band(-1980, -1560, -300, 16)
for cx in (-1880, -1770, -1660):
    oculus(cx, -150, 22)                                         # 三层：一排小圆窗
for cx, lit in ((-1880, False), (-1770, True), (-1660, False)):
    lancet(cx, 270, 26, 190, lit)                                # 二层：窄长条窗
lancet(-1770, FLOOR, 100, 230)

# B3 宽楼：芒萨尔陡屋顶 + 两个不同的老虎窗 + 中间凸窗（偏深蓝）
facade((-1440, 10, -900, FLOOR), 10, (74, 86, 108), (16, 19, 27))
m, d = mask(); d.polygon(P([(-1460, 10), (-1310, -300), (-1170, -300), (-1170, 10)]), fill=255); paste(solid((20, 24, 33)), m)
m, d = mask(); d.polygon(P([(-1170, -300), (-1030, -300), (-880, 10), (-1170, 10)]), fill=255)
paste(vgrad((108, 122, 146), (50, 58, 76), -300, 10), m)
m, d = mask(); d.line(P([(-1030, -300), (-880, 10)]), fill=255, width=4); paste(solid((200, 210, 228)), m)
m, d = mask(); d.rectangle([X(-1390), Y(-380), X(-1350), Y(-240)], fill=255); paste(solid((24, 28, 38)), m)
m, d = mask(); d.rectangle([X(-1340), Y(-190), X(-1260), Y(-80)], fill=255); d.polygon(P([(-1350, -190), (-1300, -250), (-1250, -190)]), fill=255)
paste(solid((44, 50, 64)), m)                                    # 老虎窗 1：尖顶
square(-1300, -95, 40, 70)
m, d = mask(); d.rectangle([X(-1100), Y(-170), X(-1030), Y(-80)], fill=255); d.pieslice([X(-1100), Y(-205), X(-1030), Y(-135)], 180, 360, fill=255)
paste(solid((52, 60, 76)), m)                                    # 老虎窗 2：圆顶
oculus(-1065, -125, 18)
lit_edge(-900, 10, 330)
band(-1440, -900, 10, 16)
square(-1385, 290, 70, 160); square(-1290, 290, 70, 160)          # 二层：方格窗
square(-1000, 310, 64, 150)
m, d = mask(); d.polygon(P([(-1210, 250), (-1070, 250), (-1082, 470), (-1198, 470)]), fill=255)   # 凸窗体块
paste(vgrad((96, 108, 130), (40, 46, 60), 250, 470), m)
m, d = mask(); d.line(P([(-1070, 250), (-1082, 470)]), fill=255, width=3); paste(solid((170, 182, 204)), m)
square(-1140, 440, 70, 150, lit=True)                            # 凸窗里亮着
lancet(-1330, FLOOR, 120, 250)
square(-990, FLOOR, 80, 190)

# B4 窄店面楼：阶梯山墙，窗不对称（比旁边亮一点、靠前）
b4 = [(-900, -200), (-900, -250), (-850, -250), (-850, -300), (-670, -300), (-670, -250), (-620, -250), (-620, -200),
      (-620, FLOOR), (-900, FLOOR)]
facade(b4, -300, (94, 104, 122), (19, 22, 30))
m, d = mask(); d.line(P([(-670, -300), (-670, -250), (-620, -250), (-620, -200)]), fill=255, width=4); paste(solid((200, 210, 228)), m)
lit_edge(-620, -200, 380)
band(-900, -620, -200)
lancet(-760, 20, 46, 170, lit=True)                              # 三层：一扇亮着的尖窗
oculus(-680, -110, 16)
lancet(-840, 330, 52, 230)                                       # 二层：一高一小，不对称
square(-700, 200, 40, 50)
m, d = mask(); d.rectangle([X(-860), Y(440), X(-680), Y(560)], fill=255); paste(solid((96, 66, 36)), m)   # 店面橱窗：很暗的暖光

# 广场边的石拱廊桥（桥下透出远景）
m, d = mask(); d.rectangle([X(-640), Y(30), X(-300), Y(96)], fill=255); paste(vgrad((70, 80, 98), (40, 46, 58), 30, 96), m)
m, d = mask(); d.pieslice([X(-610), Y(66), X(-330), Y(300)], 180, 360, fill=255); paste(vgrad((86, 98, 122), (94, 106, 130), 66, 300), m)

# 钟楼：石色最亮的一栋，两边角柱，钟面框；朱红是全图唯一焦点
facade((-260, -720, 260, FLOOR), -720, (108, 116, 134), (22, 25, 33))
for bx in (-260, 225):
    m, d = mask(); d.rectangle([X(bx), Y(-720), X(bx + 35), Y(FLOOR)], fill=255); paste(vgrad((124, 132, 150), (26, 29, 38), -720, FLOOR), m)
lit_edge(260, -720, 420, 18)
m, d = mask(); d.rectangle([X(-170), Y(-600), X(170), Y(-300)], fill=255); paste(solid((40, 44, 56)), m)        # 钟面框
band(-260, 260, -300, 16); band(-260, 260, 20 + 40, 10)
m, d = mask(); d.ellipse([X(-120), Y(-570), X(120), Y(-330)], fill=255); paste(solid((178, 50, 40)), m)
m, d = mask()                                                    # 钟面 / 玫瑰窗：一圈放射窗棂，不画卡通指针
import math
d.ellipse([X(-70), Y(-520), X(70), Y(-380)], outline=255, width=3)
for k in range(12):
    a = k * math.pi / 6
    d.line([(X(70 * math.cos(a)), Y(-450 + 70 * math.sin(a))), (X(118 * math.cos(a)), Y(-450 + 118 * math.sin(a)))], fill=255, width=3)
paste(solid((70, 18, 14)), m, 0.5)
lancet(0, 270, 100, 240)
m, d = mask(); d.rectangle([X(-50), Y(30 + 50), X(50), Y(270)], fill=255); d.pieslice([X(-50), Y(30), X(50), Y(130)], 180, 360, fill=255)
paste(solid((168, 46, 36)), m)                                   # 朱红彩窗
lancet(0, FLOOR, 150, 300)
lancet(-170, 480, 30, 120); lancet(170, 480, 30, 120)

# ---------------------------------------------------------------- 能站的面：阳台 / 桥 / 檐（剪影 + 栏杆上沿受光）
for x0, x1, y, kind in SEC["platforms"]:
    if x1 < X0 or x0 > X1:
        continue
    m, d = mask()
    r, rd = mask()
    if kind in ("balcony", "ring"):
        d.rectangle([X(x0), Y(y), X(x1), Y(y + 16)], fill=255)
        stone = kind == "ring" or x0 > -1450 and x1 < -900          # 宽楼和钟楼用石栏，其他用铁栏
        step = 40 if stone else 24
        for bx in range(int(x0) + 6, int(x1), step):
            d.rectangle([X(bx), Y(y - 50), X(bx + (12 if stone else 3)), Y(y)], fill=255)
        rd.line([(X(x0), Y(y - 52)), (X(x1), Y(y - 52))], fill=255, width=3 if stone else 2)
        for bx in range(int(x0) + 30, int(x1) - 10, 140):
            d.polygon(P([(bx, y + 16), (bx + 22, y + 16), (bx, y + 46)]), fill=255)
    elif kind == "bridge":
        d.rectangle([X(x0), Y(y), X(x1), Y(y + 26)], fill=255)
        for bx in range(int(x0), int(x1), 30):
            d.line([(X(bx), Y(y - 40)), (X(bx + 15), Y(y))], fill=255, width=2)
        rd.line([(X(x0), Y(y - 42)), (X(x1), Y(y - 42))], fill=255, width=2)
    else:
        d.polygon(P([(x0 - 20, y + 36), (x0, y), (x1, y), (x1 + 20, y + 36)]), fill=255)
        rd.line([(X(x0), Y(y)), (X(x1), Y(y))], fill=255, width=2)
    paste(solid((14, 17, 23)), m, 0.4)
    paste(solid((150, 162, 186)), r, 0.4)
for x0, x1, y, _ in SEC["blocks"]:
    m, d = mask()
    for i in range(3):
        sy = y + (FLOOR - y) * i / 3
        inset = (x1 - x0) * 0.12 * (2 - i)
        d.rectangle([X(x0 + inset), Y(sy), X(x1 - inset), Y(FLOOR)], fill=255)
    paste(vgrad((70, 78, 94), (30, 34, 44), y, FLOOR), m, 0.4)

# ---------------------------------------------------------------- 路灯 + 暖光 / 红光的光晕
streets = [(x, y) for x, y, k in SEC["lamps"] if k == "street" and X0 <= x <= X1] + [(-500, 580)]
m, d = mask()
for x, y in streets:
    d.rectangle([X(x - 5), Y(y - 130), X(x + 5), Y(y)], fill=255)
paste(solid((10, 11, 14)), m, 0.3)
m, d = mask()
for x, y in streets:
    d.ellipse([X(x - 18), Y(y - 162), X(x + 18), Y(y - 126)], fill=255)
paste(solid((255, 204, 128)), m, 0.5)
halo = Image.new("RGB", (W, H)); hd = ImageDraw.Draw(halo)
for x, y in streets:
    hd.ellipse([X(x - 140), Y(y - 290), X(x + 140), Y(y - 10)], fill=(80, 50, 22))
    hd.ellipse([X(x - 150), Y(y - 6), X(x + 150), Y(y + 24)], fill=(100, 64, 28))
for cx, cy in ((-2275, -120), (-1770, 180), (-1140, 370), (-760, -60)):
    hd.ellipse([X(cx - 110), Y(cy - 150), X(cx + 110), Y(cy + 150)], fill=(56, 34, 14))
hd.ellipse([X(-190), Y(-640), X(190), Y(-260)], fill=(40, 9, 7))
img = np.clip(img + np.asarray(halo.filter(ImageFilter.GaussianBlur(40)), np.float32), 0, 255)

# ---------------------------------------------------------------- 街面 / 河岸挡墙 / 河
img[int(Y(FLOOR)):int(Y(FLOOR + 26))] = (44, 49, 60)
img[int(Y(FLOOR)):int(Y(FLOOR)) + 2] = (110, 120, 140)
img[int(Y(FLOOR + 26)):int(Y(FLOOR + 96))] = (22, 25, 33)
img[int(Y(FLOOR + 96)):] = (12, 15, 21)
refl = Image.new("RGB", (W, H)); rfd = ImageDraw.Draw(refl)
for x, y in streets:
    rfd.rectangle([X(x - 14), Y(FLOOR + 2), X(x + 14), Y(FLOOR + 24)], fill=(120, 80, 36))
    rfd.rectangle([X(x - 12), Y(FLOOR + 100), X(x + 12), Y(FLOOR + 240)], fill=(90, 60, 28))
rfd.rectangle([X(-40), Y(FLOOR + 100), X(40), Y(FLOOR + 230)], fill=(110, 30, 22))
for k in range(5):                                               # 月亮在水里的碎光：几道横向短线
    rfd.line([(X(-540 + 14 * (k % 2)), Y(FLOOR + 118 + 18 * k)), (X(-460 - 14 * (k % 2)), Y(FLOOR + 118 + 18 * k))], fill=(70, 78, 96), width=3)
img = np.clip(img + np.asarray(refl.filter(ImageFilter.GaussianBlur(5)), np.float32), 0, 255)

# ---------------------------------------------------------------- 能站的面：细黄线
out = Image.fromarray(img.astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7))
od = ImageDraw.Draw(out)
for x0, x1, y, kind in SEC["platforms"]:
    if x1 < X0 or x0 > X1:
        continue
    od.line([(X(x0), Y(y)), (X(x1), Y(y))], fill=(255, 212, 0), width=4)
for x0, x1, y, _ in SEC["blocks"]:
    if X0 <= x0 <= X1:
        od.line([(X(x0 + (x1 - x0) * 0.24), Y(y)), (X(x1 - (x1 - x0) * 0.24), Y(y))], fill=(255, 212, 0), width=4)
out.save(OUT)
print("saved", out.size)
