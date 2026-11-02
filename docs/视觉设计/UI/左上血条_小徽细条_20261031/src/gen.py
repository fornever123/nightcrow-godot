"""小徽细条：按鬼泣5 / 只狼 / 空洞骑士的骨架做的左上 HUD 样图（UI 线 10-31）。
骨架：角落一个小而精的徽记 + 一根很细很长的血条 + 一排细的分段能量格。按 1280×720 原尺寸画。
用法：python gen.py → ../小徽细条_*.png
"""
import pathlib
import subprocess

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent
BG = (HERE.parents[1] / "现状截图_20261031" / "00_无UI底图.png").as_uri()
EDGE = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"

DEFS = """<defs>
<linearGradient id="ag" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#eef1f7"/><stop offset=".45" stop-color="#9aa1ae"/>
  <stop offset=".55" stop-color="#5b616d"/><stop offset="1" stop-color="#c3c8d2"/></linearGradient>
<linearGradient id="hp" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#ffffff"/><stop offset=".5" stop-color="#e4e0d6"/><stop offset="1" stop-color="#a9a49a"/></linearGradient>
<linearGradient id="hpLow" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#ffd0d6"/><stop offset=".5" stop-color="#c64a5c"/><stop offset="1" stop-color="#6e1626"/></linearGradient>
<linearGradient id="ult" x1="0" y1="0" x2="0" y2="1">
  <stop offset="0" stop-color="#e9dcff"/><stop offset=".5" stop-color="#9b6bff"/><stop offset="1" stop-color="#4f2aa8"/></linearGradient>
<linearGradient id="shade" x1="0" y1="0" x2="1" y2="0">
  <stop offset="0" stop-color="#04050a" stop-opacity=".7"/><stop offset=".6" stop-color="#04050a" stop-opacity=".35"/>
  <stop offset="1" stop-color="#04050a" stop-opacity="0"/></linearGradient>
<radialGradient id="lid" cx=".5" cy=".5" r=".5">
  <stop offset="0" stop-color="#f1e6ff"/><stop offset=".4" stop-color="#a070ff"/><stop offset="1" stop-color="#3a1680" stop-opacity="0"/></radialGradient>
<filter id="sh" x="-20%" y="-50%" width="140%" height="200%"><feDropShadow dx="0" dy="1" stdDeviation="1" flood-color="#000" flood-opacity=".9"/></filter>
<filter id="gl" x="-50%" y="-200%" width="200%" height="500%"><feGaussianBlur stdDeviation="2.2" result="g"/>
  <feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
<filter id="soft"><feGaussianBlur stdDeviation="3"/></filter>
</defs>"""


def emblem(cx: float, cy: float, state: str) -> str:
    """她的眼印：四角尖的哥特菱形银框（内凹边）+ 中间一只眼。
    充能中：眼闭着，眼缝透紫；满：睁开紫色竖瞳。低血：银框暗、眼缝发红。"""
    R = 27.0
    # 内凹四角星形外框（两层细线）
    def lozenge(r, k):
        # 竖放的尖拱（两段圆弧，上下都是尖的）= 街上哥特窗的形状，眼睛住在窗里
        w = r * .72
        return (f"M{cx} {cy - r} C{cx + w*.9} {cy - r*.55} {cx + w} {cy + r*.1} {cx + w*.62} {cy + r*.62} "
                f"Q{cx + w*.3} {cy + r*.9} {cx} {cy + r} Q{cx - w*.3} {cy + r*.9} {cx - w*.62} {cy + r*.62} "
                f"C{cx - w} {cy + r*.1} {cx - w*.9} {cy - r*.55} {cx} {cy - r} Z")
    frame = (f'<path d="{lozenge(R, .2)}" fill="#07080d" fill-opacity=".85" stroke="url(#ag)" stroke-width="1.6"/>'
             f'<path d="{lozenge(R - 4.5, .22)}" fill="none" stroke="#c9ced8" stroke-width=".6" opacity=".7"/>')
    # 上下两枚小羽（眼印的“睫羽”），左右各一道细刺
    feathers = ""
    for sgn in (-1, 1):
        y0 = cy + sgn * (R + 1)
        feathers += (f'<path d="M{cx} {y0} q2.6 {sgn*5} 0 {sgn*11} q-2.6 {-sgn*6} 0 {-sgn*11} Z" fill="url(#ag)"/>'
                     f'<path d="M{cx} {y0 + sgn*1} l0 {sgn*9}" stroke="#2a2d35" stroke-width=".5"/>')
    ticks = "".join(
        f'<circle cx="{cx + dx}" cy="{cy + dy}" r=".9" fill="#dfe3ea"/>'
        for dx, dy in [(0, -R + 7), (0, R - 7)])
    # 眼
    ew, eh = 11.5, 5.6
    almond = f"M{cx - ew} {cy} Q{cx} {cy - eh*1.6} {cx + ew} {cy} Q{cx} {cy + eh*1.6} {cx - ew} {cy} Z"
    if state == "full":
        eye = (f'<ellipse cx="{cx}" cy="{cy}" rx="18" ry="11" fill="#8a4dff" opacity=".55" filter="url(#soft)"/>'
               f'<path d="{almond}" fill="#160830"/><path d="{almond}" fill="url(#lid)"/>'
               f'<path d="M{cx} {cy - 5.2} Q{cx + 1.8} {cy} {cx} {cy + 5.2} Q{cx - 1.8} {cy} {cx} {cy - 5.2} Z" fill="#07020f"/>'
               f'<circle cx="{cx + 3}" cy="{cy - 2}" r=".8" fill="#fff"/>'
               f'<path d="{almond}" fill="none" stroke="#e8e2ff" stroke-width=".8"/>')
    else:
        glow = "#ff6a7e" if state == "low" else "#a070ff"
        k = .35 if state == "low" else .6
        eye = (f'<path d="M{cx - ew} {cy} Q{cx} {cy - eh*1.4} {cx + ew} {cy}" fill="none" stroke="#c9ced8" stroke-width="1"/>'
               f'<path d="M{cx - ew} {cy} Q{cx} {cy + eh*.5} {cx + ew} {cy}" fill="none" stroke="{glow}" stroke-width="1.3" filter="url(#gl)" opacity="{.5 + k*.5}"/>'
               f'<path d="M{cx - ew + 3} {cy + 1.2} l-2 3 M{cx - 4} {cy + 2.6} l-1 3.4 M{cx + 4} {cy + 2.6} l1 3.4 M{cx + ew - 3} {cy + 1.2} l2 3" stroke="#aeb4c0" stroke-width=".6"/>')
    return f'<g filter="url(#sh)">{frame}{feathers}{ticks}{eye}</g>'


def hud(hp=0.75, ghost=None, ult=0.6, state="charge", wave=True) -> str:
    x0, x1 = 84.0, 404.0
    y = 37.0
    h = 4.0
    low = state == "low"
    xf = x0 + (x1 - x0) * hp
    parts = ['<rect x="0" y="0" width="460" height="90" fill="url(#shade)"/>']
    # 血条：发丝细框 + 4px 实条，两端斜切
    parts.append(f'<path d="M{x0} {y - 3} L{x1 + 4} {y - 3} L{x1} {y + h + 3} L{x0 - 4} {y + h + 3} Z" fill="#05060a" fill-opacity=".65" stroke="#8d94a2" stroke-width=".6"/>')
    if ghost:
        parts.append(f'<rect x="{xf}" y="{y}" width="{(x1 - x0) * (ghost - hp)}" height="{h}" fill="#7a2232" opacity=".9"/>')
    parts.append(f'<rect x="{x0}" y="{y}" width="{xf - x0}" height="{h}" fill="url(#{"hpLow" if low else "hp"})"/>')
    parts.append(f'<rect x="{x0}" y="{y}" width="{xf - x0}" height="1" fill="#fff" opacity=".7"/>')
    parts.append(f'<path d="M{xf} {y - 2} l0 {h + 4}" stroke="#fff" stroke-width="1" opacity=".9"/>')
    for k in range(1, 4):  # 四分刻度
        xx = x0 + (x1 - x0) * k / 4
        parts.append(f'<path d="M{xx} {y + h + 3} l0 3" stroke="#8d94a2" stroke-width=".6"/>')
    # 绝影：5 段细格（3px 高），斜切
    gy = y + h + 9
    seg_w, gap = 34.0, 4.0
    for i in range(5):
        sx = x0 + i * (seg_w + gap)
        f = max(0.0, min(1.0, ult * 5 - i))
        parts.append(f'<path d="M{sx + 2} {gy} L{sx + seg_w + 2} {gy} L{sx + seg_w} {gy + 3} L{sx} {gy + 3} Z" fill="#05060a" fill-opacity=".7" stroke="#5d6370" stroke-width=".5"/>')
        if f > 0:
            fill = f'<path d="M{sx + 2} {gy} L{sx + 2 + seg_w * f} {gy} L{sx + seg_w * f} {gy + 3} L{sx} {gy + 3} Z" fill="url(#ult)"/>'
            parts.append(f'<g filter="url(#gl)">{fill}</g>' if state == "full" else fill)
    if state == "full":
        parts.append(f'<text x="{x0 + 5 * (seg_w + gap) + 6}" y="{gy + 4}" font-family="Source Han Serif SC Heavy" font-size="10" fill="#d9c6ff" letter-spacing="2" filter="url(#gl)">绝影</text>'
                     f'<text x="{x0 + 5 * (seg_w + gap) + 34}" y="{gy + 4}" font-family="Georgia" font-style="italic" font-weight="bold" font-size="9" fill="#bda6f5">J+K</text>')
    # 血量数字：小、贴在血条右端外面
    parts.append(f'<text x="{x1 + 10}" y="{y + 6}" font-family="Georgia" font-style="italic" font-weight="bold" font-size="14" fill="{"#ff9aa8" if low else "#ece6d8"}" filter="url(#sh)">{round(hp * 100)}</text>')
    parts.append(emblem(46, 42, state))
    if wave:
        parts.append('<text x="84" y="22" font-family="Source Han Serif SC Heavy" font-size="10" fill="#9aa3b8" letter-spacing="2" opacity=".85">第 1 轮 · 封印 1/3 · 第 1/2 波</text>')
    return "".join(parts)


def page(body: str, w: int, h: int) -> str:
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>html,body{{margin:0;background:#000;overflow:hidden}}'
            f'svg{{display:block}}</style></head><body><svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}">{DEFS}{body}</svg></body></html>')


def shoot(html: str, name: str, w: int, h: int, scale: int):
    f = HERE / f"_{name}.html"
    f.write_text(html, encoding="utf-8")
    png = OUT / f"{name}.png"
    subprocess.run([EDGE, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run",
                    "--allow-file-access-from-files", f"--force-device-scale-factor={scale}",
                    f"--window-size={w},{h}", f"--screenshot={png}", f.as_uri()], check=True, capture_output=True, timeout=60)
    f.unlink()
    print("wrote", png.name)


if __name__ == "__main__":
    bg = f'<image href="{BG}" x="0" y="0" width="1280" height="720"/>'
    shoot(page(bg + hud(), 1280, 720), "小徽细条_实机原尺寸", 1280, 720, 1)
    states = [("充能中", dict(hp=.75, ult=.62, state="charge")),
              ("大招满", dict(hp=.75, ult=1, state="full")),
              ("挨打后（残影）+ 低血", dict(hp=.18, ghost=.40, ult=.42, state="low"))]
    rows = ""
    for i, (t, kw) in enumerate(states):
        rows += (f'<g transform="translate(0 {i * 90})"><svg width="480" height="90" viewBox="0 0 480 90">'
                 f'<image href="{BG}" x="0" y="0" width="1280" height="720"/>{hud(**kw)}</svg>'
                 f'<text x="472" y="82" text-anchor="end" font-family="Noto Serif SC" font-size="9" fill="#c8cfdd">{t}</text></g>')
    shoot(page(rows, 480, 270), "小徽细条_三态放大", 480, 270, 3)
