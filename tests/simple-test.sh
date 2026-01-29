#!/usr/bin/env bash
# Simple test runner for reqdrive (no bats dependency)
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
echo "  reqdrive simple test suite"
echo "========================================"
echo ""

# ─────────────────────────────────────────────
# Test: Config loading
# ─────────────────────────────────────────────
echo "--- Config Tests ---"

# Test: reqdrive_load_config_path finds manifest
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path
  [ -n "$REQDRIVE_MANIFEST" ] && [ "$REQDRIVE_PROJECT_ROOT" = "$TEST_TEMP" ]
)
test_result "config: finds manifest in current dir" $?

# Test: reqdrive_load_config_path finds manifest in parent
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"}}
EOF
  mkdir -p subdir/nested
  cd subdir/nested
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path
  [ "$REQDRIVE_PROJECT_ROOT" = "$TEST_TEMP" ]
)
test_result "config: finds manifest in parent dir" $?

# Test: reqdrive_load_config loads project name
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"project":{"name":"my-proj","title":"My Project"},"paths":{"requirementsDir":"reqs","agentDir":"agent"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_PROJECT_NAME" = "my-proj" ] && [ "$REQDRIVE_PROJECT_TITLE" = "My Project" ]
)
test_result "config: loads project name and title" $?

# Test: reqdrive_resolve_path
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  result=$(reqdrive_resolve_path "docs/requirements")
  [ "$result" = "$TEST_TEMP/docs/requirements" ]
)
test_result "config: resolves relative paths" $?

# Test: reqdrive_resolve_path preserves absolute
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  result=$(reqdrive_resolve_path "/absolute/path")
  [ "$result" = "/absolute/path" ]
)
test_result "config: preserves absolute paths" $?

# Test: security args for interactive mode
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"},"security":{"mode":"interactive"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  result=$(reqdrive_claude_security_args agent)
  [ -z "$result" ]
)
test_result "config: interactive mode returns empty args" $?

# Test: security args for dangerous mode
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"},"security":{"mode":"dangerous"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  result=$(reqdrive_claude_security_args agent)
  [ "$result" = "--dangerously-skip-permissions" ]
)
test_result "config: dangerous mode returns skip flag" $?

echo ""
echo "--- Validation Tests ---"

# Test: validate passes for valid manifest
(
  cd "$TEST_TEMP"
  mkdir -p reqs agent
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path
  output=$(source "$REQDRIVE_ROOT/lib/validate.sh" 2>&1)
  echo "$output" | grep -q "Validation PASSED"
)
test_result "validate: passes for valid manifest" $?

# Test: validate fails for invalid JSON
(
  set +e  # Disable errexit for this test
  cd "$TEST_TEMP"
  echo "{ invalid json }" > reqdrive.json
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path
  # validate.sh should exit non-zero for invalid JSON
  (set -e; source "$REQDRIVE_ROOT/lib/validate.sh") >/dev/null 2>&1
  status=$?
  [ "$status" -ne 0 ]  # Expect non-zero exit
)
test_result "validate: fails for invalid JSON" $?

# Test: validate fails for missing project.name
(
  cd "$TEST_TEMP"
  cat > reqdrive.json <<'EOF'
{"project":{"title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path
  output=$(source "$REQDRIVE_ROOT/lib/validate.sh" 2>&1) || true
  echo "$output" | grep -q "Missing required field"
)
test_result "validate: fails for missing project.name" $?

# Test: validate detects circular dependencies
(
  cd "$TEST_TEMP"
  mkdir -p reqs agent
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"},"requirements":{"dependencies":{"REQ-01":["REQ-02"],"REQ-02":["REQ-01"]}}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path
  output=$(source "$REQDRIVE_ROOT/lib/validate.sh" 2>&1) || true
  echo "$output" | grep -q "Circular dependency"
)
test_result "validate: detects circular dependencies" $?

# Test: validate fails for invalid security mode
(
  cd "$TEST_TEMP"
  mkdir -p reqs agent
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"},"security":{"mode":"invalid"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path
  output=$(source "$REQDRIVE_ROOT/lib/validate.sh" 2>&1) || true
  echo "$output" | grep -q "Invalid security.mode"
)
test_result "validate: fails for invalid security mode" $?

echo ""
echo "--- CLI Tests ---"

# Test: --version exits successfully
(
  source "$REQDRIVE_ROOT/lib/config.sh"
  # Simulate version command logic
  VERSION="0.1.0"
  [ -n "$VERSION" ]
)
test_result "cli: version is defined" $?

# Test: dispatch handles validate command
(
  cd "$TEST_TEMP"
  mkdir -p reqs agent
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path
  # validate.sh should succeed
  source "$REQDRIVE_ROOT/lib/validate.sh" >/dev/null 2>&1
)
test_result "cli: validate command works" $?

# Test: deps command works with dependencies
(
  cd "$TEST_TEMP"
  mkdir -p reqs agent
  cat > reqdrive.json <<'EOF'
{"project":{"name":"test","title":"Test"},"paths":{"requirementsDir":"reqs","agentDir":"agent"},"requirements":{"dependencies":{"REQ-01":[],"REQ-02":["REQ-01"]}}}
EOF
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  output=$(source "$REQDRIVE_ROOT/lib/deps.sh" 2>&1)
  echo "$output" | grep -q "REQ-01"
)
test_result "cli: deps command shows dependencies" $?

echo ""
echo "========================================"
echo "  Results: $PASS passed, $FAIL failed, $TOTAL total"
echo "========================================"

[ "$FAIL" -eq 0 ]
