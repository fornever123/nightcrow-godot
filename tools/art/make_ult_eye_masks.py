"""大招眼睛分格（2026-10-29 原型）：从眼睛特写生成游戏用图和遮罩。只依赖 Pillow。

  python tools/art/make_ult_eye_masks.py

输入  tools/art/src/ult/feather/closeup_eye.webp（1672×941，不改原图）
输出  assets/image/ult/eye/closeup_eye.png   原图转 PNG
      assets/image/ult/eye/eye_masks.png     R = 深度（0 远 / 0.5 头发和脸 / 1 前景），G = 头发羽毛摆动（避开眼睛）
深度和摆动区域是按原图手量的多边形 / 椭圆，再大半径模糊；只用来做几像素的视差和摆动，不求精确。
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "tools/art/src/ult/feather/closeup_eye.webp"
OUT = ROOT / "assets/image/ult/eye"

# 双眼虹膜（原图像素）：中心、半径。ult_eye_panel.gd 里同一组数
EYES = [((730, 408), (66, 58)), ((1104, 488), (54, 44))]


def poly(size, pts, value, blur):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(pts, fill=value)
    return m.filter(ImageFilter.GaussianBlur(blur))


def ellipse(size, box, value, blur):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).ellipse(box, fill=value)
    return m.filter(ImageFilter.GaussianBlur(blur))


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    im = Image.open(SRC).convert("RGB")
    im.save(OUT / "closeup_eye.png", optimize=True)
    size = im.size

    # 深度：底子 0.5（头发和脸）；右边灰云远；左下肩甲和羽毛、左上虚焦羽毛、右下虚焦羽毛近
    depth = Image.new("L", size, 128)
    far = poly(size, [(1500, 0), (1672, 0), (1672, 760), (1560, 700), (1470, 520), (1440, 330)], 255, 40)
    depth.paste(Image.new("L", size, 20), (0, 0), far)
    near = [
        poly(size, [(0, 430), (300, 440), (560, 520), (720, 640), (900, 941), (0, 941)], 255, 30),
        ellipse(size, (380, 60, 680, 320), 255, 40),
        poly(size, [(1320, 760), (1672, 700), (1672, 941), (1280, 941)], 255, 40),
    ]
    for m in near:
        depth.paste(Image.new("L", size, 250), (0, 0), m)
    depth = depth.filter(ImageFilter.GaussianBlur(12))

    # 摆动：左边发梢、白发和右边头发、羽毛发饰、头顶发丝（弱）；双眼周围一圈清零，不拖动睫毛
    sway = Image.new("L", size, 0)
    for pts, v in [
        ([(0, 120), (470, 160), (520, 420), (420, 520), (0, 520)], 200),
        ([(1170, 0), (1420, 0), (1430, 760), (1250, 800), (1200, 560)], 220),
        ([(1370, 90), (1640, 90), (1640, 480), (1370, 480)], 255),
        ([(300, 0), (1170, 0), (1170, 230), (300, 230)], 110),
    ]:
        sway = ImageChops.lighter(sway, poly(size, pts, v, 35))
    guard = Image.new("L", size, 0)
    d = ImageDraw.Draw(guard)
    for (cx, cy), (rx, ry) in EYES:
        d.ellipse((cx - rx - 110, cy - ry - 70, cx + rx + 110, cy + ry + 70), fill=255)
    guard = guard.filter(ImageFilter.GaussianBlur(30))
    sway = ImageChops.subtract(sway, guard)

    zero = Image.new("L", size, 0)
    Image.merge("RGB", (depth, sway, zero)).save(OUT / "eye_masks.png", optimize=True)
    print("wrote", OUT / "closeup_eye.png", OUT / "eye_masks.png")


if __name__ == "__main__":
    main()
