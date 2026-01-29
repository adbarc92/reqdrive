#!/usr/bin/env bats
# Unit tests for lib/config.sh

# Load test helpers
load '../test_helper/common'

# Try to load bats helpers if available
if [ -f "$BATS_TEST_DIRNAME/../test_helper/bats-support/load.bash" ]; then
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
fi

setup() {
  setup_temp_dir
}

teardown() {
  teardown_temp_dir
}

# ============================================================================
# reqdrive_load_config_path tests
# ============================================================================

@test "reqdrive_load_config_path finds manifest in current directory" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path

  [ -n "$REQDRIVE_MANIFEST" ]
  [ -n "$REQDRIVE_PROJECT_ROOT" ]
  [ "$REQDRIVE_MANIFEST" = "$TEST_TEMP_DIR/reqdrive.json" ]
}

@test "reqdrive_load_config_path finds manifest in parent directory" {
  create_test_manifest "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/subdir/nested"
  cd "$TEST_TEMP_DIR/subdir/nested"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config_path

  [ "$REQDRIVE_MANIFEST" = "$TEST_TEMP_DIR/reqdrive.json" ]
  [ "$REQDRIVE_PROJECT_ROOT" = "$TEST_TEMP_DIR" ]
}

@test "reqdrive_load_config_path fails when no manifest exists" {
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  run reqdrive_load_config_path

  [ "$status" -ne 0 ]
  [[ "$output" == *"No reqdrive.json found"* ]]
}

# ============================================================================
# reqdrive_load_config tests
# ============================================================================

@test "reqdrive_load_config loads project name and title" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_PROJECT_NAME" = "test-project" ]
  [ "$REQDRIVE_PROJECT_TITLE" = "Test Project" ]
}

@test "reqdrive_load_config loads paths configuration" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_PATHS_REQUIREMENTS_DIR" = "docs/requirements" ]
  [ "$REQDRIVE_PATHS_AGENT_DIR" = ".reqdrive/agent" ]
  [ "$REQDRIVE_PATHS_APP_DIR" = "." ]
  [ "$REQDRIVE_PATHS_CONTEXT_FILE" = "CLAUDE.md" ]
}

@test "reqdrive_load_config loads commands configuration" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_CMD_INSTALL" = "npm install" ]
  [ "$REQDRIVE_CMD_TEST" = "npm test" ]
  [ "$REQDRIVE_CMD_TYPECHECK" = "npx tsc --noEmit" ]
  [ "$REQDRIVE_CMD_LINT" = "npx eslint ." ]
}

@test "reqdrive_load_config loads agent configuration" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_AGENT_MODEL" = "claude-opus-4-5-20251101" ]
  [ "$REQDRIVE_AGENT_MAX_ITERATIONS" = "10" ]
  [ "$REQDRIVE_AGENT_BRANCH_PREFIX" = "reqdrive" ]
  [ "$REQDRIVE_AGENT_COMPLETION_SIGNAL" = "<promise>COMPLETE</promise>" ]
}

@test "reqdrive_load_config loads security configuration" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_SECURITY_MODE" = "interactive" ]
}

@test "reqdrive_load_config uses defaults for missing optional fields" {
  # Create minimal manifest
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "minimal", "title": "Minimal"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"}
}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  # Check defaults are applied
  [ "$REQDRIVE_AGENT_MODEL" = "claude-opus-4-5-20251101" ]
  [ "$REQDRIVE_AGENT_MAX_ITERATIONS" = "10" ]
  [ "$REQDRIVE_ORCH_MAX_PARALLEL" = "3" ]
  [ "$REQDRIVE_SECURITY_MODE" = "interactive" ]
}

# ============================================================================
# reqdrive_resolve_path tests
# ============================================================================

@test "reqdrive_resolve_path resolves relative paths" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  result=$(reqdrive_resolve_path "docs/requirements")
  [ "$result" = "$TEST_TEMP_DIR/docs/requirements" ]
}

@test "reqdrive_resolve_path preserves absolute paths" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  result=$(reqdrive_resolve_path "/absolute/path")
  [ "$result" = "/absolute/path" ]
}

# ============================================================================
# reqdrive_get_req_file tests
# ============================================================================

@test "reqdrive_get_req_file finds requirement file by ID" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01" "Test Feature"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  result=$(reqdrive_get_req_file "REQ-01")
  [[ "$result" == *"REQ-01"* ]]
  [ -f "$result" ]
}

@test "reqdrive_get_req_file fails for non-existent requirement" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  run reqdrive_get_req_file "REQ-99"
  [ "$status" -ne 0 ]
}

# ============================================================================
# reqdrive_get_deps tests
# ============================================================================

@test "reqdrive_get_deps returns dependencies for a requirement" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "requirements": {
    "dependencies": {
      "REQ-01": [],
      "REQ-02": ["REQ-01"],
      "REQ-03": ["REQ-01", "REQ-02"]
    }
  }
}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  # REQ-01 has no deps
  deps1=$(reqdrive_get_deps "REQ-01")
  [ -z "$deps1" ]

  # REQ-02 depends on REQ-01
  deps2=$(reqdrive_get_deps "REQ-02")
  [ "$deps2" = "REQ-01" ]

  # REQ-03 has two deps
  deps3=$(reqdrive_get_deps "REQ-03")
  [[ "$deps3" == *"REQ-01"* ]]
  [[ "$deps3" == *"REQ-02"* ]]
}

# ============================================================================
# reqdrive_claude_security_args tests
# ============================================================================

@test "reqdrive_claude_security_args returns empty for interactive mode" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  result=$(reqdrive_claude_security_args agent)
  [ -z "$result" ]
}

@test "reqdrive_claude_security_args returns skip flag for dangerous mode" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "security": {"mode": "dangerous"}
}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  result=$(reqdrive_claude_security_args agent)
  [ "$result" = "--dangerously-skip-permissions" ]
}

@test "reqdrive_claude_security_args returns allowedTools for allowlist mode" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "security": {
    "mode": "allowlist",
    "allowedTools": ["Bash", "Read", "Write"]
  }
}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  result=$(reqdrive_claude_security_args agent)
  [ "$result" = "--allowedTools Bash,Read,Write" ]
}

# ============================================================================
# reqdrive_timestamp tests
# ============================================================================

@test "reqdrive_timestamp returns ISO-ish format" {
  source "$REQDRIVE_ROOT/lib/config.sh"

  result=$(reqdrive_timestamp)
  # Should match pattern like 2024-01-15T12:30:45Z or with timezone offset
  [[ "$result" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

# ============================================================================
# reqdrive_run_id tests
# ============================================================================

@test "reqdrive_run_id returns date-based ID" {
  source "$REQDRIVE_ROOT/lib/config.sh"

  result=$(reqdrive_run_id)
  # Should match pattern like 20240115-123045
  [[ "$result" =~ ^[0-9]{8}-[0-9]{6}$ ]]
}
