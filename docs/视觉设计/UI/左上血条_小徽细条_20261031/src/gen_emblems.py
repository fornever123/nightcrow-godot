"""小徽细条 · 徽记候选（UI 线 10-31）。骨架不动（gen.py 的血条 + 绝影格），只换最左边的徽记。
用法：python gen_emblems.py → ../徽记候选_*.png
"""
import math

import gen

EXTRA = """
<linearGradient id="ag2" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#f7f9fd"/><stop offset=".35" stop-color="#b9bfca"/>
  <stop offset=".6" stop-color="#5e6470"/><stop offset="1" stop-color="#a3a9b5"/></linearGradient>
<linearGradient id="ink" x1="0" y1="0" x2="1" y2="1">
  <stop offset="0" stop-color="#1a1c26"/><stop offset="1" stop-color="#07080d"/></linearGradient>
<radialGradient id="iris" cx=".5" cy=".5" r=".5">
  <stop offset="0" stop-color="#f4ecff"/><stop offset=".45" stop-color="#a678ff"/><stop offset=".85" stop-color="#5a2cc0"/>
  <stop offset="1" stop-color="#2a0f60"/></radialGradient>
<filter id="glow2" x="-80%" y="-80%" width="260%" height="260%"><feGaussianBlur stdDeviation="2.4" result="g"/>
  <feMerge><feMergeNode in="g"/><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
"""
gen.DEFS = gen.DEFS.replace("</defs>", EXTRA + "</defs>")

PURPLE_HALO = '<circle cx="{x}" cy="{y}" r="{r}" fill="#8a4dff" opacity=".45" filter="url(#soft)"/>'


def g(cx, cy, body):
    return f'<g transform="translate({cx} {cy})" filter="url(#sh)">{body}</g>'


# ---------- 1 尖拱之眼（重画：真正的尖拱 + 尖饰 + 羽睫） ----------
def e_arch(cx, cy, state):
    def vesica(h, w):
        d = (h * h - w * w) / (2 * w)
        r = w + d
        return f"M0 {-h} A{r:.2f} {r:.2f} 0 0 1 0 {h} A{r:.2f} {r:.2f} 0 0 1 0 {-h} Z"
    full = state == "full"
    b = ""
    if full:
        b += PURPLE_HALO.format(x=0, y=0, r=16)
    b += f'<path d="{vesica(27, 17)}" fill="url(#ink)" stroke="url(#ag2)" stroke-width="2.4"/>'
    b += f'<path d="{vesica(22.5, 13.2)}" fill="none" stroke="#c7ccd6" stroke-width=".55" opacity=".8"/>'
    # 顶 / 底尖饰：小鸦羽
    for s in (-1, 1):
        b += (f'<path d="M0 {s*26} C2.2 {s*29} 1.6 {s*33} 0 {s*38} C-1.6 {s*33} -2.2 {s*29} 0 {s*26} Z" fill="url(#ag2)"/>'
              f'<path d="M0 {s*27} L0 {s*36}" stroke="#30333c" stroke-width=".45"/>')
    # 眼
    if full:
        b += ('<path d="M-11 0 Q0 -9.5 11 0 Q0 9.5 -11 0 Z" fill="#12061f"/>'
              '<circle cx="0" cy="0" r="6.2" fill="url(#iris)"/>'
              '<path d="M0 -5.6 Q1.5 0 0 5.6 Q-1.5 0 0 -5.6 Z" fill="#06010c"/>'
              '<circle cx="2.4" cy="-2.4" r=".9" fill="#fff"/>'
              '<path d="M-11 0 Q0 -9.5 11 0" fill="none" stroke="#e9ecf4" stroke-width="1.3"/>'
              '<path d="M-11 0 Q0 9.5 11 0" fill="none" stroke="#9aa1ae" stroke-width=".7"/>')
    else:
        glow = "#ff5f78" if state == "low" else "#a774ff"
        b += (f'<path d="M-11 .5 Q0 4 11 .5" fill="none" stroke="{glow}" stroke-width="1.4" filter="url(#glow2)"/>'
              '<path d="M-11.5 .5 Q0 -6.5 11.5 .5" fill="none" stroke="#e9ecf4" stroke-width="1.5"/>')
        for i, x in enumerate([-8, -4, 0, 4, 8]):  # 羽睫
            ln = 3.6 if i in (1, 2, 3) else 2.8
            b += f'<path d="M{x} 2.6 q{x*.08:.2f} {ln*.5} {x*.18:.2f} {ln}" stroke="#c9ced8" stroke-width=".7" fill="none"/>'
    return g(cx, cy, b)


# ---------- 2 鸦首印（圆印 + 纹章式鸦首，喙破印而出） ----------
HEAD = ("M70 22 C62 12 46 8 32 12 C22 15 14 22 10 30 L-6 34 L12 40 L-2 50 L14 52 L4 66 L20 64 "
        "C22 72 24 80 22 90 L62 90 L60 82 L69 79 L62 74 L73 69 L66 64 L77 57 C77 52 78 48 80 46 L76 30 Z")
BEAK = "M68 22 C84 21 104 25 122 36 C125 38 125 41 121 41.5 C108 40.5 92 41 80 43 C74 38 70 30 68 22 Z M80 44 C94 43 108 43 117 43 C108 47 94 49.5 82 49.5 Z"


def e_crow(cx, cy, state):
    full = state == "full"
    b = ""
    b += '<circle cx="0" cy="0" r="25" fill="url(#ink)" stroke="url(#ag2)" stroke-width="2.2"/>'
    b += '<circle cx="0" cy="0" r="21" fill="none" stroke="#c7ccd6" stroke-width=".5" opacity=".75"/>'
    b += "".join(f'<path d="M{21*math.cos(a):.2f} {21*math.sin(a):.2f} L{24*math.cos(a):.2f} {24*math.sin(a):.2f}" stroke="#c7ccd6" stroke-width=".5"/>'
                 for a in [i * math.pi / 12 for i in range(24)] if not (-0.7 < a < 0.2 or a > 2 * math.pi - 0.7))
    k = .36
    head = f'<g transform="translate(-19 -17) scale({k})"><path d="{HEAD}" fill="url(#ag2)"/><path d="{BEAK}" fill="url(#ag)"/>'
    head += '<path d="M42 27.5 L73 23.2 L71.5 27.4 L45 30.6 Z" fill="#1a1c24"/>'
    eye_c = "#c49bff" if full else ("#ff6a80" if state == "low" else "#7c4fd8")
    head += f'<circle cx="60" cy="31" r="{5 if full else 3.6}" fill="{eye_c}" {"filter=\"url(#glow2)\"" if full else ""}/>'
    head += '</g>'
    return g(cx, cy, b + head)


# ---------- 3 鸦羽容器（一根羽毛，从羽根往羽尖灌紫） ----------
def e_feather(cx, cy, state, ult=.62):
    full = state == "full"
    L = 62
    d = (f"M0 0 C{L*.15:.1f} -6 {L*.5:.1f} -9 {L*.8:.1f} -7 C{L*.92:.1f} -6 {L*.98:.1f} -4 {L} -5 "
         f"C{L*.95:.1f} 0 {L*.85:.1f} 6.5 {L*.6:.1f} 8 C{L*.35:.1f} 9 {L*.12:.1f} 6.5 0 0 Z")
    f = 1.0 if full else ult
    clip = gen_uid("fc")
    b = f'<g transform="translate(-24 22) rotate(-50)">'
    if full:
        b += f'<path d="{d}" fill="#8a4dff" opacity=".6" filter="url(#soft)"/>'
    b += f'<clipPath id="{clip}"><rect x="-2" y="-12" width="{L * f + 2:.1f}" height="24"/></clipPath>'
    b += f'<path d="{d}" fill="url(#ink)" stroke="url(#ag2)" stroke-width="1.5"/>'
    fillc = "#ff5f78" if state == "low" else "url(#ult)"
    b += f'<path d="{d}" fill="{fillc}" clip-path="url(#{clip})" opacity=".92"/>'
    b += f'<path d="M{L*.55:.1f} -7.6 L{L*.5:.1f} -2.6 M{L*.33:.1f} 8.4 L{L*.28:.1f} 3.2" stroke="#05060a" stroke-width="1.4"/>'
    b += f'<path d="M-7 0 C{L*.4:.1f} -.8 {L*.8:.1f} -2 {L*.97:.1f} -4.6" stroke="#f1f3f8" stroke-width="1.2" fill="none"/>'
    b += '</g>'
    return g(cx, cy, b)


_n = [0]


def gen_uid(p):
    _n[0] += 1
    return f"{p}{_n[0]}"


# ---------- 4 十字护手（她的刀的护手，中间紫菱） ----------
def e_guard(cx, cy, state):
    full = state == "full"
    b = ""
    if full:
        b += PURPLE_HALO.format(x=0, y=0, r=12)
    arm = "M0 -3.4 L19 -3.4 L27 0 L19 3.4 L0 3.4 Z"
    b += f'<path d="{arm}" fill="url(#ag2)"/><path d="{arm}" fill="url(#ag2)" transform="scale(-1 1)"/>'
    b += '<path d="M-3 0 L-3 -16 L0 -22 L3 -16 L3 0 Z" fill="url(#ag)"/>'           # 柄
    b += '<path d="M-2.6 -22 L0 -27 L2.6 -22 Z" fill="url(#ag2)"/>'                  # 柄头
    b += '<path d="M-3.6 4 L3.6 4 L2.6 30 L0 36 L-2.6 30 Z" fill="url(#ag2)"/>'      # 刀身（往下）
    b += '<path d="M0 6 L0 33" stroke="#fff" stroke-width=".6" opacity=".7"/>'
    b += "".join(f'<path d="M{s*9} -3.4 l{s*3} -4 l{s*3} 4" fill="url(#ag2)"/>' for s in (-1, 1))
    gem = "#ff5f78" if state == "low" else ("#c8a2ff" if full else "#6b3fc8")
    b += (f'<path d="M0 -6.5 L4.6 0 L0 6.5 L-4.6 0 Z" fill="{gem}" stroke="#eef0f6" stroke-width=".8" {"filter=\"url(#glow2)\"" if full else ""}/>'
          '<path d="M0 -6.5 L1.4 0 L0 6.5" fill="#fff" opacity=".25"/>')
    return g(cx, cy, b)


# ---------- 5 一闪（一圈飞白墨环，被一刀斜斩开） ----------
def e_issen(cx, cy, state):
    full = state == "full"
    b = ""
    ring = ("M24 0 A24 24 0 1 1 -24 0 A24 24 0 1 1 24 0 Z M21.6 -1 A20 20 0 1 0 -18.4 -1 A20 20 0 1 0 21.6 -1 Z")
    mid = gen_uid("cut")
    b += (f'<mask id="{mid}"><rect x="-40" y="-40" width="80" height="80" fill="#fff"/>'
          '<path d="M-40 34 L30 -36 L36 -30 L-34 40 Z" fill="#000"/></mask>')
    b += f'<g mask="url(#{mid})"><path d="{ring}" fill-rule="evenodd" fill="url(#ag2)"/>'
    # 飞白：环上几道黑色细丝
    b += "".join(f'<path d="M{24*math.cos(a):.1f} {24*math.sin(a):.1f} L{19*math.cos(a+.08):.1f} {19*math.sin(a+.08):.1f}" stroke="#0a0b10" stroke-width=".7"/>'
                 for a in [1.9, 2.25, 2.4, 3.6, 4.4, 5.1])
    b += '</g>'
    b += '<circle cx="0" cy="0" r="17" fill="url(#ink)" opacity=".85"/>'
    slash = "#d6bcff" if full else ("#ff7a8e" if state == "low" else "#f4f6fb")
    b += (f'<path d="M-30 30 L31 -31 L32.5 -29.5 L-28.5 31.5 Z" fill="{slash}" {"filter=\"url(#glow2)\"" if full else ""}/>'
          f'<path d="M-30 30 L31 -31" stroke="#fff" stroke-width=".4"/>')
    if full:
        b += '<circle cx="0" cy="0" r="3" fill="#e8dbff" filter="url(#glow2)"/>'
    return g(cx, cy, b)


CANDS = [("① 尖拱之眼", e_arch), ("② 鸦首印", e_crow), ("③ 鸦羽", e_feather), ("④ 十字护手", e_guard), ("⑤ 一闪", e_issen)]

if __name__ == "__main__":
    bg = f'<image href="{gen.BG}" x="0" y="0" width="1280" height="720"/>'
    cards = ""
    W, H = 920, 160
    for i, (name, fn) in enumerate(CANDS):
        for j, (st, kw) in enumerate([("charge", dict(hp=.75, ult=.62)), ("full", dict(hp=.75, ult=1))]):
            gen.emblem = lambda cx, cy, s, fn=fn: fn(cx, cy, s)
            x, y = j * W, i * H
            cards += (f'<svg x="{x}" y="{y}" width="{W}" height="{H}" viewBox="0 0 460 80">{bg}{gen.hud(state=st, **kw)}</svg>')
        cards += f'<text x="{2*W - 10}" y="{i*H + H - 10}" text-anchor="end" font-family="Noto Serif SC" font-size="22" fill="#e2e6ef">{name}</text>'
    gen.shoot(gen.page(cards, 2 * W, len(CANDS) * H), "徽记候选_放大", 2 * W, len(CANDS) * H, 1)
    # 原尺寸：五个徽记各自放进实机画面左上，竖排裁出来
    strips = ""
    for i, (name, fn) in enumerate(CANDS):
        gen.emblem = lambda cx, cy, s, fn=fn: fn(cx, cy, s)
        strips += (f'<svg x="0" y="{i*90}" width="470" height="90" viewBox="0 0 470 90">{bg}{gen.hud(hp=.75, ult=.62)}</svg>'
                   f'<text x="462" y="{i*90 + 80}" text-anchor="end" font-family="Noto Serif SC" font-size="11" fill="#e2e6ef">{name}</text>')
    gen.shoot(gen.page(strips, 470, 450), "徽记候选_原尺寸", 470, 450, 1)
