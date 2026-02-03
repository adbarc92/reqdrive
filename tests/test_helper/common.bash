# Common test helper functions for reqdrive tests (v0.2.0)

# Get the project root directory
export REQDRIVE_ROOT
REQDRIVE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Test fixtures directory
export TEST_FIXTURES
TEST_FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fixtures"

# ── Dependency Checks ────────────────────────────────────────────────────────

# Check if claude binary is available
has_claude() {
  command -v claude &>/dev/null
}

# Skip a test if claude is not available
# Usage: skip_without_claude || return
skip_without_claude() {
  if ! has_claude; then
    echo "SKIP: claude binary not available"
    return 1
  fi
  return 0
}

# Check if gh CLI is available
has_gh() {
  command -v gh &>/dev/null
}

# Skip a test if gh is not available
skip_without_gh() {
  if ! has_gh; then
    echo "SKIP: gh CLI not available"
    return 1
  fi
  return 0
}

# ── Test Environment Setup ───────────────────────────────────────────────────

# Create a temporary directory for test isolation
setup_temp_dir() {
  export TEST_TEMP_DIR
  TEST_TEMP_DIR="$(mktemp -d)"
  export ORIGINAL_PWD
  ORIGINAL_PWD="$(pwd)"
  cd "$TEST_TEMP_DIR" || exit 1
}

# Clean up temporary directory
teardown_temp_dir() {
  cd "$ORIGINAL_PWD" || exit 1
  if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
    rm -rf "$TEST_TEMP_DIR"
  fi
}

# Create a minimal valid manifest for testing (v0.2.0 format)
create_test_manifest() {
  local dir="${1:-.}"
  cat > "$dir/reqdrive.json" <<'EOF'
{
  "requirementsDir": "docs/requirements",
  "testCommand": "npm test",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 10,
  "baseBranch": "main",
  "prLabels": ["agent-generated"],
  "projectName": "test-project"
}
EOF
}

# Create a minimal project structure
create_test_project() {
  local dir="${1:-.}"
  mkdir -p "$dir/docs/requirements"
  mkdir -p "$dir/.reqdrive/agent"
  create_test_manifest "$dir"
}

# Create a test requirements file
create_test_requirement() {
  local dir="${1:-.}"
  local req_id="${2:-REQ-01}"
  local req_name="${3:-Test Feature}"
  mkdir -p "$dir/docs/requirements"
  cat > "$dir/docs/requirements/${req_id}-${req_name// /-}.md" <<EOF
# ${req_id}: ${req_name}

## Description
This is a test requirement.

## Acceptance Criteria
- [ ] Feature is implemented
- [ ] Tests pass
EOF
}

# Initialize a git repository for testing
init_test_git_repo() {
  local dir="${1:-.}"
  cd "$dir" || exit 1
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  git add -A
  git commit -q -m "Initial commit"
  cd - > /dev/null || exit 1
}

# Mock the claude CLI
mock_claude() {
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
# Mock claude CLI for testing
echo "MOCK_CLAUDE_CALLED"
echo "Args: $*"
# Output completion signal if requested
if [[ "$*" == *"VERIFICATION_PASSED"* ]]; then
  echo "VERIFICATION_PASSED"
fi
EOF
  chmod +x "$TEST_TEMP_DIR/bin/claude"
}

# Mock the gh CLI
mock_gh() {
  export PATH="$TEST_TEMP_DIR/bin:$PATH"
  mkdir -p "$TEST_TEMP_DIR/bin"
  cat > "$TEST_TEMP_DIR/bin/gh" <<'EOF'
#!/usr/bin/env bash
# Mock gh CLI for testing
echo "MOCK_GH_CALLED"
echo "Args: $*"
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  echo "https://github.com/test/test-project/pull/1"
fi
EOF
  chmod +x "$TEST_TEMP_DIR/bin/gh"
}

# ── Assertions ───────────────────────────────────────────────────────────────

# Assert a file contains a string
assert_file_contains() {
  local file="$1"
  local expected="$2"
  if ! grep -q "$expected" "$file"; then
    echo "Expected file '$file' to contain: $expected"
    echo "Actual content:"
    cat "$file"
    return 1
  fi
}

# Assert a file does not contain a string
assert_file_not_contains() {
  local file="$1"
  local unexpected="$2"
  if grep -q "$unexpected" "$file"; then
    echo "Expected file '$file' to NOT contain: $unexpected"
    echo "Actual content:"
    cat "$file"
    return 1
  fi
}

# Assert environment variable is set
assert_env_set() {
  local var_name="$1"
  local expected="${2:-}"
  local actual="${!var_name}"
  if [ -z "$actual" ]; then
    echo "Expected environment variable '$var_name' to be set"
    return 1
  fi
  if [ -n "$expected" ] && [ "$actual" != "$expected" ]; then
    echo "Expected $var_name='$expected', got '$actual'"
    return 1
  fi
}
