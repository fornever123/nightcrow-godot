"""大招开场声音 · 路线 B（11-01，用户选“做 B”：原片声音 + 真实 CC0 录音；替换 make_ult_open_sfx.py 那条兵器录音硬改的版本）。
电平按 50 ms 最大 RMS 定：心跳保持原片电平（约 −7 dB，和睁眼段 v8 一样），墨散 −15、张翅 −25（11-01 用户：“翻翅声也压小”，原 −15）、鸦鸣 −26（11-01 用户：“乌鸦叫太吵了……一点点小声的就行”，原 −13）、涌起 −20、吸气 −22。
对齐开场 66 帧（60 帧/秒），再往后多 26 帧让心跳接进睁眼：
  6～18   世界停住、被“吸进去”：v8 0.8～1.0 秒的高频亮音倒放
  2       墨散：OGA rubberduck slime_03（用户选），起音约 0.23 秒，峰落在第 16 帧墨折上墙（墙根不另配拍墙声，用户：“不要，只留墨散”）
  8～48   墨铺开的涌起：v8 3.4～4.3 秒的持续涌起，低切、慢起，46 帧前淡掉
  25、31  两只鸦式神张翅（第 34～42 帧）：Freesound 86883 渡鸦掠过的两段翅膀声，高通去掉风噪
  36      鸦鸣：OGA crow_caw.wav 原声整条（用户：“原声”），峰在第 46 帧，画面开始沉黑；压到很小、低通 2.8 kHz + 一点混响，像远处传来
  42      黑场里一对心跳：v3 0～0.8 秒，两拍落在第 48、70 帧，接睁眼段 v8 第 96 帧那一拍（间隔都是 0.4 秒）
输出 Remotion 预览用的 ult_open_b.ogg（不进游戏资源；进游戏走 export_ult_game_media.sh 整段混音）。
"""
import sys
import numpy as np
sys.path.insert(0, r'E:/00game/nightcrow-godot/tools/audio')
import sfxlib as L

B = r'E:/00game/work/sfx-ult-b/'
V3 = r'E:/00game/ult-slash-remotion/public/ult/v3.mp4'
V8 = r'E:/00game/ult-slash-remotion/public/ult/v8.mp4'
OUT = r'E:/00game/ult-slash-remotion/public/ult/sfx/ult_open_b.ogg'
FPS = 60.0
T = 92 / FPS


def f(frame):
    return frame / FPS


def cut(path, a, b):
    x = L.decode(path)
    return x[L.n(a):L.n(b)].copy()


def suck():
    x = L.hp(cut(V8, 0.8, 1.0), 1200, 2)[::-1]
    x = x * np.linspace(0.2, 1.0, len(x)) ** 2
    return L.normalize(L.fade(x, 0.02, 0.006), -22.0)


def ink():
    x = L.decode(B + 'oga/slime/slime_03.ogg')
    return L.normalize(L.fade(x, 0.002, 0.06), -15.0)


def swell():
    x = L.hp(cut(V8, 3.4, 4.3), 150, 2)
    x = x * L.swell(len(x) / L.SR, peak_at=0.35, rise_curve=2.0, tau=0.25)
    return L.normalize(L.fade(x, 0.02, 0.15), -20.0)


def wing(a, b):
    x = cut(B + 'freesound/86883__jamesoc__ravenflyby.aiff', a, b)
    x = L.hp(L.hp(x, 220, 2), 220, 2)
    return L.normalize(L.fade(x, 0.02, 0.04), -25.0)


def caw():
    x = L.decode(B + 'oga/crow_caw.wav')
    x = L.lp(L.fade(x, 0.002, 0.03), 2800, 2)
    x = L.reverb(x, t60=0.7, mix_=0.25)
    return L.normalize(x, -26.0)


def heart():
    x = cut(V3, 0.0, 0.8)
    return L.fade(x, 0.003, 0.12)


def main():
    x = L.mix(T,
              (suck(), f(6), 1.0),
              (ink(), f(2), 1.0),
              (swell(), f(8), 1.0),
              (wing(12.3, 12.6), f(25), 0.9),
              (wing(14.2, 14.6), f(31), 1.0),
              (caw(), f(36), 1.0),
              (heart(), f(42), 1.0))
    x = L.limit(x, -1.0)
    L.encode_ogg(x, OUT, q=6)
    print('ok', OUT, 'rms max', L.rms_max_db(x), 'peak', L.peak_db(x))


if __name__ == '__main__':
    main()
