#!/usr/bin/env bash
# 默认跑无窗口逻辑测试；带参数只跑指定名称（例如 feel night_combat）。
# GODOT 可指定引擎；否则用项目自带版本，再查 PATH 上的 godot。
# TEST_TIMEOUT 为单项超时秒数（默认600）；TEST_LOG_DIR 可指定日志目录。
set -u
cd "$(dirname "$0")/../.." || exit 2

if [[ -n "${GODOT:-}" ]]; then
  G="$GODOT"
elif [[ -x engine/Godot_v4.7.2-stable_win64_console.exe ]]; then
  G="$PWD/engine/Godot_v4.7.2-stable_win64_console.exe"
else
  G="$(command -v godot || true)"
fi
if [[ -z "$G" ]] || ! command -v "$G" >/dev/null 2>&1; then
  printf '找不到 Godot，请设置 GODOT 为引擎完整路径。\n' >&2
  exit 2
fi
if ! command -v timeout >/dev/null 2>&1; then
  printf '需要 timeout 命令；Windows 请使用 Git Bash。\n' >&2
  exit 2
fi
limit="${TEST_TIMEOUT:-600}"
if [[ ! "$limit" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ -z "${limit//[0.]/}" ]]; then
  printf 'TEST_TIMEOUT 必须是大于0的秒数。\n' >&2
  exit 2
fi

skipped=0
if [[ $# -eq 0 ]]; then
  shopt -s nullglob
  suites=()
  for file in tests/test_*.gd; do
    n="${file#tests/test_}"
    n="${n%.gd}"
    if [[ "$n" == character_outline ]]; then
      printf 'SKIP character_outline: requires rendering, run without --headless.\n'
      skipped=$((skipped + 1))
      continue
    fi
    suites+=("$n")
  done
  set -- "${suites[@]}"
fi
if [[ $# -eq 0 ]]; then
  printf '没有可运行的无窗口测试。\n' >&2
  exit 2
fi
for n in "$@"; do
  if [[ ! "$n" =~ ^[A-Za-z0-9_]+$ ]] || [[ ! -f "tests/test_$n.gd" ]]; then
    printf '未知测试：%s\n' "$n" >&2
    exit 2
  fi
  if [[ "$n" == character_outline ]]; then
    printf 'character_outline requires rendering; run Godot --path . --script res://tests/test_character_outline.gd without --headless.\n' >&2
    exit 2
  fi
done

log_dir="${TEST_LOG_DIR:-.runtime/test-logs/$(date +%Y%m%d-%H%M%S)-$$}"
mkdir -p "$log_dir" || exit 2
printf '日志：%s\n' "$log_dir"
tot=0; bad=0; failed_suites=0
known_headless_error='ERROR: Condition "!actions.custom_samplers.has(function->arguments[j].tex_builtin)" is true. Continuing.'
for n in "$@"; do
  log="$log_dir/test_$n.log"
  status=0
  timeout --kill-after=5 "$limit" "$G" --headless --fixed-fps 60 --path . \
    --script "res://tests/test_$n.gd" > "$log" 2>&1 || status=$?
  line="$(grep -E '[0-9]+ checks.*[0-9]+ failures' "$log" | tail -1)"
  printf '%s: %s\n' "$n" "${line:-没有测试总结（日志：$log）}"
  suite_failed=0
  if [[ "$line" =~ ([0-9]+)[[:space:]]+checks[^0-9]*([0-9]+)[[:space:]]+failures ]]; then
    c="${BASH_REMATCH[1]}"; f="${BASH_REMATCH[2]}"
    tot=$((tot + c)); bad=$((bad + f))
    [[ "$f" -gt 0 ]] && suite_failed=1
  else
    suite_failed=1
  fi
  if [[ "$status" -ne 0 ]]; then
    suite_failed=1
    printf 'FAIL %s: process exit %d（124/137 表示超时或强制终止），日志：%s\n' "$n" "$status" "$log"
  fi
  if grep -Eq 'SCRIPT ERROR:|Parse Error:' "$log"; then
    suite_failed=1
    printf 'FAIL %s: script error，日志：%s\n' "$n" "$log"
  fi
  known_errors=0; unexpected_errors=0
  while IFS= read -r error_line; do
    error_line="${error_line%$'\r'}"
    if [[ "$error_line" == "$known_headless_error" ]]; then
      known_errors=$((known_errors + 1))
    else
      suite_failed=1
      unexpected_errors=$((unexpected_errors + 1))
      if [[ "$unexpected_errors" -le 8 ]]; then
        printf 'FAIL %s: %s\n' "$n" "$error_line"
      fi
    fi
  done < <(grep '^ERROR:' "$log")
  if [[ "$known_errors" -gt 0 ]]; then
    printf 'KNOWN_HEADLESS_DIAGNOSTIC %s: %d 次已确认的 custom_samplers 无窗口诊断，见 %s\n' "$n" "$known_errors" "$log"
  fi
  warnings="$(grep -c '^WARNING:' "$log" || true)"
  if [[ "$warnings" -gt 0 ]]; then
    printf 'DIAGNOSTIC %s: %s 条引擎警告，见 %s\n' "$n" "$warnings" "$log"
  fi
  if [[ "$suite_failed" -ne 0 ]]; then
    failed_suites=$((failed_suites + 1))
    grep -E 'FAIL|SCRIPT ERROR' "$log" | head -8 || true
  fi
done
printf '合计 %d 项，断言失败 %d，失败套件 %d，跳过 %d\n' "$tot" "$bad" "$failed_suites" "$skipped"
exit "$((failed_suites > 0))"
