"""「雨夜河岸街」钟楼广场右半边（r1）的明暗草图：GPT 照着画成图，规则同 v9。
画面范围 x −150 ~ 2560（和左半边同一比例，1672×941），最左边 −150 ~ 263 直接贴上已经画好的成图（钟楼右半），
GPT 照着这一段往右接，接缝才自然。背景直接用游戏里的天空、远景成图。
第三版（第一版成图被否；第二版草图两位评审 5.7 / 5.8，按合并意见修改）：四栋窄楼宽窄高低错开——
窄高的当铺（单陡山墙）/ 矮的船具行（平顶、木车门）/ 最暗的方塔式警署（四坡陡顶、蓝色警灯）/ 折线屋顶住宅；
焦点是钟楼和当铺之间亮雾前的河岸铸铁吊车（吊臂能站）。阳台各在自己的轴线上、不连成通长横带。
画法函数原样复制自 make_rain_street_value_v9.py 第 111–387 行（v9 脚本是一次性执行的，不能 import）。
用法：python -I tools/art/make_rain_street_value_r1.py assets/data/rain_street_layout.json <输出.png>
"""
import sys, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

LAYOUT, OUT = sys.argv[1], sys.argv[2]
SEC = json.load(open(LAYOUT, encoding="utf-8"))["sections"][0]
X0, X1, Y0, Y1 = -150, 2560, -700, 826
W, H = 1672, 941
S = W / (X1 - X0)
FLOOR = 580
ART_X = 263          ## 左半边成图的右边缘（世界 x）：这以左是成图，以右是草图


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


# ---------------------------------------------------------------- 背景：游戏里的天空 + 远景成图（远景用镜像平铺的下一张）
img = np.asarray(Image.open("assets/image/rain_street/sky.png").convert("RGB").resize((W, H), Image.LANCZOS), np.float32).copy()
farim = Image.open("assets/image/rain_street/far_city.png").convert("RGBA").transpose(Image.FLIP_LEFT_RIGHT)
fy = int(round(Y(-781)))
farc = farim.crop((0, -fy, W, H)) if fy < 0 else farim
bg = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
bg.alpha_composite(farc, (0, max(fy, 0)))
fog = np.asarray(farim, np.float32)[-1, :, :3].mean(0)
img = np.asarray(bg.convert("RGB"), np.float32).copy()
img[min(H, farc.height + max(fy, 0)):] = fog
# 左半边成图（近景层，带透明）里 x −150 ~ 263 这一段：最后盖回去
near = Image.open("assets/image/rain_street/near_plaza_left.png").convert("RGBA")
strip = near.crop((int(round((X0 + 2447) * S)), 0, near.width, near.height))


# ======== 以下画法函数原样复制自 make_rain_street_value_v9.py 第 111–387 行
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
    m, d = mask(); d.line([(X(x0), Y(y)), (X(x1), Y(y))], fill=255, width=2); paste(solid((96, 104, 122)), m, 0.4)


GLASS, SHEEN, WARM = (12, 15, 22), (58, 70, 92), (232, 200, 132)


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


# ======== v7：立面按“轴线”排门窗（古典立面构图规则）
#   1. 每栋楼先定几条竖向轴线，所有楼层的门窗都正好落在轴线上，上下对齐；轴线相对楼的中线左右对称
#   2. 楼层越往上窗越矮：一层门最高 → 二层（主层）落地窗最高 → 三层较矮 → 山墙 / 阁楼最小
#   3. 同一层的窗头齐平；窗与窗之间的墙垛不窄于窗宽；靠楼边留出半个窗宽以上
#   4. 阳台以轴线为中心，或者整层通长；山墙上的窗落在中线上
#   5. 窗少而大：窄楼 2 条轴线，宽楼 3 条，最窄的店面楼 1 条

# ======== v9：每栋楼一个身份（河岸货栈 / 行会会馆 / 商住楼 / 小酒馆）；强调竖向；墙面不画砖纹；阳台按楼错开高度、栏杆分样式
IRON = (22, 24, 30)
WOOD = (42, 36, 34)
BRICK_ARCH = (96, 92, 98)


def seg_window(cx, bottom, w, h, lit=False):
    """货栈窗：长方形 + 浅弧窗头，铸铁小方格"""
    rise = w * 0.16
    top = bottom - h
    m, d = mask()
    d.rectangle([X(cx - w / 2), Y(top + rise), X(cx + w / 2), Y(bottom)], fill=255)
    d.pieslice([X(cx - w / 2), Y(top), X(cx + w / 2), Y(top + 2 * rise)], 180, 360, fill=255)
    paste(solid(WARM if lit else GLASS), m, 0.5)
    m, d = mask()
    d.line([(X(cx), Y(top + rise * 0.4)), (X(cx), Y(bottom))], fill=255, width=2)
    gy = top + rise + (h - rise) / 3
    while gy < bottom - 4:
        d.line([(X(cx - w / 2), Y(gy)), (X(cx + w / 2), Y(gy))], fill=255, width=2)
        gy += (h - rise) / 3
    paste(solid((150, 120, 70) if lit else (40, 46, 58)), m, 0.4)
    m, d = mask()
    d.arc([X(cx - w / 2 - 8), Y(top - 8), X(cx + w / 2 + 8), Y(top + 2 * rise + 8)], 180, 360, fill=255, width=6)
    d.line([(X(cx - w / 2 - 6), Y(bottom + 4)), (X(cx + w / 2 + 6), Y(bottom + 4))], fill=255, width=4)
    paste(solid(BRICK_ARCH), m, 0.4)


def loading_door(cx, bottom, w, h, lit=False):
    rise = w * 0.14
    top = bottom - h
    m, d = mask()
    d.rectangle([X(cx - w / 2), Y(top + rise), X(cx + w / 2), Y(bottom)], fill=255)
    d.pieslice([X(cx - w / 2), Y(top), X(cx + w / 2), Y(top + 2 * rise)], 180, 360, fill=255)
    if lit:
        paste(vgrad((214, 172, 100), (110, 82, 46), top, bottom), m, 0.5)
        m, d = mask()
        d.rectangle([X(cx - w / 2 - 30), Y(top + rise + 6), X(cx - w / 2 - 4), Y(bottom)], fill=255)
        d.rectangle([X(cx + w / 2 + 4), Y(top + rise + 6), X(cx + w / 2 + 30), Y(bottom)], fill=255)
        paste(solid(WOOD), m, 0.4)
        m, d = mask()
        d.rectangle([X(cx - w / 2 + 6), Y(bottom - 46), X(cx - 4), Y(bottom)], fill=255)
        d.rectangle([X(cx + 2), Y(bottom - 30), X(cx + w / 2 - 10), Y(bottom)], fill=255)
        paste(solid((64, 46, 30)), m, 0.4)
    else:
        paste(solid(WOOD), m, 0.5)
        m, d = mask()
        d.line([(X(cx), Y(top + rise)), (X(cx), Y(bottom))], fill=255, width=2)
        d.line([(X(cx - w / 2), Y(top + h * 0.75)), (X(cx), Y(top + h * 0.35))], fill=255, width=2)
        d.line([(X(cx + w / 2), Y(top + h * 0.75)), (X(cx), Y(top + h * 0.35))], fill=255, width=2)
        paste(solid((24, 20, 20)), m, 0.3)
    m, d = mask()
    d.arc([X(cx - w / 2 - 9), Y(top - 9), X(cx + w / 2 + 9), Y(top + 2 * rise + 9)], 180, 360, fill=255, width=7)
    paste(solid(BRICK_ARCH), m, 0.4)


def pilaster(x, y0, y1, w=16):
    """细长的竖向壁柱线：把视线往上拉"""
    m, d = mask(); d.rectangle([X(x), Y(y0), X(x + w), Y(y1)], fill=255); paste(vgrad((96, 102, 118), (26, 28, 36), y0, FLOOR), m, 0.5)
    m, d = mask(); d.line([(X(x + w), Y(y0)), (X(x + w), Y(y1))], fill=255, width=2); paste(solid((140, 150, 172)), m, 0.4)


def gargoyle(x, y, side):
    """石像鬼：蹲着，朝 side 方向伸头"""
    s = side
    m, d = mask()
    d.polygon(P([(x, y), (x + s * 40, y + 4), (x + s * 70, y - 12), (x + s * 84, y), (x + s * 60, y + 16), (x + s * 36, y + 24), (x, y + 30)]), fill=255)
    d.polygon(P([(x + s * 40, y + 4), (x + s * 48, y - 30), (x + s * 64, y - 6)]), fill=255)
    paste(solid((44, 48, 60)), m, 0.4)
    m, d = mask(); d.line(P([(x + s * 84, y), (x + s * 70, y - 12), (x + s * 40, y + 4)]), fill=255, width=2); paste(solid((150, 160, 182)), m, 0.4)


def flat_wall(x0, y0, x1, top_col, bot_col, top_y):
    """平涂墙面（不画砖纹）"""
    facade((x0, y0, x1, FLOOR), top_y, top_col, bot_col)


# ======== 右半边（r1 第三版，按两位评审合并修改）：
#   调子压到和左半边同一档，全图最亮的大面积只留吊车背后的雾；维多利亚码头吊车（镂空格构、弧形斜撑）；
#   天际线：警署最高最暗、当铺荷兰式曲线山墙次之、船具行最矮；三层平台高低成锯齿；门窗全部落在轴线上；
#   平台托座按楼各不相同；街面层每四百左右一处暗暖的光块
def sk(x):   # 草图部分只画在成图接缝右边
    return max(x, ART_X)


def bez(p0, p1, p2, n=16):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]) for t in [i / n for i in range(n + 1)]]


def round_window(cx, bottom, w, h, lit=False, frame=(58, 64, 80), glow=None):
    """意式圆头窗 + 连在窗上的石框"""
    top = bottom - h
    m, d = mask()
    d.rectangle([X(cx - w / 2 - 8), Y(top + w / 2), X(cx + w / 2 + 8), Y(bottom + 6)], fill=255)
    d.pieslice([X(cx - w / 2 - 8), Y(top - 8), X(cx + w / 2 + 8), Y(top + w + 8)], 180, 360, fill=255)
    paste(solid(frame), m, 0.4)
    m, d = mask()
    d.rectangle([X(cx - w / 2), Y(top + w / 2), X(cx + w / 2), Y(bottom)], fill=255)
    d.pieslice([X(cx - w / 2), Y(top), X(cx + w / 2), Y(top + w)], 180, 360, fill=255)
    paste(solid(glow if glow else (WARM if lit else GLASS)), m, 0.5)
    m, d = mask()
    d.line([(X(cx), Y(top + w * 0.2)), (X(cx), Y(bottom))], fill=255, width=2)
    d.line([(X(cx - w / 2), Y(top + h * 0.45)), (X(cx + w / 2), Y(top + h * 0.45))], fill=255, width=2)
    paste(solid((150, 110, 64) if (lit or glow) else (38, 42, 54)), m, 0.4)


# ---------------------------------------------------------------- 背景压暗：船具行缺口后面的暗屋顶、右边缘、吊车背后只留一束亮雾
m, d = mask(); d.ellipse([X(300), Y(0), X(720), Y(600)], fill=55); paste(solid((122, 136, 160)), m, 60)
m, d = mask()                                                             # 船具行矮下去露出的：雾里的暗后排屋顶 + 烟囱
d.polygon(P([(990, 130), (990, -40), (1070, -110), (1150, -40), (1150, -70), (1290, -70), (1290, -20), (1350, -90), (1460, -10), (1460, 130)]), fill=255)
for cx in (1110, 1240, 1400):
    d.rectangle([X(cx), Y(-150), X(cx + 26), Y(-40)], fill=255)
paste(solid((40, 46, 60)), m, 1.4)
m, d = mask(); d.rectangle([X(2395), Y(-700), X(X1), Y(FLOOR)], fill=150); paste(solid((20, 24, 34)), m, 30)

# 巷子深处的后排楼（更小、更暗）
m, d = mask()
d.rectangle([X(1470), Y(-40), X(1600), Y(FLOOR)], fill=255)
d.polygon(P([(1470, -40), (1535, -120), (1600, -40)]), fill=255)
paste(vgrad((52, 60, 76), (30, 35, 46), -120, 560), m, 1.2)
m, d = mask()                                                             # 巷口：半开的铸铁大门
for gx in range(1462, 1612, 16):
    d.line([(X(gx), Y(410)), (X(gx), Y(FLOOR))], fill=255, width=2)
d.line([(X(1458), Y(414)), (X(1614), Y(414))], fill=255, width=3)
d.arc([X(1458), Y(344), X(1614), Y(484)], 180, 360, fill=255, width=3)
paste(solid(IRON), m, 0.3)

# ---- 焦点：维多利亚码头铸铁吊车（石台 [420,650] 上）：镂空格构立柱 + 三角格构柱头 + 箱形格构吊臂（顶面 140 能站）
#      + 吊臂下的弧形铸铁斜撑 + 两根拉杆 + 长铁索吊钩 + 脚下的绞盘（鼓筒 + 大小齿轮）
CR = (12, 13, 17)
m, d = mask()
for xx in (574, 636):                                                     # 立柱两根弦杆
    d.line([(X(xx), Y(140)), (X(xx), Y(470))], fill=255, width=4)
yy = 150
while yy < 460:                                                           # X 斜撑（透光）
    d.line([(X(574), Y(yy)), (X(636), Y(yy + 40))], fill=255, width=2)
    d.line([(X(636), Y(yy)), (X(574), Y(yy + 40))], fill=255, width=2)
    d.line([(X(574), Y(yy)), (X(636), Y(yy))], fill=255, width=2)
    yy += 40
d.line([(X(550), Y(140)), (X(605), Y(-100))], fill=255, width=4)          # 三角柱头
d.line([(X(660), Y(140)), (X(605), Y(-100))], fill=255, width=4)
d.line([(X(570), Y(54)), (X(640), Y(54))], fill=255, width=2)
d.line([(X(560), Y(100)), (X(624), Y(20))], fill=255, width=2)
d.ellipse([X(593), Y(-112), X(617), Y(-88)], outline=255, width=3)        # 顶上的滑轮
for yb in (140, 180):                                                     # 吊臂：上下弦
    d.line([(X(380), Y(yb)), (X(660), Y(yb))], fill=255, width=4)
k = 0
for xx in range(380, 660, 35):                                            # 吊臂腹杆
    d.line([(X(xx), Y(140 if k % 2 == 0 else 180)), (X(xx + 35), Y(180 if k % 2 == 0 else 140))], fill=255, width=2)
    k += 1
d.line([(X(380), Y(140)), (X(380), Y(180))], fill=255, width=4)
d.line(P(bez((600, 400), (420, 380), (395, 182))), fill=255, width=5)    # 弧形铸铁斜撑
d.line([(X(605), Y(-100)), (X(385), Y(140))], fill=255, width=3)          # 拉杆
d.line([(X(605), Y(-100)), (X(655), Y(140))], fill=255, width=3)
d.rectangle([X(420), Y(180), X(446), Y(196)], fill=255)                   # 小车
d.line([(X(433), Y(196)), (X(433), Y(420))], fill=255, width=2)           # 铁索 + 吊钩
d.arc([X(421), Y(410), X(445), Y(438)], 0, 200, fill=255, width=4)
d.rectangle([X(520), Y(420), X(560), Y(460)], fill=255)                   # 绞盘：鼓筒 + 大小齿轮 + 支架
d.ellipse([X(500), Y(380), X(560), Y(440)], outline=255, width=5)
d.ellipse([X(548), Y(418), X(574), Y(444)], outline=255, width=4)
d.line([(X(500), Y(470)), (X(530), Y(410))], fill=255, width=3); d.line([(X(560), Y(470)), (X(530), Y(410))], fill=255, width=3)
paste(solid(CR), m, 0.4)
m, d = mask()
d.line([(X(638), Y(140)), (X(638), Y(470))], fill=255, width=2); d.line([(X(605), Y(-100)), (X(660), Y(140))], fill=255, width=2)
paste(solid((120, 132, 156)), m, 0.4)

# ---- A 当铺（720–1000，窄高，轴线 805 / 915）：荷兰式曲线阶梯山墙（山尖 −520）；二层短铁阳台、三层素石檐；
#      一层深色木门脸：分格橱窗暗暖光 + 木门；三颗挂球从左墙角、店招高度伸出
flat_wall(720, -300, 1000, (60, 64, 76), (12, 14, 19), -300)
half = [(0, -300), (0, -346), (22, -346), (30, -372), (42, -394), (62, -398), (70, -424), (82, -446), (102, -450), (108, -478), (120, -506), (140, -520)]
gab = [(720 + dx, y) for dx, y in half] + [(1000 - dx, y) for dx, y in reversed(half)]
m, d = mask(); d.polygon(P(gab), fill=255); paste(vgrad((74, 80, 96), (52, 58, 72), -520, -300), m)
m, d = mask(); d.line(P(gab[:-1]), fill=255, width=5); paste(solid((34, 38, 50)), m)
m, d = mask(); d.line(P([(1000 - dx, y) for dx, y in reversed(half)]), fill=255, width=3); paste(solid((176, 188, 210)), m)
stack(735, 772, -500, -346, pots=2)
for px in (720, 984):
    pilaster(px, -300, 470)
lit_edge(1000, -300, 300)
band(720, 1000, -300, 10)
plinth(720, 1000)
seg_window(860, -372, 36, 90)                                             # 山墙小窗
for ax in (805, 915):
    seg_window(ax, 10, 42, 170)                                           # 三层（窗前素石檐）
    seg_window(ax, 290, 46, 220)                                          # 二层（窗前短铁阳台）
m, d = mask(); d.rectangle([X(728), Y(374), X(992), Y(FLOOR)], fill=255); paste(solid((28, 25, 28)), m)
m, d = mask(); d.rectangle([X(736), Y(382), X(984), Y(408)], fill=255); paste(solid((20, 18, 22)), m)
m, d = mask(); d.rectangle([X(736), Y(382), X(984), Y(408)], outline=255, width=2); paste(solid((96, 90, 86)), m, 0.3)
m, d = mask(); d.rectangle([X(745), Y(424), X(865), Y(560)], fill=255); paste(vgrad((112, 88, 58), (72, 56, 38), 424, 560), m, 0.5)
m, d = mask()
for gx in (775, 805, 835):
    d.line([(X(gx), Y(424)), (X(gx), Y(560))], fill=255, width=3)
d.line([(X(745), Y(470)), (X(865), Y(470))], fill=255, width=3)
d.rectangle([X(738), Y(416), X(872), Y(568)], outline=255, width=6)
paste(solid((32, 30, 34)), m, 0.4)
m, d = mask(); d.rectangle([X(888), Y(424), X(942), Y(FLOOR)], fill=255); paste(solid(WOOD), m)
m, d = mask(); d.line([(X(915), Y(424)), (X(915), Y(FLOOR))], fill=255, width=2); paste(solid((20, 16, 16)), m)
m, d = mask()                                                             # 三颗挂球：店招高度从左墙角伸出，压在亮雾上
d.line([(X(720), Y(380)), (X(656), Y(380))], fill=255, width=4)
d.line([(X(720), Y(410)), (X(676), Y(380))], fill=255, width=3)
for bx in (684, 666):
    d.line([(X(bx), Y(380)), (X(bx), Y(398))], fill=255, width=2)
paste(solid(IRON), m, 0.3)
m, d = mask()
for cx, cy in ((675, 410), (662, 434), (688, 434)):
    d.ellipse([X(cx - 12), Y(cy - 12), X(cx + 12), Y(cy + 12)], fill=255)
paste(solid((116, 96, 60)), m, 0.4)
m, d = mask(); d.rectangle([X(850), Y(160), X(870), Y(196)], fill=255); paste(solid((226, 200, 140)), m, 0.5)    # 二层壁灯
m, d = mask(); d.line([(X(860), Y(196)), (X(860), Y(212))], fill=255, width=3); d.line([(X(840), Y(160)), (X(860), Y(150))], fill=255, width=3); paste(solid(IRON), m)

# ---- B 船具行（1000–1450，两层，屋顶 120 带矮砖护墙）：平涂深色伦敦砖墙；两条轴线 1110 / 1340 + 中轴一列装卸门；
#      1110：一层砖砌弧头车门（竖木板）+ 木雨棚（360），二层弧头窗；1340：一层维多利亚店面（暗暖光，马灯和成卷缆绳的剪影），二层弧头窗；
#      中轴 1225：二层卸货门 + 门上方挑出的吊货梁和滑轮；楼右角铁托架挂一只铁锚招牌（不写字）
facade((1000, 120, 1450, FLOOR), 120, (58, 52, 54), (14, 12, 15))
band(1000, 1450, 120, 10)
lit_edge(1450, 120, 300)
stack(1390, 1426, -40, 100, pots=2)
for ax in (1110, 1340):
    seg_window(ax, 290, 52, 130)
m, d = mask(); d.rectangle([X(1195), Y(150), X(1255), Y(300)], fill=255); paste(solid(WOOD), m)                  # 中轴卸货门
m, d = mask(); d.line([(X(1225), Y(150)), (X(1225), Y(300))], fill=255, width=2); d.line([(X(1195), Y(225)), (X(1255), Y(225))], fill=255, width=2); paste(solid((20, 16, 16)), m)
m, d = mask(); d.line([(X(1195), Y(286)), (X(1255), Y(286))], fill=255, width=3)
for bx in (1200, 1225, 1250):
    d.line([(X(bx), Y(270)), (X(bx), Y(300))], fill=255, width=2)
paste(solid(IRON), m)
m, d = mask()                                                             # 吊货梁 + 滑轮 + 绳
d.line([(X(1225), Y(130)), (X(1225), Y(100))], fill=255, width=5)
d.line([(X(1225), Y(104)), (X(1225), Y(104))], fill=255, width=1)
d.line([(X(1218), Y(110)), (X(1290), Y(110))], fill=255, width=6)
d.ellipse([X(1278), Y(114), X(1298), Y(134)], fill=255)
d.line([(X(1288), Y(134)), (X(1288), Y(330))], fill=255, width=2)
paste(solid(IRON), m, 0.4)
m, d = mask()                                                             # 1110：砖砌弧头车门
d.rectangle([X(1040), Y(400), X(1180), Y(FLOOR)], fill=255)
d.pieslice([X(1040), Y(372), X(1180), Y(428)], 180, 360, fill=255)
paste(solid((32, 27, 26)), m, 0.5)
m, d = mask()
for gx in range(1058, 1180, 20):
    d.line([(X(gx), Y(388)), (X(gx), Y(FLOOR))], fill=255, width=2)
d.arc([X(1032), Y(364), X(1188), Y(436)], 180, 360, fill=255, width=7)
paste(solid((20, 16, 16)), m, 0.3)
m, d = mask()                                                             # 1340：维多利亚店面
d.rectangle([X(1262), Y(372), X(1442), Y(FLOOR)], fill=255); paste(solid((26, 26, 30)), m)
m, d = mask(); d.rectangle([X(1270), Y(378), X(1434), Y(402)], fill=255); paste(solid((18, 18, 22)), m)
m, d = mask(); d.rectangle([X(1270), Y(378), X(1434), Y(402)], outline=255, width=2); paste(solid((92, 92, 98)), m, 0.3)
m, d = mask(); d.rectangle([X(1284), Y(420), X(1396), Y(556)], fill=255); paste(vgrad((110, 86, 56), (70, 54, 36), 420, 556), m, 0.5)
m, d = mask()
d.line([(X(1340), Y(420)), (X(1340), Y(556))], fill=255, width=3)
d.line([(X(1284), Y(458)), (X(1396), Y(458))], fill=255, width=2)
d.rectangle([X(1278), Y(414), X(1402), Y(562)], outline=255, width=5)
d.ellipse([X(1300), Y(500), X(1330), Y(530)], outline=255, width=4)       # 成卷缆绳
d.line([(X(1370), Y(464)), (X(1370), Y(478))], fill=255, width=2); d.rectangle([X(1362), Y(478), X(1378), Y(498)], outline=255, width=2)   # 马灯
paste(solid((30, 26, 26)), m, 0.4)
m, d = mask(); d.rectangle([X(1406), Y(424), X(1436), Y(FLOOR)], fill=255); paste(solid(WOOD), m)
m, d = mask()                                                             # 铁锚招牌
d.line([(X(1450), Y(330)), (X(1500), Y(330))], fill=255, width=4)
d.line([(X(1488), Y(330)), (X(1488), Y(410))], fill=255, width=4)
d.line([(X(1474), Y(348)), (X(1502), Y(348))], fill=255, width=3)
d.arc([X(1466), Y(380), X(1510), Y(420)], 0, 180, fill=255, width=4)
paste(solid(IRON), m, 0.3)

# ---- C 警署（1620–2000，最高最暗，轴线 1715 / 1905）：截顶石板陡坡（平顶 −570，铁花栏到 −615、带尖刺），两扇方头老虎窗；
#      两侧贯通的壁柱；意式圆头窗配石框（三层右窗暗暖光）；一层横缝粗石基座 + 铁栏方窗（暗暖值班室光）+ 圆拱双开门、粗石拱券；
#      门上铁臂挂一盏方玻璃蓝色警灯；护墙右角一只朝右的石像鬼
facade((1620, -255, 2000, FLOOR), -255, (48, 52, 64), (18, 20, 27))
roofp = [(1632, -255), (1660, -300), (1690, -570), (1930, -570), (1960, -300), (1988, -255)]
m, d = mask(); d.polygon(P(roofp), fill=255); paste(vgrad((40, 46, 60), (16, 18, 25), -570, -255), m)
m, d = mask(); d.line(P(roofp[3:]), fill=255, width=4); paste(solid((176, 188, 210)), m)
m, d = mask()                                                             # 平顶铁花栏 + 尖刺
d.line([(X(1690), Y(-600)), (X(1930), Y(-600))], fill=255, width=2)
for bx in range(1694, 1932, 14):
    d.line([(X(bx), Y(-615)), (X(bx), Y(-570))], fill=255, width=2)
paste(solid(IRON), m, 0.3)
for ax in (1715, 1905):                                                   # 两扇方头老虎窗
    m, d = mask(); d.rectangle([X(ax - 30), Y(-470), X(ax + 30), Y(-380)], fill=255); paste(solid((36, 40, 52)), m)
    m, d = mask(); d.rectangle([X(ax - 36), Y(-482), X(ax + 36), Y(-470)], fill=255); paste(solid((60, 66, 82)), m)
    square(ax, -392, 34, 70)
for px in (1620, 1970):                                                   # 贯通壁柱
    m, d = mask(); d.rectangle([X(px), Y(-255), X(px + 30), Y(470)], fill=255); paste(vgrad((60, 66, 80), (22, 24, 32), -255, 470), m, 0.5)
lit_edge(2000, -255, 300)
for ax, lit in ((1715, False), (1905, True)):
    round_window(ax, -30, 46, 190, glow=(176, 146, 100) if lit else None)  # 三层
    round_window(ax, 310, 50, 230)                                         # 二层
m, d = mask()                                                             # 一层：横缝粗石基座
d.rectangle([X(1620), Y(390), X(2000), Y(FLOOR)], fill=255); paste(solid((34, 37, 46)), m)
m, d = mask()
for yy in range(404, FLOOR, 26):
    d.line([(X(1620), Y(yy)), (X(2000), Y(yy))], fill=255, width=2)
paste(solid((18, 20, 26)), m, 0.3)
for ax in (1715, 1905):                                                   # 铁栏方窗（暗暖的值班室光）
    m, d = mask(); d.rectangle([X(ax - 34), Y(420), X(ax + 34), Y(540)], fill=255); paste(solid((70, 58, 42)), m, 0.5)
    m, d = mask()
    for bx in range(int(ax) - 26, int(ax) + 34, 13):
        d.line([(X(bx), Y(420)), (X(bx), Y(540))], fill=255, width=3)
    d.rectangle([X(ax - 42), Y(412), X(ax + 42), Y(548)], outline=255, width=6)
    paste(solid((58, 64, 80)), m, 0.4)
m, d = mask()                                                             # 圆拱双开门 + 粗石拱券
d.rectangle([X(1756), Y(440), X(1864), Y(FLOOR)], fill=255); d.pieslice([X(1756), Y(386), X(1864), Y(494)], 180, 360, fill=255)
paste(solid((22, 22, 28)), m, 0.5)
m, d = mask()
d.arc([X(1744), Y(374), X(1876), Y(506)], 180, 360, fill=255, width=12)
paste(solid((66, 72, 88)), m, 0.4)
m, d = mask(); d.line([(X(1810), Y(392)), (X(1810), Y(FLOOR))], fill=255, width=3); paste(solid((12, 12, 16)), m)
m, d = mask()                                                             # 方玻璃蓝色警灯（铁臂）
d.line([(X(1810), Y(330)), (X(1810), Y(346))], fill=255, width=3)
d.line([(X(1790), Y(330)), (X(1830), Y(330))], fill=255, width=3)
paste(solid(IRON), m)
m, d = mask(); d.rectangle([X(1796), Y(346), X(1824), Y(374)], fill=255); paste(solid((110, 150, 210)), m, 0.5)
m, d = mask(); d.rectangle([X(1796), Y(346), X(1824), Y(374)], outline=255, width=2); d.line([(X(1810), Y(346)), (X(1810), Y(374))], fill=255, width=1); paste(solid(IRON), m, 0.3)
gargoyle(1988, -290, 1)

# ---- D 折线屋顶住宅（2000–2400，轴线 2120 / 2290）：冷灰石墙；三层前方格铁栏屋檐阳台（80）+ 后面的折线屋顶（暗）和两扇山花老虎窗；
#      二层左：从一层升到二层的暗色凸窗（铅皮低坡顶）；二层右：落地窗 + 短铁阳台（300）；一层右：方门 + 扇形气窗（落在 2290 轴上）
facade((2000, 80, 2400, FLOOR), 80, (58, 62, 74), (14, 15, 20))
roofd = [(2005, 80), (2075, -150), (2325, -150), (2395, 80)]
m, d = mask(); d.polygon(P(roofd), fill=255); paste(solid((28, 32, 42)), m)
m, d = mask(); d.line(P(roofd[2:]), fill=255, width=3); paste(solid((176, 188, 210)), m)
stack(2060, 2100, -260, -140, pots=2); stack(2300, 2340, -250, -140, pots=2)
for ax in (2120, 2290):                                                   # 山花老虎窗
    m, d = mask(); d.rectangle([X(ax - 36), Y(-90), X(ax + 36), Y(70)], fill=255); paste(solid((48, 52, 64)), m)
    m, d = mask(); d.polygon(P([(ax - 44, -90), (ax, -130), (ax + 44, -90)]), fill=255); paste(solid((56, 62, 78)), m)
    square(ax, 60, 44, 120)
for px in (2000, 2386):
    pilaster(px, 80, 470, 14)
lit_edge(2400, 80, 300)
plinth(2000, 2400)
m, d = mask()                                                             # 凸窗（暗、铅皮低坡顶）
d.polygon(P([(2062, 180), (2178, 180), (2170, 520), (2070, 520)]), fill=255); paste(vgrad((46, 50, 62), (22, 24, 32), 180, 520), m)
m, d = mask(); d.polygon(P([(2054, 182), (2070, 166), (2170, 166), (2186, 182)]), fill=255); paste(solid((30, 34, 44)), m)
for yb in (300, 500):
    square(2120, yb, 76, 110)
square(2290, 300, 56, 200)                                                # 二层右：落地窗
m, d = mask(); d.rectangle([X(2262), Y(410), X(2318), Y(FLOOR)], fill=255); paste(solid(WOOD), m)               # 一层右：方门 + 扇形气窗
m, d = mask(); d.pieslice([X(2262), Y(376), X(2318), Y(432)], 180, 360, fill=255); paste(solid(GLASS), m, 0.4)
m, d = mask(); d.arc([X(2256), Y(370), X(2324), Y(438)], 180, 360, fill=255, width=5); d.line([(X(2258), Y(406)), (X(2322), Y(406))], fill=255, width=3); paste(solid(TRIM), m, 0.4)

# ---------------------------------------------------------------- 能站的面：每栋楼一种栏杆、一种托座
def style_of(x0, x1, y, kind):
    if kind == "ring":
        return "stone"
    if kind == "gallery":
        return "jib"
    if kind == "bridge":
        return "walk"
    if x0 < 1000:
        return "iron_pawn" if y > 150 else "ledge"
    if x0 < 1450:
        return "awning" if y > 200 else "roofwall"
    if x0 < 2000:
        return "heavy" if y > 150 else ("iron" if y > -100 else "parapet")
    return "iron_house" if y > 150 else "lattice"


for x0, x1, y, kind in SEC["platforms"]:
    if x1 < X0 or x0 > X1 or x1 <= ART_X:
        continue
    st_ = style_of(x0, x1, y, kind)
    a, b = sk(x0), x1
    if st_ == "jib":                                                       # 吊臂已经画了，只补能站的亮边
        r, rd = mask(); rd.line([(X(a), Y(y)), (X(b), Y(y))], fill=255, width=4); paste(solid((182, 192, 212)), r, 0.4)
        continue
    if st_ not in ("walk", "roofwall", "awning"):
        sh, sd = mask()
        sd.polygon(P([(a - 6, y + 16), (b + 6, y + 16), (b - 34, y + 90), (a - 46, y + 90)]), fill=110)
        paste(solid((8, 10, 16)), sh, 6)
    m, d = mask()
    r, rd = mask()
    if st_ in ("stone", "ledge", "heavy", "iron", "parapet", "lattice", "iron_pawn", "iron_house"):
        sl, sd2 = mask()
        thick = 14 if st_ == "ledge" else 22
        sd2.rectangle([X(a - 6), Y(y), X(b + 6), Y(y + thick)], fill=255)
        if st_ == "stone":                                                 # 钟楼环廊：接上左边的托石和稀疏石栏，x300 收口
            for bx in range(int(a) + 4, int(b) - 10, 90):
                sd2.polygon(P([(bx, y + 22), (bx + 28, y + 22), (bx + 22, y + 64), (bx + 6, y + 64)]), fill=255)
            sd2.rectangle([X(a), Y(y - 40), X(b), Y(y - 32)], fill=255)
            for bx in range(int(a) + 8, int(b) - 4, 38):
                sd2.rectangle([X(bx), Y(y - 32), X(bx + 9), Y(y)], fill=255)
            sd2.rectangle([X(b - 12), Y(y - 46), X(b + 4), Y(y)], fill=255)
            sd2.polygon(P([(b - 30, y + 22), (b + 6, y + 22), (b - 4, y + 70)]), fill=255)
        elif st_ in ("heavy", "parapet"):                                  # 警署：密排小托座
            for bx in range(int(a) + 8, int(b) - 8, 30):
                sd2.rectangle([X(bx), Y(y + 22), X(bx + 12), Y(y + 40)], fill=255)
            if st_ == "heavy":
                sd2.rectangle([X(a), Y(y - 46), X(b), Y(y - 34)], fill=255)
                for bx in range(int(a) + 10, int(b) - 10, 46):
                    sd2.rectangle([X(bx), Y(y - 34), X(bx + 16), Y(y)], fill=255)
            else:
                sd2.rectangle([X(a), Y(y - 40), X(b), Y(y)], fill=255)
        elif st_ == "lattice":                                             # 住宅檐口：一排小飞檐托
            for bx in range(int(a) + 6, int(b) - 6, 24):
                sd2.rectangle([X(bx), Y(y + 22), X(bx + 8), Y(y + 32)], fill=255)
        paste(vgrad((84, 90, 106), (42, 46, 58), y - 46, y + 64), sl, 0.4)
        if st_ == "parapet":
            hl, hd_ = mask()
            for bx in range(int(a) + 40, int(b) - 40, 90):
                hd_.rectangle([X(bx), Y(y - 30), X(bx + 26), Y(y - 10)], fill=255)
            paste(solid((22, 26, 34)), hl, 0.4)
        if st_ in ("iron", "lattice", "iron_pawn", "iron_house"):
            ir, idr = mask()
            idr.line([(X(a), Y(y - 38)), (X(b), Y(y - 38))], fill=255, width=2)
            step = 26 if st_ == "lattice" else 32
            for bx in range(int(a) + 6, int(b), step):
                idr.line([(X(bx), Y(y - 38)), (X(bx), Y(y))], fill=255, width=2)
            if st_ == "lattice":
                idr.line([(X(a), Y(y - 19)), (X(b), Y(y - 19))], fill=255, width=2)
            if st_ == "iron_pawn":                                         # 两端细涡卷铁托
                for ex, sg in ((a + 12, 1), (b - 12, -1)):
                    idr.line(P(bez((ex, y + 22), (ex, y + 70), (ex + sg * 40, y + 22))), fill=255, width=3)
            if st_ in ("iron_house", "iron"):                              # 两根细铁斜撑
                for ex, sg in ((a + 14, 1), (b - 14, -1)):
                    idr.line([(X(ex), Y(y + 70)), (X(ex + sg * 40), Y(y + 22))], fill=255, width=3)
                    idr.line([(X(ex), Y(y + 22)), (X(ex), Y(y + 70))], fill=255, width=3)
            paste(solid(IRON), ir, 0.3)
        rd.line([(X(a - 6), Y(y)), (X(b + 6), Y(y))], fill=255, width=4)
    elif st_ == "awning":                                                  # 木雨棚：微斜的板顶 + 铁托架
        d.polygon(P([(a - 10, y), (b + 10, y), (b + 10, y + 14), (a - 10, y + 22)]), fill=255)
        for ex in (a + 20, b - 20):
            d.line([(X(ex), Y(y + 20)), (X(ex), Y(y + 56))], fill=255, width=3)
            d.line([(X(ex), Y(y + 56)), (X(ex + (30 if ex < (a + b) / 2 else -30)), Y(y + 20))], fill=255, width=3)
        rd.line([(X(a - 10), Y(y)), (X(b + 10), Y(y))], fill=255, width=4)
    elif st_ == "roofwall":                                                # 平屋顶：矮砖护墙 + 石压顶
        sl, sd2 = mask(); sd2.rectangle([X(a), Y(y - 22), X(b), Y(y + 6)], fill=255); paste(solid((46, 42, 46)), sl, 0.4)
        sl, sd2 = mask(); sd2.rectangle([X(a - 4), Y(y - 26), X(b + 4), Y(y - 18)], fill=255); paste(solid((84, 88, 100)), sl, 0.4)
        rd.line([(X(a), Y(y)), (X(b), Y(y))], fill=255, width=3)
    else:                                                                  # 巷口铁天桥：桥面亮边 + 暗铁竖杆扶手 + 桥面下三角桁架
        d.rectangle([X(a), Y(y), X(b), Y(y + 14)], fill=255)
        d.line([(X(a), Y(y - 38)), (X(b), Y(y - 38))], fill=255, width=2)
        for bx in range(int(a), int(b) + 1, 18):
            d.line([(X(bx), Y(y - 38)), (X(bx), Y(y))], fill=255, width=2)
        d.line([(X(a), Y(y + 50)), (X(b), Y(y + 50))], fill=255, width=3)
        k = 0
        for bx in range(int(a), int(b), 42):
            d.line([(X(bx), Y(y + (14 if k % 2 == 0 else 50))), (X(bx + 42), Y(y + (50 if k % 2 == 0 else 14)))], fill=255, width=2)
            k += 1
        rd.line([(X(a), Y(y)), (X(b), Y(y))], fill=255, width=4)
    paste(solid((14, 17, 23)), m, 0.4)
    paste(solid((182, 192, 212)), r, 0.4)
for x0, x1, y, _ in SEC["blocks"]:
    if x0 < ART_X or x0 > X1:
        continue
    m, d = mask(); d.rectangle([X(x0), Y(y), X(x1), Y(FLOOR)], fill=255); paste(vgrad((70, 78, 94), (28, 32, 42), y, FLOOR), m, 0.4)
    m, d = mask()
    for yy in range(int(y) + 30, FLOOR, 30):
        d.line([(X(x0), Y(yy)), (X(x1), Y(yy))], fill=255, width=2)
    paste(solid((40, 46, 58)), m, 0.4)
    band(x0 - 6, x1 + 6, y, 12)

# 巷口一处杂物：麻袋 + 倒扣的木桶（右半边只这一处）
m, d = mask()
d.ellipse([X(1462), Y(548), X(1510), Y(582)], fill=255); d.ellipse([X(1490), Y(538), X(1534), Y(582)], fill=255)
d.rounded_rectangle([X(1576), Y(536), X(1606), Y(580)], 7, fill=255)
paste(solid((44, 40, 36)), m, 0.4)

# ---------------------------------------------------------------- 路灯 + 暖光 / 冷光
streets = [(x, y) for x, y, k, *_ in SEC["lamps"] if k == "street" and ART_X <= x <= X1]
m, d = mask()
for x, y in streets:
    d.rectangle([X(x - 6), Y(y - 300), X(x + 6), Y(y)], fill=255)
    d.rectangle([X(x - 14), Y(y - 40), X(x + 14), Y(y)], fill=255)
    d.line([(X(x - 22), Y(y - 290)), (X(x + 22), Y(y - 290))], fill=255, width=3)
    d.polygon(P([(x - 22, y - 342), (x + 22, y - 342), (x, y - 370)]), fill=255)
paste(solid((10, 11, 14)), m, 0.3)
m, d = mask()
for x, y in streets:
    d.polygon(P([(x - 18, y - 342), (x + 18, y - 342), (x + 12, y - 298), (x - 12, y - 298)]), fill=255)
paste(solid((248, 224, 168)), m, 0.5)
m, d = mask(); d.rectangle([X(1530), Y(-10), X(1550), Y(26)], fill=255); paste(solid((226, 200, 140)), m, 0.5)   # 巷口天桥边壁灯
halo = Image.new("RGB", (W, H)); hd = ImageDraw.Draw(halo)
for x, y in streets:
    hd.ellipse([X(x - 180), Y(y - 500), X(x + 180), Y(y - 140)], fill=(58, 50, 34))
    hd.ellipse([X(x - 160), Y(y - 8), X(x + 160), Y(y + 24)], fill=(76, 64, 42))
for cx, cy, s_ in ((805, 490, 1.0), (860, 180, 0.8), (1540, 10, 0.8), (1905, -120, 0.6), (1340, 490, 0.9)):
    hd.ellipse([X(cx - 100), Y(cy - 130), X(cx + 100), Y(cy + 130)], fill=tuple(int(v * s_) for v in (40, 32, 18)))
hd.ellipse([X(1770), Y(320), X(1850), Y(400)], fill=(12, 22, 42))                     # 警灯：冷蓝
img = np.clip(img + np.asarray(halo.filter(ImageFilter.GaussianBlur(36)), np.float32), 0, 255)
cool = Image.new("RGB", (W, H)); cd = ImageDraw.Draw(cool)
for i in range(6):
    cd.rectangle([X(ART_X), Y(530 + i * 8), W, Y(FLOOR)], fill=(4 + i * 2, 7 + i * 3, 11 + i * 4))
img = np.clip(img + np.asarray(cool.filter(ImageFilter.GaussianBlur(6)), np.float32), 0, 255)

# ---------------------------------------------------------------- 街面 / 河岸护墙 / 河（接缝右边）
c0 = int(X(ART_X))
img[int(Y(FLOOR)):int(Y(FLOOR + 26)), c0:] = (44, 49, 60)
img[int(Y(FLOOR)):int(Y(FLOOR)) + 2, c0:] = (110, 120, 140)
img[int(Y(FLOOR + 26)):int(Y(FLOOR + 96)), c0:] = (22, 25, 33)
img[int(Y(FLOOR + 96)):, :] = (12, 15, 21)
refl = Image.new("RGB", (W, H)); rfd = ImageDraw.Draw(refl)
for x, y in streets:
    rfd.rectangle([X(x - 14), Y(FLOOR + 2), X(x + 14), Y(FLOOR + 24)], fill=(120, 80, 36))
    rfd.rectangle([X(x - 12), Y(FLOOR + 100), X(x + 12), Y(FLOOR + 240)], fill=(90, 60, 28))
rfd.rectangle([X(-40), Y(FLOOR + 100), X(40), Y(FLOOR + 230)], fill=(124, 44, 20))      # 钟楼红窗的倒影
rfd.rectangle([X(785), Y(FLOOR + 100), X(825), Y(FLOOR + 200)], fill=(64, 46, 24))
rfd.rectangle([X(1320), Y(FLOOR + 100), X(1360), Y(FLOOR + 190)], fill=(58, 42, 22))
rfd.rectangle([X(1800), Y(FLOOR + 100), X(1820), Y(FLOOR + 190)], fill=(28, 42, 70))
img = np.clip(img + np.asarray(refl.filter(ImageFilter.GaussianBlur(5)), np.float32), 0, 255)
m, d = mask()                                                    # 护墙石缝
for yy in (FLOOR + 40, FLOOR + 62):
    d.line([(X(ART_X), Y(yy)), (X(X1), Y(yy))], fill=255, width=2)
for bx in range(ART_X + 40, X1, 120):
    d.line([(X(bx), Y(FLOOR + 32)), (X(bx), Y(FLOOR + 62))], fill=255, width=2)
    d.line([(X(bx + 60), Y(FLOOR + 62)), (X(bx + 60), Y(FLOOR + 96))], fill=255, width=2)
paste(solid((12, 14, 20)), m, 0.4)
m, d = mask(); d.rectangle([X(ART_X), Y(FLOOR + 26), X(X1), Y(FLOOR + 34)], fill=255); paste(solid((70, 76, 90)), m, 0.4)
m, d = mask()                                                    # 护墙上的铸铁系船桩 ×2 + 一个系船铁环
for bx in (900, 1900):
    d.rounded_rectangle([X(bx - 10), Y(FLOOR - 30), X(bx + 10), Y(FLOOR + 2)], 5, fill=255)
    d.ellipse([X(bx - 14), Y(FLOOR - 38), X(bx + 14), Y(FLOOR - 24)], fill=255)
paste(solid((26, 28, 34)), m, 0.3)
m, d = mask(); d.ellipse([X(1386), Y(FLOOR + 50), X(1414), Y(FLOOR + 80)], outline=255, width=3); paste(solid((40, 42, 50)), m, 0.4)
m, d = mask()                                                    # 封印外：一道开在护墙上的下河石阶（不比街面亮）
for i in range(5):
    d.rectangle([X(2440 + i * 18), Y(FLOOR + 30 + i * 14), X(2540), Y(FLOOR + 44 + i * 14)], fill=255)
paste(solid((34, 38, 48)), m, 0.4)
m, d = mask()
for i in range(5):
    d.line([(X(2440 + i * 18), Y(FLOOR + 30 + i * 14)), (X(2540), Y(FLOOR + 30 + i * 14))], fill=255, width=2)
paste(solid((80, 88, 104)), m, 0.4)
m, d = mask()                                                    # 街面水洼
for px, pw in ((520, 90), (1240, 110), (2150, 90)):
    d.ellipse([X(px - pw), Y(FLOOR + 6), X(px + pw), Y(FLOOR + 20)], fill=255)
paste(solid((96, 92, 92)), m, 3)

# 左边的成图段（钟楼右半）原样盖回去：GPT 照着这一段往右接
img_pil = Image.fromarray(img.astype(np.uint8)).convert("RGBA")
img_pil.alpha_composite(strip, (0, 1))
base = img_pil.convert("RGB").filter(ImageFilter.GaussianBlur(0.5))
base.save(OUT.replace(".png", "_无黄线.png"))

# ---------------------------------------------------------------- 能站的面：细黄线
out = base.copy()
od = ImageDraw.Draw(out)
for x0, x1, y, kind in SEC["platforms"]:
    if x1 < X0 or x0 > X1:
        continue
    od.line([(X(x0), Y(y)), (X(x1), Y(y))], fill=(255, 212, 0), width=4)
for x0, x1, y, _ in SEC["blocks"]:
    if x1 >= X0 and x0 <= X1:
        od.line([(X(x0 + (x1 - x0) * 0.24), Y(y)), (X(x1 - (x1 - x0) * 0.24), Y(y))], fill=(255, 212, 0), width=4)
out.save(OUT)
print("saved", out.size)
