"""雨夜河岸街：明暗草图 v5（结构参考图）。

v5：所有门窗改成真正的哥特等边尖拱（之前其实是圆拱）；宽窗带中梃和顶上小圆窗棂；每栋楼的门窗按楼层对齐（窗头、窗台齐平），
通阳台的是落地窗；门分三种（单扇木门 / 双开大门带门楣 / 方门加尖拱气窗）；宽楼改成伦敦联排式（前坡屋顶、居中山墙老虎窗、
檐口带托石、一条通长阳台、去掉悬在门之间的凸窗）；店面楼一层是真正的店面（招牌 + 橱窗 + 侧门）。

v4b：屋面不再劈成左黑右亮（正立面只看到一个面）、阳台和檐口在墙上投影、门是木门、圆窗有石框和窗棂、
钟面是带尖拱石套的玫瑰窗、彩窗不被平台切断、烟囱砌到檐口、廊桥是实心拱、石阶连成钟楼脚下的平台、路灯不挡门窗。

v4 = v3 + 按真实建筑修正：整条街统一成维多利亚哥特复兴（深色砖墙 + 浅色石材收边），
方塔配四坡尖顶（不再是方楼顶圆锥），陡山墙代替荷兰阶梯山墙，四坡屋顶 + 山墙老虎窗，
烟囱成组立在两侧共用墙上，一层用粗石底座和高门窗显得更高；不画常春藤。
以下为 v3 的说明：

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


# ---------------------------------------------------------------- v5：真正的哥特尖拱 + 门窗按楼层对齐 + 门各不相同
import math
TRIM = (122, 130, 148)


def arch_pts(cx, bottom, w, h, n=10, closed=True):
    """等边尖拱（哥特）轮廓：两段半径 = 宽度的圆弧在顶上相交"""
    h = max(h, 0.866 * w + 4)
    ys = bottom - h + 0.866 * w
    pts = [(cx - w / 2, bottom), (cx - w / 2, ys)] if closed else [(cx - w / 2, ys)]
    for i in range(1, n + 1):
        t = math.radians(180 - 60 * i / n)
        pts.append((cx + w / 2 + w * math.cos(t), ys - w * math.sin(t)))
    for i in range(1, n + 1):
        t = math.radians(60 - 60 * i / n)
        pts.append((cx - w / 2 + w * math.cos(t), ys - w * math.sin(t)))
    if closed:
        pts.append((cx + w / 2, bottom))
    return pts, ys


def lancet(cx, bottom, w, h, lit=False, tracery=None):
    """尖拱窗。宽窗（w ≥ 50）自动加中梃和顶上的小圆窗棂"""
    pts, ys = arch_pts(cx, bottom, w, h)
    m, d = mask(); d.polygon(P(pts), fill=255); paste(solid(WARM if lit else GLASS), m, 0.5)
    bar = (150, 96, 44) if lit else (40, 46, 58)
    if tracery is None:
        tracery = w >= 50
    m, d = mask()
    if tracery:
        d.line([(X(cx), Y(bottom)), (X(cx), Y(ys - w * 0.25))], fill=255, width=2)
        r = w * 0.2
        d.ellipse([X(cx - r), Y(ys - w * 0.55 - r), X(cx + r), Y(ys - w * 0.55 + r)], outline=255, width=2)
        d.line([(X(cx - w / 2), Y(ys)), (X(cx + w / 2), Y(ys))], fill=255, width=2)
    elif w >= 34:
        d.line([(X(cx - w / 2), Y(ys)), (X(cx + w / 2), Y(ys))], fill=255, width=2)
    paste(solid(bar), m, 0.4)
    if not lit:
        m, d = mask(); d.line([(X(cx + w * 0.32), Y(ys)), (X(cx + w * 0.32), Y(bottom - 6))], fill=255, width=2)
        paste(solid(SHEEN), m, 0.5)


def hood(cx, bottom, w, h, sill=True):
    """尖拱外的浅色石窗套（跟着尖拱走）+ 窗台"""
    pts, _ = arch_pts(cx, bottom, w + 16, h + 8, closed=False)
    m, d = mask(); d.line(P(pts), fill=255, width=4)
    if sill:
        d.line([(X(cx - w / 2 - 10), Y(bottom + 4)), (X(cx + w / 2 + 10), Y(bottom + 4))], fill=255, width=4)
    paste(solid(TRIM), m, 0.4)


def door(cx, bottom, w, h, style="plain", col=(34, 30, 33)):
    """三种门：plain 单扇木门（竖木板 + 铁合页）；double 双开大门 + 门楣上的石雕；transom 方门 + 上方尖拱玻璃气窗"""
    if style == "transom":
        lintel = bottom - h * 0.68
        m, d = mask(); d.rectangle([X(cx - w / 2), Y(lintel), X(cx + w / 2), Y(bottom)], fill=255); paste(solid(col), m, 0.5)
        lancet(cx, lintel - 8, w, h * 0.32 - 8, tracery=False)
        band(cx - w / 2 - 10, cx + w / 2 + 10, lintel - 8, 8)
        m, d = mask(); d.line([(X(cx), Y(lintel)), (X(cx), Y(bottom))], fill=255, width=2); paste(solid((16, 14, 16)), m, 0.3)
        hood(cx, bottom, w, h, sill=False)
        return
    pts, ys = arch_pts(cx, bottom, w, h)
    m, d = mask(); d.polygon(P(pts), fill=255); paste(solid(col), m, 0.5)
    m, d = mask()
    if style == "double":
        d.line([(X(cx), Y(ys)), (X(cx), Y(bottom))], fill=255, width=3)
        d.line([(X(cx - w / 2), Y(ys)), (X(cx + w / 2), Y(ys))], fill=255, width=3)
        paste(solid((16, 14, 16)), m, 0.3)
        m, d = mask()                                              # 门楣（尖拱里）：浅石板 + 一个小玫瑰
        tp, _ = arch_pts(cx, ys - 3, w - 10, 0.866 * (w - 10) + 4)
        d.polygon(P(tp), fill=255); paste(solid((70, 76, 92)), m, 0.4)
        r = w * 0.13
        m, d = mask(); d.ellipse([X(cx - r), Y(ys - w * 0.38 - r), X(cx + r), Y(ys - w * 0.38 + r)], outline=255, width=2); paste(solid(TRIM), m, 0.4)
    else:
        for k in (-1, 1):
            d.line([(X(cx + k * w / 6), Y(ys - w * 0.3)), (X(cx + k * w / 6), Y(bottom))], fill=255, width=2)
        for hy in (ys + 20, bottom - 50):                            # 铁合页
            d.line([(X(cx - w / 2), Y(hy)), (X(cx - w / 6), Y(hy))], fill=255, width=3)
        paste(solid((16, 14, 16)), m, 0.3)
    hood(cx, bottom, w, h, sill=False)


def rose(cx, cy, r):
    m, d = mask(); d.ellipse([X(cx - r - 7), Y(cy - r - 7), X(cx + r + 7), Y(cy + r + 7)], fill=255); paste(solid(TRIM), m, 0.5)
    m, d = mask(); d.ellipse([X(cx - r), Y(cy - r), X(cx + r), Y(cy + r)], fill=255); paste(solid((20, 24, 34)), m, 0.5)
    m, d = mask()
    d.ellipse([X(cx - r * 0.4), Y(cy - r * 0.4), X(cx + r * 0.4), Y(cy + r * 0.4)], outline=255, width=2)
    d.line([(X(cx - r), Y(cy)), (X(cx + r), Y(cy))], fill=255, width=2)
    d.line([(X(cx), Y(cy - r)), (X(cx), Y(cy + r))], fill=255, width=2)
    paste(solid((96, 104, 122)), m, 0.4)


def quoins(x0, x1, y0, y1, side_w=26, left=True, right=True):
    m, d = mask()
    y, k = y0, 0
    while y < y1:
        ww = side_w if k % 2 == 0 else side_w * 0.6
        if left:
            d.rectangle([X(x0), Y(y), X(x0 + ww), Y(min(y + 30, y1))], fill=255)
        if right:
            d.rectangle([X(x1 - ww), Y(y), X(x1), Y(min(y + 30, y1))], fill=255)
        y += 34
        k += 1
    paste(vgrad((128, 136, 154), (40, 44, 56), y0, y1), m, 0.5)


def plinth(x0, x1, top=470):
    m, d = mask()
    for y in range(top, FLOOR, 28):
        d.line([(X(x0), Y(y)), (X(x1), Y(y))], fill=255, width=2)
    paste(solid((48, 54, 68)), m, 0.4)
    band(x0, x1, top - 14, 14)


def stack(x0, x1, top, base, pots=3):
    m, d = mask()
    d.rectangle([X(x0), Y(top), X(x1), Y(base)], fill=255)
    w = (x1 - x0) / pots
    for i in range(pots):
        d.rectangle([X(x0 + w * i + w * 0.22), Y(top - 30), X(x0 + w * i + w * 0.78), Y(top)], fill=255)
    paste(solid((30, 33, 42)), m)
    band(x0 - 6, x1 + 6, top, 10)
    m, d = mask(); d.line([(X(x1), Y(top)), (X(x1), Y(base))], fill=255, width=3); paste(solid((160, 172, 194)), m)


def gable(x0, x1, eave, apex_y, finial=True):
    cx = (x0 + x1) / 2
    m, d = mask(); d.polygon(P([(x0, eave), (cx, apex_y), (x1, eave)]), fill=255)
    paste(vgrad((92, 102, 122), (60, 68, 86), apex_y, eave), m)
    m, d = mask(); d.line(P([(x0 - 8, eave + 6), (cx, apex_y - 6), (x1 + 8, eave + 6)]), fill=255, width=7); paste(solid((34, 38, 50)), m)
    m, d = mask(); d.line(P([(cx, apex_y - 6), (x1 + 8, eave + 6)]), fill=255, width=3); paste(solid((200, 210, 228)), m)
    if finial:
        m, d = mask(); d.polygon(P([(cx - 8, apex_y), (cx, apex_y - 60), (cx + 8, apex_y)]), fill=255); paste(solid((40, 44, 56)), m)


# ======== B1 窄高砖楼：陡山墙 + 山墙小玫瑰窗；三层法式落地窗通阳台；二层双联尖窗落到阳台；一层单扇木门 + 一扇双格窗
facade((-2400, -330, -1980, FLOOR), -330, (98, 92, 98), (20, 19, 25))
gable(-2400, -1980, -330, -600)
stack(-2045, -1975, -560, -330)
quoins(-2400, -1980, -330, 470)
lit_edge(-1980, -330, 300)
band(-2400, -1980, 50); band(-2400, -1980, 330)
plinth(-2400, -1980)
rose(-2190, -440, 32)
hood(-2275, 30, 60, 250); lancet(-2275, 30, 60, 250, lit=True)        # 三层：落地尖窗通到小阳台（亮）
hood(-2080, 0, 40, 220); lancet(-2080, 0, 40, 220)                   # 三层：同一窗头高度的窄窗
hood(-2265, 310, 124, 240, sill=False)                               # 二层：双联尖窗共用一个大窗套，落到阳台
lancet(-2300, 310, 48, 230); lancet(-2230, 310, 48, 230)
hood(-2050, 290, 26, 210); lancet(-2050, 290, 26, 210)               # 二层：窄窗，窗头和双联窗对齐
door(-2290, FLOOR, 110, 250, "plain", (36, 30, 30))
hood(-2075, 520, 56, 170); lancet(-2075, 520, 56, 170)

# ======== B2 方塔：扶壁 + 垛口女儿墙 + 四坡尖顶 + 钟层百叶窗；二层三扇窄窗（中间一扇是通阳台的门）；一层双开大门
facade((-1980, -300, -1560, FLOOR), -300, (78, 90, 108), (15, 20, 27))
m, d = mask(); d.polygon(P([(-1910, -330), (-1770, -720), (-1630, -330)]), fill=255); paste(vgrad((100, 112, 136), (40, 46, 60), -720, -330), m)
m, d = mask(); d.line(P([(-1770, -720), (-1630, -330)]), fill=255, width=4); paste(solid((200, 210, 228)), m)
m, d = mask(); d.line(P([(-1910, -330), (-1770, -720)]), fill=255, width=3); paste(solid((24, 28, 38)), m)
m, d = mask(); d.polygon(P([(-1800, -440), (-1770, -500), (-1740, -440), (-1740, -410), (-1800, -410)]), fill=255); paste(solid((40, 46, 60)), m)
lancet(-1770, -414, 22, 50)
m, d = mask()
d.rectangle([X(-1985), Y(-360), X(-1555), Y(-300)], fill=255)
for bx in range(-1985, -1555, 44):
    d.rectangle([X(bx + 22), Y(-360), X(bx + 44), Y(-338)], fill=0)
paste(vgrad((96, 108, 128), (60, 68, 86), -360, -300), m)
for px in (-1985, -1585):
    m, d = mask(); d.polygon(P([(px, -360), (px + 15, -430), (px + 30, -360)]), fill=255); paste(solid((60, 68, 86)), m)
for bx in (-1980, -1585):
    m, d = mask(); d.polygon(P([(bx, -300), (bx + 25, -300), (bx + 25 + (0 if bx < -1700 else 10), FLOOR), (bx - (10 if bx < -1700 else 0), FLOOR)]), fill=255)
    paste(vgrad((96, 108, 128), (20, 24, 32), -300, FLOOR), m)
lit_edge(-1560, -300, 400)
for cx in (-1830, -1710):                                            # 钟层：一对百叶尖窗
    hood(cx, -50, 64, 210); lancet(cx, -50, 64, 210, tracery=False)
    m, d = mask()
    for ly in range(-200, -60, 20):
        d.line([(X(cx - 28), Y(ly)), (X(cx + 28), Y(ly + 8))], fill=255, width=2)
    paste(solid((48, 54, 68)), m, 0.4)
hood(-1880, 270, 28, 200); lancet(-1880, 270, 28, 200)
hood(-1770, 290, 42, 220); lancet(-1770, 290, 42, 220, lit=True)       # 中间：通阳台的落地门（亮）
hood(-1660, 270, 28, 200); lancet(-1660, 270, 28, 200)
plinth(-1975, -1565)
door(-1770, FLOOR, 120, 260, "double", (30, 32, 36))

# ======== B3 宽砖楼（伦敦联排式）：前坡屋顶 + 一个居中的山墙老虎窗 + 两端共用墙上的烟囱；
#          檐口带托石（上面能站）；二层一条通长铸铁阳台，三扇落地尖窗窗头齐平；一层：中门（方门 + 尖拱气窗）+ 两扇宽尖窗
facade((-1440, 10, -900, FLOOR), 10, (66, 80, 106), (14, 18, 28))
m, d = mask(); d.rectangle([X(-1440), Y(-230), X(-900), Y(10)], fill=255); paste(vgrad((96, 108, 132), (40, 46, 62), -230, 10), m)
m, d = mask(); d.line([(X(-1440), Y(-230)), (X(-900), Y(-230))], fill=255, width=4); paste(solid((200, 210, 228)), m)
stack(-1440, -1365, -360, -230); stack(-975, -900, -340, -230)
m, d = mask(); d.rectangle([X(-1235), Y(-190), X(-1105), Y(-10)], fill=255); paste(vgrad((80, 90, 110), (46, 52, 66), -190, -10), m)
gable(-1245, -1095, -190, -290)
hood(-1170, -30, 46, 130); lancet(-1170, -30, 46, 130)
m, d = mask(); d.rectangle([X(-1450), Y(10), X(-890), Y(40)], fill=255); paste(solid((52, 58, 74)), m)       # 檐口
m, d = mask(); d.line([(X(-1450), Y(10)), (X(-890), Y(10))], fill=255, width=3); paste(solid((170, 182, 204)), m)
m, d = mask()
for cx in range(-1430, -900, 40):                                     # 檐口下的托石
    d.rectangle([X(cx), Y(40), X(cx + 16), Y(60)], fill=255)
paste(solid((44, 50, 64)), m)
quoins(-1440, -900, 60, 470)
lit_edge(-900, 60, 330)
for cx, w, lit in ((-1350, 54, False), (-1170, 72, True), (-990, 54, False)):
    hood(cx, 300, w, 210, sill=False); lancet(cx, 300, w, 210, lit=lit)
band(-1440, -900, 330)
plinth(-1440, -900)
hood(-1330, 520, 90, 170); lancet(-1330, 520, 90, 170)
hood(-1010, 520, 90, 170); lancet(-1010, 520, 90, 170)
door(-1170, FLOOR, 90, 240, "transom", (28, 34, 40))

# ======== B4 窄店面楼：陡山墙 + 山墙小尖窗；三层落地窗通小阳台；二层楼梯间式的一高一低窗；一层是店面（招牌 + 橱窗 + 侧门）
facade((-900, -200, -620, FLOOR), -200, (102, 98, 104), (21, 20, 25))
gable(-900, -620, -200, -400)
quoins(-900, -620, -200, 400)
lit_edge(-620, -200, 380)
band(-900, -620, -200); band(-900, -620, 60)
hood(-760, -240, 30, 90); lancet(-760, -240, 30, 90)
hood(-760, 40, 50, 220); lancet(-760, 40, 50, 220, lit=True, tracery=False)
hood(-840, 330, 52, 230); lancet(-840, 330, 52, 230)
hood(-700, 210, 34, 110); lancet(-700, 210, 34, 110)
m, d = mask(); d.rectangle([X(-890), Y(400), X(-630), Y(FLOOR)], fill=255); paste(solid((40, 38, 42)), m)       # 店面木框
m, d = mask(); d.rectangle([X(-880), Y(408), X(-640), Y(438)], fill=255); paste(solid((26, 28, 34)), m)        # 招牌板（不写字）
m, d = mask(); d.rectangle([X(-880), Y(408), X(-640), Y(438)], outline=255, width=2); paste(solid(TRIM), m, 0.3)
m, d = mask(); d.rectangle([X(-870), Y(450), X(-730), Y(560)], fill=255); paste(solid((104, 72, 40)), m)       # 橱窗（很暗的暖光）
m, d = mask()
for gx in (-835, -800, -765):
    d.line([(X(gx), Y(450)), (X(gx), Y(560))], fill=255, width=2)
d.line([(X(-870), Y(490)), (X(-730), Y(490))], fill=255, width=2)
paste(solid((40, 30, 22)), m, 0.3)
m, d = mask(); d.rectangle([X(-715), Y(450), X(-650), Y(FLOOR)], fill=255); paste(solid((32, 36, 44)), m)      # 店门
m, d = mask(); d.rectangle([X(-708), Y(458), X(-657), Y(500)], fill=255); paste(solid((70, 54, 34)), m)        # 店门上的玻璃

# 广场边的石拱廊桥：哥特栏板，拱下透出远景
m, d = mask(); d.rectangle([X(-640), Y(30), X(-300), Y(183)], fill=255)
d.pieslice([X(-610), Y(66), X(-330), Y(300)], 180, 360, fill=0)
paste(vgrad((76, 86, 104), (36, 42, 54), 30, 183), m)
m, d = mask(); d.arc([X(-618), Y(58), X(-322), Y(308)], 180, 360, fill=255, width=6); paste(solid(TRIM), m, 0.5)

# 钟楼：石色最亮的一栋，两边角柱，钟面框；朱红是全图唯一焦点
facade((-260, -720, 260, FLOOR), -720, (108, 116, 134), (22, 25, 33))
for bx in (-260, 225):
    m, d = mask(); d.rectangle([X(bx), Y(-720), X(bx + 35), Y(FLOOR)], fill=255); paste(vgrad((124, 132, 150), (26, 29, 38), -720, FLOOR), m)
lit_edge(260, -720, 420, 18)
band(-260, 260, -300, 16); band(-260, 260, 20 + 40, 10)
m, d = mask()                                                    # 尖拱石套
d.polygon(P(arch_pts(0, -320, 320, 380)[0]), fill=255)
paste(solid((58, 62, 76)), m, 0.6)
m, d = mask(); d.ellipse([X(-132), Y(-582), X(132), Y(-318)], fill=255); paste(solid(TRIM), m, 0.5)
m, d = mask(); d.ellipse([X(-120), Y(-570), X(120), Y(-330)], fill=255); paste(solid((178, 50, 40)), m)
m, d = mask()                                                    # 钟面 / 玫瑰窗：一圈放射窗棂，不画卡通指针
import math
d.ellipse([X(-70), Y(-520), X(70), Y(-380)], outline=255, width=3)
for k in range(12):
    a = k * math.pi / 6
    d.line([(X(70 * math.cos(a)), Y(-450 + 70 * math.sin(a))), (X(118 * math.cos(a)), Y(-450 + 118 * math.sin(a)))], fill=255, width=3)
for k in range(12):                                              # 外圈小花瓣
    a = k * math.pi / 6 + math.pi / 12
    cx_, cy_ = 96 * math.cos(a), -450 + 96 * math.sin(a)
    d.ellipse([X(cx_ - 14), Y(cy_ - 14), X(cx_ + 14), Y(cy_ + 14)], outline=255, width=2)
paste(solid((70, 18, 14)), m, 0.5)
hood(0, 240, 90, 170)
m, d = mask(); d.polygon(P(arch_pts(0, 240, 90, 170)[0]), fill=255)
paste(solid((168, 46, 36)), m)                                   # 朱红彩窗（在 20 和 300 两层平台之间，不被切断）
m, d = mask(); d.line([(X(0), Y(100)), (X(0), Y(240))], fill=255, width=3); d.line([(X(-45), Y(148)), (X(45), Y(148))], fill=255, width=3)
paste(solid((70, 18, 14)), m, 0.4)
plinth(-260, 260)
quoins(-260, 260, -300, 470, 30)
door(0, FLOOR, 150, 300, "double", (30, 26, 28))
hood(-170, 480, 30, 130); lancet(-170, 480, 30, 130); hood(170, 480, 30, 130); lancet(170, 480, 30, 130)

# ---------------------------------------------------------------- 能站的面：阳台 / 桥 / 檐（剪影 + 栏杆上沿受光）
for x0, x1, y, kind in SEC["platforms"]:
    if x1 < X0 or x0 > X1:
        continue
    if kind in ("balcony", "ring", "eave", "cornice"):
        sh, sd = mask()
        sd.polygon(P([(x0 - 6, y + 16), (x1 + 6, y + 16), (x1 - 34, y + 96), (x0 - 46, y + 96)]), fill=120)
        paste(solid((8, 10, 16)), sh, 6)
    m, d = mask()
    r, rd = mask()
    if kind in ("balcony", "ring"):
        d.rectangle([X(x0), Y(y), X(x1), Y(y + 16)], fill=255)
        stone = kind == "ring"          # 宽楼和钟楼用石栏，其他用铁栏
        step = 40 if stone else 24
        for bx in range(int(x0) + 6, int(x1), step):
            d.rectangle([X(bx), Y(y - 50), X(bx + (12 if stone else 3)), Y(y)], fill=255)
        rd.line([(X(x0), Y(y - 52)), (X(x1), Y(y - 52))], fill=255, width=3 if stone else 2)
        for bx in range(int(x0) + 30, int(x1) - 10, 140):
            d.polygon(P([(bx, y + 16), (bx + 22, y + 16), (bx, y + 46)]), fill=255)
    elif kind == "cornice":
        pass
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
    sw = min(230.0, (x1 - x0) * 0.6)
    right = x1 + 40 if abs(x1 + 300) < 1 else x1                     # 钟楼脚下的平台一直接到钟楼墙根
    for i in range(3):
        sy = y + (FLOOR - y) * i / 3
        d.rectangle([X(x0 + sw * (2 - i) / 3), Y(sy), X(right), Y(FLOOR)], fill=255)
    paste(vgrad((74, 82, 98), (30, 34, 44), y, FLOOR), m, 0.4)
    band(x0 + sw * 2 / 3, right, y, 10)

# ---------------------------------------------------------------- 路灯 + 暖光 / 红光的光晕
streets = [(x, y) for x, y, k in SEC["lamps"] if k == "street" and X0 <= x <= X1] + [(-400, 470)]
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
