"""雨夜河岸街：明暗草图 v4（结构参考图）。

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


# ---------------------------------------------------------------- v4 新增的真实构造部件
TRIM = (122, 130, 148)        # 浅色石材收边（窗套、隅石、腰线）


def quoins(x0, x1, y0, y1, side_w=26):
    """楼角隅石：一长一短交替的浅色石块"""
    m, d = mask()
    y = y0
    k = 0
    while y < y1:
        h = 34
        for xs in ((x0, x0 + (side_w if k % 2 == 0 else side_w * 0.6)), (x1 - (side_w if k % 2 == 0 else side_w * 0.6), x1)):
            d.rectangle([X(xs[0]), Y(y), X(xs[1]), Y(min(y + h - 4, y1))], fill=255)
        y += h
        k += 1
    paste(vgrad((128, 136, 154), (40, 44, 56), y0, y1), m, 0.5)


def plinth(x0, x1, top=470):
    """一层粗石底座：几道横向石缝，让一层显得更高、更重"""
    m, d = mask()
    for y in range(top, FLOOR, 28):
        d.line([(X(x0), Y(y)), (X(x1), Y(y))], fill=255, width=2)
    paste(solid((48, 54, 68)), m, 0.4)
    band(x0, x1, top - 14, 14)


def stack(x0, x1, top, base, pots=3):
    """成组的烟囱：一根砖砌烟囱身 + 顶上几个烟囱口"""
    m, d = mask()
    d.rectangle([X(x0), Y(top), X(x1), Y(base)], fill=255)
    w = (x1 - x0) / pots
    for i in range(pots):
        d.rectangle([X(x0 + w * i + w * 0.2), Y(top - 34), X(x0 + w * i + w * 0.8), Y(top)], fill=255)
    paste(solid((26, 30, 40)), m)
    band(x0 - 6, x1 + 6, top, 8)
    m, d = mask(); d.line([(X(x1), Y(top)), (X(x1), Y(base))], fill=255, width=3); paste(solid((170, 182, 204)), m)


def gable(x0, x1, eave, apex_y, finial=True):
    """陡山墙（哥特复兴）：墙面一直到尖顶，右坡亮边，顶上一根尖饰"""
    cx = (x0 + x1) / 2
    m, d = mask(); d.polygon(P([(x0, eave), (cx, apex_y), (x1, eave)]), fill=255)
    paste(vgrad((92, 102, 122), (60, 68, 86), apex_y, eave), m)
    m, d = mask(); d.line(P([(x0 - 8, eave + 6), (cx, apex_y - 6), (x1 + 8, eave + 6)]), fill=255, width=7); paste(solid((34, 38, 50)), m)
    m, d = mask(); d.line(P([(cx, apex_y - 6), (x1 + 8, eave + 6)]), fill=255, width=3); paste(solid((200, 210, 228)), m)
    if finial:
        m, d = mask(); d.polygon(P([(cx - 8, apex_y), (cx, apex_y - 60), (cx + 8, apex_y)]), fill=255); paste(solid((40, 44, 56)), m)


def hood(cx, bottom, w, h):
    """尖窗外的浅色石窗套"""
    m, d = mask()
    d.arc([X(cx - w / 2 - 8), Y(bottom - h - 8), X(cx + w / 2 + 8), Y(bottom - h + w + 8)], 180, 360, fill=255, width=4)
    d.line([(X(cx - w / 2 - 10), Y(bottom + 4)), (X(cx + w / 2 + 10), Y(bottom + 4))], fill=255, width=4)
    paste(solid(TRIM), m, 0.4)


def door(cx, bottom, w, h):
    """木门：深色木板 + 中缝 + 浅色石门套（门不是玻璃，没有反光线）"""
    m, d = mask()
    d.rectangle([X(cx - w / 2), Y(bottom - h + w / 2), X(cx + w / 2), Y(bottom)], fill=255)
    d.pieslice([X(cx - w / 2), Y(bottom - h), X(cx + w / 2), Y(bottom - h + w)], 180, 360, fill=255)
    paste(solid((34, 30, 33)), m, 0.5)
    m, d = mask(); d.line([(X(cx), Y(bottom - h + w * 0.3)), (X(cx), Y(bottom))], fill=255, width=2); paste(solid((16, 14, 16)), m, 0.3)
    m, d = mask()
    d.arc([X(cx - w / 2 - 10), Y(bottom - h - 10), X(cx + w / 2 + 10), Y(bottom - h + w + 10)], 180, 360, fill=255, width=6)
    d.line([(X(cx - w / 2 - 7), Y(bottom - h + w / 2)), (X(cx - w / 2 - 7), Y(bottom))], fill=255, width=6)
    d.line([(X(cx + w / 2 + 7), Y(bottom - h + w / 2)), (X(cx + w / 2 + 7), Y(bottom))], fill=255, width=6)
    paste(solid(TRIM), m, 0.5)


def rose(cx, cy, r):
    """小玫瑰窗：石框 + 深色玻璃 + 十字和内圈窗棂（不是一个黑洞）"""
    m, d = mask(); d.ellipse([X(cx - r - 7), Y(cy - r - 7), X(cx + r + 7), Y(cy + r + 7)], fill=255); paste(solid(TRIM), m, 0.5)
    m, d = mask(); d.ellipse([X(cx - r), Y(cy - r), X(cx + r), Y(cy + r)], fill=255); paste(solid((20, 24, 34)), m, 0.5)
    m, d = mask()
    d.ellipse([X(cx - r * 0.4), Y(cy - r * 0.4), X(cx + r * 0.4), Y(cy + r * 0.4)], outline=255, width=2)
    d.line([(X(cx - r), Y(cy)), (X(cx + r), Y(cy))], fill=255, width=2)
    d.line([(X(cx), Y(cy - r)), (X(cx), Y(cy + r))], fill=255, width=2)
    paste(solid((96, 104, 122)), m, 0.4)


# B1 窄高楼：陡山墙（带尖饰）+ 山墙上的小玫瑰窗；右侧共用墙上一组烟囱
facade((-2400, -330, -1980, FLOOR), -330, (98, 92, 98), (20, 19, 25))
gable(-2400, -1980, -330, -600)
stack(-2040, -1975, -640, -330)
quoins(-2400, -1980, -330, 470)
lit_edge(-1980, -330, 300)
band(-2400, -1980, 330); band(-2400, -1980, 50)
plinth(-2400, -1980)
rose(-2190, -440, 32)
hood(-2275, 0, 56, 220); lancet(-2275, 0, 56, 220, lit=True)       # 三层：高尖窗（亮）
hood(-2090, -20, 40, 160); lancet(-2090, -20, 40, 160)
hood(-2270, 290, 104, 210); lancet(-2300, 290, 44, 210); lancet(-2240, 290, 44, 210)   # 二层：双联尖窗共用一个窗套
lancet(-2050, 270, 24, 170)
door(-2290, FLOOR, 120, 260)                                       # 一层：高大的门 + 高窗
lancet(-2070, 530, 60, 170)

# B2 方塔：扶壁 + 带垛口的女儿墙步道 + 四坡尖顶 + 上层一对百叶尖窗（钟层做法，不用成排圆窗）（左面背光、右面受光、中间一道硬棱）
facade((-1980, -300, -1560, FLOOR), -300, (78, 90, 108), (15, 20, 27))
m, d = mask(); d.polygon(P([(-1910, -330), (-1770, -720), (-1630, -330)]), fill=255); paste(vgrad((100, 112, 136), (40, 46, 60), -720, -330), m)
m, d = mask(); d.line(P([(-1770, -720), (-1630, -330)]), fill=255, width=4); paste(solid((200, 210, 228)), m)     # 只有右边沿受月光
m, d = mask(); d.line(P([(-1910, -330), (-1770, -720)]), fill=255, width=3); paste(solid((24, 28, 38)), m)
m, d = mask(); d.polygon(P([(-1800, -470), (-1770, -520), (-1740, -470), (-1740, -420), (-1800, -420)]), fill=255); paste(solid((40, 46, 60)), m)   # 尖顶上的小老虎窗
lancet(-1770, -425, 24, 50)
m, d = mask()                                                      # 女儿墙垛口
d.rectangle([X(-1985), Y(-360), X(-1555), Y(-300)], fill=255)
for bx in range(-1985, -1555, 44):
    d.rectangle([X(bx + 22), Y(-360), X(bx + 44), Y(-338)], fill=0)
paste(vgrad((96, 108, 128), (60, 68, 86), -360, -300), m)
for px in (-1985, -1585):                                          # 角上的小尖塔
    m, d = mask(); d.polygon(P([(px, -360), (px + 15, -430), (px + 30, -360)]), fill=255); paste(solid((60, 68, 86)), m)
for bx in (-1980, -1585):                                          # 扶壁（往下渐宽）
    m, d = mask(); d.polygon(P([(bx, -300), (bx + 25, -300), (bx + 25 + (0 if bx < -1700 else 10), FLOOR), (bx - (10 if bx < -1700 else 0), FLOOR)]), fill=255)
    paste(vgrad((96, 108, 128), (20, 24, 32), -300, FLOOR), m)
lit_edge(-1560, -300, 400)
for cx in (-1830, -1710):                                          # 上层：一对带百叶的尖拱窗
    hood(cx, -60, 60, 200); lancet(cx, -60, 60, 200)
    m, d = mask()
    for ly in range(-220, -70, 22):
        d.line([(X(cx - 26), Y(ly)), (X(cx + 26), Y(ly + 8))], fill=255, width=2)
    paste(solid((44, 50, 64)), m, 0.4)
for cx, lit in ((-1880, False), (-1770, True), (-1660, False)):
    hood(cx, 270, 26, 190); lancet(cx, 270, 26, 190, lit)
plinth(-1975, -1565)
door(-1770, FLOOR, 110, 250)

# B3 宽楼：四坡屋顶 + 两个山墙老虎窗 + 檐口后面带朴素石女儿墙的步道 + 两端共用墙上的烟囱 + 一层凸窗
facade((-1440, 10, -900, FLOOR), 10, (66, 80, 106), (14, 18, 28))
m, d = mask(); d.polygon(P([(-1440, 10), (-1310, -300), (-1030, -300), (-900, 10)]), fill=255); paste(vgrad((96, 108, 132), (40, 46, 62), -300, 10), m)
m, d = mask(); d.line(P([(-1310, -300), (-1030, -300)]), fill=255, width=4); d.line(P([(-1030, -300), (-900, 10)]), fill=255, width=4)
paste(solid((200, 210, 228)), m)
stack(-1450, -1395, -400, 10); stack(-950, -895, -380, 10)
for cx in (-1300, -1060):                                         # 两个一样构造的山墙老虎窗
    m, d = mask(); d.rectangle([X(cx - 45), Y(-180), X(cx + 45), Y(-60)], fill=255); paste(solid((46, 52, 66)), m)
    gable(cx - 52, cx + 52, -180, -250, finial=True)
    lancet(cx, -70, 34, 90)
m, d = mask()                                                      # 朴素的石女儿墙
d.rectangle([X(-1445), Y(-30), X(-895), Y(10)], fill=255)
paste(solid((58, 66, 84)), m)
band(-1445, -895, -34, 8)                                          # 女儿墙压顶
quoins(-1440, -900, 10, 470)
lit_edge(-900, -30, 330)
band(-1440, -900, 10, 16)
plinth(-1440, -900)
square(-1385, 290, 70, 160); square(-1290, 290, 70, 160)
square(-1000, 310, 64, 150)
m, d = mask(); d.polygon(P([(-1210, 250), (-1070, 250), (-1082, 470), (-1198, 470)]), fill=255)
paste(vgrad((96, 108, 130), (40, 46, 60), 250, 470), m)
m, d = mask(); d.polygon(P([(-1198, 470), (-1082, 470), (-1110, 510), (-1170, 510)]), fill=255); paste(solid((40, 46, 58)), m)   # 凸窗下的托石
m, d = mask(); d.line(P([(-1070, 250), (-1082, 470)]), fill=255, width=3); paste(solid((170, 182, 204)), m)
square(-1140, 440, 70, 150, lit=True)
door(-1330, FLOOR, 130, 270)
door(-990, FLOOR, 84, 210)

# B4 窄店面楼：陡山墙 + 左侧烟囱；一层是带帆布雨棚的店面
facade((-900, -200, -620, FLOOR), -200, (102, 98, 104), (21, 20, 25))
gable(-900, -620, -200, -400)
quoins(-900, -620, -200, 470)
lit_edge(-620, -200, 380)
band(-900, -620, -200)
hood(-760, 20, 46, 170); lancet(-760, 20, 46, 170, lit=True)
hood(-760, -240, 30, 90); lancet(-760, -240, 30, 90)
hood(-840, 330, 52, 230); lancet(-840, 330, 52, 230)
lancet(-700, 210, 34, 110)
m, d = mask(); d.rectangle([X(-870), Y(430), X(-670), Y(570)], fill=255); paste(solid((40, 44, 56)), m)   # 店面木框
m, d = mask(); d.rectangle([X(-860), Y(440), X(-680), Y(560)], fill=255); paste(solid((96, 66, 36)), m)

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
d.polygon(P([(-160, -330), (-160, -560), (0, -680), (160, -560), (160, -330)]), fill=255)
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
hood(0, 240, 100, 170)
m, d = mask(); d.rectangle([X(-50), Y(120), X(50), Y(240)], fill=255); d.pieslice([X(-50), Y(70), X(50), Y(170)], 180, 360, fill=255)
paste(solid((168, 46, 36)), m)                                   # 朱红彩窗（在 20 和 300 两层平台之间，不被切断）
m, d = mask(); d.line([(X(0), Y(80)), (X(0), Y(240))], fill=255, width=3); d.line([(X(-50), Y(165)), (X(50), Y(165))], fill=255, width=3)
paste(solid((70, 18, 14)), m, 0.4)
plinth(-260, 260)
quoins(-260, 260, -300, 470, 30)
door(0, FLOOR, 150, 300)
lancet(-170, 480, 30, 120); lancet(170, 480, 30, 120)

# ---------------------------------------------------------------- 能站的面：阳台 / 桥 / 檐（剪影 + 栏杆上沿受光）
for x0, x1, y, kind in SEC["platforms"]:
    if x1 < X0 or x0 > X1:
        continue
    if kind in ("balcony", "ring", "eave"):
        sh, sd = mask()
        sd.polygon(P([(x0 - 6, y + 16), (x1 + 6, y + 16), (x1 - 34, y + 96), (x0 - 46, y + 96)]), fill=120)
        paste(solid((8, 10, 16)), sh, 6)
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
