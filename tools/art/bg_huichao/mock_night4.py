"""地图一「回潮之夜」整屏示意 v4：同一批素材，按实战定调图的构图和光重新摆、重新调。只用于检查。"""
from PIL import Image, ImageDraw, ImageEnhance, ImageChops, ImageOps, ImageStat, ImageFilter

SC = r"E:/00game/nightcrow-godot/docs/视觉设计/work/"
K = SC + "keyed/"
P = r"E:/00game/nightcrow-godot/"
L = P + "docs/视觉设计/layers/cloud_causeway/"
W, H, FLOOR = 1280, 720, 580
BACK, FRONT = 540, 630
NIGHT = (34, 42, 70)
HAZE = (70, 88, 124)
TEAL = (90, 210, 205)


def load(n):
    return Image.open(K + n + ".png").convert("RGBA")


def sh(im, h):
    return im.resize((max(1, round(im.size[0] * h / im.size[1])), h), Image.LANCZOS)


def sw(im, w):
    return im.resize((w, max(1, round(im.size[1] * w / im.size[0]))), Image.LANCZOS)


def grade(im, sat=1.0, bright=1.0, tint=None, amt=0.0):
    a = im.split()[3]
    rgb = ImageEnhance.Color(im.convert("RGB")).enhance(sat)
    rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    if tint:
        rgb = Image.blend(rgb, Image.new("RGB", im.size, tint), amt)
    o = rgb.convert("RGBA")
    o.putalpha(a)
    return o


def screen(base, layer, pos):
    full = Image.new("RGB", base.size, (0, 0, 0))
    full.paste(layer.convert("RGB"), pos, layer)
    return ImageChops.screen(base.convert("RGB"), full).convert("RGBA")


def add(base, layer, pos=(0, 0)):
    full = Image.new("RGB", base.size, (0, 0, 0))
    full.paste(layer.convert("RGB"), pos, layer)
    return ImageChops.add(base.convert("RGB"), full).convert("RGBA")


def fog(base, y0, y1, col, peak, falloff_up=True):
    """竖向雾：从 y0 到 y1 越来越浓（或反过来）。"""
    m = Image.new("RGBA", base.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(m)
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0)
        a = t if falloff_up else 1 - t
        d.line([(0, y), (base.size[0], y)], fill=col + (int(peak * a),))
    base.alpha_composite(m)


def glow(base, cx, cy, rx, ry, col, peak):
    m = Image.new("L", base.size, 0)
    ImageDraw.Draw(m).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=peak)
    m = m.filter(ImageFilter.GaussianBlur(max(rx, ry) // 2))
    layer = Image.new("RGBA", base.size, col + (0,))
    layer.putalpha(m)
    return add(base, layer)


# 1 天空 + 巨环
sky = Image.open(L + "01_sky_ring_from_keyart.png").convert("RGB")
sk = sh(sky, H)
base = sk.crop((sk.size[0] - W, 0, sk.size[0], H)).convert("RGBA")

# 2 远山：淡、低、退到雾里
mt = load("11_mountains_v2").crop((0, 262, 1916, 779))
mt = grade(sh(mt, 130), sat=0.6, bright=0.75, tint=HAZE, amt=0.6)
x = -150
while x < W:
    base.alpha_composite(mt, (x, 455 - mt.size[1]))
    x += mt.size[0] - 4

# 3 远方云海：亮一点，右边被青光照到
clouds = load("02_clouds_v1").crop((0, 180, 1916, 590))
cm = grade(sw(clouds, 1600), bright=0.6, tint=(80, 130, 160), amt=0.2)
base = screen(base, cm, (-160, 410))
base = glow(base, 1000, 470, 420, 90, (40, 120, 120), 70)   # 巨环下方的青光照亮云顶

# 4 中景：驿塔（左）、断渡槽（右中），都退进雾里
post = load("12_crow_post_v1").crop((221, 13, 1455, 941))
post = grade(sh(post, 330), sat=0.7, bright=0.75, tint=HAZE, amt=0.35)
base.alpha_composite(post, (-40, 520 - 330))
mb = load("04_mid_b_v1").crop((0, 220, 1672, 941))
mb = grade(sh(mb, 140), sat=0.5, bright=0.6, tint=HAZE, amt=0.55)
base.alpha_composite(mb, (560, 400))

# 5 层间的雾 + 战斗带背光（主角身后亮一档）
fog(base, 300, 560, HAZE, 95)
base = glow(base, 640, 470, 700, 110, (60, 75, 105), 80)

# 6 近处云（桥下）
cn = grade(sw(clouds, 1800), bright=0.35)
base = screen(base, cn, (-260, 640))

# 7 透视桥面 + 远边矮墙残块 + 水洼倒影
deck_src = sh(Image.open(L + "09_deck_top_v1.webp").convert("RGB"), 330)
src = Image.new("RGB", (W * 2, 330))
xx = 0
while xx < W * 2:
    src.paste(deck_src, (xx, 0))
    xx += deck_src.size[0]
deck = Image.new("RGBA", (W, FRONT - BACK))
puddle = Image.new("L", (W, FRONT - BACK))
for y in range(FRONT - BACK):
    t = y / (FRONT - BACK - 1)
    depth = 1 / (0.45 + 0.55 * t)
    sy = int((1 - (depth - 1) / (1 / 0.45 - 1)) * 329)
    sx = 0.72 + 0.28 * t
    row = src.crop((0, sy, W * 2, sy + 1)).resize((round(W * 2 * sx), 1), Image.LANCZOS)
    off = (row.size[0] - W) // 2
    row = row.crop((off, 0, off + W, 1))
    lum = row.convert("L")
    puddle.paste(lum.point(lambda v: 255 if v < 52 else 0), (0, y))   # 贴图里较暗的平滑块 = 水洼
    row = ImageEnhance.Brightness(row).enhance(0.8 + 0.45 * t)
    row = Image.blend(row, Image.new("RGB", row.size, NIGHT), 0.3 * (1 - t))
    deck.paste(row.convert("RGBA"), (0, y))
base.alpha_composite(deck, (0, BACK))
# 倒影：把桥面上方的画面上下翻转、压扁，只在水洼里显示
above = base.crop((0, BACK - (FRONT - BACK) * 2, W, BACK)).transpose(Image.FLIP_TOP_BOTTOM)
above = above.resize((W, FRONT - BACK))
above = ImageEnhance.Brightness(above.convert("RGB")).enhance(1.25).convert("RGBA")
pm = puddle.filter(ImageFilter.GaussianBlur(1.2)).point(lambda v: int(v * 0.75))
above.putalpha(pm)
base.alpha_composite(above, (0, BACK))
# 远边矮墙残块（参差的石块剪影）
pv = load("10_platforms_v2")
blk = grade(pv.crop((1388, 662, 1588, 855)), bright=0.55, tint=NIGHT, amt=0.25)
import random
random.seed(7)
x = -20
while x < W:
    hgt = random.choice([18, 24, 30, 0, 22])
    if hgt:
        b = sh(blk, hgt)
        base.alpha_composite(b, (x, BACK - hgt + 6))
        x += b.size[0] + random.randint(10, 60)
    else:
        x += random.randint(40, 90)

# 8 桥的立面
g = load("05_ground_v1").crop((499, 233, 1879, 660))
g = grade(g, sat=0.6, bright=0.4, tint=NIGHT, amt=0.25)
gs = g.resize((round(g.size[0] * 320 / 460), round(g.size[1] * 320 / 460)), Image.LANCZOS)
x = -150
while x < W:
    base.alpha_composite(gs, (x, FRONT - 2))
    x += gs.size[0]
ImageDraw.Draw(base).line([(0, FRONT), (W, FRONT)], fill=(130, 145, 170, 255), width=2)

# 9 平台 v2（更小、退到两边，中间留空）
night = dict(sat=0.7, bright=0.8, tint=NIGHT, amt=0.15)
k1 = 0.24
segs = [grade(pv.crop(b), **night) for b in [(42, 98, 501, 280), (1076, 98, 1625, 280)]]
segs = [sh(s, round(s.size[1] * k1)) for s in segs]
arch = grade(pv.crop((37, 318, 460, 790)), **night)
arch = sh(arch, 140)
base.alpha_composite(arch, (95, 470 + 4))
x = 40
for s in segs:
    base.alpha_composite(s, (x, 470 - round(30 * k1)))
    x += s.size[0] - 3
k2 = 0.3
woods = [grade(pv.crop(b), **night) for b in [(490, 337, 777, 422), (1276, 337, 1646, 412)]]
woods = [sh(w_, round(w_.size[1] * k2)) for w_ in woods]
col = grade(pv.crop((590, 498, 732, 878)), **night)
col = sh(col, FLOOR - 360 - 14)
wx = 760
ww = sum(w_.size[0] - 2 for w_ in woods)
for cxp in (wx + 18, wx + ww - 18 - col.size[0]):
    base.alpha_composite(col, (cxp, 360 + 6))
x = wx
for w_ in woods:
    base.alpha_composite(w_, (x, 360 - round(14 * k2)))
    x += w_.size[0] - 2
tower = grade(pv.crop((920, 460, 1290, 905)), **night)
tower = sh(tower, FLOOR - 250 + 30)
base.alpha_composite(tower, (W - tower.size[0] + 70, 250 - 30))
# 平台脚下的接触阴影（贴在桥面上）
for (cx_, wdt) in [(200, 160), (wx + 30, 60), (wx + ww - 30, 60), (W - 90, 240)]:
    s_ = Image.new("RGBA", (wdt, 14), (0, 0, 0, 0))
    ImageDraw.Draw(s_).ellipse([0, 0, wdt - 1, 13], fill=(4, 6, 14, 130))
    base.alpha_composite(s_.filter(ImageFilter.GaussianBlur(3)), (cx_ - wdt // 2, FLOOR - 4))

# 10 主角（加一圈冷色轮廓光，模拟游戏里的角色光）
ch = Image.open(P + "assets/image/ai-hd-20261020/idle/pose_001.png").convert("RGBA")
ch = sh(ch.crop(ch.getbbox()), 98)
a = ch.split()[3]
rim_a = ImageChops.subtract(a.filter(ImageFilter.MaxFilter(5)), a)
rim = Image.new("RGBA", ch.size, (150, 215, 225, 0))
rim.putalpha(rim_a.point(lambda v: int(v * 0.8)))
shadow = Image.new("RGBA", (70, 12), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse([0, 0, 69, 11], fill=(4, 5, 12, 150))
for (cx_, fy) in [(560, FLOOR), (200, 470), (830, 360)]:
    base.alpha_composite(shadow, (cx_ + 12, fy - 6))
    base.alpha_composite(rim, (cx_, fy - 98))
    base.alpha_composite(ch, (cx_, fy - 98))

# 11 前景：两个下角大块暗剪影 + 左上角垂藤
fg = load("08_foreground_v1")
dark = dict(bright=0.35, tint=(6, 8, 16), amt=0.5)
bal = grade(sh(fg.crop((23, 565, 565, 897)), 230), **dark)
base.alpha_composite(bal, (-90, H - 200))
bush = grade(sh(fg.crop((1160, 650, 1653, 897)), 200), **dark)
base.alpha_composite(bush, (W - bush.size[0] + 60, H - 170))
ivy = grade(sh(fg.crop((1215, 0, 1450, 420)), 200), **dark)
base.alpha_composite(ivy, (-30, -10))

# 12 辉光（只让最亮的东西发光）
bright = base.convert("RGB").point(lambda v: max(0, v - 150) * 2)
base = add(base, bright.filter(ImageFilter.GaussianBlur(10)).convert("RGBA"))

out = base.convert("RGB")
out.save(SC + "mock_night4.png")
key = Image.open(P + "docs/视觉设计/keyart/gameplay_frame_v2.webp").convert("RGB").resize((W, H))
cmp_ = Image.new("RGB", (W, H * 2))
cmp_.paste(key, (0, 0))
cmp_.paste(out, (0, H))
cmp_.resize((W * 3 // 4, H * 3 // 2)).save(SC + "cmp_key_mock4.png")
gray = ImageOps.grayscale(out)
print("combat band", round(ImageStat.Stat(gray.crop((0, 250, W, BACK))).mean[0] / 255, 2),
      "whole", round(ImageStat.Stat(gray).mean[0] / 255, 2))
