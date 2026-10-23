#!/usr/bin/env python3
"""超远景 v3：用户 GPT 出的像素夜空图 → 游戏里的 星空 sky + 上层云 clouds + 下层云 clouds_low（美术方案 8.6）。
用法：python3 tools/art/make_sky_v3.py [原图.png] [--preview 目录]
  不给原图就用存档 tools/art/src/sky_v3.webp.b64。输出写进 assets/scenery/moon_embankment/，并更新 layers.json。
做法：
 1. 调色：鲜蓝 → 石板灰蓝（pixelize_keyart.lock，LAB 色相 268、彩度 ×0.5）。
 2. 分开云和天空：每行最暗 10% 当天空底色，比它亮 0.06 以上、面积够大的连通块是云；小亮点是星星（丢掉，重新撒）。
 3. 天空：按行取非云像素的平均色 → 分 8 阶 → 4×4 拜耳抖动画成像素渐变；像素格 = 游戏的 2 屏幕像素；星星重新撒。
 4. 云：每朵抠成小图，缩到游戏像素格、颜色归成 5 阶，按原来的高度分上下两层，
    随机间隔、随机左右翻转、首尾绕回，拼成长条：上层一圈 3440、下层一圈 2580 屏幕像素（两层周期不同，合起来很久才重复）。
原图高 887 → 游戏天空高 420 屏幕像素（地平线 417）。
"""
import base64, io, json, os, sys
import cv2, numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from pixelize_keyart import lock

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
OUT = os.path.join(ROOT, 'assets/scenery/moon_embankment')
SRC = os.path.join(os.path.dirname(__file__), 'src/sky_v3.webp.b64')
SKY_H = 420            # 屏幕像素
CELL = 2               # 游戏像素格（屏幕像素）
NH = SKY_H // CELL     # 天空的像素行数 210
SKY_W = 2560           # 星空宽（屏幕像素，镜像重复）
PER_UP, PER_LOW = 3440, 2580
rng = np.random.default_rng(20261021)
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32)


def load(path):
    if path:
        im = cv2.imread(path)
    else:
        im = cv2.imdecode(np.frombuffer(base64.b64decode(open(SRC).read()), np.uint8), cv2.IMREAD_COLOR)
    return im[..., :3].astype(np.float32) / 255


def b64_webp_rgba(arr):  # arr: H×W×4 uint8 RGBA
    buf = io.BytesIO(); Image.fromarray(arr, 'RGBA' if arr.shape[2] == 4 else 'RGB').save(buf, 'WEBP', lossless=True, method=6)
    return base64.b64encode(buf.getvalue()).decode('ascii')


def up(native):  # 像素格放大到屏幕像素
    return cv2.resize(native, None, fx=CELL, fy=CELL, interpolation=cv2.INTER_NEAREST)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    prev = sys.argv[sys.argv.index('--preview') + 1] if '--preview' in sys.argv else None
    if prev and prev in args: args.remove(prev)
    src = load(args[0] if args else None)
    H, W = src.shape[:2]
    im = lock(src)                                             # BGR 0..1
    lum = im @ np.array([0.114, 0.587, 0.299], np.float32)
    ns = NH / H                                                # 原图像素 → 游戏像素格

    # ---- 2. 云 / 星星 / 天空分开 ----
    low = np.percentile(lum, 10, axis=1)
    low = cv2.GaussianBlur(low.reshape(-1, 1), (1, 0), 4).ravel()
    bright = lum - low[:, None]
    cloud_zone = np.arange(H) < int(H * 0.66)
    raw = (bright > 0.06) & cloud_zone[:, None]
    raw = cv2.morphologyEx(raw.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(raw, 8)
    cloud = np.zeros((H, W), bool); stamps = []
    for i in range(1, n):
        x, y, w, h, a = st[i]
        if a < 600:
            continue
        m = lab == i; cloud |= m
        if x <= 1 or x + w >= W - 1:                           # 贴着左右边被切开的云：不当素材
            continue
        stamps.append((x, y, w, h, m[y:y + h, x:x + w]))
    # 贴边被切开的云：原图左右基本能接上，把图横向转半圈，让切口到中间拼成整朵，再抠
    rim = np.roll(im, W // 2, axis=1); rraw = np.roll(raw, W // 2, axis=1)
    n2, lab2, st2, _ = cv2.connectedComponentsWithStats(rraw, 8)
    for i in range(1, n2):
        x, y, w, h, a = st2[i]
        if a < 600 or x <= 1 or x + w >= W - 1 or not (x < W // 2 < x + w):
            continue
        stamps.append((x, y, w, h, lab2[y:y + h, x:x + w] == i, rim))
    stamps = [s if len(s) == 6 else s + (im,) for s in stamps]
    star = (bright > 0.05) & ~cloud & (np.arange(H)[:, None] < int(H * 0.45))
    bad = cv2.dilate((cloud | star).astype(np.uint8), np.ones((9, 9), np.uint8)).astype(bool)

    # ---- 3. 天空渐变 + 抖动 + 星星 ----
    rowcol = np.array([im[y][~bad[y]].mean(0) if (~bad[y]).sum() > 50 else np.full(3, np.nan) for y in range(H)])
    ok = ~np.isnan(rowcol[:, 0]); ys = np.arange(H)
    rowcol = np.stack([np.interp(ys, ys[ok], rowcol[ok, c]) for c in range(3)], 1)
    rowcol = cv2.GaussianBlur(rowcol.reshape(H, 1, 3).astype(np.float32), (1, 0), 6).reshape(H, 3)
    nat = cv2.resize(rowcol.reshape(H, 1, 3), (1, NH), interpolation=cv2.INTER_AREA).reshape(NH, 3)
    nl = nat @ np.array([0.114, 0.587, 0.299], np.float32)
    K = 8
    t = (nl - nl.min()) / max(1e-6, nl.max() - nl.min()) * (K - 1)          # 每行在 8 阶里的位置
    band = np.array([nat[np.argmin(np.abs(t - k))] for k in range(K)])     # 每阶的颜色
    NW = SKY_W // CELL
    bay = (BAYER + 0.5) / 16
    bx = np.tile(bay, (NH // 4 + 1, NW // 4 + 1))[:NH, :NW]
    idx = np.clip(np.floor(t[:, None] + bx), 0, K - 1).astype(int)
    sky = band[idx]                                                          # NH×NW×3 BGR
    # 星星：单点为主，少量十字；只在上 40%
    star_c = np.array([0.93, 0.86, 0.80], np.float32)                       # BGR，偏冷的白
    nstar = int(NW * 28 / (W * ns))
    for _ in range(nstar):
        x = int(rng.integers(2, NW - 2)); y = int(rng.integers(3, int(NH * 0.40)))
        k = rng.random()
        if k < 0.08:      # 十字
            sky[y, x] = star_c
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                sky[y + dy, x + dx] = sky[y + dy, x + dx] * 0.45 + star_c * 0.55
        else:
            a = 0.85 if k < 0.35 else 0.55
            sky[y, x] = sky[y, x] * (1 - a) + star_c * a
    sky_px = up((np.clip(sky, 0, 1) * 255).astype(np.uint8))
    sky_rgb = cv2.cvtColor(sky_px, cv2.COLOR_BGR2RGB)

    # ---- 4. 云：抠图 → 缩到像素格 → 5 阶颜色 → 两层长条 ----
    small = []
    for (x, y, w, h, m, img) in stamps:
        c = img[y:y + h, x:x + w]; a = m.astype(np.float32)
        tw, th = max(2, round(w * ns)), max(2, round(h * ns))
        pa = cv2.resize(a, (tw, th), interpolation=cv2.INTER_AREA)
        pc = cv2.resize(c * a[..., None], (tw, th), interpolation=cv2.INTER_AREA) / np.maximum(pa, 1e-4)[..., None]
        small.append(dict(y=y * ns, c=pc, a=pa >= 0.5, cy=(y + h / 2) / H))
    allc = np.concatenate([s['c'][s['a']] for s in small]).astype(np.float32)
    labc = cv2.cvtColor(allc.reshape(-1, 1, 3), cv2.COLOR_BGR2LAB).reshape(-1, 3)
    _, lb, cen = cv2.kmeans(labc, 5, None, (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 40, 0.1), 5, cv2.KMEANS_PP_CENTERS)
    cenb = cv2.cvtColor(cen.reshape(-1, 1, 3), cv2.COLOR_LAB2BGR).reshape(-1, 3)
    for s in small:
        L = cv2.cvtColor(s['c'].astype(np.float32), cv2.COLOR_BGR2LAB)
        d = ((L[..., None, :] - cen[None, None]) ** 2).sum(-1)
        s['c'] = cenb[np.argmin(d, -1)]
    split = 0.36                                                             # 云心在画面 36% 以上算上层
    ups = [s for s in small if s['cy'] < split]; lows = [s for s in small if s['cy'] >= split]

    def strip(group, period, gap):
        P = period // CELL
        rgba = np.zeros((NH, P, 4), np.float32)
        order = []
        x = 0
        while True:
            if not order:
                order = list(rng.permutation(len(group)))
            s = group[order.pop()]
            w = s['c'].shape[1]
            if x + w * 0.5 > P and x > 0:
                break
            flip = rng.random() < 0.5
            c = s['c'][:, ::-1] if flip else s['c']; a = s['a'][:, ::-1] if flip else s['a']
            y0 = int(round(s['y'] + rng.integers(-3, 4)))
            y0 = int(np.clip(y0, 0, NH - c.shape[0]))
            cols = (np.arange(w) + x) % P
            for j in range(w):
                aj = a[:, j]
                rgba[y0:y0 + c.shape[0], cols[j]][aj] = np.concatenate([c[:, j][aj], np.ones((aj.sum(), 1))], 1)
            x += w + int(rng.integers(gap[0], gap[1]))
        out = np.clip(rgba * 255, 0, 255).astype(np.uint8)
        out = up(out)
        return np.dstack([cv2.cvtColor(out[..., :3], cv2.COLOR_BGR2RGB), out[..., 3]])

    cu = strip(ups, PER_UP, (-10, 60))
    cl = strip(lows, PER_LOW, (-30, 30))

    # ---- 输出 ----
    open(f'{OUT}/sky.webp.b64', 'w').write(b64_webp_rgba(sky_rgb))
    open(f'{OUT}/clouds.webp.b64', 'w').write(b64_webp_rgba(cu))
    open(f'{OUT}/clouds_low.webp.b64', 'w').write(b64_webp_rgba(cl))
    mp = f'{OUT}/layers.json'; meta = json.load(open(mp))
    meta['sky'] = {"size": [SKY_W, SKY_H], "scroll": 0.01, "src": "sky_v3"}
    meta['clouds'] = {"size": [PER_UP, SKY_H], "period": PER_UP, "scroll": 0.05, "drift": 4.0, "src": "sky_v3"}
    meta['clouds_low'] = {"size": [PER_LOW, SKY_H], "period": PER_LOW, "scroll": 0.03, "drift": 2.0, "src": "sky_v3"}
    json.dump(meta, open(mp, 'w'), ensure_ascii=False, indent=1)
    print(f'云：上层 {len(ups)} 朵、下层 {len(lows)} 朵（共抠出 {len(stamps)} 朵）；星星 {nstar} 颗')
    for k in ('sky', 'clouds', 'clouds_low'):
        print(k, meta[k]['size'], os.path.getsize(f'{OUT}/{k}.webp.b64'), 'bytes b64')
    if prev:
        os.makedirs(prev, exist_ok=True)
        base = sky_rgb[:, :1280].astype(np.float32)
        for layer in (cl, cu):
            a = layer[:, :1280, 3:4].astype(np.float32) / 255
            base = base * (1 - a) + layer[:, :1280, :3] * a
        cv2.imwrite(f'{prev}/sky_preview.png', cv2.cvtColor(base.astype(np.uint8), cv2.COLOR_RGB2BGR))
        dbg = (cloud[..., None] * np.array([0, 0, 255]) + star[..., None] * np.array([0, 255, 0]) + (src * 120)).clip(0, 255).astype(np.uint8)
        cv2.imwrite(f'{prev}/mask.jpg', dbg)


if __name__ == '__main__':
    main()
