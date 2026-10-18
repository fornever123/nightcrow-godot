#!/usr/bin/env python3
"""找出序列帧里源视频带进来的“横贯画面的直线”（地平线/拖影线），写成擦除矩形。

结果写到 battle.json 的 sprite.assetCleanup = {资源路径: [[x, y, w, h], ...]}（贴图像素坐标），
游戏加载贴图时（art_cache.get_texture）把这些矩形抹成透明。原图不改，可重复运行。

判定：alpha>8 的像素里，竖直方向厚度 < K 的部分做连通块；
块够长（≥120px）、够扁（高 ≤ 26）、够直（逐列中心 y 的标准差 ≤ 3），
并且碰到画面左右边缘或长度 ≥ 画面宽 25% → 视为瑕疵线。
第二遍用 K=48 找“粗光束”（≥400px 长、高 ≤ 48、很直）。
"""
import json, os, sys
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DATA = os.path.join(ROOT, 'assets', 'data', 'battle.json')


def straight_components(mask, k, minlen, maxh, std_max, need_edge_or_frac):
    H, W = mask.shape
    m = mask.astype(np.uint8)
    thick = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((k, 1), np.uint8))
    thin = ((m > 0) & (thick == 0)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(thin, connectivity=8)
    out = []
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if w < minlen or h > maxh:
            continue
        ys, xs = np.where(lab[y:y + h, x:x + w] == i)
        cols = {}
        for cx, cy in zip(xs, ys):
            cols.setdefault(cx, []).append(cy)
        centers = np.array([np.mean(v) for v in cols.values()])
        if centers.std() > std_max:
            continue
        touches = x <= 3 or x + w >= W - 4
        if need_edge_or_frac and not (touches or w >= need_edge_or_frac * W):
            continue
        out.append(lab == i)
    return out


def rects_for(comp, pad=2):
    H, W = comp.shape
    comp = cv2.dilate(comp.astype(np.uint8), np.ones((2 * pad + 1, 2 * pad + 1), np.uint8)) > 0
    xs = np.where(comp.any(0))[0]
    rects = []
    cur = None
    for x in xs:
        col = np.where(comp[:, x])[0]
        y0, y1 = int(col.min()), int(col.max())
        if cur and cur[0] + cur[2] == x and abs(cur[1] - y0) <= 1 and abs(cur[1] + cur[3] - 1 - y1) <= 1:
            cur[2] += 1
            cur[1] = min(cur[1], y0); cur[3] = max(cur[1] + cur[3] - 1, y1) - cur[1] + 1
        else:
            if cur: rects.append(cur)
            cur = [int(x), y0, 1, y1 - y0 + 1]
    if cur: rects.append(cur)
    return rects


def analyse(path):
    a = np.asarray(Image.open(os.path.join(ROOT, 'assets', path)).convert('RGBA'))[..., 3] > 8
    comps = straight_components(a, 17, 120, 26, 3.0, 0.25)
    comps += straight_components(a, 48, 400, 48, 4.0, 0.0)
    rects = []
    for c in comps:
        rects += rects_for(c)
    return rects


def main():
    d = json.load(open(DATA, encoding='utf-8'))
    sp = d['characters'][0]['sprite']
    paths = []
    for name, clip in sp['animations'].items():
        for f in clip.get('frames', []):
            p = f.get('asset')
            if p and p not in paths:
                paths.append(p)
    cleanup = {}
    for p in paths:
        r = analyse(p)
        if r:
            cleanup[p] = r
    sp['assetCleanup'] = cleanup
    with open(DATA, 'w', encoding='utf-8') as fp:
        json.dump(d, fp, ensure_ascii=False, indent=2); fp.write('\n')
    print(f"{len(cleanup)} frames cleaned, {sum(len(v) for v in cleanup.values())} rects")
    if '-v' in sys.argv:
        for p, r in cleanup.items():
            print(os.path.basename(os.path.dirname(p))[:8], os.path.basename(p), len(r))


if __name__ == '__main__':
    main()
