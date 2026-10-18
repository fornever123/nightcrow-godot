"""音效合成/处理小工具（只依赖 numpy；读写音频用 ffmpeg）。供 make_sfx_v3.py 使用。"""
import subprocess, numpy as np, os, shutil

SR = 44100
FFMPEG = shutil.which('ffmpeg') or '/usr/local/bin/ffmpeg'


def decode(path, sr=SR):
    raw = subprocess.run([FFMPEG, '-v', 'error', '-i', path, '-ac', '1', '-ar', str(sr), '-f', 'f32le', '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def encode_ogg(x, path, q=5):
    pcm = (np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()
    subprocess.run([FFMPEG, '-v', 'error', '-y', '-f', 's16le', '-ar', str(SR), '-ac', '1', '-i', '-',
                    '-c:a', 'libvorbis', '-q:a', str(q), path], input=pcm, check=True)


def write_wav(x, path):
    import wave
    w = wave.open(path, 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes()); w.close()


def n(sec):
    return int(round(sec * SR))


def t(x):
    return np.arange(len(x)) / SR


# ---------------------------------------------------------------- 滤波（RBJ biquad，因果，不会有预回声）
def _biquad(x, b0, b1, b2, a1, a2):
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def _coef(kind, f, q=0.707, gain_db=0.0):
    w = 2 * np.pi * min(f, SR * 0.49) / SR; cw, sw = np.cos(w), np.sin(w); al = sw / (2 * q)
    if kind == 'lp':
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == 'hp':
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == 'bp':
        b = [al, 0, -al]; a = [1 + al, -2 * cw, 1 - al]
    elif kind == 'peak':
        A = 10 ** (gain_db / 40)
        b = [1 + al * A, -2 * cw, 1 - al * A]; a = [1 + al / A, -2 * cw, 1 - al / A]
    else:
        raise ValueError(kind)
    return [v / a[0] for v in b] + [a[1] / a[0], a[2] / a[0]]


def lp(x, f, order=2):
    for _ in range(order // 2): x = _biquad(x, *_coef('lp', f))
    return x


def hp(x, f, order=2):
    for _ in range(order // 2): x = _biquad(x, *_coef('hp', f))
    return x


def bp(x, lo, hi, order=2):
    return lp(hp(x, lo, order), hi, order)


def peak(x, f, gain_db, q=1.0):
    return _biquad(x, *_coef('peak', f, q, gain_db))


def sweep_lp(x, f0, f1, curve=1.0):
    """一阶低通，截止频率随时间从 f0 滑到 f1（做“刷—”的扫频）。"""
    y = np.zeros_like(x); s = 0.0; L = len(x)
    for i in range(L):
        u = (i / max(L - 1, 1)) ** curve
        f = f0 * (f1 / f0) ** u
        k = 1 - np.exp(-2 * np.pi * f / SR)
        s += k * (x[i] - s); y[i] = s
    return y


# ---------------------------------------------------------------- 包络 / 发生器
def rng(seed):
    return np.random.default_rng(seed)


def noise(sec, seed=0):
    return rng(seed).standard_normal(n(sec))


def env(sec, attack=0.002, tau=0.05, hold=0.0, curve=1.0):
    tt = np.arange(n(sec)) / SR
    a = np.clip(tt / max(attack, 1e-5), 0, 1) ** curve
    d = np.where(tt < attack + hold, 1.0, np.exp(-(tt - attack - hold) / max(tau, 1e-5)))
    return a * d


def swell(sec, peak_at, rise_curve=2.0, tau=0.08):
    tt = np.arange(n(sec)) / SR
    up = np.clip(tt / peak_at, 0, 1) ** rise_curve
    down = np.where(tt < peak_at, 1.0, np.exp(-(tt - peak_at) / tau))
    return up * down


def sine_sweep(sec, f0, f1, curve=2.0):
    tt = np.arange(n(sec)) / SR
    u = np.clip(tt / sec, 0, 1)
    f = f1 + (f0 - f1) * (1 - u) ** curve
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def metal(sec, f0, ratios, amps, taus, detune=1.2, seed=0):
    """非谐和分音（金属块/刀身）：每个分音一对略微失谐的正弦 → 有拍频的“铮——”。"""
    r = rng(seed); tt = np.arange(n(sec)) / SR; y = np.zeros(len(tt))
    for k, (ra, am, ta) in enumerate(zip(ratios, amps, taus)):
        f = f0 * ra * (1 + r.uniform(-0.004, 0.004))
        ph = r.uniform(0, 2 * np.pi)
        y += am * np.exp(-tt / ta) * 0.5 * (np.sin(2 * np.pi * f * tt + ph) + np.sin(2 * np.pi * (f + detune * (k + 1)) * tt + ph * 0.7))
    return y


def bell(sec, f, tau=0.4, vib_hz=0.0, vib_depth=0.0, partials=((1, 1.0), (2.76, 0.35), (5.4, 0.12))):
    tt = np.arange(n(sec)) / SR; y = np.zeros(len(tt))
    vib = 1 + vib_depth * np.sin(2 * np.pi * vib_hz * tt)
    for ra, am in partials:
        y += am * np.exp(-tt / (tau / ra ** 0.5)) * np.sin(2 * np.pi * np.cumsum(f * ra * vib) / SR)
    return y


def grains(sec, rate, tau_density, seed=0, lo=2500, hi=7000, grain_tau=0.0025):
    """碎石/碎屑：随机小脉冲，密度按 exp(-t/tau_density) 衰减。"""
    r = rng(seed); L = n(sec); y = np.zeros(L)
    tt = np.arange(L) / SR
    p = rate / SR * np.exp(-tt / tau_density)
    hits = np.nonzero(r.random(L) < p)[0]
    g = np.exp(-np.arange(n(grain_tau * 6)) / (grain_tau * SR)) * r.standard_normal(n(grain_tau * 6))
    for h in hits:
        seg = g * r.uniform(0.3, 1.0); e = min(L, h + len(seg)); y[h:e] += seg[:e - h]
    return bp(y, lo, hi)


def flutter(sec, rate=22.0, depth=0.5, seed=0):
    """布料抖动：随机调幅。"""
    r = rng(seed); L = n(sec)
    k = max(2, int(sec * rate) + 2)
    pts = r.uniform(1 - depth, 1, k)
    return np.interp(np.linspace(0, k - 1, L), np.arange(k), pts)


# ---------------------------------------------------------------- 组合
def mix(length_sec, *layers):
    """layers: (signal, offset_sec, gain)"""
    L = n(length_sec); y = np.zeros(L)
    for sig, off, g in layers:
        o = n(off); e = min(L, o + len(sig))
        if e > o:
            seg = sig[:e - o].copy(); k = max(1, int(len(seg) * 0.25))
            seg[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2   # 每层尾巴都淡出，不会“咔”地断掉
            y[o:e] += g * seg
    return y


def resample(x, ratio):
    """ratio>1 → 音调升高、变短。"""
    if abs(ratio - 1) < 1e-6: return x.copy()
    if ratio > 1: x = lp(x, SR * 0.45 / ratio, 4)
    idx = np.arange(0, len(x) - 1, ratio)
    return np.interp(idx, np.arange(len(x)), x)


def fade(x, fin=0.004, fout=0.03):
    y = x.copy(); a, b = n(fin), n(fout)
    if a: y[:a] *= np.linspace(0, 1, a) ** 2
    if b: y[-b:] *= np.cos(np.linspace(0, np.pi / 2, b)) ** 2
    return y


def trim_tail(x, floor_db=-60):
    a = np.abs(x); thr = a.max() * 10 ** (floor_db / 20)
    idx = np.nonzero(a > thr)[0]
    end = min(len(x), (idx[-1] if len(idx) else len(x)) + n(0.01))
    return fade(x[:end], 0.0, min(0.03, end / SR * 0.3))


def reverb(x, t60=0.6, mix_=0.15, seed=7, damp=3500, pre=0.012):
    """短混响：衰减噪声当冲激响应（FFT 卷积），再低通模拟空气吸收。"""
    L = n(t60 * 1.2); tt = np.arange(L) / SR
    ir = rng(seed).standard_normal(L) * np.exp(-6.9 * tt / t60)
    ir = lp(ir, damp); ir /= np.sqrt((ir ** 2).sum()) + 1e-12
    ir = np.concatenate([np.zeros(n(pre)), ir])
    N = len(x) + len(ir)
    wet = np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(ir, N), N)
    dry = np.concatenate([x, np.zeros(len(ir))])
    return dry + mix_ * wet * (np.abs(x).max() / (np.abs(wet).max() + 1e-12))


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def rms_max_db(x, win=0.05):
    w = n(win); c = np.convolve(x ** 2, np.ones(w) / w, 'same')
    return 10 * np.log10(c.max() + 1e-12)


def peak_db(x):
    return 20 * np.log10(np.abs(x).max() + 1e-12)


def limit(x, ceil_db=-1.0, release=0.04, look=0.0015):
    """前瞻峰值限幅：增益平滑下降/恢复，不改变低于上限的部分。"""
    ceil = 10 ** (ceil_db / 20); a = np.abs(x)
    need = np.minimum(1.0, ceil / np.maximum(a, 1e-12))
    w = max(1, n(look))
    # 前瞻：取未来 w 个样本里最小的增益（先降下来再碰到峰）
    pad = np.concatenate([need, np.ones(w)])
    g = np.min(np.lib.stride_tricks.sliding_window_view(pad, w + 1), axis=1)[:len(x)]
    out = np.empty_like(g); r = np.exp(-1.0 / (release * SR)); cur = 1.0
    for i in range(len(g)):
        cur = g[i] if g[i] < cur else g[i] + (cur - g[i]) * r
        out[i] = cur
    return x * out


def normalize(x, rms_target_db, peak_ceiling_db=-1.0, max_limit_db=6.0):
    """响度对到目标；峰值超了先用限幅器压最多 max_limit_db，再多就整体降增益（保住打击的“尖”）。"""
    g_db = rms_target_db - rms_max_db(x)
    over = peak_db(x) + g_db - peak_ceiling_db
    if over > max_limit_db:
        g_db -= over - max_limit_db
    y = x * 10 ** (g_db / 20)
    if peak_db(y) > peak_ceiling_db:
        y = limit(y, peak_ceiling_db)
    return y


def peak_time(x, win=0.01):
    w = n(win); c = np.convolve(x ** 2, np.ones(w) / w, 'same')
    return int(np.argmax(c)) / SR
