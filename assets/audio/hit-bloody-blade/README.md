# 命中 / 受击 · Bloody Blade 原声（2026-11-01）

用户在受击参考页选了 Freesound #323525「Bloody Blade」，听了原样版后说“就用它进游戏”，并说明“受击是怪物受击和角色受击都有”。所以敌人被打中（`hit_light` / `hit_heavy` / `hit_finisher`）和主角被打（`hurt` / `hurt_heavy`）都换成这一条录音。

- 原文件归档：[`art/hit-bloody-blade-audio/`](../../../art/hit-bloody-blade-audio/)，和下载的文件逐字节一致（SHA256 见本目录 [manifest.json](manifest.json)）。
- 一层都不叠：不加合成音、不加混响、不变调，游戏里也不加随机音高（`pitchJitter` 0）。
- 只做：35 Hz 高通（原文件有漂移的直流偏移，耳朵听不出来）、从 0.10 秒刀接触处切（前面是很轻的刀风，游戏里挥刀已经有风声）、固定增益、2 毫秒淡入、尾巴淡出。44.1kHz 单声道 WAV，和原文件一样。
- 各档只差音量和长度：轻 −33 dB / 0.25 秒，重 −32 dB / 0.40 秒，终结 −31 dB / 0.56 秒；主角受击 −33 dB / 0.29 秒，重受击 −32 dB / 0.40 秒（用户要和敌人被打一样）（响度是 50 毫秒 RMS；长度按 `tests/test_audio.gd` 的“打击声不拖尾”上限）。
- 音量按用户“挥刀声音为主，击中声音其次”定：挥刀在游戏里每声道约 −23 dB（−19 dB 片段走 −4 dB 的 Motion 总线），命中走 0 dB 的 Impact 总线、再按力度 0～−2.5 dB，所以比挥刀低 8～12 dB。第一版用旧命中声的 −11 / −10 / −9 dB，用户说太大声、把挥刀盖没了；降到 −27 / −26 / −25 后用户又说“击中再小一倍”，再降 6 dB。
- 换下来的 `sfx_v3/hit_*.ogg.b64`、`hurt*.ogg.b64`（Kenney 拳击 / 闷击加工）原样留在磁盘；改回去只要把 `sfx_v3/manifest.json` 里这五项改回原来的文件列表。

重新制作（仓库根目录，需要 FFmpeg）：

```powershell
python -I tools/audio/apply_bloody_blade_hits.py --source "art/hit-bloody-blade-audio/323525__kreastricon62__bloody-blade.wav"
```

`make_hits_v4.py` 重跑时会跳过这五项；`make_sfx_v3.py` 会整份重写清单，跑完它要再跑一次上面的命令。

授权：CC0 1.0（https://freesound.org/people/Kreastricon62/sounds/323525/ ），可商用，不用署名。
