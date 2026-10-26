"""第 2 处回潮区（C 渡槽来水）英雄画面的编辑画布 + 物件 ID 图。
画布 = 游戏一屏 × 1.30625（1672×941，和 GPT 出图尺寸一致）。
真像素：天空层（定调图巨环 + 天空 v2）、远山层、远处云海带、左边一截桥面（取自定调图）。
草图（带三档明暗、不画纹理）：断渡槽、细瀑、桥面延续、桥立面、两个平台、前景。"""
import math, random
from PIL import Image, ImageDraw, ImageEnhance, ImageChops, ImageFilter

SC = r"E:/00game/nightcrow-godot/docs/视觉设计/work/"
P = r"E:/00game/nightcrow-godot/"
L = P + "docs/视觉设计/layers/cloud_causeway/"
OUT = P + "docs/视觉设计/blockin/"
S = 1672 / 1280
W, H = 1672, 941
K2C = 0.88 * S                                   # 定调图像素 → 画布像素（约 1.149）


def c(v):                                        # 游戏屏幕坐标 → 画布坐标
    return v * S


def grade(im, sat=1.0, bright=1.0, tint=None, amt=0.0):
    a = im.split()[3]
    rgb = ImageEnhance.Color(im.convert("RGB")).enhance(sat)
    rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    if tint:
        rgb = Image.blend(rgb, Image.new("RGB", im.size, tint), amt)
    o = rgb.convert("RGBA")
    o.putalpha(a)
    return o


# ---------------- 真像素部分 ----------------
sky = Image.open(L + "01_sky_ring_from_keyart.png").convert("RGB")
sk = sky.resize((round(sky.size[0] * H / sky.size[1]), H), Image.LANCZOS)
canvas = sk.crop((sk.size[0] - W, 0, sk.size[0], H)).convert("RGBA")

mt = Image.open(SC + "keyed/11_mountains_v2.png").convert("RGBA").crop((0, 262, 1916, 779))
mt = grade(mt.resize((round(mt.size[0] * c(95) / mt.size[1]), round(c(95))), Image.LANCZOS),
           sat=0.5, bright=0.6, tint=(48, 62, 92), amt=0.7)
x = -int(c(150)) - int(c(180))                   # 远景比第 1 处多走 180 屏幕像素
while x < W:
    canvas.alpha_composite(mt, (x, int(c(455)) - mt.size[1]))
    x += mt.size[0] - 4

clouds = Image.open(SC + "keyed/02_clouds_v1.png").convert("RGBA").crop((0, 180, 1916, 590))
cm = grade(clouds.resize((round(c(1600)), round(c(1600) * clouds.size[1] / clouds.size[0])), Image.LANCZOS),
           bright=0.6, tint=(80, 130, 160), amt=0.2)
full = Image.new("RGB", (W, H))
full.paste(cm.convert("RGB"), (int(c(-160 - 180)), int(c(410))), cm)
canvas = ImageChops.screen(canvas.convert("RGB"), full).convert("RGBA")

key = Image.open(P + "docs/视觉设计/keyart/gameplay_frame_v2.webp").convert("RGB")
strip = key.crop((595, 555, 1027, 941))          # 定调图里干净的一段桥面（水洼、矮墙、拱）
strip = strip.resize((round(strip.size[0] * K2C), round(strip.size[1] * K2C)), Image.LANCZOS)
sm = Image.new("L", strip.size, 255)
ImageDraw.Draw(sm).rectangle([0, 0, strip.size[0], 10], fill=0)
sm = sm.filter(ImageFilter.GaussianBlur(5))
STRIP_W = strip.size[0]
canvas.paste(strip, (0, round(555 * K2C)), sm)

# ---------------- 草图部分（定调图吸的颜色，三档明暗，不画纹理） ----------------
d = ImageDraw.Draw(canvas)
ids = Image.new("RGB", (W, H), (0, 0, 0))        # 物件 ID 图：给拆层当蒙版，不给 GPT
di = ImageDraw.Draw(ids)
FAR = round(621 * K2C)                           # 桥面远边
NEAR = round(706 * K2C)                          # 桥面近边
PAR = round(570 * K2C)                           # 矮墙顶

# 0) 左边：渡槽的来处——一座暗色崖岩（中景，左上暗块），底部没入云海
cliff = [(0, c(140)), (c(60), c(110)), (c(130), c(150)), (c(200), c(140)), (c(260), c(175)), (c(330), c(170)),
         (c(400), c(195)), (c(410), c(240)), (c(330), c(270)), (c(280), c(330)), (c(250), c(400)), (c(220), c(420)), (0, c(420))]
d.polygon(cliff, fill=(30, 40, 58))
d.line(cliff[:7], fill=(56, 74, 98), width=4)                     # 顶沿受月光
di.polygon(cliff, fill=(255, 128, 0))
for yy in range(int(c(260)), int(c(430))):                         # 崖脚早早没入云雾，一层平台上的角色背后是亮雾
    k = (yy - c(260)) / c(170)
    d.line([(0, yy), (c(300) - k * c(80), yy)], fill=(int(30 + 70 * k), int(40 + 80 * k), int(58 + 92 * k)))

# 1) 断渡槽（中景，亮度 40～60，不描边；朝巨环的右上沿一道青边；越往右下越雾，沉进云海）
A0, A1 = (c(380), c(180)), (c(1050), c(470))
thick = c(46)
ang = math.atan2(A1[1] - A0[1], A1[0] - A0[0])
nx, ny = -math.sin(ang), math.cos(ang)
def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
segs = [(0.0, 0.38), (0.43, 0.80), (0.84, 1.0)]  # 断成三段
for t0, t1 in segs:
    p0, p1 = lerp(A0, A1, t0), lerp(A0, A1, t1)
    fog = (t0 + t1) / 2                          # 越往右下越雾
    body = tuple(int(v) for v in (40 + 22 * fog, 54 + 24 * fog, 74 + 28 * fog))
    top = tuple(int(v) for v in (70 + 18 * fog, 92 + 18 * fog, 112 + 18 * fog))
    poly = [p0, p1, (p1[0] + nx * thick, p1[1] + ny * thick), (p0[0] + nx * thick, p0[1] + ny * thick)]
    d.polygon(poly, fill=body)
    di.polygon(poly, fill=(255, 0, 0))
    d.line([p0, p1], fill=top, width=6)                               # 槽顶受光
    d.line([(p0[0] + 2, p0[1] - 4), (p1[0] + 2, p1[1] - 4)], fill=(70, 150, 150), width=3)  # 青色边
    # 槽下的拱和墩：墩往下没入云海（越往下越淡）
    n = max(1, int((t1 - t0) * 7))
    for i in range(n + 1):
        q = lerp(p0, p1, i / n)
        qx, qy = q[0] + nx * thick, q[1] + ny * thick
        bottom = min(c(500), qy + c(170))
        if bottom <= qy + 4:
            continue
        for yy in range(int(qy), int(bottom)):
            k = (yy - qy) / max(1, bottom - qy)
            col = tuple(int(body[j] * (1 - k) + (70, 92, 120)[j] * k) for j in range(3))
            d.line([(qx - c(9), yy), (qx + c(9), yy)], fill=col)
        di.rectangle([qx - c(9), qy, qx + c(9), bottom], fill=(255, 0, 0))
# 断口的碎块
for (bx, by, bs) in [(0.40, 0.30, 16), (0.82, 0.33, 12), (0.86, 0.36, 9)]:
    q = lerp(A0, A1, bx)
    d.rectangle([q[0] + c(6), q[1] + c(40) * by * 3, q[0] + c(6) + c(bs), q[1] + c(40) * by * 3 + c(bs * 0.8)],
                fill=(52, 66, 88))

# 2) 断口泻下的细瀑（被青光照亮，落进云海；下面桥面水洼里有它的倒影）
wx0, wy0 = A1[0] - c(4), A1[1] + c(26)
for yy in range(int(wy0), int(c(545))):
    k = (yy - wy0) / (c(545) - wy0)
    wobble = math.sin(yy * 0.05) * 2
    d.line([(wx0 + wobble - 3 - 4 * k, yy), (wx0 + wobble + 3 + 4 * k, yy)],
           fill=(int(150 + 40 * (1 - k)), int(210 + 20 * (1 - k)), 205))
    di.line([(wx0 - 6, yy), (wx0 + 6, yy)], fill=(0, 255, 255))
d.ellipse([wx0 - c(40), c(530), wx0 + c(40), c(552)], fill=(150, 200, 200))   # 落点溅起的雾

# 3) 桥面延续（右边）：矮墙成组、远边、顶面、水洼
random.seed(11)
x = STRIP_W
while x < W:
    for _ in range(random.randint(2, 3)):
        w_, h_ = random.randint(26, 52), random.randint(18, 52)
        d.rectangle([x, FAR - h_, x + w_, FAR], fill=(60, 72, 94))
        d.rectangle([x, FAR - h_, x + w_, FAR - h_ + 5], fill=(84, 98, 120))
        di.rectangle([x, FAR - h_, x + w_, FAR], fill=(0, 0, 255))
        x += w_ + random.randint(3, 10)
    x += random.randint(140, 300)
for y in range(FAR, NEAR):
    t = (y - FAR) / (NEAR - FAR)
    d.line([(STRIP_W, y), (W, y)], fill=(int(52 + 18 * t), int(62 + 18 * t), int(80 + 18 * t)))
di.rectangle([STRIP_W, FAR, W, NEAR], fill=(0, 0, 255))
for (px, pw, col) in [(wx0 - c(90), c(200), (110, 175, 175)), (c(760), c(120), (96, 140, 150)), (c(1180), c(70), (90, 120, 140))]:
    d.ellipse([px, FAR + c(10), px + pw, FAR + c(30)], fill=col)               # 不规则水洼（大的在瀑布下方）
    d.ellipse([px + pw * 0.2, FAR + c(6), px + pw * 0.6, FAR + c(18)], fill=col)
d.line([(STRIP_W, NEAR), (W, NEAR)], fill=(96, 110, 132), width=3)           # 桥面近边亮线
# 铺石分格线（只画结构，不画纹理）
for yy in (FAR + 22, FAR + 52, FAR + 88):
    d.line([(STRIP_W, yy), (W, yy)], fill=(44, 52, 68), width=1)

# 4) 桥立面 + 拱（接左边那一截的拱距）
d.rectangle([STRIP_W, NEAR, W, H], fill=(14, 18, 26))
d.rectangle([STRIP_W, NEAR, W, NEAR + c(40)], fill=(22, 28, 38))
period = 390 * K2C
first = (980 - 595) * K2C                         # 左边那一截里最后一个拱的中心
for i in range(1, 5):
    ax = first + i * period
    if ax - c(80) < STRIP_W - 40:
        continue
    top = round(760 * K2C)                        # 定调图里拱顶约在第 760 行
    r = 105 * K2C
    d.pieslice([ax - r, top, ax + r, top + 2 * r], 180, 360, fill=(26, 34, 46))
    if top + r < H:
        d.rectangle([ax - r, top + r, ax + r, H], fill=(26, 34, 46))
di.rectangle([STRIP_W, NEAR, W, H], fill=(0, 0, 160))

# 5) 平台：一层 = 掉到桥面上的一段槽（左），二层 = 槽墩顶（右）；亮度 20～40，带深色细描边，顶面亮边
def platform(x0, x1, top_y, body_bottom, top_col, body_col, ident):
    d.rectangle([x0, top_y + 6, x1, body_bottom], fill=body_col, outline=(10, 12, 18))
    d.rectangle([x0, top_y - 6, x1, top_y + 6], fill=top_col, outline=(10, 12, 18))
    di.rectangle([x0, top_y - 6, x1, body_bottom], fill=ident)

platform(c(120), c(370), c(470), FAR + 6, (88, 100, 118), (36, 44, 58), (0, 255, 0))
d.rectangle([c(170), c(470) - 3, c(320), c(470) + 2], fill=(120, 170, 175))      # 槽里的积水
platform(c(860), c(1020), c(360), c(400), (90, 100, 116), (38, 46, 60), (255, 255, 0))
d.rectangle([c(900), c(400), c(980), FAR], fill=(34, 42, 56), outline=(10, 12, 18))  # 槽墩
di.rectangle([c(900), c(400), c(980), FAR], fill=(255, 255, 0))

# 6) 几只鸦（沿渡槽飞）
for (bx, by) in [(c(560), c(150)), (c(610), c(170)), (c(680), c(158))]:
    d.polygon([(bx, by), (bx + 12, by - 5), (bx + 5, by + 4), (bx - 6, by - 4)], fill=(10, 12, 18))

# 7) 前景：右下断柱 + 蕨叶（有机剪影）、左上几根垂藤
d.polygon([(W, H), (W, c(560)), (c(1250), c(575)), (c(1235), c(640)), (c(1200), c(660)), (c(1185), H)], fill=(6, 7, 11))
for i in range(6):
    ang2 = math.radians(200 + i * 14)
    d.line([(c(1205), c(700)), (c(1205) + math.cos(ang2) * c(70), c(700) + math.sin(ang2) * c(70))], fill=(6, 7, 11), width=8)
di.polygon([(W, H), (W, c(560)), (c(1150), c(600)), (c(1140), H)], fill=(255, 0, 255))
for x0 in (c(20), c(48), c(78)):
    d.line([(x0, 0), (x0 + 6, c(120))], fill=(6, 7, 11), width=7)
    di.line([(x0, 0), (x0 + 6, c(120))], fill=(255, 0, 255), width=9)

canvas.convert("RGB").save(OUT + "arena2_C_canvas.png")
ids.save(OUT + "arena2_C_ids.png")
print("strip width", STRIP_W, "FAR", FAR, "NEAR", NEAR)
