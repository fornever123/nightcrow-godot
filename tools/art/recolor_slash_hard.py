"""刀光收硬边（光线 / 特效会话 2026-10-31，项目进程 §3.2 攻击特效 A）：recolor_slash.py 的硬边版。
识别、尘土、冲刺尾迹、写帧都沿用 recolor_slash.py，只换刀光的上色：
  - 色阶不再平滑渐变，分成 白芯 / 亮紫 / 紫 / 深紫 四阶硬边（赛璐璐）；
  - 内侧不再半透明淡出，而是按“干笔”锯齿硬切掉（原图越灰 = 画师画的收尾越细）；
  - 去掉外侧紫晕（运行时的刀光辉光另外收紧，见 impact_fx.gd glow_*）。
用法（Windows 用户目录的 Python，-I 运行）：
  python -I tools/art/recolor_slash_hard.py preview [过滤词...]   预览到 .runtime/recolor_hard/
  python -I tools/art/recolor_slash_hard.py write   [过滤词...]   覆盖 assets/image/fixed-fx/ 的修复帧
回滚：python -I tools/art/recolor_slash.py write（旧的柔边版）。"""
import json, os, sys
import numpy as np, cv2
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import recolor_slash as R

hexc = R.hexc
CORE = hexc('f4f0ff')      # 外缘白芯
BANDS = [                  # (u 上限, 颜色)：u = 0 外缘 → 1 内缘
    (0.13, hexc('c6b4ff')),
    (0.50, hexc('a487ff')),
    (1.01, hexc('7656ea')),
]
STRIPE = hexc('6447d6')    # 紫带里的硬边刷痕
CORE_PX = 5.5              # 白芯宽（原图像素；原图约 0.17–0.49 倍显示，屏幕上 1–3 像素）
CUT_U = 0.74               # 内侧在 u 到这里附近硬切
CUT_JAG = 0.13             # 干笔锯齿幅度
CUT_MIN = 0.3              # 原图最灰（收尾）处只留外缘这么宽


def recolor_hard(D, slash, dust, stray=None, seed=0, wake_y=None, solid_fx=None):
    P = R.PAD
    Dp = cv2.copyMakeBorder(D, P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    S = cv2.copyMakeBorder(slash.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    U = cv2.copyMakeBorder(dust.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    if stray is not None and stray.any():
        Dp[cv2.copyMakeBorder(stray.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0) > 0] = 0
    out = Dp.astype(np.float32) / 255.0
    rgb0 = Dp[..., :3].astype(np.float32); a0 = Dp[..., 3].astype(np.float32) / 255
    lum = rgb0.max(-1)
    if U.any():
        t = np.clip((lum - 100) / 140, 0, 1)[..., None]
        col = np.where(t > 0.5, R.DUST * (2 - 2 * t) + R.DUST_L * (2 * t - 1), R.DUST_D * (1 - 2 * t) + R.DUST * (2 * t))
        m = U > 0
        out[m, :3] = col[m] / 255
        out[m, 3] = a0[m] * R.DUST_A
    if not S.any():
        return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)
    # ---- 几何：和 recolor_slash.recolor 一样（补半透明边 → 磨圆台阶 → 凸包分内外缘 → u）
    ch = rgb0.max(-1) - rgb0.min(-1)
    near = cv2.dilate(S, np.ones((3, 3), np.uint8)) > 0
    fringe = near & (Dp[..., 3] > 0) & (((Dp[..., 3] < 250) & (ch < 60)) | (ch < 36))
    near = cv2.dilate(((S > 0) | fringe).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    fringe |= near & (Dp[..., 3] > 0) & (ch < 36)
    S = ((S > 0) | fringe).astype(np.uint8)
    raw = S > 0
    sm = cv2.GaussianBlur(S.astype(np.float32), (0, 0), 3.2) > 0.5
    S = (sm & (raw | (Dp[..., 3] < 24))).astype(np.uint8)
    out[raw & (S == 0)] = 0
    Sfull = S
    S = (cv2.GaussianBlur(S.astype(np.float32), (0, 0), 5.5) > 0.5).astype(np.uint8)
    if S.sum() < 0.3 * Sfull.sum():
        S = Sfull
    grp = cv2.morphologyEx(S, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, lab = cv2.connectedComponents(grp, connectivity=8)
    hull = np.zeros_like(S)
    for i in range(1, n):
        ys, xs = np.nonzero(lab == i)
        if len(xs) < 30: continue
        cv2.fillConvexPoly(hull, cv2.convexHull(np.stack([xs, ys], 1).astype(np.int32)), 1)
    border = (S > 0) & (cv2.erode(S, np.ones((3, 3), np.uint8)) == 0)
    d_hull_out = cv2.distanceTransform((hull > 0).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    outer = border & (d_hull_out <= 4)
    inner = border & ~outer
    big = 1e4
    da = cv2.distanceTransform((~outer).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE) if outer.any() else np.full(S.shape, big, np.float32)
    db = cv2.distanceTransform((~inner).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE) if inner.sum() > 40 else None
    dm = cv2.distanceTransform(S, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    if db is None:
        thick = cv2.dilate(dm, np.ones((31, 31), np.uint8)) + 1e-3
        u = 0.5 * (1 - np.clip(dm / thick, 0, 1))
    else:
        u = da / np.maximum(da + db, 1e-3)
    u = np.clip(u, 0, 1)
    d_geo = cv2.distanceTransform((S == 0).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    thin = (Sfull > 0) & (d_geo > 2.5)
    u = np.where(thin, 0.12, u); da = np.where(thin, np.minimum(da, 4.0), da)
    S = Sfull
    m = S > 0
    # ---- 噪声（沿外缘方向变化：da 加低频扰动当“沿弧坐标”的替身）
    rng = np.random.default_rng(seed)
    def lowfreq(sig):
        z = cv2.GaussianBlur(rng.standard_normal(S.shape).astype(np.float32), (0, 0), sig)
        return z / (np.abs(z).max() + 1e-6)
    # 原图有多亮：画师画的收尾（灰）→ 刀光变细，不变透明
    Sf = (raw & (Dp[..., 3] > 200)).astype(np.float32)
    lum_s = cv2.GaussianBlur(lum * Sf, (0, 0), 5) / np.maximum(cv2.GaussianBlur(Sf, (0, 0), 5), 1e-3)
    lum_t = np.clip((lum_s - 95) / 120, 0, 1)
    cut = (CUT_MIN + (CUT_U - CUT_MIN) * lum_t) + lowfreq(7) * CUT_JAG + lowfreq(2.5) * CUT_JAG * 0.5
    keep = m & ((u <= cut) | thin)
    # 干笔边只要大锯齿：补掉小洞、去掉孤立的小碎块
    keep = cv2.morphologyEx(keep.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    keep = cv2.morphologyEx(keep, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    nk, lk, sk, _ = cv2.connectedComponentsWithStats(keep, connectivity=8)
    for i in range(1, nk):
        if sk[i, 4] < 60:
            keep[lk == i] = 0
    keep = (keep > 0) & m
    # ---- 四阶硬边上色
    col = np.zeros(S.shape + (3,), np.float32)
    lo = 0.0
    for hi, c in BANDS:
        col[(u >= lo) & (u < hi)] = c
        lo = hi
    # 刷痕：和外缘平行的细长硬条（沿外缘的距离 da 加低频扰动取噪声），时有时无
    rv = rng.random(4096).astype(np.float32)
    q = np.clip((da + lowfreq(30) * 9.0) / 5.5, 0, 4094)
    qi = np.floor(q).astype(np.int32); qf = q - qi
    n1 = rv[qi] * (1 - qf) + rv[qi + 1] * qf
    stripe = (n1 > 0.72) & (lowfreq(18) > -0.1) & (u > 0.24) & (u < 0.62)
    col[stripe] = STRIPE
    core_w = CORE_PX * (0.55 + 0.45 * lum_t) * (1.0 + 0.25 * lowfreq(12))
    col[da < core_w] = CORE
    alpha = np.clip(a0 * 1.1, 0, 1)
    # 冲刺斩尾迹：贴地那截渐变成尘土（沿用旧版）
    if wake_y is not None:
        yy = np.arange(S.shape[0], dtype=np.float32)[:, None] + np.zeros((1, S.shape[1]), np.float32)
        z = np.clip((yy - (wake_y + P - R.WAKE_TOP - R.WAKE_W / 2)) / R.WAKE_W, 0, 1)
        wd = z * z * (3 - 2 * z)
        tt = np.clip((lum - 100) / 140, 0, 1)[..., None]
        dcol = np.where(tt > 0.5, R.DUST * (2 - 2 * tt) + R.DUST_L * (2 * tt - 1), R.DUST_D * (1 - 2 * tt) + R.DUST * (2 * tt))
        col = col * (1 - wd[..., None]) + dcol * wd[..., None]
        alpha = alpha * (1 - wd) + np.clip(a0, 0, 1) * R.DUST_A * wd
        keep = keep | (m & (wd > 0.5))
    if solid_fx is not None and solid_fx.any():
        sf = cv2.copyMakeBorder(solid_fx.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0) > 0
        alpha = np.where(sf, np.maximum(alpha, np.clip(a0, 0, 1) * 0.97), alpha)
    # 只做 1 像素以内的抗锯齿（原图缩到屏幕 0.17–0.49 倍，再硬就闪）
    edge = cv2.GaussianBlur(keep.astype(np.float32), (0, 0), 0.7)
    edge_a = np.clip((edge - 0.5) * 2.2 + 0.5, 0, 1)
    out[m, :3] = col[m] / 255
    out[m, 3] = alpha[m] * edge_a[m]
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)


def process(cfg, asset):
    sprite = cfg['characters'][0]['sprite']
    D = R.load_base(sprite, asset)
    f = R.frame_refs(cfg)[asset][0]
    p_old = sprite.get('assetFxPad', {}).get(asset, 0)
    sy = float(f.get('height', D.shape[0] + 2 * p_old)) / (D.shape[0] + 2 * p_old)
    ground = float(f.get('pivotY', (D.shape[0] + p_old) * sy)) / sy - p_old
    dash = R.DASH_DIR in asset
    slash, dust, white, stray = R.classify(D, ground, dash)
    if not slash.any() and not dust.any() and not stray.any():
        return D, None
    seed = sum(asset.encode('utf-8')) % 9973
    return D, recolor_hard(D, slash, dust, stray, seed=seed, wake_y=ground if dash else None, solid_fx=R.classify.solid_fx)


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    only = sys.argv[2:]
    cfg = R.load_cfg(); sprite = cfg['characters'][0]['sprite']
    before = json.dumps(cfg, ensure_ascii=False, sort_keys=True)
    prev = os.path.join(os.path.dirname(__file__), '..', '..', '.runtime', 'recolor_hard')
    os.makedirs(prev, exist_ok=True)
    done = 0
    for asset in R.targets(sprite):
        if only and not any(o in asset for o in only): continue
        # 只换旧版已经上过色的帧（蓄力斩 charge-20261026 是另一套成品帧，没走过旧版，不碰）
        if not sprite.get('assetOverride', {}).get(asset, '').startswith(R.OUT_DIR): continue
        D, out = process(cfg, asset)
        if out is None: continue
        done += 1
        if mode == 'preview':
            Image.fromarray(out).save(os.path.join(prev, asset.replace('image/', '').replace('/', '__')))
        else:
            R.write_frame(cfg, asset, D, out)
    # PAD 没变时 battle.json 不用动（只换了修复帧文件），免得和修改器的改动打架
    if mode == 'write' and json.dumps(cfg, ensure_ascii=False, sort_keys=True) != before:
        open(R.CFG, 'w', encoding='utf-8').write(json.dumps(cfg, ensure_ascii=False, separators=(',', ':')) + '\n')
        print('battle.json updated')
    print('frames with fx:', done)
