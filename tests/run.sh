#!/usr/bin/env bash
# Regression tests for cmux-ffm against fake cmux CLIs (no cmux install needed).
set -uo pipefail
cd "$(dirname "$0")/.."
BIN="${1:-./cmux-ffm}"
FAKE="$PWD/tests/fake-cmux"
fails=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

# Runs BIN with a fake cmux and a hard 10 s cap; prints output, then elapsed seconds on the last line.
run_with() {
  local fake="$1"; shift
  local start end out
  start=$(date +%s)
  out=$(CMUX_BIN="$FAKE/$fake" perl -e 'alarm 10; exec @ARGV' "$BIN" "$@" 2>&1)
  end=$(date +%s)
  printf '%s\n%s\n' "$out" "$((end - start))"
}

# 1. Layout parsing: both panes come back with their rectangles.
out=$(run_with ok --layout)
if grep -q "pane:1  x=200 y=30 w=600 h=800  (focused)" <<<"$out" && grep -q "pane:2  x=800 y=30 w=600 h=800" <<<"$out"; then
  pass "--layout parses panes from cmux JSON"
else
  fail "--layout parses panes from cmux JSON"; echo "$out"
fi

# 2. A cmux call that floods stderr must not deadlock the daemon.
out=$(run_with noisy --layout)
secs=$(tail -n1 <<<"$out")
if grep -q "pane:2" <<<"$out" && [ "$secs" -le 3 ]; then
  pass "stderr flood does not deadlock (${secs}s)"
else
  fail "stderr flood does not deadlock (${secs}s)"; echo "$out"
fi

# 3. A cmux call that never returns is killed after the timeout.
out=$(run_with hang --layout)
secs=$(tail -n1 <<<"$out")
if grep -q "Could not read the pane layout" <<<"$out" && [ "$secs" -le 5 ]; then
  pass "hung cmux call is killed after the timeout (${secs}s)"
else
  fail "hung cmux call is killed after the timeout (${secs}s)"; echo "$out"
fi

[ "$fails" -eq 0 ] && echo "all tests passed" || { echo "$fails test(s) failed"; exit 1; }
