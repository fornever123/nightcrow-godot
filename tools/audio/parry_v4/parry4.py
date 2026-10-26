"""弹刀第四版：按著名游戏弹刀的实测数据来做（refs/analysis.json，用 analyze_refs.py 量出来）。

《只狼》弹刀实测：嗡鸣主音 1.75k–4.0kHz、衰减 40dB 0.86–2.34s；100Hz 以下低频冲击衰减 20dB 0.24–0.47s；
4kHz 以上火花衰减 20dB 0.25–0.64s；0.5s 时嗡鸣比起音低 10–21dB。上一版错在嗡鸣放在 0.4–1kHz（低了一到两个八度）、
低频冲击只有 0.07s。

结构（全部以真实录音为底）：
  起音   Still North 真实刀刃撞击（最多降到 0.75 倍，保住高频的"锵"）
  身体   真实闷金属撞击（blacklodgegames 27 Metal，CC0）的 150–1200Hz
  嗡鸣   用这一下撞击里刀身真实的共振比例，在目标频率上延长（稳定，不颤；只留极慢的光泽变化）
  金属共振 撞击送进上百个金属振动模式的共振器，得到尾音里密集的"沙沙"质感（只在 1.5kHz 以上）
  火花   撞击的 4kHz 以上部分过一个明亮的短混响，拖出 0.3–0.5s 的"嘶"
  力量   75→45Hz 超低频轰（加饱和）+ 真实铃铛降两个八度 + 真实拳击，衰减约 0.35s
  空间   很短的立体声小空间
  压缩   快起音 4:1，让前 200ms 像《只狼》一样又响又厚（只掉 3–4dB）

用法：python -I parry4.py  → processed3/cand3_parry_*.wav + processed3/stats.json
"""
import os, sys, json
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import realistic as R   # noqa: E402  复用读取、滤波、门限、混响等工具

SR = R.SR
n = R.n
OUT = os.path.join(HERE, 'processed3')


def source_hit(rank):
    hit = json.load(open(os.path.join(HERE, 'scan', 'still_north_hits.json'), encoding='utf-8'))['top'][rank]
    raw = R.load(os.path.join('still-north', 'x', hit['file']), 192000)
    a = max(0, int((hit['t'] - 0.01) * 192000)); seg = raw[a:a + int((hit['len'] - 0.03) * 192000)]
    seg = R.gate(R.hp(seg, 150, 192000), -48, 192000)
    seg = seg[R.onset(seg, 192000, 0.06):]
    k = int(0.12 * 192000); seg[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return seg, hit


def at_speed(seg, ratio):
    """192k 源，ratio>1 = 升调变短，<1 = 降调变长；输出 48k。"""
    idx = np.arange(0, len(seg) - 1, 4 * ratio)
    return np.interp(idx, np.arange(len(seg)), seg)


def ring(partials, f_target, sec, tau, seed, shimmer=0.0008, bloom=0.025, side=0.55):
    """嗡鸣：把刀身真实共振整体移到 f_target；主音最长，越往上衰减越快。
    每个分音配一个只差 0.08% 的副本 → 2Hz 左右的缓慢光泽，不会"颤"。"""
    r = np.random.default_rng(seed); t = np.arange(n(sec)) / SR; y = np.zeros(len(t))
    scale = f_target / partials[0][0]
    for k, (fr, amp) in enumerate(partials):
        f0 = fr * scale
        amp = amp if k == 0 else amp * side   # 一条主音为主，其余共振压低（多条同样亮的谱线会像和弦/合成音）
        if f0 > 16000:
            continue
        ta = tau * (f_target / f0) ** 0.6 if f0 > f_target else tau * 0.8
        ph = r.uniform(0, 2 * np.pi)
        y += amp * np.exp(-t / ta) * (np.sin(2 * np.pi * f0 * t + ph) + 0.5 * np.sin(2 * np.pi * f0 * (1 + shimmer) * t + ph + 1.0))
    return R.unit(y) * np.clip(t / bloom, 0, 1) ** 1.5    # 振鸣在撞击后"冒"出来，不叠在起音峰值上


def power(seg, tau):
    """力量层。实测真实铃铛/拳击里能持续的低频比撞击那一下弱 25–30dB，降调后 150ms 就掉 18dB，撑不起《只狼》
    0.24–0.47s 的低频轰。40–80Hz 听不出音色，所以主体用 75→45Hz 下滑的超低频 + 轻微饱和（产生 100–200Hz 谐波，
    小音箱也听得到）；真实铃铛降两个八度和真实拳击只给头部质感。前 30ms 保持满，之后按 tau 衰减。"""
    L = n(1.5); t = np.arange(L) / SR
    f = 45 + 30 * np.exp(-t / 0.08)
    sub = np.tanh(1.8 * np.sin(2 * np.pi * np.cumsum(f) / SR)) / np.tanh(1.8)
    bell = R.load('kenney-impact/impactBell_heavy_001.ogg'); bell = bell[R.onset(bell):]
    bell = R.lp(np.interp(np.arange(0, len(bell) - 1, 0.25), np.arange(len(bell)), bell), 250)[:L]
    a = R.lp(R.load('fleshy-fight/x/punch_alt-2a.wav'), 200); a = a[R.onset(a):][:L]
    y = sub.copy(); y[:len(bell)] += 0.4 * R.unit(bell); y[:len(a)] += 0.3 * R.unit(a)
    env = np.minimum(1.0, np.exp(-(t - 0.03) / tau)) * np.clip(t / 0.002, 0, 1)
    return R.unit(y * env)


def shimmer(x, T, seed, lo=1500, hi=14000, count=140, smooth=False):
    """金属共振：把真实撞击（1.5kHz 以上的头 30ms）送进一个有上百个金属振动模式的共振器，
    得到这一下撞击在刀身里回荡的密集"沙沙"质感（《只狼》尾音里那一片）。模式频率对数均匀分布，越高衰减越快。"""
    r = np.random.default_rng(seed); t = np.arange(n(T * 5)) / SR; ir = np.zeros(len(t))
    for _ in range(count):
        f = lo * (hi / lo) ** r.random()
        tau = T * (lo / f) ** 0.5 * r.uniform(0.7, 1.3)
        # smooth：模式更多、单个振幅差异小、高频更弱 → 均匀的金属光泽，不会有个别模式冒出来变成杂乱的"沙"
        amp = r.uniform(0.75, 1.0) * (f / lo) ** -0.9 if smooth else r.uniform(0.3, 1.0) * (f / lo) ** -0.6
        ir += amp * np.exp(-t / tau) * np.sin(2 * np.pi * f * t + r.uniform(0, 2 * np.pi))
    excite = R.hp(x[:n(0.03)], lo)
    return R.unit(R.conv(excite, ir))


def sparks(x, t60):
    """火花：撞击的 4kHz 以上 + 明亮短混响 → 0.3–0.5s 的"嘶"。"""
    h = R.hp(x, 4000)
    w = R.conv(h, R.reverb_ir(t60, 7, damp=15000, pre=0.002))
    return R.unit(w)


def compress(st, thr_db, ratio=4.0, attack=0.001, release=0.08):
    """立体声联动压缩：快起音、80ms 释放。《只狼》弹刀前 200ms 只掉 1–4dB，是一堵又响又厚的声墙，
    靠压缩把起音尖峰压下来、让后面的层托上来。"""
    m = np.abs(st).max(axis=0)
    thr = m.max() * 10 ** (thr_db / 20)
    a_c, r_c = np.exp(-1 / (attack * SR)), np.exp(-1 / (release * SR))
    env = np.empty_like(m); e = 0.0
    for i, v in enumerate(m):
        e = a_c * e + (1 - a_c) * v if v > e else r_c * e + (1 - r_c) * v
        env[i] = e
    over = np.maximum(env / thr, 1.0)
    gain = over ** (1 / ratio - 1)
    return st * gain


def build(spec):
    seg, hit = source_hit(spec['src'])
    if spec.get('src_cut'):   # 只留主撞击：原录音里后面的余颤/二次碰撞会变成"咔嗒"杂响，在它之前截断并淡出
        k = int(spec['src_cut'] * 192000); f = int(0.03 * 192000)
        seg = seg[:k].copy(); seg[-f:] *= np.cos(np.linspace(0, np.pi / 2, f)) ** 2
    parts = R.blade_partials(seg, 192000, 6, 1200, 7000)      # 刀身真实共振（按强度排序，第一个最强）
    scale = spec['f0'] / parts[0][0]
    hit_scale = float(np.clip(scale, 0.75, 1.1))               # 起音最多降到 0.75 倍，保住高频的"锵"
    hitx = R.unit(at_speed(seg, hit_scale))
    if spec.get('click', 0):   # 起音提亮：撞击开头 15ms 的 2kHz 以上再叠一层，"锵"更清楚
        k = n(0.015); c = R.hp(hitx[:n(0.03)], 2000); c[k:] *= np.cos(np.linspace(0, np.pi / 2, len(c) - k)) ** 2
        hitx = hitx.copy(); hitx[:len(c)] += spec['click'] * c
    rg = ring(parts, spec['f0'], spec['len'], spec['tau'], spec['src'], bloom=spec.get('bloom', 0.025))
    sp = sparks(hitx, spec['spark_t60'])
    pw = power(seg, spec['power_tau'])
    # 身体：Still North 这几下撞击的能量都在 2kHz 以上，降八度也补不出中频 → 用真实闷金属撞击（CC0）的 150–1200Hz
    body = R.load('blacklodge-metal/dull_metal_collision_%s_44k_32bit_stereo.wav' % spec.get('body_src', '11'))
    body = R.unit(R.lp(R.hp(body[R.onset(body):], spec.get('body_lo', 150)), spec.get('body_hi', 1200)))
    sh = shimmer(hitx, spec['shimmer_T'], spec['src'] + 100, count=spec.get('shimmer_count', 140), smooth=spec.get('shimmer_smooth', False))
    dry = R.place(spec['len'], (hitx, 0, spec.get('hit', 1.0)), (body, 0, spec['body']), (rg, 0.002, spec['ring']),
                  (sh, 0, spec['shimmer']), (sp, 0, spec['spark']), (pw, 0, spec['power']))
    st = R.stereo_reverb(dry, spec['room_t60'], spec['room'], 9000, 0.012)[:, :n(spec['len'])]
    st = compress(st, spec.get('comp_thr', -14), spec.get('comp_ratio', 4.0), spec.get('comp_attack', 0.001))
    return np.vstack([R.fade_out(c, spec['len'] * 0.35) for c in st]), hit, parts, hit_scale   # 长淡出：尾音自然消失，不在结尾被切断


PARRY = {   # f0 = 嗡鸣主音目标（Hz），对照《只狼》1.75k / 2.34k / 3.55k / 4.03k；tau = 主音衰减常数（40dB ≈ 4.6×tau）
    'parry_a': dict(src=8, f0=2340, tau=0.30, ring=1.0, shimmer=0.7, shimmer_T=0.6, spark=0.7, spark_t60=0.7, body=0.6, power=0.3, power_tau=0.13, room=0.10, room_t60=0.6, len=2.0),
    # A2：用户选了 A，反馈"有不清晰的感觉"。拆层测出真实撞击在 0–100ms 被嗡鸣/火花/共振/身体层盖住，压缩又压了 7dB
    # → 真实撞击当主角（+起音提亮），身体层 -8dB 且收窄到 300–900Hz，嗡鸣 40ms 后才冒出，火花/共振减小缩短，压缩放过瞬态
    'parry_a2': dict(src=8, src_cut=0.14, f0=2340, tau=0.30, hit=1.6, click=0.6, ring=0.65, bloom=0.04, shimmer=0.45, shimmer_T=0.45,
                     spark=0.4, spark_t60=0.5, body=0.25, body_lo=300, body_hi=900, power=0.22, power_tau=0.13,
                     room=0.06, room_t60=0.5, comp_thr=-12, comp_ratio=3.0, comp_attack=0.006, len=2.0),
    # A2/A3 的源都截在 0.14s：原录音主撞击后 0.157s（源时间）有一下二次碰撞（只比主撞击低 20dB），是"不清晰"的主要来源
    # A3：折中版。A2 起音突出但嗡鸣/厚度掉出《只狼》区间；A3 保留 A 的厚度和嗡鸣，只清理发浑的来源：
    # 身体层收窄到 300–900Hz 并减小、金属共振换成均匀光泽（300 个模式、无个别突出）、火花混响缩短减嘶声、压缩 4ms 起音减抽吸
    'parry_a3': dict(src=8, src_cut=0.14, f0=2340, tau=0.30, hit=1.3, click=0.45, ring=0.95, bloom=0.03, shimmer=1.0, shimmer_T=0.5,
                     shimmer_count=300, shimmer_smooth=True, spark=0.5, spark_t60=0.55, body=0.35, body_lo=300, body_hi=900,
                     power=0.28, power_tau=0.13, room=0.05, room_t60=0.5, comp_thr=-16, comp_ratio=4.0, comp_attack=0.004, len=2.0),
    'parry_b': dict(src=2, f0=1750, tau=0.45, ring=0.7, shimmer=0.5, shimmer_T=0.7, spark=0.5, spark_t60=0.6, body=0.7, body_src='12', power=0.35, power_tau=0.16, room=0.12, room_t60=0.7, len=2.5),
    'parry_c': dict(src=0, f0=4030, tau=0.25, ring=1.1, shimmer=0.9, shimmer_T=0.6, spark=0.5, spark_t60=0.5, body=0.5, power=0.28, power_tau=0.12, room=0.10, room_t60=0.6, len=2.0),
    'parry_d': dict(src=12, f0=2340, tau=0.24, ring=1.1, shimmer=0.8, shimmer_T=0.45, spark=0.4, spark_t60=0.4, body=0.55, power=0.28, power_tau=0.10, room=0.08, room_t60=0.5, len=1.4),
}


def main():
    os.makedirs(OUT, exist_ok=True)
    report = {}
    for name, spec in PARRY.items():
        x, hit, parts, scale = build(spec)
        x = R.normalize(x, -10.0)          # 《只狼》的弹刀比格挡响得多；与命中同级
        R.write(x, os.path.join(OUT, 'cand3_%s.wav' % name))
        report['cand3_' + name] = {**R.stats(x), 'src': 'still-north/x/%s @ %.3fs' % (hit['file'], hit['t']),
                                   'hit_pitch_scale': round(scale, 2), 'blade_partials_hz': [round(f) for f, _ in parts]}
        print(name, report['cand3_' + name])
    json.dump(report, open(os.path.join(OUT, 'stats.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
