import sys
from PIL import Image
SC = r"E:/00game/nightcrow-godot/docs/视觉设计/work/"
L = r"E:/00game/nightcrow-godot/docs/视觉设计/layers/cloud_causeway/"
def key_magenta(im):
    out, pink = [], 0
    for R, G, B in im.convert("RGB").get_flattened_data():
        d = (min(R, B) - G) / 255.0
        a = 1.0 - (d - 0.15) / 0.7
        if a >= 1.0:
            out.append((R, G, B, 255)); continue
        if a <= 0.003:
            out.append((0, 0, 0, 0)); continue
        r = (R / 255.0 - (1 - a)) / a; g = (G / 255.0) / a; b = (B / 255.0 - (1 - a)) / a
        r, g, b = [min(1.0, max(0.0, v)) for v in (r, g, b)]
        if r > g + 0.25 and b > g + 0.25: pink += 1
        out.append((int(r * 255), int(g * 255), int(b * 255), int(a * 255)))
    o = Image.new("RGBA", im.size); o.putdata(out); return o, pink
for n in ["11_mountains_v2", "12_crow_post_v1"]:
    o, p = key_magenta(Image.open(L + n + ".webp"))
    o.save(SC + "keyed/" + n + ".png"); print(n, o.size, o.getbbox(), "pink", p)
m = Image.open(SC + "keyed/11_mountains_v2.png"); w, h = m.size
seam = Image.new("RGBA", (600, h), (30, 40, 70, 255))
seam.alpha_composite(m.crop((w - 300, 0, w, h)), (0, 0)); seam.alpha_composite(m.crop((0, 0, 300, h)), (300, 0))
seam.save(SC + "mount_seam.png")
