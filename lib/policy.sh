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
