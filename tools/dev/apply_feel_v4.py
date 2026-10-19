#!/usr/bin/env python3
"""第四轮手感（照《疯狂小人战斗》）：把招式改成"快出手、短顿帧、轻招不震屏"。

用法：python3 tools/dev/apply_feel_v4.py   （会直接改 assets/data/battle.json）
帧数都是 60fps 的游戏帧：S=前摇 A=判定 C=判定结束到接招点 T=接招点到收招结束。
脚本按动画时间反推每段的播放速度（startupSpeed/activeSpeed/recoverySpeed/tailSpeed）。
"""
import json, math, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
PATH = ROOT / "assets/data/battle.json"

#        id               S  A  C  T   攻顿 受顿 震屏  前冲  空中托举
PLAN = {
    "light_1":         (5, 3, 4, 8,   3, 4,  0.0, 120, None),
    "light_2":         (4, 3, 6, 10,  3, 4,  0.0, 120, None),
    "light_3":         (4, 5, 14, 14, 6, 8,  4.0, 200, None),
    "charge_1":        (6, 5, 10, 14, 8, 10, 7.0, 260, None),
    "up_strike":       (6, 4, 8, 14,  5, 6,  2.5, 60,  None),
    "air_up":          (5, 4, 4, 4,   3, 4,  0.0, 40,  None),
    "air_light_1":     (5, 4, 4, 4,   3, 4,  0.0, 40,  0),
    "air_light_2":     (3, 5, 0, 5,   3, 4,  0.0, 40,  0),
    "air_light_3":     (0, 6, 10, 10, 5, 6,  3.0, 60,  0),
    "dash_slash":      (7, 8, 12, 12, 6, 8,  5.0, 300, None),
    "dash_slash_left": (7, 8, 8, 4,   6, 8,  5.0, 300, None),
    "ranged_1":        (6, 4, 8, 0,   1, 2,  0.0, 0,   None),
}


def ticks_before(frames, n):
    t = 0.0
    for f in frames[:max(n, 0)]:
        v = f.get("durationTicks", 1.0)
        t += float(v) if isinstance(v, (int, float)) and v > 0 else 1.0
    return t


def anim_times(mv, anims):
    if mv.get("syncAnimation") and mv.get("animation") in anims:
        clip = anims[mv["animation"]]
        frames = clip.get("frames", [])
        fps = float(clip.get("fps", 36)) * float(mv.get("animationSpeed", 1.0))
        dur = ticks_before(frames, len(frames)) / fps
        st = ticks_before(frames, int(mv.get("activeFrameStart", 2))) / fps
        en = ticks_before(frames, int(mv.get("activeFrameEnd", 12)) + 1) / fps
        ch = ticks_before(frames, int(mv.get("chainFrame", len(frames)))) / fps
    else:
        dur, st, en = float(mv["duration"]), float(mv["activeStart"]), float(mv["activeEnd"])
        ch = float(mv.get("chainOpen", en))
    en = max(en, st)
    ch = min(max(ch, en), max(dur, en))
    dur = max(dur, ch)
    return st, en, ch, dur


def speed(seconds, frames):
    if frames <= 0 or seconds <= 1e-9:
        return 1.0 if seconds <= 1e-9 else 50.0
    return round(seconds * 60.0 / frames, 6) - 1e-6


def main():
    text = PATH.read_text(encoding="utf-8")
    cfg = json.loads(text)
    anims = cfg["characters"][0]["sprite"]["animations"]
    for mv in cfg["moves"]:
        plan = PLAN.get(mv["id"])
        if plan is None:
            continue
        s, a, c, t, hs, vhs, shake, lunge, suspend = plan
        st, en, ch, dur = anim_times(mv, anims)
        mv["startupSpeed"] = speed(st, s)
        mv["activeSpeed"] = speed(en - st, a)
        mv["recoverySpeed"] = speed(ch - en, c)
        mv["tailSpeed"] = speed(dur - ch, t)
        mv["hitstop"] = round(hs / 60.0, 5)
        mv["victimHitstop"] = round(vhs / 60.0, 5)
        mv["shakeAmount"] = shake
        mv["lunge"] = lunge
        if "moveCancelDelay" in mv or mv["input"] == "J":
            mv["moveCancelDelay"] = 0
        if suspend is not None:
            mv["airSuspendFrames"] = suspend
            mv["airGravityScale"] = 1.0
    cfg["feedback"]["shakeMultiplier"] = 1.0
    rt = cfg["runtime"]
    rt["attackBufferFrames"] = 16
    rt["comboKeepFrames"] = 40
    PATH.write_text(json.dumps(cfg, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print("ok")


if __name__ == "__main__":
    main()
