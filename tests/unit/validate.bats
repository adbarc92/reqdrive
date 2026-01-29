#!/usr/bin/env bats
# Unit tests for lib/validate.sh

# Load test helpers
load '../test_helper/common'

# Try to load bats helpers if available
if [ -f "$BATS_TEST_DIRNAME/../test_helper/bats-support/load.bash" ]; then
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
fi

setup() {
  setup_temp_dir
  export REQDRIVE_ROOT
}

teardown() {
  teardown_temp_dir
}

# ============================================================================
# JSON syntax validation
# ============================================================================

@test "validate.sh passes for valid manifest" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Valid JSON"* ]]
  [[ "$output" == *"Validation PASSED"* ]]
}

@test "validate.sh fails for invalid JSON" {
  echo "{ invalid json }" > "$TEST_TEMP_DIR/reqdrive.json"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid JSON syntax"* ]]
}

# ============================================================================
# Required fields validation
# ============================================================================

@test "validate.sh fails when project.name is missing" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"}
}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required field"* ]]
  [[ "$output" == *"project.name"* ]]
}

@test "validate.sh fails when project.title is missing" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"}
}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required field"* ]]
  [[ "$output" == *"project.title"* ]]
}

@test "validate.sh fails when paths.requirementsDir is missing" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"agentDir": "agent"}
}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required field"* ]]
  [[ "$output" == *"requirementsDir"* ]]
}

@test "validate.sh fails when paths.agentDir is missing" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs"}
}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing required field"* ]]
  [[ "$output" == *"agentDir"* ]]
}

# ============================================================================
# Path existence validation
# ============================================================================

@test "validate.sh warns when requirementsDir does not exist" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "nonexistent", "agentDir": "agent"}
}
EOF
  mkdir -p "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  # Should warn but still pass (warning not error)
  [[ "$output" == *"WARN"* ]] || [[ "$output" == *"does not exist"* ]]
}

# ============================================================================
# Commands validation
# ============================================================================

@test "validate.sh shows configured commands" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [[ "$output" == *"install:"* ]]
  [[ "$output" == *"test:"* ]]
}

@test "validate.sh handles null commands" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "commands": {"install": null, "test": null}
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"disabled"* ]] || [[ "$output" == *"null"* ]]
}

# ============================================================================
# Dependencies validation
# ============================================================================

@test "validate.sh passes with valid dependencies" {
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
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"no circular dependencies"* ]]
}

@test "validate.sh fails on circular dependencies" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "requirements": {
    "dependencies": {
      "REQ-01": ["REQ-02"],
      "REQ-02": ["REQ-01"]
    }
  }
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Circular dependency"* ]]
}

@test "validate.sh fails when dependency references undefined requirement" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "requirements": {
    "dependencies": {
      "REQ-01": ["REQ-99"]
    }
  }
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"not defined"* ]]
}

# ============================================================================
# Security validation
# ============================================================================

@test "validate.sh accepts interactive security mode" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "security": {"mode": "interactive"}
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"interactive"* ]]
}

@test "validate.sh accepts allowlist security mode" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "security": {"mode": "allowlist", "allowedTools": ["Bash", "Read"]}
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowlist"* ]]
}

@test "validate.sh warns about dangerous security mode" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "security": {"mode": "dangerous"}
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"dangerous"* ]]
  [[ "$output" == *"UNRESTRICTED"* ]] || [[ "$output" == *"sandboxed"* ]]
}

@test "validate.sh fails on invalid security mode" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "security": {"mode": "invalid-mode"}
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid security.mode"* ]]
}

@test "validate.sh warns when allowlist mode has no tools" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "security": {"mode": "allowlist", "allowedTools": []}
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  # Should pass but warn
  [[ "$output" == *"WARN"* ]] || [[ "$output" == *"no allowedTools"* ]]
}

# ============================================================================
# Verification checks validation
# ============================================================================

@test "validate.sh shows verification check count" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "reqs", "agentDir": "agent"},
  "verification": {
    "checks": [
      {"name": "TypeScript", "command": "tsc"},
      {"name": "Tests", "command": "npm test"}
    ]
  }
}
EOF
  mkdir -p "$TEST_TEMP_DIR/reqs" "$TEST_TEMP_DIR/agent"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 verification checks"* ]]
}

@test "validate.sh handles no verification checks" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [[ "$output" == *"No verification checks"* ]] || [[ "$output" == *"will use commands"* ]]
}
