#!/usr/bin/env python3
"""第四轮音效：命中 / 受击 / 撞墙 / 砸地等换成 Kenney CC0 真实录音叠层（替掉之前的合成声）。

只改下面 SPEC 里列的事件，其他条目（16 段用户选的视频原声、脚步、跳跃……）原样保留。
素材：Kenney "Impact Sounds" + "RPG Audio"（CC0，见 assets/audio/sfx_v3/LICENSE-Kenney.txt）。
  本地没有会自动下载到 KENNEY_DIR（默认 /data/sfxsrc）。
用法：python3 tools/audio/make_hits_v4.py [预览目录]
  在 make_sfx_v3.py 之后跑（make_sfx_v3 结尾会自动调用本脚本）。
原则（对照《疯狂小人战斗》那种干脆的打击声）：
  - 开头不留静音，峰值在前 15ms 内 → 和顿帧同一帧响
  - 短：轻击 ≤0.25s，重击 ≤0.4s，终结/砸地 ≤0.6s，只有大招允许 0.9s
  - 命中最响（50ms RMS ≈ −9～−11 dB），刀风（视频原声）约 −16～−18 dB
"""
import os, sys, json, base64, tempfile, zipfile, urllib.request, glob
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
from sfxlib import *

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = os.path.join(ROOT, 'assets', 'audio', 'sfx_v3')
KENNEY_DIR = os.environ.get('KENNEY_DIR', '/data/sfxsrc')
PACKS = {
    'impact': 'https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip',
    'rpg': 'https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip',
}
PREVIEW = sys.argv[1] if len(sys.argv) > 1 else ''


def ensure_sources():
    for pack, url in PACKS.items():
        d = os.path.join(KENNEY_DIR, pack)
        if glob.glob(os.path.join(d, '**', '*.ogg'), recursive=True):
            continue
        os.makedirs(d, exist_ok=True)
        z = os.path.join(KENNEY_DIR, pack + '.zip')
        if not os.path.exists(z):
            urllib.request.urlretrieve(url, z)
        zipfile.ZipFile(z).extractall(d)


_cache = {}
def K(name):
    """按文件名（不带 .ogg）取一段 Kenney 原声：去开头静音，峰值归一到 0dB。"""
    if name not in _cache:
        hits = glob.glob(os.path.join(KENNEY_DIR, '**', name + '.ogg'), recursive=True)
        if not hits:
            raise FileNotFoundError(name)
        x = decode(hits[0])
        a = np.abs(x); on = max(0, int(np.argmax(a > a.max() * 0.05)) - n(0.002))
        x = x[on:]
        _cache[name] = x / (np.abs(x).max() + 1e-12)
    return _cache[name].copy()


def L(name, gain_db=0.0, at=0.0, ratio=1.0, length=None, hp_f=None, lp_f=None, fout=0.04):
    """一层：(信号, 偏移秒, 线性增益)，给 mix() 用。"""
    x = resample(K(name), ratio)
    if hp_f: x = hp(x, hp_f)
    if lp_f: x = lp(x, lp_f)
    if length: x = x[:n(length)]
    x = fade(x, 0.0015, min(fout, len(x) / SR * 0.5))
    return (x, at, 10 ** (gain_db / 20))


def sub_boom(sec, f0=70, f1=38, tau=0.12):
    """低频“咚”，给砸地 / 爆炸 / 大招垫底。"""
    return sine_sweep(sec, f0, f1) * env(sec, 0.002, tau)


def pick(lst, i):
    return lst[i % len(lst)]


# ---------------------------------------------------------------- 配方
PUNCH_M = ['impactPunch_medium_000', 'impactPunch_medium_001', 'impactPunch_medium_003', 'impactPunch_medium_004']
PUNCH_H = ['impactPunch_heavy_000', 'impactPunch_heavy_001', 'impactPunch_heavy_003', 'impactPunch_heavy_004']
SOFT_H = ['impactSoft_heavy_000', 'impactSoft_heavy_001', 'impactSoft_heavy_002']
SOFT_M = ['impactSoft_medium_001', 'impactSoft_medium_004', 'impactSoft_medium_000']
MINING = ['impactMining_000', 'impactMining_001', 'impactMining_004']


def hit_light(i):
    # 肉感“啪” + 一点点刀刃“嚓”（高通过，只留咬合感）
    return mix(0.24, L(pick(PUNCH_M, i), 0, ratio=1.08 + 0.04 * i, length=0.2, hp_f=140),
               L('knifeSlice2', -9, 0.0, ratio=1.15, length=0.09, hp_f=2500),
               L(pick(SOFT_M, i), -8, 0, length=0.1))


def hit_heavy(i):
    return mix(0.38, L(pick(PUNCH_H, i), 0, ratio=1.0 + 0.03 * i, length=0.34, hp_f=90),
               L(pick(SOFT_H, i), -5, 0, ratio=1.1, length=0.22, lp_f=400),
               L('knifeSlice2', -8, 0.0, length=0.1, hp_f=2200))


def hit_finisher(i):
    y = mix(0.55, L(pick(PUNCH_H, i + 1), 0, ratio=0.94, length=0.42, hp_f=70),
            L(pick(SOFT_H, i), -3, 0, ratio=0.9, length=0.3, lp_f=350),
            L(pick(MINING, i), -11, 0.004, ratio=1.1, length=0.22, hp_f=600),
            L('knifeSlice', -7, 0.0, length=0.14, hp_f=2000),
            (sub_boom(0.3, 80, 42, 0.09), 0, 0.5))
    return reverb(y, 0.35, 0.10, damp=2500)[:n(0.55)]


def hurt(i):
    # 玩家挨打：更闷、更低，不带刀刃声
    return mix(0.28, L(pick(PUNCH_M, i + 2), 0, ratio=0.86, length=0.24, hp_f=80),
               L(pick(SOFT_M, i + 1), -4, 0, ratio=0.9, length=0.14))


def hurt_heavy(i):
    return mix(0.38, L(pick(PUNCH_H, i + 2), 0, ratio=0.84, length=0.34, hp_f=60),
               L(pick(SOFT_H, i + 1), -3, 0, ratio=0.95, length=0.25, lp_f=380))


def wall(i):
    # 撞墙：木石“咚”+碎石
    return mix(0.4, L(pick(['impactWood_heavy_000', 'impactWood_heavy_002', 'impactWood_heavy_004'], i), 0, length=0.3),
               L(pick(MINING, i + 1), -6, 0.003, ratio=1.05, length=0.3, hp_f=300),
               L(pick(PUNCH_H, i), -6, 0, length=0.25))


def slam(i):
    return mix(0.6, L(pick(SOFT_H, i + 2), 0, ratio=0.8, length=0.45, lp_f=500),
               L(pick(MINING, i + 2), -4, 0.005, ratio=0.95, length=0.45),
               L(pick(PUNCH_H, i + 1), -7, 0, ratio=0.9, length=0.3),
               (sub_boom(0.45, 70, 36, 0.14), 0, 0.6))


def chain(i):
    # 连段加档：短促清脆的“叮”
    return mix(0.32, L('impactMetal_light_001', 0, ratio=1.25, length=0.3, hp_f=900),
               L('impactGeneric_light_000', -6, 0, length=0.12))


def deflect(i):
    # 箭 / 炸弹被打回去：金属“铛”
    return mix(0.3, L(pick(['impactMetal_medium_000', 'impactMetal_medium_003'], i), 0, length=0.28),
               L('impactMetal_light_001', -5, 0, ratio=1.3, length=0.2, hp_f=1500))


def guard_break(i):
    # 格挡被砸开：铁板重击 + 碎裂
    return mix(0.45, L('impactPlate_heavy_001', 0, ratio=0.95, length=0.35),
               L('impactGlass_heavy_003', -7, 0.01, ratio=0.9, length=0.17),
               L(pick(PUNCH_H, i), -5, 0, length=0.3))


def bomb(i):
    y = mix(0.7, L(pick(MINING, i + 1), 0, ratio=0.72, length=0.6),
            L(pick(SOFT_H, i), -2, 0, ratio=0.6, length=0.5, lp_f=300),
            (lp(noise(0.5, 11 + i), 1800) * env(0.5, 0.002, 0.12), 0, 0.5),
            (sub_boom(0.6, 60, 30, 0.2), 0, 0.8))
    return reverb(y, 0.5, 0.12, damp=2000)[:n(0.7)]


def shade_shot(i):
    # 影弓放箭：短“嗖”+弦响
    return mix(0.3, L('knifeSlice2', 0, 0, ratio=1.15 + 0.05 * i, length=0.22, hp_f=1500, lp_f=9000),
               L('metalClick', -10, 0, ratio=0.9, length=0.06))


def ult_start(i):
    # 大招起手：拔刀“铮” + 低沉钟声（降调、低通，像空气一沉）
    y = mix(0.9, L('drawKnife3', 0, 0, length=0.45),
            L('impactBell_heavy_001', -6, 0, ratio=0.5, length=0.9, lp_f=900, fout=0.4),
            (sub_boom(0.6, 55, 40, 0.25), 0, 0.35))
    return reverb(y, 0.6, 0.15, damp=2500)[:n(0.9)]


def ult_slash(i):
    y = mix(0.9, L('knifeSlice2', -2, 0, ratio=0.85, length=0.25, hp_f=1200),
            L('impactPunch_heavy_002', 0, 0.01, ratio=0.85, length=0.4),
            L('impactSoft_heavy_003', 0, 0.01, ratio=0.7, length=0.45, lp_f=320),
            L('impactMining_004', -6, 0.012, ratio=0.85, length=0.4),
            (sub_boom(0.7, 70, 30, 0.22), 0.01, 0.8))
    return reverb(y, 0.7, 0.14, damp=2200)[:n(0.9)]


def step(i):
    # 脚步：石板路实录，很轻
    return mix(0.11, L(pick(['footstep_concrete_000', 'footstep_concrete_003', 'footstep_concrete_004', 'footstep_concrete_001'], i),
                       0, ratio=0.95 + 0.03 * i, length=0.11, lp_f=6000))


def jump(i):
    return mix(0.3, L(pick(['cloth1', 'cloth3'], i), 0, ratio=1.1, length=0.28),
               L(pick(['footstep_concrete_003', 'footstep_concrete_000'], i), -6, 0, length=0.08))


def jump_double(i):
    return mix(0.32, L(pick(['cloth1', 'cloth2'], i), 0, ratio=1.3, length=0.28),
               L('knifeSlice', -12, 0.02, ratio=0.8, length=0.2, lp_f=5000))


def land_light(i):
    return mix(0.16, L(pick(['footstep_concrete_000', 'footstep_concrete_004', 'footstep_concrete_003'], i), 0, ratio=0.85, length=0.11),
               L(pick(SOFT_M, i), -5, 0, length=0.1))


def land_heavy(i):
    return mix(0.35, L(pick(SOFT_H, i), 0, ratio=0.95, length=0.3, lp_f=600),
               L(pick(['footstep_concrete_000', 'footstep_concrete_004'], i), -3, 0, ratio=0.8, length=0.11),
               L(pick(MINING, i), -14, 0.004, length=0.25, hp_f=500))


def launch(i):
    # 被挑飞：衣服猎猎 + 一下闷顶
    return mix(0.36, L(pick(['cloth1', 'cloth3'], i + 1), 0, ratio=1.15, length=0.34),
               L(pick(SOFT_M, i), -3, 0, length=0.12))


def shade_die(i):
    # 影子散掉：轻碎裂 + 闷响 + 衣料散开
    return mix(0.5, L(pick(['impactGlass_light_000', 'impactGlass_light_003'], i), -4, 0, ratio=0.75, length=0.22, lp_f=5000),
               L(pick(SOFT_H, i + 1), 0, 0, ratio=1.05, length=0.25, lp_f=500),
               L(pick(['cloth2', 'cloth3'], i), -8, 0.03, ratio=0.85, length=0.4))


def stun(i):
    # 破防眩晕：“当——”一声短促的铁响
    return mix(0.5, L('impactBell_heavy_004', 0, 0, ratio=1.7, length=0.25),
               L('impactMetal_light_003', -4, 0.0, ratio=1.15, length=0.45, fout=0.2))


def shade_windup(i, heavy=False):
    # 影卒抬手（提示要出手了）：衣料一抖 + 兵器“咔”
    if heavy:
        return mix(0.5, L('cloth1', 0, 0, ratio=0.72, length=0.48, fout=0.15),
                   L('metalLatch', -6, 0.02, ratio=0.75, length=0.2))
    return mix(0.3, L(pick(['cloth2', 'cloth3'], i), 0, ratio=1.0, length=0.28),
               L('metalLatch', -8, 0.01, ratio=1.0 + 0.05 * i, length=0.15))


def shade_swing(i, heavy=False):
    if heavy:
        return mix(0.4, L('knifeSlice2', 0, 0, ratio=0.58 + 0.04 * i, length=0.38, lp_f=4500),
                   L('cloth1', -6, 0, ratio=0.8, length=0.3))
    return mix(0.3, L('knifeSlice2', 0, 0, ratio=0.78 - 0.06 * i, length=0.28, lp_f=6000),
               L('cloth4', -6, 0, length=0.2))


def shorten(key, sec):
    """旧声太长：沿用原素材，只截短 + 淡出。"""
    def f(i):
        p = os.path.join(OUT, '%s_%d.ogg.b64' % (key, i))
        with tempfile.NamedTemporaryFile(suffix='.ogg', delete=False) as tf:
            tf.write(base64.b64decode(open(p).read())); tmp = tf.name
        x = decode(tmp); os.remove(tmp)
        x = x[:n(sec)]
        return fade(x, 0.0, min(0.15, sec * 0.35))
    return f


# 键: (函数, 变体数, 目标 50ms RMS dB, 总线, 音高抖动)
SPEC = {
    'hit_light':    (hit_light, 3, -11.0, 'impact', 0.05),
    'hit_heavy':    (hit_heavy, 3, -10.0, 'impact', 0.04),
    'hit_finisher': (hit_finisher, 2, -9.0, 'impact', 0.03),
    'hurt':         (hurt, 2, -11.0, 'impact', 0.04),
    'hurt_heavy':   (hurt_heavy, 2, -10.0, 'impact', 0.03),
    'wall':         (wall, 2, -10.5, 'impact', 0.04),
    'slam':         (slam, 2, -9.5, 'impact', 0.03),
    'chain':        (chain, 1, -15.0, 'impact', 0.0),
    'deflect':      (deflect, 2, -12.0, 'impact', 0.04),
    'guard_break':  (guard_break, 1, -10.0, 'impact', 0.02),
    'bomb':         (bomb, 2, -9.0, 'impact', 0.04),
    'shade_shot':   (shade_shot, 2, -19.0, 'motion', 0.05),
    'ult_start':    (ult_start, 1, -14.0, 'impact', 0.0),
    'ult_slash':    (ult_slash, 1, -8.0, 'impact', 0.0),
    # 原来的合成声（噪声“沙沙”太多）也换成实录；目标响度沿用旧值，混音不变
    'step':         (step, 4, -28.0, 'motion', 0.05),
    'jump':         (jump, 2, -22.0, 'motion', 0.03),
    'jump_double':  (jump_double, 2, -21.0, 'motion', 0.03),
    'land_light':   (land_light, 3, -21.0, 'motion', 0.04),
    'land_heavy':   (land_heavy, 2, -14.0, 'impact', 0.03),
    'launch':       (launch, 2, -16.0, 'impact', 0.03),
    'shade_die':    (shade_die, 2, -15.0, 'impact', 0.04),
    'stun':         (stun, 1, -13.0, 'impact', 0.0),
    'shade_windup': (shade_windup, 2, -24.0, 'motion', 0.04),
    'shade_windup_heavy': (lambda i: shade_windup(i, True), 1, -21.0, 'motion', 0.02),
    'shade_swing':  (shade_swing, 2, -20.0, 'motion', 0.04),
    'shade_swing_heavy': (lambda i: shade_swing(i, True), 2, -18.5, 'motion', 0.03),
}
# 已有但太长的：截短（秒）
SHORTEN = {}


def write_clip(key, i, y, total, report):
    with tempfile.NamedTemporaryFile(suffix='.ogg', delete=False) as tf: tmp = tf.name
    encode_ogg(y, tmp, 5)
    data = open(tmp, 'rb').read(); os.remove(tmp)
    name = '%s_%d.ogg.b64' % (key, i)
    open(os.path.join(OUT, name), 'w').write(base64.b64encode(data).decode() + '\n')
    report.append((key, i, len(y) / SR, rms_max_db(y), peak_db(y), peak_time(y), len(data)))
    if PREVIEW: write_wav(y, os.path.join(PREVIEW, '%s_%d.wav' % (key, i)))
    return name


def main():
    ensure_sources()
    if PREVIEW: os.makedirs(PREVIEW, exist_ok=True)
    mpath = os.path.join(OUT, 'manifest.json')
    manifest = json.load(open(mpath))
    clips = manifest['clips']
    report = []
    # 先截短（要读旧文件，所以在删除前做）
    shortened = {}
    for key, (count, sec, target) in SHORTEN.items():
        f = shorten(key, sec)
        shortened[key] = [trim_tail(normalize(f(i), target, -1.0), -58) for i in range(count)]
    for key, (count, sec, target) in SHORTEN.items():
        files = [write_clip(key, i, y, 0, report) for i, y in enumerate(shortened[key])]
        clips[key]['files'] = files
    for key, (fn, count, target, bus, jitter) in SPEC.items():
        old = clips.get(key, {})
        if old.get('sourceVideo'):
            continue   # 用户选的视频原声优先，不覆盖
        for f in os.listdir(OUT):
            if f.startswith(key + '_') and f.endswith('.ogg.b64') and f[len(key) + 1:-8].isdigit():
                os.remove(os.path.join(OUT, f))
        files = []
        for i in range(count):
            y = trim_tail(normalize(fn(i), target, -1.0), -56)
            files.append(write_clip(key, i, y, 0, report))
        clips[key] = {'files': files, 'bus': bus, 'pitchJitter': jitter}
    manifest['note'] = ('由 tools/audio/make_sfx_v3.py 生成，命中/受击/撞墙等由 make_hits_v4.py（Kenney CC0 实录）覆盖；'
                        '勿手改；混音微调写在 battle.json audio.gainDb')
    json.dump(manifest, open(mpath, 'w'), ensure_ascii=False, indent=1)
    for r in report:
        print('%-14s %d  %.2fs  rms %.1f  peak %.1f  peak@%.3f  %5dB' % r)


if __name__ == '__main__':
    main()
