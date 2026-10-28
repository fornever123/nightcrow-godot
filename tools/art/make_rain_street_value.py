"""雨夜河岸街：明暗草图（结构参考图 v2）。

和 make_rain_street_ref.py 同一套楼的位置和能站的面，但把光影规划直接画进去，
让 GPT 照着画的时候明暗主次一开始就是对的：
  - 天空最上面最暗，往下渐亮；远景城市在雾里，很淡、低对比
  - 楼：上部被右上方的月光照亮，越往下越暗；街面一层最暗、最平
  - 屋顶右坡、楼的右边缘、檐口和栏杆上沿是银白轮廓光
  - 全图只有 5 扇暖光窗 + 3 盏路灯；钟楼的朱红钟面和彩窗是唯一焦点
  - 楼前没有栅栏；能站的面仍是细黄线
用法：python make_rain_street_value.py <layout.json> <输出.png>
"""
import sys, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops

LAYOUT, OUT = sys.argv[1], sys.argv[2]
L = json.load(open(LAYOUT, encoding="utf-8"))
SEC = L["sections"][0]
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
    """整张图大小的竖直渐变（世界 y_top → y_bot）"""
    t = np.clip((np.arange(H)[:, None] - Y(y_top)) / max(Y(y_bot) - Y(y_top), 1), 0, 1)[..., None]
    a, b = np.array(top_col, np.float32), np.array(bot_col, np.float32)
    return np.broadcast_to(a * (1 - t) + b * t, (H, W, 3)).copy()


def paste(base, color_arr, m, blur=0.0):
    mm = m.filter(ImageFilter.GaussianBlur(blur)) if blur else m
    a = np.asarray(mm, np.float32)[..., None] / 255.0
    base[:] = base * (1 - a) + color_arr * a


# ---------------------------------------------------------------- 天空 + 远景雾
img = vgrad((20, 25, 36), (64, 74, 94), -700, 560)
m, d = mask()
d.ellipse([X(-560), Y(-640), X(-440), Y(-520)], fill=255)
paste(img, np.full((H, W, 3), (222, 226, 232), np.float32), m, 1.0)
glow, gd = mask()
gd.ellipse([X(-700), Y(-780), X(-300), Y(-380)], fill=110)
paste(img, np.full((H, W, 3), (150, 162, 186), np.float32), glow, 60)
m, d = mask()
far = [(-2450, 330), (-2200, 310), (-2180, 230), (-2140, 230), (-2120, 310), (-1500, 300), (-1480, 190), (-1440, 190),
       (-1420, 300), (-760, 270), (-700, 150), (-660, 100), (-620, 150), (-560, 270), (260, 300), (260, 700), (-2450, 700)]
d.polygon(P(far), fill=255)
d.ellipse([X(-860), Y(-20), X(-500), Y(320)], fill=255)          # 远处穹顶，很淡
paste(img, vgrad((78, 88, 108), (90, 100, 120), 100, 600), m, 1.5)
fog, fd = mask()
fd.rectangle([0, Y(200), W, Y(600)], fill=150)
paste(img, np.full((H, W, 3), (96, 108, 130), np.float32), fog, 40)

# ---------------------------------------------------------------- 近景楼体：上亮下暗
near, nd = mask()
roof, rd = mask()
# B1 窄高联排（阶梯山墙）
nd.rectangle([X(-2400), Y(-330), X(-1980), Y(FLOOR)], fill=255)
steps = [(-2400, -330), (-2400, -380), (-2350, -380), (-2350, -430), (-2290, -430), (-2290, -480), (-2240, -480), (-2240, -520),
         (-2140, -520), (-2140, -480), (-2090, -480), (-2090, -430), (-2030, -430), (-2030, -380), (-1980, -380), (-1980, -330)]
nd.polygon(P(steps), fill=255)
rd.rectangle([X(-2060), Y(-560), X(-2010), Y(-380)], fill=255)
# B2 角楼 + 圆锥塔帽
nd.rectangle([X(-1980), Y(-300), X(-1560), Y(FLOOR)], fill=255)
rd.polygon(P([(-1920, -300), (-1770, -680), (-1620, -300)]), fill=255)
# B3 宽联排 + 陡屋顶
nd.rectangle([X(-1440), Y(10), X(-900), Y(FLOOR)], fill=255)
rd.polygon(P([(-1460, 10), (-1300, -300), (-1040, -300), (-880, 10)]), fill=255)
rd.rectangle([X(-1380), Y(-360), X(-1340), Y(-220)], fill=255)
# B4 窄店面楼
nd.rectangle([X(-900), Y(-200), X(-620), Y(FLOOR)], fill=255)
nd.polygon(P([(-900, -200), (-900, -250), (-850, -250), (-850, -300), (-670, -300), (-670, -250), (-620, -250), (-620, -200)]), fill=255)
# 广场边的石拱廊桥（桥下透出远景）
nd.rectangle([X(-640), Y(30), X(-300), Y(90)], fill=255)
paste(img, vgrad((70, 78, 94), (16, 18, 24), -500, 560), near, 0.8)      # 月光照着上部，往下沉进暗部
paste(img, np.full((H, W, 3), (24, 27, 36), np.float32), roof, 0.8)
arch, ad = mask()
ad.pieslice([X(-610), Y(60), X(-330), Y(300)], 180, 360, fill=255)
paste(img, vgrad((78, 88, 108), (90, 100, 120), 100, 600), arch, 0.8)
# 巷子深处的后排楼：雾里，中间调
back, bd = mask()
bd.rectangle([X(-1560), Y(-180), X(-1440), Y(FLOOR)], fill=255)
bd.polygon(P([(-1560, -180), (-1500, -300), (-1440, -180)]), fill=255)
paste(img, vgrad((86, 96, 116), (52, 58, 72), -300, 560), back, 1.0)

# 钟楼：比两边亮一档，是焦点
tower, td = mask()
td.rectangle([X(-260), Y(-720), X(260), Y(FLOOR)], fill=255)
paste(img, vgrad((92, 100, 118), (22, 24, 32), -700, 560), tower, 0.8)

# 窗：只交代楼层节奏，比墙暗一点点（低对比）
win, wd = mask()
def windows(x0, x1, ys, n, w=46, h=150):
    for k in range(n):
        cx = x0 + (k + 0.5) * (x1 - x0) / n
        for y in ys:
            wd.rectangle([X(cx - w / 2), Y(y - h + w / 2), X(cx + w / 2), Y(y)], fill=255)
            wd.pieslice([X(cx - w / 2), Y(y - h), X(cx + w / 2), Y(y - h + w)], 180, 360, fill=255)
windows(-2380, -2000, [250, -20], 2, 54, 190)
windows(-1960, -1580, [240, -60], 3, 40, 160)
windows(-1430, -1210, [250], 2, 44, 150)
windows(-1070, -910, [250], 1, 44, 150)
windows(-1430, -910, [-40], 4, 40, 150)
windows(-890, -630, [250, -30], 2, 44, 150)
for cx, w, h in [(-2190, 110, 240), (-1770, 100, 230), (-1320, 110, 240), (-1000, 100, 220), (0, 150, 300)]:   # 门
    wd.rectangle([X(cx - w / 2), Y(FLOOR - h + w / 2), X(cx + w / 2), Y(FLOOR)], fill=255)
    wd.pieslice([X(cx - w / 2), Y(FLOOR - h), X(cx + w / 2), Y(FLOOR - h + w)], 180, 360, fill=255)
paste(img, img * 0.62, win, 0.6)
bay, byd = mask()
byd.polygon(P([(-1205, 250), (-1075, 250), (-1085, 520), (-1195, 520)]), fill=255)      # 凸窗体块
paste(img, img * 1.15, bay, 0.6)

# ---------------------------------------------------------------- 月光轮廓光（右坡、右边缘、塔帽）
rim, rmd = mask()
def rim_line(pts, w=4):
    rmd.line(P(pts), fill=255, width=w)
rim_line([(-2140, -520), (-2140, -480), (-2090, -480), (-2090, -430), (-2030, -430), (-2030, -380), (-1980, -380)])
rim_line([(-1770, -680), (-1620, -300)], 5)
rim_line([(-1040, -300), (-880, 10)], 5)
rim_line([(-670, -300), (-670, -250), (-620, -250), (-620, -200)])
rim_line([(-1980, -330), (-1980, 200)], 3)
rim_line([(-900, 10), (-900, 200)], 3)
rim_line([(260, -720), (260, 300)], 4)
rim_line([(-2010, -560), (-2010, -380)], 3)
paste(img, np.full((H, W, 3), (190, 200, 218), np.float32), rim, 0.7)

# ---------------------------------------------------------------- 能站的面（阳台 / 桥 / 檐）：暗色剪影 + 上沿亮线
plat, pd = mask()
rail, rld = mask()
for x0, x1, y, kind in SEC["platforms"]:
    if x1 < X0 or x0 > X1:
        continue
    if kind in ("balcony", "ring"):
        pd.rectangle([X(x0), Y(y), X(x1), Y(y + 16)], fill=255)
        rld.line([(X(x0), Y(y - 50)), (X(x1), Y(y - 50))], fill=255, width=2)
        for bx in range(int(x0), int(x1), 26 if kind == "balcony" else 44):
            pd.line([(X(bx), Y(y - 50)), (X(bx), Y(y))], fill=255, width=2)
    elif kind == "bridge":
        pd.rectangle([X(x0), Y(y), X(x1), Y(y + 26)], fill=255)
        rld.line([(X(x0), Y(y - 40)), (X(x1), Y(y - 40))], fill=255, width=2)
    else:
        pd.polygon(P([(x0 - 20, y + 36), (x0, y), (x1, y), (x1 + 20, y + 36)]), fill=255)
for x0, x1, y, _ in SEC["blocks"]:
    for i in range(3):
        sy = y + (FLOOR - y) * i / 3
        inset = (x1 - x0) * 0.12 * (2 - i)
        pd.rectangle([X(x0 + inset), Y(sy), X(x1 - inset), Y(FLOOR)], fill=255)
paste(img, np.full((H, W, 3), (14, 16, 21), np.float32), plat, 0.5)
paste(img, np.full((H, W, 3), (150, 160, 180), np.float32), rail, 0.5)

# ---------------------------------------------------------------- 焦点和暖光
red, red_d = mask()
red_d.ellipse([X(-110), Y(-560), X(110), Y(-340)], fill=255)
red_d.rectangle([X(-50), Y(-40), X(50), Y(200)], fill=255)
paste(img, np.full((H, W, 3), (176, 52, 40), np.float32), red, 0.8)
warm, wmd = mask()
lit = [(-2190, -40, 54, 190), (-1770, 240, 40, 160), (-1140, 380, 60, 110), (-760, -30, 44, 150)]
for cx, by, w, h in lit:
    wmd.rectangle([X(cx - w / 2), Y(by - h), X(cx + w / 2), Y(by)], fill=255)
paste(img, np.full((H, W, 3), (236, 168, 84), np.float32), warm, 0.6)
shop, sd_ = mask()
sd_.rectangle([X(-850), Y(450), X(-690), Y(560)], fill=255)          # 店面橱窗：很暗的暖光（角色身后要安静）
paste(img, np.full((H, W, 3), (120, 84, 46), np.float32), shop, 0.6)
lamp, lmd = mask()
streets = [(x, y) for x, y, k in SEC["lamps"] if k == "street" and X0 <= x <= X1] + [(-500, 580)]
for x, y in streets:
    lmd.ellipse([X(x - 20), Y(y - 166), X(x + 20), Y(y - 126)], fill=255)
paste(img, np.full((H, W, 3), (255, 200, 120), np.float32), lamp, 0.5)
post, ptd = mask()
for x, y in streets:
    ptd.rectangle([X(x - 5), Y(y - 130), X(x + 5), Y(y)], fill=255)
paste(img, np.full((H, W, 3), (10, 10, 13), np.float32), post, 0.3)
halo = Image.new("RGB", (W, H))
hd = ImageDraw.Draw(halo)
for x, y in streets:
    hd.ellipse([X(x - 150), Y(y - 300), X(x + 150), Y(y)], fill=(90, 56, 24))
    hd.ellipse([X(x - 160), Y(y - 10), X(x + 160), Y(y + 26)], fill=(110, 70, 30))
for cx, by, w, h in lit:
    hd.ellipse([X(cx - 120), Y(by - h - 60), X(cx + 120), Y(by + 60)], fill=(60, 36, 14))
hd.ellipse([X(-200), Y(-640), X(200), Y(-260)], fill=(34, 8, 6))
halo = halo.filter(ImageFilter.GaussianBlur(40))
img = np.clip(img + np.asarray(halo, np.float32), 0, 255)

# ---------------------------------------------------------------- 街面 / 河岸挡墙 / 河（灯的竖直倒影）
g = np.zeros((H, W, 3), np.float32)
img[int(Y(FLOOR)):int(Y(FLOOR + 26))] = (40, 44, 54)
img[int(Y(FLOOR + 26)):int(Y(FLOOR + 96))] = (22, 24, 31)
img[int(Y(FLOOR + 96)):] = (13, 15, 21)
refl = Image.new("RGB", (W, H))
rfd = ImageDraw.Draw(refl)
for x, y in streets:
    rfd.rectangle([X(x - 14), Y(FLOOR + 2), X(x + 14), Y(FLOOR + 24)], fill=(120, 80, 36))
    rfd.rectangle([X(x - 12), Y(FLOOR + 100), X(x + 12), Y(FLOOR + 240)], fill=(90, 60, 28))
rfd.rectangle([X(-40), Y(FLOOR + 100), X(40), Y(FLOOR + 230)], fill=(110, 30, 22))
img = np.clip(img + np.asarray(refl.filter(ImageFilter.GaussianBlur(5)), np.float32), 0, 255)

# ---------------------------------------------------------------- 能站的面：细黄线（GPT 要把它画成对应的顶面）
out = Image.fromarray(img.astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))
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
