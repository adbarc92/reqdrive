#!/usr/bin/env bash
# Simple test runner for reqdrive v0.2.0 (no bats dependency)
set -e

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
TEST_TEMP=$(mktemp -d)
trap "rm -rf $TEST_TEMP" EXIT

echo "========================================"
echo "  reqdrive v0.2.0 simple test suite"
echo "========================================"
echo ""

if [ "$HAS_CLAUDE" = "false" ]; then
  echo -e "${YELLOW}NOTE${NC}: 'claude' binary not found. Some tests will be skipped."
  echo ""
fi

# ─────────────────────────────────────────────
# Test: Config loading
# ─────────────────────────────────────────────
echo "--- Config Tests ---"

# Test: reqdrive_find_manifest finds manifest
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements","testCommand":"npm test"}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  result=$(reqdrive_find_manifest)
  [ "$result" = "$TEST_TEMP/reqdrive.json" ]
)
test_result "config: finds manifest in current dir" $?

# Test: reqdrive_find_manifest finds manifest in parent
(
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
test_result "config: finds manifest in parent dir" $?

# Test: reqdrive_load_config loads settings
(
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
test_result "config: loads all settings" $?

# Test: reqdrive_load_config uses defaults
(
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
test_result "config: uses defaults for missing fields" $?

# Test: reqdrive_get_req_file finds requirement
(
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
test_result "config: reqdrive_get_req_file finds requirement" $?

echo ""
echo "--- Validation Tests ---"

# Test: validate passes for valid manifest
(
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

echo ""
echo "--- Sanitization Tests ---"

# Test: sanitize_for_prompt escapes dangerous patterns
(
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  input='echo $(whoami) and `id`'
  result=$(sanitize_for_prompt "$input")
  # Should escape $ and backticks - result should contain \$ instead of $(
  # and ' instead of `
  echo "$result" | grep -qF '\$' && echo "$result" | grep -qF "'"
)
test_result "sanitize: escapes command substitution" $?

# Test: sanitize_label removes dangerous characters
(
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  input='label;rm -rf /'
  result=$(sanitize_label "$input")
  # Should not contain semicolon - check that result doesn't have ;
  [ "$(echo "$result" | grep -c ';')" -eq 0 ]
)
test_result "sanitize: removes shell metacharacters from labels" $?

# Test: validate_requirement_content warns on suspicious patterns
(
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  content='Run this: $(rm -rf /)'
  output=$(validate_requirement_content "$content" 2>&1) || true
  echo "$output" | grep -q "Suspicious pattern"
)
test_result "sanitize: detects suspicious patterns in requirements" $?

echo ""
echo "--- Error Codes Tests ---"

# Test: errors.sh defines exit codes
(
  source "$REQDRIVE_ROOT/lib/errors.sh"
  [ "$EXIT_SUCCESS" = "0" ] &&
  [ "$EXIT_GENERAL_ERROR" = "1" ] &&
  [ "$EXIT_MISSING_DEPENDENCY" = "2" ] &&
  [ "$EXIT_PREFLIGHT_FAILED" = "8" ]
)
test_result "errors: defines standard exit codes" $?

echo ""
echo "--- Preflight Tests ---"

# Test: check_git_repo fails outside git repo
(
  cd "$TEST_TEMP"
  rm -rf .git 2>/dev/null || true
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  ! check_git_repo 2>/dev/null
)
test_result "preflight: check_git_repo fails outside repo" $?

# Test: check_clean_working_tree passes on clean repo
(
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
  cd "$TEST_TEMP"
  echo "dirty" >> file.txt
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  ! check_clean_working_tree 2>/dev/null
)
test_result "preflight: check_clean_working_tree fails on dirty repo" $?

echo ""
echo "--- CLI Tests ---"

# Test: --version shows version (no claude needed)
(
  output=$("$REQDRIVE_ROOT/bin/reqdrive" --version 2>&1)
  echo "$output" | grep -q "0.2.0"
)
test_result "cli: --version shows 0.2.0" $?

# Test: --help shows usage (no claude needed)
(
  output=$("$REQDRIVE_ROOT/bin/reqdrive" --help 2>&1)
  echo "$output" | grep -q "Usage:" &&
  echo "$output" | grep -q "init" &&
  echo "$output" | grep -q "run" &&
  echo "$output" | grep -q "validate"
)
test_result "cli: --help shows usage" $?

# Test: --help shows new flags
(
  output=$("$REQDRIVE_ROOT/bin/reqdrive" --help 2>&1)
  echo "$output" | grep -q "\-\-interactive" &&
  echo "$output" | grep -q "\-\-unsafe" &&
  echo "$output" | grep -q "\-\-force" &&
  echo "$output" | grep -q "\-\-resume"
)
test_result "cli: --help shows security flags" $?

# Test: unknown command shows error (no claude needed)
(
  output=$("$REQDRIVE_ROOT/bin/reqdrive" unknown-cmd 2>&1) || true
  echo "$output" | grep -q "Unknown command"
)
test_result "cli: unknown command shows error" $?

# Test: validate command works (no claude needed)
(
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
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped, $TOTAL total"
echo "========================================"

[ "$FAIL" -eq 0 ]
