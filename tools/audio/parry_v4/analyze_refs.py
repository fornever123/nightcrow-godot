"""量化著名游戏弹刀参考（refs/，只做分析、不进游戏）和我们的候选，得出可执行的配方数据。

用法：python -I analyze_refs.py [文件...]   默认分析 refs/*.mp3 + processed2/cand2_parry_*.wav
每个文件输出：
  ring       嗡鸣主音：起音后 0.3–1.0s 最强的几个音调峰（Hz，相对峰值 dB）
  ring_t40   主音从峰值衰减 40dB 用了多久（s）
  bands      各频段在起音 0–50ms 的能量占比
  low_t20    100Hz 以下低频冲击衰减 20dB 用了多久（s）
  hi_t20     4kHz 以上"火花"衰减 20dB 用了多久（s）
  tone_vs_hit  0.5s 时主音电平相对起音峰值（dB）
  tail_hi_db   0.5–1.0s 里 1.5kHz 以上的宽带能量相对起音峰值（dB）：金属"沙沙"质感有多厚
  line_share   这段里主音占 1.5kHz 以上能量的比例：越接近 1 越像单一干净谱线（合成感）
"""
import os, sys, glob, json, shutil, subprocess
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SR = 48000
FFMPEG = shutil.which('ffmpeg')


def load(path):
    raw = subprocess.run([FFMPEG, '-v', 'error', '-i', path, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def band(x, lo, hi):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    X[(f < lo) | (f >= hi)] = 0
    return np.fft.irfft(X, len(x))


def env_db(x, win=0.01):
    w = int(win * SR); k = len(x) // w
    return 20 * np.log10(np.sqrt((x[:k * w].reshape(k, w) ** 2).mean(axis=1)) + 1e-12)


def t_drop(e, p, db):
    i = np.nonzero(e[p:] < e[p] - db)[0]
    return round(float((i[0] if len(i) else len(e) - p) * 0.01), 2)


def analyze(path):
    x = load(path)
    e = env_db(x); on = int(np.argmax(e > e.max() - 30)); x = x[max(0, on * 480 - 480):]
    e = env_db(x); p = int(np.argmax(e[:30]))
    a, b = int(0.3 * SR), min(len(x), int(1.0 * SR))
    seg = x[a:b] * np.hanning(b - a)
    spec = np.abs(np.fft.rfft(seg, 1 << 16)); f = np.fft.rfftfreq(1 << 16, 1 / SR)
    m = (f > 300) & (f < 12000); idx = np.nonzero(m)[0]; s = spec.copy(); peaks = []
    for _ in range(5):
        i = idx[np.argmax(s[idx])]; peaks.append(i); s[max(0, i - 40):i + 40] = 0
    top = spec[peaks[0]]
    ring = [(round(float(f[i])), round(float(20 * np.log10(spec[i] / top)), 1)) for i in peaks]
    f0 = f[peaks[0]]
    tone = band(x, f0 * 0.97, f0 * 1.03); et = env_db(tone); pt = int(np.argmax(et[:40]))
    head = x[:int(0.05 * SR)]
    H = np.abs(np.fft.rfft(head)) ** 2; fh = np.fft.rfftfreq(len(head), 1 / SR); tot = H.sum()
    bands = {k: round(float(100 * H[(fh >= lo) & (fh < hi)].sum() / tot)) for k, (lo, hi) in
             {'<150': (0, 150), '150-1k': (150, 1000), '1-4k': (1000, 4000), '>4k': (4000, 24000)}.items()}
    el = env_db(band(x, 20, 100)); eh = env_db(band(x, 4000, 20000))
    e05 = env_db(tone)[50] if len(et) > 50 else -120
    # 尾音质感：0.5–1.0s 里 1.5kHz 以上的宽带能量（相对起音峰值）和"线状程度"（主音占 1.5k 以上能量的比例）
    tail = band(x[int(0.5 * SR):int(1.0 * SR)], 1500, 16000) if len(x) > SR else np.zeros(10)
    tail_db = round(float(10 * np.log10((tail ** 2).mean() + 1e-12) - e[p]), 1)
    T = np.abs(np.fft.rfft(tail)) ** 2; ft = np.fft.rfftfreq(len(tail), 1 / SR)
    line = round(float(T[(ft > f0 * 0.98) & (ft < f0 * 1.02)].sum() / (T[ft > 1500].sum() + 1e-12)), 2)
    return {'file': os.path.basename(path), 'dur': round(len(x) / SR, 2), 'ring': ring,
            'tail_hi_db': tail_db, 'line_share': line,
            'ring_t40': t_drop(et, pt, 40), 'bands': bands,
            'low_t20': t_drop(el, int(np.argmax(el[:30])), 20), 'hi_t20': t_drop(eh, int(np.argmax(eh[:30])), 20),
            'tone_vs_hit_0.5s': round(float(e05 - e[p]), 1)}


def main():
    files = sys.argv[1:] or sorted(glob.glob(os.path.join(HERE, 'refs', '*.mp3'))) + \
        sorted(glob.glob(os.path.join(HERE, 'processed2', 'cand2_parry_*.wav'))) + [os.path.join(HERE, 'current', 'parry.wav')]
    rows = [analyze(p) for p in files]
    json.dump(rows, open(os.path.join(HERE, 'refs', 'analysis.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    for r in rows:
        print(r)


if __name__ == '__main__':
    main()
