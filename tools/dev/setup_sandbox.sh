#!/usr/bin/env bash
# 云端沙盒一键恢复（沙盒经常被重置）：同步仓库、装 Godot 4.7.2 + Xvfb、首次导入。
# 用法：bash tools/dev/setup_sandbox.sh        （在仓库根目录；可重复执行，已装好的会跳过）
set -e
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TOOLS=/data/tools
mkdir -p "$TOOLS"
# 1. 仓库：工作区干净时快进到 origin/main（有本地改动就不动）
git fetch -q origin || true
if [ -z "$(git status --porcelain --untracked-files=no)" ]; then git merge -q --ff-only origin/main 2>/dev/null || true; fi
# 2. 系统库（Xvfb + GL + 声音）
if ! command -v Xvfb >/dev/null; then
  sudo dnf install -y -q xorg-x11-server-Xvfb mesa-libGL mesa-libEGL mesa-dri-drivers libXcursor libXinerama libXrandr libXi alsa-lib pulseaudio-libs >/dev/null
fi
# 3. Godot
if [ ! -x "$TOOLS/godot" ]; then
  Z=Godot_v4.7.2-stable_linux.x86_64
  curl -sSL -o "$TOOLS/$Z.zip" "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/$Z.zip"
  (cd "$TOOLS" && unzip -q -o "$Z.zip" && ln -sf "$TOOLS/$Z" "$TOOLS/godot" && rm -f "$Z.zip")
fi
# 4. 虚拟屏幕
pgrep -x Xvfb >/dev/null || (Xvfb :99 -screen 0 1280x720x24 >/dev/null 2>&1 &)
# 5. 首次导入（生成 .import / .uid，不要提交）
if [ ! -d "$ROOT/.godot/imported" ]; then
  timeout 300 "$TOOLS/godot" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
fi
echo "OK  godot=$TOOLS/godot  DISPLAY=:99  测试：bash tools/dev/runtests.sh [名字…]"
