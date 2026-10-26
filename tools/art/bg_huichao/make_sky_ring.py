"""天空层：天空 v2（01a_sky_v2.webp）+ 从实战定调图右上角裁下的巨环、月亮、青光云。
输出 layers/cloud_causeway/01_sky_ring_from_keyart.png（1916×821）。
已知问题：裁块左上边缘在画面 x≈940 附近有一条竖向色差接缝，需要改成“先按重叠区校色、再用更大的羽化”（见交接文档 7.2）。"""
from PIL import Image, ImageDraw, ImageFilter

L = "E:/00game/nightcrow-godot/docs/视觉设计/layers/cloud_causeway/"
K = "E:/00game/nightcrow-godot/docs/视觉设计/keyart/gameplay_frame_v2.webp"

sky = Image.open(L + "01a_sky_v2.webp").convert("RGB")
SW, SH = sky.size
# 天空 v2 自己的月亮（右上最亮的一块）用旁边的夜空盖掉
g = sky.convert("L")
best = (0, 0, 0)
for y in range(40, 400, 4):
    for x in range(1100, 1800, 4):
        v = g.getpixel((x, y))
        if v > best[0]:
            best = (v, x, y)
_, mx, my = best
R = 90
patch = sky.crop((mx - R - 260, my - R, mx + R - 260, my + R))
pm = Image.new("L", (2 * R, 2 * R), 0)
ImageDraw.Draw(pm).ellipse([10, 10, 2 * R - 10, 2 * R - 10], fill=255)
sky.paste(patch, (mx - R, my - R), pm.filter(ImageFilter.GaussianBlur(14)))

# 定调图右上角：巨环 + 月亮 + 青光云，按“定调图一屏 = 游戏一屏”缩放
kf = Image.open(K).convert("RGB")
crop = kf.crop((930, 0, 1672, 360))
k = (720 / 941) / (720 / SH)
crop = crop.resize((round(crop.size[0] * k), round(crop.size[1] * k)), Image.LANCZOS)
cw, ch = crop.size
m = Image.new("L", (cw, ch), 0)
d = ImageDraw.Draw(m)
d.ellipse([320 - 300, 105 - 150, 320 + 300, 105 + 150], fill=255)
d.rectangle([110, 0, cw, 40], fill=255)       # 保住被上沿切掉的环顶 —— 这一块造成了竖向接缝，改进时去掉或羽化
d.rectangle([425, 150, cw, ch], fill=0)       # 定调图里的断塔不要
d.rectangle([600, 0, cw, ch], fill=0)
m = m.filter(ImageFilter.GaussianBlur(36))
sky.paste(crop, (SW - cw + 10, 0), m)
sky.save(L + "01_sky_ring_from_keyart.png")
print("ok")
