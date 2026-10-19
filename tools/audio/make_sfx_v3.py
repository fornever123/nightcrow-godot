#!/usr/bin/env python3
"""生成第二轮音效（assets/audio/sfx_v3/*.ogg.b64 + manifest.json）。

素材来源：
  - art/selected-video-audio/*.m4a（用户选的 6 段动作视频原声：刀风、拔刀“铮”、闷响）
  - assets/audio/combat_v2/*.wav（CC0，见同目录 LICENSE.txt）
  - 其余全部用代码合成（脚步、落地、命中肉感、金属弹刀、眩晕星星、碎石、混响……）
用法：python3 tools/audio/make_sfx_v3.py [预览目录]
  不带参数只写游戏用文件；带目录会额外写 wav 预览 + 频谱总览 overview.png。
每个声音都按“50ms 最大 RMS”归一到目标响度，所以游戏里基本不用再调增益。
"""
import os, sys, json, base64, tempfile
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from sfxlib import *

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'audio', 'sfx_v3')
SRC_DIR = os.path.join(ROOT, 'art', 'selected-video-audio')
PREVIEW = sys.argv[1] if len(sys.argv) > 1 else ''

_src = {}
def S(name):
    files = {'A': 'mmh3_action_00014.m4a', 'D': 'mmh3_冲刺攻击_v2.m4a', 'G': 'mmh3_左侧格挡_v5.m4a',
             'B': 'mmh3_拔刀40.m4a', 'X': 'mmh3_死亡_v1.m4a', 'K': '空中a.m4a'}
    if name not in _src:
        p = os.path.join(SRC_DIR, files[name]) if name in files else os.path.join(ROOT, 'assets', 'audio', name)
        _src[name] = decode(p)
    return _src[name]

def cut(name, t0, t1):
    x = S(name); return x[n(t0):n(t1)].copy()

# ---------------------------------------------------------------- 原声切片
# 刀风（起点, 终点）—— 都是原视频里一次挥刀的“呼——”
WHOOSH = {
    'A1': ('A', 0.82, 1.13), 'A2': ('A', 1.31, 1.66), 'A3': ('A', 2.05, 2.40), 'A4': ('A', 2.87, 3.26),
    'A5': ('A', 4.58, 4.92), 'A6': ('A', 5.05, 5.40), 'A7': ('A', 5.61, 5.96), 'A8': ('A', 6.30, 6.72),
    'A9': ('A', 7.11, 7.44), 'A12': ('A', 8.71, 9.06),
    'K1': ('K', 0.28, 0.64), 'K2': ('K', 0.64, 1.04), 'K3': ('K', 1.04, 1.60),
    'D0': ('D', 0.10, 0.62), 'D3': ('D', 1.14, 1.58), 'D4': ('D', 1.60, 2.25),
    'G2': ('G', 1.04, 1.47), 'G3': ('G', 1.71, 2.13), 'G4': ('G', 2.27, 2.73), 'G5': ('G', 2.96, 3.43),
    'G6': ('G', 5.99, 6.55), 'G7': ('G', 6.63, 7.12),
}

def whoosh(key, ratio=1.0, peak_at=0.05, length=None, hp_f=200, bright=0.0, seed=0):
    """原声刀风 → 去低频闷响 → 变调 → 把峰值对到 peak_at 秒（出招提示音提前 3 帧发）。"""
    name, a, b = WHOOSH[key]
    x = hp(cut(name, a, b), hp_f, 4)
    x = resample(x, ratio)
    pk = peak_time(x, 0.02)
    start = max(0, n(pk - peak_at))
    x = x[start:]
    if length: x = x[:n(length)]
    x = fade(x, 0.006, min(0.08, len(x) / SR * 0.35))
    if bright > 0:  # 刀刃“嘶”的一层：高频噪声，峰值对齐
        L = len(x) / SR
        edge = bp(noise(L, seed + 11), 3800, 9500) * swell(L, peak_at, 2.5, 0.035)
        x = x / (np.abs(x).max() + 1e-9) + bright * edge / (np.abs(edge).max() + 1e-9)
    return x

RING = lambda: hp(cut('B', 1.86, 2.42), 1800, 4)      # 拔刀 40 里的“铮——”尾音（高次分音）
SUB_THUMP = lambda: lp(cut('B', 0.33, 0.62), 220, 4)  # 拔刀 40 开头的低频闷响
THUMP2 = lambda: lp(cut('B', 5.13, 5.36), 400, 2)
BODYFALL = lambda: cut('X', 2.99, 3.34)

def legacy(name):
    return S(name)

# ---------------------------------------------------------------- 合成配方
def step(seed):
    r = rng(seed); p = r.uniform(0.92, 1.08)
    L = 0.11
    thump = sine_sweep(0.06, 150 * p, 70 * p) * env(0.06, 0.001, 0.012)
    scuff = bp(noise(0.06, seed), 1200 * p, 4800 * p) * env(0.06, 0.002, 0.011)
    grit = grains(0.06, 900, 0.02, seed, 3000, 8000)
    return mix(L, (thump, 0, 0.8), (scuff, 0.004, 0.45), (grit, 0.003, 0.5))

def jump(seed, double=False):
    L = 0.32
    if double:
        air = bp(noise(L, seed), 650, 5200) * swell(L, 0.045, 1.6, 0.075) * flutter(L, 26, 0.35, seed)
        lift = sweep_lp(noise(L, seed + 3), 600, 4200, 0.7) * swell(L, 0.06, 1.5, 0.09)
        wh = whoosh('K2', 1.35, 0.05, 0.3)
        return mix(L, (air, 0, 0.6), (hp(lift, 300), 0, 0.5), (wh / (np.abs(wh).max() + 1e-9), 0, 0.55))
    push = sine_sweep(0.07, 130, 65) * env(0.07, 0.001, 0.018)
    scuff = bp(noise(0.08, seed), 900, 4200) * env(0.08, 0.002, 0.016)
    cloth = bp(noise(L, seed + 1), 350, 2400) * swell(L, 0.055, 1.8, 0.07) * flutter(L, 21, 0.55, seed)
    return mix(L, (push, 0, 0.7), (scuff, 0, 0.35), (cloth, 0.01, 0.55))

def land(seed, heavy=False):
    r = rng(seed); p = r.uniform(0.94, 1.06)
    if not heavy:
        L = 0.2
        thump = sine_sweep(0.1, 120 * p, 55 * p) * env(0.1, 0.001, 0.028)
        body = lp(noise(0.08, seed), 700) * env(0.08, 0.001, 0.02)
        scuff = bp(noise(0.12, seed + 1), 1100, 5200) * env(0.12, 0.003, 0.03)
        grit = grains(0.14, 1400, 0.04, seed, 2800, 8000)
        return mix(L, (thump, 0, 0.9), (body, 0, 0.5), (scuff, 0.004, 0.35), (grit, 0.006, 0.45))
    L = 0.55
    sub = SUB_THUMP(); sub = sub / (np.abs(sub).max() + 1e-9)
    thump = sine_sweep(0.22, 95 * p, 38 * p) * env(0.22, 0.001, 0.06)
    crunch = lp(noise(0.15, seed), 2600) * env(0.15, 0.001, 0.035)
    debris = grains(0.45, 2200, 0.12, seed + 2, 2200, 7500)
    dust = lp(noise(0.4, seed + 3), 3000) * env(0.4, 0.01, 0.11)
    y = mix(L, (sub, 0, 0.55), (thump, 0, 1.0), (crunch, 0, 0.55), (debris, 0.01, 0.9), (dust, 0.0, 0.15))
    return reverb(y, 0.5, 0.12)

def hit(seed, tier):
    r = rng(seed); p = r.uniform(0.95, 1.05)
    click = bp(noise(0.006, seed), 2500, 9000) * env(0.006, 0.0002, 0.0015)
    if tier == 'light':
        click *= 0.6
        L = 0.28
        slice_ = bp(noise(0.12, seed + 1), 1600, 7500) * env(0.12, 0.0008, 0.024)
        body = sine_sweep(0.1, 175 * p, 82 * p) * env(0.1, 0.0008, 0.026)
        tear = bp(noise(0.09, seed + 2), 600, 2600) * env(0.09, 0.001, 0.03) * flutter(0.09, 140, 0.7, seed)
        crisp = lp(legacy('combat_v2/blade_crisp.wav')[:n(0.25)], 9000)
        y = mix(L, (click, 0, 0.7), (slice_, 0, 0.55), (body, 0, 0.75), (tear, 0.002, 0.35), (crisp / (np.abs(crisp).max() + 1e-9), 0, 0.22))
        return reverb(y, 0.35, 0.08)
    if tier == 'heavy':
        L = 0.45
        slice_ = bp(noise(0.16, seed + 1), 1300, 7000) * env(0.16, 0.0008, 0.036)
        body = sine_sweep(0.2, 135 * p, 52 * p) * env(0.2, 0.0008, 0.055)
        th = THUMP2(); th = th / (np.abs(th).max() + 1e-9)
        tear = bp(noise(0.14, seed + 2), 500, 2400) * env(0.14, 0.001, 0.045) * flutter(0.14, 120, 0.7, seed)
        crisp = legacy('combat_v2/blade_crisp.wav')[:n(0.35)]
        y = mix(L, (click, 0, 0.8), (slice_, 0, 0.6), (body, 0, 1.0), (th, 0.002, 0.55), (tear, 0.002, 0.4), (crisp / (np.abs(crisp).max() + 1e-9), 0, 0.28))
        return reverb(soft_clip(y, 1.3), 0.5, 0.12)
    # finisher：重击 + 金属长尾 + 次低频轰
    L = 0.9
    base = hit(seed, 'heavy')
    ring = RING(); ring = ring / (np.abs(ring).max() + 1e-9) * env(len(ring) / SR, 0.004, 0.16)
    boom = sine_sweep(0.7, 62 * p, 32 * p) * env(0.7, 0.002, 0.13)
    y = mix(L, (base, 0, 1.0), (ring, 0.008, 0.28), (boom, 0, 0.7))
    return reverb(y, 0.85, 0.16)

def hurt(seed, heavy=False):
    r = rng(seed); p = r.uniform(0.95, 1.05) * (0.86 if heavy else 1.0)
    L = 0.4
    body = sine_sweep(0.18, 105 * p, 48 * p) * env(0.18, 0.001, 0.05)
    crunch = soft_clip(bp(noise(0.1, seed), 350, 1800) * env(0.1, 0.001, 0.028) * 3, 2.0)
    smack = bp(noise(0.03, seed + 1), 1500, 6000) * env(0.03, 0.0005, 0.006)
    th = THUMP2(); th = th / (np.abs(th).max() + 1e-9)
    y = mix(L, (body, 0, 1.0), (crunch, 0, 0.45), (smack, 0, 0.5), (th, 0, 0.6 if heavy else 0.4))
    return reverb(y, 0.4, 0.08)

def clang(seed, f0, sec, tau, bright=1.0, noise_amt=0.6):
    ratios = [1.0, 1.585, 2.31, 2.97, 3.84, 4.62, 5.41, 6.73]
    amps = [1.0, 0.75, 0.6, 0.5, 0.38, 0.3, 0.22, 0.15]
    taus = [tau * (1.0 / (1 + 0.35 * k)) for k in range(len(ratios))]
    m = metal(sec, f0, ratios, [a * (bright ** k) for k, a in enumerate(amps)], taus, 1.4, seed)
    hitn = bp(noise(0.03, seed), 2000, 11000) * env(0.03, 0.0002, 0.004)
    return mix(sec, (m / (np.abs(m).max() + 1e-9), 0, 1.0), (hitn, 0, noise_amt))

def parry(seed):
    f0 = [1240, 1370][seed % 2]
    L = 1.7
    c = clang(seed, f0, 1.6, 0.42, 0.95, 0.9)
    ring = RING(); ring = ring / (np.abs(ring).max() + 1e-9)
    knock = sine_sweep(0.05, 230, 120) * env(0.05, 0.0005, 0.012)
    crisp = legacy('combat_v2/blade_crisp.wav'); crisp = hp(crisp, 1200) / (np.abs(crisp).max() + 1e-9)
    y = mix(L, (c, 0, 0.8), (ring, 0.004, 0.45), (knock, 0, 0.4), (crisp, 0, 0.3))
    return reverb(y, 1.0, 0.22, damp=6000)

def block(seed):
    f0 = [520, 590][seed % 2]
    L = 0.65
    c = clang(seed + 5, f0, 0.6, 0.11, 0.8, 1.0)
    thud = sine_sweep(0.08, 160, 85) * env(0.08, 0.0005, 0.02)
    scr = bp(noise(0.08, seed), 900, 4200) * env(0.08, 0.001, 0.018)
    y = mix(L, (c, 0, 0.75), (thud, 0, 0.6), (scr, 0, 0.35))
    return reverb(y, 0.45, 0.1)

def stun(seed):
    L = 1.45
    c = clang(seed + 9, 930, 1.3, 0.3, 0.9, 1.0)
    crack = soft_clip(bp(noise(0.06, seed), 900, 5200) * env(0.06, 0.0005, 0.012) * 3, 2.5)
    notes = [2093, 2637, 3136]
    stars = [bell(1.1, f, 0.22, 9.0, 0.012) for f in notes]
    y = mix(L, (c, 0, 0.6), (crack, 0, 0.5), (stars[0], 0.12, 0.16), (stars[1], 0.19, 0.14), (stars[2], 0.26, 0.13))
    return reverb(y, 0.9, 0.18, damp=7000)

def launch(seed):
    L = 0.42
    up = sweep_lp(noise(L, seed), 350, 5200, 0.8) * swell(L, 0.09, 1.4, 0.12)
    wh = whoosh('G5', 1.15, 0.06, 0.38); wh = wh / (np.abs(wh).max() + 1e-9)
    return mix(L, (hp(up, 250), 0, 0.7), (wh, 0, 0.6))

def slam(seed):
    L = 1.3
    sub = SUB_THUMP(); sub = sub / (np.abs(sub).max() + 1e-9)
    boom = sine_sweep(0.9, 72, 28) * env(0.9, 0.001, 0.22)
    crunch = lp(noise(0.2, seed), 2400) * env(0.2, 0.0005, 0.05)
    debris = grains(0.7, 2600, 0.2, seed + 1, 1800, 7000)
    crack = soft_clip(bp(noise(0.05, seed + 2), 700, 4000) * env(0.05, 0.0005, 0.01) * 3, 2.5)
    y = mix(L, (boom, 0, 1.0), (sub, 0, 0.6), (crunch, 0, 0.6), (crack, 0, 0.45), (debris, 0.012, 0.8))
    return reverb(soft_clip(y, 1.2), 0.9, 0.2)

def wall(seed):
    r = rng(seed); p = r.uniform(0.93, 1.07)
    L = 0.6
    thud = sine_sweep(0.25, 92 * p, 44 * p) * env(0.25, 0.0008, 0.07)
    crack = soft_clip(bp(noise(0.06, seed), 450, 2600) * env(0.06, 0.0005, 0.016) * 3, 2.2)
    debris = grains(0.4, 1800, 0.1, seed + 1, 1500, 6000)
    old = legacy('combat_v2/wall.wav')[:n(0.5)]; old = old / (np.abs(old).max() + 1e-9)
    y = mix(L, (thud, 0, 1.0), (crack, 0, 0.55), (debris, 0.01, 0.7), (old, 0, 0.35))
    return reverb(y, 0.6, 0.14)

def chain(seed):
    L = 1.3
    base = hit(seed + 30, 'heavy')
    d1 = bell(1.0, 1568, 0.25); d2 = bell(1.1, 2349, 0.3)
    return reverb(mix(L, (base, 0, 0.85), (d1, 0.03, 0.2), (d2, 0.09, 0.22)), 0.7, 0.15, damp=7000)

def shade_die(seed):
    L = 1.2
    hiss = sweep_lp(noise(1.15, seed), 7000, 380, 0.6) * swell(1.15, 0.03, 1.0, 0.24)
    whump = sine_sweep(0.3, 85, 38) * env(0.3, 0.002, 0.08)
    crackle = grains(1.0, 900, 0.25, seed + 1, 3000, 9000, 0.0015)
    y = mix(L, (hp(hiss, 120), 0, 0.55), (whump, 0, 0.7), (crackle, 0.02, 0.6))
    return reverb(y, 0.8, 0.15)

def windup(seed, heavy=False):
    if heavy:
        L = 0.5
        tt = t(np.zeros(n(L)))
        buzz = sum(np.sin(2 * np.pi * 92 * h * tt) / h for h in range(1, 12)) + 0.5 * np.sin(2 * np.pi * 139 * tt)
        hum = lp(buzz, 1100) * swell(L, 0.28, 1.5, 0.12) * flutter(L, 12, 0.4, seed)
        scrape = bp(noise(L, seed), 1800, 6000) * swell(L, 0.3, 2.0, 0.08)
        return mix(L, (hum, 0, 0.7), (scrape, 0, 0.35))
    L = 0.3
    shink = bp(noise(L, seed), 3200, 9500) * swell(L, 0.07, 2.0, 0.05)
    ring = metal(0.3, 2350, [1, 1.71, 2.62], [1, 0.5, 0.3], [0.07, 0.05, 0.04], 2.0, seed)
    return mix(L, (shink, 0, 0.7), (ring, 0.06, 0.25))

def shade_swing(seed, heavy=False):
    src = ['A4', 'A8'][seed % 2]
    x = whoosh(src, 0.72 if heavy else 0.84, 0.05, 0.42 if heavy else 0.32, 160)
    return lp(x, 3600 if heavy else 4800)

def seal(seed):
    L = 1.5
    boom = sine_sweep(1.3, 62, 38) * env(1.3, 0.003, 0.3)
    rumble = lp(noise(1.3, seed), 500) * env(1.3, 0.01, 0.25)
    gong = metal(1.45, 176, [1, 1.47, 2.09, 2.56, 3.2], [1, 0.6, 0.45, 0.3, 0.2], [0.55, 0.4, 0.3, 0.25, 0.2], 0.8, seed)
    y = mix(L, (boom, 0, 1.0), (rumble, 0, 0.45), (gong / (np.abs(gong).max() + 1e-9), 0.005, 0.35))
    return reverb(y, 1.2, 0.25)

def clear(seed):
    L = 1.6
    notes = [(659, 0.0), (988, 0.09), (1319, 0.18), (1976, 0.3)]
    y = mix(L, *[(bell(1.2, f, 0.55, 5.0, 0.004), o, 0.3) for f, o in notes])
    air = hp(noise(1.0, seed), 6000) * swell(1.0, 0.35, 1.5, 0.25)
    y = mix(L, (y, 0, 1.0), (air, 0, 0.05))
    return reverb(y, 1.4, 0.3, damp=8000)

def die(seed):
    L = 1.0
    fall = BODYFALL(); fall = fall / (np.abs(fall).max() + 1e-9)
    boom = sine_sweep(0.95, 70, 30) * env(0.95, 0.002, 0.2)
    return reverb(mix(L, (fall, 0, 0.8), (boom, 0, 0.7)), 0.9, 0.2)

def dash(seed):
    return whoosh('D0', [1.15, 1.22][seed % 2], 0.06, 0.34, 180)

# 招式刀风：每个招式两种（游戏里随机挑、再随机 ±3% 音高）
SWINGS = {
    'swing_l1': [('A7', 1.12, 0.22, 0.25), ('A2', 1.15, 0.22, 0.25)],
    'swing_l2': [('A12', 1.05, 0.26, 0.2), ('A5', 1.10, 0.26, 0.3)],
    'swing_l3': [('D4', 1.00, 0.42, 0.35), ('G6', 0.97, 0.42, 0.35)],
    'swing_charge': [('D4', 0.88, 0.5, 0.3), ('G7', 0.92, 0.5, 0.25)],
    'swing_up': [('G5', 1.05, 0.38, 0.25), ('G4', 1.05, 0.38, 0.25)],
    'swing_air1': [('K1', 1.15, 0.26, 0.25), ('A3', 1.15, 0.26, 0.25)],
    'swing_air2': [('K2', 1.10, 0.28, 0.25), ('A6', 1.12, 0.28, 0.25)],
    'swing_air3': [('K3', 0.95, 0.4, 0.3), ('A9', 0.95, 0.36, 0.3)],
    'swing_air_up': [('G3', 1.10, 0.3, 0.25), ('G2', 1.10, 0.3, 0.25)],
    'swing_dash': [('D3', 1.0, 0.4, 0.3), ('A1', 1.0, 0.32, 0.3)],
}

def swing(key, i):
    src, ratio, length, bright = SWINGS[key][i]
    y = whoosh(src, ratio, 0.05, length, 200, bright, seed=i)
    if key in ('swing_l3', 'swing_charge'):   # 重刀：再垫一层低频“呼”
        L = len(y) / SR
        body = lp(noise(L, 40 + i), 900) * swell(L, 0.06, 1.6, 0.09)
        y = y / (np.abs(y).max() + 1e-9) + 0.35 * body / (np.abs(body).max() + 1e-9)
    if key == 'swing_charge':
        ring = RING(); ring = ring / (np.abs(ring).max() + 1e-9)
        y = mix(len(y) / SR + 0.1, (y, 0, 1.0), (ring, 0.04, 0.22))
    if key in ('swing_up', 'swing_air_up'):   # 上挑：往上扫的气流
        L = len(y) / SR
        up = hp(sweep_lp(noise(L, 50 + i), 500, 6000, 0.7), 300) * swell(L, 0.06, 1.5, 0.08)
        y = y / (np.abs(y).max() + 1e-9) + 0.35 * up / (np.abs(up).max() + 1e-9)
    return y

# key: (生成函数, 变体数, 目标响度 dB(50ms RMS), 总线, 音高抖动)
SPEC = {
    'step': (step, 4, -28.0, 'motion', 0.05),
    'jump': (lambda s: jump(s), 2, -22.0, 'motion', 0.03),
    'jump_double': (lambda s: jump(s, True), 2, -21.0, 'motion', 0.03),
    'land_light': (lambda s: land(s), 3, -21.0, 'motion', 0.04),
    'land_heavy': (lambda s: land(s, True), 2, -14.0, 'impact', 0.03),
    'dash': (dash, 2, -21.0, 'motion', 0.03),
    'hit_light': (lambda s: hit(s, 'light'), 3, -12.5, 'impact', 0.04),
    'hit_heavy': (lambda s: hit(s, 'heavy'), 3, -11.0, 'impact', 0.03),
    'hit_finisher': (lambda s: hit(s, 'finisher'), 2, -10.0, 'impact', 0.02),
    'hurt': (lambda s: hurt(s), 2, -11.5, 'impact', 0.03),
    'hurt_heavy': (lambda s: hurt(s, True), 2, -10.5, 'impact', 0.03),
    'parry': (parry, 2, -11.0, 'impact', 0.02),
    'block': (block, 2, -13.0, 'impact', 0.03),
    'stun': (stun, 1, -11.5, 'impact', 0.0),
    'launch': (launch, 2, -16.0, 'impact', 0.03),
    'slam': (slam, 2, -9.5, 'impact', 0.03),
    'wall': (wall, 2, -11.5, 'impact', 0.04),
    'chain': (chain, 1, -12.5, 'impact', 0.0),
    'shade_die': (shade_die, 2, -16.0, 'impact', 0.04),
    'shade_windup': (lambda s: windup(s), 2, -25.0, 'motion', 0.04),
    'shade_windup_heavy': (lambda s: windup(s, True), 1, -22.0, 'motion', 0.02),
    'shade_swing': (lambda s: shade_swing(s), 2, -21.0, 'motion', 0.04),
    'shade_swing_heavy': (lambda s: shade_swing(s, True), 2, -19.0, 'motion', 0.03),
    'seal': (seal, 1, -16.0, 'ui', 0.0),
    'clear': (clear, 1, -18.0, 'ui', 0.0),
    'die': (die, 1, -12.0, 'impact', 0.0),
}
for k in SWINGS:
    heavy = k in ('swing_l3', 'swing_charge', 'swing_dash', 'swing_air3')
    SPEC[k] = ((lambda key: (lambda s: swing(key, s)))(k), len(SWINGS[k]), -17.5 if heavy else -19.0, 'motion', 0.03)


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith('.ogg.b64'): os.remove(os.path.join(OUT, f))
    if PREVIEW: os.makedirs(PREVIEW, exist_ok=True)
    manifest = {'note': '由 tools/audio/make_sfx_v3.py 生成，勿手改；混音微调写在 battle.json audio.gainDb', 'clips': {}}
    report = []; total = 0
    for key, (fn, count, target, bus, jitter) in SPEC.items():
        files = []; pk_t = 0.0
        for i in range(count):
            y = fn(i)
            y = trim_tail(normalize(y, target, -1.0), -58)
            pk_t = peak_time(y)
            with tempfile.NamedTemporaryFile(suffix='.ogg', delete=False) as tf: tmp = tf.name
            encode_ogg(y, tmp, 5)
            data = open(tmp, 'rb').read(); os.remove(tmp)
            name = '%s_%d.ogg.b64' % (key, i)
            open(os.path.join(OUT, name), 'w').write(base64.b64encode(data).decode() + '\n')
            files.append(name); total += len(data)
            report.append((key, i, len(y) / SR, rms_max_db(y), peak_db(y), pk_t, len(data)))
            if PREVIEW: write_wav(y, os.path.join(PREVIEW, '%s_%d.wav' % (key, i)))
        manifest['clips'][key] = {'files': files, 'bus': bus, 'pitchJitter': jitter}
    json.dump(manifest, open(os.path.join(OUT, 'manifest.json'), 'w'), ensure_ascii=False, indent=1)
    for r in report:
        print('%-20s %d  %.2fs  rms %.1f  peak %.1f  peak@%.3f  %5dB' % r)
    print('total ogg bytes', total, 'clips', len(report))
    # The user's selected original sounds take priority over these old recipes.
    from apply_selected_video_audio import main as apply_selected_video_audio
    apply_selected_video_audio()


if __name__ == '__main__':
    main()
