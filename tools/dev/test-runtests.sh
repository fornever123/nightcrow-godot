#!/usr/bin/env bash
# Regression tests for runtests.sh. Uses isolated fake engines, never Godot.
set -u

runner="$(cd "$(dirname "$0")" && pwd)/runtests.sh"
tmp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
sandbox="$(mktemp -d "$tmp_root/nightcrow-runner.XXXXXX")"
trap '[[ "$sandbox" == "$tmp_root"/nightcrow-runner.* ]] && rm -rf -- "$sandbox"' EXIT
mkdir -p "$sandbox/tools/dev" "$sandbox/tests" "$sandbox/engine"
cp "$runner" "$sandbox/tools/dev/runtests.sh"

cat > "$sandbox/fake godot" <<'ENGINE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_CALLS"
suite=""
headless=false
for arg in "$@"; do
  [[ "$arg" == --headless ]] && headless=true
  [[ "$arg" == res://tests/test_*.gd ]] && suite="${arg#res://tests/test_}"
done
case "${suite%.gd}" in
  assertion_fail) echo 'FAKE: 3 checks / 1 failures'; exit 0 ;;
  process_fail) echo 'FAKE: 3 checks / 0 failures'; exit 7 ;;
  missing_summary) echo 'script stopped before reporting'; exit 0 ;;
  timeout) sleep 0.3; echo 'FAKE: 3 checks / 0 failures'; exit 0 ;;
  script_error) echo 'SCRIPT ERROR: Parse Error: invalid token'; echo 'FAKE: 3 checks / 0 failures' ;;
  render_diagnostic) printf '%s\r\n' 'ERROR: Condition "!actions.custom_samplers.has(function->arguments[j].tex_builtin)" is true. Continuing.'; echo 'FAKE: 3 checks / 0 failures' ;;
  resource_error) echo 'ERROR: Failed loading resource: res://assets/missing.png'; echo 'FAKE: 3 checks / 0 failures' ;;
  unknown_render_error) echo 'ERROR: custom_samplers requires rendering'; echo 'FAKE: 3 checks / 0 failures' ;;
  mixed_errors) echo 'ERROR: Condition "!actions.custom_samplers.has(function->arguments[j].tex_builtin)" is true. Continuing.'; echo 'ERROR: Failed loading resource: res://assets/missing.png'; echo 'FAKE: 3 checks / 0 failures' ;;
  warning) echo 'WARNING: ObjectDB instances leaked at exit'; echo 'FAKE: 3 checks / 0 failures' ;;
  character_outline)
    if "$headless"; then echo 'requires rendering'; exit 2; fi
    echo 'FAKE: 3 checks / 0 failures' ;;
  *) echo 'FAKE: 3 checks / 0 failures' ;;
esac
ENGINE
chmod +x "$sandbox/fake godot"

checks=0
failures=0
check() {
  checks=$((checks + 1))
  if ! "$@"; then
    failures=$((failures + 1))
    printf 'FAIL: %s\n' "$*"
  fi
}

run_suite() {
  local suite="$1"
  local limit=2
  [[ "$suite" == timeout ]] && limit=0.1
  : > "$sandbox/tests/test_$suite.gd"
  status=0
  FAKE_CALLS="$sandbox/calls" GODOT="$sandbox/fake godot" \
    TEST_LOG_DIR="$sandbox/logs" TEST_TIMEOUT="$limit" \
    bash "$sandbox/tools/dev/runtests.sh" "$suite" > "$sandbox/output" 2>&1 || status=$?
}

run_suite pass
check test "$status" -eq 0
run_suite assertion_fail
check test "$status" -ne 0
run_suite process_fail
check test "$status" -ne 0
run_suite missing_summary
check test "$status" -ne 0
run_suite timeout
check test "$status" -ne 0
run_suite script_error
check test "$status" -ne 0
run_suite render_diagnostic
check test "$status" -eq 0
check grep -q 'KNOWN_HEADLESS_DIAGNOSTIC' "$sandbox/output"
run_suite resource_error
check test "$status" -ne 0
run_suite unknown_render_error
check test "$status" -ne 0
run_suite mixed_errors
check test "$status" -ne 0
run_suite warning
check test "$status" -eq 0
check grep -q 'DIAGNOSTIC' "$sandbox/output"

# An allowed diagnostic must not hide a new error from another suite.
status=0
FAKE_CALLS="$sandbox/calls" GODOT="$sandbox/fake godot" TEST_LOG_DIR="$sandbox/logs" \
  bash "$sandbox/tools/dev/runtests.sh" render_diagnostic resource_error > "$sandbox/output" 2>&1 || status=$?
check test "$status" -ne 0

# A later successful suite must not erase an earlier failure.
status=0
FAKE_CALLS="$sandbox/calls" GODOT="$sandbox/fake godot" TEST_LOG_DIR="$sandbox/logs" \
  bash "$sandbox/tools/dev/runtests.sh" assertion_fail pass > "$sandbox/output" 2>&1 || status=$?
check test "$status" -ne 0
check grep -q '合计 6 项' "$sandbox/output"

# Default enumeration must not feed a rendering-only suite to a headless engine.
rm -f -- "$sandbox"/tests/*.gd
: > "$sandbox/tests/test_pass.gd"
: > "$sandbox/tests/test_character_outline.gd"
: > "$sandbox/calls"
status=0
FAKE_CALLS="$sandbox/calls" GODOT="$sandbox/fake godot" TEST_LOG_DIR="$sandbox/logs" \
  bash "$sandbox/tools/dev/runtests.sh" > "$sandbox/output" 2>&1 || status=$?
check test "$status" -eq 0
check grep -q 'SKIP.*character_outline' "$sandbox/output"
check test "$(wc -l < "$sandbox/calls")" -eq 1
check test -s "$sandbox/logs/test_pass.log"

run_suite character_outline
check test "$status" -ne 0
check grep -q -- 'without --headless' "$sandbox/output"

# GODOT is optional when the project's bundled executable exists.
cp "$sandbox/fake godot" "$sandbox/engine/Godot_v4.7.2-stable_win64_console.exe"
chmod +x "$sandbox/engine/Godot_v4.7.2-stable_win64_console.exe"
: > "$sandbox/calls"
status=0
env -u GODOT FAKE_CALLS="$sandbox/calls" TEST_LOG_DIR="$sandbox/logs" \
  bash "$sandbox/tools/dev/runtests.sh" pass > "$sandbox/output" 2>&1 || status=$?
check test "$status" -eq 0
check test "$(wc -l < "$sandbox/calls")" -eq 1

status=0
GODOT="$sandbox/missing-engine" bash "$sandbox/tools/dev/runtests.sh" pass > "$sandbox/output" 2>&1 || status=$?
check test "$status" -ne 0

printf 'RUNNER_TESTS: %d checks / %d failures\n' "$checks" "$failures"
exit "$((failures > 0))"
