# DSH 版（DeepSeek Harness 线）

这是《夜鸦 / 沉影之昼》的一条**独立玩法线**，由 DSH 会话维护。它不修改原版的雨街战斗、不共用原版的规则，
以后 **DSH 会话的所有改动都只写进 `dsh/` 目录**，避免和其他并行会话（战斗、背景、UI、大招、音效、角色动作）
抢同一批文件。

## 目录

```
dsh/
  README.md                 本文件：这条线的规矩
  docs/玩法-不落.md          **当前设想的主玩法**（2026-11-03 第二轮设想稿，未实现，先读这个）
  docs/玩法-未竟.md          第一轮设想（已被用户否掉，存档对照）
  docs/玩法-截弦.md          上一版玩法（截弦，有原型）
  docs/玩法-错拍.md          第一版玩法（错拍，有原型）
  data/offbeat.json         错拍的全部可调参数（延迟、连击、敌人、波次、光区）
  scenes/offbeat_trial.tscn 试炼场入口
  scripts/
    offbeat_trial.gd        世界、波次、全局「错拍」时钟、光/影区
    offbeat_player.gd       主角（自制，读 battle.json 的招式时间轴与序列帧）
    offbeat_shade.gd        敌人 + 它的「影身」（未来 0.6 秒的那一份）
    offbeat_hud.gd          延迟条 / 连击 / 影斑 / 波次
    offbeat_fx.gd           刀光、迟到斩痕、伤害数字、粒子
    offbeat_audio.gd        只读现有音效库
```

启动：根目录 `OPEN_DSH.bat`。

## 三条硬规矩

1. **只改 `dsh/` 里的文件。** 需要动 `scripts/night/*`、`scenes/*`、`assets/data/battle.json` 时，
   先和对应会话（见 `docs/项目进程.md` §3）确认，或者把要用的数据**复制**进 `dsh/data/` 再改。
2. **只读共享资源。** 现有序列帧、音效、背景图当只读素材用；新材料放 `dsh/assets/`。
3. **不碰 `project.godot` 的主场景。** DSH 版是并行模式，从 `OPEN_DSH.bat` 进，不改 `run/main_scene`。

## 版本

- Git 分支 `dsh`（基线 = 建线时的 `rain-street` HEAD），提交只放 `dsh/` 和本线文档。
- 进程和要求照旧写进 `docs/项目进程.md` 的 §1 与 §3.10。
