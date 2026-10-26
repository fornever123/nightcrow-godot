"""把 Still North 刀对刀长录音里的每一次撞击切出来并打分（找"振刀嗡鸣"最足的几下）。

用法：python -I slice_src.py   → scan/still_north_hits.json + scan/sn_XX.wav（前 24 名，48kHz 单声道）
指标：
  ring_s    从峰值衰减 30dB 用了多久（余振/嗡鸣长度）
  sustain   峰后 150–600ms 的能量相对峰值（dB，越大越"嗡"）
  centroid  频谱重心
"""
import os, sys, glob, json, subprocess, shutil
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'downloads', 'still-north', 'x')
OUT = os.path.join(HERE, 'scan')
SR = 48000
FFMPEG = shutil.which('ffmpeg')


def load(path):
    raw = subprocess.run([FFMPEG, '-v', 'error', '-i', path, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'],
                         check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def env_db(x, win):
    w = int(win * SR); k = len(x) // w
    e = np.sqrt((x[:k * w].reshape(k, w) ** 2).mean(axis=1) + 1e-12)
    return 20 * np.log10(e)


def onsets(x):
    e = env_db(x, 0.005)                 # 5ms 一格
    floor = np.percentile(e, 20)
    hits = []
    for i in range(4, len(e)):
        if e[i] - e[i - 4:i].max() > 14 and e[i] > floor + 30 and (not hits or i - hits[-1] > 60):
            hits.append(i)
    return [h * 0.005 for h in hits]


def score(seg):
    e = env_db(seg, 0.01)
    p = int(np.argmax(e[:10])); pk = e[p]
    after = np.nonzero(e[p:] < pk - 30)[0]
    ring = (after[0] if len(after) else len(e) - p) * 0.01
    sus = e[p + 15:p + 60].mean() - pk if len(e) > p + 60 else -60
    spec = np.abs(np.fft.rfft(seg[:int(0.6 * SR)])); f = np.fft.rfftfreq(min(len(seg), int(0.6 * SR)), 1 / SR)
    cen = float((spec * f).sum() / (spec.sum() + 1e-12))
    return round(float(pk), 1), round(float(ring), 2), round(float(sus), 1), round(cen)


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for path in sorted(glob.glob(os.path.join(SRC, '*.wav'))):
        name = os.path.basename(path)
        if 'Blade' not in name:
            continue
        x = load(path)
        ts = onsets(x)
        for j, t in enumerate(ts):
            end = min(ts[j + 1] if j + 1 < len(ts) else len(x) / SR, t + 3.0)
            a = max(0, int((t - 0.01) * SR)); b = int(end * SR)
            seg = x[a:b]
            if len(seg) < int(0.3 * SR):
                continue
            pk, ring, sus, cen = score(seg)
            rows.append({'file': name, 't': round(t, 3), 'len': round(len(seg) / SR, 2), 'peak_db': pk,
                         'ring_s': ring, 'sustain_db': sus, 'centroid': cen})
    # 嗡鸣优先：余振长 + 峰后能量高；太弱的不要
    good = [r for r in rows if r['peak_db'] > -40]
    good.sort(key=lambda r: (r['ring_s'] + 0.05 * r['sustain_db']), reverse=True)
    for k, r in enumerate(good[:24]):
        x = load(os.path.join(SRC, r['file']))
        a = max(0, int((r['t'] - 0.01) * SR)); seg = x[a:a + int(r['len'] * SR)]
        seg = seg / (np.abs(seg).max() + 1e-12) * 0.89
        r['clip'] = 'sn_%02d.wav' % k
        import wave
        w = wave.open(os.path.join(OUT, r['clip']), 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((seg * 32767).astype('<i2').tobytes()); w.close()
    json.dump({'total_hits': len(rows), 'top': good[:24]}, open(os.path.join(OUT, 'still_north_hits.json'), 'w'),
              ensure_ascii=False, indent=1)
    print('hits found:', len(rows))
    for r in good[:24]:
        print(r)


if __name__ == '__main__':
    main()
