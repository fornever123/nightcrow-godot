#!/usr/bin/env bash
# 跑 Godot 测试。不带参数 = tests/test_*.gd 全部；带参数 = 只跑这些（例如 feel night_combat）。
cd "$(dirname "$0")/../.."
G=${GODOT:-/data/tools/godot}
if [ $# -eq 0 ]; then set -- $(ls tests/test_*.gd | sed 's#tests/test_##; s#\.gd$##'); fi
tot=0; bad=0
for n in "$@"; do
  out=$(timeout 600 "$G" --headless --fixed-fps 60 --path . --script "res://tests/test_$n.gd" 2>&1)
  line=$(echo "$out" | grep -E "[0-9]+ checks" | tail -1)
  echo "$n: ${line:-（没有结果，看日志 /tmp/test_$n.log）}"
  echo "$out" > "/tmp/test_$n.log"
  echo "$out" | grep -E "FAIL" | head -8
  c=$(echo "$line" | grep -oE "[0-9]+ checks" | grep -oE "[0-9]+"); f=$(echo "$line" | grep -oE "[0-9]+ failures" | grep -oE "[0-9]+")
  tot=$((tot+${c:-0})); bad=$((bad+${f:-1}))
done
echo "合计 $tot 项，失败 $bad"
