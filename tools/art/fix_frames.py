#!/usr/bin/env python3
"""节点 10：序列帧代码修复（原图不改，输出“替换帧”）。见 docs/HANDOFF-试玩版.md §13。

修什么（都只针对能靠规则判断的瑕疵）：
  1) 白色刀光/尘土的“马赛克台阶边”：源视频压缩把白色特效压成 8–12px 的方块。
     找出“白/灰、低饱和、大块、贴着透明区”的特效连通块，单独抽成一层，
     在预乘透明度空间做高斯平滑（σ≈4px）再收紧边缘 → 台阶变成圆滑的弧线；
     边缘带一点淡紫（和空中攻击的紫色刀光统一），再盖回角色上面。
  2) 离身体很远的小碎点、细横线（地平线残留）→ 擦掉。
  3) 身体外面一圈很淡的黑色抠图残渣（低透明 + 暗色 + 不贴着实心像素）→ 擦掉。
输出：assets/image/fixed/<原路径去掉 image/ 前缀>.webp.b64（有损 webp q90，base64 文本，
      因为仓库推送只能走文本）；battle.json 的 sprite.assetOverride = {原路径: 新路径}，
      ArtCache 加载原路径时自动换成修复帧。
用法：python3 tools/art/fix_frames.py [动作名,...]   （不带参数 = 全部默认动作）
      PREVIEW=/tmp/dir 只输出对比图不写文件。
"""
import base64, io, json, os, sys
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DATA = os.path.join(ROOT, 'assets', 'data', 'battle.json')
LAVENDER = np.array([0.72, 0.62, 1.0], np.float32)


def load(path, cleanup):
    im = np.array(Image.open(os.path.join(ROOT, 'assets', path)).convert('RGBA')).astype(np.float32) / 255.0
    for r in cleanup.get(path, []):
        x, y, w, h = map(int, r)
        im[y:y + h, x:x + w] = 0
    return im


def gblur(x, s):
    k = int(s * 3) * 2 + 1
    return cv2.GaussianBlur(x, (k, k), s, borderType=cv2.BORDER_CONSTANT)


def effect_mask(im):
    """白/灰特效：低饱和、偏亮；只保留“大块且大量贴着透明区”的连通块（排除衣服白边、刀刃高光）。"""
    a = im[..., 3]
    rgb = im[..., :3]
    mx = rgb.max(-1); mn = rgb.min(-1)
    sat = (mx - mn) / (mx + 1e-4)
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    cand = ((a > 0.04) & (sat < 0.26) & (lum > 0.42)).astype(np.uint8)
    cand = cv2.morphologyEx(cand, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(cand, connectivity=8)
    clear = (a < 0.08).astype(np.uint8)
    near_clear = cv2.dilate(clear, np.ones((5, 5), np.uint8)) > 0
    keep = np.zeros(a.shape, bool)
    total = float((a > 0.5).sum()) + 1.0
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if area < max(180, total * 0.004):
            continue
        comp = lab[y:y + h, x:x + w] == i
        edge = comp & ~cv2.erode(comp.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool)
        touch = (edge & near_clear[y:y + h, x:x + w]).sum() / max(edge.sum(), 1)
        # 大面积 + 贴着透明区 → 特效；身体上的白色块被黑描边包着，touch 很低
        if touch > 0.38 or (area > total * 0.05 and touch > 0.22) or (area > total * 0.12 and touch > 0.13):
            keep[y:y + h, x:x + w] |= comp
    return keep


def smooth_effect(im, keep, sigma=4.0):
    a = im[..., 3]
    soft = gblur(keep.astype(np.float32), 1.2)
    ea = a * np.clip(soft * 1.4, 0, 1)                 # 特效层透明度
    pm = im[..., :3] * ea[..., None]
    ba = gblur(ea, sigma)
    bp = gblur(pm, sigma)
    col = bp / np.maximum(ba[..., None], 1e-4)
    na = np.clip((ba - 0.5) * 1.9 + 0.5, 0, 1)          # 收紧：边缘过渡约 3–4px
    na = np.where(ba > 0.02, np.maximum(na, ba * 0.35), 0)
    # 边缘泛淡紫：离特效内部越远越紫
    core = gblur(keep.astype(np.float32), sigma * 2.5)
    t = np.clip(1.0 - core * 1.6, 0, 1)[..., None] * 0.55
    lum = (col @ np.array([0.299, 0.587, 0.114], np.float32))[..., None]
    col = col * (1 - t) + LAVENDER * np.clip(lum * 1.1, 0, 1) * t
    eff = np.dstack([np.clip(col, 0, 1), na])
    # 原图去掉特效像素 = 身体层
    body = im.copy()
    body[..., 3] = a * (1 - np.clip(soft * 1.4, 0, 1))
    # 特效盖在身体上面（源视频里刀光就在前面）
    ea2 = eff[..., 3:4]; ba2 = body[..., 3:4]
    out_a = ea2 + ba2 * (1 - ea2)
    out_pm = eff[..., :3] * ea2 + body[..., :3] * ba2 * (1 - ea2)
    # 身体轮廓里面保持原样：白光压在脸/胸口上的部分一模糊就成了“烟”，反而更糟；
    # 台阶边只出现在特效和透明背景的交界处，平滑那里就够了。
    solid = ((a > 0.6) & ~keep).astype(np.uint8)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (17, 17))
    inside = cv2.erode(cv2.morphologyEx(solid, cv2.MORPH_CLOSE, k), np.ones((3, 3), np.uint8))
    inside = gblur(inside.astype(np.float32), 2.0)[..., None]
    o_pm = im[..., :3] * a[..., None]
    out_pm = out_pm * (1 - inside) + o_pm * inside
    out_a = out_a * (1 - inside) + a[..., None] * inside
    out_rgb = out_pm / np.maximum(out_a, 1e-4)
    return np.dstack([out_rgb, out_a])


def remove_lines_and_specks(im):
    a = im[..., 3]
    m = (a > 0.03).astype(np.uint8)
    # 细横线：竖直厚度 ≤ 4、横向 ≥ 140px 的连通块
    thick = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 1), np.uint8))
    thin = ((m > 0) & (thick == 0)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(thin, connectivity=8)
    kill = np.zeros(a.shape, bool)
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if (w >= 140 and h <= 8) or (w >= 60 and h <= 5):
            kill |= lab == i
    # 地面细横线（常和脚、尘土连在一起，连通块判断不出来）：只看最底部一条带，
    # 逐行找“竖直厚度 ≤ 4 的像素”连成的长横段（≥ 40px），整段擦掉。
    # 别的高度上也有贯穿画面的细横线（强普挑飞第 9–11 帧胸口那条），阈值放到 ≥ 150px。
    rows = np.nonzero((a > 0.5).sum(1) > 3)[0]
    if len(rows):
        y_ground = max(int(rows.max()) - 40, 0)
        band = thin.astype(bool)
        bridged = cv2.dilate(band.astype(np.uint8), np.ones((1, 5), np.uint8)) > 0
        for yy in np.nonzero(bridged.sum(1) >= 40)[0]:
            need = 40 if yy >= y_ground else 150
            d = np.diff(np.concatenate([[0], bridged[yy].astype(np.int8), [0]]))
            st_, en_ = np.nonzero(d == 1)[0], np.nonzero(d == -1)[0]
            for s0, e0 in zip(st_, en_):
                if e0 - s0 >= need:
                    kill[yy, s0:e0] |= band[yy, s0:e0]
    # 离身体远的小碎块
    core = (a > 0.5).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, connectivity=8)
    big = max(st[1:, 4].max() if n > 1 else 0, 1)
    rgb = im[..., :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    sat = (rgb.max(-1) - rgb.min(-1)) / (rgb.max(-1) + 1e-4)
    for i in range(1, n):
        x, y, w, h, area = st[i]
        if area < max(40, big * 0.002):
            kill |= lab == i
        elif area < big * 0.05 and w <= 24 and h >= 30 and h >= 2.5 * w:
            # 孤立的白色竖条（抠图残留的刀光碎片）
            c = lab == i
            if lum[c].mean() > 0.55 and sat[c].mean() < 0.3:
                kill |= c
    out = im.copy()
    kill &= a > 0
    out[kill] = 0
    return out, int(kill.sum())


def remove_dark_haze(im, keep):
    """身体外面一圈很淡的黑色抠图残渣：低透明 + 暗色 + 不贴着【身体】实心像素（特效实心不算）。"""
    a = im[..., 3]
    rgb = im[..., :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114], np.float32)
    sat = (rgb.max(-1) - rgb.min(-1)) / (rgb.max(-1) + 1e-4)
    solid = cv2.dilate(((a > 0.7) & ~keep).astype(np.uint8), np.ones((5, 5), np.uint8)) > 0
    kill = (a > 0) & (a < 0.5) & (lum < 0.25) & ~solid
    # 灰紫色半透明雾（空中攻击周围那圈“脏边”）：不饱和、偏暗、离任何实心像素都 ≥ 5px
    solid_any = cv2.dilate((a > 0.7).astype(np.uint8), np.ones((11, 11), np.uint8)) > 0
    kill |= (a > 0) & (a < 0.6) & (lum < 0.46) & (sat < 0.4) & ~solid_any
    out = im.copy()
    out[kill] = 0
    return out, int(kill.sum())


def fix(im, do_effect=True):
    out, killed = remove_lines_and_specks(im)
    keep = effect_mask(out) if do_effect else np.zeros(im.shape[:2], bool)
    out, k2 = remove_dark_haze(out, keep)
    if keep.sum() > 0:
        out = smooth_effect(out, keep)
    return out, int(keep.sum()), killed + k2


def to_webp_b64(im, q=90):
    a8 = (np.clip(im, 0, 1) * 255 + 0.5).astype(np.uint8)
    a8[a8[..., 3] == 0, :3] = 0
    b = io.BytesIO()
    Image.fromarray(a8, 'RGBA').save(b, 'WEBP', quality=q, method=6, alpha_quality=100)
    return base64.b64encode(b.getvalue()).decode('ascii')


# 要修的帧（逐帧质检结论，见交接文档 §13.4）：动作名 -> (帧号列表, 是否平滑白色特效)
# 只擦横线/碎点/脏边的写 False（空中攻击的紫色刀光本身质量好）。
def _r(a, b):
    return list(range(a, b + 1))


TARGETS = {
    'attack_1': ([1, 5, 6, 7, 12], True),
    'attack_2': (_r(0, 10), True),
    'attack_3': (_r(1, 11), True),
    'strong_attack': (_r(9, 19), True),
    'dash_left': (_r(1, 13), True),
    'dash_right': (_r(1, 34), True),
    'guard_start': ([8, 9], True),
    'guard_hit_1': (_r(0, 3), True),
    'guard_hit_2': (_r(3, 6), True),
    'guard_hit_3': (_r(9, 11), True),
    'parry_react_1': (_r(1, 3), True),
    'parry_react_2': (_r(1, 5), True),
    'parry_react_3': ([1, 2, 3, 8, 9], True),
    'death': (_r(21, 24) + _r(42, 45) + _r(75, 81), True),
    'air_attack_1': (None, False),
    'air_attack_2': (None, False),
    'air_attack_3': (None, False),
}
FIXED_PREFIX = 'image/fixed/'


def fixed_path(src):
    rel = src[len('image/'):] if src.startswith('image/') else src
    return FIXED_PREFIX + os.path.splitext(rel)[0] + '.webp.b64'


def write_all(cfg, names):
    sprite = cfg['characters'][0]['sprite']
    cleanup = sprite.get('assetCleanup', {})
    override = dict(sprite.get('assetOverride', {}))
    done = {}
    total = 0
    for an in names:
        idxs, do_effect = TARGETS[an]
        frames = sprite['animations'][an]['frames']
        for i in (idxs if idxs is not None else range(len(frames))):
            src = frames[i].get('asset')
            if not src or src in done:
                continue
            out, ne, nk = fix(load(src, cleanup), do_effect)
            dst = fixed_path(src)
            if ne == 0 and nk < 300:          # 几乎没改动：不值得多存一份
                override.pop(src, None)
                if os.path.exists(os.path.join(ROOT, 'assets', dst)):
                    os.remove(os.path.join(ROOT, 'assets', dst))
                print(an, i, 'skip (killed %d)' % nk)
                continue
            os.makedirs(os.path.dirname(os.path.join(ROOT, 'assets', dst)), exist_ok=True)
            text = to_webp_b64(out)
            with open(os.path.join(ROOT, 'assets', dst), 'w', encoding='ascii') as fh:
                fh.write(text)
            override[src] = dst
            done[src] = True
            total += len(text)
            print(an, i, 'effect_px', ne, 'killed', nk, '%.0fKB' % (len(text) / 1024))
    sprite['assetOverride'] = dict(sorted(override.items()))
    print('frames', len(done), 'total %.2fMB' % (total / 1048576))


if __name__ == '__main__':
    cfg = json.load(open(DATA, encoding='utf-8'))
    sprite = cfg['characters'][0]['sprite']
    cleanup = sprite.get('assetCleanup', {})
    anims = sys.argv[1].split(',') if len(sys.argv) > 1 else []
    preview = os.environ.get('PREVIEW', '')
    if not preview:
        write_all(cfg, anims or list(TARGETS))
        with open(DATA, 'w', encoding='utf-8') as fh:
            json.dump(cfg, fh, ensure_ascii=False, separators=(',', ':'))
            fh.write('\n')
        sys.exit(0)
    frames_only = os.environ.get('ONLY', '')
    for an in anims:
        for i, f in enumerate(sprite['animations'][an]['frames']):
            if frames_only and str(i) not in frames_only.split(','):
                continue
            p = f.get('asset')
            if not p:
                continue
            im = load(p, cleanup)
            out, ne, nk = fix(im)
            print(an, i, p, 'effect_px', ne, 'killed', nk)
            if preview:
                bg = np.array([24, 32, 46], np.float32) / 255
                def comp(x):
                    return x[..., :3] * x[..., 3:4] + bg * (1 - x[..., 3:4])
                ys, xs = np.nonzero(np.maximum(im[..., 3], out[..., 3]) > 0.1)
                box = (slice(max(ys.min() - 4, 0), ys.max() + 5), slice(max(xs.min() - 4, 0), xs.max() + 5))
                pair = np.concatenate([comp(im)[box], comp(out)[box]], axis=1)
                Image.fromarray((pair * 255).astype(np.uint8)).save(os.path.join(preview, '%s_%02d.png' % (an, i)))
