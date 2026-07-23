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
    --arg generated "$(date +%Y-%m-%d)" \
    --arg claude "$(command -v claude >/dev/null && echo true || echo false)" \
    --rawfile map "$WORK/map.tsv" '
    {
      version: "0.3.0",
      generated: $generated,
      environment: { claude: ($claude == "true") },
      suiteSha256: $suite,
      gateSha256: $gate,
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

echo "oracle-gate: parsed $(wc -l < "$WORK/results.tsv" | tr -d ' ') result lines, suite exit $SUITE_RC"
