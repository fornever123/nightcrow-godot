#!/usr/bin/env python3
"""夜景分层 v2（第二轮节点 9，见 docs/HANDOFF-试玩版.md §13）。

把用户的三张原图（1672×941：远景 / 中景洋红底 / 近景洋红底）拆成 8 层，各层视差不同：
  sky       星空 + 银河（云、月亮、月晕都挖掉后补洞）       镜头 ×0.01，镜像重复
  halo      月晕（加色）                                   固定
  moon      月亮圆盘（被云挡住的下半部分用上半部分对称补全）  固定
  clouds    云（GrabCut 分割 + 反混色还原边缘颜色）          ×0.05 + 风飘
  sea       海面（去掉月光带后做成可平铺），着色器里逐行视差 + 程序月光带
  mountains 雪山 + 山丘（避开城堡/钟楼的干净片段拼成无缝条带） ×0.12
  castle    城堡 + 小镇 + 谷雾（桥灯抹掉）                    ×0.3
  bridge    石桥 + 桥灯（按灯距做成严格周期）                  ×0.42
  near      近景步道（沿用 v1 的 near.webp.b64，不重做）       ×1.0
用法：python3 tools/art/make_night_layers_v2.py <远景.png> <中景.png> [输出目录]
"""
import base64, io, json, os, sys
import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_night_layers import key_magenta, load720, make_seamless, min_cut  # noqa: E402

DEBUG = os.environ.get('DEBUG_DIR', '')


def dbg(name, arr):
    if not DEBUG:
        return
    a = np.clip(arr, 0, 1)
    mode = 'RGBA' if a.ndim == 3 and a.shape[2] == 4 else ('RGB' if a.ndim == 3 else 'L')
    Image.fromarray((a * 255).round().astype(np.uint8), mode).save(os.path.join(DEBUG, name + '.png'))


def b64_webp(arr, quality=90, lossless=False):
    a = np.clip(arr, 0, 1)
    mode = 'RGBA' if a.shape[2] == 4 else 'RGB'
    im = Image.fromarray((a * 255).round().astype(np.uint8), mode)
    buf = io.BytesIO()
    im.save(buf, 'WEBP', quality=quality, method=6, lossless=lossless, exact=False)
    return base64.b64encode(buf.getvalue()).decode('ascii')


def to_u8(a):
    return (np.clip(a, 0, 1) * 255).round().astype(np.uint8)


def norm_conv(img, w, sigma):
    num = cv2.GaussianBlur(img * w[..., None], (0, 0), sigma)
    den = cv2.GaussianBlur(w, (0, 0), sigma)
    return num / np.maximum(den[..., None], 1e-6), den


def smooth1d(n, sigma, rng):
    v = rng.standard_normal(n + int(sigma * 8))
    v = cv2.GaussianBlur(v[None, :].astype(np.float32), (0, 0), sigma)[0][int(sigma * 4):int(sigma * 4) + n]
    return v / (np.abs(v).max() + 1e-6)


# ---------------------------------------------------------------- 远景
def far_layers(path, out, meta):
    rgb = np.asarray(Image.open(path).convert('RGB').resize((1280, 720), Image.LANCZOS))
    f = rgb.astype(np.float32) / 255.0
    lum_rows = f.mean(axis=2).mean(axis=1)
    HZ = int(np.argmax(lum_rows[300:500]) + 300)
    H = HZ
    sky = f[:H].copy()
    bgr8 = cv2.cvtColor(rgb[:H], cv2.COLOR_RGB2BGR)
    op8 = cv2.morphologyEx(bgr8, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7)))
    op = cv2.cvtColor(op8, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
    yy, xx = np.mgrid[:H, :1280]

    # 月亮：亮盘拟合圆（只用上半部分边缘，下半部分被云挡住）
    bright = (f[..., :3].min(axis=2) > 0.78)
    bright[:, :900] = False
    bright[300:] = False
    n, lab, st, _ = cv2.connectedComponentsWithStats(bright.astype(np.uint8), 8)
    bright = lab == (1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])))
    ys, xs = np.where(bright)
    top = ys.min()
    edge = []
    for y in range(top, top + 110):
        row = np.where(bright[y])[0]
        if len(row):
            edge += [(row[0], y), (row[-1], y)]
    edge += [(x, top) for x in np.where(bright[top])[0]]
    E = np.array(edge, np.float64)
    A = np.c_[2 * E[:, 0], 2 * E[:, 1], np.ones(len(E))]
    bb = (E ** 2).sum(1)
    cx, cy, c0 = np.linalg.lstsq(A, bb, rcond=None)[0]
    R = float(np.sqrt(c0 + cx ** 2 + cy ** 2))
    print('moon', round(cx, 1), round(cy, 1), 'R', round(R, 1))
    rr = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)

    # 云：GrabCut（种子：亮且偏白 = 云；暗 = 天；银河和月亮 = 天；地平线雾带 = 可能是天）
    lo = op.mean(axis=2)
    Rch = op[..., 0]
    moon = rr < R + 4
    mw = np.zeros((H, 1280), np.uint8)
    cv2.fillPoly(mw, [np.array([(150, 0), (560, 0), (780, 310), (540, 310)], np.int32)], 1)
    mw = mw.astype(bool)
    haze = (yy >= HZ - 95) & (xx >= 540) & (xx <= 1040)
    mask = np.full((H, 1280), cv2.GC_PR_BGD, np.uint8)
    sure = (Rch > 150 / 255) & (lo > 160 / 255) & ~moon & ~mw
    mask[(lo > 120 / 255) & (yy < HZ - 17)] = cv2.GC_PR_FGD
    mask[sure] = cv2.GC_FGD
    mask[(yy >= HZ - 17) & ~haze] = cv2.GC_FGD
    mask[(lo < 70 / 255) & (yy < HZ - 87)] = cv2.GC_BGD
    mask[moon | (mw & ~sure)] = cv2.GC_BGD
    mask[haze & ~sure] = cv2.GC_PR_BGD
    bgm, fgm = np.zeros((1, 65)), np.zeros((1, 65))
    cv2.grabCut(op8, mask, None, bgm, fgm, 6, cv2.GC_INIT_WITH_MASK)
    cm = ((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)).astype(np.uint8)
    n, lab, st, cen = cv2.connectedComponentsWithStats(cm, 8)
    for i in range(1, n):
        if mw[int(cen[i][1]), int(cen[i][0])] or st[i, cv2.CC_STAT_AREA] < 25:
            cm[lab == i] = 0
    n, lab, st, _ = cv2.connectedComponentsWithStats((1 - cm).astype(np.uint8), 4)
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] < 400:
            cm[lab == i] = 1
    cloud = cm.astype(bool)
    if DEBUG:
        ovl = f[:H].copy(); ovl[~cloud] *= 0.35; dbg('far_cloudmask', ovl)

    # 天空底色：去星后的天空，挖掉云/银河/月亮周围，多尺度归一化卷积补出来
    valid = (~cv2.dilate(cm, np.ones((9, 9), np.uint8)).astype(bool)) & ~mw & (rr > 330) & (yy < HZ - 2)
    wv = valid.astype(np.float32)
    B1, W1 = norm_conv(op, wv, 25)
    B2, W2 = norm_conv(op, wv, 80)
    rowmed = np.zeros((H, 3), np.float32)
    have = []
    for y in range(H):
        sel = valid[y]
        if sel.sum() > 30:
            rowmed[y] = np.median(op[y][sel], axis=0)
            have.append(y)
    have = np.array(have)
    for c in range(3):
        rowmed[:, c] = np.interp(np.arange(H), have, rowmed[have, c])
    B3 = np.repeat(rowmed[:, None, :], 1280, axis=1)
    w1 = np.clip(W1 / 0.25, 0, 1)[..., None]
    w2 = np.clip(W2 / 0.25, 0, 1)[..., None]
    B = w1 * B1 + (1 - w1) * (w2 * B2 + (1 - w2) * B3)

    # 月晕：径向中位数（只取天空像素），从 R 往外，330 处收到 0
    hv = (~cv2.dilate(cm, np.ones((7, 7), np.uint8)).astype(bool)) & ~mw & (rr > R + 3) & (rr < 330) & (yy < HZ - 20)
    exc = op - B
    bins = np.arange(int(R) + 2, 331, 3)
    prof = np.zeros((len(bins), 3), np.float32)
    for i, r0 in enumerate(bins):
        sel = hv & (rr >= r0) & (rr < r0 + 3)
        prof[i] = np.median(exc[sel], axis=0) if sel.sum() > 20 else (prof[i - 1] if i else 0)
    prof = np.maximum(prof, 0)
    for i in range(1, len(prof)):
        prof[i] = np.minimum(prof[i], prof[i - 1])
    prof = cv2.GaussianBlur(prof[None], (0, 0), 1.5)[0] if len(prof) > 3 else prof
    taper = np.clip((330 - bins) / 50.0, 0, 1)[:, None]
    prof *= taper

    def halo_at(r):
        out = np.zeros(r.shape + (3,), np.float32)
        for c in range(3):
            out[..., c] = np.interp(r, bins + 1.5, prof[:, c], left=prof[0, c], right=0.0)
        return out

    halo = halo_at(rr)
    print('halo at R+5', np.round(prof[1] * 255), 'at 200', np.round(halo_at(np.array([200.0]))[0] * 255))
    sky_nh = np.clip(sky - halo, 0, 1)

    # 补洞：云 + 月亮（含最亮的一圈月晕）→ 平滑底色（中值去星后按行方向插值）+ 稀疏合成星点
    hole = cv2.dilate(cm, np.ones((5, 5), np.uint8)).astype(bool) | (rr < R + 24)
    med = cv2.cvtColor(cv2.medianBlur(cv2.cvtColor(to_u8(sky_nh), cv2.COLOR_RGB2BGR), 7), cv2.COLOR_BGR2RGB).astype(np.float32) / 255
    vf = ((~cv2.dilate(cm, np.ones((5, 5), np.uint8)).astype(bool)) & ~mw & (rr > R + 24) & (yy < HZ - 1)).astype(np.float32)
    def nca(img, w, sx, sy):
        num = cv2.GaussianBlur(img * w[..., None], (0, 0), sigmaX=sx, sigmaY=sy)
        den = cv2.GaussianBlur(w, (0, 0), sigmaX=sx, sigmaY=sy)
        return num / np.maximum(den[..., None], 1e-6), den
    F1, V1 = nca(med, vf, 30, 3)
    F2, V2 = nca(med, vf, 140, 6)
    rm = np.zeros((H, 3), np.float32)
    hv_ = []
    for y in range(H):
        sel = vf[y] > 0
        if sel.sum() > 20:
            rm[y] = np.median(med[y][sel], axis=0)
            hv_.append(y)
    hv_ = np.array(hv_)
    for c_ in range(3):
        rm[:, c_] = np.interp(np.arange(H), hv_, rm[hv_, c_])
    F3 = np.repeat(rm[:, None, :], 1280, axis=1)
    v1 = np.clip(V1 / 0.3, 0, 1)[..., None]
    v2 = np.clip(V2 / 0.3, 0, 1)[..., None]
    fill = v1 * F1 + (1 - v1) * (v2 * F2 + (1 - v2) * F3)
    fill = cv2.GaussianBlur(fill, (0, 0), 2.0)
    star = np.clip(sky_nh - med, 0, 1)
    star_l = star.mean(axis=2)
    n, lab, st, cen = cv2.connectedComponentsWithStats(((star_l > 0.1) & (vf > 0)).astype(np.uint8), 8)
    patches, prow = [], []
    for i in range(1, n):
        x0, y0, w, h, area = st[i]
        if w <= 6 and h <= 6:
            patches.append(star[max(y0 - 1, 0):y0 + h + 1, max(x0 - 1, 0):x0 + w + 1].copy())
            prow.append(y0)
    prow = np.array(prow)
    rng = np.random.default_rng(20261018)
    hy, hx = np.where(hole)
    nplaced = 0
    for band in range(0, H, 40):
        area_v = vf[band:band + 40].sum()
        cnt = ((prow >= band) & (prow < band + 40)).sum()
        sel = (hy >= band) & (hy < band + 40)
        if area_v < 500 or sel.sum() == 0:
            continue
        nb = int(cnt / area_v * sel.sum())
        idx = np.where(sel)[0]
        for k in rng.choice(idx, size=min(nb, len(idx)), replace=False):
            p_ = patches[rng.integers(len(patches))]
            y0, x0 = hy[k], hx[k]
            h, w = p_.shape[:2]
            if y0 + h < H and x0 + w < 1280:
                fill[y0:y0 + h, x0:x0 + w] += p_
                nplaced += 1
    print('star patches', len(patches), 'placed', nplaced)
    soft = cv2.GaussianBlur(hole.astype(np.float32), (0, 0), 2.0)[..., None]
    soft = np.maximum(soft, (cv2.GaussianBlur((rr < R + 24).astype(np.float32), (0, 0), 7.0) * 1.0)[..., None])
    soft = np.maximum(soft, hole[..., None].astype(np.float32))
    sky_l = np.clip(sky_nh * (1 - soft) + fill * soft, 0, 1)
    # 再往下多 3 行（被海面盖住，防接缝）
    sky_l = np.concatenate([sky_l, np.repeat(sky_l[-1:], 3, axis=0)], axis=0)
    dbg('sky', sky_l)
    open(f'{out}/sky.webp.b64', 'w').write(b64_webp(sky_l, 90))
    meta['sky'] = {"size": [1280, int(sky_l.shape[0])], "scroll": 0.01}

    # 月晕贴图（加色）：只存半径 330 内
    HS = 332
    gy, gx = np.mgrid[:HS * 2, :HS * 2]
    gr = np.sqrt((gx - HS + 0.5) ** 2 + (gy - HS + 0.5) ** 2)
    hal = halo_at(gr)
    hal[gr < R - 2] = halo_at(np.array([R + 2.0]))[0]
    dbg('halo', hal * 3)
    open(f'{out}/halo.webp.b64', 'w').write(b64_webp(hal, 92))
    meta['halo'] = {"size": [HS * 2, HS * 2]}

    # 月亮圆盘：下半部分（被云遮住）用上半部分对称补
    MS = int(np.ceil(R)) + 3
    my, mx = np.mgrid[-MS:MS, -MS:MS].astype(np.float32) + 0.5
    mr = np.sqrt(mx ** 2 + my ** 2)
    def samp(xs_, ys_):
        return np.dstack([cv2.remap(f[..., c], xs_.astype(np.float32), ys_.astype(np.float32), cv2.INTER_LINEAR) for c in range(3)])
    rin = np.minimum(mr, R - 1.8) / np.maximum(mr, 1e-3)
    sx, sy = cx + mx * rin, cy + my * rin
    col = samp(sx, sy)
    mir = samp(sx, cy - (sy - cy))
    wv_ = np.clip((my - 34) / 14.0, 0, 1)[..., None]
    col = col * (1 - wv_) + mir * wv_
    ma = np.clip(R + 0.5 - mr, 0, 1)[..., None]
    moon_rgba = np.concatenate([col, ma], axis=2)
    dbg('moon', moon_rgba)
    open(f'{out}/moon.webp.b64', 'w').write(b64_webp(moon_rgba, 94))
    meta['moon'] = {"center": [round(float(cx), 1), round(float(cy), 1)], "radius": round(R, 1), "size": [MS * 2, MS * 2]}

    # 云：软边 + 反混色（背景 = 补好的天空 + 月晕）
    a = cv2.GaussianBlur(cm.astype(np.float32), (0, 0), 0.8)
    a *= np.clip((rr - R - 2) / 12.0, 0, 1)
    bg = np.clip(sky_l[:H] + halo, 0, 1)
    C = (f[:H] - (1 - a[..., None]) * bg) / np.maximum(a[..., None], 0.05)
    C = np.clip(C, 0, 1)
    a[a < 0.04] = 0
    # 左右两端被原图边框切断的云：带噪声的渐隐
    for side in (0, 1):
        nb = smooth1d(H, 10, rng)
        xb = 70 + 34 * nb
        dist = xx if side == 0 else (1279 - xx)
        a *= np.clip((dist - (xb[:, None] - 45)) / 90.0, 0, 1)
    GAP = 440
    W = 1280 + GAP
    cl = np.zeros((H, W, 4), np.float32)
    cl[:, :1280, :3] = C
    cl[:, :1280, 3] = a
    # 透明处颜色取邻近的云色（避免线性过滤时边缘发黑）
    dil = cv2.dilate(cl[..., :3], np.ones((3, 3), np.uint8))
    cl[..., :3] = np.where(cl[..., 3:4] > 0.02, cl[..., :3], dil)
    dbg('clouds', cl)
    open(f'{out}/clouds.webp.b64', 'w').write(b64_webp(cl, 90))
    meta['clouds'] = {"size": [W, H], "period": W, "scroll": 0.05, "drift": 3.0}

    # 海面：去掉月光带（用左边一段替换，两边交叉淡化），再做成可平铺
    sea = f[HZ:].copy()
    prof_c = cv2.GaussianBlur(sea[60:].mean(axis=2).mean(axis=0)[None], (0, 0), 10)[0]
    bx = int(np.argmax(prof_c[700:1200]) + 700)
    b0, b1 = bx - 135, min(bx + 135, 1279)
    shift = -(b1 - b0) - 10
    t = np.ones(1280, np.float32) * 0
    ramp = 26
    for x in range(b0 - ramp, b1 + 1):
        if 0 <= x < 1280:
            t[x] = np.clip((x - (b0 - ramp)) / ramp, 0, 1) if x < b0 else (np.clip((b1 + 0 - x) / ramp, 0, 1) if x > b1 - ramp else 1.0)
    src = np.roll(sea, -shift, axis=1)
    sea2 = sea * (1 - t[None, :, None]) + src * t[None, :, None]
    # 水波是横向条纹，用很宽的线性交叉淡化做周期（不会像切缝那样留下竖向的明暗边）
    OVS = 256
    P = 1280 - OVS
    tw = np.linspace(0, 1, OVS, dtype=np.float32)[None, :, None]
    tile = sea2[:, :P].copy()
    tile[:, :OVS] = sea2[:, P:P + OVS] * (1 - tw) + sea2[:, :OVS] * tw
    tile = np.concatenate([tile, np.ones(tile.shape[:2] + (1,), np.float32)], axis=2)
    info = {"period": P, "match": 0.0}
    dbg('sea', tile[..., :3])
    open(f'{out}/sea.webp.b64', 'w').write(b64_webp(tile[..., :3], 88))
    meta['sea'] = {"top": HZ, "size": [int(tile.shape[1]), int(tile.shape[0])], "period": int(info['period']),
                   "bandX": int(bx), "match": info['match']}
    meta['far'] = {"size": [1280, 720], "horizonY": HZ}
    print('sea band x', bx, 'period', info['period'])
    return HZ


# ---------------------------------------------------------------- 中景
def mid_layers(path, out, meta):
    rgba = key_magenta(load720(path))
    H, W = rgba.shape[:2]
    alpha = rgba[..., 3]
    s = 0.7651
    bgr = cv2.cvtColor(to_u8(rgba[..., :3]), cv2.COLOR_RGB2BGR)
    yy, xx = np.mgrid[:H, :W]
    top = np.argmax(alpha > 0.5, axis=0)
    rows = np.where(alpha.max(axis=1) > 0.02)[0]
    TOP, BOT = int(rows.min()), int(rows.max())
    # 桥栏顶（最亮的那一行之后变暗）与桥灯
    med = np.median(rgba[..., :3].mean(axis=2), axis=1)
    RAIL = int(np.argmax(med[BOT - 40:BOT - 10]) + BOT - 40) + 1
    c = rgba[..., :3]
    org = (c[..., 0] > 0.75) & (c[..., 1] > 0.5) & (c[..., 2] < 0.6)
    colsum = org[RAIL - 22:RAIL - 4].sum(axis=0)
    xs = np.where(colsum > 0)[0]
    groups = []
    for x in xs:
        if groups and x - groups[-1][-1] <= 2:
            groups[-1].append(x)
        else:
            groups.append([x])
    cent = np.array([np.mean(g) for g in groups])
    # 灯距：等距直线拟合（排除小镇窗户这类误检），再用实际检测到的灯心
    best = None
    for sp in np.arange(59.0, 62.0, 0.01):
        ph = np.median(np.mod(cent, sp))
        d = np.abs(((cent - ph + sp / 2) % sp) - sp / 2)
        inl = d < 4
        if best is None or inl.sum() > best[0] or (inl.sum() == best[0] and d[inl].mean() < best[3]):
            best = (inl.sum(), sp, ph, d[inl].mean())
    _, SP, PH = best[:3]
    inl = np.abs(((cent - PH + SP / 2) % SP) - SP / 2) < 4
    k = np.round((cent[inl] - PH) / SP).astype(int)
    SP, PH = np.polyfit(k, cent[inl], 1)
    real = dict(zip(k.tolist(), cent[inl].tolist()))
    print('rail', RAIL, 'lamp spacing', round(SP, 3), 'phase', round(PH, 2), 'inliers', int(inl.sum()))
    lamps = [real.get(i, PH + SP * i) for i in range(-1, int(W / SP) + 2)]
    lampmask = np.zeros((H, W), np.float32)
    LTOP = RAIL - 20
    for lx in lamps:
        for y in range(LTOP, RAIL):
            hw = 4.2 if y < RAIL - 5 else 1.8   # 灯头宽、灯杆细
            lampmask[y] = np.maximum(lampmask[y], np.clip(hw + 0.5 - np.abs(xx[y] - lx), 0, 1))

    # 山 / 前景（城堡、小镇、谷雾）分割
    mask = np.full((H, W), cv2.GC_PR_BGD, np.uint8)
    mask[alpha < 0.5] = cv2.GC_BGD
    def box(x0, x1, y0, y1, v):
        mask[int(y0 * s):int(y1 * s), int(x0 * s):int(x1 * s)] = v
    mask[(yy > 455 * s) & (alpha >= 0.5)] = cv2.GC_PR_FGD
    mask[yy > 495 * s] = cv2.GC_FGD
    ridge = (yy >= top[None, :]) & (yy < top[None, :] + 22) & (alpha >= 0.5)
    castle = np.zeros((H, W), bool)
    for x0, x1, y0, y1 in [(555, 925, 230, 560), (1290, 1338, 355, 560), (425, 450, 395, 560)]:
        castle[int(y0 * s):int(y1 * s), int(x0 * s):int(x1 * s)] = True
    mask[ridge & ~castle] = cv2.GC_BGD
    box(585, 905, 395, 500, cv2.GC_FGD)
    box(1297, 1328, 385, 500, cv2.GC_FGD)
    lumc = c.mean(axis=2)
    br = c[..., 2] - c[..., 0]
    snow = castle & (yy < int(430 * s)) & (br > 0.28) & (lumc > 0.42) & (alpha > 0.5)
    mask[snow] = cv2.GC_BGD
    facade = castle & (((br < 0.16) & (lumc > 0.3)) | ((c[..., 0] > c[..., 2]) & (lumc > 0.3))) & (alpha > 0.5)
    mask[facade & ~snow] = cv2.GC_FGD
    bgm, fgm = np.zeros((1, 65)), np.zeros((1, 65))
    cv2.grabCut(bgr, mask, None, bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    fg = (((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)) & (alpha >= 0.5)).astype(np.uint8)
    bgk = ((1 - fg) * (alpha >= 0.5)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(bgk, connectivity=4)
    small = [i for i in range(1, n) if st[i, cv2.CC_STAT_AREA] < 700]
    fg[np.isin(lab, small) & castle] = 1
    fg[yy >= RAIL - 8] = 1
    fgf = fg.astype(np.float32)

    # ---- 桥：从一盏灯到第 8 盏灯，横向微调到整数周期
    NL = 8
    runs = [i for i in sorted(real) if all((i + j) in real for j in range(NL + 1))]
    i0 = min(runs, key=lambda i: np.std(np.diff([real[i + j] for j in range(NL + 1)])))
    l0, l1 = real[i0], real[i0 + NL]
    P = int(round(l1 - l0))
    SPN = (l1 - l0) / NL
    print('bridge tile lamps', i0, round(l0, 1), round(l1, 1), 'P', P)
    BT = LTOP - 2
    bh = BOT + 1 - BT
    xs_src = l0 + np.arange(P + 24) * ((l1 - l0) / P)
    ys_src = np.arange(BT, BOT + 1).astype(np.float32)
    mx_, my_ = np.meshgrid(xs_src.astype(np.float32), ys_src)
    def rs(img):
        return cv2.remap(img, mx_, my_, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    br_rgb = np.dstack([rs(rgba[..., i]) for i in range(3)])
    br_a = np.ones((bh, P + 24), np.float32)
    lm = rs(lampmask)
    above = (ys_src < RAIL)[:, None]
    br_a = np.where(above, lm, br_a)
    # 周期接缝：末尾多出的 24 列淡入到开头
    tt = np.linspace(0, 1, 24, dtype=np.float32)[None, :, None]
    br_rgb[:, :24] = br_rgb[:, P:P + 24] * (1 - tt) + br_rgb[:, :24] * tt
    br_a[:, :24] = br_a[:, P:P + 24] * (1 - tt[..., 0]) + br_a[:, :24] * tt[..., 0]
    bridge = np.dstack([br_rgb[:, :P], br_a[:, :P]])
    dbg('bridge', bridge)
    open(f'{out}/bridge.webp.b64', 'w').write(b64_webp(bridge, 92))
    meta['bridge'] = {"top": BT, "size": [P, bh], "period": P, "scroll": 0.42, "railY": RAIL,
                      "lamps": [round((real[i0 + j] - l0) * P / (l1 - l0), 2) for j in range(NL)], "lampY": RAIL - 13}

    # ---- 城堡层：前景像素；桥灯抹掉；桥栏以下 8 行保留（被桥挡住）
    CB = RAIL + 8
    ct = rgba[:CB].copy()
    lmk = (cv2.dilate((lampmask[:CB] > 0.02).astype(np.uint8), np.ones((5, 5), np.uint8)) > 0)
    lmk[:LTOP - 3] = False
    inp = cv2.inpaint(to_u8(ct[..., :3]), lmk.astype(np.uint8), 5, cv2.INPAINT_TELEA).astype(np.float32) / 255
    ct[..., :3] = np.where(lmk[..., None], inp, ct[..., :3])
    ca = cv2.GaussianBlur(fgf[:CB], (0, 0), 0.7) * ct[..., 3]
    ca[RAIL - 8:] = 1.0
    ct[..., 3] = ca
    crop = ct[TOP - 1:]
    tile, info = make_seamless(crop)
    dbg('castle', tile)
    open(f'{out}/castle.webp.b64', 'w').write(b64_webp(tile, 90))
    meta['castle'] = {"top": TOP - 1, "size": [int(tile.shape[1]), int(tile.shape[0])], "period": info['period'],
                      "scroll": 0.3, "match": info['match']}

    # ---- 山层：避开城堡/钟楼的三段干净片段，前景盖住的部分往下延伸并融进谷雾
    MB = RAIL - 4
    mt = rgba[:MB].copy()
    bga = (1 - fgf[:MB]) * mt[..., 3]
    known = bga > 0.5
    fogc = np.array([0.56, 0.64, 0.84], np.float32)
    filled = mt[..., :3].copy()
    for y in range(1, MB):
        hole = ~known[y] & (y > top)
        if hole.any():
            prev = cv2.GaussianBlur(filled[y - 1][None], (0, 0), 5.0)[0]
            depth = np.clip((y - top) / 60.0, 0, 1)
            k = 0.10 + 0.06 * depth
            filled[y, hole] = prev[hole] * (1 - k[hole, None]) + fogc * k[hole, None]
    m_rgba = np.dstack([filled, np.where(yy[:MB] > top[None, :], 1.0, mt[..., 3])])
    m_rgba[..., 3] = np.where(yy[:MB] >= top[None, :] + 2, 1.0, mt[..., 3])
    segs = [(0, int(555 * s)), (int(930 * s), int(1285 * s)), (int(1342 * s), W)]
    parts = [m_rgba[:, a_:b_] for a_, b_ in segs]
    OV = 36
    def join(A, Bm):
        pa = np.dstack([A[..., :3] * A[..., 3:], A[..., 3:]])
        pb = np.dstack([Bm[..., :3] * Bm[..., 3:], Bm[..., 3:]])
        best = None
        for ta in range(OV, min(120, A.shape[1] - OV)):
            for tb in range(0, min(90, Bm.shape[1] - OV), 2):
                d = ((pa[:, A.shape[1] - ta:A.shape[1] - ta + OV] - pb[:, tb:tb + OV]) ** 2).sum(axis=2)
                sc = float(d.mean())
                if best is None or sc < best[0]:
                    best = (sc, ta, tb)
        sc, ta, tb = best
        aa = A[:, :A.shape[1] - ta + OV]
        bb_ = Bm[:, tb:]
        cost = ((pa[:, A.shape[1] - ta:A.shape[1] - ta + OV] - pb[:, tb:tb + OV]) ** 2).sum(axis=2)
        seam, _ = min_cut(cost)
        cols = np.arange(OV)[None, :]
        tw = np.clip((cols - seam[:, None] + 3) / 6.0, 0, 1)[..., None]
        blend = aa[:, -OV:] * (1 - tw) + bb_[:, :OV] * tw
        return np.concatenate([aa[:, :-OV], blend, bb_[:, OV:]], axis=1), round(sc, 4)
    strip, s1 = join(parts[0], parts[1])
    strip, s2 = join(strip, parts[2])
    tile_m, info_m = make_seamless(strip, ov=OV, p_min=int(strip.shape[1] * 0.85))
    print('mountain joins', s1, s2, info_m)
    mtop = int(top.min()) - 1
    tile_m = tile_m[mtop:]
    dbg('mountains', tile_m)
    open(f'{out}/mountains.webp.b64', 'w').write(b64_webp(tile_m, 90))
    meta['mountains'] = {"top": mtop, "size": [int(tile_m.shape[1]), int(tile_m.shape[0])], "period": info_m['period'],
                         "scroll": 0.12}
    if DEBUG:
        ov = bgr.copy()
        ov[fg == 0] = (ov[fg == 0] * 0.4).astype(np.uint8)
        cv2.imwrite(os.path.join(DEBUG, 'mid_fg.png'), ov[TOP:])


def main():
    far_p, mid_p = sys.argv[1:3]
    out = sys.argv[3] if len(sys.argv) > 3 else 'assets/scenery/moon_embankment'
    os.makedirs(out, exist_ok=True)
    mp = os.path.join(out, 'layers.json')
    old = json.load(open(mp)) if os.path.exists(mp) else {}
    meta = {"version": 2}
    far_layers(far_p, out, meta)
    mid_layers(mid_p, out, meta)
    if 'near' in old:
        meta['near'] = old['near']
    json.dump(meta, open(mp, 'w'), indent=1, ensure_ascii=False)
    for k in ['sky', 'halo', 'moon', 'clouds', 'sea', 'mountains', 'castle', 'bridge']:
        print(k, meta[k].get('size'), os.path.getsize(f'{out}/{k}.webp.b64'), 'bytes b64')


if __name__ == '__main__':
    main()
