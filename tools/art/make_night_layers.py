#!/usr/bin/env python3
"""夜景三层图 → 试玩关卡用的无缝图层（节点 4，见 docs/HANDOFF-试玩版.md §5/§11）。

输入：用户用 GPT 出的三张 1672×941 原图（远景 / 中景洋红底 / 近景洋红底）。
输出：assets/scenery/moon_embankment/{far,mid,near}.webp.b64
      （GitHub 推送通道只能传文本，所以存 base64；运行时 night_backdrop.gd 解码）
做法：
  1. 统一缩放到 720 高（与游戏画面 1280×720 1:1）。
  2. 洋红抠图（去溢色），裁到有内容的行。
  3. 无缝：在 [P_MIN, W-OV] 里找周期 P，使 [P, P+OV) 与 [0, OV) 最像；
     重叠区用最小误差竖向切缝（image quilting）拼接，切缝两侧再羽化 2px。
     图块宽 = P，横向重复贴图即可无缝滚动。
用法：python3 tools/art/make_night_layers.py <远景.png> <中景.png> <近景.png> [输出目录]
"""
import base64, io, json, sys, os
import numpy as np
from PIL import Image, ImageFilter

K = np.array([1.0, 0.0, 1.0], np.float32)


def key_magenta(rgb):
    c = rgb.astype(np.float32) / 255.0
    m = np.minimum(c[..., 0], c[..., 2]) - c[..., 1]
    a = 1.0 - np.clip((m - 0.22) / (0.62 - 0.22), 0.0, 1.0)
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3)), np.float32) / 255.0
    f = (c - (1.0 - a[..., None]) * K) / np.maximum(a[..., None], 1e-3)
    f = np.clip(f, 0.0, 1.0)
    sp = np.clip(np.minimum(f[..., 0], f[..., 2]) - f[..., 1], 0.0, None)
    f[..., 0] -= sp
    f[..., 2] -= sp
    f = np.clip(f, 0.0, 1.0)
    # 半透明边缘去绿边：反算颜色时 G 会被放大，夜景里 G 不该超过 max(R, B)
    edge = a < 0.95
    f[..., 1] = np.where(edge, np.minimum(f[..., 1], np.maximum(f[..., 0], f[..., 2])), f[..., 1])
    f[a <= 0.003] = 0.0
    return np.dstack([f, a])


def load720(path):
    im = Image.open(path).convert('RGB')
    w = round(im.width * 720 / im.height)
    return np.asarray(im.resize((w, 720), Image.LANCZOS))


def min_cut(cost):
    """cost: (H, OV) → 每行切缝列号（左边取 A，右边取 B）"""
    h, w = cost.shape
    acc = cost.copy()
    back = np.zeros((h, w), np.int32)
    for y in range(1, h):
        prev = acc[y - 1]
        l = np.r_[np.inf, prev[:-1]]
        r = np.r_[prev[1:], np.inf]
        stack = np.vstack([l, prev, r])
        idx = np.argmin(stack, axis=0)
        acc[y] += stack[idx, np.arange(w)]
        back[y] = np.arange(w) + idx - 1
    seam = np.zeros(h, np.int32)
    seam[-1] = int(np.argmin(acc[-1]))
    for y in range(h - 1, 0, -1):
        seam[y - 1] = back[y, seam[y]]
    return seam, float(acc[-1].min())


def make_seamless(rgba, ov=120, p_min=None):
    h, w, _ = rgba.shape
    p_min = p_min or int(w * 0.8)
    a = rgba[..., 3:4]
    prem = np.concatenate([rgba[..., :3] * a, a], axis=2)  # 预乘后比较，透明区不计颜色
    head = prem[:, :ov]
    best = None
    for p in range(p_min, w - ov + 1):
        d = ((prem[:, p:p + ov] - head) ** 2).sum(axis=2)
        score = float(d.mean())
        if best is None or score < best[0]:
            best = (score, p)
    p = best[1]
    cost = ((prem[:, p:p + ov] - head) ** 2).sum(axis=2)
    seam, total = min_cut(cost)
    cols = np.arange(ov)[None, :]
    # 软切缝：seam 左边用尾段（衔接上一块的末尾），右边用开头
    t = np.clip((cols - seam[:, None] + 2) / 4.0, 0.0, 1.0)[..., None]
    blend = rgba[:, p:p + ov] * (1 - t) + rgba[:, :ov] * t
    tile = rgba[:, :p].copy()
    tile[:, :ov] = blend
    return tile, {"period": int(p), "overlap": ov, "match": round(best[0], 5), "seamCost": round(total, 3)}


def to_b64_webp(rgba, quality, lossless=False):
    im = Image.fromarray((np.clip(rgba, 0, 1) * 255).round().astype(np.uint8), 'RGBA' if rgba.shape[2] == 4 else 'RGB')
    buf = io.BytesIO()
    im.save(buf, 'WEBP', quality=quality, method=6, lossless=lossless, exact=False)
    return base64.b64encode(buf.getvalue()).decode('ascii'), im


def main():
    far_p, mid_p, near_p = sys.argv[1:4]
    out = sys.argv[4] if len(sys.argv) > 4 else 'assets/scenery/moon_embankment'
    os.makedirs(out, exist_ok=True)
    meta = {}
    # 远景：不抠，固定在屏幕上（裁成 1280 宽，居中）
    far = np.asarray(Image.open(far_p).convert('RGB').resize((1280, 720), Image.LANCZOS)).astype(np.float32) / 255.0
    lum = far.mean(axis=2).mean(axis=1)
    band = slice(300, 500)
    horizon = int(np.argmax(lum[band]) + band.start)
    b64, _ = to_b64_webp(far, 88)
    open(f'{out}/far.webp.b64', 'w').write(b64)
    meta['far'] = {"size": [1280, 720], "horizonY": horizon}
    for name, path, q in [('mid', mid_p, 90), ('near', near_p, 92)]:
        rgba = key_magenta(load720(path))
        rows = np.where(rgba[..., 3].max(axis=1) > 0.02)[0]
        y0, y1 = int(rows.min()) - 2, int(rows.max()) + 3
        crop = rgba[max(y0, 0):y1]
        tile, info = make_seamless(crop)
        b64, im = to_b64_webp(tile, q)
        open(f'{out}/{name}.webp.b64', 'w').write(b64)
        im.save(f'/tmp/{name}_tile.png')
        Image.fromarray((np.clip(crop, 0, 1) * 255).astype(np.uint8), 'RGBA').save(f'/tmp/{name}_crop.png')
        info.update({"top": max(y0, 0), "size": [int(tile.shape[1]), int(tile.shape[0])]})
        meta[name] = info
    json.dump(meta, open(f'{out}/layers.json', 'w'), indent=1)
    print(json.dumps(meta, ensure_ascii=False))
    for n in ['far', 'mid', 'near']:
        print(n, os.path.getsize(f'{out}/{n}.webp.b64'), 'bytes b64')


if __name__ == '__main__':
    main()
