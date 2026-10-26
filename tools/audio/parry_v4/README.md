# 弹刀音效生成脚本（第四版，2026-10-26）

产出 `assets/audio/parry/parry_a2.wav`。原始工作目录在本机 `E:\00game\work\sfx-audition-hit-parry-20261025\`，那里还有试听页和全部候选。这里是脚本副本，体积很大的素材包不进仓库。

## 重新生成

需要 Python 3.10+、numpy 和 ffmpeg。

1. 新建一个工作目录，把本目录的 `*.py` 放进去，并在里面建 `scan/`，把 `still_north_hits.json` 放进 `scan/`。
2. 下载素材，解压到工作目录的 `downloads/`：
   - `downloads/still-north/x/`：[Still North Media 兵器互撞](https://opengameart.org/node/146863) 的两个 7z（CC0，约 156MB）
   - `downloads/fleshy-fight/x/`：[fleshy fight sounds](https://opengameart.org/content/fleshy-fight-sounds)（OGA-BY 3.0）
   - `downloads/kenney-impact/impactBell_heavy_001.ogg`：Kenney Impact Sounds（CC0）
   - `downloads/blacklodge-metal/dull_metal_collision_11_44k_32bit_stereo.wav`：blacklodgegames 27 Metal Audio Samples（CC0）
3. 运行 `python -I parry4.py`，结果写到 `processed3/`。`cand3_parry_a2.wav` 就是游戏里用的那个文件。

`slice_src.py` 会重新切 Still North 长录音并重新排名，得到的排名应和 `still_north_hits.json` 一致。`analyze_refs.py` 是对标测量工具。参考用的著名游戏原声只用于分析，不放进仓库，也不能进游戏。

## 文件

| 文件 | 作用 |
|---|---|
| `parry4.py` | 弹刀第四版的分层合成，参数在 `PARRY`，游戏用的是 `parry_a2` |
| `realistic.py` | 读取、滤波、门限、混响等基础工具（`parry4.py` 依赖它），也包含击中候选 |
| `slice_src.py` | 把 Still North 长录音按撞击切开，并按余振打分 |
| `analyze_refs.py` | 测量嗡鸣主音、衰减、频段分布等指标，用来和参考做对比 |
