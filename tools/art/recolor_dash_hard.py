"""冲刺斩（desktop-actions/冲刺攻击）刀光：形状完全照原版白刀光（硬边、6px 台阶都保留），颜色换成主角紫。
和 recolor_slash.py 的区别：不磨圆边缘、不加刷痕、不往内侧淡出、外面不垫紫晕——只在原白色像素上平涂三档紫（硬分层）。
尘土同样保留原形状，换成灰蓝。识别（哪些白像素算刀光/尘土）沿用 recolor_slash.classify。

用法：python tools/art/recolor_dash_hard.py preview <输出目录>   （只出预览 PNG）
      python tools/art/recolor_dash_hard.py write                （写 assets/image/fixed-fx/…webp.b64，挂到 battle.json 的 assetOverride）"""
import os, sys, json
import numpy as np, cv2
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
import recolor_slash as rs

ANIMS = ['dash_left', 'dash_right']   # 全 56 帧（新动画 dash_left_video / dash_right_video 引用同一批图）
PAD = rs.PAD

# 硬分层色阶：u = 到外缘（刀尖划过那条边）的相对距离，0 外缘 → 1 内缘
BANDS = [(0.14, rs.hexc('e6deff')),   # 外缘亮芯
         (0.38, rs.hexc('9d7fff')),   # 淡紫
         (0.78, rs.hexc('7651ec')),   # 紫身（游戏里有辉光和打光，会亮一档）
         (1.01, rs.hexc('5638c4'))]   # 内缘深紫
CORE_PX = 4.0                         # 外缘亮芯至少这么宽（细刀光也看得见一条亮边）
DUST_L, DUST, DUST_D = rs.DUST_L, rs.DUST, rs.DUST_D
DUST_A = 0.85


def band_color(u, da):
    out = np.zeros(u.shape + (3,), np.float32)
    lo = -1.0
    for hi, c in BANDS:
        out[(u > lo) & (u <= hi)] = c
        lo = hi
    out[da <= CORE_PX] = BANDS[0][1]
    return out


def recolor_hard(D, slash, dust, stray):
    P = PAD
    Dp = cv2.copyMakeBorder(D, P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    S = cv2.copyMakeBorder(slash.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    U = cv2.copyMakeBorder(dust.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    if stray is not None and stray.any():
        Dp[cv2.copyMakeBorder(stray.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0) > 0] = 0
    out = Dp.astype(np.float32) / 255.0
    rgb0 = Dp[..., :3].astype(np.float32)
    a0 = Dp[..., 3].astype(np.float32) / 255
    lum = rgb0.max(-1)
    ch = rgb0.max(-1) - rgb0.min(-1)
    # 尘土：原形状，灰蓝三档（按原亮度硬分）
    if U.any():
        m = U > 0
        col = np.where((lum >= 200)[..., None], DUST_L, np.where((lum >= 150)[..., None], DUST, DUST_D))
        out[m, :3] = col[m] / 255
        out[m, 3] = np.clip(a0[m], 0, 1) * DUST_A
    if not S.any():
        return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)
    # 刀光边上抠像留下的半透明灰白过渡像素也算刀光（否则紫刀光外面会留一圈白边）
    near = cv2.dilate(S, np.ones((3, 3), np.uint8)) > 0
    fringe = near & (Dp[..., 3] > 0) & (ch < 60)
    m = (S > 0) | fringe
    # 内外缘只用来分色阶，遮罩本身不改
    hull = np.zeros(m.shape, np.uint8)
    grp = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, lab = cv2.connectedComponents(grp, connectivity=8)
    for i in range(1, n):
        ys, xs = np.nonzero(lab == i)
        if len(xs) < 30:
            continue
        cv2.fillConvexPoly(hull, cv2.convexHull(np.stack([xs, ys], 1).astype(np.int32)), 1)
    mm = m.astype(np.uint8)
    border = m & (cv2.erode(mm, np.ones((3, 3), np.uint8)) == 0)
    d_hull = cv2.distanceTransform(hull, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    outer = border & (d_hull <= 6)
    inner = border & ~outer
    da = cv2.distanceTransform((~outer).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE) if outer.any() else np.full(m.shape, 1e4, np.float32)
    if inner.sum() > 40:
        db = cv2.distanceTransform((~inner).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
        u = da / np.maximum(da + db, 1e-3)
    else:
        # 细长、没有凹边：中线最深、两边亮
        dm = cv2.distanceTransform(mm, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
        thick = cv2.dilate(dm, np.ones((31, 31), np.uint8)) + 1e-3
        u = 0.75 * np.clip(dm / thick, 0, 1)
        da = np.full(m.shape, 1e4, np.float32)
    col = band_color(np.clip(u, 0, 1), da)
    out[m, :3] = col[m] / 255
    # 透明度照原图：原来是实的就实，抠像边的半透明保持半透明（形状不变）
    solid = m & (Dp[..., 3] > 0)
    out[solid, 3] = np.clip(a0[solid] * 1.05, 0, 1)
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)


def process(cfg, asset):
    sprite = cfg['characters'][0]['sprite']
    D = rs.load_base(sprite, asset)
    f = rs.frame_refs(cfg)[asset][0]
    p_old = sprite.get('assetFxPad', {}).get(asset, 0)
    sy = float(f.get('height', D.shape[0] + 2 * p_old)) / (D.shape[0] + 2 * p_old)
    ground = float(f.get('pivotY', (D.shape[0] + p_old) * sy)) / sy - p_old
    slash, dust, white, stray = rs.classify(D, ground, True)
    if not slash.any() and not dust.any() and not stray.any():
        return D, None
    return D, recolor_hard(D, slash, dust, stray)


def targets(sprite):
    out = []
    for k in ANIMS:
        for f in sprite['animations'][k]['frames']:
            a = f.get('asset')
            if a and a not in out:
                out.append(a)
    return out


if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    cfg = rs.load_cfg()
    sprite = cfg['characters'][0]['sprite']
    out_dir = sys.argv[2] if mode == 'preview' and len(sys.argv) > 2 else None
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    done = 0
    for asset in targets(sprite):
        D, R = process(cfg, asset)
        if R is None:
            continue
        done += 1
        if mode == 'preview':
            Image.fromarray(R).save(os.path.join(out_dir, os.path.basename(asset)))
        else:
            rs.write_frame(cfg, asset, D, R)
    if mode == 'write':
        open(rs.CFG, 'w', encoding='utf-8').write(json.dumps(cfg, ensure_ascii=False, separators=(',', ':')) + '\n')
    print('frames with fx:', done)
