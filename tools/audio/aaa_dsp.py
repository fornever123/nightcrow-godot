"""《断晓》商业 3A 级混合声音设计核心 DSP 引擎（48kHz Stereo Mastering）。

结合 192kHz/24-bit 高清物理母带采样（Foley）与物理建模/非线性信号处理（DSP）：
  - 抗混叠变速重采样（保留 192kHz 超声波下移后的细腻空气高频）
  - 瞬态塑形器（Transient Shaper：双包络差分精确锐化前 5-15ms 刀锋咬合）
  - 多段软饱和激励（Tube/Tape Saturation：消除数字干瘪感，增加偶/奇次谐波密度）
  - 相位锁定紧致超低频（Phase-Locked Sub-Drop：只震胸腔不糊中频）
  - 色散刚体/白瓷/冷钢模态谐振器库（Dispersive Modal Resonator Bank）
  - 立体声早期反射与微声像宽度（Stereo Early Reflections & Micro-Haas）
  - 4:1 快速联动总线压缩与 Lookahead 峰值限幅母带归一化
"""
from __future__ import annotations

from pathlib import Path
import numpy as np
from scipy.ndimage import minimum_filter1d
from scipy.signal import butter, fftconvolve, resample_poly, sosfilt, sosfiltfilt
import soundfile as sf

SR = 48000

# 本机已验证的 CC0 物理录音根目录（只读，绝不修改原文件）
RAW_ROOT_A = Path(r"E:\00game\work\sfx-audition-hit-parry-20261025\downloads")
RAW_ROOT_B = Path(r"E:\00game\work\nightcrow-音效试听-20261029\downloads")
RAW_ROOT_C = Path(r"E:\00game\work\sfx-ult-b")

_FILE_CACHE: dict[str, tuple[np.ndarray, int]] = {}


def resolve_raw(rel_path: str) -> Path:
    for base in (RAW_ROOT_A, RAW_ROOT_B, RAW_ROOT_C):
        p = base / rel_path
        if p.exists():
            return p
    p = Path(rel_path)
    if p.exists():
        return p
    raise FileNotFoundError(f"找不到原始音频素材: {rel_path}")


def load_raw(rel_path: str, mono: bool = True) -> tuple[np.ndarray, int]:
    key = f"{rel_path}|{mono}"
    if key not in _FILE_CACHE:
        p = resolve_raw(rel_path)
        data, sr = sf.read(str(p), dtype="float64", always_2d=True)
        x = data.mean(axis=1) if mono else data.T.copy()
        _FILE_CACHE[key] = (x, int(sr))
    arr, sr = _FILE_CACHE[key]
    return arr.copy(), sr


def slice_192k(
    rel_path: str,
    t0: float,
    t1: float,
    speed: float = 1.0,
    hp_hz: float = 45.0,
    trim_onset: bool = True,
    onset_thr_db: float = -34.0,
) -> np.ndarray:
    """从 192kHz（或任意采样率）母带切出片段并变速转到 48kHz。
    speed < 1.0 时将 192kHz 中的超声波真实物理湍流下移至可听高频，厚重而不闷！
    """
    raw, sr = load_raw(rel_path, mono=True)
    i0 = max(0, int(round(t0 * sr)))
    i1 = min(len(raw), int(round(t1 * sr)))
    seg = raw[i0:i1].copy()
    if len(seg) < 64:
        return np.zeros(int(0.05 * SR))
    seg -= np.mean(seg)
    # 先在原采样率去超低频直流漂移
    if hp_hz > 0 and hp_hz < sr * 0.45:
        seg = sosfiltfilt(butter(2, hp_hz, "high", fs=sr, output="sos"), seg)
    # 抗混叠重采样到 48kHz：目标长度 = len(seg) * (SR / (sr * speed))
    ratio = SR / (sr * max(speed, 0.12))
    # 若降速后最高有效频率高于 22.5kHz，先低通防混叠
    nyq_src = 0.46 * sr * min(ratio, 1.0)
    if nyq_src < 0.48 * sr:
        seg = sosfiltfilt(butter(4, nyq_src, "low", fs=sr, output="sos"), seg)
    target_len = max(32, int(round(len(seg) * ratio)))
    idx = np.linspace(0, len(seg) - 1, target_len)
    y = np.interp(idx, np.arange(len(seg)), seg)
    if trim_onset:
        y = strip_leading_silence(y, thr_db=onset_thr_db, pre_ms=1.8)
    return y


def strip_leading_silence(x: np.ndarray, thr_db: float = -36.0, pre_ms: float = 1.5) -> np.ndarray:
    a = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=0)
    pk = float(a.max())
    if pk < 1e-9:
        return x
    thr = pk * (10.0 ** (thr_db / 20.0))
    hits = np.flatnonzero(a >= thr)
    if len(hits) == 0:
        return x
    start = max(0, int(hits[0]) - int(round(pre_ms * 0.001 * SR)))
    return x[start:].copy() if x.ndim == 1 else x[:, start:].copy()


def align_peak_to(x: np.ndarray, target_peak_s: float = 0.050, win_ms: float = 12.0) -> np.ndarray:
    """将刀风类音效的能量包络最高峰对齐到 target_peak_s（与游戏提前 3 帧 swing_cue 严丝合缝）。"""
    mono = x if x.ndim == 1 else x.mean(axis=0)
    w = max(8, int(round(win_ms * 0.001 * SR)))
    if len(mono) <= w:
        return x
    env = np.convolve(mono ** 2, np.ones(w) / w, mode="same")
    pk_idx = int(np.argmax(env))
    want_idx = int(round(target_peak_s * SR))
    if pk_idx > want_idx:
        cut = pk_idx - want_idx
        return x[cut:].copy() if x.ndim == 1 else x[:, cut:].copy()
    elif pk_idx < want_idx:
        pad = want_idx - pk_idx
        if x.ndim == 1:
            return np.pad(x, (pad, 0))
        return np.pad(x, ((0, 0), (pad, 0)))
    return x


def ensure_stereo(x: np.ndarray) -> np.ndarray:
    if x.ndim == 1:
        return np.vstack([x, x])
    if x.shape[0] == 2:
        return x.copy()
    return x.T.copy()


def fade_io(x: np.ndarray, in_s: float = 0.0015, out_s: float = 0.045) -> np.ndarray:
    y = x.copy()
    L = y.shape[-1]
    ni = min(L // 2, max(1, int(round(in_s * SR))))
    no = min(L - ni, max(1, int(round(out_s * SR))))
    if ni > 1:
        fi = np.sin(np.linspace(0, np.pi / 2, ni)) ** 2
        if y.ndim == 1:
            y[:ni] *= fi
        else:
            y[:, :ni] *= fi[None, :]
    if no > 1:
        fo = np.cos(np.linspace(0, np.pi / 2, no)) ** 2
        if y.ndim == 1:
            y[-no:] *= fo
        else:
            y[:, -no:] *= fo[None, :]
    return y


def crop_or_pad(x: np.ndarray, dur_s: float, fade_out_s: float = 0.04) -> np.ndarray:
    n_target = max(32, int(round(dur_s * SR)))
    if x.ndim == 1:
        if len(x) >= n_target:
            y = x[:n_target].copy()
        else:
            y = np.pad(x, (0, n_target - len(x)))
    else:
        if x.shape[1] >= n_target:
            y = x[:, :n_target].copy()
        else:
            y = np.pad(x, ((0, 0), (0, n_target - x.shape[1])))
    return fade_io(y, in_s=0.0012, out_s=min(fade_out_s, dur_s * 0.42))


# ------------------------------ 滤波器与塑形 ------------------------------

def hp(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    hz = float(np.clip(hz, 18.0, SR * 0.46))
    sos = butter(order, hz, "high", fs=SR, output="sos")
    return sosfiltfilt(sos, x, axis=-1)


def lp(x: np.ndarray, hz: float, order: int = 2) -> np.ndarray:
    hz = float(np.clip(hz, 40.0, SR * 0.47))
    sos = butter(order, hz, "low", fs=SR, output="sos")
    return sosfiltfilt(sos, x, axis=-1)


def bp(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    lo = float(np.clip(lo, 20.0, SR * 0.44))
    hi = float(np.clip(hi, lo * 1.18, SR * 0.475))
    sos = butter(order, [lo, hi], "band", fs=SR, output="sos")
    return sosfiltfilt(sos, x, axis=-1)


def tilt_eq(x: np.ndarray, low_shelf_db: float = 0.0, presence_db: float = 0.0, air_db: float = 0.0) -> np.ndarray:
    """三段平滑音乐性均衡：低频重量 (<180Hz) + 中高频咬合 (2.2k-5.5kHz) + 空气感 (>7.5kHz)。"""
    y = x.copy()
    if abs(low_shelf_db) > 0.1:
        lo_band = lp(x, 185.0, order=2)
        y = y + (10.0 ** (low_shelf_db / 20.0) - 1.0) * lo_band
    if abs(presence_db) > 0.1:
        mid_band = bp(x, 2100.0, 5800.0, order=2)
        y = y + (10.0 ** (presence_db / 20.0) - 1.0) * mid_band
    if abs(air_db) > 0.1:
        hi_band = hp(x, 7500.0, order=2)
        y = y + (10.0 ** (air_db / 20.0) - 1.0) * hi_band
    return y


def transient_shaper(x: np.ndarray, attack_db: float = 5.0, sustain_db: float = 0.0) -> np.ndarray:
    """SPL 风格双包络差分瞬态塑形器：突出前几毫秒真实物理接触头，收紧多余混浊尾音。"""
    mono = np.abs(x) if x.ndim == 1 else np.abs(x).max(axis=0)
    # 快包络 (0.8ms) vs 慢包络 (22ms)
    def follow(sig: np.ndarray, att_s: float, rel_s: float) -> np.ndarray:
        ca = np.exp(-1.0 / max(1.0, att_s * SR))
        cr = np.exp(-1.0 / max(1.0, rel_s * SR))
        out = np.empty_like(sig)
        e = 0.0
        for i, v in enumerate(sig):
            e = ca * e + (1.0 - ca) * v if v > e else cr * e + (1.0 - cr) * v
            out[i] = e
        return out

    ef = follow(mono, 0.0006, 0.018)
    es = follow(mono, 0.018, 0.095)
    diff = (ef - es) / (ef + 1e-7)
    att_mask = np.clip(diff, 0.0, 1.0)
    sus_mask = np.clip(-diff, 0.0, 1.0)
    gain_db = att_mask * attack_db + sus_mask * sustain_db
    gain = 10.0 ** (gain_db / 20.0)
    return x * gain if x.ndim == 1 else x * gain[None, :]


def saturate(x: np.ndarray, drive: float = 1.6, asym: float = 0.08) -> np.ndarray:
    """带轻微偶次谐波不对称性的电子管/磁带软饱和激励。"""
    pk = float(np.abs(x).max())
    if pk < 1e-9:
        return x
    norm = x / pk
    y = np.tanh(drive * (norm + asym * (norm ** 2))) - np.tanh(drive * asym * 0.0)
    y -= np.mean(y, axis=-1, keepdims=True)
    y_pk = float(np.abs(y).max()) + 1e-12
    return (y / y_pk) * pk


# ------------------------------ 物理建模与合成层 ------------------------------

def sub_drop(
    dur_s: float,
    f_start: float = 88.0,
    f_end: float = 38.0,
    tau_pitch: float = 0.045,
    tau_amp: float = 0.11,
    drive: float = 1.75,
    punch_ms: float = 2.2,
) -> np.ndarray:
    """相位零点锁定的紧致超低频冲击（带温润偶次/奇次谐波，耳机和小音箱同样拳拳到肉）。"""
    n = max(16, int(round(dur_s * SR)))
    t = np.arange(n) / SR
    freq = f_end + (f_start - f_end) * np.exp(-t / tau_pitch)
    phase = 2.0 * np.pi * np.cumsum(freq) / SR
    raw = np.sin(phase) + 0.28 * np.sin(2.0 * phase)
    sat = np.tanh(drive * raw) / np.tanh(drive)
    att = np.clip(t / max(0.0005, punch_ms * 0.001), 0.0, 1.0)
    env = att * np.exp(-t / tau_amp)
    y = lp(sat * env, 210.0, order=3)
    return fade_io(y, 0.0008, min(0.04, dur_s * 0.35))


def modal_bank(
    excite: np.ndarray,
    dur_s: float,
    freqs: list[float] | np.ndarray,
    amps: list[float] | np.ndarray,
    taus: list[float] | np.ndarray,
    detune_cents: float = 3.2,
    seed: int = 1,
) -> np.ndarray:
    """立体声色散模态谐振器库：先对激励信号做高频预白化，避免卷积吃掉 >4kHz 冷钢泛音。"""
    rng = np.random.default_rng(seed)
    n_ir = max(64, int(round(dur_s * SR)))
    t = np.arange(n_ir) / SR
    ir_l = np.zeros(n_ir)
    ir_r = np.zeros(n_ir)
    for f, a, tau in zip(freqs, amps, taus):
        if f >= SR * 0.46 or f < 30.0:
            continue
        ratio_l = 2.0 ** (rng.uniform(-detune_cents, detune_cents) / 1200.0)
        ratio_r = 2.0 ** (rng.uniform(-detune_cents, detune_cents) / 1200.0)
        ph_l = rng.uniform(0, 2 * np.pi)
        ph_r = rng.uniform(0, 2 * np.pi)
        env = a * np.exp(-t / tau)
        ir_l += env * (np.sin(2 * np.pi * f * ratio_l * t + ph_l) + 0.45 * np.sin(2 * np.pi * f * ratio_l * 1.0008 * t + ph_l + 0.9))
        ir_r += env * (np.sin(2 * np.pi * f * ratio_r * t + ph_r) + 0.45 * np.sin(2 * np.pi * f * ratio_r * 1.0010 * t + ph_r + 1.7))
    mono_ex = excite if excite.ndim == 1 else excite.mean(axis=0)
    # 预加重一阶差分，补偿真实采样高频滚降，让高次金属模态通透发亮
    ex_white = np.diff(mono_ex, prepend=mono_ex[0]) if len(mono_ex) > 4 else mono_ex
    yl = fftconvolve(ex_white, ir_l)[:n_ir]
    yr = fftconvolve(ex_white, ir_r)[:n_ir]
    st = np.vstack([yl, yr])
    pk = float(np.abs(st).max()) + 1e-12
    return st / pk


def blade_partials_192k(
    rel_path: str,
    t0: float,
    t1: float,
    count: int = 6,
    lo: float = 1700.0,
    hi: float = 10500.0,
) -> list[tuple[float, float]]:
    """从 192kHz 原始兵器母带中提取真实的刀身固有高频金属共振峰 (freq_hz, rel_amp)。"""
    raw, sr = load_raw(rel_path, mono=True)
    i0 = max(0, int(round(t0 * sr)))
    i1 = min(len(raw), int(round(t1 * sr)))
    seg = raw[i0:i1].copy()
    if len(seg) < 512:
        return [(3520.0, 1.0), (5420.0, 0.62), (7850.0, 0.42), (10400.0, 0.25)]
    # 聚焦峰值及峰值后余振区，避开纯宽带空气噪声
    pk_i = int(np.argmax(np.abs(seg)))
    a = min(max(0, pk_i + int(0.012 * sr)), max(0, len(seg) - 512))
    b = min(len(seg), a + int(0.32 * sr))
    if b - a < 256:
        a, b = 0, len(seg)
    w = seg[a:b] * np.hanning(b - a)
    nfft = 1 << 16
    spec = np.abs(np.fft.rfft(w, nfft))
    freqs = np.fft.rfftfreq(nfft, 1.0 / sr)
    idx = np.flatnonzero((freqs >= lo) & (freqs <= hi))
    if len(idx) == 0:
        return [(3520.0, 1.0), (5420.0, 0.62), (7850.0, 0.42), (10400.0, 0.25)]
    s_work = spec.copy()
    bin_sep = max(2, int(round(95.0 / (freqs[1] - freqs[0]))))
    peaks: list[tuple[float, float]] = []
    for _ in range(count):
        best = int(idx[int(np.argmax(s_work[idx]))])
        if s_work[best] <= 1e-12:
            break
        peaks.append((float(freqs[best]), float(s_work[best])))
        s_work[max(0, best - bin_sep):min(len(s_work), best + bin_sep + 1)] = 0.0
    if not peaks:
        return [(3520.0, 1.0), (5420.0, 0.62), (7850.0, 0.42), (10400.0, 0.25)]
    m = max(p[1] for p in peaks) + 1e-12
    return [(fr, amp / m) for fr, amp in peaks]


def cold_steel_ring(
    partials: list[tuple[float, float]],
    f_primary: float,
    dur_s: float,
    tau: float,
    bloom_s: float = 0.022,
    side_gain: float = 0.56,
    spine_low_ratio: float = 0.0,
    crystalline_boost: float = 0.45,
    shimmer: float = 0.0008,
    detune_cents: float = 2.4,
    seed: int = 1,
) -> np.ndarray:
    """直驱相位纯净冷钢长鸣合成器（无卷积高频衰减！）：
    将真实刀身泛音比锁定至高音区主频 f_primary (3.3kHz - 4.8kHz)，并补足 5.5kHz - 12.5kHz 极高频钢刃寒芒，
    每个分音带 0.08% (~2.5Hz) 双生微拍频金属光泽，呈现《只狼 / 星刃》最高音调名刀铮鸣！
    """
    rng = np.random.default_rng(seed)
    n = max(64, int(round(dur_s * SR)))
    t = np.arange(n) / SR
    st = np.zeros((2, n), dtype=np.float64)
    base_src = partials[0][0] if partials else 3500.0
    scale = f_primary / max(base_src, 200.0)

    mode_list: list[tuple[float, float, float]] = []
    for k, (fr, amp) in enumerate(partials):
        f0 = fr * scale
        # 若缩放后某分音落到 1.9kHz 以下，自动折叠回高音冷钢区，杜绝中低频木鱼/铁锅感
        while f0 < 1950.0:
            f0 *= 2.0
        while f0 > 13800.0:
            f0 *= 0.5
        a0 = amp if k == 0 else amp * side_gain
        tau_k = tau * ((f_primary / max(f0, f_primary * 0.7)) ** 0.52)
        mode_list.append((f0, a0, tau_k))

    # 显式注入 5.4kHz - 12.2kHz 极高频名刀寒芒泛音簇（决定“最高音调金属感”的灵魂频段）
    if crystalline_boost > 0.01:
        for mult, rel_a, tau_mul in (
            (1.515, 0.68 * crystalline_boost, 0.76),
            (2.190, 0.52 * crystalline_boost, 0.58),
            (2.960, 0.36 * crystalline_boost, 0.44),
        ):
            fh = f_primary * mult
            if fh < SR * 0.45:
                mode_list.append((fh, rel_a, tau * tau_mul))

    # 可选刀脊支撑泛音（如 2380Hz，保证高音锐利同时不单薄发飘）
    if spine_low_ratio > 0.01:
        f_sp = max(2150.0, f_primary * 0.665)
        mode_list.append((f_sp, spine_low_ratio, tau * 0.88))

    for f0, a0, tau_k in mode_list:
        if f0 >= SR * 0.46 or f0 < 200.0:
            continue
        rl = 2.0 ** (rng.uniform(-detune_cents, detune_cents) / 1200.0)
        rr = 2.0 ** (rng.uniform(-detune_cents, detune_cents) / 1200.0)
        pl = rng.uniform(0.0, 2.0 * np.pi)
        pr = rng.uniform(0.0, 2.0 * np.pi)
        env = a0 * np.exp(-t / max(0.012, tau_k))
        st[0] += env * (
            np.sin(2.0 * np.pi * (f0 * rl) * t + pl)
            + 0.48 * np.sin(2.0 * np.pi * (f0 * rl * (1.0 + shimmer)) * t + pl + 1.05)
        )
        st[1] += env * (
            np.sin(2.0 * np.pi * (f0 * rr) * t + pr)
            + 0.48 * np.sin(2.0 * np.pi * (f0 * rr * (1.0 + shimmer * 1.12)) * t + pr + 1.85)
        )

    if bloom_s > 0.0005:
        bloom = (np.clip(t / bloom_s, 0.0, 1.0) ** 1.35)[None, :]
        st *= bloom
    pk = float(np.abs(st).max()) + 1e-12
    return fade_io(st / pk, in_s=0.001, out_s=min(0.18, dur_s * 0.35))


def dense_metallic_shimmer(
    excite: np.ndarray,
    dur_s: float,
    tau_base: float = 0.36,
    lo: float = 2300.0,
    hi: float = 16200.0,
    modes: int = 260,
    seed: int = 7,
) -> np.ndarray:
    """《只狼》风格刀身密集高频丝滑金属共振光泽（2.3kHz - 16.2kHz 均匀模态，无突兀单频刺耳感）。"""
    rng = np.random.default_rng(seed)
    freqs = lo * ((hi / lo) ** rng.random(modes))
    amps = rng.uniform(0.75, 1.0, modes) * ((freqs / lo) ** -0.55)
    taus = tau_base * ((lo / freqs) ** 0.46) * rng.uniform(0.78, 1.22, modes)
    mono_ex = excite if excite.ndim == 1 else excite.mean(axis=0)
    ex_hi = hp(mono_ex[:min(len(mono_ex), int(0.024 * SR))], lo, order=2)
    return modal_bank(ex_hi, dur_s, freqs, amps, taus, detune_cents=4.5, seed=seed + 13)


def bright_sparks(x: np.ndarray, dur_s: float, hp_hz: float = 4400.0, t60: float = 0.42, seed: int = 19) -> np.ndarray:
    """提取真实刀刃碰撞 >4.4kHz 超高频火石擦挂声，扩散成明亮丝滑的冷钢火星尾迹。"""
    mono = x if x.ndim == 1 else x.mean(axis=0)
    n_out = max(64, int(round(dur_s * SR)))
    hi_src = hp(mono[:min(len(mono), int(0.14 * SR))], hp_hz, order=2)
    ir_len = max(64, int(round(t60 * 1.25 * SR)))
    tt = np.arange(ir_len) / SR
    pre = int(round(0.002 * SR))
    outs = []
    for ch_seed in (seed, seed + 31):
        rng = np.random.default_rng(ch_seed)
        ir = rng.standard_normal(ir_len) * np.exp(-6.9 * tt / max(0.05, t60))
        ir = bp(ir, hp_hz, 17500.0, order=2)
        ir = np.concatenate([np.zeros(pre), ir])
        w = fftconvolve(hi_src, ir)[:n_out]
        if len(w) < n_out:
            w = np.pad(w, (0, n_out - len(w)))
        outs.append(w)
    st = np.vstack(outs)
    pk = float(np.abs(st).max()) + 1e-12
    return fade_io(st / pk, in_s=0.001, out_s=min(0.12, dur_s * 0.3))


def slice_clean_clash_192k(
    rel_path: str,
    t_onset: float,
    cut_s: float = 0.138,
    speed: float = 1.05,
    hp_hz: float = 460.0,
    click_boost: float = 0.65,
) -> np.ndarray:
    """精确切取 192kHz 单次冷兵器刃对刃交击，在二次杂响前 (cut_s) 干净截断，并强化前 14ms 钻石级高频钢口！"""
    raw, sr = load_raw(rel_path, mono=True)
    i0 = max(0, int(round((t_onset - 0.008) * sr)))
    i1 = min(len(raw), i0 + int(round(0.55 * sr)))
    seg = raw[i0:i1].copy()
    seg -= np.mean(seg)
    if hp_hz > 0:
        seg = sosfiltfilt(butter(2, min(hp_hz, sr * 0.42), "high", fs=sr, output="sos"), seg)
    # 精确对齐第一下碰撞起音
    pk = float(np.abs(seg).max()) + 1e-12
    hits = np.flatnonzero(np.abs(seg) >= pk * 0.055)
    if len(hits) > 0:
        onset_i = max(0, int(hits[0]) - int(0.0012 * sr))
        seg = seg[onset_i:]
    # 在原录音二次余颤/杂响出现前干净截断并余弦淡出
    k_cut = min(len(seg), max(256, int(round(cut_s * sr))))
    seg = seg[:k_cut].copy()
    k_fade = min(len(seg) // 2, int(round(0.028 * sr)))
    if k_fade > 8:
        seg[-k_fade:] *= np.cos(np.linspace(0.0, np.pi / 2.0, k_fade)) ** 2

    # 192kHz -> 48kHz 抗混叠重采样（speed >= 1.0 保住最高音调“叮/锵”脆度）
    ratio = SR / (sr * max(speed, 0.25))
    nyq_src = 0.46 * sr * min(ratio, 1.0)
    if nyq_src < 0.48 * sr:
        seg = sosfiltfilt(butter(4, nyq_src, "low", fs=sr, output="sos"), seg)
    out_len = max(32, int(round(len(seg) * ratio)))
    y = np.interp(np.linspace(0, len(seg) - 1, out_len), np.arange(len(seg)), seg)
    y = y / (float(np.abs(y).max()) + 1e-12)

    # 前 14ms 的 >3.0kHz 钢口瞬态提亮，赋予刀尖硬碰硬的极致金属火花感
    if click_boost > 0.01 and len(y) > int(0.028 * SR):
        n_c = int(0.028 * SR)
        n_hold = int(0.012 * SR)
        edge = hp(y[:n_c], 3000.0, order=2)
        edge[n_hold:] *= np.cos(np.linspace(0.0, np.pi / 2.0, n_c - n_hold)) ** 2
        y[:n_c] += click_boost * edge
    return fade_io(y / (float(np.abs(y).max()) + 1e-12), in_s=0.0006, out_s=0.020)


def slice_razor_shing_192k(
    rel_path: str,
    t0: float,
    t1: float,
    speed: float = 1.15,
    pre_s: float = 0.050,
    post_s: float = 0.24,
    attack_s: float = 0.040,
    hp_hz: float = 1700.0,
) -> np.ndarray:
    """从 192kHz 快速拔刀母带提取凌冽金属刮擦“锵 / シャキン！”：
    高通滤除一切低闷摩擦，用二次包络塑形前导渐起，使冷钢寒光最高峰精准落在 pre_s (0.050s)！
    """
    y = slice_192k(rel_path, t0, t1, speed=speed, hp_hz=hp_hz, trim_onset=False)
    if len(y) < 64:
        return np.zeros(int((pre_s + post_s) * SR))
    y = hp(y, hp_hz, order=2)
    w = max(8, int(round(0.008 * SR)))
    env = np.convolve(y ** 2, np.ones(w) / w, mode="same")
    pk_i = int(np.argmax(env))
    n_pre = int(round(pre_s * SR))
    n_post = int(round(post_s * SR))

    if pk_i >= n_pre:
        seg = y[pk_i - n_pre:min(len(y), pk_i + n_post)].copy()
        lead = n_pre
    else:
        pad_l = n_pre - pk_i
        seg = np.pad(y[:min(len(y), pk_i + n_post)], (pad_l, 0))
        lead = n_pre

    if len(seg) < n_pre + n_post:
        seg = np.pad(seg, (0, (n_pre + n_post) - len(seg)))

    # 干净利落的金属渐起斜坡，既消除切点咔哒声，又让峰值像剃刀一样凌厉切出
    if lead > 0:
        k_att = min(lead, max(16, int(round(attack_s * SR))))
        seg[lead - k_att:lead] *= np.linspace(0.0, 1.0, k_att) ** 1.8
        if lead > k_att:
            seg[:lead - k_att] = 0.0

    pk = float(np.abs(seg).max()) + 1e-12
    return fade_io(seg / pk, in_s=0.0025, out_s=post_s * 0.52)


def rift_warp_synth(dur_s: float = 0.55, seed: int = 42, intensity: float = 1.0) -> np.ndarray:
    """《断晓》紫电空间裂口撕裂层（仅用于 rift_burst 等空间崩裂招式，去除廉价随机正弦颗粒，改用宽带电弧撕裂）。"""
    rng = np.random.default_rng(seed)
    n = max(64, int(round(dur_s * SR)))
    t = np.arange(n) / SR
    st = np.zeros((2, n))
    # 1) 空间坍缩下潜冲击核 (210Hz -> 42Hz)
    f_car = 42.0 + 170.0 * np.exp(-t / 0.055)
    ph_c = 2 * np.pi * np.cumsum(f_car) / SR
    ph_m = 2 * np.pi * np.cumsum(f_car * 2.41) / SR
    idx_env = 2.6 * intensity * np.exp(-t / 0.075)
    for ch, dph in enumerate([0.0, 0.65]):
        fm = np.sin(ph_c + dph + idx_env * np.sin(ph_m + dph * 1.3))
        st[ch] += 0.60 * fm * np.exp(-t / 0.14) * np.clip(t / 0.002, 0, 1)
    # 2) 高压宽带紫电电弧嘶裂（非单频正弦啾声，真实自然不科幻怪异）
    for ch in range(2):
        noise = rng.standard_normal(n)
        crack = bp(noise, 1800.0, 12500.0, order=2)
        flutter = 0.55 + 0.45 * np.sin(2 * np.pi * (28.0 + 9.0 * ch) * t + rng.uniform(0, 6.28))
        st[ch] += 0.45 * intensity * crack * flutter * np.exp(-t / 0.15)
    st = saturate(st, drive=1.65)
    return fade_io(st, 0.001, min(0.08, dur_s * 0.3))


# ------------------------------ 空间、立体声与混音母带 ------------------------------

def stereo_widen(x: np.ndarray, width_ms: float = 0.0, pan: float = 0.0, er_mix: float = 0.06, er_decay_s: float = 0.065, seed: int = 3) -> np.ndarray:
    """纯净无梳状滤波立体声空间构建：
    1) 严禁对干声做 Haas 延迟叠加（彻底根除梳状滤波空管怪味！）
    2) 严禁使用分立多抽头回声（彻底根除浴室瓷砖哒哒反射！）
    3) 干声保持 100% 相位纯净瞬态，仅叠加极克制的左右非相关高频丝滑空气漫反射 (<7% wet)。
    """
    st = ensure_stereo(x)
    n = st.shape[1]
    # 250Hz 以下单声道居中锁死冲击力
    lo = lp(st.mean(axis=0), 250.0, order=2)
    hi = hp(st, 250.0, order=2)
    out = np.vstack([lo, lo]) + hi

    # 等功率声像偏置 (-1.0 左 .. +1.0 右)
    if abs(pan) > 1e-3:
        angle = (np.clip(pan, -1.0, 1.0) + 1.0) * (np.pi / 4.0)
        out[0] *= np.cos(angle) * np.sqrt(2.0)
        out[1] *= np.sin(angle) * np.sqrt(2.0)

    # 极克制的左右非相关高频空气漫反射（无任何分立回声抽头，绝不糊瞬态）
    wet = float(np.clip(er_mix * 0.36, 0.0, 0.085))
    if wet > 0.004 and n > 64:
        t60 = float(np.clip(er_decay_s * 3.6, 0.16, 0.46))
        send = hp(out.mean(axis=0), 900.0, order=2)
        send_pk = float(np.abs(send).max())
        if send_pk > 1e-9:
            ir_len = max(64, int(round(t60 * 1.15 * SR)))
            tt = np.arange(ir_len) / SR
            pre = int(round(0.007 * SR))
            diff_lr = np.zeros_like(out)
            for ch, ch_seed in enumerate((seed * 2 + 11, seed * 2 + 29)):
                rng = np.random.default_rng(ch_seed)
                ir = rng.standard_normal(ir_len) * np.exp(-6.9 * tt / t60)
                ir = bp(ir, 950.0, 13500.0, order=2)
                ir = np.concatenate([np.zeros(pre), ir])
                w = fftconvolve(send, ir)[:n]
                w_pk = float(np.abs(w).max()) + 1e-12
                diff_lr[ch, :len(w)] = w * (send_pk / w_pk)
            out = out + wet * diff_lr
    return out


def dynamic_pan_sweep(x: np.ndarray, pan_start: float = -0.55, pan_end: float = 0.55) -> np.ndarray:
    """给冲刺斩等高速横掠招式施加平滑的立体声横扫运动轨迹。"""
    st = ensure_stereo(x)
    n = st.shape[1]
    pan_curve = np.linspace(pan_start, pan_end, n)
    ang = (np.clip(pan_curve, -1.0, 1.0) + 1.0) * (np.pi / 4.0)
    lo = lp(st.mean(axis=0), 200.0, order=2)
    hi = hp(st, 200.0, order=2)
    hi[0] *= np.cos(ang) * np.sqrt(2.0)
    hi[1] *= np.sin(ang) * np.sqrt(2.0)
    return np.vstack([lo, lo]) + hi


def bus_compress(x: np.ndarray, threshold_db: float = -12.0, ratio: float = 3.5, attack_s: float = 0.0018, release_s: float = 0.065) -> np.ndarray:
    """立体声联动 FET 风格压缩器：把冲击声前段托得紧实饱满。"""
    st = ensure_stereo(x)
    det = np.abs(st).max(axis=0)
    pk = float(det.max())
    if pk < 1e-9:
        return st
    thr = pk * (10.0 ** (threshold_db / 20.0))
    ca = np.exp(-1.0 / max(1.0, attack_s * SR))
    cr = np.exp(-1.0 / max(1.0, release_s * SR))
    env = np.empty_like(det)
    e = 0.0
    for i, v in enumerate(det):
        e = ca * e + (1.0 - ca) * v if v > e else cr * e + (1.0 - cr) * v
        env[i] = e
    over = np.maximum(env / max(thr, 1e-9), 1.0)
    gain = over ** (1.0 / ratio - 1.0)
    return st * gain[None, :]


def mix_layers(dur_s: float, *layers: tuple[np.ndarray, float, float]) -> np.ndarray:
    """混合多层信号：每项为 (signal_1d_or_2d, offset_seconds, gain_db)。"""
    n_total = max(32, int(round(dur_s * SR)))
    acc = np.zeros((2, n_total), dtype=np.float64)
    for sig, offset_s, gain_db in layers:
        st = ensure_stereo(sig)
        # 每层先归一到自身峰值 1.0 再按 gain_db 混合，确保配比直观可控
        pk = float(np.abs(st).max())
        if pk < 1e-12:
            continue
        st = (st / pk) * (10.0 ** (gain_db / 20.0))
        i0 = max(0, int(round(offset_s * SR)))
        if i0 >= n_total:
            continue
        take = min(st.shape[1], n_total - i0)
        acc[:, i0:i0 + take] += st[:, :take]
    return acc


def lookahead_limit(x: np.ndarray, ceiling_db: float = -1.0) -> np.ndarray:
    st = ensure_stereo(x)
    ceil = 10.0 ** (ceiling_db / 20.0)
    env = np.abs(st).max(axis=0)
    if float(env.max()) <= ceil:
        return st
    look = max(4, int(round(0.0018 * SR)))
    raw_g = np.minimum(1.0, ceil / np.maximum(env, 1e-12))
    g = minimum_filter1d(raw_g, size=look * 2 + 1)
    rel = np.exp(-1.0 / max(1.0, 0.028 * SR))
    for i in range(1, len(g)):
        g[i] = min(g[i], rel * g[i - 1] + (1.0 - rel))
    return st * g[None, :]


def master_finalize(
    x: np.ndarray,
    target_rms50_db: float = -12.0,
    ceiling_db: float = -1.0,
    hp_cut_hz: float = 32.0,
) -> np.ndarray:
    """商业游戏母带终混：去直流超低频 -> 50ms 滑动窗口最大响度精准校准 -> Lookahead 真峰值限幅。"""
    st = ensure_stereo(x)
    st -= np.mean(st, axis=1, keepdims=True)
    if hp_cut_hz > 0:
        st = hp(st, hp_cut_hz, order=2)
    win = max(16, int(round(0.050 * SR)))
    for _ in range(5):
        pwr = np.mean(st ** 2, axis=0)
        if len(pwr) <= win:
            max_e = float(np.mean(pwr))
        else:
            max_e = float(np.convolve(pwr, np.ones(win) / win, mode="valid").max())
        cur_db = 10.0 * np.log10(max(max_e, 1e-15))
        diff_db = np.clip(target_rms50_db - cur_db, -24.0, 24.0)
        st = st * (10.0 ** (diff_db / 20.0))
        st = lookahead_limit(st, ceiling_db=ceiling_db)
    return st


def measure_stats(x: np.ndarray) -> dict[str, float]:
    st = ensure_stereo(x)
    dur = st.shape[1] / SR
    pk_db = 20.0 * np.log10(max(float(np.abs(st).max()), 1e-12))
    win = max(16, int(round(0.050 * SR)))
    pwr = np.mean(st ** 2, axis=0)
    max_e = float(np.convolve(pwr, np.ones(win) / win, mode="valid").max()) if len(pwr) > win else float(np.mean(pwr))
    rms50_db = 10.0 * np.log10(max(max_e, 1e-15))
    # 峰值到达时间与频谱重心
    env10 = np.convolve(pwr, np.ones(int(0.008 * SR)) / int(0.008 * SR), mode="same")
    peak_s = float(np.argmax(env10)) / SR
    mono = st.mean(axis=0)
    spec = np.abs(np.fft.rfft(mono * np.hanning(len(mono))))
    freqs = np.fft.rfftfreq(len(mono), 1.0 / SR)
    centroid = float(np.sum(freqs * spec) / (np.sum(spec) + 1e-12))
    return {
        "duration_s": round(dur, 3),
        "peak_db": round(pk_db, 2),
        "rms50_db": round(rms50_db, 2),
        "peak_at_s": round(peak_s, 4),
        "centroid_hz": round(centroid, 0),
    }


def write_wav48(path: Path, x: np.ndarray) -> dict[str, float]:
    path.parent.mkdir(parents=True, exist_ok=True)
    st = ensure_stereo(x)
    sf.write(str(path), st.T, SR, subtype="PCM_16")
    return measure_stats(st)
