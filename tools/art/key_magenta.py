"""品红底抠图（只用 Pillow）：只把和画面边缘连通的品红区域当背景，角色身上的紫色不会被误抠。

用法：python key_magenta.py 输入图 输出.png
- 品红程度 m = min(R, B) - G（纯品红 255，角色的紫色一般 < 120）
- 从四条边往里漫水填充 m > 150 的像素 = 背景；被围住的几乎纯品红小块（m > 205）也算背景
- 背景旁边 3 像素内按 m 做半透明过渡，并去掉品红溢色
"""
import sys
from collections import deque

from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
w, h = im.size
px = im.load()

m = [[0] * w for _ in range(h)]
for y in range(h):
    for x in range(w):
        r, g, b = px[x, y]
        m[y][x] = min(r, b) - g

bg = [[False] * w for _ in range(h)]
q = deque()
for x in range(w):
    for y in (0, h - 1):
        if m[y][x] > 150 and not bg[y][x]:
            bg[y][x] = True
            q.append((x, y))
for y in range(h):
    for x in (0, w - 1):
        if m[y][x] > 150 and not bg[y][x]:
            bg[y][x] = True
            q.append((x, y))
while q:
    x, y = q.popleft()
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if 0 <= nx < w and 0 <= ny < h and not bg[ny][nx] and m[ny][nx] > 150:
            bg[ny][nx] = True
            q.append((nx, ny))

# 被头发 / 手臂 / 羽毛围起来的品红小块和边缘不连通：几乎纯品红（m > 205）的也当背景
for y in range(h):
    for x in range(w):
        if m[y][x] > 205:
            bg[y][x] = True

# 背景遮罩膨胀 3 像素 = 边缘过渡区
mask = Image.new("L", (w, h), 0)
mp = mask.load()
for y in range(h):
    for x in range(w):
        if bg[y][x]:
            mp[x, y] = 255
near = mask.filter(ImageFilter.MaxFilter(7)).load()

out = Image.new("RGBA", (w, h))
op = out.load()
for y in range(h):
    for x in range(w):
        r, g, b = px[x, y]
        if bg[y][x]:
            op[x, y] = (0, 0, 0, 0)
            continue
        a = 255
        if near[x, y]:
            # 过渡区：品红越重越透明；再把品红溢色压掉（R、B 不超过 G + 当地允许的紫色）
            mm = m[y][x]
            a = max(0, min(255, int((170 - mm) * 255 / 120)))
            cap = g + 90
            r = min(r, cap)
            b = min(b, cap + 40)
        op[x, y] = (r, g, b, a)
out.save(dst)
print("ok", w, h)
