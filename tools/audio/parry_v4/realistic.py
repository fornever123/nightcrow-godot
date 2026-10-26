"""第二批候选：以真实录音为主体（不再用纯合成的"游戏味"），只写到试听目录，不接入游戏。

用法：python -I realistic.py   → processed2/*.wav（48kHz）+ processed2/stats.json

素材（downloads/ 下，均来自 OpenGameArt）：
  still-north   Still North Media 兵器互撞（CC0），192kHz 录音
  fleshy-fight  will_leamon "fleshy fight sounds"（OGA-BY 3.0，用了要署名 "Additional Sound FX by Will Leamon"）
  qubodup       qubodup Impact（CC0）

弹刀 = 真实刀刃撞击（起音）+ 从这一下余振里提取刀身真实共振频率做的振刀嗡鸣（低频模式为主、带颤、含降八度）+
       同一下撞击降八度慢放（更沉）+ 低频冲击 + 0.4–0.6s 的小空间回响（只给一点空气感）。
击中 = 剑砍入肉的真实录音（切掉前面的挥风，从命中那一刻开始）+ 拳击/湿肉的身体层，几乎不加处理。
"""
import os, sys, json, shutil, subprocess, wave
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
DL = os.path.join(HERE, 'downloads')
OUT = os.path.join(HERE, 'processed2')
SR = 48000
FFMPEG = shutil.which('ffmpeg')
CURRENT_PARRY = os.path.join(HERE, 'current', 'parry.wav')


# ---------------------------------------------------------------- 基础
def load(rel, sr=SR):
    raw = subprocess.run([FFMPEG, '-v', 'error', '-i', os.path.join(DL, rel), '-ac', '1', '-ar', str(sr),
                          '-f', 'f32le', '-'], check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def n(sec):
    return int(round(sec * SR))


def unit(x):
    return x / (np.abs(x).max() + 1e-12)


def biquad(x, kind, f, q=0.707, sr=SR):
    w = 2 * np.pi * min(f, sr * 0.49) / sr; cw, sw = np.cos(w), np.sin(w); al = sw / (2 * q)
    if kind == 'lp':
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
    else:
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
    a = [1 + al, -2 * cw, 1 - al]
    b0, b1, b2, a1, a2 = b[0] / a[0], b[1] / a[0], b[2] / a[0], a[1] / a[0], a[2] / a[0]
    y = np.empty_like(x); x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        xi = x[i]; yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi; y[i] = yi
    return y


def hp(x, f, sr=SR):
    return biquad(biquad(x, 'hp', f, sr=sr), 'hp', f, sr=sr)


def lp(x, f, sr=SR):
    return biquad(biquad(x, 'lp', f, sr=sr), 'lp', f, sr=sr)


def env_db(x, win, sr=SR):
    w = max(1, int(win * sr)); k = len(x) // w
    return 20 * np.log10(np.sqrt((x[:k * w].reshape(k, w) ** 2).mean(axis=1)) + 1e-12)


def onset(x, sr=SR, within=None):
    """主撞击的起点：包络最大处（只在前 within 秒里找）往回找，直到比峰低 12dB（最多回退 10ms，不带进前面的挥风），再留 1ms。"""
    e = env_db(x, 0.0025, sr)
    p = int(np.argmax(e if within is None else e[:int(within / 0.0025)])); i = p
    while i > 0 and e[i] > e[p] - 12 and p - i < 4:
        i -= 1
    return max(0, int(i * 0.0025 * sr) - int(0.001 * sr))


def gate(x, floor_db=-50, sr=SR):
    """底噪门：低于峰值 floor_db 的部分平滑压掉（去掉原录音的房间底噪）。"""
    e = 10 ** (env_db(x, 0.01, sr) / 20); thr = e.max() * 10 ** (floor_db / 20)
    g = np.clip((e / thr - 1) / 2, 0, 1) ** 2
    g = np.repeat(g, int(0.01 * sr))[:len(x)]
    g = np.concatenate([g, np.full(len(x) - len(g), g[-1] if len(g) else 1)])
    k = int(0.02 * sr); g = np.convolve(g, np.ones(k) / k, 'same')
    return x * g


def place(length, *layers):
    """layers: (信号, 起始秒, 增益)。"""
    y = np.zeros(n(length))
    for sig, off, g in layers:
        o = n(off); e = min(len(y), o + len(sig))
        if e > o:
            y[o:e] += g * sig[:e - o]
    return y


def fade_out(x, sec):
    k = min(len(x), n(sec)); y = x.copy()
    y[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return y


def reverb_ir(t60, seed, damp=5000, pre=0.02):
    r = np.random.default_rng(seed); L = n(t60 * 1.3); tt = np.arange(L) / SR
    ir = r.standard_normal(L) * np.exp(-6.9 * tt / t60)
    ir = lp(ir, damp); ir /= np.sqrt((ir ** 2).sum()) + 1e-12
    return np.concatenate([np.zeros(n(pre)), ir])


def conv(x, h):
    N = len(x) + len(h) - 1
    return np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(h, N), N)


def stereo_reverb(x, t60, wet, damp=5000, pre=0.02):
    """左右用不同的冲激响应 → 有空间宽度的回响。返回 (2, N)。"""
    outs = []
    send = hp(x, 180)   # 低频不进回响：低频冲击保持干、紧，不拖成隆隆声
    for seed in (11, 23):
        w = conv(send, reverb_ir(t60, seed, damp, pre))
        dry = np.concatenate([x, np.zeros(len(w) - len(x))])
        outs.append(dry + wet * w * (np.abs(x).max() / (np.abs(w).max() + 1e-12)))
    return np.vstack(outs)


# ---------------------------------------------------------------- 弹刀
def blade_partials(seg, sr, count, lo, hi):
    """取撞击后 60–400ms 的频谱，在 [lo, hi] 里挑最强的若干个共振峰（刀身真实的振动频率）。"""
    a, b = int(0.06 * sr), min(len(seg), int(0.4 * sr))
    w = seg[a:b] * np.hanning(b - a)
    spec = np.abs(np.fft.rfft(w, 1 << 16)); f = np.fft.rfftfreq(1 << 16, 1 / sr)
    idx = np.nonzero((f > lo) & (f < hi))[0]
    s = spec.copy(); peaks = []
    for _ in range(count):
        i = idx[np.argmax(s[idx])]
        peaks.append((f[i], s[i]))
        s[max(0, i - 60):i + 60] = 0          # 相邻 ±44Hz 内不重复挑
    m = max(p[1] for p in peaks)
    return [(fr, amp / m) for fr, amp in peaks]


def hum(low, high, sec, tau_low, seed):
    """振刀嗡鸣：以刀身低频振动模式（250–1500Hz）为主体；每个低分音配一个较弱的副本（0.35–0.5），
    两者相差的拍频从 5–8Hz 慢慢降到 2–4Hz → "嗡嗡"的颤由快变慢、不会颤到完全抵消（太规则会像电子颤音）。
    叠一点降八度加厚；高频分音只做短的"铮"。起音 4ms，不盖住真实撞击。"""
    r = np.random.default_rng(seed); t = np.arange(n(sec)) / SR; y = np.zeros(len(t))
    for fr, amp in low:
        tau = tau_low * (500 / fr) ** 0.25 * r.uniform(0.85, 1.15)
        for mul, g in ((1.0, 1.0), (0.5, 0.2)):
            f0 = fr * mul
            b0, b1 = r.uniform(5.0, 8.0), r.uniform(2.0, 4.0)
            beat = b1 + (b0 - b1) * np.exp(-t / 0.5)                  # 拍频随时间变慢
            ph = r.uniform(0, 2 * np.pi)
            partner = r.uniform(0.35, 0.5)
            y += g * amp * np.exp(-t / tau) * (np.sin(2 * np.pi * f0 * t + ph)
                                               + partner * np.sin(2 * np.pi * np.cumsum(f0 + beat) / SR + ph * 1.3))
    hi = np.zeros(len(t))
    for fr, amp in high:
        tau = 0.35 * (2000 / fr) ** 0.4
        ph = r.uniform(0, 2 * np.pi)
        hi += amp * np.exp(-t / tau) * (np.sin(2 * np.pi * fr * t + ph) + 0.4 * np.sin(2 * np.pi * fr * 1.002 * t + ph))
    y = unit(y) + 0.35 * unit(hi)
    return unit(y) * np.clip(t / 0.004, 0, 1)


def parry(spec):
    hit = json.load(open(os.path.join(HERE, 'scan', 'still_north_hits.json'), encoding='utf-8'))['top'][spec['src']]
    raw = load(os.path.join('still-north', 'x', hit['file']), 192000)
    # 只取这一下：截在原录音下一次撞击之前（hit['len'] 由 slice_src.py 按下一个起音算出），尾部淡出
    a = max(0, int((hit['t'] - 0.01) * 192000)); seg = raw[a:a + int((hit['len'] - 0.03) * 192000)]
    seg = gate(hp(seg, 150, 192000), -48, 192000)
    seg = seg[onset(seg, 192000, 0.06):]
    k = int(0.12 * 192000); seg[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    low = blade_partials(seg, 192000, 4, 250, 1500)
    high = blade_partials(seg, 192000, 8, 1500, 7000)
    # 原速（192k→48k）与降调慢放：把 192k 样本当成 192k*ratio 播放，再重采样到 48k
    def at_speed(ratio):
        idx = np.arange(0, len(seg) - 1, 4 * ratio)
        return np.interp(idx, np.arange(len(seg)), seg)
    real = unit(at_speed(spec['pitch']))
    slow = unit(hp(at_speed(spec['pitch'] * 0.5), 120))
    p = spec['pitch']
    hm = hum([(f * p, a_) for f, a_ in low], [(f * p, a_) for f, a_ in high], spec['len'], spec['tau'], spec['src'])
    body = unit(lp(load('fleshy-fight/x/punch_alt-2a.wav'), 220)); body = body[onset(body):]
    body = body * np.exp(-np.arange(len(body)) / SR / 0.12)   # 只留冲击本身，素材后面的底噪尾巴自然衰减掉
    dry = place(spec['len'], (real, 0, 1.0), (slow, 0.002, spec['slow']), (hm, 0.003, spec['hum']), (body, 0, spec['body']))
    st = stereo_reverb(dry, spec['t60'], spec['wet'], spec.get('damp', 5500))
    st = st[:, :n(spec['len'])]
    return np.vstack([fade_out(c, spec['len'] * 0.25) for c in st]), hit


PARRY = {   # src = scan/still_north_hits.json 排名；pitch<1 = 整体降调（更沉）
    # 第三版：用户反馈"回音太大太长、嗡鸣不够" → 回响缩到 0.4–0.6s 小空间、音量压低；
    # 尾音主体改成刀身低频嗡鸣，自然指数衰减（约 1–1.5s 衰减 30dB）
    'parry_a': dict(src=8, pitch=0.85, hum=0.8, slow=0.35, body=0.35, tau=0.75, t60=0.5, wet=0.12, len=1.8),
    'parry_b': dict(src=2, pitch=0.75, hum=0.9, slow=0.45, body=0.45, tau=0.9, t60=0.6, wet=0.12, len=2.0),
    'parry_c': dict(src=0, pitch=0.9, hum=0.75, slow=0.3, body=0.3, tau=0.65, t60=0.5, wet=0.1, len=1.6, damp=7000),
    'parry_d': dict(src=12, pitch=0.85, hum=0.7, slow=0.3, body=0.4, tau=0.4, t60=0.4, wet=0.08, len=1.1),
}


# ---------------------------------------------------------------- 击中
def clip(rel, gain_hp=60):
    x = hp(load(rel), gain_hp)
    return unit(x[onset(x):])


def hit(layers, cap, room=0.0):
    y = place(cap, *[(clip(rel), off, g) for rel, off, g in layers])
    if room:
        y = stereo_reverb(y, 0.35, room, 6000, 0.008)[:, :n(cap)]
        return np.vstack([fade_out(c, cap * 0.3) for c in y])
    return fade_out(y, cap * 0.3)


FF = 'fleshy-fight/x/'
QB = 'qubodup-impact/x/qubodupImpact/'
HITS = {
    'hit_light_a': (0.25, [(FF + 'sword-1a.wav', 0, 1.0)], 0),
    'hit_light_b': (0.25, [(FF + 'sword-1b.wav', 0, 1.0)], 0),
    'hit_light_c': (0.25, [(FF + 'sword-1a.wav', 0, 1.0), (QB + 'qubodupImpactMeat02.flac', 0, 0.35)], 0),
    'hit_heavy_a': (0.40, [(FF + 'sword-1b.wav', 0, 1.0), (FF + 'punch_alt-2a.wav', 0, 0.6), (QB + 'qubodupImpactMeat02.flac', 0, 0.3)], 0.08),
    'hit_heavy_b': (0.40, [(FF + 'sword-arm-2b.wav', 0, 1.0), (FF + 'punch_1a.wav', 0, 0.5)], 0.08),
    'hit_heavy_c': (0.40, [(FF + 'sword-1a.wav', 0, 1.0), (FF + 'punch_1a.wav', 0, 0.6), (QB + 'qubodupImpactMeat01.flac', 0.004, 0.35)], 0.08),
    'hit_finisher_a': (0.60, [(FF + 'sword-1b.wav', 0, 1.0), (FF + 'hammer-1a.wav', 0, 0.6), (FF + 'punch_alt-2a.wav', 0, 0.6), (QB + 'qubodupImpactMeat02.flac', 0, 0.35)], 0.14),
    'hit_finisher_b': (0.60, [(FF + 'sword-arm-2a.wav', 0, 1.0), (FF + 'punch_alt-2b.wav', 0, 0.7), (QB + 'qubodupImpactMeat02.flac', 0, 0.3)], 0.14),
    'hit_finisher_c': (0.60, [(FF + 'sword-1a.wav', 0, 0.9), (FF + 'sword-1b.wav', 0.03, 0.8), (FF + 'punch_alt-2a.wav', 0.03, 0.7), (QB + 'qubodupImpactMeat01.flac', 0.03, 0.3)], 0.14),
}


# ---------------------------------------------------------------- 输出
def rms50(x):
    m = x.mean(axis=0) if x.ndim == 2 else x
    w = n(0.05); c = np.convolve(m ** 2, np.ones(w) / w, 'same')
    return 10 * np.log10(c.max() + 1e-12)


def normalize(x, target, ceil_db=-1.0):
    y = x * 10 ** ((target - rms50(x)) / 20)
    pk = np.abs(y).max(); ceil = 10 ** (ceil_db / 20)
    if pk > ceil:   # 软拐点压峰：只动最尖的那几毫秒
        y = np.sign(y) * np.where(np.abs(y) > ceil * 0.7, ceil * 0.7 + (ceil * 0.3) * np.tanh((np.abs(y) - ceil * 0.7) / (ceil * 0.3)), np.abs(y))
    return y


def write(x, path):
    x = np.atleast_2d(x)
    w = wave.open(path, 'wb'); w.setnchannels(x.shape[0]); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.clip(x.T, -1, 1) * 32767).astype('<i2').tobytes()); w.close()


def stats(x):
    m = x.mean(axis=0) if x.ndim == 2 else x
    e = env_db(m, 0.01); p = int(np.argmax(e))
    t30 = np.nonzero(e[p:] < e[p] - 30)[0]
    return {'dur_ms': round(len(m) / SR * 1000), 'peak_ms': p * 10, 'rms50_db': round(rms50(x), 1),
            'peak_db': round(20 * np.log10(np.abs(x).max() + 1e-12), 1),
            'ring30_ms': int(t30[0] * 10) if len(t30) else round(len(m) / SR * 1000),
            'channels': 2 if x.ndim == 2 else 1}


def main():
    os.makedirs(OUT, exist_ok=True)
    cur = load(os.path.relpath(CURRENT_PARRY, DL)); parry_target = rms50(cur)
    report = {}
    for name, (cap, layers, room) in HITS.items():
        x = normalize(hit(layers, cap, room), -10.0)
        write(x, os.path.join(OUT, 'cand2_%s.wav' % name)); report['cand2_' + name] = {**stats(x), 'src': [l[0] for l in layers]}
    for name, spec in PARRY.items():
        x, src = parry(spec)
        x = normalize(x, parry_target)
        write(x, os.path.join(OUT, 'cand2_%s.wav' % name))
        report['cand2_' + name] = {**stats(x), 'src': ['still-north/x/%s @ %.3fs' % (src['file'], src['t'])]}
    json.dump(report, open(os.path.join(OUT, 'stats.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    for k, v in report.items():
        print(k, {kk: vv for kk, vv in v.items() if kk != 'src'})


if __name__ == '__main__':
    main()
