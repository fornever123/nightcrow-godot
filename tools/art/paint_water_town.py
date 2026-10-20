#!/usr/bin/env python3
"""纯代码绘制「月下水乡」分层背景（实验）。输出 layers/*.png（直通透明）+ comp.png。"""
import numpy as np, cairo, cv2, math, os, json, sys
OUT = sys.argv[1] if len(sys.argv) > 1 else '/data/bgtest'
os.makedirs(OUT + '/layers', exist_ok=True)
W, H = 2560, 1080
VIEW = 1920
YH, YB, YW, YWALL, YWB = 600, 668, 862, 880, 975   # 远岸水线 / 桥水线 / 步道顶 / 墙顶 / 墙底
MOON = (1500.0, 226.0, 56.0)
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)


def C(h):
    h = h.lstrip('#'); return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)], np.float32)
def mix(a, b, t): return a + (b - a) * t
def sstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)
def gauss(x): return np.exp(-0.5 * x * x)


def surf():
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, W, H); c = cairo.Context(s)
    c.set_source_rgba(1, 1, 1, 1); c.set_line_cap(cairo.LINE_CAP_ROUND); c.set_line_join(cairo.LINE_JOIN_ROUND)
    return s, c
def amask(s):
    s.flush(); d = np.ndarray((H, s.get_stride() // 4, 4), np.uint8, s.get_data())
    return d[:, :W, 3].astype(np.float32) / 255
def shape(fn):
    s, c = surf(); fn(c); return amask(s)


def noise(sx, sy, octv=5, seed=0, pers=0.5):
    r = np.random.default_rng(seed); o = np.zeros((H, W), np.float32); a = 1; t = 0
    for i in range(octv):
        f = 2 ** i; gw = max(4, int(W / sx * f) + 4); gh = max(4, int(H / sy * f) + 4)
        o += a * cv2.resize(r.random((gh, gw)).astype(np.float32), (W, H), interpolation=cv2.INTER_CUBIC)
        t += a; a *= pers
    o /= t; return (o - o.min()) / (o.max() - o.min() + 1e-6)
def n1(scale, octv=5, seed=0, pers=0.5):
    r = np.random.default_rng(seed); o = np.zeros(W, np.float32); a = 1; t = 0
    for i in range(octv):
        k = max(4, int(W / scale * 2 ** i) + 4)
        o += a * cv2.resize(r.random((1, k)).astype(np.float32), (W, 1), interpolation=cv2.INTER_CUBIC)[0]
        t += a; a *= pers
    o /= t; return (o - o.min()) / (o.max() - o.min() + 1e-6)


class Layer:
    def __init__(s, name, par, add=False):
        s.name, s.par, s.add = name, par, add; s.a = np.zeros((H, W, 4), np.float32)
    def put(s, mask, rgb, alpha=1.0):
        m = np.clip(mask * alpha, 0, 1)[..., None]
        rgb = rgb if np.ndim(rgb) == 3 else np.asarray(rgb)[None, None, :]
        s.a[..., :3] = rgb * m + s.a[..., :3] * (1 - m); s.a[..., 3:] = m + s.a[..., 3:] * (1 - m)
    def glow(s, x, y, rad, rgb, amt, sy=None):
        sy = sy or rad; g = np.exp(-(((xx - x) / rad) ** 2 + ((yy - y) / sy) ** 2)) * amt
        s.a[..., :3] += g[..., None] * np.asarray(rgb)[None, None, :]


def reflect(layer, y0, depth, darken=0.5, alpha=0.75, wob=4.0, seed=1, blur=1.5):
    """把 layer 在 y0 以上 depth 行翻到 y0 以下，按行加横向抖动，越远越淡。"""
    src = layer.a[max(0, y0 - depth):y0][::-1].copy(); d = src.shape[0]
    rows = np.arange(d, dtype=np.float32)
    r = np.random.default_rng(seed)
    ph = r.random(4) * 6.28
    sh = np.zeros((d, W), np.float32)
    for k, f in enumerate((0.21, 0.37, 0.09, 0.6)):
        sh += np.sin(rows[:, None] * f + ph[k] + xx[0][None, :] * 0.004 * (k + 1)) * (wob / (k + 1.5))
    sh *= (0.35 + rows[:, None] / max(d, 1))
    mapx = (xx[:d] + sh).astype(np.float32); mapy = yy[:d].astype(np.float32)
    out = cv2.remap(src, mapx, mapy, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    if blur: out = cv2.GaussianBlur(out, (0, 0), sigmaX=0.6, sigmaY=blur)
    fade = (1 - rows / d) ** 1.2 * alpha
    out[..., :3] *= darken
    out *= fade[:, None, None]
    tgt = layer.a[y0:y0 + d]
    tgt[...] = out[:tgt.shape[0]] + tgt * (1 - out[:tgt.shape[0], :, 3:])


def bez(p, t):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = p; u = 1 - t
    return (u**3*x0 + 3*u*u*t*x1 + 3*u*t*t*x2 + t**3*x3, u**3*y0 + 3*u*u*t*y1 + 3*u*t*t*y2 + t**3*y3)
def bezd(p, t):
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = p; u = 1 - t
    return (3*u*u*(x1-x0) + 6*u*t*(x2-x1) + 3*t*t*(x3-x2), 3*u*u*(y1-y0) + 6*u*t*(y2-y1) + 3*t*t*(y3-y2))


def strand(c, r, x0, y0, L, dx, lw=1.2, leaf=7.0, spacing=4.2):
    p = ((x0, y0), (x0 + dx * 0.15, y0 + L * 0.35), (x0 + dx * 0.7, y0 + L * 0.72), (x0 + dx, y0 + L))
    c.set_line_width(lw); c.move_to(*p[0]); c.curve_to(*p[1], *p[2], *p[3]); c.stroke()
    n = int(L / spacing)
    c.set_line_width(lw * 1.35)
    for i in range(n):
        t = (i + r.random() * 0.6) / n
        x, y = bez(p, t); tx, ty = bezd(p, t); a = math.atan2(ty, tx)
        side = 1 if i % 2 else -1
        la = leaf * (0.55 + 0.6 * t) * (0.7 + 0.5 * r.random())
        aa = a + side * (0.35 + 0.25 * r.random())
        c.move_to(x, y); c.line_to(x + la * math.cos(aa), y + la * math.sin(aa)); c.stroke()


def lit_edge(m, dx=2, dy=2):
    sh = np.roll(np.roll(m, dy, axis=0), -dx, axis=1)
    return np.clip(m - sh, 0, 1)


# ============================================================ 调色板
SKY_T, SKY_M, HOR = C('#0A141B'), C('#122330'), C('#2C4550')
WARM, WARM_CORE, LANT_RED = C('#F0A04B'), C('#FFC27A'), C('#D8643A')
SIL = C('#060A0D')
layers = []

# ============================================================ 0 天空（固定）
sky = Layer('sky', 0.0)
t = np.clip(yy / YH, 0, 1.2)
col = np.where((t < 0.55)[..., None], mix(SKY_T, SKY_M, (t / 0.55)[..., None]),
               mix(SKY_M, HOR, np.clip((t - 0.55) / 0.45, 0, 1)[..., None] ** 1.6))
dm = np.hypot(xx - MOON[0], yy - MOON[1])
col = col + C('#5E7A7C')[None, None] * (0.16 * np.exp(-dm / 300) + 0.10 * np.exp(-dm / 110))[..., None]
sky.put(np.ones((H, W), np.float32), col)
# 星星
s, c = surf(); r = np.random.default_rng(5)
for i in range(520):
    x, y = r.random() * VIEW, r.random() ** 1.5 * 520
    d = math.hypot(x - MOON[0], y - MOON[1])
    if d < 180 or r.random() < y / 650: continue
    b = r.random() ** 3.2; rad = 0.55 + 1.1 * b
    c.set_source_rgba(1, 1, 1, min(1, 0.25 + 0.85 * b) * min(1, (d - 180) / 200)); c.arc(x, y, rad, 0, 6.283); c.fill()
star = amask(s)
starcol = np.stack([np.full((H, W), 0.86), np.full((H, W), 0.9), np.full((H, W), 0.86)], -1).astype(np.float32)
sky.put(star, starcol, 0.9)
sglow = cv2.GaussianBlur(star, (0, 0), 3.0)
sky.a[..., :3] += sglow[..., None] * C('#9FB4B0')[None, None] * 0.5
# 月亮
mx, my, mr = MOON
d = np.hypot(xx - mx, yy - my); disk = np.clip(mr - d + 0.5, 0, 1)
crat = noise(70, 70, 5, 21)
mc = mix(C('#E8ECE1')[None, None], C('#AEB9B2')[None, None], (sstep(0.5, 0.8, crat) * 0.55)[..., None])
mc = mc * (1 - 0.2 * np.clip(d / mr, 0, 1) ** 2)[..., None]
sky.put(disk, mc)
sky.a[..., :3] += C('#8FA6A2')[None, None] * (0.22 * np.exp(-np.maximum(d - mr, 0) / 26))[..., None]
# 云：横向细长的层云，靠近月亮被照亮
cn = noise(700, 70, 6, 31); cn2 = noise(300, 40, 5, 32); wv = (noise(500, 200, 3, 33) - 0.5) * 70
band = gauss((yy + wv - 312) / 34) + 0.75 * gauss((yy + wv - 430) / 30) + 0.5 * gauss((yy + wv - 128) / 24)
cm = sstep(0.42, 0.72, cn * 0.7 + cn2 * 0.3) * np.clip(band, 0, 1)
litc = np.exp(-dm / 330)
ccol = mix(C('#18272F')[None, None], C('#6F8587')[None, None], (np.clip(litc * (0.35 + 0.9 * cn2), 0, 1))[..., None])
sky.put(cm, ccol, 0.78)
layers.append(sky)

# ============================================================ 1 远山 + 宝塔
far1 = Layer('far_mountains', 0.05)
ry = 515 - 150 * n1(900, 6, 41) ** 1.6
m = np.clip(yy - ry[None, :], 0, 1) * (yy < YH + 4)
c1 = mix(mix(C('#2A424D'), HOR, 0.45)[None, None], HOR[None, None], (sstep(ry[None, :], YH, yy) * 0.8)[..., None])
far1.put(m, c1)
layers.append(far1)

far2 = Layer('hills_pagoda', 0.1)
PX = 640.0
ry2 = 560 - 85 * n1(520, 5, 43) ** 1.3 - 70 * np.exp(-((xx[0] - PX) / 150) ** 2)
m = np.clip(yy - ry2[None, :], 0, 1) * (yy < YH + 4)
c2 = mix(C('#1B2E37')[None, None], mix(C('#1B2E37'), HOR, 0.7)[None, None], (sstep(ry2[None, :], YH, yy))[..., None])
far2.put(m, c2)
base_y = float(ry2[int(PX)]) + 3
def pagoda(c):
    y = base_y; w = 44.0; hgt = 19.0
    c.rectangle(PX - w / 2 - 6, y - 6, w + 12, 6); c.fill(); y -= 6
    for i in range(7):
        bw = w * (1 - i * 0.08); th = hgt * (1 - i * 0.05)
        c.rectangle(PX - bw / 2, y - th, bw, th); c.fill()
        ex = bw / 2 + 9; ey = y - th
        c.move_to(PX - ex - 4, ey - 5); c.curve_to(PX - ex + 6, ey + 1, PX - bw / 4, ey - 3, PX, ey - 7)
        c.curve_to(PX + bw / 4, ey - 3, PX + ex - 6, ey + 1, PX + ex + 4, ey - 5)
        c.line_to(PX + ex - 2, ey + 2); c.line_to(PX - ex + 2, ey + 2); c.close_path(); c.fill()
        y = ey - 1
    c.rectangle(PX - 1.5, y - 26, 3, 26); c.fill()
    for k in range(4): c.arc(PX, y - 6 - k * 5, 3.2 - k * 0.5, 0, 6.283); c.fill()
pm = shape(pagoda)
far2.put(pm, C('#16262E'))
for wy in (base_y - 40, base_y - 78):
    far2.glow(PX, wy, 2.2, WARM, 0.9); far2.glow(PX, wy, 9, WARM, 0.12)
layers.append(far2)

# ============================================================ 2 孔明灯
skyl = Layer('sky_lanterns', 0.08, add=True)
for (x, y, sz) in [(300, 205, 7), (395, 262, 5.5), (930, 150, 4.5), (1120, 318, 6), (1830, 120, 4), (220, 330, 4)]:
    skyl.glow(x, y, sz * 0.55, WARM_CORE, 1.4, sy=sz * 0.75)
    skyl.glow(x, y + sz * 0.3, sz * 0.9, WARM, 0.55)
    skyl.glow(x, y, sz * 5, WARM, 0.07)
layers.append(skyl)

# ============================================================ 3 低空雾带
mist = Layer('horizon_mist', 0.15)
mn = noise(480, 36, 5, 51)
mist.put(np.ones((H, W), np.float32), C('#3A5560'), 1.0)
mist.a *= (0.62 * gauss((yy - 590) / 38) * (0.55 + 0.45 * mn))[..., None]
layers.append(mist)

# ============================================================ 4 远岸民居（白墙黑瓦马头墙）+ 水面底色 + 倒影
town = Layer('town', 0.25)
# 水面底色
wt = np.clip((yy - YH) / (YW - YH), 0, 1)
wcol = mix(mix(HOR, C('#000000'), 0.18)[None, None], C('#0A151B')[None, None], (wt ** 0.7)[..., None])
rip = noise(1400, 7, 4, 61)
wcol = wcol + (sstep(0.62, 0.82, rip) * 0.05 * (0.3 + wt))[..., None] * C('#9FB6B4')[None, None]
town.put((yy >= YH).astype(np.float32), wcol)
r = np.random.default_rng(71)
walls, roofs, wins = surf(), surf(), []
trees = surf()
far_row = surf()
x = -60.0
houses = []
while x < W + 60:
    if r.random() < 0.22:
        # 树丛
        tw = 60 + r.random() * 90
        for k in range(9):
            cx = x + r.random() * tw; cr = 16 + r.random() * 22
            trees[1].arc(cx, YH - 30 - r.random() * 40, cr, 0, 6.283); trees[1].fill()
        trees[1].rectangle(x, YH - 50, tw, 50); trees[1].fill()
        x += tw * 0.8; continue
    w = 90 + r.random() * 150; h = 46 + r.random() * 70
    if r.random() < 0.35: h += 30
    houses.append((x, w, h)); x += w - 4 + r.random() * 6
# 后排更远的屋顶（更淡）
rr = np.random.default_rng(72); x = -40
while x < W:
    w = 70 + rr.random() * 120; h = 70 + rr.random() * 60
    c = far_row[1]; c.rectangle(x, YH - h, w, h); c.fill()
    c.move_to(x - 5, YH - h); c.line_to(x + w + 5, YH - h); c.line_to(x + w - 8, YH - h - 9); c.line_to(x + 8, YH - h - 9); c.fill()
    x += w + rr.random() * 30
fm = amask(far_row[0])
town.put(fm * (yy < YH), mix(C('#4E6268'), HOR, 0.6))
for (x, w, h) in houses:
    top = YH - h
    walls[1].rectangle(x, top, w, h); walls[1].fill()
    c = roofs[1]
    # 屋顶：薄而深的瓦檐
    c.move_to(x - 8, top + 3); c.line_to(x + w + 8, top + 3); c.line_to(x + w - 4, top - 10); c.line_to(x + 4, top - 10); c.close_path(); c.fill()
    # 马头墙：两端台阶状
    steps = 1 + int(r.random() * 3)
    for side in (0, 1):
        for k in range(steps):
            sw = 16; sh = 12 + k * 11
            sx = x + k * sw if side == 0 else x + w - (k + 1) * sw
            walls[1].rectangle(sx, top - sh, sw, sh); walls[1].fill()
            c.rectangle(sx - 3, top - sh - 4, sw + 6, 5); c.fill()
    # 窗
    nw = int(w / 38)
    for k in range(nw):
        wx = x + 18 + k * (w - 36) / max(nw - 1, 1) if nw > 1 else x + w / 2
        for row in ([top + h * 0.35] if h < 90 else [top + h * 0.25, top + h * 0.6]):
            wins.append((wx, row, r.random() < 0.28))
wm = amask(walls[0]); rm = amask(roofs[0]); tm = amask(trees[0])
tm = sstep(0.42, 0.58, cv2.GaussianBlur(tm, (0, 0), 7) + (noise(14, 14, 4, 75) - 0.5) * 0.5) * (yy < YH)
wallc = mix(C('#8A9A98')[None, None], HOR[None, None], (0.32 + 0.4 * sstep(YH - 140, YH, yy))[..., None])
wallc = wallc * (0.92 + 0.08 * noise(30, 30, 3, 73))[..., None]
tone = np.ones((H, W), np.float32); topmap = np.full((H, W), YH, np.float32); rt = np.random.default_rng(76)
for (hx, hw, hh) in houses:
    tone[YH - int(hh) - 40:YH, max(0, int(hx)):int(hx + hw)] = 0.82 + 0.22 * rt.random()
    topmap[YH - int(hh) - 40:YH, max(0, int(hx)):int(hx + hw)] = YH - hh
streak = sstep(0.35, 0.85, noise(4, 120, 3, 77)) * np.exp(-np.clip(yy - topmap, 0, None) / 38)
grime = np.clip(streak * 0.55 + 0.4 * sstep(YH - 26, YH, yy) * noise(20, 8, 3, 78), 0, 0.75)
wallc = wallc * tone[..., None]
wallc = mix(wallc, C('#2B3A3C')[None, None], grime[..., None])
town.put(wm * (yy < YH), wallc)
town.put(rm * (yy < YH), mix(C('#141E24'), HOR, 0.22))
tiles = (np.sin(xx * 1.6) > 0.55).astype(np.float32) * rm * (1 - lit_edge(rm, 0, 3))
town.put(tiles * (yy < YH), mix(C('#26333A'), HOR, 0.2), 0.6)
town.put(lit_edge(rm, 0, 1) * (yy < YH), C('#5F7474'), 0.5)
town.put(tm * (yy < YH), mix(C('#132227'), HOR, 0.25))
s, c = surf()
for (wx, wy, lit) in wins:
    c.rectangle(wx - 4, wy - 5, 8, 10); c.fill()
town.put(amask(s), C('#1A262B'))
for (wx, wy, lit) in wins:
    if lit:
        town.glow(wx, wy, 3.2, WARM, 0.95, sy=4.5); town.glow(wx, wy, 14, WARM, 0.10)
reflect(town, YH, 160, darken=0.55, alpha=0.7, wob=3.0, seed=74)
for (wx, wy, lit) in wins:
    if lit:
        town.glow(wx, YH + (YH - wy) + 6, 2.2, WARM, 0.28, sy=16)
layers.append(town)

# ============================================================ 5 月光水路（固定在屏幕）
mp = Layer('moon_path', 0.0, add=True)
wid = np.maximum(24 + (yy - YH) * 0.5, 4)
dash = sstep(0.6, 0.82, noise(160, 3.2, 3, 81))
inten = np.exp(-((xx - MOON[0]) / (wid * 0.55)) ** 2) * dash * (yy > YH + 2) * (yy < YW) * (1.0 - 0.6 * np.clip((yy - YH) / (YW - YH), 0, 1))
mp.a[..., :3] += (inten * 0.55)[..., None] * C('#C8D3C6')[None, None]
mp.a[..., :3] += (np.exp(-((xx - MOON[0]) / (wid * 1.6)) ** 2) * (yy > YH) * (yy < YW) * 0.05)[..., None] * C('#8FA6A2')[None, None]
layers.append(mp)

# ============================================================ 6 石拱桥（三孔驼峰桥，桥洞镂空，倒影成圆）+ 灯笼
bridge = Layer('bridge', 0.35)
BC = 1500.0; R0, R1 = 104.0, 52.0; RING = 15.0
SIDE = R0 + 34 + R1                    # 侧孔圆心离中心
HALF = 450.0                           # 桥两端
DECK_TOP = YB - R0 - RING - 18
def ydeck(x):
    d = abs(x - BC)
    if d < 58: return DECK_TOP
    t = min(1.0, (d - 58) / (HALF - 58))
    y = DECK_TOP + (YB - 30 - DECK_TOP) * t ** 1.08
    return math.floor(y / 7) * 7 if d > 70 else y    # 坡面台阶
xsd = np.arange(BC - HALF, BC + HALF + 1, 1.0)
def bridge_body(c):
    c.move_to(xsd[0], YB)
    for x in xsd: c.line_to(x, ydeck(x))
    c.line_to(xsd[-1], YB); c.close_path(); c.fill()
    # 两端石砌驳岸
    for sgn in (-1, 1):
        x0 = BC + sgn * HALF
        c.move_to(x0, YB - 30); c.line_to(x0 + sgn * 70, YB - 16); c.line_to(x0 + sgn * 90, YB); c.line_to(x0, YB); c.close_path(); c.fill()
bm = shape(bridge_body)
ARCH = [(BC - SIDE, R1), (BC, R0), (BC + SIDE, R1)]
def arches(c):
    for (xc, rad) in ARCH: c.arc(xc, YB + 1, rad, math.pi, 2 * math.pi); c.close_path(); c.fill()
am = shape(arches)
def ring(c):
    for (xc, rad) in ARCH:
        c.set_line_width(RING); c.arc(xc, YB + 1, rad + RING / 2, math.pi, 2 * math.pi); c.stroke()
rgm = shape(ring)
def vouss(c):
    for (xc, rad) in ARCH:
        n = int(rad / 4.2)
        for k in range(1, n):
            a = math.pi + k * math.pi / n; c.set_line_width(1.3)
            c.move_to(xc + math.cos(a) * rad, YB + 1 + math.sin(a) * rad)
            c.line_to(xc + math.cos(a) * (rad + RING), YB + 1 + math.sin(a) * (rad + RING)); c.stroke()
vm = shape(vouss)
# 石块：交错砌，每块明度不同
r = np.random.default_rng(91)
blk = np.zeros((H, W), np.float32); s, c = surf(); c.set_line_width(1.1)
for y0 in range(int(DECK_TOP) - 4, YB, 12):
    x = BC - HALF - r.random() * 40
    c.move_to(BC - HALF - 180, y0); c.line_to(BC + HALF + 180, y0); c.stroke()
    while x < BC + HALF + 180:
        w = 24 + r.random() * 34
        blk[y0:y0 + 12, max(0, int(x)):int(x + w)] = r.random()
        c.move_to(x, y0); c.line_to(x, y0 + 12); c.stroke(); x += w
jm = amask(s)
body = np.clip(bm - am, 0, 1)
inner = np.clip(body - np.clip(rgm, 0, 1), 0, 1)
stn = noise(30, 14, 4, 92)
stone = C('#24343B') * (0.82 + 0.22 * blk + 0.14 * stn)[..., None]
# 水线上方受潮更暗、更绿
damp = sstep(YB - 60, YB, yy)
stone = mix(stone, C('#14231F')[None, None], (damp * 0.55)[..., None])
bridge.put(body, stone)
bridge.put(jm * inner, C('#111C21'), 0.55)
ringc = C('#30434A') * (0.9 + 0.2 * stn)[..., None]
bridge.put(rgm * body, mix(ringc, C('#15241F')[None, None], (damp * 0.4)[..., None]))
bridge.put(vm * rgm * body, C('#121D22'), 0.75)
# 桥洞内侧拱腹（暗）
def soffit(c):
    for (xc, rad) in ARCH:
        c.set_line_width(rad * 0.07); c.arc(xc, YB + 1, rad - rad * 0.035, math.pi, 2 * math.pi); c.stroke()
sfm = shape(soffit) * am
bridge.put(sfm, C('#0C1418'), 0.6)
# 栏板 + 望柱
def parapet(c):
    xs = np.arange(BC - HALF + 14, BC + HALF - 13, 1.0)
    c.move_to(xs[0], ydeck(xs[0]))
    for x in xs: c.line_to(x, ydeck(x) - 13)
    for x in xs[::-1]: c.line_to(x, ydeck(x))
    c.close_path(); c.fill()
posts = list(np.arange(BC - HALF + 24, BC + HALF - 20, 46.0))
def pposts(c):
    for x in posts:
        y = ydeck(x); c.rectangle(x - 3.5, y - 21, 7, 21); c.fill(); c.arc(x, y - 22, 4, 0, 6.283); c.fill()
ppm = shape(parapet); pom = shape(pposts)
bridge.put(ppm, C('#2B3D44') * (0.9 + 0.15 * stn)[..., None])
s, c = surf(); c.set_line_width(1)
for x in np.arange(BC - HALF + 30, BC + HALF - 20, 23.0):
    c.move_to(x, ydeck(x) - 12); c.line_to(x, ydeck(x) - 1); c.stroke()
bridge.put(amask(s) * ppm, C('#172328'), 0.6)
bridge.put(pom, C('#33464C'))
# 朝上的面受一点冷月光（很淡、不是描边）
top_all = np.clip(body + ppm + pom, 0, 1)
bridge.put(lit_edge(top_all, 0, 2), C('#5D7373'), 0.55)
bridge.put(lit_edge(rgm * body, 0, 1), C('#4B6062'), 0.4)
# 桥身藤蔓（薜荔）垂挂
s, c = surf(); r = np.random.default_rng(94)
for (x0, n) in ((BC - R0 - 20, 9), (BC + R0 + 22, 7), (BC - SIDE - R1 - 10, 5)):
    for i in range(n):
        xx0 = x0 + r.normal() * 14; L = 18 + r.random() * 46
        strand(c, r, xx0, ydeck(xx0) + 2, L, r.normal() * 5, lw=0.9, leaf=3.6, spacing=3.2)
vine = amask(s) * np.clip(body + am, 0, 1)
bridge.put(vine, C('#101C1A'), 0.95)
# 灯笼：挂在望柱上，桥面暖光
lant = [(x, ydeck(x) - 6) for x in posts[1::2]]
s, c = surf()
for (x, y) in lant:
    c.set_line_width(1); c.move_to(x + 4, y - 16); c.line_to(x + 9, y - 16); c.line_to(x + 9, y - 6); c.stroke()
    c.save(); c.translate(x + 9, y + 1); c.scale(5.2, 6.4); c.arc(0, 0, 1, 0, 6.283); c.restore(); c.fill()
    c.rectangle(x + 6.5, y - 6.4, 5, 1.6); c.fill(); c.rectangle(x + 6.5, y + 6.8, 5, 1.6); c.fill()
lm = amask(s)
bridge.put(lm, LANT_RED)
warm_on_stone = np.zeros((H, W), np.float32)
for (x, y) in lant:
    bridge.glow(x + 9, y + 1, 2.6, WARM_CORE, 1.0, sy=3.8)
    bridge.glow(x + 9, y + 1, 13, WARM, 0.18)
    warm_on_stone += np.exp(-(((xx - x - 9) / 30) ** 2 + ((yy - y - 16) / 26) ** 2))
bridge.a[..., :3] += (np.clip(warm_on_stone, 0, 1) * top_all * 0.22)[..., None] * WARM[None, None]
reflect(bridge, YB, 200, darken=0.5, alpha=0.82, wob=2.2, seed=95)
for (x, y) in lant:
    yr = YB + (YB - y)
    bridge.glow(x + 9, yr, 2.8, WARM, 0.34, sy=20)
    bridge.glow(x + 9, yr + 34, 2.0, WARM, 0.12, sy=26)
layers.append(bridge)

# ============================================================ 7 乌篷船
boat = Layer('boat', 0.5)
BX, BY = 640.0, 746.0
def hull(c):
    c.move_to(BX - 105, BY - 16); c.curve_to(BX - 70, BY + 2, BX + 60, BY + 4, BX + 110, BY - 20)
    c.line_to(BX + 104, BY - 12); c.curve_to(BX + 50, BY - 6, BX - 60, BY - 6, BX - 98, BY - 9); c.close_path(); c.fill()
def canopy(c):
    c.move_to(BX - 46, BY - 8); c.curve_to(BX - 44, BY - 40, BX + 40, BY - 42, BX + 44, BY - 8); c.close_path(); c.fill()
    c.set_line_width(2); c.move_to(BX + 70, BY - 12); c.line_to(BX + 140, BY - 120); c.stroke()
hm = shape(hull); cm2 = shape(canopy)
boat.put(cm2, C('#121B20')); boat.put(hm, C('#0E1519'))
boat.put(lit_edge(cm2, 0, 2), C('#4A6062'), 0.7)
s, c = surf(); c.set_line_width(1); c.move_to(BX - 92, BY - 14); c.line_to(BX - 92, BY - 34); c.stroke()
c.save(); c.translate(BX - 92, BY - 30); c.scale(4, 5); c.arc(0, 0, 1, 0, 6.283); c.restore(); c.fill()
boat.put(amask(s), LANT_RED)
boat.glow(BX - 92, BY - 30, 2.2, WARM_CORE, 0.9); boat.glow(BX - 92, BY - 30, 22, WARM, 0.14)
reflect(boat, int(BY - 2), 60, darken=0.45, alpha=0.7, wob=2.0, seed=93)
boat.glow(BX - 92, BY + 26, 2.4, WARM, 0.3, sy=18)
layers.append(boat)

# ============================================================ 8 中景垂柳 + 岸边草
mid = Layer('willow_mid', 0.6)
def willow(c, r, tx, ty, height, width, nstr, lean=0.0):
    """树冠是一团有机的圆顶叶团，垂丝从叶团下沿和内部垂下，外圈长、中间短，形成帘子。返回 (冠, 枝条) 两个绘制列表。"""
    kx = tx + lean; ky = ty - height * 0.42
    c.set_line_width(28); c.move_to(tx - 6, ty); c.curve_to(tx - 6, ty - height * 0.2, kx - 12, ky + 40, kx, ky); c.stroke()
    c.set_line_width(18); c.move_to(tx + 12, ty); c.curve_to(tx + 10, ty - 50, kx + 10, ky + 40, kx + 6, ky); c.stroke()
    rx = height * 0.55 * width; ry = height * 0.30
    ccx, ccy = kx + lean * 0.6, ty - height * 0.86
    for ang in (-2.4, -1.9, -1.35, -0.85):
        ex, ey = ccx + math.cos(ang) * rx * 0.75, ccy + math.sin(ang) * ry * 0.4 + ry * 0.5
        c.set_line_width(11); c.move_to(kx, ky); c.curve_to(kx, ky - 40, ex - (ex - kx) * 0.4, ey + 20, ex, ey); c.stroke()
    blobs = []
    for i in range(70):
        t = r.random() * 2 * math.pi; rr = math.sqrt(r.random())
        bx = ccx + math.cos(t) * rx * rr * 0.8; by = ccy + math.sin(t) * ry * rr * 0.7
        blobs.append((bx, by, 10 + 16 * r.random()))
    # 树冠表层：大量短垂丝从冠顶拱出，冠顶就有柳叶质感
    for i in range(int(nstr * 0.8)):
        t = r.random() * 2 * math.pi; rr = math.sqrt(r.random())
        bx = ccx + math.cos(t) * rx * rr * 0.95; by = ccy + math.sin(t) * ry * rr * 0.95 - ry * 0.15
        p = ((bx, by), (bx + 10, by - 14 - 10 * r.random()), (bx + 22, by - 6), (bx + 26 + 10 * r.random(), by + 28 + 50 * r.random()))
        c.set_line_width(0.9); c.move_to(*p[0]); c.curve_to(*p[1], *p[2], *p[3]); c.stroke()
        n = 12
        for k in range(n):
            x, y = bez(p, (k + 0.5) / n); tx_, ty_ = bezd(p, (k + 0.5) / n); a = math.atan2(ty_, tx_) + (0.4 if k % 2 else -0.4)
            c.move_to(x, y); c.line_to(x + 5.5 * math.cos(a), y + 5.5 * math.sin(a)); c.stroke()
    for i in range(nstr):
        u = r.normal() * 0.55; u = max(-1.08, min(1.08, u))
        x0 = ccx + u * rx
        y0 = ccy + ry * math.sqrt(max(0.0, 1 - min(1, u * u))) * (0.2 + 0.8 * r.random()) - ry * 0.2
        dist = min(1.0, abs(u))
        L = (ty - 40 - y0) * (0.28 + 0.72 * dist ** 0.7) * (0.65 + 0.45 * r.random())
        strand(c, r, x0, y0, max(40, L), 10 + 22 * r.random(), lw=0.85, leaf=5.6, spacing=3.4)
    return blobs
r = np.random.default_rng(101)
s, c = surf(); bl1 = willow(c, r, 250, YW + 10, 480, 1.0, 520, lean=24)
bl2 = willow(c, r, 2240, YW + 10, 350, 0.85, 300, lean=-16)
wlm = amask(s)
s2, c2 = surf()
for (bx, by, br) in bl1 + bl2: c2.arc(bx, by, br, 0, 6.283); c2.fill()
crown = sstep(0.42, 0.6, cv2.GaussianBlur(amask(s2), (0, 0), 9) + (noise(9, 9, 4, 102) - 0.5) * 0.55)
wlm = np.clip(wlm + crown * 0.8, 0, 1)
# 叶团体积：从上到下、从外到内微弱明暗（月在右上后方，不做白描边）
dens = cv2.GaussianBlur(wlm, (0, 0), 14)
wl = mix(C('#0E1C1F')[None, None], C('#24393A')[None, None], (np.clip(1 - dens * 1.6, 0, 1) * 0.8)[..., None])
wl = wl * (1 - 0.35 * sstep(YW - 260, YW, yy))[..., None]
mid.put(wlm, wl)
# 岸边草（软化步道和水的分界）
s, c = surf(); c.set_line_width(1.4)
for i in range(1400):
    x = r.random() * W; hgt = 8 + r.random() * 22
    if r.random() < 0.35: continue
    c.move_to(x, YW + 4); c.curve_to(x, YW - hgt * 0.5, x + 3, YW - hgt * 0.8, x + 2 + r.normal() * 4, YW - hgt); c.stroke()
mid.put(amask(s), C('#15242A'))
layers.append(mid)

# ============================================================ 9 背光雾带（角色身后，中等明度）
fogb = Layer('fog_band', 0.9)
fn = noise(620, 60, 5, 111)
fogb.put(np.ones((H, W), np.float32), C('#4D6870'))
fogb.a *= (0.40 * gauss((yy - 812) / 52) * (0.5 + 0.5 * fn) * (yy < YW + 2))[..., None]
layers.append(fogb)

# ============================================================ 10 河堤步道（战斗层）
walk = Layer('walkway', 1.0)
r = np.random.default_rng(121)
top_m = ((yy >= YW) & (yy < YWALL)).astype(np.float32)
slab = np.zeros(W, np.float32); joints_x = []
x = 0.0
while x < W:
    w = 60 + r.random() * 80; slab[int(x):int(x + w)] = r.random(); joints_x.append(x); x += w
slabv = (0.9 + 0.18 * slab)[None, :]
topc = C('#46585C') * slabv[..., None] * (0.92 + 0.12 * noise(16, 6, 3, 122))[..., None]
topc = topc * (1 - 0.25 * sstep(YW + 6, YWALL, yy))[..., None]
walk.put(top_m, topc)
walk.put(((yy >= YW) & (yy < YW + 2)).astype(np.float32), C('#93A6A1'), 0.8)
s, c = surf(); c.set_line_width(1.6)
for jx in joints_x: c.move_to(jx, YW + 2); c.line_to(jx - 3, YWALL); c.stroke()
walk.put(amask(s) * top_m, C('#1D292D'), 0.8)
# 墙：毛石块
wall_m = ((yy >= YWALL) & (yy < YWB)).astype(np.float32)
blk = np.zeros((H, W), np.float32); s, c = surf(); c.set_line_width(2.2)
rows = [YWALL, YWALL + 30, YWALL + 62, YWB]
for k in range(3):
    y0, y1 = rows[k], rows[k + 1]; x = -r.random() * 80
    c.move_to(0, y0); c.line_to(W, y0); c.stroke()
    while x < W:
        w = 70 + r.random() * 80; blk[int(y0):int(y1), max(0, int(x)):int(x + w)] = r.random()
        c.move_to(x, y0); c.line_to(x + r.normal() * 2, y1); c.stroke(); x += w
mort = amask(s)
wn = noise(10, 10, 3, 123)
wallc = C('#1D2C31') * (0.8 + 0.36 * blk)[..., None] * (0.9 + 0.2 * wn)[..., None]
moss = sstep(0.55, 0.75, noise(90, 26, 4, 124)) * (gauss((yy - YWALL - 6) / 10) + gauss((yy - YWB + 8) / 12))
wallc = mix(wallc, C('#1D3330')[None, None], (moss * 0.6)[..., None])
wallc = wallc * (1 - 0.35 * sstep(YWB - 24, YWB, yy))[..., None]
walk.put(wall_m, wallc)
walk.put(mort * wall_m, C('#10181B'), 0.85)
walk.put(lit_edge(wall_m * (1 - mort), 0, 2) * wall_m, C('#3E5257'), 0.5)
walk.put(((yy >= YWALL) & (yy < YWALL + 3)).astype(np.float32), C('#0D1417'), 0.9)
# 墙面细节：河埠头台阶、系船石、排水孔+水渍、石缝里的蕨草
s, c = surf()
STX = 1080.0
for k in range(7):
    c.rectangle(STX + k * 22, YWALL + k * 13.5, 170 - k * 22, 13.5); c.fill()
stair = amask(s) * wall_m
s, c = surf()
for k in range(7): c.rectangle(STX + k * 22, YWALL + k * 13.5, 170 - k * 22, 2.2); c.fill()
tread = amask(s) * wall_m
walk.put(stair, C('#121C20'))
walk.put(cv2.GaussianBlur(stair, (0, 0), 3) * (1 - stair) * wall_m, C('#0B1215'), 0.6)
walk.put(tread, C('#405254'), 0.8)
s, c = surf()
for x in (770.0, 1930.0):
    c.rectangle(x - 13, YWALL + 26, 26, 22); c.fill()
ms = amask(s) * wall_m
walk.put(ms, C('#33454A'))
s, c = surf(); c.set_line_width(2.6)
for x in (770.0, 1930.0): c.arc(x, YWALL + 46, 7, 0, math.pi); c.stroke()
walk.put(amask(s), C('#0E1517'), 0.9)
s, c = surf()
for x in (400.0, 1560.0, 2140.0): c.rectangle(x - 9, YWALL + 36, 18, 13); c.fill()
holes2 = amask(s)
drip = np.zeros((H, W), np.float32)
for x in (400.0, 1560.0, 2140.0):
    drip += np.exp(-((xx - x) / 8) ** 2) * (yy > YWALL + 48) * np.exp(-(yy - YWALL - 48).clip(0) / 40)
walk.put(np.clip(drip, 0, 1) * wall_m * (0.55 + 0.45 * noise(3, 60, 3, 128)), C('#14201F'), 0.8)
walk.put(holes2, C('#05090B'))
s, c = surf(); c.set_line_width(1.6); rf = np.random.default_rng(129)
for i in range(38):
    x = rf.random() * W; y = rows[1 + int(rf.random() * 2)]
    for k in range(5):
        a = -math.pi / 2 + (k - 2) * 0.5 + rf.normal() * 0.1; L = 9 + rf.random() * 12
        c.move_to(x, y); c.curve_to(x + math.cos(a) * L * 0.5, y + math.sin(a) * L * 0.6, x + math.cos(a) * L, y + math.sin(a) * L * 0.6, x + math.cos(a) * L * 1.2, y + math.sin(a) * L * 0.3 + 4); c.stroke()
walk.put(amask(s) * (1 - stair), C('#12201C'), 0.95)
# 步道面：湿痕（深）和积水（反光）
wet = sstep(0.55, 0.75, noise(120, 10, 4, 130)) * top_m
walk.put(wet, C('#2C3B3F'), 0.45)
pud = sstep(0.72, 0.8, noise(90, 7, 4, 131)) * top_m * (yy > YW + 4)
walk.put(pud, C('#6E8687'), 0.35)
# 墙下水面 + 墙的倒影
lw_m = (yy >= YWB).astype(np.float32)
nearw = mix(C('#0B161B')[None, None], C('#081014')[None, None], np.clip((yy - YWB) / 100, 0, 1)[..., None])
nearw = nearw + (sstep(0.6, 0.8, noise(900, 5, 4, 125)) * 0.06)[..., None] * C('#9FB6B4')[None, None]
walk.put(lw_m, nearw)
# 石灯笼
LANTERNS = [560.0, 1420.0, 2330.0]
def stone_lantern(c, x):
    y = YW
    c.rectangle(x - 28, y - 10, 56, 10); c.fill()
    c.move_to(x - 11, y - 10); c.line_to(x - 9, y - 58); c.line_to(x + 9, y - 58); c.line_to(x + 11, y - 10); c.fill()
    c.rectangle(x - 24, y - 67, 48, 9); c.fill()
    c.rectangle(x - 18, y - 99, 36, 32); c.fill()
    c.move_to(x - 36, y - 99); c.curve_to(x - 26, y - 101, x - 14, y - 112, x, y - 117)
    c.curve_to(x + 14, y - 112, x + 26, y - 101, x + 36, y - 99); c.line_to(x + 30, y - 95); c.line_to(x - 30, y - 95); c.fill()
    c.rectangle(x - 4, y - 127, 8, 11); c.fill(); c.arc(x, y - 129, 5, 0, 6.283); c.fill()
s, c = surf()
for x in LANTERNS: stone_lantern(c, x)
slm = amask(s)
s, c = surf()
for x in LANTERNS: c.rectangle(x - 10, YW - 93, 20, 20); c.fill()
holes = amask(s)
lc = C('#34454A') * (0.88 + 0.2 * noise(8, 8, 3, 126))[..., None]
lcol = mix(lc, C('#1A2427')[None, None], 0.0)
walk.put(slm, lcol)
walk.put(lit_edge(slm, 2, 2), C('#62787A'), 0.55)
walk.put(holes, C('#FFB765'))
# 木栏杆
s, c = surf()
for x in np.arange(1660, 2010, 58): c.rectangle(x - 3, YW - 46, 7, 46); c.fill()
c.rectangle(1656, YW - 42, 356, 5); c.fill(); c.rectangle(1656, YW - 22, 356, 4); c.fill()
rail = amask(s)
walk.put(rail, C('#27231F'))
walk.put(lit_edge(rail, 0, 2), C('#5A5249'), 0.6)
reflect(walk, YWB, 90, darken=0.4, alpha=0.6, wob=2.0, seed=127)
layers.append(walk)

# ============================================================ 11 灯光（加色）：石灯笼光圈、墙面暖光、雾里暖晕
light = Layer('walk_light', 1.0, add=True)
for x in LANTERNS:
    light.glow(x, YW - 83, 9, WARM_CORE, 0.9)
    light.glow(x, YW - 83, 60, WARM, 0.16)
    light.glow(x, YW - 70, 210, WARM, 0.07)
    g = np.exp(-(((xx - x) / 190) ** 2 + ((yy - YW - 6) / 14) ** 2)) * top_m
    light.a[..., :3] += (g * 0.35)[..., None] * WARM[None, None]
    g2 = np.exp(-(((xx - x) / 150) ** 2 + ((yy - YWALL - 10) / 50) ** 2)) * wall_m
    light.a[..., :3] += (g2 * 0.16)[..., None] * WARM[None, None]
    light.glow(x, YWB + 40, 3.5, WARM, 0.25, sy=40)
layers.append(light)

# ============================================================ 12 萤火
ff = Layer('fireflies', 1.0, add=True)
r = np.random.default_rng(131)
for i in range(26):
    x = r.random() * W; y = 640 + r.random() * 210
    ff.glow(x, y, 1.6, C('#FFE29A'), 0.9); ff.glow(x, y, 9, C('#FFD27A'), 0.08)
layers.append(ff)

# ============================================================ 13 前景剪影（柳枝、石栏、芦苇），轻微虚化
fg = Layer('foreground', 1.4)
r = np.random.default_rng(141)
s, c = surf()
for i in range(70):
    x0 = r.random() * 460; L = 90 + 300 * r.random() * (1 - x0 / 600)
    strand(c, r, x0, -20, L, 10 + 20 * r.random(), lw=2.0, leaf=13, spacing=6)
for i in range(26):
    x0 = 1790 + r.random() * 260; L = 60 + 170 * r.random()
    strand(c, r, x0, -20, L, 6 + 14 * r.random(), lw=2.0, leaf=12, spacing=6)
for x in list(np.arange(-40, 820, 120)) + list(np.arange(1480, 2600, 120)):
    c.rectangle(x - 9, 1008, 18, 80); c.fill(); c.rectangle(x - 13, 1000, 26, 10); c.fill()
c.rectangle(-40, 1030, 860, 14); c.fill(); c.rectangle(1480, 1030, 1200, 14); c.fill()
c.set_line_width(2.4)
for cx in (790, 1460, 2480):
    for i in range(16):
        h = 60 + r.random() * 90; x = cx + r.normal() * 22
        c.move_to(x, 1085); c.curve_to(x, 1085 - h * 0.5, x + r.normal() * 8, 1085 - h * 0.8, x + r.normal() * 16, 1085 - h); c.stroke()
fgm = cv2.GaussianBlur(amask(s), (0, 0), 2.2)
fg.put(fgm, SIL, 0.97)
layers.append(fg)


def composite(pan=0.0, post=True):
    img = np.zeros((H, VIEW, 3), np.float32)
    for L in layers:
        off = int(round(pan * L.par)); sl = np.nan_to_num(L.a[:, off:off + VIEW])
        if L.add: img += sl[..., :3]
        else: img = sl[..., :3] + img * (1 - sl[..., 3:])
    if post:
        lum = img.mean(-1)
        hi = np.clip(img - 0.62, 0, None)
        img = img + 0.55 * cv2.GaussianBlur(hi, (0, 0), 7) + 0.45 * cv2.GaussianBlur(hi, (0, 0), 28)
        vy, vx = np.mgrid[0:H, 0:VIEW].astype(np.float32)
        v = ((vx - VIEW / 2) / (VIEW * 0.62)) ** 2 + ((vy - H * 0.45) / (H * 0.75)) ** 2
        img = img * (1 - 0.32 * np.clip(v, 0, 1))[..., None]
        img = img + (np.random.default_rng(9).random((H, VIEW, 1)).astype(np.float32) - 0.5) * 0.012
    return np.clip(img, 0, 1)


if __name__ == '__main__':
    img = composite()
    cv2.imwrite(OUT + '/comp.png', (img[..., ::-1] * 255).astype(np.uint8))
    cv2.imwrite(OUT + '/comp_1280.jpg', cv2.resize((img[..., ::-1] * 255).astype(np.uint8), (1280, 720), interpolation=cv2.INTER_AREA), [cv2.IMWRITE_JPEG_QUALITY, 92])
    meta = []
    for L in layers:
        a = L.a.copy()
        if L.add:
            rgba = np.concatenate([np.clip(a[..., :3], 0, 1), np.ones((H, W, 1), np.float32)], -1)
        else:
            al = a[..., 3:]; rgb = np.where(al > 1e-4, a[..., :3] / np.maximum(al, 1e-4), 0)
            rgba = np.concatenate([np.clip(rgb, 0, 1), al], -1)
        cv2.imwrite('%s/layers/%s.png' % (OUT, L.name), (rgba[..., [2, 1, 0, 3]] * 255).astype(np.uint8))
        meta.append({'name': L.name, 'parallax': L.par, 'add': L.add})
    json.dump({'w': W, 'h': H, 'view': VIEW, 'layers': meta}, open(OUT + '/layers/layers.json', 'w'), indent=1)
    print('ok')
