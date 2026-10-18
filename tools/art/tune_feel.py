#!/usr/bin/env python3
"""手感参数（可重复运行，写绝对值）。先跑 align_sequences.py、clean_lines.py，再跑本脚本。

1. 跑步：帧率与速度按“着地脚每帧后退 ≈18.6 世界像素”绑定，脚不打滑。
2. 转身：提速 + 早翻转/早取消。
3. 输入缓冲、顿帧分级。
4. 攻击判定框：按出刀帧（activeFrameStart..End）里刀光/身体像素的实际范围重算（只取身前）。
5. 冲刺斩：画里身体落后于脚的部分，用 movementTimeline 的额外前滑补回（滑步段正好有尘土特效）。
"""
import json, os, sys
import numpy as np
import cv2
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
DATA = os.path.join(ROOT, 'assets', 'data', 'battle.json')

RUN_STRIDE = 18.6     # 着地脚每帧位移（世界像素，体检测得）
RUN_FPS = 10.0
TURN = {'turn_left_right': (18.0, 3, 4), 'turn_right_left': (18.0, 2, 3)}  # fps, flipFrame, cancelFrame
BUFFER_FRAMES = 36  # C 盘原值：顿帧里按的下一刀要能等到取消窗口打开
# 顿帧（攻击者 / 受击者，60fps 帧数）：沿用 C 盘原工程的数值（测试里也锁着），终结技的加重放到战斗节点里做
HITSTOP = {
    'light_1': (6, 7), 'light_2': (6, 8), 'light_3': (11, 15), 'charge_1': (13, 16), 'up_strike': (9, 11),
    'air_up': (6, 7), 'air_light_1': (6, 7), 'air_light_2': (6, 7), 'air_light_3': (6, 7),
    'dash_slash': (11, 15), 'dash_slash_left': (11, 15), 'ranged_1': (3, 5),
}
# 攻击中按方向键的走位倍率：前冲已经交给根位移，再按满速走就会“滑着砍”
MOVE_SCALE = {'light_1': 0.3, 'light_2': 0.3, 'light_3': 0.3, 'charge_1': 0.2, 'up_strike': 0.2,
              'ranged_1': 0.45, 'parry_1': 0.3}
HITBOX_LIMIT = (440.0, 300.0)
# 最小判定（宽, 高）：空中目标在动、冲刺是穿过去打，判定要宽容一些
HITBOX_MIN = {'air_up': (180, 190), 'air_light_1': (180, 190), 'air_light_2': (180, 200), 'air_light_3': (190, 220),
              'dash_slash': (190, 170), 'dash_slash_left': (190, 170), 'up_strike': (200, 230), 'charge_1': (240, 210)}


CLEAN = {}  # sprite.assetCleanup（clean_lines.py 生成）：先抹掉横线再量判定


def img(path, cache={}):
    if path not in cache:
        a = (np.asarray(Image.open(os.path.join(ROOT, 'assets', path)).convert('RGBA'))[..., 3] > 110).astype(np.uint8)
        for x, y, w, h in CLEAN.get(path, []):
            a[y:y + h, x:x + w] = 0
        # 开运算去掉细长的拖影线（上挑里有一条横贯全屏的灰线），只留成片的刀光
        cache[path] = cv2.morphologyEx(a, cv2.MORPH_OPEN, np.ones((9, 9), np.uint8))
    return cache[path]


def frame_points(f, clip, ds):
    """返回该帧不透明像素在“角色脚底坐标系”的 (x 朝前, y 向下为正) 坐标（抽样）。"""
    a = img(f['asset'])
    th, tw = a.shape
    W = float(f.get('width', tw)); H = float(f.get('height', th))
    ys, xs = np.where(a[::3, ::3] > 0)
    xs = xs * 3; ys = ys * 3
    x = (xs * W / tw - float(f['pivotX'])) * ds
    y = (ys * H / th - float(f.get('pivotY', H))) * ds
    if clip.get('sourceFacing', 1) == -1 and not clip.get('authoredTurn'):
        x = -x
    return x, y


def calibrate_hitbox(move, clip, ds):
    frames = clip['frames']
    a0 = int(move.get('activeFrameStart', 0)); a1 = int(move.get('activeFrameEnd', a0))
    X, Y = [], []
    for i in range(max(0, a0), min(len(frames), a1 + 1)):
        if not frames[i].get('asset'):
            continue
        x, y = frame_points(frames[i], clip, ds)
        X.append(x); Y.append(y)
    if not X:
        return None
    x = np.concatenate(X); y = np.concatenate(Y)
    front = x > 10
    if front.sum() < 30:
        return None
    x = x[front]; y = y[front]
    x0, x1 = np.percentile(x, 1), np.percentile(x, 99)
    y0, y1 = np.percentile(y, 2), np.percentile(y, 99.5)
    x0 = max(-10.0, x0)
    mw, mh = HITBOX_MIN.get(move['id'], (90.0, 90.0))
    w = min(HITBOX_LIMIT[0], max(mw, x1 - x0)); h = min(HITBOX_LIMIT[1], max(mh, y1 - y0))
    cx = x0 + w / 2; cy = min((y0 + y1) / 2, -h / 2 + 6)
    return {'x': round(float(cx), 1), 'y': round(float(cy), 1), 'width': round(float(w), 1), 'height': round(float(h), 1)}


def dash_timeline(move, clip):
    """新时间轴 = 原时间轴 + 抵消画里“身体退到脚后面”的部分。"""
    old = move.get('movementTimelineAuthored') or move.get('movementTimeline') or []
    move['movementTimelineAuthored'] = old
    rm = clip.get('rootMotionX') or []
    frames = clip['frames']; n = len(frames)
    ticks = [float(f.get('durationTicks', 1)) for f in frames]
    total = sum(ticks)

    def old_at(t):
        pt, pd = 0.0, 0.0
        for p in old:
            et = min(max(float(p['time']), pt), 1.0); ed = float(p['distance'])
            if t <= et:
                w = 0 if et - pt < 1e-6 else (t - pt) / (et - pt)
                return pd + (ed - pd) * max(0.0, min(1.0, w))
            pt, pd = et, ed
        return pd
    out = [{'time': 0.0, 'distance': 0.0}]
    acc = 0.0
    for i in range(n):
        acc += ticks[i]
        t = acc / total
        back = -min(0.0, float(rm[min(i + 1, n - 1)]) if rm else 0.0)
        out.append({'time': round(t, 5), 'distance': round(old_at(t) + back, 2)})
    move['movementTimeline'] = out
    return out[-1]['distance']


def main():
    d = json.load(open(DATA, encoding='utf-8'))
    ch = d['characters'][0]; sp = ch['sprite']; A = sp['animations']; ds = float(sp['displayScale'])
    CLEAN.update(sp.get('assetCleanup', {}))
    # 1 跑步
    A['run']['fps'] = RUN_FPS
    ch['speed'] = round(RUN_STRIDE * RUN_FPS, 1)
    # 2 转身
    for name, (fps, flip, cancel) in TURN.items():
        A[name]['fps'] = fps
    loco = sp['locomotion']
    loco['turnRight'].update({'animation': 'turn_left_right', 'flipFrame': TURN['turn_left_right'][1], 'cancelFrame': TURN['turn_left_right'][2]})
    loco['turnLeft'].update({'animation': 'turn_right_left', 'flipFrame': TURN['turn_right_left'][1], 'cancelFrame': TURN['turn_right_left'][2]})
    loco['landingCancelFrame'] = 2
    # 3 缓冲 / 顿帧
    d['runtime']['attackBufferFrames'] = BUFFER_FRAMES
    report = []
    for m in d['moves']:
        if m['id'] in HITSTOP:
            a, v = HITSTOP[m['id']]
            m['hitstop'] = round(a / 60.0, 5); m['victimHitstop'] = round(v / 60.0, 5)
        if m['id'] in MOVE_SCALE:
            m['movementSpeedMultiplier'] = MOVE_SCALE[m['id']]
        clip = A.get(m.get('animation', ''), {})
        if m['id'] in HITSTOP and m['id'] != 'ranged_1' and clip.get('frames'):
            m.setdefault('hitboxAuthored', m.get('hitbox'))
            hb = calibrate_hitbox(m, clip, ds)
            if hb:
                m['hitbox'] = hb
        if m['id'].startswith('dash_slash'):
            end = dash_timeline(m, clip)
            report.append(f"{m['id']}: timeline end {end}")
        report.append(f"{m['id']:16s} hitbox {m.get('hitbox')} hs {m['hitstop']*60:.0f}/{m['victimHitstop']*60:.0f}")
    with open(DATA, 'w', encoding='utf-8') as fp:
        json.dump(d, fp, ensure_ascii=False, indent=2); fp.write('\n')
    print(f"run fps {RUN_FPS} speed {ch['speed']}")
    print('\n'.join(report))


if __name__ == '__main__':
    main()
