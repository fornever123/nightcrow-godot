"""地面攻击烘焙在序列帧里的纯白刀光 → 主角紫刀光（白芯亮边 + 淡紫 + 紫身 + 内侧淡出 + 外侧紫晕），
白色尘土 → 灰蓝尘土。只改刀光/尘土像素，角色本身不动。

用法：python3 tools/art/recolor_slash.py preview   （只出预览到 /data/fxwork/recolor/）
      python3 tools/art/recolor_slash.py write     （写修复帧 assets/image/fixed-fx/…webp.b64 并改 battle.json）

识别：低饱和、亮的像素按连通块分类——大块且边缘多挨着透明 = 刀光；贴地、不细长 = 尘土；
其余（衣服白边、刀身高光）不动。刀光的「外缘」= 挨着凸包的那条边（刀尖划过的路径），
按到外缘/内缘的距离比 u 上色：外缘白芯 → 淡紫 → 紫 → 深紫并淡出，外侧加一圈半透明紫晕。
输出帧四周各加 PAD 像素透明边给紫晕留地方，battle.json 里引用这些帧的 width/height/pivot 同步换算。"""
import base64, io, json, os, sys
import numpy as np, cv2
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), '..', '..', 'assets') + '/'
CFG = ROOT + 'data/battle.json'
ANIMS = ['attack_1', 'attack_2', 'attack_3', 'attack_2_start', 'attack_2_recovery', 'strong_attack', 'attack_up', 'charge_slash',
         'dash_right', 'dash_left']
PAD = 20
OUT_DIR = 'image/fixed-fx/'

def hexc(h): return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)
# 刀光色阶（u=0 外缘 → u=1 内缘），和程序特效 VIO_L/VIO/VIO_D 一套
RAMP = [(0.00, hexc('e4dbff')), (0.14, hexc('cbbcff')), (0.32, hexc('a487ff')),
        (0.60, hexc('7e5cf0')), (0.85, hexc('6447d6')), (1.00, hexc('5238b8'))]
CORE = hexc('efeaff')   # 外缘白芯（固定像素宽，不随刀光粗细变）；略偏蓝，夜景描边才认得出是刀光（char_light.gdshader OL_TAP）
CORE_W = 13.0
GLOW = hexc('9a7cff')
# 尘土：浅灰蓝、半透明；三档都“亮且偏蓝”（最小通道 ≥0.55、蓝比红高），夜景描边不会给尘土描黑边
DUST_L, DUST, DUST_D = hexc('cdd4e2'), hexc('aab4c8'), hexc('96a0b6')
DUST_A = 0.62
# 冲刺斩（desktop-actions/冲刺攻击）：①冲刺时画在身上的横向白色速度条也算刀光；②贴地那一截（尾迹扬起的白烟）渐变成尘土
DASH_DIR = 'desktop-actions/冲刺攻击/'
WAKE_TOP, WAKE_W = 58.0, 22.0   # 地面往上 WAKE_TOP 像素处开始过渡成尘土，过渡宽 WAKE_W

def ramp(u):
    out = np.zeros(u.shape + (3,), np.float32)
    for (u0, c0), (u1, c1) in zip(RAMP[:-1], RAMP[1:]):
        m = (u >= u0) & (u <= u1)
        t = ((u[m] - u0) / (u1 - u0))[:, None]
        out[m] = c0 * (1 - t) + c1 * t
    return out

def load_cfg():
    return json.load(open(CFG, encoding='utf-8'))

def load_base(sprite, asset):
    ov = sprite.get('assetOverride', {})
    if asset in ov and not ov[asset].startswith(OUT_DIR):
        return np.array(Image.open(io.BytesIO(base64.b64decode(open(ROOT + ov[asset]).read().strip()))).convert('RGBA'))
    if asset in sprite.get('assetFxBase', {}):  # 已经处理过一次：从记下的原底图重来
        src = sprite['assetFxBase'][asset]
        if src != asset:
            return np.array(Image.open(io.BytesIO(base64.b64decode(open(ROOT + src).read().strip()))).convert('RGBA'))
    im = np.array(Image.open(ROOT + asset).convert('RGBA'))
    for x, y, w, h in sprite.get('assetCleanup', {}).get(asset, []):
        im[y:y + h, x:x + w] = 0
    return im

def classify(D, ground_y, dash=False):
    rgb = D[..., :3].astype(np.int16); a = D[..., 3]
    mx = rgb.max(-1); ch = mx - rgb.min(-1)
    white = (a > 24) & (ch <= 46) & (mx >= 100)
    n, lab, st, _ = cv2.connectedComponentsWithStats(white.astype(np.uint8), connectivity=8)
    trans = a < 24
    H, W = a.shape
    slash = np.zeros((H, W), bool); dust = np.zeros((H, W), bool)
    solid_fx = np.zeros((H, W), bool)   # 压在身上的速度条：底下没有身体像素，上色后要保持不透明
    minor = []
    k5 = np.ones((5, 5), np.uint8)
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if area < 20: continue
        x0, y0 = max(0, x - 3), max(0, y - 3)
        comp = (lab[y0:y + h + 3, x0:x + w + 3] == i).astype(np.uint8)
        ring = cv2.dilate(comp, k5) - comp
        ratio = (trans[y0:y + h + 3, x0:x + w + 3] & (ring > 0)).sum() / max(1, ring.sum())
        near_ground = (y + h) >= ground_y - 70
        aspect = max(w, h) / max(1, min(w, h))
        blob = (aspect < 3.5 and h < 140) or (aspect < 7 and h < 90)
        thick = float(cv2.distanceTransform(comp, cv2.DIST_L2, 3).max())  # 最大内切半径：刀身/衣服白边都很细
        if near_ground and blob and area >= 300 and thick >= 5 and (ratio >= 0.55 or (ratio >= 0.3 and area >= 800)):
            dust[lab == i] = True
        elif thick >= 10 and ((area >= 2000 and ratio >= 0.3) or (area >= 600 and ratio >= 0.6)):
            slash[lab == i] = True
        elif ratio >= 0.35:
            minor.append(i)
    if slash.any() and minor:
        near = cv2.dilate(slash.astype(np.uint8), np.ones((33, 33), np.uint8)) > 0
        for i in minor:
            m = lab == i
            if (near & m).sum() >= 0.5 * m.sum():
                slash |= m
    if dash:
        # 冲刺时压在身上的纯白速度条：宽松的“白”会连上身体外圈的灰边（抠像残留），所以用纯白当种子，
        # 只往外长 5px 吃掉它自己的过渡边
        strict = (a > 24) & (ch <= 24) & (mx >= 228)
        n3, lab3, st3, _ = cv2.connectedComponentsWithStats(strict.astype(np.uint8), connectivity=8)
        for i in range(1, n3):
            x, y, w, h, area = st3[i]
            if area < 300: continue
            comp = (lab3 == i)
            if (comp & (slash | dust)).sum() >= 0.5 * area: continue
            if float(cv2.distanceTransform(comp.astype(np.uint8), cv2.DIST_L2, 3).max()) < 5: continue
            grown = (cv2.dilate(comp.astype(np.uint8), np.ones((11, 11), np.uint8)) > 0) & white & ~slash & ~dust
            aspect = max(w, h) / max(1, min(w, h))
            if (y + h) >= ground_y - 70 and aspect < 3.5:
                dust |= grown
            else:
                slash |= grown; solid_fx |= grown
    # 孤立的小杂点（源视频带进来的）：周围 60px 内没有别的东西 → 直接抹掉
    stray = np.zeros((H, W), bool)
    solid = a > 24
    n2, lab2, st2, _ = cv2.connectedComponentsWithStats(solid.astype(np.uint8), connectivity=8)
    for i in range(1, n2):
        x, y, w, h, area = st2[i]
        if area >= 800: continue
        x0, y0, x1, y1 = max(0, x - 60), max(0, y - 60), min(W, x + w + 60), min(H, y + h + 60)
        comp = lab2[y0:y1, x0:x1] == i
        if not (solid[y0:y1, x0:x1] & ~comp).any():
            stray[lab2 == i] = True
    slash &= ~stray; dust &= ~stray
    classify.solid_fx = solid_fx & slash
    return slash, dust, white, stray

def recolor(D, slash, dust, stray=None, seed=0, wake_y=None, solid_fx=None):
    H, W = slash.shape
    P = PAD
    Dp = cv2.copyMakeBorder(D, P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    S = cv2.copyMakeBorder(slash.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    U = cv2.copyMakeBorder(dust.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0)
    if stray is not None and stray.any():
        Dp[cv2.copyMakeBorder(stray.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0) > 0] = 0
    out = Dp.astype(np.float32) / 255.0
    rgb0 = Dp[..., :3].astype(np.float32); a0 = Dp[..., 3].astype(np.float32) / 255
    lum = rgb0.max(-1)
    # —— 尘土：灰蓝 ——
    if U.any():
        t = np.clip((lum - 100) / 140, 0, 1)[..., None]
        col = np.where(t > 0.5, DUST * (2 - 2 * t) + DUST_L * (2 * t - 1), DUST_D * (1 - 2 * t) + DUST * (2 * t))
        m = U > 0
        out[m, :3] = col[m] / 255
        out[m, 3] = a0[m] * DUST_A
    if not S.any():
        return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)
    # 补上刀光边缘的半透明过渡像素（挨着刀光、低饱和、半透明）
    ch = rgb0.max(-1) - rgb0.min(-1)
    near = cv2.dilate(S, np.ones((3, 3), np.uint8)) > 0
    fringe = near & (Dp[..., 3] > 0) & (((Dp[..., 3] < 250) & (ch < 60)) | (ch < 36))
    near = cv2.dilate(((S > 0) | fringe).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    fringe |= near & (Dp[..., 3] > 0) & (ch < 36)
    S = ((S > 0) | fringe).astype(np.uint8)
    # 原刀光边缘是 6px 一级的台阶：遮罩先糊再二值化，把台阶磨圆（只往透明处长，不盖角色）
    raw = S > 0
    sm = cv2.GaussianBlur(S.astype(np.float32), (0, 0), 3.2) > 0.5
    S = (sm & (raw | (Dp[..., 3] < 24))).astype(np.uint8)
    cut = raw & (S == 0)
    out[cut] = 0
    a0 = np.where(S > 0, np.maximum(a0, (S > 0) * 1.0), a0)
    # 几何（内外缘、距离）用更圆的遮罩算，原图 6px 台阶不会让白芯变成虚线
    Sfull = S
    S = (cv2.GaussianBlur(S.astype(np.float32), (0, 0), 5.5) > 0.5).astype(np.uint8)
    if S.sum() < 0.3 * Sfull.sum():
        S = Sfull
    # 按连通组算凸包：外缘 = 贴着凸包的边界
    grp = cv2.morphologyEx(S, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n, lab = cv2.connectedComponents(grp, connectivity=8)
    hull = np.zeros_like(S)
    for i in range(1, n):
        ys, xs = np.nonzero(lab == i)
        if len(xs) < 30: continue
        pts = np.stack([xs, ys], 1).astype(np.int32)
        cv2.fillConvexPoly(hull, cv2.convexHull(pts), 1)
    border = (S > 0) & (cv2.erode(S, np.ones((3, 3), np.uint8)) == 0)
    d_hull_out = cv2.distanceTransform((hull > 0).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)  # 到凸包外的距离
    outer = border & (d_hull_out <= 4)
    inner = border & ~outer
    big = 1e4
    da = cv2.distanceTransform((~outer).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE) if outer.any() else np.full(S.shape, big, np.float32)
    db = cv2.distanceTransform((~inner).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE) if inner.sum() > 40 else None
    dm = cv2.distanceTransform(S, cv2.DIST_L2, cv2.DIST_MASK_PRECISE)  # 到刀光外的距离（厚度的一半左右）
    if db is None:
        # 细长无凹边：按厚度对称，外缘当两边
        thick = cv2.dilate(dm, np.ones((31, 31), np.uint8)) + 1e-3
        u = 1 - np.clip(dm / thick, 0, 1)
        u = 0.5 * u
    else:
        u = da / np.maximum(da + db, 1e-3)
    u = np.clip(u, 0, 1)
    # 圆遮罩磨掉的细尾巴：当成细刀光，亮紫
    d_geo = cv2.distanceTransform((S == 0).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    thin = (Sfull > 0) & (d_geo > 2.5)
    u = np.where(thin, 0.12, u); da = np.where(thin, np.minimum(da, 4.0), da)
    S = Sfull
    # 刷痕：沿外缘平行、断断续续的条纹（不规则间距 + 沿弧慢慢错位、时有时无）
    rng = np.random.default_rng(seed)
    def lowfreq(sig):
        z = cv2.GaussianBlur(rng.standard_normal(S.shape).astype(np.float32), (0, 0), sig)
        return z / (np.abs(z).max() + 1e-6)
    def vnoise(x, k=4096):
        r = rng.random(k).astype(np.float32)
        x = np.clip(x, 0, k - 2); i = np.floor(x).astype(np.int32); f = x - i
        f = f * f * (3 - 2 * f)
        return r[i] * (1 - f) + r[i + 1] * f
    q = da + lowfreq(30) * 9.0
    n1 = vnoise(q / 6.5)
    n2 = vnoise(q / 2.8 + 777)
    gate = np.clip(lowfreq(18) * 2.2 + 0.55, 0, 1)
    band = np.clip((u - 0.12) / 0.18, 0, 1) * np.clip((1.0 - u) / 0.25, 0, 1)
    streak = (0.7 * n1 + 0.3 * n2) * gate
    shade = 1 - band * 0.30 * streak + band * 0.10 * (1 - gate) * n1
    col = ramp(u) * shade[..., None]
    w = np.clip(1 - da / CORE_W, 0, 1) ** 1.3 * 0.96
    col = col * (1 - w[..., None]) + CORE * w[..., None]
    # 透明度：外半边实，内侧淡出；原图灰的地方（画师画的淡出尾巴）更透
    Sf = (raw & (Dp[..., 3] > 200)).astype(np.float32)
    lum_s = cv2.GaussianBlur(lum * Sf, (0, 0), 5) / np.maximum(cv2.GaussianBlur(Sf, (0, 0), 5), 1e-3)
    lum_t = np.clip((lum_s - 95) / 120, 0, 1)
    t = np.clip((u - 0.45) / 0.57, 0, 1)
    alpha = 1 - (t * t * (3 - 2 * t)) * 0.92
    alpha *= (0.25 + 0.75 * lum_t) * np.clip(a0 * 1.1, 0, 1)
    alpha *= 1 - band * 0.18 * streak
    m = S > 0
    # 冲刺斩尾迹：贴地那截渐变成尘土（颜色、透明度都过去，紫晕也跟着淡掉）
    wd = np.zeros(S.shape, np.float32)
    if wake_y is not None:
        yy = np.arange(S.shape[0], dtype=np.float32)[:, None] + np.zeros((1, S.shape[1]), np.float32)
        z = np.clip((yy - (wake_y + P - WAKE_TOP - WAKE_W / 2)) / WAKE_W, 0, 1)
        wd = z * z * (3 - 2 * z)
        tt = np.clip((lum - 100) / 140, 0, 1)[..., None]
        dcol = np.where(tt > 0.5, DUST * (2 - 2 * tt) + DUST_L * (2 * tt - 1), DUST_D * (1 - 2 * tt) + DUST * (2 * tt))
        col = col * (1 - wd[..., None]) + dcol * wd[..., None]
        alpha = alpha * (1 - wd) + np.clip(a0, 0, 1) * DUST_A * wd
    if solid_fx is not None and solid_fx.any():
        sf = cv2.copyMakeBorder(solid_fx.astype(np.uint8), P, P, P, P, cv2.BORDER_CONSTANT, value=0) > 0
        alpha = np.where(sf, np.maximum(alpha, np.clip(a0, 0, 1) * 0.97), alpha)
    # 边缘抗锯齿：用略糊的刀光遮罩
    soft = cv2.GaussianBlur(S.astype(np.float32), (0, 0), 1.1)
    edge_a = np.where(m, np.clip(soft * 1.6, 0, 1), 0)
    out[m, :3] = col[m] / 255
    out[m, 3] = alpha[m] * edge_a[m]
    # 外侧紫晕（垫在角色后面）
    g = 18.0
    dout = cv2.distanceTransform((S == 0).astype(np.uint8), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
    near_outer = da <= dout + 2.5
    ga = np.where((~m) & (dout < g) & near_outer, 0.5 * np.clip(1 - dout / g, 0, 1) ** 1.6, 0) * np.clip(cv2.GaussianBlur(lum_t, (0, 0), 3) * 1.4 + 0.25, 0, 1)
    ga = np.where(m, 0.5 * np.clip(lum_t * 1.4 + 0.25, 0, 1), ga)
    ga *= 1 - cv2.GaussianBlur(wd, (0, 0), 4)
    # 刀光/原像素 over 紫晕
    base_a = out[..., 3]
    na = base_a + ga * (1 - base_a)
    nc = (out[..., :3] * base_a[..., None] + (GLOW / 255) * (ga * (1 - base_a))[..., None]) / np.maximum(na, 1e-4)[..., None]
    # 刀光内部的紫晕只垫在外缘一侧的边上（内缘照样淡出）
    inside_glow = m & (da > 6)
    out[..., :3] = np.where(inside_glow[..., None], out[..., :3], nc)
    out[..., 3] = np.where(inside_glow, out[..., 3], na)
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)

def write_frame(cfg, asset, D, R):
    """存成 webp base64 文本（和 fix_frames.py 一样，GitHub 推送只能传文本），挂到 assetOverride；
    帧四周加了 PAD 透明边，引用这帧的地方 width/height/pivot 按原缩放比例一起放大，显示位置不变。"""
    sprite = cfg['characters'][0]['sprite']
    ov = sprite.setdefault('assetOverride', {})
    base = sprite.setdefault('assetFxBase', {})
    pads = sprite.setdefault('assetFxPad', {})
    if asset not in base:
        base[asset] = ov.get(asset, asset)
    rel = OUT_DIR + asset[len('image/'):].rsplit('.', 1)[0] + '.webp.b64'
    os.makedirs(os.path.dirname(ROOT + rel), exist_ok=True)
    buf = io.BytesIO()
    Image.fromarray(R).save(buf, 'WEBP', quality=88, alpha_quality=90, method=6)
    open(ROOT + rel, 'w').write(base64.b64encode(buf.getvalue()).decode('ascii') + '\n')
    ov[asset] = rel
    p_old = pads.get(asset, 0); dp = PAD - p_old
    if dp:
        w0, h0 = D.shape[1] + 2 * p_old, D.shape[0] + 2 * p_old
        for f in frame_refs(cfg)[asset]:
            sx = float(f.get('width', w0)) / w0; sy = float(f.get('height', h0)) / h0
            f['width'] = round(float(f.get('width', w0)) + 2 * dp * sx, 5)
            f['height'] = round(float(f.get('height', h0)) + 2 * dp * sy, 5)
            f['pivotX'] = round(float(f.get('pivotX', w0 * sx / 2)) + dp * sx, 4)
            f['pivotY'] = round(float(f.get('pivotY', h0 * sy)) + dp * sy, 4)
            if 'pivotXAuthored' in f: f['pivotXAuthored'] = round(float(f['pivotXAuthored']) + dp * sx, 4)
        pads[asset] = PAD

def frame_refs(cfg):
    """asset -> [frame dict...]（所有引用到的地方）"""
    refs = {}
    def walk(o):
        if isinstance(o, dict):
            if isinstance(o.get('asset'), str): refs.setdefault(o['asset'], []).append(o)
            for v in o.values(): walk(v)
        elif isinstance(o, list):
            for v in o: walk(v)
    walk(cfg)
    return refs

def targets(sprite):
    out = []
    for k in ANIMS:
        for f in sprite['animations'][k]['frames']:
            a = f.get('asset')
            if a and a not in out: out.append(a)
    return out

def process(cfg, asset):
    sprite = cfg['characters'][0]['sprite']
    D = load_base(sprite, asset)
    f = frame_refs(cfg)[asset][0]
    p_old = sprite.get('assetFxPad', {}).get(asset, 0)
    sy = float(f.get('height', D.shape[0] + 2 * p_old)) / (D.shape[0] + 2 * p_old)
    ground = float(f.get('pivotY', (D.shape[0] + p_old) * sy)) / sy - p_old
    dash = DASH_DIR in asset
    slash, dust, white, stray = classify(D, ground, dash)
    if not slash.any() and not dust.any() and not stray.any():
        return D, None, slash, dust
    seed = sum(asset.encode('utf-8')) % 9973
    return D, recolor(D, slash, dust, stray, seed=seed, wake_y=ground if dash else None, solid_fx=classify.solid_fx), slash, dust

if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    cfg = load_cfg(); sprite = cfg['characters'][0]['sprite']
    only = sys.argv[2:] 
    os.makedirs('/data/fxwork/recolor', exist_ok=True)
    done = 0
    for asset in targets(sprite):
        if only and not any(o in asset for o in only): continue
        D, R, s, u = process(cfg, asset)
        if R is None: continue
        done += 1
        if mode == 'preview':
            name = asset.replace('image/', '').replace('/', '__')
            Image.fromarray(R).save('/data/fxwork/recolor/' + name)
        else:
            write_frame(cfg, asset, D, R)
    if mode == 'write':
        open(CFG, 'w', encoding='utf-8').write(json.dumps(cfg, ensure_ascii=False, separators=(',', ':')) + '\n')
    print('frames with fx:', done)
