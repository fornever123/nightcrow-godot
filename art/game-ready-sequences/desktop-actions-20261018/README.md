# 桌面动作原片归档

来源：`C:\Users\MECHREVO\Desktop\实际应用到游戏的序列帧`；FrameBaker 项目 `f185d603-1f17-43cb-8319-1e42e5527122`。

共 24 个动作目录、734 张 PNG。原始 PNG 与 `.frames.json` 按字节原样归档，SHA-256 与字节数见 `manifest.json`。
运行副本只裁掉透明边界，不缩放、不绘制、不降分辨率；固定锚点由来源 originX/Y 减裁剪左上角得到，
根运动用独立的 sourceRoot 估算轨迹记录，便于审计与后续接入。所有动作合成图设置 `effectsBaked=true`。
统一基准倍率仅按待机第1帧透明边界高度标定为168px，不代表每个动作身体尺寸都正确；fall与a1尺寸异常见桌面导入审计。
运行时显示倍率与战斗碰撞 worldScale 分开。
重建：fresh clone 可直接运行 `python tools/art/import_desktop_actions.py --source art/game-ready-sequences/desktop-actions-20261018`，再运行 configure 脚本重建 battle 配置；来源就是归档目录时会跳过自复制，并逐文件校验字节与 SHA-256。未指定 `--source` 时优先读取原桌面目录，找不到时回退到此归档。
跑步与转身 FPS 已通过 FrameBaker SQLite 项目的 animation_axes.fps 核对为4；GIF 60ms是预览节奏。
下坠素材无 `.frames.json`，仅按 preview.gif 的60ms/帧显式回退。跳起与落地共享跳动作的17FPS。
