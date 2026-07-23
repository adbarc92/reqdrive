#!/usr/bin/env bash
# Demonstrate that each freeze-gate rule fires. Operates on scratch copies;
# the working tree is never modified.
# shellcheck disable=SC2016
# SC2016: single-quoted $status in the sed pattern is intentional — it must
# stay literal so sed matches it in the scratch copy, not expand in this shell.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASSED=0; FAILED=0

scratch() {
  local d
  d=$(mktemp -d) || return 1
  (cd "$PROJECT_ROOT" && git ls-files -z | tar --null -T - -cf -) | (cd "$d" && tar -xf -)
  printf '%s\n' "$d"
}

# expect_rule <rule> <description> <mutator-function>
expect_rule() {
  local rule="$1" desc="$2" mutate="$3" dir out rc
  dir=$(scratch) || { echo "FAIL: $desc (scratch failed)"; FAILED=$((FAILED+1)); return; }
  "$mutate" "$dir"
  out=$(cd "$dir" && bash tests/oracle-gate.sh 2>&1); rc=$?
  rm -rf "$dir"
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "GATE FAIL \[$rule\]"; then
    echo "PASS: $rule fires — $desc"; PASSED=$((PASSED+1))
  else
    echo "FAIL: $rule did not fire — $desc (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/    /'
    FAILED=$((FAILED+1))
  fi
}

mut_r7_reporter() {
  # The attack a per-body hash misses: patch the reporter, leave every body intact.
  sed -i 's|  if \[ "\$status" -eq 0 \]; then|  if true; then|' "$1/tests/simple-test.sh"
}
mut_r7_body() {
  sed -i '0,/^  set -e$/s/^  set -e$/  set -e\n  true/' "$1/tests/simple-test.sh"
}
mut_r2_fail() {
  # Break a library function so a locked test genuinely fails, then re-lock
  # the suite hash so R7 does not mask R2.
  sed -i 's|^load_checkpoint() {|load_checkpoint() {\n  return 1|' "$1/lib/run.sh"
  (cd "$1" && bash tests/oracle-gate.sh --accept >/dev/null 2>&1)
}
mut_r6_unregistered() {
  cat >> "$1/tests/simple-test.sh" <<'EOF'

(
  set -e
  true
)
test_result "selftest: an unregistered assertion" $?
EOF
  # Re-lock only the file hashes, not the test list, to isolate R6 from R7.
  (cd "$1" && jq --arg s "$(sha256sum tests/simple-test.sh | cut -d' ' -f1)" \
    '.suiteSha256 = $s' tests/oracle.lock.json > /tmp/l.json && mv /tmp/l.json tests/oracle.lock.json)
}
mut_r0_truncate() {
  # Add a locked-but-unrunnable tail: exit early so later results never print.
  sed -i '60i exit 0' "$1/tests/simple-test.sh"
  (cd "$1" && jq --arg s "$(sha256sum tests/simple-test.sh | cut -d' ' -f1)" \
    '.suiteSha256 = $s' tests/oracle.lock.json > /tmp/l.json && mv /tmp/l.json tests/oracle.lock.json)
}

echo "=== oracle-gate self-test ==="
expect_rule R7 "reporter patched to always PASS"        mut_r7_reporter
expect_rule R7 "an assertion body edited"               mut_r7_body
expect_rule R2 "a locked test genuinely fails"          mut_r2_fail
expect_rule R6 "an unregistered assertion ran"          mut_r6_unregistered
expect_rule R0 "the suite exits before emitting results" mut_r0_truncate

echo "=== $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ]
