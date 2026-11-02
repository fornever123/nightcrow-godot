"""大招开场 v10 的声音（10-31，用户看整段预览 5 后同意补：开场 1.1 秒原来完全没声音）。
全用现有真实录音变调、滤波拼出来，对齐 v10 的帧（60 帧/秒）：
  0～60   地鸣：慢收刀的刮擦降两个八度、低通，一路往上推，第 60 帧（全黑）一刀切断 → 抽空
  2、14   脚下鼓泡：肉感切开的录音降调、低通，像黏稠的墨
  16      墨撞墙根往上折：一声更重的黏稠拍击
  28、38  两只鸦式神破墨张翅：箭羽摩擦的录音降一点调，短促的“哗”
输出 Remotion 预览用的 ult_open.ogg（不进游戏资源）。
"""
import os, sys
import numpy as np
sys.path.insert(0, r'E:/00game/nightcrow-godot/tools/audio')
import sfxlib as L

SRC = r'E:/00game/work/sfx-audition-hit-parry-20261025/downloads/'
X = SRC + 'still-north-textures/x/'
FLESH = SRC + 'fleshy-fight/x/'
OUT = r'E:/00game/ult-slash-remotion/public/ult/sfx/ult_open.ogg'
FPS = 60.0
T = 66 / FPS


def load(path, a=None, b=None):
    x = L.decode(path)
    if a is not None:
        x = x[L.n(a):L.n(b) if b is not None else None]
    return x.copy()


def rumble():
    x = load(X + 'Katana Sheath Slow.wav')
    x = L.lp(L.resample(x, 0.25), 380, 4)
    k = L.n(60 / FPS)
    x = np.resize(x, k) if len(x) < k else x[:k]
    x = x * np.linspace(0.05, 1.0, k) ** 2.2
    x[-L.n(0.004):] *= np.linspace(1, 0, L.n(0.004))  # 全黑那一帧切断
    return L.normalize(x, -24.0)


def goo(name, ratio, lp_hz=1600):
    x = load(FLESH + name)
    x = L.lp(L.resample(x, ratio), lp_hz, 2)
    return L.normalize(L.fade(x, 0.003, 0.08), -24.0)


def wing(a, ratio):
    x = load(X + 'Arrow Fletching.wav')
    s = L.n(a)
    x = x[s:s + L.n(0.3)]
    x = L.hp(L.resample(x, ratio), 500)
    x = x * L.env(len(x) / L.SR, attack=0.02, tau=0.09)
    return L.normalize(L.fade(x, 0.005, 0.05), -24.0)


def main():
    fl = load(X + 'Arrow Fletching.wav')
    # 找箭羽录音里最响的两段当翅膀
    w = L.n(0.05)
    e = np.array([np.sqrt((fl[i:i + w] ** 2).mean()) for i in range(0, len(fl) - w, w)])
    top = sorted(np.argsort(e)[-2:] * 0.05)
    x = L.mix(T,
              (rumble(), 0.0, 1.0),
              (goo('punch_1b.wav', 0.5, 900), 2 / FPS, 0.55),
              (goo('sword-1a.wav', 0.55), 14 / FPS, 0.7),
              (goo('sword-arm-2a.wav', 0.5), 16 / FPS, 1.0),
              (wing(max(0.0, top[0] - 0.05), 0.85), 28 / FPS, 0.8),
              (wing(max(0.0, top[1] - 0.05), 0.8), 38 / FPS, 0.7))
    x[L.n(60 / FPS):] = 0.0  # 全黑：抽空
    x = L.reverb(x, t60=0.35, mix_=0.06, damp=5000, pre=0.008)
    x[L.n(60 / FPS):] = 0.0
    x = L.normalize(x, -21.0, peak_ceiling_db=-3.0)
    L.encode_ogg(x, OUT, q=6)
    print('ok', OUT, 'rms max', L.rms_max_db(x), 'peak', L.peak_db(x))


if __name__ == '__main__':
    main()
