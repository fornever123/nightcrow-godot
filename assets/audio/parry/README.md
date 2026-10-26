# 弹刀音效（2026-10-26）

`parry_a2.wav` 是游戏里精准弹刀（`parry` 事件）现在用的声音，替换了此前从 `mmh3_左侧格挡_v5` 视频切出的 `selected-video/parry.wav`（原文件保留）。

- 格式：48kHz 双声道 16-bit PCM WAV，时长 2.0s，峰值 -1.0dBFS，50ms RMS -10.1dB（与命中声同级）。
- SHA256：`9ba0c07c506eb5c2e937750a00b7f8ad20f1ea69882fd80af9dd0b8148fcdb85`
- 用户在试听中选了"A2"：起音清脆突出，嗡鸣主音 2.34kHz，尾音约 1s。

## 怎么做的

对标《只狼》弹刀的频谱实测（嗡鸣主音 1.75–4kHz、低频冲击约 0.3s、尾音是密集的金属共振）。分层如下：

| 层 | 内容 |
|---|---|
| 起音 | Still North Media 真实矛对矛撞击（192kHz 录音），降到 0.75 倍；截在 0.14s，去掉原录音里的二次碰撞杂响；开头 15ms 的 2kHz 以上再提亮 |
| 身体 | 真实闷金属撞击的 300–900Hz |
| 嗡鸣 | 用这一下撞击里刀身真实的共振比例，主音移到 2.34kHz，撞击后 40ms 冒出 |
| 金属共振 | 撞击送进一个有上百个金属振动模式的共振器，只在 1.5kHz 以上 |
| 火花 | 撞击的 4kHz 以上部分加一个短的明亮混响 |
| 力量 | 75→45Hz 超低频（轻微饱和）+ 真实铃铛撞击降两个八度 + 真实拳击，约 0.3s |
| 空间/压缩 | 0.5s 小空间（6%），6ms 起音的 3:1 压缩 |

生成脚本复制在 `tools/audio/parry_v4/`（参数为 `PARRY['parry_a2']`），素材下载地址见那里的 README。

## 素材授权

| 素材 | 授权 |
|---|---|
| [Still North Media 兵器互撞](https://opengameart.org/node/146863) | CC0 |
| Kenney Impact Sounds（铃铛撞击） | CC0 |
| blacklodgegames 27 Metal Audio Samples（闷金属撞击） | CC0 |
| [will_leamon fleshy fight sounds](https://opengameart.org/content/fleshy-fight-sounds)（拳击） | OGA-BY 3.0，**需署名** |

发布时制作名单需要写上：**Additional Sound FX by Will Leamon**。
