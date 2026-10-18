#!/usr/bin/env python3
"""序列帧对位（可重复运行）。

做什么：
  1. 逐帧测量角色“躯干中心”（排除白色刀光/尘土与细长的剑），单位 = 游戏世界像素（已乘 displayScale），朝前为正。
  2. 按动作类型改 pivotX，让躯干中心落在角色坐标（碰撞盒中心）上：
       const  循环动作（待机/跑步/下坠…）：整段统一平移，保留原画里的呼吸摆动
       lock   过渡动作（起跳/落地/拔刀…）：逐帧平移（平滑后），去掉画里的横向漂移
       root   招式/冲刺/格挡反馈：逐帧平移 + 把画里的位移提取成 rootMotionX（运行时变成真实位移）
       turn   转身（像素里自己转身，不受朝向翻转）：躯干从“跑步朝左”平滑过渡到“跑步朝右”
  3. 原始数据保存在 pivotXAuthored，脚本永远从原始值计算，所以可以反复运行。

用法：python3 tools/art/align_sequences.py [--report]
需要：numpy、Pillow、opencv-python-headless
"""
import json, sys, os
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DATA = os.path.join(ROOT, 'assets', 'data', 'battle.json')

MODES = {
    'idle': 'const', 'run': 'const', 'fall': 'const', 'guard_hold': 'const',
    'jump': 'lock', 'land': 'lock', 'draw': 'lock', 'sheathe': 'lock', 'death': 'lock',
    'turn_left_right': 'turn', 'turn_right_left': 'turn',
    # 空中招式的紫色刀光与身体粘连，逐帧测量不可靠；身体在画里基本不动 → 整段统一平移
    'air_attack_1': 'const', 'air_attack_2': 'const', 'air_attack_3': 'const', 'air_slash': 'const',
}
# 转身原片 13 帧里其实转了两次（0–6 一次，7–12 又从朝左开始转一次）。只取第一次。
TRIM = {'turn_left_right': ('source_跑步左向转右', 0, 7)}
ROOT_DEFAULT = 'root'
# 招式里不希望出现的“往后退”根位移上限（世界像素）。画里的小幅后撤保留。
SMOOTH = 3


def _img(path, cache={}):
    if path not in cache:
        cache[path] = Image.open(os.path.join(ROOT, 'assets', path)).convert('RGBA')
    return cache[path]


def measure(frame, clip, ds, pivot_x):
    """返回 (躯干中心x, 脚底y)，以锚点为原点；非转身动作朝前为正。"""
    im = _img(frame['asset'])
    tw, th = im.size
    W = float(frame.get('width', tw)); H = float(frame.get('height', th))
    sx = W / tw * ds; sy = H / th * ds
    nw = max(1, int(round(tw * sx))); nh = max(1, int(round(th * sy)))
    img = im.resize((nw, nh), Image.BILINEAR)
    ox = pivot_x * tw / W * sx
    oy = float(frame.get('pivotY', H)) * th / H * sy
    flip = clip.get('sourceFacing', 1) == -1 and not clip.get('authoredTurn')
    if flip:
        img = img.transpose(Image.FLIP_LEFT_RIGHT); ox = nw - ox
    a = np.asarray(img).astype(np.int16)
    rgb = a[..., :3]; al = a[..., 3]
    mx = rgb.max(-1); mn = rgb.min(-1)
    white = (mn > 165) & ((mx - mn) < 60)
    m = ((al > 140) & ~white).astype(np.uint8)
    mo = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(mo, 8)
    if n <= 1:
        return None
    j = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    body = lab == j
    x0, w = st[j, 0], st[j, 2]
    for q in range(1, n):
        if q != j and st[q, cv2.CC_STAT_AREA] > 0.15 * st[j, cv2.CC_STAT_AREA]:
            qx = st[q, 0] + st[q, 2] / 2
            if x0 - 20 < qx < x0 + w + 20:
                body |= lab == q
    ys, xs = np.where(body)
    bot = ys.max(); top = ys.min(); h = bot - top
    band = (ys < bot - 0.40 * h) & (ys > bot - 0.80 * h)
    cx = float(np.median(xs[band])) if band.sum() > 20 else float(np.median(xs))
    xl = int(max(0, cx - 45)); xr = int(min(al.shape[1], cx + 45))
    rows = (al[:, xl:xr] > 200).sum(1)
    cand = np.where(rows >= 4)[0]
    fy = int(cand.max()) if len(cand) else int(bot)
    return cx - ox, fy - oy, (1 if not flip else -1)


def smooth(v, k=SMOOTH):
    v = np.asarray(v, float)
    if len(v) < 3 or k <= 1:
        return v.copy()
    pad = k // 2
    p = np.pad(v, pad, mode='edge')
    med = np.array([np.median(p[i:i + k]) for i in range(len(v))])
    return med


def main():
    report = '--report' in sys.argv
    d = json.load(open(DATA, encoding='utf-8'))
    sprite = d['characters'][0]['sprite']
    ds = float(sprite['displayScale'])
    anims = sprite['animations']
    run_lean = 0.0
    summary = {}
    import copy
    for name, (src, a, b) in TRIM.items():
        if name in anims and src in anims:
            anims[name]['frames'] = copy.deepcopy(anims[src]['frames'][a:b])
            anims[name]['trimmedFrom'] = {'animation': src, 'start': a, 'end': b}
    for name, clip in anims.items():
        if name.startswith('source_'):
            continue
        frames = clip.get('frames', [])
        cxs, signs, idx = [], [], []
        for i, f in enumerate(frames):
            if not f.get('asset'):
                continue
            f.setdefault('pivotXAuthored', f.get('pivotX', f.get('width', 0) / 2))
            r = measure(f, clip, ds, float(f['pivotXAuthored']))
            if r is None:
                continue
            cxs.append(r[0]); signs.append(r[2]); idx.append(i)
        if not cxs:
            continue
        mode = MODES.get(name, ROOT_DEFAULT)
        cx = np.array(cxs); sm = smooth(cx)
        if mode == 'const':
            shift = np.full_like(cx, float(np.median(cx)))
        elif mode == 'lock':
            shift = sm
        elif mode == 'turn':
            # 转身很短，逐帧精确锁到碰撞盒中心（像素坐标，不受朝向翻转）
            shift = cx.copy()
        else:
            shift = sm
        rootx = None
        if mode == 'root':
            rootx = [0.0] * len(frames)
            base = float(sm[0])
            for k, i in enumerate(idx):
                rootx[i] = round(float(sm[k] - base), 2)
            # 空帧沿用前一帧
            for i in range(1, len(frames)):
                if i not in idx:
                    rootx[i] = rootx[i - 1]
            clip['rootMotionX'] = rootx
        else:
            clip.pop('rootMotionX', None)
        for k, i in enumerate(idx):
            f = frames[i]
            # 世界像素 → 帧坐标（width 单位）。flip 时方向相反。
            f['pivotX'] = round(float(f['pivotXAuthored']) + float(shift[k]) * signs[k] / ds, 4)
        clip['alignment'] = {'mode': mode, 'tool': 'tools/art/align_sequences.py',
                             'bodyOffsetBefore': [round(float(v), 1) for v in cx],
                             'residual': [round(float(a - b), 1) for a, b in zip(cx, shift)]}
        summary[name] = (mode, cx, shift, rootx)
    sprite['alignmentNote'] = '躯干中心对齐到角色坐标；原始 pivotX 存于 pivotXAuthored；招式位移在 animations.*.rootMotionX（世界像素，朝前为正）。'
    with open(DATA, 'w', encoding='utf-8') as fp:
        json.dump(d, fp, ensure_ascii=False, indent=2)
        fp.write('\n')
    for name, (mode, cx, shift, rootx) in summary.items():
        res = cx - shift
        line = f'{name:18s} {mode:5s} before[{cx.min():6.1f},{cx.max():6.1f}] residual max {np.abs(res).max():5.1f}'
        if rootx:
            line += f' root end {rootx[-1]:6.1f} min {min(rootx):6.1f} max {max(rootx):6.1f}'
        print(line)


if __name__ == '__main__':
    main()
