"""把 AI 生成的角色图放到更大的品红画布上，四周留足空间，让视频里挥刀、转刀不会出画。
不缩放角色本身（不损失清晰度），只扩画布。

用法：
  python tools/art/pad_first_frame.py <输入图> <输出 png> [--ratio 0.5] [--canvas-h H]
                                       [--left 0.06] [--center 0.45] [--foot 0.78]
  --ratio     角色包围盒高度占画面高度的比例（不给 --canvas-h 时用来定画布大小）
  --canvas-h  直接指定画布高度；几张图要放进同一尺寸画布时用它（宽度按 16:9）
  --left      角色包围盒左边贴在画面宽度的这个比例处（放左下角时用）
  --right     角色包围盒右边（面朝右时是前脚尖）贴在画面宽度的这个比例处；几张图按前脚对齐时用
  --center    不给 --left / --right 时，角色包围盒水平中心放在这个比例处
  --foot      脚底（包围盒底边）放在画面高度的这个比例处
  --scale     先把整张图缩放这个倍数（几张图里角色大小不一致时，用来统一比例）
"""
import argparse

from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("src")
ap.add_argument("dst")
ap.add_argument("--ratio", type=float, default=0.5)
ap.add_argument("--canvas-h", type=int, default=0)
ap.add_argument("--left", type=float, default=-1.0)
ap.add_argument("--right", type=float, default=-1.0)
ap.add_argument("--center", type=float, default=0.45)
ap.add_argument("--foot", type=float, default=0.78)
ap.add_argument("--scale", type=float, default=1.0)
a = ap.parse_args()

im = Image.open(a.src).convert("RGB")
if a.scale != 1.0:
    im = im.resize((round(im.width * a.scale), round(im.height * a.scale)), Image.LANCZOS)
w, h = im.size

# 背景色：四个角的像素中位数
corners = [im.getpixel((x, y)) for x in (2, w - 3) for y in (2, h - 3)]
bg = tuple(sorted(c[i] for c in corners)[len(corners) // 2] for i in range(3))


def is_bg(c):
    return sum(abs(c[i] - bg[i]) for i in range(3)) < 90


# 角色包围盒（隔点扫描足够）
xs, ys = [], []
px = im.load()
for y in range(0, h, 2):
    for x in range(0, w, 2):
        if not is_bg(px[x, y]):
            xs.append(x)
            ys.append(y)
x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)

# 原图背景有噪点和轻微渐变：接近背景色的像素统一压成纯背景色，避免新旧画布之间出现方框接缝
for y in range(h):
    for x in range(w):
        if is_bg(px[x, y]):
            px[x, y] = bg

H2 = a.canvas_h or max(int(round((y1 - y0) / a.ratio)), h)
W2 = int(round(H2 * 16 / 9))
if a.left >= 0:
    ox = int(W2 * a.left) - x0
elif a.right >= 0:
    ox = int(W2 * a.right) - x1
else:
    ox = int(W2 * a.center) - (x0 + x1) // 2
oy = int(H2 * a.foot) - y1

canvas = Image.new("RGB", (W2, H2), bg)
canvas.paste(im, (ox, oy))
canvas.save(a.dst)
print(f"bg={bg} char=({x0},{y0})-({x1},{y1}) canvas={W2}x{H2} offset=({ox},{oy}) "
      f"char_on_canvas=({x0 + ox},{y0 + oy})-({x1 + ox},{y1 + oy})")
