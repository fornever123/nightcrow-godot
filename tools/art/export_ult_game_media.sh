#!/usr/bin/env bash
# 大招进游戏用的两份媒体（10-31，用户看完整段预览 13 说“干活”；同日看完预览 17 说“可以进游戏先”，换成预览 17；又删掉光痕拉出，换成预览 18；11-01 开场音效换路线 B、地图斩断开去掉心跳，换成预览 20，画面同 18；同日看完预览 22c 说“可以，进游戏”，换成预览 22：睁眼段声音重剪、冲击帧重击、收刀拖尾、鸦鸣翻翅压小，地图斩时停缩短 + 推近收刀，睁眼挥刀画面同 18；同日尾部回到预览 21 样子，换成预览 23；同日用户选“×2 改：烧白从甩出第一帧（151）就开始一路变白……就之前这一版吧，做进游戏”，换成 26×2b = UltFullPreview26x2：剑挥到底慢放 2 倍甩出 12 帧、一路烧白、甩出最后一帧整屏白）：
#   assets/video/ult_eyes_swing.ogv   预览 18 / 20 的第 66～157 帧（92 帧；11-01 修：原来误写 MAP_AT=160，多导了 2 帧 Remotion 的地图斩开头；睁眼三截原速叠化 → 手臂扫过 → 冲击帧 → 剑挥到底 → 甩出），游戏里全屏放
#   assets/audio/ult/ult_full.ogg      预览 22 整段的混音（开场 → 睁眼 → 挥刀 → 地图斩 → 收刀），游戏里第 0 帧开始放
# 开场和地图斩 / 收刀是游戏里实时画的（ult_fx.gd），所以只导中间这段画面；声音按同一条时间轴整段导出。
# 帧号要和 player.gd 的 ult_vanish_frame / ult_calm_start、UltFullPreview22 的 OPEN / MAP_AT 一致（地图斩里的断开 / 咔 / 总长对 ult_cut_frames / ult_final_frame / ult_total_frames）。
set -eu
REMOTION="E:/00game/ult-slash-remotion"
GAME="$(cd "$(dirname "$0")/../.." && pwd)"
FF="${FFMPEG:-/c/Users/MECHREVO/AppData/Local/Microsoft/WinGet/Packages/Gyan.FFmpeg.Essentials_Microsoft.Winget.Source_8wekyb3d8bbwe/ffmpeg-9.0.1-essentials_build/bin/ffmpeg}"
OPEN=66
MAP_AT=162
COMP=UltFullPreview26x2
cd "$REMOTION"
npx remotion render $COMP out/ult_game_mid.mp4 --frames=$OPEN-$((MAP_AT - 1)) --muted --log=error
npx remotion render $COMP out/ult_game_full.wav --codec=wav --log=error
"$FF" -nostdin -y -loglevel error -i out/ult_game_mid.mp4 -c:v libtheora -q:v 9 -r 60 -an "$GAME/assets/video/ult_eyes_swing.ogv"
"$FF" -nostdin -y -loglevel error -i out/ult_game_full.wav -c:a libvorbis -q:a 6 -ar 48000 "$GAME/assets/audio/ult/ult_full.ogg"
ls -la "$GAME/assets/video/ult_eyes_swing.ogv" "$GAME/assets/audio/ult/ult_full.ogg"
