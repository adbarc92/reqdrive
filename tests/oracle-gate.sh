#!/usr/bin/env bash
# Freeze gate — DOCTRINE B2/B3.
#
# Usage:
#   bash tests/oracle-gate.sh            enforce the lock
#   bash tests/oracle-gate.sh --accept   regenerate the lock (deliberate human act)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$SCRIPT_DIR/simple-test.sh"
GATE="$SCRIPT_DIR/oracle-gate.sh"
# The suite sources pipeline-harness.sh at enforce time, so its content decides
# test outcomes and MUST be frozen too — otherwise it can be gutted toward
# fake-success (ph_run(){ echo 0; } + a canned gh log) with the hash unchanged.
# spec-map.sh gates lock generation; freeze it so the map cannot be silently
# weakened before an --accept.
HARNESS="$SCRIPT_DIR/lib/pipeline-harness.sh"
SPECMAP="$SCRIPT_DIR/spec-map.sh"
LOCK="$SCRIPT_DIR/oracle.lock.json"
MODE="${1:-enforce}"

command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "FATAL: sha256sum required" >&2; exit 1; }

WORK=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: bad WORK" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

hash_file() { sha256sum "$1" | cut -d' ' -f1; }

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# Emit "VERDICT<TAB>NAME" for every result line.
# Split on the FIRST ": " only — 158 of 158 names contain ": " themselves,
# so cut -d: would truncate every one.
parse_results() {
  grep -E '^(PASS|FAIL|SKIP): ' | while IFS= read -r line; do
    verdict="${line%%: *}"
    name="${line#*: }"
    [ "$verdict" = "SKIP" ] && name="${name% (*}"
    printf '%s\t%s\n' "$verdict" "$name"
  done
}

# Run the suite once; keep both the output and the exit code.
bash "$SUITE" > "$WORK/raw.txt" 2>&1
SUITE_RC=$?
strip_ansi < "$WORK/raw.txt" | parse_results > "$WORK/results.tsv"
cut -f2 "$WORK/results.tsv" | sort > "$WORK/ran.txt"

if [ "$MODE" = "--accept" ]; then
  bash "$SCRIPT_DIR/spec-map.sh" >/dev/null || {
    echo "FATAL: spec-map is not total; every test needs a story before locking" >&2
    exit 1
  }
  bash "$SCRIPT_DIR/spec-map.sh" --list | sort > "$WORK/map.tsv"

  jq -Rn \
    --arg suite "$(hash_file "$SUITE")" \
    --arg gate "$(hash_file "$GATE")" \
    --arg harness "$(hash_file "$HARNESS")" \
    --arg specmap "$(hash_file "$SPECMAP")" \
    --arg generated "$(date +%Y-%m-%d)" \
    --arg claude "$(command -v claude >/dev/null && echo true || echo false)" \
    --rawfile map "$WORK/map.tsv" '
    {
      version: "0.3.0",
      generated: $generated,
      environment: { claude: ($claude == "true") },
      suiteSha256: $suite,
      gateSha256: $gate,
      harnessSha256: $harness,
      specmapSha256: $specmap,
      tests: ($map | rtrimstr("\n") | split("\n") | map(
        (split("\t")) as $p | { name: $p[0], story: $p[1] }
      ))
    }' > "$LOCK"

  # The two claude-gated tests are the only conditional entries.
  jq '(.tests[] | select(.name == "cli: run requires REQ-ID argument" or
                         .name == "cli: plan without args shows usage"))
      |= . + { conditional: "claude" }' "$LOCK" > "$LOCK.tmp" && mv "$LOCK.tmp" "$LOCK"

  echo "Lock regenerated: $(jq '.tests | length' "$LOCK") tests"
  echo "  suiteSha256 $(jq -r .suiteSha256 "$LOCK")"
  echo "  gateSha256  $(jq -r .gateSha256 "$LOCK")"
  exit 0
fi

[ -f "$LOCK" ] || { echo "FATAL: no lock at $LOCK — run --accept first" >&2; exit 1; }

# tr strips \r: some jq builds (e.g. native Windows/chocolatey) write
# multi-line -r output in CRT text mode, appending \r before every \n.
# ran.txt is built by pure bash string parsing and never carries \r, so
# without stripping here, comm below would see zero overlap between the
# two files on those platforms and misfire R1+R6 on every locked test.
#
# Why isn't the same tr needed on the single-value jq calls below (e.g.
# `locked_suite=$(jq -r .suiteSha256 "$LOCK")`)? Those go through $(...)
# command substitution, and bash's command substitution strips trailing
# newline(s) off the captured output wholesale — verified: on this affected
# jq build, `$(jq -r .foo file)` for a one-line "val\r\n" result comes back
# as plain "val", no \r. That stripping only ever removes a *trailing*
# run at the very end of the output, which is exactly where a single-value
# result's \r lives. Multi-line output has no such luck: every line except
# the last carries its \r in the *middle* of the stream once fed through a
# pipe (`jq ... | tr ... | sort`), and a pipe does no newline stripping at
# all — hence the explicit `tr -d '\r'` here.
jq -r '.tests[].name' "$LOCK" | tr -d '\r' | sort > "$WORK/locked.txt"
LOCK_COUNT=$(jq '.tests | length' "$LOCK")
RAN_COUNT=$(wc -l < "$WORK/ran.txt" | tr -d ' ')
FAIL_COUNT=$(awk -F'\t' '$1=="FAIL"' "$WORK/results.tsv" | wc -l | tr -d ' ')

fail() { echo "GATE FAIL [$1] $2" >&2; VERDICT=1; }
VERDICT=0

# ── R7: file integrity ──────────────────────────────────────────────────
locked_suite=$(jq -r .suiteSha256 "$LOCK")
locked_gate=$(jq -r .gateSha256 "$LOCK")
locked_harness=$(jq -r '.harnessSha256 // ""' "$LOCK")
locked_specmap=$(jq -r '.specmapSha256 // ""' "$LOCK")
actual_suite=$(hash_file "$SUITE")
actual_gate=$(hash_file "$GATE")
actual_harness=$(hash_file "$HARNESS")
actual_specmap=$(hash_file "$SPECMAP")
if [ "$locked_suite" != "$actual_suite" ]; then
  fail R7 "NEEDS_HUMAN: tests/simple-test.sh changed (locked $locked_suite, actual $actual_suite). Review the diff, then re-lock with --accept."
fi
if [ "$locked_gate" != "$actual_gate" ]; then
  fail R7 "NEEDS_HUMAN: tests/oracle-gate.sh changed (locked $locked_gate, actual $actual_gate). Review the diff, then re-lock with --accept."
fi
if [ "$locked_harness" != "$actual_harness" ]; then
  fail R7 "NEEDS_HUMAN: tests/lib/pipeline-harness.sh changed (locked $locked_harness, actual $actual_harness). Review the diff, then re-lock with --accept."
fi
if [ "$locked_specmap" != "$actual_specmap" ]; then
  fail R7 "NEEDS_HUMAN: tests/spec-map.sh changed (locked $locked_specmap, actual $actual_specmap). Review the diff, then re-lock with --accept."
fi

# ── R2: a locked test reported FAIL ─────────────────────────────────────
while IFS=$'\t' read -r verdict name; do
  [ "$verdict" = "FAIL" ] || continue
  if grep -qxF "$name" "$WORK/locked.txt"; then
    fail R2 "baseline weakened: '$name' FAILED"
  fi
done < "$WORK/results.tsv"

# ── R3: a locked test reported SKIP (conditional entries exempted) ───────
while IFS=$'\t' read -r verdict name; do
  [ "$verdict" = "SKIP" ] || continue
  grep -qxF "$name" "$WORK/locked.txt" || continue
  cond=$(jq -r --arg n "$name" '.tests[] | select(.name == $n) | .conditional // ""' "$LOCK")
  case "$cond" in
    "")
      fail R3 "silent weakening: '$name' SKIPPED and is not conditional"
      ;;
    claude)
      if command -v claude >/dev/null; then
        fail R3 "'$name' SKIPPED but its condition (claude) is met"
      fi
      ;;
    *)
      fail R3 "unknown conditional '$cond' on '$name' — the enum is {claude}"
      ;;
  esac
done < "$WORK/results.tsv"

# ── R6: a test ran that the lock does not know about ────────────────────
unregistered=$(comm -23 "$WORK/ran.txt" "$WORK/locked.txt")
if [ -n "$unregistered" ]; then
  fail R6 "NEEDS_HUMAN: unregistered tests ran; add them with --accept:"
  printf '%s\n' "$unregistered" | sed 's/^/    /' >&2
fi

# ── R1: a locked test did not run (diagnostic) ──────────────────────────
missing=$(comm -13 "$WORK/ran.txt" "$WORK/locked.txt")
if [ -n "$missing" ]; then
  fail R1 "locked tests did not run (renamed or deleted):"
  printf '%s\n' "$missing" | sed 's/^/    /' >&2
fi

# ── R0: truncation, only when nothing failed ────────────────────────────
if [ "$RAN_COUNT" -lt "$LOCK_COUNT" ] && [ "$FAIL_COUNT" -eq 0 ]; then
  fail R0 "SUITE_TRUNCATED: $RAN_COUNT of $LOCK_COUNT results emitted, no FAIL parsed"
fi

if [ "$VERDICT" -eq 0 ]; then
  echo "oracle-gate: OK — $RAN_COUNT/$LOCK_COUNT locked tests ran, suite exit $SUITE_RC"
fi
exit "$VERDICT"
