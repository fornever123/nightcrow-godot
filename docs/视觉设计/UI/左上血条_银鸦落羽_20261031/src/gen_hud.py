"""银鸦落羽 HUD 精绘样图生成器（UI 线 10-31）。

画法：SVG 手写几何 + 程序生成雕刻纹，金属感用 feSpecularLighting 浮雕。
输出 HTML（底图 = 现状截图 00_无UI底图），用 Edge 无头截图成 PNG。
用法：python gen_hud.py   → 在 ../ 下写 银鸦落羽_*.png
"""
import math
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent
BG = (HERE.parents[1] / "现状截图_20261031" / "00_无UI底图.png").as_uri()
_UID = [0]


def uid(base):
    _UID[0] += 1
    return f"{base}{_UID[0]}"


EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

# ---------- 公共 defs ----------
DEFS = """
<defs>
  <linearGradient id="silver" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#f4f6fb"/><stop offset=".16" stop-color="#ccd2dc"/>
    <stop offset=".42" stop-color="#7b818e"/><stop offset=".56" stop-color="#3c404b"/>
    <stop offset=".78" stop-color="#8d94a2"/><stop offset="1" stop-color="#dfe3ea"/>
  </linearGradient>
  <linearGradient id="silverH" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#e9edf5"/><stop offset=".35" stop-color="#9aa1ae"/>
    <stop offset=".6" stop-color="#4a4f5a"/><stop offset=".85" stop-color="#a7adba"/>
    <stop offset="1" stop-color="#5d626d"/>
  </linearGradient>
  <linearGradient id="oxSilver" x1="0" y1="0" x2=".35" y2="1">
    <stop offset="0" stop-color="#d9dee8"/><stop offset=".18" stop-color="#7c828e"/>
    <stop offset=".45" stop-color="#2c2f37"/><stop offset=".75" stop-color="#1b1d23"/>
    <stop offset="1" stop-color="#5a5f6b"/>
  </linearGradient>
  <linearGradient id="oxDark" x1="0" y1="0" x2=".4" y2="1">
    <stop offset="0" stop-color="#6c7280"/><stop offset=".3" stop-color="#2e313a"/>
    <stop offset=".7" stop-color="#16181d"/><stop offset="1" stop-color="#3a3e48"/>
  </linearGradient>
  <linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#2b3350"/><stop offset=".45" stop-color="#101219"/>
    <stop offset="1" stop-color="#1c1730"/>
  </linearGradient>
  <linearGradient id="beak" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#e6e9f0"/><stop offset=".3" stop-color="#8e94a1"/>
    <stop offset=".7" stop-color="#2f323b"/><stop offset="1" stop-color="#6b707c"/>
  </linearGradient>
  <linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#cfd8f0" stop-opacity=".30"/><stop offset=".3" stop-color="#8090b8" stop-opacity=".08"/>
    <stop offset=".75" stop-color="#101626" stop-opacity=".35"/><stop offset="1" stop-color="#aab6d8" stop-opacity=".28"/>
  </linearGradient>
  <linearGradient id="liquid" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#b8344a"/><stop offset=".25" stop-color="#8a1a2c"/>
    <stop offset=".7" stop-color="#4e0a17"/><stop offset="1" stop-color="#2a0510"/>
  </linearGradient>
  <linearGradient id="liquidLow" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#e0485e"/><stop offset=".25" stop-color="#a81f34"/>
    <stop offset=".7" stop-color="#5a0b19"/><stop offset="1" stop-color="#300511"/>
  </linearGradient>
  <linearGradient id="back" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#05070d" stop-opacity=".82"/><stop offset=".55" stop-color="#05070d" stop-opacity=".55"/>
    <stop offset="1" stop-color="#05070d" stop-opacity="0"/>
  </linearGradient>
  <linearGradient id="backV" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".7" stop-color="#fff" stop-opacity=".9"/>
    <stop offset="1" stop-color="#fff" stop-opacity="0"/>
  </linearGradient>
  <mask id="backMask"><rect x="0" y="0" width="560" height="150" fill="url(#backV)"/></mask>
  <radialGradient id="eyeGlow" cx=".5" cy=".5" r=".5">
    <stop offset="0" stop-color="#e6d4ff"/><stop offset=".35" stop-color="#9b62ff"/>
    <stop offset="1" stop-color="#2a0f55" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="eyeDim" cx=".5" cy=".5" r=".5">
    <stop offset="0" stop-color="#8a5ae0" stop-opacity=".9"/><stop offset=".5" stop-color="#4a2490" stop-opacity=".5"/>
    <stop offset="1" stop-color="#120820" stop-opacity="0"/>
  </radialGradient>
  <filter id="metal" x="-15%" y="-15%" width="130%" height="130%" color-interpolation-filters="sRGB">
    <feGaussianBlur in="SourceAlpha" stdDeviation="1.4" result="b"/>
    <feSpecularLighting in="b" surfaceScale="3.6" specularConstant="1.05" specularExponent="20"
        lighting-color="#e6ecff" result="spec"><feDistantLight azimuth="225" elevation="38"/></feSpecularLighting>
    <feComposite in="spec" in2="SourceAlpha" operator="in" result="specIn"/>
    <feComposite in="SourceGraphic" in2="specIn" operator="arithmetic" k1="0" k2="1" k3=".8" k4="0" result="lit"/>
    <feDropShadow in="lit" dx="0" dy="2" stdDeviation="1.6" flood-color="#000" flood-opacity=".75"/>
  </filter>
  <filter id="shadow" x="-10%" y="-20%" width="120%" height="140%">
    <feDropShadow dx="0" dy="1.5" stdDeviation="1.4" flood-color="#000" flood-opacity=".8"/>
  </filter>
  <filter id="glow" x="-40%" y="-80%" width="180%" height="260%">
    <feGaussianBlur in="SourceGraphic" stdDeviation="3.2" result="g"/>
    <feMerge><feMergeNode in="g"/><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="softglow" x="-60%" y="-60%" width="220%" height="220%">
    <feGaussianBlur stdDeviation="4"/>
  </filter>
</defs>
"""

# ---------- 鸦首（局部坐标，喙朝右；纹章式：后颈三根尖羽、喉下尖羽、压眉） ----------
HEAD = ("M70 22 C62 12 46 8 32 12 C22 15 14 22 10 30 "
        "L-6 34 L12 40 L-2 50 L14 52 L4 66 L20 64 "
        "C22 72 24 80 22 90 L62 90 "
        "L60 82 L69 79 L62 74 L73 69 L66 64 L77 57 "
        "C77 52 78 48 80 46 L76 30 Z")
BEAK_UP = ("M68 22 C84 21 104 25 122 36 C125 38 125 41 121 41.5 "
           "C108 40.5 92 41 80 43 C74 38 70 30 68 22 Z")
BEAK_LO = "M80 44 C94 43 108 43 117 43 C108 47 94 49.5 82 49.5 Z"
EYE = "M50.5 31.6 C55 26.8 62.5 26.2 69 29.4 C64.5 34.2 56 35 50.5 31.6 Z"
BROW = "M42 27.5 L73 23.2 L71.5 27.4 L45 30.6 Z"


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def engraving():
    """羽流刻线：从喙根往后脑、后颈尖羽方向梳过去。暗刻线 + 上沿一道亮线。"""
    dark, lite = [], []
    n = 17
    for k in range(n):
        u = k / (n - 1)
        s = lerp((71, 20), (79, 50), u)
        e = lerp((6, 30), (16, 88), u)
        e = (e[0] - 6 * math.sin(u * math.pi * 3) ** 2, e[1])
        c1 = (s[0] - 18, s[1] - 7 * (1 - u) + 2 * u)
        c2 = (e[0] + 22, e[1] - 10 * (1 - u) - 2)
        d = f"M{s[0]:.1f} {s[1]:.1f} C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {e[0]:.1f} {e[1]:.1f}"
        dark.append(d)
        lite.append(f"M{s[0]:.1f} {s[1] - .8:.1f} C{c1[0]:.1f} {c1[1] - .8:.1f} {c2[0]:.1f} {c2[1] - .8:.1f} {e[0]:.1f} {e[1] - .8:.1f}")
    # 尖羽中脊
    for a, b in [((12, 36), (-4, 34)), ((14, 47), (0, 50)), ((18, 61), (6, 65)),
                 ((63, 79), (68, 79)), ((64, 72), (71, 69)), ((68, 62), (75, 57))]:
        lite.append(f"M{a[0]} {a[1]} L{b[0]} {b[1]}")
    return ("".join(f'<path d="{d}"/>' for d in dark), "".join(f'<path d="{d}"/>' for d in lite))


def crow_head(eye_state: str) -> str:
    dark, lite = engraving()
    if eye_state == "open":
        eye = (f'<ellipse cx="60" cy="30.5" rx="15" ry="9" fill="#8f55ff" opacity=".6" filter="url(#softglow)"/>'
               f'<path d="{EYE}" fill="#1a0b33"/><path d="{EYE}" fill="url(#eyeGlow)"/>'
               '<path d="M60 26.6 C61.2 28.8 61.2 32 60 33.6 C58.8 32 58.8 28.8 60 26.6 Z" fill="#0a0414"/>'
               '<circle cx="62.6" cy="29.2" r=".8" fill="#fff" opacity=".9"/>')
    else:
        eye = (f'<path d="{EYE}" fill="#07060c"/>'
               f'<ellipse cx="60" cy="31" rx="6.5" ry="2.6" fill="url(#eyeDim)"/>')
    return f"""
  <g filter="url(#metal)">
    <path d="{HEAD}" fill="url(#silver)"/>
    <path d="{HEAD}" fill="url(#oxDark)" transform="translate(1.8 2.2)" clip-path="url(#headClip)"/>
    <g clip-path="url(#headClip)" fill="none" stroke-linecap="round">
      <g stroke="#050608" stroke-width=".9" opacity=".8">{dark}</g>
      <g stroke="#e3e8f3" stroke-width=".6" opacity=".55">{lite}</g>
    </g>
    <path d="{BEAK_LO}" fill="url(#beak)"/>
    <path d="{BEAK_UP}" fill="url(#beak)"/>
    <path d="{BROW}" fill="url(#silver)"/>
  </g>
  <path d="M70 22.6 C86 22 104 26 120 36.4" fill="none" stroke="#fbfcff" stroke-width="1" opacity=".8"/>
  <path d="M80 43.5 C94 42.6 108 42.4 119 42.3" fill="none" stroke="#06070a" stroke-width="1.1"/>
  <g stroke="#0d0e12" stroke-width=".7" fill="none" opacity=".85">
    <path d="M71 26 L84 29.5"/><path d="M72 29.5 L86 32"/><path d="M73.5 33 L85 34.8"/>
  </g>
  <path d="M86 33 C88.5 32.2 91 32.4 93 33.2" stroke="#050608" stroke-width="1.2" fill="none"/>
  <path d="M43 27.6 L72.6 23.5" stroke="#ffffff" stroke-width=".8" opacity=".7"/>
  {eye}
  <path d="{EYE}" fill="none" stroke="#aeb5c4" stroke-width=".7" opacity=".6"/>
"""


# ---------- 羽毛（局部坐标，羽根在 0,0，指向 +x，羽尖微微上翘） ----------
def feather(L: float, fill: float, idx: int, lit_all: bool) -> str:
    """fill: 0..1 从羽根往羽尖填紫。"""
    d = (f"M0 0 C{L*.15:.1f} -4.6 {L*.5:.1f} -6.4 {L*.8:.1f} -5.2 C{L*.92:.1f} -4.4 {L*.98:.1f} -3.4 {L:.1f} -3.8 "
         f"C{L*.95:.1f} -.2 {L*.85:.1f} 4.6 {L*.6:.1f} 5.9 C{L*.35:.1f} 6.7 {L*.12:.1f} 4.9 0 0 Z")
    if fill <= 0:
        grad, paint = "", "url(#sheen)"
    else:
        gid = uid("fg")
        f = min(fill, 1.0)
        tail = (f'<stop offset="{f:.3f}" stop-color="#e6d6ff"/><stop offset="{min(1, f + .004):.3f}" stop-color="#14131c"/>'
                if f < 1 else '<stop offset="1" stop-color="#40217f"/>')
        grad = (f'<linearGradient id="{gid}" x1="0" y1="0" x2="1" y2="0">'
                f'<stop offset="0" stop-color="#d8c2ff"/><stop offset="{f*.3:.3f}" stop-color="#9a6af0"/>'
                f'<stop offset="{f*.9:.3f}" stop-color="#5b33b4"/>{tail}</linearGradient>')
        paint = f"url(#{gid})"
    barbs = []
    t = 8.0
    while t < L - 6:
        k = math.sin(math.pi * min(1, t / L) ** .75)
        barbs.append(f"M{t:.1f} -.4 L{t + 6:.1f} {-5.4*k:.1f}")
        barbs.append(f"M{t:.1f} .4 L{t + 6.5:.1f} {5.6*k:.1f}")
        t += 4.2
    notch = (f'<path d="M{L*.57:.1f} -5.6 L{L*.52:.1f} -2.2" stroke="#05060a" stroke-width="1.2"/>'
             f'<path d="M{L*.36:.1f} 6.4 L{L*.31:.1f} 2.6" stroke="#05060a" stroke-width="1.2"/>')
    glow = f'<path d="{d}" fill="#8b52ff" opacity="{.6 if lit_all else .3}" filter="url(#softglow)"/>' if fill > 0 else ""
    edge = "#d2c0ff" if fill >= 1 and lit_all else "#9aa2b4"
    return f"""{grad}{glow}
    <path d="{d}" fill="{paint}" stroke="{edge}" stroke-width=".75" filter="url(#shadow)"/>
    <g stroke="{'#2a1650' if fill > 0 else '#3a4260'}" stroke-width=".5" opacity=".45" fill="none">{''.join(f'<path d="{b}"/>' for b in barbs)}</g>
    {notch}
    <path d="M-2 0 C{L*.4:.1f} -.6 {L*.8:.1f} -1.6 {L*.97:.1f} -3.4" stroke="#e9ecf4" stroke-width="1" opacity=".8" fill="none"/>"""


def wing(energy: float, full: bool) -> str:
    """5 根羽毛，energy 0..1。先画最右（第 5 根），左边的盖在上面。满了羽毛微微张开上扬。"""
    parts = []
    for i in reversed(range(5)):
        fill = max(0.0, min(1.0, energy * 5 - i))
        L = 86 + i * 10
        x = 102 + i * 37 + (5 * i if full else 0)
        y = 87 + i * 1.4 - (2 if full else 0)
        rot = 15 - i * 2.4 - (4 if full else 0)
        parts.append(f'<g transform="translate({x:.1f} {y:.1f}) rotate({rot:.1f})">{feather(L, fill, i, full)}</g>')
    return "".join(parts)


# ---------- 玻璃管 ----------
TX0, TX1, TY0, TY1 = 92.0, 404.0, 61.0, 81.0


def tube(hp: float, low: bool) -> str:
    ix0, ix1 = TX0 + 4, TX1 - 2
    lx = ix0 + (ix1 - ix0) * hp
    liq = "liquidLow" if low else "liquid"
    mid = (TX0 + TX1) / 2 + 20
    bubbles = "".join(f'<circle cx="{ix0 + (lx - ix0) * f:.1f}" cy="{TY0 + 5 + (i % 3) * 3.5:.1f}" r="{0.7 + (i % 2) * 0.5:.1f}" fill="#ffb3c0" opacity=".45"/>'
                      for i, f in enumerate([0.12, 0.31, 0.47, 0.66, 0.83]))
    cracks = ""
    if low:
        cracks = ('<g stroke="#e9eeff" stroke-width=".7" fill="none" opacity=".75">'
                  f'<path d="M{lx + 40:.1f} {TY0 + 2} l4 5 l-3 4 l5 6"/><path d="M{lx + 44:.1f} {TY0 + 7} l7 -2"/>'
                  f'<path d="M{ix0 + 30:.1f} {TY1 - 2} l3 -6 l5 -2"/></g>')
    cid = uid("inner")
    return f"""
  <rect x="{TX0}" y="{TY0}" width="{TX1 - TX0}" height="{TY1 - TY0}" rx="10" fill="#06070c" opacity=".7"/>
  <clipPath id="{cid}"><rect x="{ix0}" y="{TY0 + 3}" width="{ix1 - ix0}" height="{TY1 - TY0 - 6}" rx="7"/></clipPath>
  <g clip-path="url(#{cid})">
    <path d="M{ix0} {TY0 + 3} L{lx - 1.5:.1f} {TY0 + 3} C{lx + 2.5:.1f} {TY0 + 7} {lx + 2.5:.1f} {TY1 - 7} {lx - 1.5:.1f} {TY1 - 3} L{ix0} {TY1 - 3} Z" fill="url(#{liq})"/>
    <path d="M{lx - 1.5:.1f} {TY0 + 3.2} C{lx + 2.5:.1f} {TY0 + 7} {lx + 2.5:.1f} {TY1 - 7} {lx - 1.5:.1f} {TY1 - 3}" stroke="#ff9db0" stroke-width=".9" fill="none" opacity=".7"/>
    {bubbles}
    <rect x="{ix0}" y="{TY0 + 3}" width="{lx - ix0:.1f}" height="2.2" fill="#ff8ea2" opacity=".35"/>
  </g>
  <rect x="{TX0}" y="{TY0}" width="{TX1 - TX0}" height="{TY1 - TY0}" rx="10" fill="url(#glass)" stroke="#b9c1d3" stroke-width=".9"/>
  <path d="M{TX0 + 10} {TY0 + 4.2} L{TX1 - 12} {TY0 + 4.2}" stroke="#ffffff" stroke-width="1.6" opacity=".55" stroke-linecap="round"/>
  <path d="M{TX0 + 14} {TY1 - 4} L{TX1 - 20} {TY1 - 4}" stroke="#c8d4ff" stroke-width=".7" opacity=".3" stroke-linecap="round"/>
  {cracks}
  <!-- 刻度：十分之一一道 -->
  <g stroke="#dfe5f2" stroke-width=".6" opacity=".35">{''.join(f'<path d="M{ix0 + (ix1 - ix0) * k / 10:.1f} {TY1 - 2} l0 -3"/>' for k in range(1, 10))}</g>
  <!-- 银箍：中段 + 尾端 + 尖顶封头 -->
  <g filter="url(#metal)">
    <rect x="{mid - 5}" y="{TY0 - 3}" width="10" height="{TY1 - TY0 + 6}" rx="2" fill="url(#silver)"/>
    <path d="M{mid} {TY0 - 8} l4 5 l-4 2.4 l-4 -2.4 Z" fill="url(#silver)"/>
    <path d="M{mid} {TY1 + 8} l4 -5 l-4 -2.4 l-4 2.4 Z" fill="url(#silver)"/>
    <rect x="{TX1 - 6}" y="{TY0 - 4}" width="12" height="{TY1 - TY0 + 8}" rx="2.5" fill="url(#silver)"/>
    <path d="M{TX1 + 6} {TY0 + 3} L{TX1 + 16} {TY0 + 5} L{TX1 + 46} {(TY0 + TY1) / 2} L{TX1 + 16} {TY1 - 5} L{TX1 + 6} {TY1 - 3} Z" fill="url(#silverH)"/>
    <path d="M{TX1 + 6} {TY0 + 2} L{TX1 + 26} {TY0 - 9} L{TX1 + 18} {TY0 + 4} Z" fill="url(#silver)"/>
    <path d="M{TX1 + 6} {TY1 - 2} L{TX1 + 26} {TY1 + 9} L{TX1 + 18} {TY1 - 4} Z" fill="url(#silver)"/>
    <circle cx="{TX1 + 12}" cy="{(TY0 + TY1) / 2}" r="3" fill="url(#silver)"/>
  </g>
  <path d="M{TX1 + 16} {(TY0 + TY1) / 2} L{TX1 + 44} {(TY0 + TY1) / 2}" stroke="#ffffff" stroke-width=".8" opacity=".6"/>
"""


def collar() -> str:
    """颈箍（下垂三尖）+ 管座（三根鸦爪扣住玻璃管头）。"""
    claws = ""
    for k, (y0, sgn) in enumerate([(61.0, -1), (81.0, 1)]):
        for j in range(2):
            x = 100 + j * 9
            claws += (f'<path d="M{x - 4} {y0 + sgn * 1.5} C{x} {y0 + sgn * 6} {x + 7} {y0 + sgn * 5} {x + 9} {y0 - sgn * 1.5} '
                      f'C{x + 6} {y0 + sgn * 1.6} {x + 2} {y0 + sgn * 2.2} {x - 2} {y0 + sgn * 0.6} Z" fill="url(#silver)"/>')
    return f"""
  <g filter="url(#metal)">
    <path d="M74 55 L101 58 L101 84 L74 87 C69 77 69 65 74 55 Z" fill="url(#oxSilver)"/>
    {claws}
    <path d="M22 90 C40 96 56 96 72 90 L74 97 L67 96.5 L63 104 L57 97.5 L47 107 L37 97.5 L30 104 L26 96.5 L19 97 Z" fill="url(#silver)"/>
  </g>
  <g fill="#e7ebf3" opacity=".85">{''.join(f'<circle cx="{28 + i*9:.1f}" cy="{95 + math.sin(i/4*math.pi)*1.4:.1f}" r="1.1"/>' for i in range(5))}</g>
  <path d="M80 61 L96 62.5 M80 81 L96 79.5" stroke="#e9edf6" stroke-width=".6" opacity=".55"/>
  <path d="M83 66 C88 68 88 74 83 76" stroke="#0b0c10" stroke-width="1" fill="none" opacity=".8"/>
"""


def hud(hp=0.75, energy=0.68, full=False, low=False, show_bg_band=True) -> str:
    eye = "open" if full else "closed"
    num = int(round(hp * 100))
    label = ""
    if full:
        label = ('<g filter="url(#glow)"><text x="318" y="122" font-family="Source Han Serif SC Heavy, Noto Serif SC" font-weight="900" '
                 'font-size="17" fill="#e4d2ff" letter-spacing="3">绝影</text></g>'
                 '<text x="364" y="121" font-family="Georgia" font-style="italic" font-weight="bold" font-size="14" fill="#cdb6ff">J+K</text>')
    num_col = "#ffb0bb" if low else "#ece6d8"
    band = f'<rect x="0" y="0" width="560" height="150" fill="url(#back)" mask="url(#backMask)"/>' if show_bg_band else ""
    return f"""
<g id="hud">
  {band}
  <g transform="translate(6 4)">
    {wing(energy, full)}
    {tube(hp, low)}
    {collar()}
    <g transform="translate(4 2)">{crow_head(eye)}</g>
    <text x="462" y="80" font-family="Georgia" font-style="italic" font-weight="bold" font-size="30" fill="{num_col}" filter="url(#shadow)">{num}</text>
    {label}
  </g>
  <text x="34" y="140" font-family="Source Han Serif SC Heavy, Noto Serif SC" font-size="12.5" fill="#9aa3b8" letter-spacing="3" opacity=".85">第 1 轮 · 封印 1/3 · 第 1/2 波</text>
</g>"""


def page(body_svg: str, w: int, h: int, bg=True, view=None) -> str:
    vb = view or f"0 0 {w} {h}"
    bgimg = f'<image href="{BG}" x="0" y="0" width="1280" height="720"/>' if bg else ""
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
html,body{{margin:0;background:#05060a;overflow:hidden}}svg{{display:block}}</style></head><body>
<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{vb}">
{DEFS}
<clipPath id="headClip"><path d="{HEAD}"/></clipPath>
{bgimg}
{body_svg}
</svg></body></html>"""


def shoot(html: str, name: str, w: int, h: int, scale: int = 1):
    f = HERE / f"_{name}.html"
    f.write_text(html, encoding="utf-8")
    png = OUT / f"{name}.png"
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                    "--allow-file-access-from-files", f"--force-device-scale-factor={scale}",
                    f"--window-size={w},{h}", f"--screenshot={png}", f.as_uri()],
                   check=True, capture_output=True, timeout=60)
    print("wrote", png)


if __name__ == "__main__":
    # 1) 实机构图：常态（75 血、大招 68%）
    shoot(page(hud(), 1280, 720), "银鸦落羽_实机常态", 1280, 720)
    # 2) 三态特写（2 倍）：常态 / 大招满 / 低血
    states = [("常态", dict(hp=0.75, energy=0.68)), ("大招满", dict(hp=0.75, energy=1.0, full=True)),
              ("低血", dict(hp=0.18, energy=1.0, full=True, low=True))]
    rows = []
    for i, (title, kw) in enumerate(states):
        rows.append(f'<g transform="translate(0 {i * 160})"><svg x="0" y="0" width="600" height="160" viewBox="0 0 600 160">'
                    f'<image href="{BG}" x="-20" y="-6" width="1280" height="720"/>{hud(**kw)}</svg>'
                    f'<text x="590" y="150" text-anchor="end" font-family="Noto Serif SC" font-size="13" fill="#c8cfdd">{title}</text></g>')
    shoot(page("".join(rows), 600, 480, bg=False), "银鸦落羽_三态特写", 600, 480, scale=2)
    shoot(page(f'<svg x="0" y="0" width="300" height="130" viewBox="0 0 150 65"><image href="{BG}" x="-20" y="-6" width="1280" height="720"/>{hud(hp=.75, energy=1.0, full=True)}</svg>',
               300, 130, bg=False), "_鸦首特写", 300, 130, scale=3)
