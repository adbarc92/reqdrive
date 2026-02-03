#!/usr/bin/env bash
# Simple test runner for reqdrive v0.2.0 (no bats dependency)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export REQDRIVE_ROOT="$PROJECT_ROOT"

PASS=0
FAIL=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

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

# Create temp directory
TEST_TEMP=$(mktemp -d)
trap "rm -rf $TEST_TEMP" EXIT

echo "========================================"
echo "  reqdrive v0.2.0 simple test suite"
echo "========================================"
echo ""

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
echo "--- CLI Tests ---"

# Test: --version shows version
(
  output=$("$REQDRIVE_ROOT/bin/reqdrive" --version 2>&1)
  echo "$output" | grep -q "0.2.0"
)
test_result "cli: --version shows 0.2.0" $?

# Test: --help shows usage
(
  output=$("$REQDRIVE_ROOT/bin/reqdrive" --help 2>&1)
  echo "$output" | grep -q "Usage:" &&
  echo "$output" | grep -q "init" &&
  echo "$output" | grep -q "run" &&
  echo "$output" | grep -q "validate"
)
test_result "cli: --help shows usage" $?

# Test: unknown command shows error
(
  output=$("$REQDRIVE_ROOT/bin/reqdrive" unknown-cmd 2>&1) || true
  echo "$output" | grep -q "Unknown command"
)
test_result "cli: unknown command shows error" $?

# Test: validate command works
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

# Test: run requires REQ-ID
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"requirementsDir":"docs/requirements"}
EOF
  output=$("$REQDRIVE_ROOT/bin/reqdrive" run 2>&1) || true
  echo "$output" | grep -q "Usage: reqdrive run"
)
test_result "cli: run requires REQ-ID argument" $?

echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "========================================"

[ "$FAIL" -eq 0 ]
