#!/usr/bin/env bash
# Risk-tier path classification.
#
# Patterns are bare path prefixes, not globs. A path matches a pattern when
# it equals the pattern or begins with "<pattern>/". Globs are deliberately
# not used: inside [[ ]] bash does not honour globstar, so ** and * are
# indistinguishable and both cross "/", while "src/auth/**" fails to match
# "src/auth" itself. Prefix semantics are what a reader expects and what the
# tests can pin.
set -e

# policy_tier_for_path <path> -> high | medium | low | none
policy_tier_for_path() {
  local path="$1"
  local policy="${REQDRIVE_POLICY_JSON:-{\}}"
  local tier pattern

  # Highest tier wins, so probe in descending order of risk.
  for tier in high medium low; do
    while IFS= read -r pattern; do
      pattern="${pattern%$'\r'}"  # native jq.exe on Windows/MSYS emits CRLF
      [ -n "$pattern" ] || continue
      if [ "$path" = "$pattern" ] || [ "${path#"$pattern"/}" != "$path" ]; then
        printf '%s\n' "$tier"
        return 0
      fi
    done < <(printf '%s' "$policy" | jq -r --arg t "$tier" '.riskTiers[$t][]? // empty' 2>/dev/null)
  done

  printf 'none\n'
}

# policy_classify_paths <path>... -> "TIER<TAB>PATH" per line
policy_classify_paths() {
  local p
  for p in "$@"; do
    printf '%s\t%s\n' "$(policy_tier_for_path "$p")" "$p"
  done
}

# policy_scope_check <agent_dir> <iteration> <tests_passed:0|1>
#
# A finding is a high-risk path changed in an iteration whose testCommand
# run did not pass. warn (default) logs the finding to scope-findings.txt
# and continues; block does the same and returns 1 so the caller aborts.
#
# Paths are read line-by-line rather than passed as `policy_classify_paths
# $changed` — an unquoted expansion word-splits on spaces, and filenames can
# contain them. Quoting `"$changed"` in a herestring keeps each line, and
# therefore each path, intact.
#
# Returns 0 to continue, 1 when block mode must abort.
policy_scope_check() {
  local agent_dir="$1" iteration="$2" tests_passed="$3"
  local mode="${REQDRIVE_POLICY_SCOPE_CHECK:-warn}"
  local findings_file="$agent_dir/scope-findings.txt"

  local changed
  changed=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
  [ -n "$changed" ] || return 0

  local violations=""
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    local tier
    tier=$(policy_tier_for_path "$path")
    [ "$tier" = "high" ] || continue
    [ "$tests_passed" = "1" ] && continue
    violations="$violations $path"
  done <<< "$changed"

  [ -n "$violations" ] || return 0

  echo "iteration $iteration: high-risk paths changed without a passing test run:$violations" \
    >> "$findings_file"

  if [ "$mode" = "block" ]; then
    echo "[ERROR] Scope check: high-risk paths changed without a passing test run:$violations" >&2
    return 1
  fi
  echo "[WARN]  Scope check: high-risk paths changed without a passing test run:$violations" >&2
  return 0
}
