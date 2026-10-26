"""绿底抠图（只用 Pillow）：和边缘连通的绿 + 几乎纯绿 = 背景；其余像素按“比红蓝多出来的绿”给半透明并去绿溢色
（半透明黑烟透出来的绿底也能变成干净的半透明黑）。用法：python key_green.py 源 输出"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter


def key(src, dst):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    cand = Image.new("L", (w, h), 0)
    cp = cand.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if g > 150 and g - max(r, b) > 110:
                cp[x, y] = 255
    for s in [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]:
        if cp[s] == 255:
            ImageDraw.floodfill(cand, s, 128)
    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            m = max(r, b)
            spill = g - m
            if cp[x, y] == 128 or (g > 200 and spill > 170):
                op[x, y] = (0, 0, 0, 0)
                continue
            if spill > 0:
                a = max(0.0, 1.0 - spill / 230.0)
                if a <= 0.02:
                    op[x, y] = (0, 0, 0, 0)
                    continue
                # 去掉混进来的绿：反解 c = fg*a + green*(1-a)，绿通道压到不超过红蓝
                rr = min(255, max(0, int((r - 0 * (1 - a)) / a)))
                bb = min(255, max(0, int((b - 0 * (1 - a)) / a)))
                gg = min(255, max(0, int((g - 255 * (1 - a)) / a)))
                gg = min(gg, (rr + bb) // 2 + 8)
                op[x, y] = (rr, gg, bb, int(a * 255))
            else:
                op[x, y] = (r, min(g, (r + b) // 2 + 8) if g > (r + b) // 2 + 8 and g > 40 else g, b, 255)
    # 收边（评审：青色溢色边）：贴着背景的 3px 以内，绿通道压到 (R+B)/2（原来只压到 max(R,B)，蓝紫边上会剩青色），
    # 透明度收 1px 再羽化，去掉最外一圈混了绿底的毛边
    alpha = out.getchannel("A")
    bg = alpha.point(lambda v: 255 if v == 0 else 0)
    ring = ImageChops.subtract(bg.filter(ImageFilter.MaxFilter(7)), bg)
    shrunk = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    rp = ring.load()
    sp = shrunk.load()
    for y in range(h):
        for x in range(w):
            if rp[x, y]:
                r, g, b, a = op[x, y]
                op[x, y] = (r, min(g, (r + b) // 2), b, min(a, sp[x, y]))
    out.save(dst)
    print("keyed", dst, out.size)


if __name__ == "__main__":
    key(sys.argv[1], sys.argv[2])
