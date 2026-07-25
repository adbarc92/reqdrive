#!/usr/bin/env bash
# Verify every runtime test name maps to exactly one BEHAVIOR-SPEC story.
#
# Usage: bash tests/spec-map.sh [--list]
#   (no args) validate; exit 0 only if the mapping is total and unambiguous
#   --list    print "NAME<TAB>STORY" for every mapped name
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC="$SCRIPT_DIR/BEHAVIOR-SPEC.md"
MODE="${1:-validate}"

WORK=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: bad WORK" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Runtime names, from an actual run. Strip ANSI, match the three verdicts,
# split on the FIRST ": " only, drop the trailing " (reason)" from SKIP lines.
bash "$SCRIPT_DIR/simple-test.sh" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -E '^(PASS|FAIL|SKIP): ' \
  | while IFS= read -r line; do
      verdict="${line%%: *}"
      name="${line#*: }"
      [ "$verdict" = "SKIP" ] && name="${name% (*}"
      printf '%s\n' "$name"
    done | sort -u > "$WORK/runtime.txt"

# Story -> test-name pairs, from the spec.
awk '
  /^### US-[A-Z]+-[0-9]+:/ { story = $2; sub(/:$/, "", story); next }
  /^\*\*Test:\*\* / {
    if (story == "") next
    line = $0
    sub(/^\*\*Test:\*\* /, "", line)
    gsub(/^`|`$/, "", line)
    printf "%s\t%s\n", line, story
    story = ""
  }
' "$SPEC" | sort > "$WORK/mapped.txt"

cut -f1 "$WORK/mapped.txt" | sort > "$WORK/mapped-names.txt"

if [ "$MODE" = "--list" ]; then
  cat "$WORK/mapped.txt"
  exit 0
fi

rc=0

unmapped=$(comm -23 "$WORK/runtime.txt" "$WORK/mapped-names.txt")
if [ -n "$unmapped" ]; then
  echo "UNMAPPED — these tests ran but have no story:" >&2
  printf '%s\n' "$unmapped" | sed 's/^/  /' >&2
  rc=1
fi

phantom=$(comm -13 "$WORK/runtime.txt" "$WORK/mapped-names.txt")
if [ -n "$phantom" ]; then
  echo "PHANTOM — these stories name a test that did not run:" >&2
  printf '%s\n' "$phantom" | sed 's/^/  /' >&2
  rc=1
fi

dupes=$(cut -f1 "$WORK/mapped.txt" | uniq -d)
if [ -n "$dupes" ]; then
  echo "AMBIGUOUS — these test names are claimed by more than one story:" >&2
  printf '%s\n' "$dupes" | sed 's/^/  /' >&2
  rc=1
fi

total=$(wc -l < "$WORK/runtime.txt" | tr -d ' ')
mapped=$(wc -l < "$WORK/mapped-names.txt" | tr -d ' ')
echo "spec-map: $mapped of $total runtime test names mapped"
exit "$rc"
