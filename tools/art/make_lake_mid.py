#!/usr/bin/env python3
"""第七轮「月下东方园林湖」中景层（湖对岸）：把用户 GPT 出的 3 段洋红底长条拼成一条首尾无缝的循环图。
用法：python3 tools/art/make_lake_mid.py 段1.png 段2.png 段3.png [输出目录=assets/scenery/moon_embankment] [--preview 目录]
做法：
  1. 抠图：离品红 #FF00FF 的距离 → 透明度，边缘去粉；
  2. 像素格对齐：GPT 的“像素”约 3 原图像素一格 → 缩到 512 格宽（INTER_AREA，带透明度加权），透明度只取 0/1；
  3. 三段共用一套 40 色调色板（k-means，LAB），格子颜色统一；
  4. 底边（岸线）对齐到同一行；
  5. 拼接：相邻两段在 OVERLAP 格宽的重叠区里，逐行找差异最小的竖向接缝（动态规划，允许每行左右挪 1 格），
     第 3 段的右边和第 1 段的左边同样做一次，所以整条首尾相接；
  6. 每格放大成 2×2 屏幕像素（和夜景像素化的 SNAP 2 一致），存成 castle.webp.b64（无损 webp），更新 layers.json。
原图存档在 tools/art/src/lake/mid_{1,2,3}.png。
"""
import base64, io, json, os, sys
import cv2
import numpy as np
from PIL import Image

GRID_W = 512          # 每段缩成多少格宽（1536 / 3）
CELL = 2              # 每格 = 几个屏幕像素
COLORS = 40
OVERLAP = 28          # 拼接重叠区（格）
HORIZON = 417         # 屏幕上水平线（湖面最上沿）的 y，见 layers.json sea.top


def key(im):
    """im 是 BGR。品红距离 → 透明度；再全图去品红溢色：红、蓝都明显高于绿的像素（紫 / 品红混色）把红压到绿、蓝压到绿 +0.12。
    暖灯（红高蓝低）和冷色树叶（蓝高红低）都不受影响。"""
    d = np.linalg.norm(im - np.array([1, 0, 1], np.float32), axis=2)
    a = np.clip((d - 0.35) / 0.3, 0, 1)
    b, g, r = im[..., 0], im[..., 1], im[..., 2]
    spill = (r > g + 0.03) & (b > g + 0.03)
    r2 = np.where(spill, np.minimum(r, g), r)
    b2 = np.where(spill, np.minimum(b, g + 0.12), b)
    im = np.stack([b2, g, r2], 2)
    return im, a


def to_grid(path):
    im = cv2.imread(path).astype(np.float32) / 255
    im, a = key(im)
    H, W = a.shape
    gh = round(H * GRID_W / W)
    pre = cv2.resize(im * a[..., None], (GRID_W, gh), interpolation=cv2.INTER_AREA)
    aa = cv2.resize(a, (GRID_W, gh), interpolation=cv2.INTER_AREA)
    rgb = np.clip(pre / np.maximum(aa, 1e-4)[..., None], 0, 1)
    return rgb, (aa >= 0.5)


def quantize(segs):
    allpx = np.concatenate([cv2.cvtColor(r.astype(np.float32), cv2.COLOR_BGR2LAB)[m] for r, m in segs])
    _, _, cen = cv2.kmeans(allpx.astype(np.float32), COLORS, None,
                           (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 50, 0.1), 4, cv2.KMEANS_PP_CENTERS)
    out = []
    for r, m in segs:
        lab = cv2.cvtColor(r.astype(np.float32), cv2.COLOR_BGR2LAB).reshape(-1, 3)
        d = ((lab[:, None, :] - cen[None, :, :]) ** 2).sum(2)
        q = cen[d.argmin(1)].reshape(r.shape).astype(np.float32)
        q = cv2.cvtColor(q, cv2.COLOR_LAB2BGR)
        rgba = np.zeros(r.shape[:2] + (4,), np.float32)
        rgba[..., :3] = q
        rgba[..., 3] = m
        out.append(rgba)
    return out


def align_bottom(segs):
    """每段的岸线（最下面有内容的行）对齐到同一行，裁掉上下多余的透明行"""
    bottoms = [int(np.where(s[..., 3].any(1))[0].max()) for s in segs]
    tops = [int(np.where(s[..., 3].any(1))[0].min()) for s in segs]
    height = max(b - t for b, t in zip(bottoms, tops)) + 3
    out = []
    for s, b in zip(segs, bottoms):
        canvas = np.zeros((height, s.shape[1], 4), np.float32)
        y0 = b + 1 - height
        src = s[max(y0, 0):b + 1]
        canvas[height - src.shape[0]:] = src
        # 岸线最下面一行补满（GPT 偶尔留洞）
        last = canvas[-1]
        holes = last[..., 3] < 0.5
        if holes.any():
            fill = canvas[-2].copy()
            last[holes] = fill[holes]
        out.append(canvas)
    return out


def seam(a_tail, b_head):
    """a 的最后 OVERLAP 列和 b 的最前 OVERLAP 列重叠；返回每行从哪一列起换成 b"""
    h, w = a_tail.shape[:2]
    cost = np.abs(a_tail - b_head).sum(2) + 2.0 * np.abs(a_tail[..., 3] - b_head[..., 3])
    acc = cost.copy()
    back = np.zeros((h, w), np.int32)
    for y in range(1, h):
        for x in range(w):
            lo, hi = max(x - 1, 0), min(x + 2, w)
            k = int(np.argmin(acc[y - 1, lo:hi])) + lo
            back[y, x] = k
            acc[y, x] += acc[y - 1, k]
    xs = np.zeros(h, np.int32)
    xs[-1] = int(np.argmin(acc[-1]))
    for y in range(h - 1, 0, -1):
        xs[y - 1] = back[y, xs[y]]
    return xs, float(acc[-1].min() / h)


def join(a_tail, b_head):
    xs, c = seam(a_tail, b_head)
    out = b_head.copy()
    for y, x in enumerate(xs):
        out[y, :x] = a_tail[y, :x]
    return out, c


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    prev = None
    if "--preview" in sys.argv:
        prev = sys.argv[sys.argv.index("--preview") + 1]
        args = [a for a in args if a != prev]
    srcs = args[:3]
    outdir = args[3] if len(args) > 3 else "assets/scenery/moon_embankment"
    segs = [to_grid(p) for p in srcs]
    segs = align_bottom(quantize(segs))
    O = OVERLAP
    # 循环拼接：s1[O:-O] | 接缝(s1,s2) | s2[O:-O] | 接缝(s2,s3) | s3[O:-O] | 接缝(s3,s1)
    parts, costs = [], []
    n = len(segs)
    for i in range(n):
        a, b = segs[i], segs[(i + 1) % n]
        parts.append(a[:, O:-O])
        j, c = join(a[:, -O:], b[:, :O])
        parts.append(j)
        costs.append(round(c, 3))
    strip = np.concatenate(parts, 1)
    up = np.repeat(np.repeat(strip, CELL, 0), CELL, 1)
    rgba = (np.clip(up, 0, 1) * 255).astype(np.uint8)
    rgba = rgba[..., [2, 1, 0, 3]]          # BGR → RGB
    img = Image.fromarray(rgba, "RGBA")
    buf = io.BytesIO()
    img.save(buf, "WEBP", lossless=True)
    with open(os.path.join(outdir, "castle.webp.b64"), "w") as f:
        f.write(base64.b64encode(buf.getvalue()).decode())
    meta_p = os.path.join(outdir, "layers.json")
    meta = json.load(open(meta_p))
    H, W = rgba.shape[:2]
    meta["castle"] = {"top": HORIZON - H + 2, "size": [W, H], "period": W, "scroll": 0.3, "src": "lake_mid_v1",
                      "seamCost": costs, "reflect": True}
    json.dump(meta, open(meta_p, "w"), ensure_ascii=False, indent=1)
    print("strip", W, "x", H, "top", HORIZON - H + 2, "seam costs", costs)
    if prev:
        os.makedirs(prev, exist_ok=True)
        img.save(os.path.join(prev, "lake_mid_strip.png"))


if __name__ == "__main__":
    main()
