# 地面三连挥刀 · 普攻三段原声（2026-11-01）

用户提供 `E:/.0download/普攻三段.mp4`，要求“挥刀声音试试用作现在挥刀”。从视频原声切出地面三连的三刀，替换 `swing_l1/2/3`。

- 原声归档：[`art/swing-pg3-audio/普攻三段.m4a`](../../../art/swing-pg3-audio/manifest.json)，直接复制视频的 AAC 音轨，解码后和视频完全一致。
- 三刀对应视频里的刀光：第一刀上挑（源 0.25 秒）、第二刀前斩（0.70 秒）、第三刀大劈（1.50 秒）。1.21 秒那一下转身小风声没用。
- 44.1kHz 双声道 WAV。只做裁切、短淡入淡出和固定增益，峰值在片段开始后约 50 毫秒，和挥刀提示提前 3 帧对齐。第三刀带约 0.8 秒的尾音。
- 换下来的 `selected-video/swing_l1..3.wav` 原样保留；改回去只要把 `sfx_v3/manifest.json` 里这三项的路径改回 `../selected-video/`。

每个片段的裁切秒数、增益和 SHA256 见本目录 [manifest.json](manifest.json)。

重新制作（仓库根目录，需要 FFmpeg）：

```powershell
python -I tools/audio/apply_pg3_swing_audio.py --source "E:/.0download/普攻三段.mp4"
```

`apply_selected_video_audio.py` 重跑时会保留这三项的路由。

授权：用户提供的视频原声。
