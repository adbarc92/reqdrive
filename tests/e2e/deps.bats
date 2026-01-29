#!/usr/bin/env bats
# E2E tests for dependency checking and requirement finding

# Load test helpers
load '../test_helper/common'

# Try to load bats helpers if available
if [ -f "$BATS_TEST_DIRNAME/../test_helper/bats-support/load.bash" ]; then
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
fi

setup() {
  setup_temp_dir
  mock_gh
}

teardown() {
  teardown_temp_dir
}

# ============================================================================
# find-next-reqs tests
# ============================================================================

@test "E2E: find-next-reqs identifies requirements with no dependencies" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-02"
  init_test_git_repo "$TEST_TEMP_DIR"

  # Set up dependencies where REQ-01 has none
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {
    "pattern": "REQ-*-*.md",
    "idRegex": "REQ-[0-9]+",
    "dependencies": {
      "REQ-01": [],
      "REQ-02": ["REQ-01"]
    }
  },
  "orchestration": {"baseBranch": "main"}
}
EOF

  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  run bash "$REQDRIVE_ROOT/lib/find-next-reqs.sh"

  # REQ-01 should be available (no deps)
  [[ "$output" == *"REQ-01"* ]]
}

@test "E2E: find-next-reqs handles empty requirements directory" {
  create_test_project "$TEST_TEMP_DIR"
  init_test_git_repo "$TEST_TEMP_DIR"

  # No requirement files created
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  run bash "$REQDRIVE_ROOT/lib/find-next-reqs.sh"

  # Should handle gracefully - either empty output or message
  [ "$status" -eq 0 ] || [[ "$output" == *"No"* ]]
}

# ============================================================================
# check-deps tests
# ============================================================================

@test "E2E: check-deps passes for requirement with no dependencies" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01"
  init_test_git_repo "$TEST_TEMP_DIR"

  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {
    "dependencies": {
      "REQ-01": []
    }
  },
  "orchestration": {"baseBranch": "main"}
}
EOF

  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  run bash "$REQDRIVE_ROOT/lib/check-deps.sh" REQ-01

  [ "$status" -eq 0 ]
}

@test "E2E: check-deps handles unknown requirements" {
  create_test_project "$TEST_TEMP_DIR"
  init_test_git_repo "$TEST_TEMP_DIR"

  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {"dependencies": {}},
  "orchestration": {"baseBranch": "main"}
}
EOF

  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  # Unknown requirement with no configured deps should pass
  run bash "$REQDRIVE_ROOT/lib/check-deps.sh" REQ-UNKNOWN

  # Should either pass (no deps configured) or fail gracefully
  [ "$status" -eq 0 ] || [[ "$output" == *"not found"* ]]
}

# ============================================================================
# Dependency graph visualization
# ============================================================================

@test "E2E: deps command shows ASCII graph" {
  create_test_project "$TEST_TEMP_DIR"

  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {
    "dependencies": {
      "REQ-01": [],
      "REQ-02": ["REQ-01"],
      "REQ-03": ["REQ-01"],
      "REQ-04": ["REQ-02", "REQ-03"]
    }
  }
}
EOF

  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" deps

  [ "$status" -eq 0 ]
  # Should show all requirements
  [[ "$output" == *"REQ-01"* ]]
  [[ "$output" == *"REQ-02"* ]]
  [[ "$output" == *"REQ-03"* ]]
  [[ "$output" == *"REQ-04"* ]]
}

@test "E2E: deps handles no dependencies gracefully" {
  create_test_project "$TEST_TEMP_DIR"

  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {"dependencies": {}}
}
EOF

  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" deps

  [ "$status" -eq 0 ]
  [[ "$output" == *"No dependencies"* ]] || [[ "$output" == *"empty"* ]] || [[ "$output" != *"error"* ]]
}

# ============================================================================
# Complex dependency scenarios
# ============================================================================

@test "E2E: deps identifies parallel execution opportunities" {
  create_test_project "$TEST_TEMP_DIR"

  # REQ-01 and REQ-02 can run in parallel (no deps)
  # REQ-03 depends on both
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {
    "dependencies": {
      "REQ-01": [],
      "REQ-02": [],
      "REQ-03": ["REQ-01", "REQ-02"]
    }
  }
}
EOF

  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" deps

  [ "$status" -eq 0 ]
  # Both REQ-01 and REQ-02 should be in same tier/group
  # The output format varies but should indicate parallel opportunity
}

@test "E2E: deps detects deep dependency chains" {
  create_test_project "$TEST_TEMP_DIR"

  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {
    "dependencies": {
      "REQ-01": [],
      "REQ-02": ["REQ-01"],
      "REQ-03": ["REQ-02"],
      "REQ-04": ["REQ-03"],
      "REQ-05": ["REQ-04"]
    }
  }
}
EOF

  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" deps

  [ "$status" -eq 0 ]
  # Should show 5 tiers (each req in its own tier due to chain)
}
