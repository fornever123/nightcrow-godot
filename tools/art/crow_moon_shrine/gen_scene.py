"""鸦冢月祠 —— 程序化像素视差场景生成器。

原生分辨率 640x360（游戏内整数放大 x2/x3），所有视差层水平可平铺。
用法: py -3.10 gen_scene.py  -> 输出到 assets/scenery/crow_moon_shrine/
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw

H = 360
GROUND_Y = 296
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "..", "..", "assets", "scenery", "crow_moon_shrine"))

BAYER4 = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) + 0.5) / 16.0

# ---------------------------------------------------------------- palette
P = {
    # sky (deep -> horizon)
    "sky": ["#08081a", "#0d0d24", "#12142f", "#171d3b", "#1d2747", "#233353", "#2b405f", "#344e6a", "#3f5d74", "#4d6d7e"],
    "star": ["#56688c", "#8798b8", "#c9d4e4", "#f4f6ff"],
    "moon": ["#fbf7e4", "#ece8cf", "#d8d8bf", "#bfc5af", "#a3ae9f"],
    "cloud": ["#18223c", "#20304c", "#2a3d5a", "#3a5470", "#5a7a90", "#8fa9b0"],
    "far": ["#2a4062", "#30496b", "#3a5677", "#4a6a86", "#5d7f95"],
    "far2": ["#21334f", "#27405d", "#2f4a68", "#3e5f7a"],
    "mist": ["#3d5a73", "#4b6a80", "#5a7b8d"],
    "mid": ["#141d34", "#18233d", "#1e2c48", "#2c4260", "#3f5f7b"],
    "near": ["#0e1324", "#121829", "#182036", "#202b46", "#2c3b5a", "#5a7c95"],
    "stone": ["#0b0e1a", "#141827", "#1b2133", "#232a40", "#2c3550", "#3a4662", "#55677f", "#7f98ab", "#a9bfcc"],
    "moss": ["#1c302f", "#25403b", "#305246", "#406a55", "#5d8a6c"],
    "fg": ["#040309", "#08070f", "#111326", "#1c2240"],
    "violet": ["#2a1660", "#4a2aa0", "#6b3fd6", "#9468ff", "#c3a6ff", "#efe6ff"],
    "amber": ["#5e2f1c", "#9a5226", "#d98a3d", "#ffc56e", "#fff0c4"],
    "steel": ["#2a3044", "#4c5670", "#7d8ba3", "#b6c3d4", "#eef3f8"],
    "paper": ["#6f8091", "#a8b8c4", "#dfe6ea"],
}


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def new_layer(w):
    return np.zeros((H, w, 4), np.uint8)


def bayer(w, h=H):
    return np.tile(BAYER4, (h // 4 + 1, w // 4 + 1))[:h, :w]


def paint(L, m, col, a=255):
    L[m] = (*rgb(col), a)


def px(L, x, y, col, a=255, wrap=True):
    h, w = L.shape[:2]
    if wrap:
        x %= w
    if 0 <= x < w and 0 <= y < h:
        L[y, x] = (*rgb(col), a)


def shift(m, dx, dy):
    """result[y, x] = m[y-dy, x-dx]; x 方向循环，y 方向不循环。"""
    r = np.roll(m, dx, axis=1)
    r = np.roll(r, dy, axis=0)
    if dy > 0:
        r[:dy] = False
    elif dy < 0:
        r[dy:] = False
    return r


def edge(m, dx, dy):
    """m 中在 (x+dx, y+dy) 处为空的像素。"""
    return m & ~shift(m, -dx, -dy)


def rim(m, dirs=((1, 0), (0, -1))):
    r = np.zeros_like(m)
    for dx, dy in dirs:
        r |= edge(m, dx, dy)
    return r


def band_index(t, n, B, seam=0.35):
    """把 0..1 映射到 n 档色带：平涂色带 + 窄的 Bayer 抖动过渡缝。"""
    v = np.clip(t, 0, 0.9999) * (n - 1)
    i = np.floor(v).astype(int)
    f = v - i
    p = (f - (1 - seam)) / seam
    up = (p > B) & (f > 1 - seam)
    return np.clip(i + up, 0, n - 1)


def pnoise(x, period, cells, octaves, seed, pers=0.5):
    total = np.zeros_like(x, dtype=float)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        c = cells * (2 ** o)
        vals = np.random.default_rng(seed + o * 101).random(c)
        u = x / period * c
        i0 = np.floor(u).astype(int) % c
        i1 = (i0 + 1) % c
        f = u - np.floor(u)
        f = f * f * (3 - 2 * f)
        total += amp * (vals[i0] * (1 - f) + vals[i1] * f)
        norm += amp
        amp *= pers
    return total / norm


class Mask:
    def __init__(self, w, wrap=True):
        self.w, self.wrap = w, wrap
        self.im = Image.new("L", (w, H), 0)
        self.d = ImageDraw.Draw(self.im)

    def offs(self):
        return (-self.w, 0, self.w) if self.wrap else (0,)

    def poly(self, pts):
        for o in self.offs():
            self.d.polygon([(x + o, y) for x, y in pts], fill=255)
        return self

    def rect(self, x0, y0, x1, y1):
        for o in self.offs():
            self.d.rectangle([x0 + o, y0, x1 + o, y1], fill=255)
        return self

    def ell(self, cx, cy, rx, ry):
        for o in self.offs():
            self.d.ellipse([cx - rx + o, cy - ry, cx + rx + o, cy + ry], fill=255)
        return self

    def line(self, pts, width=1):
        for o in self.offs():
            self.d.line([(x + o, y) for x, y in pts], fill=255, width=width)
        return self

    def arr(self):
        return np.array(self.im) > 127


def stamp(L, rows, x, y, cmap, wrap=True, flip=False):
    for j, row in enumerate(rows):
        if flip:
            row = row[::-1]
        for i, ch in enumerate(row):
            if ch in cmap:
                px(L, x + i, y + j, cmap[ch], wrap=wrap)


def blend(L, m, col, a):
    """把颜色以不透明度 a(0..1) 用 over 运算叠到层上（层内已有像素会被染色，空像素变成半透明）。"""
    if not m.any():
        return
    c = np.array(rgb(col), float)
    la = L[m, 3].astype(float) / 255.0
    lr = L[m, :3].astype(float)
    oa = a + la * (1 - a)
    orgb = (c * a + lr * (la * (1 - a))[:, None]) / np.maximum(oa, 1e-6)[:, None]
    L[m, :3] = np.clip(orgb + 0.5, 0, 255).astype(np.uint8)
    L[m, 3] = np.clip(oa * 255 + 0.5, 0, 255).astype(np.uint8)


def glow(L, cx, cy, r, col, B, levels=(0.10, 0.16, 0.24), wrap=True):
    """像素风光晕：同心平涂色阶 + 1~2px 的 Bayer 抖动接缝（不是满屏网点）。"""
    h, w = L.shape[:2]
    x0, x1 = int(cx - r) - 2, int(cx + r) + 3
    y0, y1 = max(0, int(cy - r) - 2), min(h, int(cy + r) + 3)
    xs = np.arange(x0, x1)
    ys = np.arange(y0, y1)
    gx, gy = np.meshgrid(xs, ys)
    d = np.hypot(gx - cx, (gy - cy) * 1.1) + (B[gy % 4, gx % 4] - 0.5) * 2.2
    xi = gx % w if wrap else np.clip(gx, 0, w - 1)
    valid = (gx >= 0) & (gx < w) if not wrap else np.ones_like(gx, bool)
    n = len(levels)
    for i, a in enumerate(levels):
        rad = r * (1 - i / n)
        sel = (d < rad) & valid
        m = np.zeros((h, w), bool)
        m[gy[sel], xi[sel]] = True
        blend(L, m, col, a)


def mist_band(L, y_top, thick, col, a, seed, waves=8, amp=8.0):
    """平涂半透明雾带：噪声起伏的上沿 + 1px 抖动边。"""
    h, w = L.shape[:2]
    B = bayer(w)
    x = np.arange(w).astype(float)
    top = y_top + (pnoise(x, w, waves, 3, seed) - 0.5) * 2 * amp
    yy = np.arange(h)[:, None]
    t = yy - top[None, :] + (B - 0.5) * 1.5
    blend(L, (t >= 0) & (t < thick), col, a)
    blend(L, (t >= thick * 0.45) & (t < thick), col, a * 0.6)


# ---------------------------------------------------------------- sprites
CROW_FLY = [
    ["#.........#", ".##.....##.", "..###.###..", "....###....", ".....#....."],
    ["...........", "##.......##", "..##...##..", "...#####...", ".....#....."],
]
CROW_BIG = [
    "##...............##",
    ".###...........###.",
    "..####.......####..",
    "...#####...#####...",
    "....####.#.####....",
    "......########.....",
    ".......#####.......",
    "........###........",
    ".........#.........",
]
CROW_PERCH = [
    ".##....",
    "####...",
    ".####..",
    ".#####.",
    "..#####",
    "..####.",
    "..#.#..",
]
CROW_EMBLEM = [
    "....##.....",
    "...####....",
    "..#.##.#...",
    ".##.##.##..",
    "##..##..##.",
    "#..####..#.",
    "...#..#....",
    "..#....#...",
]
FEATHER = [".#", "##", "#.", "#."]
SHIDE = ["#.", "##", ".#", "##", "#."]


# ---------------------------------------------------------------- SKY
def make_sky():
    w = 640
    L = new_layer(w)
    B = bayer(w)
    yy, xx = np.mgrid[0:H, 0:w]
    mx, my, R = 470, 92, 46
    tv = np.clip(yy / 290.0, 0, 1) ** 1.25
    d = np.hypot(xx - mx, (yy - my) * 1.08)
    g = np.clip(1 - (d - R) / 210.0, 0, 1) ** 2.2
    t = np.clip(tv * 0.78 + g * 0.62, 0, 1)
    idx = band_index(t, len(P["sky"]), B)
    for i, c in enumerate(P["sky"]):
        paint(L, idx == i, c)

    rng = np.random.default_rng(7)
    # stars
    for _ in range(260):
        x, y = int(rng.integers(0, w)), int(rng.integers(0, 230))
        if g[y, x] > 0.22:
            continue
        c = P["star"][int(rng.choice(4, p=[0.55, 0.3, 0.12, 0.03]))]
        px(L, x, y, c, wrap=False)
    for _ in range(9):
        x, y = int(rng.integers(10, w - 10)), int(rng.integers(8, 170))
        if g[y, x] > 0.15:
            continue
        px(L, x, y, P["star"][3], wrap=False)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            px(L, x + dx, y + dy, P["star"][1], wrap=False)
        if rng.random() < 0.5:
            for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
                px(L, x + dx, y + dy, P["star"][0], wrap=False)

    # moon halo rings
    ring = (d > R + 4) & (d < R + 7) & (B > 0.45)
    paint(L, ring, P["sky"][-1])
    ring2 = (d > R + 12) & (d < R + 14) & (B > 0.75)
    paint(L, ring2, P["sky"][-2])

    # moon disc
    disc = d <= R
    paint(L, disc, P["moon"][1])
    dl = np.hypot(xx - (mx + 13), (yy - (my - 11)) * 1.08)
    paint(L, disc & (dl > R + 2), P["moon"][2])
    paint(L, disc & (dl > R + 8) & (B > 0.5), P["moon"][3])
    paint(L, disc & (dl > R + 8) & (B <= 0.5), P["moon"][2])
    hl = np.hypot(xx - (mx + 18), (yy - (my - 18)) * 1.08)
    paint(L, disc & (hl < R * 0.55), P["moon"][0])
    # maria：用二维噪声阈值做有机的月海，只用相邻两档色
    xn = (xx - mx) / R
    yn = (yy - my) / R
    field = np.zeros_like(xn)
    mr = np.random.default_rng(11)
    for _ in range(14):
        cx, cy = mr.uniform(-0.8, 0.5), mr.uniform(-0.6, 0.7)
        s = mr.uniform(0.12, 0.3)
        field += np.exp(-(((xn - cx) / s) ** 2 + ((yn - cy) / (s * 0.8)) ** 2))
    mare = disc & (field > 0.75)
    paint(L, mare & ~(disc & (dl > R + 2)), P["moon"][2])
    paint(L, mare & (disc & (dl > R + 2)), P["moon"][3])
    paint(L, disc & (field > 1.45), P["moon"][3])
    for (cx, cy, r) in [(-24, 18, 3), (16, -26, 2), (26, 20, 2)]:
        cd = np.hypot(xx - (mx + cx), yy - (my + cy))
        paint(L, disc & (cd < r), P["moon"][3])
        paint(L, disc & (cd < r) & (yy == my + cy - r + 1), P["moon"][4])
    # 月亮右上缘 1px 最亮边
    paint(L, rim(disc, ((1, 0), (0, -1))) & (xx > mx) & (yy < my), P["moon"][0])

    # cloud strata (some cross the moon)
    clouds = [(360, 124, 260, 7, 3), (500, 150, 200, 5, 5), (110, 64, 200, 6, 9),
              (220, 192, 340, 9, 17), (590, 206, 220, 7, 21)]
    for cx, cy, length, thick, seed in clouds:
        cm = Mask(w, wrap=False)
        cr = np.random.default_rng(seed)
        n = int(length / 9)
        for i in range(n):
            u = i / max(1, n - 1)
            x = cx - length / 2 + u * length
            th = thick * (math.sin(u * math.pi) ** 0.7) * (0.6 + 0.6 * cr.random())
            cm.ell(x, cy + cr.integers(-2, 3) + (u - 0.5) * 6, 8 + cr.integers(0, 10), max(1.5, th))
        m = cm.arr()
        near = np.clip(1 - np.hypot(xx - mx, yy - my) / 190.0, 0, 1)
        base = P["cloud"][1] if cy < 160 else P["cloud"][2]
        paint(L, m, base)
        under = m & ~shift(m, 0, -2)
        paint(L, under, P["cloud"][0])
        top = rim(m, ((0, -1),))
        top2 = m & ~shift(m, 0, 2) & ~top
        lit_far = top & (near < 0.35)
        paint(L, lit_far, P["cloud"][3])
        paint(L, top & (near >= 0.35), P["cloud"][4])
        paint(L, top2 & (near >= 0.45) & (B > 0.5), P["cloud"][4])
        paint(L, top & (near >= 0.62), P["cloud"][5])
        # 月面上的云：更透的亮边
        over = m & disc
        paint(L, over & (B > 0.5), P["cloud"][3])
        paint(L, over & (B <= 0.5), P["cloud"][4])

    # crows over the moon
    stamp(L, CROW_BIG, mx - 34, my - 14, {"#": "#07061199"[:7]}, wrap=False)
    for (x, y, f) in [(mx + 6, my + 6, 0), (mx + 22, my - 26, 1), (mx - 52, my + 24, 1), (mx + 46, my + 18, 0),
                      (mx - 80, my - 30, 0), (mx + 80, my - 44, 1), (mx - 120, my + 2, 1)]:
        stamp(L, CROW_FLY[f], x, y, {"#": "#07061a"}, wrap=False)
    return L


# ---------------------------------------------------------------- FAR
def mountain(L, w, base, amp, cells, seed, cols, B, jag=0.25):
    x = np.arange(w)
    n = pnoise(x, w, cells, 4, seed, 0.55)
    n = n + jag * (pnoise(x, w, cells * 8, 2, seed + 50) - 0.5)
    n = (n - n.min()) / (n.max() - n.min())
    ridge = (base - amp * n ** 1.6).astype(int)
    yy = np.arange(H)[:, None]
    m = yy >= ridge[None, :]
    paint(L, m, cols[0])
    dr = np.roll(ridge, -2) - np.roll(ridge, 2)
    depth = (5 + 34 * pnoise(x, w, cells * 6, 2, seed + 9)).astype(int)
    lit = m & (dr > 0)[None, :] & (yy < (ridge + depth)[None, :])
    paint(L, lit, cols[1])
    lit2 = lit & (yy < (ridge + depth // 3)[None, :]) & (dr > 3)[None, :]
    paint(L, lit2, cols[2])
    rr = np.random.default_rng(seed + 3)
    for _ in range(w // 6):
        gx = int(rr.integers(0, w))
        if dr[gx] <= 0:
            continue
        gl = int(rr.integers(4, 18))
        for k in range(gl):
            gy = ridge[gx] + 2 + k
            xk = gx - k // 2
            if lit[min(H - 1, gy), xk % w]:
                px(L, xk, gy, cols[0])
    paint(L, rim(m, ((0, -1),)) & (dr > -1)[None, :], cols[-1])
    return ridge


def make_far():
    w = 1280
    L = new_layer(w)
    B = bayer(w)
    yy, xx = np.mgrid[0:H, 0:w]
    ridgeA = mountain(L, w, 262, 120, 5, 21, P["far"], B)
    # pagoda on the highest peak
    px0 = int(np.argmin(ridgeA[200:600])) + 200
    top = ridgeA[px0]
    pm = Mask(w)
    base_y = top + 6
    pm.rect(px0 - 9, base_y - 4, px0 + 9, base_y + 6)
    tiers = 5
    y = base_y - 4
    for i in range(tiers):
        hw = 15 - i * 2
        pm.poly([(px0 - hw - 3, y + 1), (px0 - hw, y - 2), (px0 + hw, y - 2), (px0 + hw + 3, y + 1),
                 (px0 + hw - 1, y), (px0 - hw + 1, y)])
        pm.rect(px0 - hw + 4, y - 7, px0 + hw - 4, y - 2)
        y -= 8
    pm.rect(px0, y - 8, px0, y)
    m = pm.arr()
    paint(L, m, P["far2"][1])
    paint(L, rim(m), P["far"][3])
    for i in range(tiers):
        for wx in (-3, 0, 3):
            if (i + wx) % 2 == 0:
                px(L, px0 + wx, base_y - 8 - i * 8, P["amber"][3])
    glow(L, px0, base_y - 14, 7, P["amber"][2], B, (0.08,))

    mist_band(L, 236, 40, P["mist"][1], 0.35, 71, amp=6)
    ridgeB = mountain(L, w, 300, 60, 7, 33, P["far2"], B, 0.35)
    mist_band(L, 262, 60, P["mist"][0], 0.45, 72, amp=8)
    paint(L, yy >= 318, P["far2"][0])
    return L


# ---------------------------------------------------------------- MID
def cedar(m, x, base, h, w0, rr):
    tiers = max(4, int(h / 9))
    for i in range(tiers):
        u = i / tiers
        ty = base - u * h
        hw = w0 * (1 - u) ** 0.9 + 1
        jag = rr.integers(-1, 2)
        m.poly([(x - hw - jag, ty), (x, ty - h / tiers * 1.7), (x + hw + jag, ty)])
    m.rect(x - 1, base - 6, x + 1, base + 4)


def branch(m, x, y, ang, length, width, depth, rr, tips):
    if depth == 0 or length < 3:
        tips.append((x, y))
        return
    x2 = x + math.cos(ang) * length
    y2 = y - math.sin(ang) * length
    m.line([(x, y), (x2, y2)], width=max(1, int(width)))
    n = 2 if depth > 1 else 3
    for k in range(n):
        da = rr.uniform(0.25, 0.75) * (1 if k % 2 == 0 else -1)
        branch(m, x2, y2, ang + da, length * rr.uniform(0.62, 0.78), width * 0.62, depth - 1, rr, tips)


def torii(m, x, base, h, span, lean=0.0):
    pw = 3
    for sx in (-1, 1):
        px0 = x + sx * span / 2
        m.poly([(px0 - pw, base), (px0 + pw, base), (px0 + pw + lean - 1 * sx, base - h), (px0 - pw + lean - 1 * sx, base - h)])
    kt = base - h - 6
    m.poly([(x - span / 2 - 14 + lean, kt - 4), (x + span / 2 + 14 + lean, kt - 4), (x + span / 2 + 10 + lean, kt + 2),
            (x - span / 2 - 10 + lean, kt + 2)])
    m.poly([(x - span / 2 - 16 + lean, kt - 7), (x - span / 2 - 12 + lean, kt - 4), (x - span / 2 + lean, kt - 4)])
    m.poly([(x + span / 2 + 16 + lean, kt - 7), (x + span / 2 + 12 + lean, kt - 4), (x + span / 2 + lean, kt - 4)])
    m.rect(x - span / 2 - 6 + lean, kt + 7, x + span / 2 + 6 + lean, kt + 11)
    m.rect(x - 2 + lean, kt + 2, x + 2 + lean, kt + 7)


def make_mid():
    w = 1280
    L = new_layer(w)
    B = bayer(w)
    yy, xx = np.mgrid[0:H, 0:w]
    rr = np.random.default_rng(91)
    n = pnoise(xx[0].astype(float), w, 6, 3, 300)
    gl = (290 + (n - 0.5) * 12).astype(int)

    # 远一档的杉林（更浅，被雾吃掉）
    back2 = Mask(w)
    for _ in range(34):
        x = float(rr.integers(0, w))
        cedar(back2, x, gl[int(x) % w] - 6, rr.integers(40, 80), rr.integers(7, 11), rr)
    m2 = back2.arr()
    paint(L, m2, P["far2"][1])
    paint(L, rim(m2, ((1, 0),)), P["far2"][2])
    mist_band(L, 236, 60, P["mist"][0], 0.4, 310, amp=6)

    back = Mask(w)
    for _ in range(22):
        x = float(rr.integers(0, w))
        if 150 < x % w < 330 or 370 < x % w < 450:
            continue
        cedar(back, x, gl[int(x) % w] + 2, rr.integers(60, 120), rr.integers(9, 15), rr)
    mb = back.arr() | (yy >= gl[None, :])
    paint(L, mb, P["mid"][1])
    paint(L, rim(mb, ((1, 0),)) & (yy < 280), P["mid"][2])
    paint(L, rim(mb, ((0, -1),)), P["mid"][3])

    # dead giant tree + torii
    tm = Mask(w)
    tips = []
    tx = 236
    tm.poly([(tx - 10, gl[tx] + 4), (tx + 10, gl[tx] + 4), (tx + 5, gl[tx] - 40), (tx + 2, gl[tx] - 90), (tx - 3, gl[tx] - 90),
             (tx - 5, gl[tx] - 40)])
    tm.poly([(tx - 18, gl[tx] + 4), (tx - 8, gl[tx] - 6), (tx - 4, gl[tx] + 4)])
    tm.poly([(tx + 20, gl[tx] + 4), (tx + 8, gl[tx] - 8), (tx + 4, gl[tx] + 4)])
    br = np.random.default_rng(5)
    branch(tm, tx, gl[tx] - 88, math.radians(95), 26, 5, 5, br, tips)
    branch(tm, tx + 2, gl[tx] - 60, math.radians(25), 30, 4, 4, br, tips)
    branch(tm, tx - 2, gl[tx] - 50, math.radians(160), 26, 4, 4, br, tips)
    TX = 404
    torii(tm, TX, gl[TX] + 2, 92, 84, lean=3)
    torii(tm, 1010, gl[1010] + 2, 70, 60, lean=-2)
    m = tm.arr()
    paint(L, m, P["mid"][0])
    paint(L, rim(m, ((1, 0),)), P["mid"][3])
    paint(L, rim(m, ((0, -1),)), P["mid"][4])
    # crows perched on tips
    pr = np.random.default_rng(12)
    for (x, y) in pr.permutation(np.array(tips))[:9]:
        stamp(L, CROW_PERCH, int(x) - 3, int(y) - 7, {"#": P["mid"][0]}, flip=bool(pr.random() < 0.5))
    # shimenawa + shide on big torii
    rope = [(TX + 3 - 42 + i, gl[TX] - 74 + int(4 * math.sin(i / 84 * math.pi))) for i in range(0, 85)]
    for (x, y) in rope:
        px(L, x, y, P["paper"][0])
        px(L, x, y + 1, P["mid"][3])
    for k in range(5):
        x, y = rope[8 + k * 17]
        stamp(L, SHIDE, x, y + 2, {"#": P["paper"][1 if k % 2 else 2]})
    # violet spirit lights at torii bases (far, tiny)
    for x in (TX - 42, TX + 44, 1010 - 30, 1010 + 30):
        glow(L, x, gl[x] - 10, 12, P["violet"][2], B, (0.12, 0.22))
        px(L, x, gl[x] - 10, P["violet"][4])
        px(L, x, gl[x] - 9, P["violet"][3])
    mist_band(L, 270, 40, P["mist"][0], 0.35, 320, amp=5)
    return L


# ---------------------------------------------------------------- NEAR
def shrine_hall(m, roofm, x, base, w2, h, rr):
    """右侧残破拝殿：柱 + 反翘屋檐。返回灯笼挂点。"""
    roof_y = base - h
    for k in range(5):
        cx = x - w2 + 6 + k * (2 * w2 - 12) / 4
        m.rect(cx - 2, roof_y + 6, cx + 2, base)
    m.rect(x - w2 + 2, roof_y + 8, x + w2 - 2, roof_y + 12)
    m.rect(x - w2 + 4, base - 30, x + w2 - 4, base - 27)
    m.rect(x - w2 - 6, base - 4, x + w2 + 6, base)
    ex = w2 + 22
    roofm.poly([(x - ex - 6, roof_y - 2), (x - ex + 6, roof_y + 3), (x + ex - 6, roof_y + 3), (x + ex + 6, roof_y - 2),
                (x + ex - 6, roof_y - 6), (x + w2 - 4, roof_y - 22), (x - w2 + 4, roof_y - 22), (x - ex + 6, roof_y - 6)])
    roofm.poly([(x - w2 - 2, roof_y - 22), (x + w2 + 2, roof_y - 22), (x + w2 - 10, roof_y - 40), (x - w2 + 10, roof_y - 40)])
    roofm.poly([(x - w2 + 6, roof_y - 40), (x - w2 + 2, roof_y - 46), (x + w2 - 2, roof_y - 46), (x + w2 - 6, roof_y - 40)])
    return [(x - w2 + 18, roof_y + 13), (x + w2 - 18, roof_y + 13), (x, roof_y + 13)]


def toro(m, x, base):
    m.rect(x - 6, base - 3, x + 6, base)
    m.rect(x - 2, base - 22, x + 2, base - 3)
    m.rect(x - 5, base - 25, x + 5, base - 22)
    m.rect(x - 4, base - 33, x + 4, base - 25)
    m.poly([(x - 9, base - 33), (x + 9, base - 33), (x + 4, base - 39), (x - 4, base - 39)])
    m.rect(x - 1, base - 42, x + 1, base - 39)
    return (x, base - 29)


def make_near():
    w = 1920
    L = new_layer(w)
    B = bayer(w)
    yy, xx = np.mgrid[0:H, 0:w]
    rr = np.random.default_rng(404)
    base = 304

    body = Mask(w)
    roof = Mask(w)
    lanterns = shrine_hall(body, roof, 1380, base, 92, 96, rr)
    lanterns += shrine_hall(body, roof, 520, base + 2, 50, 74, rr)
    toros = [toro(body, x, base) for x in (180, 300, 860, 1080, 1700)]
    # tall nobori poles
    poles = [(400, 150), (1180, 140), (1560, 160), (1840, 130)]
    for (x, ht) in poles:
        body.rect(x, base - ht, x + 1, base)
        body.rect(x, base - ht, x + 14, base - ht + 1)
    # low broken wall
    wall = Mask(w)
    for (x0, x1, top) in [(0, 140, 278), (640, 820, 282), (1880, 1990, 276)]:
        pts = [(x0, base)]
        for x in range(x0, x1 + 1, 6):
            pts.append((x, top + int(rr.integers(-3, 4))))
        pts.append((x1, base))
        body.poly(pts)
        wall.poly(pts)
    ground = yy >= base - 2
    mb = body.arr() | ground
    paint(L, mb, P["near"][1])
    paint(L, rim(mb, ((1, 0),)), P["near"][3])
    paint(L, rim(mb, ((0, -1),)), P["near"][4])
    # 拝殿纸门：内部透出的淡紫灵光（格子窗）
    for (hx, w2, hh, b0) in ((1380, 92, 96, base), (520, 50, 74, base + 2)):
        x0, x1 = hx - w2 + 9, hx + w2 - 9
        y0, y1 = b0 - hh + 14, b0 - 32
        sh = (xx >= x0) & (xx <= x1) & (yy >= y0) & (yy <= y1)
        paint(L, sh, "#2b2550")
        paint(L, sh & (yy > (y0 + y1) // 2), "#342c62")
        paint(L, sh & ((xx - x0) % 6 == 0), "#1a1734")
        paint(L, sh & ((yy - y0) % 8 == 0), "#1a1734")
        # 破洞的纸门
        tear = Mask(w).poly([(hx - 10, y0 + 10), (hx + 2, y0 + 6), (hx + 6, y0 + 18), (hx - 4, y0 + 24)]).arr()
        paint(L, sh & tear, P["near"][0])
        posts = (xx - (hx - w2 + 6)) % max(1, int((2 * w2 - 12) / 4))
        paint(L, sh & (posts <= 1), P["near"][1])
        # 回廊栏杆
        rail = (xx >= hx - w2 - 4) & (xx <= hx + w2 + 4)
        paint(L, rail & (yy == b0 - 14), P["near"][3])
        paint(L, rail & (yy == b0 - 13), P["near"][0])
        paint(L, rail & (yy > b0 - 14) & (yy < b0 - 4) & ((xx % 5) == 0), P["near"][2])
        # 台阶
        for s in range(3):
            st = (xx >= hx - 16 - s * 4) & (xx <= hx + 16 + s * 4) & (yy >= b0 - 10 + s * 3) & (yy < b0 - 7 + s * 3)
            paint(L, st, P["near"][2])
            paint(L, st & (yy == b0 - 10 + s * 3), P["near"][4])
    # wall bricks
    wallband = wall.arr() & (yy < base - 2) & ~rim(wall.arr(), ((0, -1),))
    paint(L, wallband & ((yy % 7 == 0) | (((xx + (yy // 7) * 5) % 14) == 0)), P["near"][0])

    rm = roof.arr()
    paint(L, rm, P["near"][2])
    paint(L, rm & (xx % 3 == 0), P["near"][1])
    paint(L, rm & ~shift(rm, 0, -2), P["near"][0])
    paint(L, rim(rm, ((0, -1),)), P["near"][5])
    paint(L, rim(rm, ((1, 0),)) & ~rim(rm, ((0, -1),)), P["near"][4])
    # broken roof hole on the big hall
    hole = Mask(w).poly([(1400, 168), (1420, 160), (1436, 178), (1426, 190), (1408, 186)]).arr() & rm
    paint(L, hole, P["near"][0])
    paint(L, hole & rim(~hole, ((0, 1),)) & rm, P["near"][4])

    # banners (cloth) with crow emblem
    for (x, ht) in poles:
        cm = Mask(w)
        top_y = base - ht + 2
        clen = 70
        pts = [(x + 2, top_y), (x + 14, top_y)]
        for k in range(6):
            pts.append((x + 14 - k * 2 + (k % 2) * 3, top_y + clen - (k % 2) * 7))
        pts.append((x + 2, top_y + clen - 4))
        cm.poly(pts)
        c = cm.arr()
        paint(L, c, "#1f1838")
        paint(L, c & (xx % 13 == (x + 6) % 13), "#18122c")
        paint(L, rim(c, ((1, 0),)), "#4a3d78")
        paint(L, rim(c, ((0, 1),)), "#2e2552")
        stamp(L, CROW_EMBLEM, x + 3, top_y + 14, {"#": "#9aa6c4"})

    # paper lanterns under eaves (violet spirit fire)
    for (lx, ly) in lanterns:
        lx, ly = int(lx), int(ly)
        for y in range(ly - 6, ly):
            px(L, lx, y, P["near"][0])
        glow(L, lx, ly + 6, 28, P["violet"][2], B, (0.07, 0.12, 0.2))
        lm = Mask(w).ell(lx, ly + 6, 5, 7).arr()
        paint(L, lm, P["violet"][2])
        paint(L, lm & (xx >= lx + 1), P["violet"][3])
        paint(L, lm & (xx == lx + 2) & (yy < ly + 8), P["violet"][4])
        paint(L, lm & ((yy == ly + 3) | (yy == ly + 9)), P["violet"][1])
        for dx in range(-3, 4):
            px(L, lx + dx, ly - 1, P["near"][0])
            px(L, lx + dx, ly + 13, P["near"][0])
        px(L, lx, ly + 14, P["violet"][1])
        px(L, lx, ly + 15, P["violet"][2])
    # stone lantern flames
    for i, (fx, fy) in enumerate(toros):
        warm = i in (1, 3)
        cols = P["amber"] if warm else P["violet"]
        glow(L, fx, fy, 22, cols[2], B, (0.08, 0.14, 0.22))
        paint(L, Mask(w).rect(fx - 2, fy - 3, fx + 2, fy + 3).arr(), cols[2])
        px(L, fx, fy, cols[4])
        px(L, fx, fy - 1, cols[3])
        px(L, fx, fy + 1, cols[3])
    return L


# ---------------------------------------------------------------- GROUND
def sword(L, x, y, ang_deg, length, rr, ribbon=True):
    """插在地里的剑（剑冢）。x,y = 入土点。"""
    a = math.radians(ang_deg)
    dx, dy = math.sin(a), -math.cos(a)
    pts = [(x + dx * k, y + dy * k) for k in range(length)]
    for k, (sx, sy) in enumerate(pts):
        sx, sy = int(round(sx)), int(round(sy))
        if k < length - 8:
            px(L, sx, sy, P["steel"][2])
            px(L, sx + 1, sy, P["steel"][3] if k % 5 else P["steel"][4])
            px(L, sx - 1, sy, P["steel"][1])
        elif k < length - 7:
            for g in range(-4, 5):
                px(L, sx + g, sy, P["stone"][2] if abs(g) < 4 else P["steel"][2])
            px(L, sx + 4, sy - 1, P["steel"][3])
        else:
            px(L, sx, sy, "#2a2034")
            px(L, sx + 1, sy, "#3a2e48")
    tx, ty = pts[-1]
    px(L, int(round(tx)), int(round(ty)) - 1, P["violet"][2])
    if ribbon:
        hx, hy = pts[length - 9]
        hx, hy = int(round(hx)), int(round(hy))
        for k in range(rr.integers(8, 14)):
            wv = int(round(math.sin(k * 0.8) * 1.5))
            px(L, hx + 2 + k, hy + 1 + k // 3 + wv, P["violet"][2] if k % 3 else P["violet"][3])
            if k % 4 == 1:
                px(L, hx + 2 + k, hy + 2 + k // 3 + wv, P["violet"][1])
    # dirt mound
    for g in range(-3, 4):
        px(L, x + g, y, P["stone"][4] if abs(g) < 2 else P["stone"][3])


def crow_statue(L, x, base, B):
    m = Mask(L.shape[1])
    m.rect(x - 9, base - 14, x + 9, base)
    m.rect(x - 11, base - 16, x + 11, base - 14)
    m.poly([(x - 6, base - 16), (x + 7, base - 16), (x + 9, base - 26), (x + 6, base - 34), (x + 11, base - 36),
            (x + 16, base - 34), (x + 10, base - 30), (x + 10, base - 40), (x + 4, base - 43), (x - 2, base - 38),
            (x - 8, base - 26)])
    m.poly([(x - 8, base - 26), (x - 2, base - 38), (x - 12, base - 46), (x - 16, base - 34)])
    mm = m.arr()
    paint(L, mm, P["stone"][2])
    paint(L, rim(mm, ((1, 0),)), P["stone"][6])
    paint(L, rim(mm, ((0, -1),)), P["stone"][7])
    paint(L, mm & ~shift(mm, -1, 0), P["stone"][1])
    px(L, x + 8, base - 37, P["violet"][4])
    px(L, x + 8, base - 36, P["violet"][2])
    yy = np.arange(H)[:, None]
    paint(L, mm & (yy == base - 8), P["stone"][1])


def spider_lily(L, x, y, rr, col_set):
    """白色彼岸花：细茎 + 放射状卷瓣（4~5px 宽）。y = 茎根部。"""
    stem = int(rr.integers(4, 9))
    for k in range(stem):
        px(L, x, y - k, P["moss"][2] if k < stem - 2 else P["moss"][3])
    hx, hy = x, y - stem
    c0, c1, c2 = col_set
    for dx, dy, c in [(0, 0, c2), (-1, 0, c1), (1, 0, c1), (0, -1, c1), (-2, -1, c0), (2, -1, c0), (-2, 1, c0),
                      (2, 1, c0), (-1, -2, c0), (1, -2, c0), (-3, -2, c0), (3, -2, c0)]:
        px(L, hx + dx, hy + dy, c)
    if rr.random() < 0.6:
        px(L, hx - 3, hy - 3, c1)
        px(L, hx + 3, hy - 3, c1)


def make_ground():
    w = 1920
    L = new_layer(w)
    B = bayer(w)
    yy, xx = np.mgrid[0:H, 0:w]
    rr = np.random.default_rng(777)
    G = GROUND_Y
    S = P["stone"]

    body = yy >= G
    paint(L, body, S[2])
    # 顶面（可行走面，略带透视的 6px 石板）
    top = (yy >= G) & (yy < G + 6)
    paint(L, top, S[4])
    paint(L, top & (yy >= G + 3), S[3])
    x = 0
    while x < w:
        sw = int(rr.integers(14, 30))
        paint(L, top & (xx == x % w) & (yy > G), S[1])
        paint(L, top & (xx == (x + 1) % w) & (yy > G), S[5])
        x += sw
    paint(L, yy == G, S[7])
    paint(L, (yy == G) & (B > 0.8), S[8])
    paint(L, yy == G + 6, S[0])
    # 正面大石块（倒角高光 + 阴影边）
    fy = G + 7
    row = 0
    while fy < H:
        bh = [16, 18, 20, 22][min(row, 3)]
        x = int(rr.integers(-30, 0)) + (row % 2) * 13
        while x < w:
            bw = int(rr.integers(30, 58))
            x0, x1 = x, x + bw
            col = S[2] if rr.random() < 0.7 else S[3]
            blk = Mask(w).rect(x0 + 1, fy + 1, x1 - 1, fy + bh - 1).arr()
            paint(L, blk, col)
            paint(L, blk & (yy == fy + 1), S[5])
            paint(L, blk & (yy == fy + 2), S[4])
            paint(L, blk & (xx == (x1 - 1) % w), S[4])
            paint(L, blk & (xx == (x0 + 1) % w), S[1])
            paint(L, blk & (yy == fy + bh - 1), S[1])
            # 缺角
            if rr.random() < 0.3:
                cc = Mask(w).poly([(x1 - 6, fy), (x1, fy), (x1, fy + 6)]).arr()
                paint(L, cc, S[0])
                paint(L, rim(cc, ((-1, 1),)) & ~cc & blk, S[5])
            # 稀疏碎屑
            for _ in range(int(rr.integers(1, 4))):
                cx, cy = int(rr.integers(x0 + 3, x1 - 3)), int(rr.integers(fy + 4, fy + bh - 3))
                px(L, cx, cy, S[1])
                px(L, cx + 1, cy - 1, S[4])
            # 裂缝
            if rr.random() < 0.35:
                cx, cy = int(rr.integers(x0 + 6, x1 - 6)), fy + 2
                for k in range(int(rr.integers(5, bh))):
                    cx += int(rr.choice([-1, 0, 0, 1]))
                    px(L, cx, cy + k, S[0])
                    px(L, cx + 1, cy + k, S[4])
            x = x1
        paint(L, yy == fy, S[0])
        fy += bh
        row += 1
    # 分档压暗：越往下越暗，平涂色带 + 窄抖动缝
    t = np.clip((yy - (G + 24)) / 40.0, 0, 1)
    shade = body & (yy > G + 7)
    blend(L, shade & (t > 0.0) & ((t > 0.35) | (B < t / 0.35)), S[0], 0.35)
    blend(L, shade & (t > 0.55) & ((t > 0.85) | (B < (t - 0.55) / 0.3)), S[0], 0.45)

    # 苔藓：顶边铺开 + 垂挂
    n = pnoise(xx[0].astype(float), w, 24, 3, 900)
    for x in range(w):
        if n[x] > 0.56:
            ln = int((n[x] - 0.56) * 70 * rr.uniform(0.2, 1.1)) + int(rr.integers(0, 3)) - 3
            px(L, x, G - 1, P["moss"][3])
            px(L, x, G, P["moss"][4] if rr.random() < 0.5 else P["moss"][3])
            for k in range(1, 6 + min(0, ln)):
                px(L, x, G + k, P["moss"][2])
            ln = max(0, ln)
            for k in range(6, 6 + ln):
                px(L, x, G + k, P["moss"][1] if k < 6 + ln - 1 else P["moss"][0])
            if rr.random() < 0.12:
                for k in range(6 + ln, 6 + ln + int(rr.integers(4, 14))):
                    px(L, x + (k // 7) % 2, G + k, P["moss"][1])
    # 草丛（成簇）
    for _ in range(170):
        cx = int(rr.integers(0, w))
        if n[cx] < 0.4 and rr.random() < 0.7:
            continue
        for j in range(int(rr.integers(3, 8))):
            x = cx + int(rr.integers(-4, 5))
            hgt = int(rr.integers(2, 7))
            lean = int(rr.choice([-1, 0, 1]))
            for k in range(hgt):
                c = P["moss"][4] if k == hgt - 1 else P["moss"][3] if k > hgt // 2 else P["moss"][2]
                px(L, x + (lean if k > hgt // 2 else 0), G - 1 - k, c)
    # 白彼岸花群（带一点紫）
    lily = ("#8a86b8", "#c9c6ea", "#f2f0ff")
    for cx in (60, 330, 600, 930, 1120, 1410, 1630, 1860):
        for _ in range(int(rr.integers(3, 7))):
            spider_lily(L, cx + int(rr.integers(-12, 13)), G - 1, rr, lily)
    # 小碎石
    for _ in range(50):
        x = int(rr.integers(0, w))
        px(L, x, G - 1, S[5])
        px(L, x + 1, G - 1, S[6])

    # 剑冢群
    graves = [(118, [(-14, 34), (6, 40), (24, 30)]), (760, [(-10, 38), (12, 44)]),
              (1260, [(-18, 30), (-2, 42), (16, 36), (30, 28)]), (1720, [(8, 40)])]
    for gx, swords in graves:
        glow(L, gx + len(swords) * 4, G - 6, 22, P["violet"][2], B, (0.06, 0.1, 0.16))
        for i, (ang, ln) in enumerate(swords):
            sword(L, gx + i * 9, G + 1, ang, ln, rr, ribbon=(i % 2 == 0))
    crow_statue(L, 1000, G, B)
    crow_statue(L, 1520, G, B)
    # 地上灵火小烛
    for x in (200, 840, 1060, 1340, 1580):
        glow(L, x, G - 4, 14, P["violet"][3], B, (0.08, 0.14, 0.24))
        px(L, x, G - 1, S[5])
        px(L, x, G - 2, P["paper"][1])
        px(L, x, G - 3, P["violet"][3])
        px(L, x, G - 4, P["violet"][4])
        px(L, x, G - 5, P["violet"][5])
    # 落羽
    for _ in range(36):
        x = int(rr.integers(0, w))
        c = P["paper"][2] if rr.random() < 0.4 else P["fg"][2]
        px(L, x, G - 1, c)
        px(L, x + 1, G - 1, c)
    return L


# ---------------------------------------------------------------- FOREGROUND
def make_fg():
    w = 1920
    L = new_layer(w)
    yy, xx = np.mgrid[0:H, 0:w]
    rr = np.random.default_rng(55)
    m = Mask(w)
    n = pnoise(xx[0].astype(float), w, 10, 3, 1200)
    for cx in range(0, w, 3):
        if n[cx] < 0.55:
            continue
        hgt = int(8 + (n[cx] - 0.55) * 130 + rr.integers(0, 10))
        lean = rr.uniform(-6, 6)
        m.poly([(cx - 2, H), (cx + 2, H), (cx + lean, H - hgt)])
    # 偶尔的高秆
    for cx in (330, 1100, 1650):
        for k in range(5):
            lean = rr.uniform(-14, 14)
            m.poly([(cx + k * 4 - 2, H), (cx + k * 4 + 2, H), (cx + k * 4 + lean, H - rr.integers(45, 70))])
    mm = m.arr()
    paint(L, mm, P["fg"][0])
    paint(L, rim(mm, ((1, 0),)), P["fg"][2])
    paint(L, rim(mm, ((0, -1),)), P["fg"][3])
    # 顶部垂下的枝条 + 纸垂 + 铃
    tm = Mask(w)
    tips = []
    br = np.random.default_rng(8)
    branch(tm, 860, -6, math.radians(-20), 60, 6, 4, br, tips)
    t = tm.arr()
    paint(L, t, P["fg"][0])
    paint(L, rim(t, ((0, -1),)), P["fg"][2])
    paint(L, rim(t, ((1, 0),)), P["fg"][3])
    for i, (x, y) in enumerate(tips[:6]):
        x, y = int(x), int(y)
        if not (0 <= y < 120):
            continue
        ln = 6 + i * 3
        for k in range(ln):
            px(L, x, y + k, P["fg"][2])
        if i % 2 == 0:
            stamp(L, SHIDE, x, y + ln, {"#": P["paper"][1]})
        else:
            bell = Mask(w).ell(x, y + ln + 2, 2, 2).arr()
            paint(L, bell, P["amber"][1])
            px(L, x + 1, y + ln + 1, P["amber"][3])
    return L


# ---------------------------------------------------------------- LIGHT SHAFTS
def make_light():
    w = 640
    L = new_layer(w)
    B = bayer(w)
    yy, xx = np.mgrid[0:H, 0:w]
    # 斜向下左的月光束：平涂半透明光带，边缘 1px 抖动
    u = (xx - 470) + (yy - 92) * 0.55 + (B - 0.5) * 1.5
    fade = np.clip((yy - 110) / 120.0, 0, 1) * np.clip((300 - yy) / 50.0, 0, 1)
    for (c, wd, a) in [(-70, 20, 0.10), (-160, 30, 0.08), (-262, 14, 0.07), (-340, 36, 0.05)]:
        band = (np.abs(u - c) < wd / 2) & (fade > 0)
        for lv in (0.25, 0.6):
            blend(L, band & (fade > lv), "#a9c6d0", a * 0.6)
    return L


LAYERS = [
    # name, factor, builder
    ("00_sky", 0.0, make_sky),
    ("01_far_mountains", 0.12, make_far),
    ("02_mid_forest_torii", 0.3, make_mid),
    ("03_light_shafts", 0.0, make_light),
    ("04_near_shrine", 0.6, make_near),
    ("05_ground_sword_graves", 1.0, make_ground),
    ("06_foreground", 1.3, make_fg),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, f, fn in LAYERS:
        L = fn()
        Image.fromarray(L, "RGBA").save(os.path.join(OUT, name + ".png"))
        print("wrote", name, L.shape[1], "x", L.shape[0], "parallax", f)


if __name__ == "__main__":
    main()
