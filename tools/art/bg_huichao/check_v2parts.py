from PIL import Image, ImageStat, ImageOps

SC = r"E:/00game/nightcrow-godot/docs/视觉设计/work/"
L = r"E:/00game/nightcrow-godot/docs/视觉设计/layers/cloud_causeway/"


def key_magenta(im):
    px = im.convert("RGB").get_flattened_data()
    out, pink = [], 0
    for R, G, B in px:
        d = (min(R, B) - G) / 255.0
        a = 1.0 - (d - 0.15) / 0.7
        if a >= 1.0:
            out.append((R, G, B, 255))
            continue
        if a <= 0.003:
            out.append((0, 0, 0, 0))
            continue
        r = (R / 255.0 - (1 - a)) / a
        g = (G / 255.0) / a
        b = (B / 255.0 - (1 - a)) / a
        r, g, b = [min(1.0, max(0.0, v)) for v in (r, g, b)]
        if r > g + 0.25 and b > g + 0.25:
            pink += 1
        out.append((int(r * 255), int(g * 255), int(b * 255), int(a * 255)))
    o = Image.new("RGBA", im.size)
    o.putdata(out)
    return o, pink


parts, pink = key_magenta(Image.open(L + "10_platforms_v2.webp"))
parts.save(SC + "keyed/10_platforms_v2.png")
print("parts pink-left", pink)

# 各零件的外框：按列 / 行找连通的不透明块（粗略）
a = parts.split()[3]
W, H = parts.size
def runs(vals):
    out, s = [], None
    for i, v in enumerate(vals):
        if v and s is None:
            s = i
        if not v and s is not None:
            out.append((s, i - 1)); s = None
    if s is not None:
        out.append((s, len(vals) - 1))
    return out
rows = [any(a.getpixel((x, y)) > 128 for x in range(0, W, 3)) for y in range(H)]
for y0, y1 in runs(rows):
    cols = [any(a.getpixel((x, y)) > 128 for y in range(y0, y1 + 1, 3)) for x in range(W)]
    print("row band", (y0, y1), "pieces", [r for r in runs(cols) if r[1] - r[0] > 20])

# 俯视石板：2×2 平铺看接缝
deck = Image.open(L + "09_deck_top_v1.webp").convert("RGB")
dw, dh = deck.size
tile = Image.new("RGB", (dw * 2, dh * 2))
for i in range(2):
    for j in range(2):
        tile.paste(deck, (i * dw, j * dh))
tile.crop((dw - 400, dh - 250, dw + 400, dh + 250)).save(SC + "deck_seam.png")
print("deck", deck.size, "mean", round(ImageStat.Stat(ImageOps.grayscale(deck)).mean[0] / 255, 2))
