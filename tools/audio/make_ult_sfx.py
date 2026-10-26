"""大招「绝影 · 鸦羽止」整套音效（2026-10-26）：全部用真实录音（Still North CC0 兵器质感包 + 用户视频 6 的刀声 + fleshy fight），
按游戏里的大招帧号（60 帧/秒）对齐。输出每个提示音（cues/）和一条对齐样片画面的试听音轨。

时间轴（ult_frame）：
  0    发动：倒放的风声吸进去（时间停住）
  44   眼睛横向紫光：一声很轻的刀鸣
  108  推开鲤口：“咔”一下 + 刀身滑出的亮刮擦
  ~110→124  白闪：箭矢逼近的风声越来越响，到 124 一刀切断
  124  冲击帧：一声极短、极亮的斩 + 一点低频顿感；之后全场静
  ~146→168  静：收刀的摩擦声慢慢滑进去，168 “咔”（画面在这一帧跳切到收剑）
  168～174  顿帧：完全无声
  174  影沿刀线裂开：两声斩切 + 肉感切开，3 帧一前一后
"""
import os, sys
import numpy as np
sys.path.insert(0, r'E:/00game/nightcrow-godot/tools/audio')
import sfxlib as L

D = os.path.dirname(os.path.abspath(__file__))
SRC = r'E:/00game/work/sfx-audition-hit-parry-20261025/'
X = SRC + 'downloads/still-north-textures/x/'
FLESH = SRC + 'downloads/fleshy-fight/x/'
OUT = os.path.join(D, 'cues'); os.makedirs(OUT, exist_ok=True)
FPS = 60.0
TOTAL = 248


def load(path, a=None, b=None):
    x = L.decode(path)
    if a is not None:
        x = x[L.n(a):L.n(b) if b is not None else None]
    return x.copy()


def room(x, mix=0.08):
    """小房间（用户嫌大混响假）"""
    return L.reverb(x, t60=0.35, mix_=mix, damp=5000, pre=0.008)


# ---------------------------------------------------------------- 各提示音

def cue_start():
    # 倒放的挥刀风声：越来越近地吸进去，在第 10 帧收住
    w = load(X + 'Katana Swing.wav', 5.62, 5.86)
    w = L.hp(w[::-1], 700)
    w = L.fade(w, 0.004, 0.012)
    return L.normalize(room(w, 0.05), -26.0)


def cue_eye():
    # 视频 6 刀声里那段“唱”：只留 1.2kHz 以上的金属鸣，很轻
    r = load(SRC + 'refs/user_video6/blade_clean.wav', 0.17, 0.95)
    r = L.hp(r, 1200)
    r = r * L.env(len(r) / L.SR, attack=0.004, tau=0.22)
    return L.normalize(L.fade(r, 0.003, 0.08), -28.0)


PUSH_PRE = 0.29     # 推鲤口：click 在切片里的位置（秒）

def cue_push():
    # 拔刀录音开头：鲤口“咔”（0.29s）+ 刀身滑出的亮刮擦（0.42s 最亮）
    x = load(X + 'Katana Draw Fast.wav', 0.0, 0.62)
    x = L.hp(x, 300)
    x[:L.n(0.26)] *= 0.0
    x = L.fade(x, 0.002, 0.08)
    return L.normalize(room(x, 0.07), -19.0)


def cue_rise():
    # 重箭逼近：推开鲤口之后才起，0.25s 里越来越响，峰值放在最后（拇指蓄力那段保持安静）
    x = load(X + 'Scythian Recurve Heavy Arrow Approach.wav', 4.96, 5.215)
    x = L.hp(x, 400)
    x = x * np.linspace(0.25, 1.0, len(x)) ** 2
    x = L.fade(x, 0.01, 0.003)     # 结尾硬切
    return L.normalize(x, -22.0)


def cue_impact():
    # 极短极亮的一斩：挥刀录音最亮的 0.11s + 一点低频顿感（拳击录音低通，很短）
    s = load(X + 'Katana Swing.wav', 7.93, 8.06)
    s = L.hp(s, 900)
    s = L.fade(s, 0.001, 0.04)
    p = load(FLESH + 'punch_1a.wav')
    p = L.lp(p, 180)[:L.n(0.09)] * L.env(0.09, attack=0.001, tau=0.025)
    x = L.mix(0.16, (s, 0.0, 1.0), (p, 0.0, 0.6))
    return L.normalize(room(x, 0.06), -15.0, peak_ceiling_db=-1.0)


SHEATH_PRE = 0.42   # 收刀：click 在切片里的位置（秒）

def cue_sheathe():
    # 收刀录音：0.36s 摩擦滑进去 → 2.62s 那一下“咔”
    x = load(X + 'Katana Sheath Fast.wav', 2.20, 3.05)
    x = L.hp(x, 250)
    # 摩擦声提一点，让“嘶——”听得见
    k = L.n(SHEATH_PRE - 0.02)
    x[:k] *= 2.2
    x = L.fade(x, 0.03, 0.06)
    return L.normalize(room(x, 0.06), -18.0)


def cue_burst():
    # 两声斩切 + 肉感切开，3 帧一前一后
    s1 = L.hp(load(X + 'Katana Swing.wav', 5.74, 5.92), 700)
    s2 = L.hp(load(X + 'Katana Swing.wav', 0.33, 0.50), 700)
    f1 = load(FLESH + 'sword-1a.wav')
    f2 = load(FLESH + 'sword-1b.wav')
    gap = 3 / FPS
    x = L.mix(0.9, (L.fade(s1, 0.001, 0.03), 0.0, 1.0), (f1, 0.005, 0.8),
              (L.fade(s2, 0.001, 0.03), gap, 0.75), (f2, gap + 0.005, 0.6))
    return L.normalize(room(x, 0.09), -14.0, peak_ceiling_db=-1.0)


# ---------------------------------------------------------------- 放到时间轴上

def main():
    cues = {
        'ult_start': (cue_start(), 0, None),
        'ult_eye': (cue_eye(), 44, None),
        'ult_push': (cue_push(), 108, PUSH_PRE),
        'ult_rise': (cue_rise(), 124, 'end'),
        'ult_impact': (cue_impact(), 124, None),
        'ult_sheathe': (cue_sheathe(), 168, SHEATH_PRE),
        'ult_burst': (cue_burst(), 174, None),
    }
    track = np.zeros(L.n(TOTAL / FPS + 1.0))
    starts = {}
    for name, (x, frame, pre) in cues.items():
        t0 = frame / FPS
        if pre == 'end':
            t0 -= len(x) / L.SR
        elif pre is not None:
            t0 -= pre
        i = max(0, L.n(t0))
        track[i:i + len(x)] += x[:len(track) - i]
        starts[name] = round(t0 * FPS, 1)
        L.encode_ogg(x, os.path.join(OUT, name + '.ogg'), q=6)
        L.write_wav(x, os.path.join(OUT, name + '.wav'))
    track = L.limit(track, -1.0)
    L.write_wav(track, os.path.join(D, 'ult_track.wav'))
    for k, v in starts.items():
        print('%-12s 开始于第 %6.1f 帧' % (k, v))


if __name__ == '__main__':
    main()
