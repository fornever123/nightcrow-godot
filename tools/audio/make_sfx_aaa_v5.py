r"""《断晓》商业 3A 级全量混合合成音效生成器（sfx_aaa_v5 · 48kHz 16-bit Stereo）。

运行方式：
    C:\Python314\python.exe -P tools/audio/make_sfx_aaa_v5.py

输出：
  1. 游戏实机高清音效库：nightcrow-godot/assets/audio/sfx_aaa_v5/（含 manifest.json、LICENSE.txt、README.md）
  2. 新旧 A/B 可视化对比试听站：E:/00game/work/nightcrow-3a音效合成-20261114/（含旧音效解码对比与频谱指标）
"""
from __future__ import annotations

import base64
import json
from pathlib import Path
import shutil
import sys
import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import aaa_dsp as D  # noqa: E402

ROOT = HERE.parents[1]
OUT_BANK = ROOT / "assets" / "audio" / "sfx_aaa_v5"
OLD_BANK = ROOT / "assets" / "audio" / "sfx_v3"
AUDITION_DIR = Path(r"E:\00game\work\nightcrow-3a音效合成-20261114")

# ---------------------------------------------------------------------------
# 精选 192kHz / 24-bit 物理母带瞬态坐标池（全部经频谱高通占比与峰值扫描实测核验）
# ---------------------------------------------------------------------------
SN_TEX = "still-north-textures/x/"
SN_HIT = "still-north/x/"

KATANA_SWINGS = [
    (SN_TEX + "Katana Swing.wav", 0.305, 0.450),
    (SN_TEX + "Katana Swing.wav", 1.285, 1.420),
    (SN_TEX + "Katana Swing.wav", 2.275, 2.395),
    (SN_TEX + "Katana Swing.wav", 3.450, 3.565),
    (SN_TEX + "Katana Swing.wav", 5.740, 5.885),
    (SN_TEX + "Katana Swing.wav", 6.960, 7.105),
]
SABRE_SWINGS = [
    (SN_TEX + "Sabre Swing.wav", 0.500, 0.670),
    (SN_TEX + "Sabre Swing.wav", 12.840, 12.975),
    (SN_TEX + "Sabre Swing.wav", 14.880, 14.995),
    (SN_TEX + "Sabre Swing.wav", 15.410, 15.520),
    (SN_TEX + "Sabre Swing.wav", 20.215, 20.385),
]
DAGGER_SWINGS = [
    (SN_TEX + "Dagger Swing.wav", 0.995, 1.115),
    (SN_TEX + "Dagger Swing.wav", 1.540, 1.660),
    (SN_TEX + "Dagger Swing.wav", 2.600, 2.720),
]
HEAVY_SWINGS = [
    (SN_TEX + "Spear Swing.wav", 0.200, 0.315),
    (SN_TEX + "Spear Swing.wav", 0.840, 0.970),
    (SN_TEX + "Spear Swing.wav", 3.160, 3.275),
    (SN_TEX + "Seax Swing.wav", 2.435, 2.550),
    (SN_TEX + "Seax Swing.wav", 5.925, 6.035),
]

# 凌冽寒光核心源：192kHz 快速金属出鞘刮擦（>2kHz 能量占比高达 92%~95%，重心 5700~7376Hz！）
SABRE_RAZOR_DRAWS = [
    (SN_TEX + "Sabre Draw Fast.wav", 2.560, 3.055),    # hi_share=0.95, centroid=6466Hz
    (SN_TEX + "Sabre Draw Fast.wav", 7.370, 7.870),    # hi_share=0.92, centroid=5710Hz
    (SN_TEX + "Sabre Draw Fast.wav", 10.845, 11.345),  # hi_share=0.95, centroid=5917Hz
    (SN_TEX + "Sabre Draw Fast.wav", 11.535, 11.945),  # hi_share=0.95, centroid=6234Hz
    (SN_TEX + "Sabre Draw Fast.wav", 12.215, 12.650),  # hi_share=0.94, centroid=6305Hz
    (SN_TEX + "Sabre Draw Fast.wav", 8.800, 9.275),    # hi_share=0.93, centroid=6086Hz
]
DAGGER_RAZOR_DRAWS = [
    (SN_TEX + "Dagger Draw Fast.wav", 0.450, 0.685),   # hi_share=0.95, centroid=6881Hz
    (SN_TEX + "Dagger Draw Fast.wav", 1.810, 2.065),   # hi_share=0.95, centroid=6850Hz
    (SN_TEX + "Dagger Draw Fast.wav", 3.390, 3.680),   # hi_share=0.93, centroid=7376Hz
]
KATANA_DRAWS = [
    (SN_TEX + "Katana Draw Fast.wav", 0.165, 0.595),   # centroid=4711Hz
    (SN_TEX + "Katana Draw Fast.wav", 1.210, 1.605),   # centroid=4100Hz
    (SN_TEX + "Katana Draw Fast.wav", 2.225, 2.665),   # centroid=5571Hz
    (SN_TEX + "Katana Draw Fast.wav", 3.145, 3.545),   # centroid=4178Hz
    (SN_TEX + "Seax Draw Fast.wav", 2.235, 2.565),     # centroid=6609Hz
]
KATANA_SHEATHS = [
    (SN_TEX + "Katana Sheath Fast.wav", 2.56, 2.74),
    (SN_TEX + "Katana Sheath Fast.wav", 5.50, 5.88),
    (SN_TEX + "Sabre Sheath Fast.wav", 1.39, 1.92),
]

# 弹刀核心源：经 still_north_hits.json 逐一核验的单次纯净高音刃对刃撞击 (file, onset_s, clean_cut_s)
CLEAN_HIGH_CLASHES = [
    (SN_HIT + "Spear Spear Blade on Blade.wav", 11.225, 0.138),       # peak -20.8dB, centroid 5852Hz
    (SN_HIT + "Mace Sabre Blade.wav", 3.310, 0.138),                  # centroid 6405Hz!
    (SN_HIT + "Axe Spear Blade on Blade.wav", 0.545, 0.128),          # centroid 6601Hz!
    (SN_HIT + "Mace Sabre Blade.wav", 4.300, 0.142),                  # peak -27.2dB, centroid 5690Hz
    (SN_HIT + "Spear Sabre Blade on Blade.wav", 12.715, 0.138),       # centroid 6264Hz!
    (SN_HIT + "Seax Dagger Blade on Blade.wav", 9.070, 0.134),        # centroid 6103Hz!
    (SN_HIT + "Norse Sword Katana Blade on Blade.wav", 12.805, 0.140),  # centroid 5304Hz
]
BLADE_CLASHES = [
    (c[0], c[1], c[1] + 0.55) for c in CLEAN_HIGH_CLASHES
]
HILT_CLASHES = [
    (SN_HIT + "Sabre Katana Hilt on Blade.wav", 9.30, 9.68),
    (SN_HIT + "Sabre Katana Hilt on Blade.wav", 0.24, 0.62),
    (SN_HIT + "Sabre Katana Hilt on Blade.wav", 2.17, 2.55),
    (SN_HIT + "Spear Sabre Blade on Hilt.wav", 6.175, 6.55),
]


# ===========================================================================
# 1. 身法与雨港湿石板物理交互（Footsteps, Jump, Double-Jump, Land）
# ===========================================================================

def build_step(idx: int) -> np.ndarray:
    """雨港湿青石板疾跑皮靴：干脆靴跟触石瞬态 + 极细腻积水微花 + 风衣微擦。"""
    dur = 0.14
    boot_file = f"kenney-impact-sounds/x/Audio/footstep_concrete_00{idx % 5}.ogg"
    splash_file = f"oga-40-cc0-water-splash/x/splash_0{(idx % 6) + 1}.ogg"
    cloth_file = f"kenney-rpg-audio/x/Audio/cloth{(idx % 3) + 1}.ogg"

    pitch = [0.96, 1.04, 0.99, 1.07, 0.94, 1.02][idx % 6]
    boot = D.slice_192k(boot_file, 0.0, 0.16, speed=pitch, hp_hz=85.0)
    boot = D.transient_shaper(boot, attack_db=6.5, sustain_db=-7.0)
    boot = D.tilt_eq(boot, low_shelf_db=2.0, presence_db=3.5, air_db=1.5)
    boot = D.crop_or_pad(boot, 0.095, fade_out_s=0.045)

    # 极克制的高频湿石板微水珠（>2.8kHz，绝不成踩水坑哗啦声）
    sp = D.slice_192k(splash_file, 0.01, 0.16, speed=1.45 + 0.08 * (idx % 3), hp_hz=2800.0)
    sp = D.crop_or_pad(sp, 0.105, fade_out_s=0.055)

    cl = D.slice_192k(cloth_file, 0.0, 0.12, speed=1.35, hp_hz=450.0)
    cl = D.crop_or_pad(cl, 0.085, fade_out_s=0.04)

    heel_sub = D.sub_drop(0.065, f_start=128 * pitch, f_end=58, tau_pitch=0.018, tau_amp=0.028, drive=1.3)
    st = D.mix_layers(
        dur,
        (boot, 0.0, 0.0),
        (heel_sub, 0.0, -7.5),
        (sp, 0.005, -13.5),
        (cl, 0.008, -16.5),
    )
    pan = [-0.08, 0.08, -0.06, 0.07, -0.09, 0.06][idx % 6]
    st = D.stereo_widen(st, width_ms=0.28, pan=pan, er_mix=0.10, er_decay_s=0.045, seed=100 + idx)
    return D.master_finalize(st, target_rms50_db=-22.5)


def build_jump(idx: int, double: bool = False) -> np.ndarray:
    if not double:
        dur = 0.25
        boot = D.slice_192k(f"kenney-impact-sounds/x/Audio/footstep_concrete_00{idx % 5}.ogg", 0.0, 0.12, speed=1.18, hp_hz=110.0)
        boot = D.transient_shaper(boot, attack_db=5.5, sustain_db=-6.0)
        cloth = D.slice_192k(f"kenney-rpg-audio/x/Audio/cloth{(idx % 3) + 1}.ogg", 0.0, 0.25, speed=1.08 + 0.05 * idx, hp_hz=260.0)
        whoosh_f, t0, t1 = DAGGER_SWINGS[idx % len(DAGGER_SWINGS)]
        air = D.slice_192k(whoosh_f, t0, t1, speed=1.25 + 0.06 * idx, hp_hz=320.0)
        air = D.lp(air, 6800.0)
        sp = D.slice_192k(f"oga-40-cc0-water-splash/x/splash_0{(idx % 4) + 1}.ogg", 0.0, 0.15, speed=1.4, hp_hz=2400.0)
        push = D.sub_drop(0.09, f_start=115, f_end=56, tau_pitch=0.025, tau_amp=0.045, drive=1.4)
        st = D.mix_layers(
            dur,
            (boot, 0.0, -2.5),
            (push, 0.0, -6.0),
            (cloth, 0.008, -3.5),
            (air, 0.012, -5.0),
            (sp, 0.006, -13.0),
        )
        st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.38, er_mix=0.12, seed=200 + idx), dur, 0.06)
        return D.master_finalize(st, target_rms50_db=-19.0)
    else:
        # 二段跳：夜鸦踏空（轻巧利落的羽翼掠风 + 空灵冷银微泛音）
        dur = 0.28
        wf, t0, t1 = DAGGER_SWINGS[(idx + 1) % len(DAGGER_SWINGS)]
        wing_a = D.slice_192k(wf, t0, t1, speed=1.35 + 0.06 * idx, hp_hz=420.0)
        cloth = D.slice_192k(f"kenney-rpg-audio/x/Audio/cloth{(idx % 3) + 1}.ogg", 0.0, 0.22, speed=1.25, hp_hz=380.0)
        # 第二拍微羽翼扑动营造真实鸟翼双拍感
        wing_b = D.crop_or_pad(D.slice_192k(wf, t0, t1, speed=1.55, hp_hz=600.0), 0.12, 0.04)
        # 极淡的夜鸦紫银空气谐振（不喧宾夺主）
        shimmer = D.modal_bank(
            wing_a[:int(0.02 * D.SR)], dur,
            freqs=[1980.0 * (1 + 0.03 * idx), 2970.0, 4450.0],
            amps=[0.5, 0.35, 0.2], taus=[0.08, 0.06, 0.045], seed=220 + idx
        )
        st = D.mix_layers(
            dur,
            (wing_a, 0.0, 0.0),
            (cloth, 0.004, -3.5),
            (wing_b, 0.055, -5.5),
            (shimmer, 0.005, -14.5),
        )
        st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.55, er_mix=0.15, seed=230 + idx), dur, 0.07)
        return D.master_finalize(st, target_rms50_db=-18.0)


def build_land(idx: int, heavy: bool = False) -> np.ndarray:
    if not heavy:
        dur = 0.20
        boot = D.slice_192k(f"kenney-impact-sounds/x/Audio/footstep_concrete_00{(idx + 2) % 5}.ogg", 0.0, 0.16, speed=0.90 + 0.04 * idx, hp_hz=65.0)
        boot = D.transient_shaper(boot, attack_db=6.0, sustain_db=-4.0)
        sp = D.slice_192k(f"oga-40-cc0-water-splash/x/splash_0{(idx % 5) + 2}.ogg", 0.0, 0.22, speed=1.22, hp_hz=1800.0)
        leather = D.slice_192k(f"kenney-rpg-audio/x/Audio/beltHandle{(idx % 2) + 1}.ogg", 0.0, 0.18, speed=1.15, hp_hz=350.0)
        sub = D.sub_drop(0.11, f_start=110, f_end=48, tau_pitch=0.028, tau_amp=0.05, drive=1.45)
        st = D.mix_layers(
            dur,
            (boot, 0.0, 0.0),
            (sub, 0.0, -4.5),
            (sp, 0.006, -9.5),
            (leather, 0.015, -13.5),
        )
        st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.35, er_mix=0.13, seed=250 + idx), dur, 0.055)
        return D.master_finalize(st, target_rms50_db=-18.5)
    else:
        dur = 0.44
        thud = D.slice_192k("qubodup-impact/x/qubodupImpact/qubodupImpactMeat01.flac", 0.0, 0.32, speed=0.82 + 0.05 * idx, hp_hz=40.0)
        thud = D.lp(D.transient_shaper(thud, attack_db=5.5, sustain_db=-3.0), 3200.0)
        boot = D.slice_192k(f"kenney-impact-sounds/x/Audio/footstep_concrete_00{idx % 5}.ogg", 0.0, 0.18, speed=0.78, hp_hz=55.0)
        sp = D.slice_192k(f"oga-40-cc0-water-splash/x/splash_0{(idx % 4) + 1}.ogg", 0.0, 0.38, speed=0.98, hp_hz=900.0)
        armor = D.slice_192k(f"kenney-rpg-audio/x/Audio/beltHandle{(idx % 2) + 1}.ogg", 0.0, 0.25, speed=0.92, hp_hz=300.0)
        sub = D.sub_drop(0.28, f_start=92, f_end=36, tau_pitch=0.045, tau_amp=0.11, drive=1.85)
        st = D.mix_layers(
            dur,
            (thud, 0.0, -1.5),
            (boot, 0.0, -2.5),
            (sub, 0.0, -1.0),
            (sp, 0.008, -6.5),
            (armor, 0.018, -10.5),
        )
        st = D.bus_compress(st, threshold_db=-10.0, ratio=3.0)
        st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.52, er_mix=0.18, er_decay_s=0.08, seed=270 + idx), dur, 0.09)
        return D.master_finalize(st, target_rms50_db=-14.0)


# ===========================================================================
# 2. 主角全系冷钢凌冽刀锋与拔收刀姿态（192kHz 快速拔刀寒芒主角 + 高音刀鸣丝 + >1kHz 破风嘶声）
# ===========================================================================

def _craft_blade_whoosh(
    razor_spec: tuple[str, float, float],
    razor_sub_spec: tuple[str, float, float],
    air_spec: tuple[str, float, float],
    dur: float,
    speed_razor: float,
    speed_air: float,
    ring_f0: float,
    ring_tau: float,
    ring_db: float,
    air_db: float,
    target_rms_db: float,
    hp_razor_hz: float = 1750.0,
    hp_air_hz: float = 1050.0,
    pan_sweep: tuple[float, float] | None = None,
    seed: int = 300,
) -> np.ndarray:
    """商业 3A 冷钢凌冽挥刀构建器（对标 katana schwing / 大招 ult_cut_0 频谱：>2kHz 占 86%~95%，<300Hz < 3%）：
    1) 主角层 (0 dB)：192kHz 真实金属高速拔刀刮擦“锵 / シャキン！”（高通 >1.7kHz，峰值精准锁死 0.050s）
    2) 双刃寒芒副层 (-4.2 dB)：异质冷钢副刮擦微偏声像，塑造立体真刀宽度（零梳状滤波）
    3) 高音冷钢刀鸣丝 (ring_db)：提取真实 192kHz 刀身泛音比并锁定在 3.3k~5.1kHz + 6k~12kHz 极高音寒芒
    4) 超音速破风刃嘶 (air_db)：高通 >950~1200Hz 滤除一切木棍“呼呼”闷风，只留锋刃切裂空气的“嘶/唰！”
    """
    post_len = max(0.15, dur - 0.050)
    sh_main = D.slice_razor_shing_192k(
        razor_spec[0], razor_spec[1], razor_spec[2],
        speed=speed_razor, pre_s=0.050, post_s=post_len, attack_s=0.038, hp_hz=hp_razor_hz,
    )
    sh_main = D.tilt_eq(sh_main, low_shelf_db=-3.0, presence_db=2.8, air_db=4.2)

    sh_sub = D.slice_razor_shing_192k(
        razor_sub_spec[0], razor_sub_spec[1], razor_sub_spec[2],
        speed=speed_razor * 1.07, pre_s=0.051, post_s=post_len * 0.82, attack_s=0.034, hp_hz=hp_razor_hz + 350.0,
    )
    # 左右微偏置营造纯粹双声道刀锋宽度，绝不用 Haas 延迟混合
    sh_l = D.stereo_widen(sh_main, pan=-0.10, er_mix=0.0)
    sh_r = D.stereo_widen(sh_sub, pan=0.14, er_mix=0.0)

    # 高通破风刃嘶（严格滤除 <900Hz 钝木棍风声，峰值对齐 0.050s）
    air = D.slice_192k(air_spec[0], air_spec[1], air_spec[2], speed=speed_air, hp_hz=hp_air_hz, trim_onset=False)
    air = D.hp(air, hp_air_hz, order=2)
    air = D.align_peak_to(air, target_peak_s=0.050)
    air = D.crop_or_pad(air, dur, fade_out_s=min(0.09, dur * 0.35))

    # 真实刀身泛音驱动的高音冷钢寒芒弦（克制衬底，让 192kHz 真实高速钢刃刮擦占绝对主导，自然凌冽不发假）
    parts = D.blade_partials_192k(razor_spec[0], razor_spec[1], razor_spec[2], count=5, lo=2000.0, hi=10800.0)
    ring = D.cold_steel_ring(
        parts, f_primary=ring_f0, dur_s=max(0.12, dur - 0.042), tau=ring_tau,
        bloom_s=0.010, side_gain=0.52, crystalline_boost=0.68, seed=seed + 17,
    )

    st = D.mix_layers(
        dur,
        (sh_l, 0.0, 0.0),
        (sh_r, 0.0, -3.8),
        (air, 0.0, air_db),
        (ring, 0.044, ring_db),
    )
    st = D.crop_or_pad(st, dur, fade_out_s=min(0.085, dur * 0.32))
    if pan_sweep is not None:
        st = D.dynamic_pan_sweep(st, pan_sweep[0], pan_sweep[1])
    st = D.stereo_widen(st, er_mix=0.07, er_decay_s=0.055, seed=seed)
    return D.master_finalize(st, target_rms50_db=target_rms_db, hp_cut_hz=260.0)


def build_swing_l1(idx: int) -> np.ndarray:
    """普攻一段·疾切寒芒：高音军刀/短刃冷钢急掠（重心 ~6.2kHz，干脆凌冽）。"""
    return _craft_blade_whoosh(
        SABRE_RAZOR_DRAWS[idx % len(SABRE_RAZOR_DRAWS)],
        DAGGER_RAZOR_DRAWS[idx % len(DAGGER_RAZOR_DRAWS)],
        KATANA_SWINGS[idx % len(KATANA_SWINGS)],
        dur=0.28, speed_razor=1.20 + 0.04 * idx, speed_air=1.38 + 0.04 * idx,
        ring_f0=4480.0 + 140.0 * idx, ring_tau=0.070, ring_db=-7.8, air_db=-6.0,
        target_rms_db=-13.2, hp_razor_hz=1850.0, hp_air_hz=1150.0,
        pan_sweep=(-0.22, 0.24), seed=310 + idx,
    )


def build_swing_l2(idx: int) -> np.ndarray:
    """普攻二段·斜撩寒弧：更宽阔的日本刀+军刀双锋切裂（真实钢口寒光刺骨）。"""
    return _craft_blade_whoosh(
        SABRE_RAZOR_DRAWS[(idx + 2) % len(SABRE_RAZOR_DRAWS)],
        KATANA_DRAWS[idx % len(KATANA_DRAWS)],
        SABRE_SWINGS[idx % len(SABRE_SWINGS)],
        dur=0.33, speed_razor=1.12 + 0.03 * idx, speed_air=1.28 + 0.03 * idx,
        ring_f0=4120.0 + 120.0 * idx, ring_tau=0.092, ring_db=-7.4, air_db=-5.5,
        target_rms_db=-12.2, hp_razor_hz=1760.0, hp_air_hz=1050.0,
        pan_sweep=(0.25, -0.25), seed=320 + idx,
    )


def build_swing_l3(idx: int) -> np.ndarray:
    """普攻三段·重劈裂空：饱满冷钢长弧刮擦 + 悠扬高音名刀铮鸣（纯正金属凌冽，绝无闷雷木棍风）。"""
    return _craft_blade_whoosh(
        SABRE_RAZOR_DRAWS[(idx + 4) % len(SABRE_RAZOR_DRAWS)],
        KATANA_DRAWS[(idx + 2) % len(KATANA_DRAWS)],
        HEAVY_SWINGS[idx % len(HEAVY_SWINGS)],
        dur=0.46, speed_razor=1.02 + 0.03 * idx, speed_air=1.18 + 0.03 * idx,
        ring_f0=3920.0 + 120.0 * idx, ring_tau=0.150, ring_db=-6.8, air_db=-5.2,
        target_rms_db=-10.8, hp_razor_hz=1650.0, hp_air_hz=940.0,
        pan_sweep=(-0.32, 0.35), seed=330 + idx,
    )


def build_swing_up(idx: int, air: bool = False) -> np.ndarray:
    """上挑 / 空中挑升斩：由低向高急速扬起的锐利刀尖寒芒！"""
    base = _craft_blade_whoosh(
        DAGGER_RAZOR_DRAWS[idx % len(DAGGER_RAZOR_DRAWS)] if air else SABRE_RAZOR_DRAWS[(idx + 1) % len(SABRE_RAZOR_DRAWS)],
        KATANA_DRAWS[(idx + 1) % len(KATANA_DRAWS)],
        SABRE_SWINGS[(idx + 1) % len(SABRE_SWINGS)],
        dur=0.32 if air else 0.35,
        speed_razor=(1.22 if air else 1.14) + 0.04 * idx,
        speed_air=(1.40 if air else 1.28) + 0.04 * idx,
        ring_f0=(4620.0 if air else 4180.0) + 120.0 * idx,
        ring_tau=0.086 if air else 0.108,
        ring_db=-7.2, air_db=-5.8,
        target_rms_db=-12.4 if air else -11.6,
        hp_razor_hz=1820.0, hp_air_hz=1100.0,
        seed=340 + idx + (10 if air else 0),
    )
    return base


def build_swing_air(stage: int, idx: int) -> np.ndarray:
    if stage == 1:
        return _craft_blade_whoosh(
            DAGGER_RAZOR_DRAWS[idx % len(DAGGER_RAZOR_DRAWS)],
            SABRE_RAZOR_DRAWS[idx % len(SABRE_RAZOR_DRAWS)],
            DAGGER_SWINGS[idx % len(DAGGER_SWINGS)],
            dur=0.25, speed_razor=1.25 + 0.04 * idx, speed_air=1.42,
            ring_f0=4880.0 + 130.0 * idx, ring_tau=0.062, ring_db=-7.8, air_db=-6.2,
            target_rms_db=-13.5, hp_razor_hz=1950.0, hp_air_hz=1250.0, seed=360 + idx,
        )
    elif stage == 2:
        return _craft_blade_whoosh(
            SABRE_RAZOR_DRAWS[(idx + 3) % len(SABRE_RAZOR_DRAWS)],
            DAGGER_RAZOR_DRAWS[(idx + 1) % len(DAGGER_RAZOR_DRAWS)],
            KATANA_SWINGS[(idx + 2) % len(KATANA_SWINGS)],
            dur=0.29, speed_razor=1.15 + 0.04 * idx, speed_air=1.32,
            ring_f0=4280.0 + 120.0 * idx, ring_tau=0.084, ring_db=-7.4, air_db=-5.8,
            target_rms_db=-12.4, hp_razor_hz=1820.0, hp_air_hz=1120.0, seed=370 + idx,
        )
    else:
        return _craft_blade_whoosh(
            SABRE_RAZOR_DRAWS[(idx + 4) % len(SABRE_RAZOR_DRAWS)],
            KATANA_DRAWS[(idx + 4) % len(KATANA_DRAWS)],
            HEAVY_SWINGS[(idx + 1) % len(HEAVY_SWINGS)],
            dur=0.42, speed_razor=1.05 + 0.03 * idx, speed_air=1.22,
            ring_f0=4020.0 + 110.0 * idx, ring_tau=0.142, ring_db=-6.8, air_db=-5.4,
            target_rms_db=-11.0, hp_razor_hz=1680.0, hp_air_hz=960.0, seed=380 + idx,
        )


def build_swing_charge(idx: int) -> np.ndarray:
    """满蓄力一刀断昼斩：极致璀璨的双重名刀拔斩寒芒 + 长余韵高音刀吟（对标大招 ult_cut 质感）！"""
    return _craft_blade_whoosh(
        SABRE_RAZOR_DRAWS[(idx + 4) % len(SABRE_RAZOR_DRAWS)],
        KATANA_DRAWS[(idx + 2) % len(KATANA_DRAWS)],
        HEAVY_SWINGS[idx % len(HEAVY_SWINGS)],
        dur=0.52, speed_razor=1.00 + 0.03 * idx, speed_air=1.15 + 0.03 * idx,
        ring_f0=3880.0 + 140.0 * idx, ring_tau=0.210, ring_db=-6.2, air_db=-5.2,
        target_rms_db=-10.2, hp_razor_hz=1620.0, hp_air_hz=900.0,
        pan_sweep=(-0.38, 0.38), seed=390 + idx,
    )


def build_swing_dash(idx: int, left: bool = False) -> np.ndarray:
    """残影冲刺斩：高速剃刀一闪横贯左右声场 + 凛冽冷钢残响丝！"""
    pan = (0.56, -0.56) if left else (-0.56, 0.56)
    return _craft_blade_whoosh(
        DAGGER_RAZOR_DRAWS[(idx + 1) % len(DAGGER_RAZOR_DRAWS)],
        SABRE_RAZOR_DRAWS[(idx + 2) % len(SABRE_RAZOR_DRAWS)],
        SABRE_SWINGS[(idx + 3) % len(SABRE_SWINGS)],
        dur=0.44, speed_razor=1.14 + 0.04 * idx, speed_air=1.32 + 0.04 * idx,
        ring_f0=4220.0 + 150.0 * idx, ring_tau=0.170, ring_db=-6.4, air_db=-5.5,
        target_rms_db=-10.8, hp_razor_hz=1750.0, hp_air_hz=1020.0,
        pan_sweep=pan, seed=400 + idx + (20 if left else 0),
    )


def build_dash_step(idx: int) -> np.ndarray:
    """纯残影瞬步追击（不出刀时的暗影折跃）：利落风衣掠动 + 短促破空。"""
    dur = 0.26
    air = D.slice_192k(DAGGER_SWINGS[idx % 3][0], DAGGER_SWINGS[idx % 3][1], DAGGER_SWINGS[idx % 3][2], speed=1.35, hp_hz=380.0)
    cloth = D.slice_192k(f"kenney-rpg-audio/x/Audio/cloth{(idx % 3) + 1}.ogg", 0.0, 0.20, speed=1.32, hp_hz=360.0)
    sub = D.sub_drop(0.085, f_start=118, f_end=50, tau_pitch=0.022, tau_amp=0.038, drive=1.35)
    st = D.mix_layers(dur, (air, 0.0, 0.0), (cloth, 0.004, -3.5), (sub, 0.0, -6.5))
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.08, seed=435 + idx), dur, 0.07)
    return D.master_finalize(st, target_rms50_db=-15.5)


def build_draw() -> np.ndarray:
    """待机拔刀姿态：192kHz 刀脊滑出鞘口 + 0.26s 刀尖离鞘一瞬的高音清冽寒芒！"""
    dur = 0.92
    slide = D.slice_192k(SN_TEX + "Katana Draw Slow.wav", 5.32, 6.25, speed=1.06, hp_hz=650.0, trim_onset=True)
    snap = D.slice_razor_shing_192k(
        SABRE_RAZOR_DRAWS[0][0], SABRE_RAZOR_DRAWS[0][1], SABRE_RAZOR_DRAWS[0][2],
        speed=1.08, pre_s=0.040, post_s=0.38, attack_s=0.032, hp_hz=1650.0,
    )
    cloth = D.slice_192k("kenney-rpg-audio/x/Audio/clothBelt.ogg", 0.0, 0.22, speed=1.08, hp_hz=320.0)
    parts = D.blade_partials_192k(SABRE_RAZOR_DRAWS[0][0], SABRE_RAZOR_DRAWS[0][1], SABRE_RAZOR_DRAWS[0][2], count=5, lo=2000.0, hi=10500.0)
    ring = D.cold_steel_ring(parts, f_primary=3860.0, dur_s=0.62, tau=0.22, bloom_s=0.015, crystalline_boost=0.60, seed=450)
    st = D.mix_layers(dur, (cloth, 0.0, -11.0), (slide, 0.03, -4.5), (snap, 0.22, 0.0), (ring, 0.26, -5.8))
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.10, er_decay_s=0.08, seed=451), dur, 0.18)
    return D.master_finalize(st, target_rms50_db=-16.0, hp_cut_hz=220.0)


def build_sheathe() -> np.ndarray:
    """战斗结束归鞘姿态：清脆钢刃入鞘滑擦 + 0.56s 处鲤口严丝合缝清脆“咔哒”锁死！"""
    dur = 0.95
    slide = D.slice_192k(SN_TEX + "Katana Sheath Slow.wav", 5.40, 5.95, speed=1.05, hp_hz=520.0, trim_onset=True)
    metal_glide = D.slice_192k(SABRE_RAZOR_DRAWS[1][0], SABRE_RAZOR_DRAWS[1][1], SABRE_RAZOR_DRAWS[1][2], speed=1.18, hp_hz=2200.0, trim_onset=True)
    metal_glide = D.crop_or_pad(metal_glide, 0.34, 0.14)
    lock_click = D.slice_192k(SN_TEX + "Katana Sheath Fast.wav", 2.58, 2.72, speed=0.98, hp_hz=220.0, trim_onset=True)
    lock_click = D.transient_shaper(lock_click, attack_db=7.5, sustain_db=-4.0)
    hilt_thud = D.slice_192k(HILT_CLASHES[0][0], HILT_CLASHES[0][1], HILT_CLASHES[0][1] + 0.14, speed=0.96, hp_hz=110.0)
    hilt_thud = D.lp(D.crop_or_pad(hilt_thud, 0.12, 0.05), 2200.0)
    cloth = D.slice_192k("kenney-rpg-audio/x/Audio/cloth2.ogg", 0.0, 0.22, speed=1.02, hp_hz=260.0)
    st = D.mix_layers(
        dur,
        (cloth, 0.02, -11.0),
        (slide, 0.07, -4.5),
        (metal_glide, 0.08, -7.5),
        (lock_click, 0.56, 0.0),
        (hilt_thud, 0.562, -4.5),
    )
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.09, er_decay_s=0.07, seed=460), dur, 0.15)
    return D.master_finalize(st, target_rms50_db=-15.5)


# ===========================================================================
# 3. 命中与受击（刀锋切入瞬态 + 紧致冲击核，严格守死 test_audio.gd 干脆时长门禁！）
# ===========================================================================

def build_hit(tier: str, idx: int) -> np.ndarray:
    """剑刃斩入肉身/暗影（严守「挥刀声为主、击中声其次」与「砍无甲肉身绝无刀砍铁锵声」原则）：
    采用 Bloody Blade 利刃切入瞬态 + 高速破空切口丝（无刀撞金属敲击音，无科幻合成杂音！）+ 紧致受击冲击核！
    """
    bb = D.slice_192k("freesound-323525/323525__kreastricon62__bloody-blade.wav", 0.098, 0.46, speed=1.00 + 0.04 * idx, hp_hz=95.0)
    bb = D.transient_shaper(bb, attack_db=6.5, sustain_db=-4.5)
    bb = bb - 0.40 * D.bp(bb, 230.0, 560.0)  # 彻底挖除中低频闷泥感，保留纯粹利刃切肉瞬态
    bb = D.tilt_eq(bb, presence_db=3.2, air_db=2.8)

    # 高速气流切裂声（非金铁敲击音），增强刀锋划开的“嚓！”利落度
    air_cut = D.slice_192k(DAGGER_SWINGS[idx % 3][0], DAGGER_SWINGS[idx % 3][1], DAGGER_SWINGS[idx % 3][2], speed=1.45 + 0.05 * idx, hp_hz=1800.0)
    air_cut = D.crop_or_pad(air_cut, 0.068, 0.035)

    meat_f = f"qubodup-impact/x/qubodupImpact/qubodupImpactMeat0{(idx % 2) + 1}.flac"
    body = D.slice_192k(meat_f, 0.0, 0.22, speed=1.10 + 0.05 * idx, hp_hz=60.0)
    body = D.lp(D.transient_shaper(body, attack_db=6.5, sustain_db=-7.0), 2000.0)

    if tier == "light":
        dur = 0.21  # < 0.26s 门禁
        sub = D.sub_drop(0.085, f_start=118, f_end=50, tau_pitch=0.020, tau_amp=0.038, drive=1.4)
        st = D.mix_layers(dur, (bb, 0.0, 0.0), (air_cut, 0.0, -5.5), (body, 0.002, -4.8), (sub, 0.0, -6.0))
        st = D.bus_compress(st, threshold_db=-10.5, ratio=2.6, attack_s=0.0035)
        st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.06, seed=500 + idx), dur, 0.05)
        return D.master_finalize(st, target_rms50_db=-16.2)

    elif tier == "heavy":
        dur = 0.34  # < 0.42s 门禁
        sub = D.sub_drop(0.145, f_start=98, f_end=42, tau_pitch=0.028, tau_amp=0.065, drive=1.6)
        sabre_cut = D.slice_192k(SABRE_SWINGS[idx % len(SABRE_SWINGS)][0], SABRE_SWINGS[idx % len(SABRE_SWINGS)][1], SABRE_SWINGS[idx % len(SABRE_SWINGS)][2], speed=1.22, hp_hz=650.0)
        sabre_cut = D.crop_or_pad(sabre_cut, 0.16, 0.065)
        st = D.mix_layers(
            dur,
            (bb, 0.0, 0.0),
            (air_cut, 0.0, -4.5),
            (sabre_cut, 0.0, -5.5),
            (body, 0.001, -2.8),
            (sub, 0.0, -3.2),
        )
        st = D.bus_compress(st, threshold_db=-11.0, ratio=3.0, attack_s=0.0035)
        st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.08, seed=510 + idx), dur, 0.075)
        return D.master_finalize(st, target_rms50_db=-14.6)

    else:  # finisher
        dur = 0.50  # < 0.60s 门禁
        sub = D.sub_drop(0.24, f_start=88, f_end=36, tau_pitch=0.038, tau_amp=0.098, drive=1.85)
        heavy_cut = D.slice_192k(HEAVY_SWINGS[idx % len(HEAVY_SWINGS)][0], HEAVY_SWINGS[idx % len(HEAVY_SWINGS)][1], HEAVY_SWINGS[idx % len(HEAVY_SWINGS)][2], speed=1.08, hp_hz=550.0)
        st = D.mix_layers(
            dur,
            (bb, 0.0, 0.0),
            (air_cut, 0.0, -3.8),
            (body, 0.0, -1.8),
            (heavy_cut, 0.003, -4.5),
            (sub, 0.0, -1.5),
        )
        st = D.bus_compress(st, threshold_db=-11.5, ratio=3.2, attack_s=0.004)
        st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.10, er_decay_s=0.065, seed=520 + idx), dur, 0.10)
        return D.master_finalize(st, target_rms50_db=-12.8)


def build_hurt(heavy: bool, idx: int) -> np.ndarray:
    """主角受击：冷峻利落的护甲/衣料受创 + 低频心跳骤沉（与进攻命中音色拉开区分，一听便知自己挨打）。"""
    dur = 0.36 if heavy else 0.25  # 门禁 0.42s / 0.30s
    bb = D.slice_192k("freesound-323525/323525__kreastricon62__bloody-blade.wav", 0.10, 0.40, speed=0.84 if heavy else 0.92, hp_hz=60.0)
    bb = D.lp(bb, 5200.0)  # 压暗高频，让玩家受击偏沉闷内敛，区别于玩家砍怪的明亮锋利！
    cloth = D.slice_192k(f"kenney-rpg-audio/x/Audio/clothBelt{'' if idx % 2 == 0 else '2'}.ogg", 0.0, 0.25, speed=0.95, hp_hz=200.0)
    meat = D.slice_192k("qubodup-impact/x/qubodupImpact/qubodupImpactMeat02.flac", 0.0, 0.24, speed=0.88, hp_hz=45.0)
    sub = D.sub_drop(0.22 if heavy else 0.13, f_start=95 if heavy else 108, f_end=35, tau_pitch=0.038, tau_amp=0.09 if heavy else 0.055, drive=1.8)
    st = D.mix_layers(dur, (bb, 0.0, -1.5), (meat, 0.0, 0.0), (cloth, 0.005, -4.5), (sub, 0.0, 0.0 if heavy else -2.5))
    st = D.bus_compress(st, threshold_db=-11.0, ratio=3.2, attack_s=0.003)
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.08, seed=540 + idx), dur, 0.07)
    return D.master_finalize(st, target_rms50_db=-12.8 if heavy else -14.5)


# ===========================================================================
# 4. 王牌核心：最高音调冷钢精准弹刀、满势大弹刀、格挡、白壳弹反、破晓碎壳
# ===========================================================================

def build_parry(idx: int, heavy_tier: bool = False) -> np.ndarray:
    """《只狼 / 星刃》级最高音调冷钢弹刀混合合成（对标 Sekiro_Parry / HeavyParry 频谱：>2kHz 占 85%~92%，最高泛音直达 8k~12kHz！）：
    1) 192kHz 单次纯净刃对刃交击（在 0.138s 二次杂响前截断！speed >= 1.03 保住最高音调“叮/锵！”钢口脆度 + 前 14ms >3kHz 钻石瞬态提亮）
    2) 192kHz 高速军刀钢口擦火丝（>4.2kHz，赋予刀锋相撞一瞬迸射火星的锐度）
    3) 直驱相位纯净高音冷钢长鸣簇（主频锁定 3.6kHz~4.1kHz 最高冷钢区 + 5.6k/8.4k/11.5kHz 极高频晶莹泛音 + 2.4kHz 刀脊支撑）
    4) 280 模态丝滑高频金属余响床 (2.4k~16.2kHz) + >4.5kHz 火石散射尾迹
    5) 严控 800~2000Hz 铁锅中频 (<3.5%)，配紧致胸腔微震（5.8ms 慢起音压缩，绝不压扁第一下最高音调钢口瞬态！）
    """
    dur = 2.00
    c1 = CLEAN_HIGH_CLASHES[idx % len(CLEAN_HIGH_CLASHES)]
    c2 = CLEAN_HIGH_CLASHES[(idx + 2) % len(CLEAN_HIGH_CLASHES)]

    # 绝不降调变闷！保持 1.03x ~ 1.15x 高刚度碳钢清脆咬合
    sp_l = (1.03 if heavy_tier else 1.06) + 0.035 * idx
    sp_r = sp_l * 1.055
    bite_l = D.slice_clean_clash_192k(c1[0], c1[1], cut_s=c1[2], speed=sp_l, hp_hz=480.0, click_boost=0.72)
    bite_r = D.slice_clean_clash_192k(c2[0], c2[1], cut_s=c2[2], speed=sp_r, hp_hz=540.0, click_boost=0.68)

    # 零延迟纯净双真刀立体声咬合（杜绝 Haas 梳状滤波！）
    n_b = max(len(bite_l), len(bite_r))
    bl_pad = np.pad(bite_l, (0, n_b - len(bite_l)))
    br_pad = np.pad(bite_r, (0, n_b - len(bite_r)))
    bite_st = np.vstack([
        0.88 * bl_pad + 0.28 * br_pad,
        0.88 * br_pad + 0.28 * bl_pad,
    ])
    bite_st = D.tilt_eq(bite_st, low_shelf_db=-2.0, presence_db=3.2, air_db=5.0)

    # 刀锋擦出白炽火星的 >4.2kHz 极高频钢丝刮擦（前 95~135ms）
    rz = SABRE_RAZOR_DRAWS[idx % len(SABRE_RAZOR_DRAWS)]
    spark_scrape = D.slice_razor_shing_192k(
        rz[0], rz[1], rz[2],
        speed=1.24 + 0.04 * idx, pre_s=0.005, post_s=0.135 if heavy_tier else 0.095,
        attack_s=0.004, hp_hz=4200.0,
    )

    # 提取 192kHz 刀身真实高频泛音比，直驱最高音调冷钢长鸣（3.8k~4.4kHz 极高冷钢主峰 + 5.8k/8.6k/11.8kHz 晶莹泛音！）
    parts = D.blade_partials_192k(c1[0], c1[1], c1[1] + 0.42, count=6, lo=2200.0, hi=11500.0)
    f_hi = ([3840.0, 4120.0][idx % 2] if heavy_tier else [3780.0, 4050.0, 4340.0][idx % 3])
    sing_hi = D.cold_steel_ring(
        parts,
        f_primary=f_hi,
        dur_s=dur,
        tau=0.43 if heavy_tier else 0.35,
        bloom_s=0.020,
        side_gain=0.56,
        spine_low_ratio=0.38 if heavy_tier else 0.32,
        crystalline_boost=0.95 if heavy_tier else 0.88,
        detune_cents=2.4,
        seed=600 + idx + (30 if heavy_tier else 0),
    )

    # 280 模态丝滑高音金属共振床 (>2.8kHz) + >4.6kHz 真实碰撞火星散射
    shimmer_bed = D.dense_metallic_shimmer(
        bite_l, dur, tau_base=0.40 if heavy_tier else 0.32,
        lo=2850.0, hi=16800.0, modes=280, seed=610 + idx,
    )
    sparks_tail = D.bright_sparks(
        bite_l, dur, hp_hz=4600.0, t60=0.54 if heavy_tier else 0.44, seed=630 + idx,
    )

    # 极短促克制的 320~760Hz 锻钢实心底托（避开 800~2000Hz 铁锅频段！）+ 对标《只狼》2%~3% 紧致胸腔脉冲
    metal_thud = D.slice_192k(
        f"blacklodge-metal/dull_metal_collision_1{(idx % 2) + 1}_44k_32bit_stereo.wav",
        0.0, 0.16, speed=1.05, hp_hz=180.0,
    )
    body_tight = D.bp(D.crop_or_pad(metal_thud, 0.075, 0.045), 320.0, 760.0)
    sub = D.sub_drop(
        0.24 if heavy_tier else 0.16,
        f_start=82.0 if heavy_tier else 88.0,
        f_end=42.0,
        tau_pitch=0.036,
        tau_amp=0.110 if heavy_tier else 0.075,
        drive=1.65,
    )

    layers: list[tuple[np.ndarray, float, float]] = [
        (bite_st, 0.0, 0.0),
        (spark_scrape, 0.0, -3.0 if heavy_tier else -3.6),
        (sing_hi, 0.002, -4.4 if heavy_tier else -5.0),
        (shimmer_bed, 0.003, -5.6 if heavy_tier else -6.4),
        (sparks_tail, 0.002, -4.8 if heavy_tier else -5.5),
        (body_tight, 0.001, -13.5 if heavy_tier else -15.0),
        (sub, 0.0, -3.8 if heavy_tier else -5.5),
    ]

    st = D.mix_layers(dur, *layers)
    # 5.8ms 慢起音联动压缩：100% 放过前 6ms 最高音调“叮/锵！”钢口尖峰，同时把后段长鸣托得清澈饱满！
    st = D.bus_compress(st, threshold_db=-12.5, ratio=3.0, attack_s=0.0058, release_s=0.085)
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.10, er_decay_s=0.09, seed=620 + idx), dur, 0.30)
    return D.master_finalize(st, target_rms50_db=-8.8 if heavy_tier else -9.2, ceiling_db=-0.8)


def build_block(idx: int) -> np.ndarray:
    """普通按住格挡：沉稳清脆的刀镡/刀背硬架卸力“铛！”，0.36s 内干净收住，与精准弹刀高音长鸣一眼分明！"""
    dur = 0.36
    hc = HILT_CLASHES[idx % len(HILT_CLASHES)]
    c1 = CLEAN_HIGH_CLASHES[(idx + 3) % len(CLEAN_HIGH_CLASHES)]
    hilt = D.slice_192k(hc[0], hc[1], hc[2], speed=1.02 + 0.04 * idx, hp_hz=180.0)
    blade = D.slice_clean_clash_192k(c1[0], c1[1], cut_s=0.12, speed=1.00 + 0.03 * idx, hp_hz=380.0, click_boost=0.35)
    damped_ring = D.cold_steel_ring(
        [(2680.0, 1.0), (4120.0, 0.55)], f_primary=2680.0 + 90.0 * idx,
        dur_s=0.24, tau=0.048, bloom_s=0.008, crystalline_boost=0.25, seed=642 + idx,
    )
    sub = D.sub_drop(0.12, f_start=102, f_end=48, tau_pitch=0.025, tau_amp=0.048, drive=1.5)
    st = D.mix_layers(dur, (hilt, 0.0, 0.0), (blade, 0.0, -1.5), (damped_ring, 0.004, -7.5), (sub, 0.0, -6.5))
    st = D.bus_compress(st, threshold_db=-11.0, ratio=2.8, attack_s=0.004)
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.07, seed=640 + idx), dur, 0.085)
    return D.master_finalize(st, target_rms50_db=-12.8)


def build_deflect(idx: int) -> np.ndarray:
    """砍在敌人白金凝壳弹开 / 一刀斩飞箭矢炸弹：极高音调白瓷冷钢清脆弹跳偏折音（4.2kHz~12.8kHz 晶莹脆响）！"""
    dur = 0.40
    c1 = CLEAN_HIGH_CLASHES[(idx + 4) % len(CLEAN_HIGH_CLASHES)]
    clang = D.slice_clean_clash_192k(c1[0], c1[1], cut_s=0.125, speed=1.22 + 0.05 * idx, hp_hz=550.0, click_boost=0.75)
    porcelain = D.cold_steel_ring(
        [(4250.0, 1.0), (6480.0, 0.72), (9350.0, 0.48)],
        f_primary=4250.0 + 160.0 * idx,
        dur_s=dur, tau=0.095, bloom_s=0.008, crystalline_boost=0.70, seed=650 + idx,
    )
    ricochet = D.slice_192k(SN_TEX + "Scythian Recurve Arrow Passby.wav", 3.45, 3.76, speed=1.42, hp_hz=1400.0)
    st = D.mix_layers(dur, (clang, 0.0, 0.0), (porcelain, 0.002, -3.5), (ricochet, 0.022, -6.8))
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.08, seed=655 + idx), dur, 0.09)
    return D.master_finalize(st, target_rms50_db=-11.8, hp_cut_hz=280.0)


def build_stun_shell_break(idx: int) -> np.ndarray:
    """白金凝壳崩碎（「破晓」！0.15s 慢放高潮）/ 霸体炸破：
    前 3ms 极高音白瓷冷钢炸裂 + 冰晶飞散碎片 + 胸口紧致一锤 Sub-Drop，0.56s 干净收束（守住 <0.62s 门禁）！
    """
    dur = 0.56
    c1 = CLEAN_HIGH_CLASHES[(idx + 1) % len(CLEAN_HIGH_CLASHES)]
    crack = D.slice_clean_clash_192k(c1[0], c1[1], cut_s=0.135, speed=1.26, hp_hz=520.0, click_boost=0.85)
    razor_burst = D.slice_razor_shing_192k(
        DAGGER_RAZOR_DRAWS[idx % len(DAGGER_RAZOR_DRAWS)][0],
        DAGGER_RAZOR_DRAWS[idx % len(DAGGER_RAZOR_DRAWS)][1],
        DAGGER_RAZOR_DRAWS[idx % len(DAGGER_RAZOR_DRAWS)][2],
        speed=1.32, pre_s=0.006, post_s=0.18, attack_s=0.005, hp_hz=2600.0,
    )
    heavy_metal = D.slice_192k("qubodup-impact/x/qubodupImpact/qubodupImpactMetal.flac", 0.0, 0.36, speed=1.02 + 0.05 * idx, hp_hz=95.0)

    # 飞散的高频白瓷晶体碎片簇 (3.6kHz - 13.5kHz)
    rng = np.random.default_rng(670 + idx)
    shards = np.zeros((2, int(dur * D.SR)))
    for _ in range(26):
        t_on = int(rng.uniform(0.010, 0.32) * D.SR)
        sl = min(shards.shape[1] - t_on, int(rng.uniform(0.012, 0.042) * D.SR))
        if sl < 32:
            continue
        gt = np.arange(sl) / D.SR
        f_a = rng.uniform(3600.0, 12800.0)
        f_b = min(18000.0, f_a * rng.uniform(1.42, 1.76))
        ping = (np.sin(2 * np.pi * f_a * gt) + 0.55 * np.sin(2 * np.pi * f_b * gt)) * np.exp(-gt / 0.013)
        ping *= rng.uniform(0.18, 0.58) * np.exp(-t_on / (0.20 * D.SR))
        pan = rng.uniform(0.12, 0.88)
        shards[0, t_on:t_on + sl] += ping * np.sqrt(1.0 - pan)
        shards[1, t_on:t_on + sl] += ping * np.sqrt(pan)

    sub = D.sub_drop(0.34, f_start=94, f_end=35, tau_pitch=0.045, tau_amp=0.13, drive=1.95)

    st = D.mix_layers(
        dur,
        (crack, 0.0, 0.0),
        (razor_burst, 0.0, -2.5),
        (heavy_metal, 0.002, -3.5),
        (shards, 0.0, -4.2),
        (sub, 0.0, -0.5),
    )
    st = D.bus_compress(st, threshold_db=-12.0, ratio=3.2, attack_s=0.005)
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.10, er_decay_s=0.08, seed=678 + idx), dur, 0.11)
    return D.master_finalize(st, target_rms50_db=-9.2)


def build_guard_break(idx: int) -> np.ndarray:
    """架势被重击震崩：沉重金属崩脱 + 闷雷下沉。"""
    dur = 0.50
    metal = D.slice_192k("blacklodge-metal/dull_metal_collision_11_44k_32bit_stereo.wav", 0.0, 0.45, speed=0.82 + 0.04 * idx, hp_hz=70.0)
    hilt = D.slice_192k(HILT_CLASHES[idx % len(HILT_CLASHES)][0], HILT_CLASHES[idx % len(HILT_CLASHES)][1], HILT_CLASHES[idx % len(HILT_CLASHES)][1] + 0.35, speed=0.80, hp_hz=120.0)
    sub = D.sub_drop(0.34, f_start=88, f_end=33, tau_pitch=0.05, tau_amp=0.13, drive=2.0)
    st = D.mix_layers(dur, (metal, 0.0, 0.0), (hilt, 0.004, -2.0), (sub, 0.0, 0.0))
    st = D.bus_compress(st, threshold_db=-12.0, ratio=3.6)
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.55, er_mix=0.16, seed=685 + idx), dur, 0.10)
    return D.master_finalize(st, target_rms50_db=-9.8)


def build_impact_accent_light(idx: int) -> np.ndarray:
    """play_slam(<0.45) 专属智能分流：二连击微重音衬底（干净紧致的刀脊微震，彻底消除旧版砸石头闷响！）。"""
    dur = 0.16
    w = D.slice_192k(SEAX_OR_KAT := KATANA_SWINGS[(idx + 2) % 6][0], KATANA_SWINGS[(idx + 2) % 6][1], KATANA_SWINGS[(idx + 2) % 6][2], speed=0.88, hp_hz=90.0)
    w = D.lp(D.crop_or_pad(w, 0.14, 0.06), 3600.0)
    sub = D.sub_drop(0.10, f_start=108, f_end=46, tau_pitch=0.025, tau_amp=0.045, drive=1.45)
    st = D.mix_layers(dur, (w, 0.0, -2.0), (sub, 0.0, 0.0))
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.32, er_mix=0.08, seed=690 + idx), dur, 0.05)
    return D.master_finalize(st, target_rms50_db=-17.5)


def build_slam(idx: int) -> np.ndarray:
    """重砸地面 / 重击轰飞（0.55s < 0.62s 门禁）：厚重物理撞击 + 湿石板震裂水花 + 深沉低频！"""
    dur = 0.55
    meat = D.slice_192k("qubodup-impact/x/qubodupImpact/qubodupImpactMeat01.flac", 0.0, 0.35, speed=0.76 + 0.04 * idx, hp_hz=42.0)
    metal = D.slice_192k("blacklodge-metal/dull_metal_collision_12_44k_32bit_stereo.wav", 0.0, 0.38, speed=0.78, hp_hz=65.0)
    metal = D.lp(metal, 3400.0)
    splash = D.slice_192k(f"oga-40-cc0-water-splash/x/splash_0{(idx % 4) + 1}.ogg", 0.0, 0.42, speed=0.92, hp_hz=650.0)
    axe_air = D.slice_192k(SN_TEX + "Axe Swing.wav", 2.45, 2.68, speed=0.75, hp_hz=120.0)
    sub = D.sub_drop(0.36, f_start=86, f_end=34, tau_pitch=0.048, tau_amp=0.14, drive=2.0)
    st = D.mix_layers(
        dur,
        (meat, 0.0, 0.0),
        (metal, 0.002, -3.5),
        (axe_air, 0.0, -4.5),
        (splash, 0.012, -7.5),
        (sub, 0.0, 0.5),
    )
    st = D.bus_compress(st, threshold_db=-12.0, ratio=3.6)
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.55, er_mix=0.18, er_decay_s=0.085, seed=700 + idx), dur, 0.11)
    return D.master_finalize(st, target_rms50_db=-11.2)


def build_rift_burst(idx: int) -> np.ndarray:
    """play_slam(>1.02) 专属智能分流：紫电空间裂口崩裂 / 锋芒破四段 / 满势远轰！
    8ms 反向吸气瞬态聚能 -> 192kHz 降八度次元重刃撕裂 -> FM 紫电电弧饱和爆裂 -> 深潜 Sub 冲击！
    """
    dur = 0.58
    # 192kHz 刀刃撕裂降半八度（超声波变成凌厉次元裂缝声！）
    clash = BLADE_CLASHES[(idx + 2) % len(BLADE_CLASHES)]
    slash_rip = D.slice_192k(clash[0], clash[1], clash[1] + 0.42, speed=0.68 + 0.03 * idx, hp_hz=200.0)
    slash_rip = D.transient_shaper(slash_rip, attack_db=7.0, sustain_db=-2.5)

    spear_air = D.slice_192k(SN_TEX + "Spear Swing.wav", 0.08, 0.52, speed=0.66, hp_hz=110.0)
    # 12ms 反向预吸气聚能（Reverse Pre-suck）
    pre_suck = slash_rip[:int(0.014 * D.SR)][::-1] * np.linspace(0.0, 0.55, int(0.014 * D.SR))

    rift = D.rift_warp_synth(dur_s=0.52, seed=715 + idx, intensity=1.15)
    sub = D.sub_drop(0.40, f_start=94, f_end=32, tau_pitch=0.052, tau_amp=0.155, drive=2.15)

    st = D.mix_layers(
        dur,
        (pre_suck, 0.0, -5.0),
        (slash_rip, 0.012, 0.0),
        (spear_air, 0.012, -2.5),
        (rift, 0.012, -2.0),
        (sub, 0.012, 0.8),
    )
    st = D.bus_compress(st, threshold_db=-13.0, ratio=4.0)
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.72, er_mix=0.20, er_decay_s=0.095, seed=720 + idx), dur, 0.12)
    return D.master_finalize(st, target_rms50_db=-9.4)


# ===========================================================================
# 5. 挑飞、撞墙、连锁、炸弹、敌人预警与出手、关卡仪式音、蓄力与远射
# ===========================================================================

def build_launch(idx: int) -> np.ndarray:
    """敌人被挑飞升空（<=0.41s < 0.45s 门禁）：由下向上掀开气流的升频破空斩 + 水尘拔起！"""
    dur = 0.40
    sw = D.slice_192k(SABRE_SWINGS[idx % 4][0], SABRE_SWINGS[idx % 4][1], SABRE_SWINGS[idx % 4][2], speed=1.08 + 0.05 * idx, hp_hz=150.0)
    # 赋予向上挑起的升频动势 (0.85x -> 1.35x 变速率重采样)
    n_s = len(sw)
    curve = np.cumsum(np.linspace(0.82, 1.38, n_s))
    curve = curve / curve[-1] * (n_s - 1)
    sw_up = np.interp(curve, np.arange(n_s), sw)

    draw_zing = D.slice_192k(KATANA_DRAWS[idx % 5][0], KATANA_DRAWS[idx % 5][1], KATANA_DRAWS[idx % 5][2], speed=1.25, hp_hz=1600.0)
    splash = D.slice_192k(f"oga-40-cc0-water-splash/x/splash_0{(idx % 3) + 2}.ogg", 0.0, 0.28, speed=1.28, hp_hz=1200.0)
    sub = D.sub_drop(0.16, f_start=72, f_end=118, tau_pitch=0.06, tau_amp=0.075, drive=1.5)  # 向上提气的反向低频包络！

    st = D.mix_layers(dur, (sw_up, 0.0, 0.0), (draw_zing, 0.006, -5.5), (splash, 0.010, -8.5), (sub, 0.0, -3.5))
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.50, er_mix=0.14, seed=730 + idx), dur, 0.09)
    return D.master_finalize(st, target_rms50_db=-11.8)


def build_wall(idx: int) -> np.ndarray:
    """躯体高速撞击湿石砖墙（<=0.40s < 0.45s 门禁）：沉实砖墙闷撞 + 碎砾水珠散落！"""
    dur = 0.39
    thud = D.slice_192k(f"qubodup-impact/x/qubodupImpact/qubodupImpactMeat0{(idx % 2) + 1}.flac", 0.0, 0.30, speed=0.84 + 0.05 * idx, hp_hz=45.0)
    stone = D.slice_192k(f"kenney-impact-sounds/x/Audio/footstep_concrete_00{(idx + 1) % 5}.ogg", 0.0, 0.18, speed=0.68, hp_hz=90.0)
    stone = D.transient_shaper(stone, attack_db=7.0, sustain_db=-2.0)
    sp = D.slice_192k(f"oga-40-cc0-water-splash/x/splash_0{(idx % 5) + 1}.ogg", 0.0, 0.30, speed=1.15, hp_hz=1500.0)
    sub = D.sub_drop(0.24, f_start=92, f_end=38, tau_pitch=0.038, tau_amp=0.095, drive=1.85)
    st = D.mix_layers(dur, (thud, 0.0, 0.0), (stone, 0.0, -1.5), (sp, 0.012, -9.0), (sub, 0.0, -1.0))
    st = D.bus_compress(st, threshold_db=-11.0, ratio=3.2)
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.46, er_mix=0.17, er_decay_s=0.075, seed=740 + idx), dur, 0.085)
    return D.master_finalize(st, target_rms50_db=-12.5)


def build_chain(idx: int) -> np.ndarray:
    """连携传导冲击（<=0.35s < 0.40s 门禁）：暗紫晶体弦共鸣咬合（按层数升调时依然清澈高级）。"""
    dur = 0.34
    bite = D.slice_192k(BLADE_CLASHES[idx % len(BLADE_CLASHES)][0], BLADE_CLASHES[idx % len(BLADE_CLASHES)][1], BLADE_CLASHES[idx % len(BLADE_CLASHES)][1] + 0.18, speed=1.25, hp_hz=400.0)
    chord = D.modal_bank(
        bite[:int(0.012 * D.SR)], dur,
        freqs=[1180.0 * (1 + 0.02 * idx), 1770.0, 2655.0, 3980.0],
        amps=[0.85, 0.70, 0.45, 0.25], taus=[0.12, 0.10, 0.08, 0.06],
        detune_cents=4.0, seed=750 + idx
    )
    sub = D.sub_drop(0.15, f_start=105, f_end=48, tau_pitch=0.03, tau_amp=0.06, drive=1.5)
    st = D.mix_layers(dur, (bite, 0.0, -2.5), (chord, 0.0, 0.0), (sub, 0.0, -3.5))
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.55, er_mix=0.14, seed=755 + idx), dur, 0.08)
    return D.master_finalize(st, target_rms50_db=-13.2)


def build_bomb(idx: int) -> np.ndarray:
    """投弹者黑火药爆轰：近场脆裂铁壳炸开 + 冲击波轰鸣 + 飞溅水花。"""
    dur = 0.64
    crack = D.slice_192k("qubodup-impact/x/qubodupImpact/qubodupImpactMetal.flac", 0.0, 0.35, speed=0.72 + 0.04 * idx, hp_hz=60.0)
    crack = D.transient_shaper(crack, attack_db=7.5, sustain_db=-1.0)
    blast = D.rift_warp_synth(0.56, seed=760 + idx, intensity=1.0)
    blast = D.lp(blast, 3800.0)
    splash = D.slice_192k(f"oga-40-cc0-water-splash/x/splash_0{(idx % 4) + 3}.ogg", 0.0, 0.50, speed=0.85, hp_hz=500.0)
    sub = D.sub_drop(0.48, f_start=95, f_end=30, tau_pitch=0.06, tau_amp=0.18, drive=2.25)
    st = D.mix_layers(dur, (crack, 0.0, 0.0), (blast, 0.004, -3.0), (splash, 0.020, -6.5), (sub, 0.0, 1.5))
    st = D.bus_compress(st, threshold_db=-13.0, ratio=4.0)
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.68, er_mix=0.22, er_decay_s=0.11, seed=765 + idx), dur, 0.14)
    return D.master_finalize(st, target_rms50_db=-10.6)


def build_shade_windup(heavy: bool, idx: int) -> np.ndarray:
    """敌人起手高辨识度招牌预警：
    - 普通影卒（0.24s < 0.27s 起手帧）：干脆冷锐的高音暗刃微出鞘“嚓！”（峰值在 0.055s，混战一耳朵捕捉！）
    - 重甲影（0.39s < 0.43s 起手帧）：沉重黑铁甲叶碰撞 + 192kHz 巨刃拖地金属刮擦威慑音！
    """
    if not heavy:
        dur = 0.24
        rz = DAGGER_RAZOR_DRAWS[idx % len(DAGGER_RAZOR_DRAWS)]
        shing = D.slice_razor_shing_192k(rz[0], rz[1], rz[2], speed=1.35 + 0.05 * idx, pre_s=0.045, post_s=0.18, attack_s=0.032, hp_hz=2000.0)
        ping = D.cold_steel_ring(
            [(4150.0, 1.0), (6350.0, 0.55)], f_primary=4150.0 + 130.0 * idx,
            dur_s=0.19, tau=0.058, bloom_s=0.008, crystalline_boost=0.45, seed=780 + idx,
        )
        st = D.mix_layers(dur, (shing, 0.0, 0.0), (ping, 0.040, -5.0))
        st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.07, seed=782 + idx), dur, 0.06)
        return D.master_finalize(st, target_rms50_db=-14.2, hp_cut_hz=350.0)
    else:
        dur = 0.39
        armor = D.slice_192k("blacklodge-metal/dull_metal_collision_11_44k_32bit_stereo.wav", 0.0, 0.28, speed=0.88 + 0.04 * idx, hp_hz=95.0)
        drag = D.slice_192k(SABRE_RAZOR_DRAWS[idx % len(SABRE_RAZOR_DRAWS)][0], SABRE_RAZOR_DRAWS[idx % len(SABRE_RAZOR_DRAWS)][1], SABRE_RAZOR_DRAWS[idx % len(SABRE_RAZOR_DRAWS)][2], speed=0.78, hp_hz=900.0)
        drag = D.lp(drag, 6500.0)
        sub = D.sub_drop(0.24, f_start=76, f_end=42, tau_pitch=0.06, tau_amp=0.11, drive=1.75)
        st = D.mix_layers(dur, (armor, 0.0, 0.0), (drag, 0.025, -2.0), (sub, 0.01, -3.5))
        st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.10, seed=790 + idx), dur, 0.085)
        return D.master_finalize(st, target_rms50_db=-12.8)


def build_shade_swing(heavy: bool, idx: int) -> np.ndarray:
    """敌人挥砍：特意做低沉阴冷风色（切除 >5.5kHz 亮边），与主角清冽锋利的刀风形成鲜明敌我区分！"""
    dur = 0.42 if heavy else 0.29
    src = HEAVY_SWINGS[idx % len(HEAVY_SWINGS)] if heavy else SABRE_SWINGS[idx % 4]
    sw = D.slice_192k(src[0], src[1], src[2], speed=(0.74 if heavy else 0.96) + 0.04 * idx, hp_hz=75.0)
    sw = D.lp(D.saturate(sw, drive=1.4), 5200.0 if not heavy else 4200.0)
    sub = D.sub_drop(0.22 if heavy else 0.12, f_start=88 if heavy else 105, f_end=40, tau_pitch=0.04, tau_amp=0.085 if heavy else 0.05, drive=1.5)
    st = D.mix_layers(dur, (sw, 0.0, 0.0), (sub, 0.02, -3.0 if heavy else -6.5))
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.42, er_mix=0.14, seed=800 + idx), dur, 0.08)
    return D.master_finalize(st, target_rms50_db=-14.2 if heavy else -16.2)


def build_shade_shot(idx: int) -> np.ndarray:
    """影弓放箭：192kHz 斯基泰反曲弓真弦崩响 + 羽箭高速贴耳呼啸破空！"""
    dur = 0.38
    shoot_t = [(0.19, 0.34), (0.89, 1.07), (3.38, 3.52)][idx % 3]
    twang = D.slice_192k(SN_TEX + "Scythian Recurve Shoot.wav", shoot_t[0], shoot_t[1], speed=1.02 + 0.04 * idx, hp_hz=140.0)
    twang = D.transient_shaper(twang, attack_db=6.5, sustain_db=-2.0)
    passby = D.slice_192k(SN_TEX + "Scythian Recurve Arrow Passby.wav", 3.30, 3.76, speed=1.18 + 0.05 * idx, hp_hz=350.0)
    st = D.mix_layers(dur, (twang, 0.0, 0.0), (passby, 0.015, -2.0))
    st = D.dynamic_pan_sweep(st, 0.35, -0.35)
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.48, er_mix=0.12, seed=815 + idx), dur, 0.085)
    return D.master_finalize(st, target_rms50_db=-13.5)


def build_shade_die(idx: int) -> np.ndarray:
    """影卒溃散化作黑羽（<=0.55s < 0.62s 门禁）：暗核崩解消融 + 黑鸦羽翼散落风声。"""
    dur = 0.54
    pop = D.slice_192k("qubodup-impact/x/qubodupImpact/qubodupImpactMeat02.flac", 0.0, 0.24, speed=0.92 + 0.05 * idx, hp_hz=60.0)
    cloth_flutter = D.slice_192k(f"kenney-rpg-audio/x/Audio/cloth{(idx % 3) + 1}.ogg", 0.0, 0.28, speed=1.15, hp_hz=300.0)
    wing = D.slice_192k(DAGGER_SWINGS[idx % 3][0], DAGGER_SWINGS[idx % 3][1], DAGGER_SWINGS[idx % 3][2], speed=1.28, hp_hz=450.0)
    dissolve = D.lp(D.rift_warp_synth(0.46, seed=825 + idx, intensity=0.55), 5500.0)
    sub = D.sub_drop(0.24, f_start=84, f_end=35, tau_pitch=0.05, tau_amp=0.095, drive=1.6)
    st = D.mix_layers(
        dur,
        (pop, 0.0, -1.5),
        (dissolve, 0.01, -3.5),
        (wing, 0.03, -4.5),
        (cloth_flutter, 0.09, -5.5),
        (sub, 0.0, -2.5),
    )
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.58, er_mix=0.16, seed=830 + idx), dur, 0.12)
    return D.master_finalize(st, target_rms50_db=-14.8)


def build_player_die() -> np.ndarray:
    """主角力竭倒下：手中名刀脱手坠落石板清冷铮鸣 + 躯体倒向积水石街。"""
    dur = 0.92
    blade_drop = D.slice_192k(BLADE_CLASHES[1][0], BLADE_CLASHES[1][1], BLADE_CLASHES[1][1] + 0.65, speed=0.88, hp_hz=220.0)
    fall = D.slice_192k("qubodup-impact/x/qubodupImpact/qubodupImpactMeat01.flac", 0.0, 0.35, speed=0.75, hp_hz=42.0)
    splash = D.slice_192k("oga-40-cc0-water-splash/x/splash_02.ogg", 0.0, 0.45, speed=0.90, hp_hz=600.0)
    sub = D.sub_drop(0.45, f_start=82, f_end=32, tau_pitch=0.06, tau_amp=0.18, drive=1.85)
    st = D.mix_layers(dur, (fall, 0.0, 0.0), (sub, 0.0, 0.0), (splash, 0.02, -6.0), (blade_drop, 0.14, -2.5))
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.55, er_mix=0.20, er_decay_s=0.12, seed=840), dur, 0.20)
    return D.master_finalize(st, target_rms50_db=-12.2)


def build_seal() -> np.ndarray:
    """封场结界升起（哥特雨港暗银钟鸣 + 结界凝滞共鸣，替代廉价电子提示音）。"""
    dur = 1.35
    bell = D.slice_192k("kenney-impact-sounds/x/Audio/impactBell_heavy_000.ogg", 0.0, 1.2, speed=0.78, hp_hz=95.0)
    strike_air = D.slice_192k(HILT_CLASHES[0][0], HILT_CLASHES[0][1], HILT_CLASHES[0][1] + 0.18, speed=1.05, hp_hz=800.0)
    blade_hum = D.modal_bank(
        strike_air[:int(0.025 * D.SR)], dur,
        freqs=[293.66, 440.0, 587.33, 880.0, 1318.5, 2093.0],  # D minor 哥特暗银钟泛音列
        amps=[0.85, 0.70, 0.55, 0.40, 0.28, 0.16], taus=[0.55, 0.48, 0.42, 0.35, 0.26, 0.18],
        detune_cents=5.5, seed=850
    )
    sub = D.sub_drop(0.55, f_start=73.4, f_end=36.7, tau_pitch=0.10, tau_amp=0.22, drive=1.45)
    st = D.mix_layers(dur, (bell, 0.0, -1.5), (strike_air, 0.0, -5.0), (blade_hum, 0.008, 0.0), (sub, 0.0, -4.5))
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.75, er_mix=0.24, er_decay_s=0.14, seed=851), dur, 0.32)
    return D.master_finalize(st, target_rms50_db=-13.5)


def build_clear() -> np.ndarray:
    """封印解除 / 波次肃清：破晓微光泛音绽放 + 名刀轻吟消散。"""
    dur = 1.65
    zing = D.slice_192k(SN_TEX + "Katana Draw Slow.wav", 5.45, 6.45, speed=1.08, hp_hz=600.0)
    chord = D.modal_bank(
        zing[:int(0.035 * D.SR)], dur,
        freqs=[440.0, 659.25, 880.0, 1108.7, 1760.0, 2637.0],  # 清冽破晓开阔五度/大三泛音
        amps=[0.75, 0.70, 0.55, 0.35, 0.28, 0.16], taus=[0.68, 0.62, 0.55, 0.48, 0.38, 0.28],
        detune_cents=4.5, seed=860
    )
    t = np.arange(chord.shape[1]) / D.SR
    chord *= (np.clip(t / 0.035, 0.0, 1.0) ** 1.2)[None, :]
    sub = D.sub_drop(0.55, f_start=110.0, f_end=55.0, tau_pitch=0.10, tau_amp=0.24, drive=1.35)
    st = D.mix_layers(dur, (chord, 0.0, 0.0), (zing, 0.0, -7.5), (sub, 0.0, -5.0))
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.80, er_mix=0.25, er_decay_s=0.16, seed=861), dur, 0.40)
    return D.master_finalize(st, target_rms50_db=-13.8)


def build_charge_start(idx: int) -> np.ndarray:
    """蓄力起手聚势：名刀缓缓拉紧鞘口的高音冷钢微鸣升频聚气！"""
    dur = 0.56
    draw = D.slice_192k(SN_TEX + "Katana Draw Slow.wav", 0.20, 0.95, speed=1.22 + 0.05 * idx, hp_hz=950.0)
    n = int(dur * D.SR)
    t = np.arange(n) / D.SR
    # 清冽冷钢高音聚能弦（2.4kHz -> 3.6kHz 缓慢绷紧，不发闷不科幻）
    f_rise = 2350.0 + 1250.0 * ((t / dur) ** 1.5)
    ph = 2 * np.pi * np.cumsum(f_rise) / D.SR
    wire = (np.sin(ph) + 0.45 * np.sin(1.502 * ph)) * (np.sin(np.pi * (t / dur)) ** 0.85)
    st = D.mix_layers(dur, (draw, 0.0, 0.0), (wire, 0.0, -7.5))
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.09, seed=870 + idx), dur, 0.12)
    return D.master_finalize(st, target_rms50_db=-16.0, hp_cut_hz=320.0)


def build_charge_release(idx: int) -> np.ndarray:
    """蓄力释放瞬间爆发音：高音名刀脱鞘寒芒迸裂 + 紧致气浪冲击（配合 swing_charge 断昼斩）。"""
    dur = 0.45
    rz = SABRE_RAZOR_DRAWS[(idx + 2) % len(SABRE_RAZOR_DRAWS)]
    snap = D.slice_razor_shing_192k(rz[0], rz[1], rz[2], speed=1.10, pre_s=0.012, post_s=0.28, attack_s=0.010, hp_hz=1650.0)
    ring = D.cold_steel_ring(
        [(3680.0, 1.0), (5620.0, 0.65)], f_primary=3680.0 + 120.0 * idx,
        dur_s=0.38, tau=0.14, bloom_s=0.010, crystalline_boost=0.55, seed=880 + idx,
    )
    sub = D.sub_drop(0.22, f_start=96, f_end=38, tau_pitch=0.036, tau_amp=0.088, drive=1.75)
    st = D.mix_layers(dur, (snap, 0.0, 0.0), (ring, 0.010, -4.5), (sub, 0.0, -2.5))
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.10, seed=882 + idx), dur, 0.10)
    return D.master_finalize(st, target_rms50_db=-12.2)


def build_ranged_throw(idx: int) -> np.ndarray:
    """飞刃/鸦羽镖射出：指间高音冷钢薄刃脱手铮鸣 + 极速破风！"""
    dur = 0.25
    rz = DAGGER_RAZOR_DRAWS[idx % len(DAGGER_RAZOR_DRAWS)]
    zing = D.slice_razor_shing_192k(rz[0], rz[1], rz[2], speed=1.42, pre_s=0.012, post_s=0.18, attack_s=0.010, hp_hz=2100.0)
    wh = D.slice_192k(SN_TEX + "Crossbow Bolt Passby.wav", 0.10, 0.65, speed=1.45, hp_hz=950.0)
    st = D.mix_layers(dur, (zing, 0.0, 0.0), (wh, 0.006, -2.5))
    st = D.crop_or_pad(D.stereo_widen(st, er_mix=0.07, seed=890 + idx), dur, 0.06)
    return D.master_finalize(st, target_rms50_db=-15.2, hp_cut_hz=350.0)


def build_ranged_hit(idx: int) -> np.ndarray:
    """飞刃钉入目标：清脆钢针贯入瞬态 + 紧促闷响。"""
    dur = 0.24
    hit = D.slice_192k(SN_TEX + "Crossbow Shoot.wav", 0.30 + 0.5 * idx, 0.48 + 0.5 * idx, speed=1.15, hp_hz=180.0)
    bb = D.slice_192k("freesound-323525/323525__kreastricon62__bloody-blade.wav", 0.10, 0.30, speed=1.22, hp_hz=120.0)
    sub = D.sub_drop(0.09, f_start=125, f_end=55, tau_pitch=0.02, tau_amp=0.04, drive=1.4)
    st = D.mix_layers(dur, (hit, 0.0, 0.0), (bb, 0.002, -2.0), (sub, 0.0, -5.0))
    st = D.crop_or_pad(D.stereo_widen(st, width_ms=0.38, er_mix=0.10, seed=895 + idx), dur, 0.06)
    return D.master_finalize(st, target_rms50_db=-14.0)


# ===========================================================================
# 清单组装与批量生成
# ===========================================================================

BANK_SPECS: list[tuple[str, str, float, dict, list]] = [
    # (key, bus, pitchJitter, extra_meta, [builder_callables...])
    ("step", "motion", 0.035, {"label": "湿石板疾跑皮靴", "cat": "身法与环境"}, [lambda i=i: build_step(i) for i in range(6)]),
    ("jump", "motion", 0.025, {"label": "蹬地起跳破风", "cat": "身法与环境"}, [lambda i=i: build_jump(i, False) for i in range(3)]),
    ("jump_double", "motion", 0.025, {"label": "二段跳·夜鸦踏空", "cat": "身法与环境"}, [lambda i=i: build_jump(i, True) for i in range(3)]),
    ("land_light", "motion", 0.03, {"label": "轻巧落石板微溅水", "cat": "身法与环境"}, [lambda i=i: build_land(i, False) for i in range(3)]),
    ("land_heavy", "impact", 0.025, {"label": "高处重坠震地水花", "cat": "身法与环境"}, [lambda i=i: build_land(i, True) for i in range(2)]),
    ("dash", "motion", 0.025, {"label": "残影瞬步折跃", "cat": "身法与环境"}, [lambda i=i: build_dash_step(i) for i in range(2)]),

    ("swing_l1", "blade", 0.02, {"label": "普攻一段·疾切刀风", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_l1(i) for i in range(3)]),
    ("swing_l2", "blade", 0.02, {"label": "普攻二段·斜撩刀风", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_l2(i) for i in range(3)]),
    ("swing_l3", "blade", 0.018, {"label": "普攻三段·重劈裂风", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_l3(i) for i in range(3)]),
    ("swing_up", "blade", 0.02, {"label": "地面上挑破空斩", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_up(i, False) for i in range(2)]),
    ("swing_air_up", "blade", 0.02, {"label": "空中挑升斩", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_up(i, True) for i in range(2)]),
    ("swing_air1", "blade", 0.02, {"label": "空连一段快斩", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_air(1, i) for i in range(2)]),
    ("swing_air2", "blade", 0.02, {"label": "空连二段旋斩", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_air(2, i) for i in range(2)]),
    ("swing_air3", "blade", 0.018, {"label": "空连三段重劈", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_air(3, i) for i in range(2)]),
    ("swing_charge", "blade", 0.015, {"label": "满蓄力断昼巨风", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_charge(i) for i in range(2)]),
    ("swing_dash", "blade", 0.018, {"label": "右向冲刺斩·剃刀横掠", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_dash(i, False) for i in range(2)]),
    ("swing_dash_left", "blade", 0.018, {"label": "左向冲刺斩·剃刀横掠", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.05, "preAlignedSwing": True}, [lambda i=i: build_swing_dash(i, True) for i in range(2)]),
    ("draw", "blade", 0.0, {"label": "名刀出鞘寒芒", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.26}, [build_draw]),
    ("sheathe", "blade", 0.0, {"label": "归鞘滑擦·鲤口锁死", "cat": "主角冷钢刀风", "peakOffsetSeconds": 0.56}, [build_sheathe]),
    ("charge_start", "blade", 0.02, {"label": "蓄力刀鸣聚势", "cat": "主角冷钢刀风"}, [lambda i=i: build_charge_start(i) for i in range(2)]),
    ("charge_release", "impact", 0.02, {"label": "蓄力释气迸发", "cat": "主角冷钢刀风"}, [lambda i=i: build_charge_release(i) for i in range(2)]),
    ("ranged_throw", "blade", 0.03, {"label": "鸦羽飞刃射出", "cat": "主角冷钢刀风"}, [lambda i=i: build_ranged_throw(i) for i in range(2)]),
    ("ranged_hit", "impact", 0.03, {"label": "鸦羽飞刃钉入", "cat": "核心打击与受击"}, [lambda i=i: build_ranged_hit(i) for i in range(2)]),

    ("hit_light", "impact", 0.025, {"label": "轻命中·锋刃切入", "cat": "核心打击与受击"}, [lambda i=i: build_hit("light", i) for i in range(3)]),
    ("hit_heavy", "impact", 0.025, {"label": "重命中·深斩入骨", "cat": "核心打击与受击"}, [lambda i=i: build_hit("heavy", i) for i in range(3)]),
    ("hit_finisher", "impact", 0.02, {"label": "终结命中·裂空重斩", "cat": "核心打击与受击"}, [lambda i=i: build_hit("finisher", i) for i in range(3)]),
    ("hurt", "impact", 0.02, {"label": "主角受击（轻）", "cat": "核心打击与受击"}, [lambda i=i: build_hurt(False, i) for i in range(2)]),
    ("hurt_heavy", "impact", 0.02, {"label": "主角重创（重）", "cat": "核心打击与受击"}, [lambda i=i: build_hurt(True, i) for i in range(2)]),

    ("parry", "impact", 0.015, {"label": "精准弹刀·冷钢火星长鸣", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_parry(i, False) for i in range(3)]),
    ("parry_heavy", "impact", 0.012, {"label": "满势大弹刀·暗钟震鸣", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_parry(i, True) for i in range(2)]),
    ("block", "impact", 0.025, {"label": "架刀格挡卸力", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_block(i) for i in range(3)]),
    ("deflect", "impact", 0.03, {"label": "砍白金凝壳 / 斩飞箭矢", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_deflect(i) for i in range(3)]),
    ("stun", "impact", 0.02, {"label": "白壳崩碎「破晓」！/ 霸体炸破", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_stun_shell_break(i) for i in range(2)]),
    ("guard_break", "impact", 0.02, {"label": "架势被重击震崩", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_guard_break(i) for i in range(2)]),
    ("impact_accent_light", "impact", 0.03, {"label": "二连斩刀脊低频微震", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_impact_accent_light(i) for i in range(3)]),
    ("slam", "impact", 0.025, {"label": "重砸震地溅水", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_slam(i) for i in range(3)]),
    ("rift_burst", "impact", 0.02, {"label": "紫电空间裂口崩裂 / 锋芒破", "cat": "弹刀·破壳·空间裂口"}, [lambda i=i: build_rift_burst(i) for i in range(3)]),

    ("launch", "impact", 0.025, {"label": "挑飞升空掀浪", "cat": "战场物理与敌招"}, [lambda i=i: build_launch(i) for i in range(2)]),
    ("wall", "impact", 0.03, {"label": "轰撞湿石砖墙", "cat": "战场物理与敌招"}, [lambda i=i: build_wall(i) for i in range(3)]),
    ("chain", "impact", 0.0, {"label": "暗晶连携传导", "cat": "战场物理与敌招"}, [lambda i=i: build_chain(i) for i in range(2)]),
    ("bomb", "impact", 0.03, {"label": "黑火药铁弹爆轰", "cat": "战场物理与敌招"}, [lambda i=i: build_bomb(i) for i in range(2)]),
    ("shade_windup", "warning", 0.025, {"label": "影卒起手预警·冷刃微拔", "cat": "战场物理与敌招"}, [lambda i=i: build_shade_windup(False, i) for i in range(3)]),
    ("shade_windup_heavy", "warning", 0.02, {"label": "甲影重起手预警·重甲拖刀", "cat": "战场物理与敌招"}, [lambda i=i: build_shade_windup(True, i) for i in range(2)]),
    ("shade_swing", "motion", 0.03, {"label": "影卒阴冷挥刃", "cat": "战场物理与敌招"}, [lambda i=i: build_shade_swing(False, i) for i in range(3)]),
    ("shade_swing_heavy", "motion", 0.025, {"label": "甲影巨刃压迫重挥", "cat": "战场物理与敌招"}, [lambda i=i: build_shade_swing(True, i) for i in range(2)]),
    ("shade_shot", "warning", 0.03, {"label": "影弓崩弦羽箭破空", "cat": "战场物理与敌招"}, [lambda i=i: build_shade_shot(i) for i in range(2)]),
    ("shade_die", "impact", 0.03, {"label": "暗影溃散化鸦羽", "cat": "战场物理与敌招"}, [lambda i=i: build_shade_die(i) for i in range(3)]),
    ("die", "impact", 0.0, {"label": "主角倒下·名刀坠地", "cat": "关卡仪式与状态"}, [build_player_die]),
    ("seal", "ui", 0.0, {"label": "封场结界·暗银哥特钟鸣", "cat": "关卡仪式与状态"}, [build_seal]),
    ("clear", "ui", 0.0, {"label": "封印解除·破晓清音", "cat": "关卡仪式与状态"}, [build_clear]),
    # 兼容保留旧接口键名（大招现由 ult_fx.gd 独立播放，但 test_audio.gd 会校验这两个键存在）
    ("ult_start", "impact", 0.0, {"label": "绝影蓄势（兼容槽）", "cat": "关卡仪式与状态"}, [lambda: build_charge_start(0)]),
    ("ult_slash", "impact", 0.0, {"label": "绝影裂空（兼容槽）", "cat": "关卡仪式与状态"}, [lambda: build_rift_burst(0)]),
]


def export_old_reference_wavs(old_out_dir: Path) -> dict[str, str]:
    """将旧 sfx_v3 的当前音效解码导出一份到试听目录，方便用户在网页里一键新旧 A/B 对比！"""
    old_out_dir.mkdir(parents=True, exist_ok=True)
    old_manifest_path = OLD_BANK / "manifest.json"
    if not old_manifest_path.exists():
        return {}
    old_clips = json.loads(old_manifest_path.read_text(encoding="utf-8")).get("clips", {})
    mapping: dict[str, str] = {}
    for key, spec in old_clips.items():
        files = spec.get("files", [])
        if not files:
            continue
        f0 = files[0]
        src_p = (OLD_BANK / f0).resolve()
        if not src_p.exists():
            continue
        dst_name = f"old_{key}.wav"
        dst_p = old_out_dir / dst_name
        try:
            if str(src_p).endswith(".ogg.b64"):
                raw_ogg = base64.b64decode(src_p.read_text(encoding="ascii").strip())
                tmp_ogg = old_out_dir / f"_tmp_{key}.ogg"
                tmp_ogg.write_bytes(raw_ogg)
                data, sr = sf.read(str(tmp_ogg), dtype="float32")
                tmp_ogg.unlink(missing_ok=True)
                sf.write(str(dst_p), data, sr, subtype="PCM_16")
            else:
                shutil.copyfile(src_p, dst_p)
            mapping[key] = f"old/{dst_name}"
        except Exception as exc:
            print(f"[warn] export old {key} failed: {exc}")
    return mapping


def write_license_and_readme(out_dir: Path) -> None:
    lic = """《断晓》商业 3A 混合合成音效库 (sfx_aaa_v5) 授权与来源说明
====================================================================

本目录下全部音频文件均由 tools/audio/make_sfx_aaa_v5.py 与 aaa_dsp.py 离线合成生成（48kHz 16-bit Stereo）。
所引用的底层物理瞬态采样全部为 **CC0 1.0 Universal (Public Domain，可免费商用且无需强制署名)**：

1. Still North Media — Medieval Weapons & Weapon Textures (192kHz / 24-bit)
   授权：CC0 1.0 Public Domain (https://opengameart.org/node/146863)
   用途：日本刀/军刀/猎刀/长枪真实挥砍破风、出鞘、归鞘、刃对刃交击、反曲弓崩弦与羽箭破空母带。

2. Kreastricon62 — "Bloody Blade" (Freesound #323525)
   授权：CC0 1.0 Public Domain
   用途：剑刃命中切入物理接触瞬态层。

3. blacklodgegames — 27 Metal Audio Samples (44.1kHz / 32-bit Stereo)
   授权：CC0 1.0 Public Domain
   用途：厚重黑铁甲叶、架势崩解与格挡中低频躯干层。

4. Iwan 'qubodup' Gabovitch — Impact Meat & Metal Pack
   授权：CC0 1.0 Public Domain
   用途：重砸、撞墙与爆轰物理冲击层。

5. rubberduck — 40 CC0 Water Splash & Slime SFX
   授权：CC0 1.0 Public Domain
   用途：雨港湿青石板脚步微溅水、落地水花。

6. Kenney — Impact Sounds & RPG Audio
   授权：CC0 1.0 Public Domain (https://kenney.nl)
   用途：硬底皮靴触石瞬态、风衣布料摩擦、暗银钟鸣基音。

7. 程序物理建模与非线性 DSP 合成层（tools/audio/aaa_dsp.py，项目自研原创）
   用途：色散冷钢/白瓷模态谐振器、紫电空间裂口 FM 撕裂层、紧致相位锁定 Sub-Drop 与 48kHz 母带处理。
"""
    (out_dir / "LICENSE.txt").write_text(lic, encoding="utf-8")
    readme = """# sfx_aaa_v5（《断晓》3A 级混合合成音效库）

由 `C:\\Python314\\python.exe -P tools/audio/make_sfx_aaa_v5.py` 一键可重现生成。
旧版 `assets/audio/sfx_v3/` 完整保留未删；`scripts/presentation/audio_feedback.gd` 默认加载本库。
"""
    (out_dir / "README.md").write_text(readme, encoding="utf-8")


def build_audition_html(aud_dir: Path, report: list[dict], old_map: dict[str, str]) -> None:
    rows_json = json.dumps(report, ensure_ascii=False)
    old_json = json.dumps(old_map, ensure_ascii=False)
    html = f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<title>《断晓》3A 级混合合成音效 · 全量新旧 A/B 对比台 (48kHz Stereo)</title>
<style>
  :root {{
    --bg: #0b0e15; --card: #131926; --border: #253047; --text: #e6ecf8;
    --muted: #8b9bb8; --accent: #b388ff; --accent2: #64d2ff; --old: #ff7b7b;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0; padding: 28px 36px 60px; background: var(--bg); color: var(--text);
    font-family: "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif;
  }}
  h1 {{ margin: 0 0 8px; font-size: 24px; letter-spacing: 0.5px; }}
  .sub {{ color: var(--muted); font-size: 14px; margin-bottom: 22px; line-height: 1.6; }}
  .combo-bar {{
    background: linear-gradient(135deg, #181f33, #131826); border: 1px solid var(--border);
    border-radius: 12px; padding: 16px 20px; margin-bottom: 26px;
  }}
  .combo-title {{ font-size: 14px; font-weight: 600; color: var(--accent); margin-bottom: 10px; }}
  .combo-btns {{ display: flex; flex-wrap: wrap; gap: 10px; }}
  button {{
    background: #1e273d; color: var(--text); border: 1px solid #334366;
    border-radius: 7px; padding: 7px 13px; cursor: pointer; font-size: 13px; transition: all .12s;
  }}
  button:hover {{ background: #2a3756; border-color: var(--accent); }}
  button.playing {{ background: #4a2c82; border-color: #d2b3ff; color: #fff; }}
  button.btn-old {{ background: #2b1d24; border-color: #5c3340; color: #ffb8b8; }}
  button.btn-old:hover {{ background: #422632; border-color: var(--old); }}
  .cat-header {{
    margin: 28px 0 12px; font-size: 17px; font-weight: 700; color: var(--accent2);
    border-left: 3px solid var(--accent); padding-left: 10px;
  }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(430px, 1fr)); gap: 12px; }}
  .item {{
    background: var(--card); border: 1px solid var(--border); border-radius: 10px;
    padding: 12px 15px; display: flex; flex-direction: column; gap: 8px;
  }}
  .item-top {{ display: flex; justify-content: space-between; align-items: baseline; gap: 8px; }}
  .item-name {{ font-weight: 600; font-size: 14.5px; }}
  .item-key {{ font-family: Consolas, monospace; font-size: 12px; color: var(--muted); }}
  .item-meta {{ font-size: 11.5px; color: var(--muted); }}
  .btn-row {{ display: flex; flex-wrap: wrap; gap: 7px; align-items: center; }}
  .tag-new {{ font-size: 11px; color: #c8a6ff; font-weight: 600; margin-right: 2px; }}
  .tag-old {{ font-size: 11px; color: #ff9494; margin-left: 6px; margin-right: 2px; }}
</style>
</head>
<body>
  <h1>《断晓》商业 3A 混合合成音效库 · 新旧 A/B 试听台</h1>
  <div class="sub">
    全部新音效采用 <b>192kHz / 24-bit 真实冷兵器超声波母带 + 物理建模模态谐振 + 紫电空间裂口 FM 合成 + 48kHz 立体声母带</b> 制作，已接入游戏实机。<br>
    点击下方「实战连招模拟」可按真实游戏帧时序试听组合反馈；每个单项均可直接与旧版原声做 A/B 对比。
  </div>

  <div class="combo-bar">
    <div class="combo-title">⚡ 实战连招时序模拟（按游戏真实帧间隔混合回放）</div>
    <div class="combo-btns">
      <button onclick="playSeq([['swing_l1',0],['hit_light',50],['swing_l2',280],['hit_light',330],['impact_accent_light',335],['swing_l3',620],['hit_finisher',675],['slam',680]])">▶ 地面普攻三连斩（递进刀风+命中）</button>
      <button onclick="playSeq([['shade_windup',0],['shade_swing',210],['parry',260]])">▶ 敌起手预警 → 精准弹刀（冷钢长鸣）</button>
      <button onclick="playSeq([['shade_windup_heavy',0],['shade_swing_heavy',360],['parry_heavy',410]])">▶ 甲影拖刀重劈 → 满势大弹刀！</button>
      <button onclick="playSeq([['swing_l1',0],['deflect',50],['swing_l2',290],['deflect',340],['swing_charge',660],['stun',720]])">▶ 砍白金凝壳×2 → 破晓碎壳崩裂！</button>
      <button onclick="playSeq([['swing_up',0],['launch',50],['jump',160],['swing_air1',320],['hit_light',370],['swing_air2',560],['hit_heavy',610],['swing_dash',860],['rift_burst',920],['wall',1160]])">▶ 挑飞 → 空连追斩 → 冲刺撕裂紫裂口 → 撞墙！</button>
      <button onclick="playSeq([['step',0],['step',260],['step',520],['jump',760],['jump_double',1060],['land_light',1480],['sheathe',1720]])">▶ 雨夜石板疾跑 → 二段夜鸦跳 → 落地收刀入鞘</button>
    </div>
  </div>

  <div id="root"></div>

<script>
const ITEMS = {rows_json};
const OLD_MAP = {old_json};
const ctx = new (window.AudioContext || window.webkitAudioContext)();
const bufCache = {{}};

async function playUrl(url, btn) {{
  if (window.location.protocol === 'file:') {{
    const el = new Audio(url);
    if (btn) btn.classList.add('playing');
    el.onended = () => {{ if (btn) btn.classList.remove('playing'); }};
    el.play();
    return;
  }}
  try {{
    if (ctx.state === 'suspended') await ctx.resume();
    if (!bufCache[url]) {{
      const res = await fetch(url);
      const arr = await res.arrayBuffer();
      bufCache[url] = await ctx.decodeAudioData(arr);
    }}
    const src = ctx.createBufferSource();
    src.buffer = bufCache[url];
    src.connect(ctx.destination);
    if (btn) btn.classList.add('playing');
    src.onended = () => {{ if (btn) btn.classList.remove('playing'); }};
    src.start();
  }} catch (_err) {{
    const el = new Audio(url);
    if (btn) btn.classList.add('playing');
    el.onended = () => {{ if (btn) btn.classList.remove('playing'); }};
    el.play();
  }}
}}

function pickNewUrl(key) {{
  const it = ITEMS.find(x => x.key === key);
  if (!it) return null;
  const f = it.files[Math.floor(Math.random() * it.files.length)];
  return 'new/' + f;
}}

function playSeq(steps) {{
  steps.forEach(([key, ms]) => {{
    setTimeout(() => {{
      const u = pickNewUrl(key);
      if (u) playUrl(u, null);
    }}, ms);
  }});
}}

const cats = [...new Set(ITEMS.map(x => x.cat))];
const root = document.getElementById('root');
for (const cat of cats) {{
  const h = document.createElement('div');
  h.className = 'cat-header';
  h.textContent = cat;
  root.appendChild(h);
  const g = document.createElement('div');
  g.className = 'grid';
  for (const it of ITEMS.filter(x => x.cat === cat)) {{
    const d = document.createElement('div');
    d.className = 'item';
    const s0 = it.stats[0];
    let btns = '<span class="tag-new">3A 新版</span>';
    it.files.forEach((f, idx) => {{
      btns += `<button onclick="playUrl('new/${{f}}', this)">变体 ${{idx + 1}}</button>`;
    }});
    if (OLD_MAP[it.key]) {{
      btns += `<span class="tag-old">旧版对照</span><button class="btn-old" onclick="playUrl('${{OLD_MAP[it.key]}}', this)">听旧版</button>`;
    }}
    d.innerHTML = `
      <div class="item-top">
        <span class="item-name">${{it.label}}</span>
        <span class="item-key">${{it.key}} · ${{it.bus}}</span>
      </div>
      <div class="item-meta">时长 ${{s0.duration_s}}s · 50ms响度 ${{s0.rms50_db}} dB · 峰值 ${{s0.peak_db}} dB · 频谱重心 ${{s0.centroid_hz}} Hz</div>
      <div class="btn-row">${{btns}}</div>
    `;
    g.appendChild(d);
  }}
  root.appendChild(g);
}}
</script>
</body>
</html>
"""
    (aud_dir / "index.html").write_text(html, encoding="utf-8")


def main() -> None:
    OUT_BANK.mkdir(parents=True, exist_ok=True)
    new_aud_dir = AUDITION_DIR / "new"
    old_aud_dir = AUDITION_DIR / "old"
    new_aud_dir.mkdir(parents=True, exist_ok=True)

    manifest_clips: dict[str, dict] = {}
    report_rows: list[dict] = []
    total_files = 0

    print(f"=== 开始生成《断晓》商业 3A 混合合成音效库 -> {OUT_BANK} ===")
    for key, bus, jitter, meta, builders in BANK_SPECS:
        files_list: list[str] = []
        stats_list: list[dict] = []
        for idx, fn in enumerate(builders):
            sig = fn()
            fname = f"{key}_{idx}.wav"
            st_info = D.write_wav48(OUT_BANK / fname, sig)
            shutil.copyfile(OUT_BANK / fname, new_aud_dir / fname)
            files_list.append(fname)
            stats_list.append(st_info)
            total_files += 1
        entry: dict = {
            "files": files_list,
            "bus": bus,
            "pitchJitter": jitter,
        }
        if "peakOffsetSeconds" in meta:
            entry["peakOffsetSeconds"] = meta["peakOffsetSeconds"]
        if meta.get("preAlignedSwing"):
            entry["preAlignedSwing"] = True
        manifest_clips[key] = entry
        report_rows.append({
            "key": key,
            "label": meta.get("label", key),
            "cat": meta.get("cat", "其他"),
            "bus": bus,
            "files": files_list,
            "stats": stats_list,
        })
        s0 = stats_list[0]
        print(f"  [OK] {key:22s} ({len(files_list)}x) | {s0['duration_s']:.3f}s | RMS50 {s0['rms50_db']:6.1f}dB | Centroid {s0['centroid_hz']:5.0f}Hz")

    manifest = {
        "version": "sfx_aaa_v5_2_20261114",
        "sampleRate": D.SR,
        "channels": 2,
        "note": "《断晓》商业 3A 级混合合成音效库 v5.2（最高音调冷钢弹刀长鸣 + 192kHz 快速拔刀凌冽寒芒挥斩 + 纯净无梳状滤波立体声母带）。由 tools/audio/make_sfx_aaa_v5.py 生成。",
        "clips": manifest_clips,
    }
    (OUT_BANK / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    write_license_and_readme(OUT_BANK)

    old_map = export_old_reference_wavs(old_aud_dir)
    build_audition_html(AUDITION_DIR, report_rows, old_map)
    (AUDITION_DIR / "report.json").write_text(json.dumps(report_rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"=== 生成完毕：{len(manifest_clips)} 个事件键，共 {total_files} 个 48kHz 立体声母带文件 ===")
    print(f"=== 试听对比台：{AUDITION_DIR / 'index.html'} ===")


if __name__ == "__main__":
    main()
