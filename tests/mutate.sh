#!/usr/bin/env bash
# Apply a named mutation to a scratch copy of the repo, run the suite,
# and report how many assertions detected it.
#
# Usage: bash tests/mutate.sh <mutation-name>
# Mutations: impl-prompt-return1 | load-checkpoint-return1 | impl-prompt-silent | none
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MUTANT="${1:-none}"

WORK=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: bad WORK" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Copy tracked files only — no .git, no run state.
(cd "$PROJECT_ROOT" && git ls-files -z | tar --null -T - -cf -) | (cd "$WORK" && tar -xf -)

apply_mutation() {
  case "$MUTANT" in
    none) ;;
    impl-prompt-return1)
      # Total failure with an error status.
      sed -i 's|^build_implementation_prompt() {|build_implementation_prompt() {\n  return 1|' \
        "$WORK/lib/run.sh"
      ;;
    load-checkpoint-return1)
      sed -i 's|^load_checkpoint() {|load_checkpoint() {\n  return 1|' \
        "$WORK/lib/run.sh"
      ;;
    impl-prompt-silent)
      # Total failure with a SUCCESS status: writes an empty prompt, returns 0.
      # shellcheck disable=SC2016 # "$1" is meant to stay literal — it becomes
      # build_implementation_prompt's own arg reference inside the mutated
      # lib/run.sh, not something this script should expand.
      sed -i 's|^build_implementation_prompt() {|build_implementation_prompt() {\n  : > "$1"; return 0|' \
        "$WORK/lib/run.sh"
      ;;
    *)
      echo "FATAL: unknown mutation '$MUTANT'" >&2
      exit 1
      ;;
  esac
}

apply_mutation
bash -n "$WORK/lib/run.sh" || { echo "FATAL: mutation broke syntax" >&2; exit 1; }

out=$(cd "$WORK" && bash tests/simple-test.sh 2>&1)
rc=$?
fails=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '^FAIL: ')
lines=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -cE '^(PASS|FAIL|SKIP): ')

echo "MUTANT=$MUTANT EXIT=$rc FAILS=$fails RESULT_LINES=$lines"
printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep '^FAIL: ' || true
