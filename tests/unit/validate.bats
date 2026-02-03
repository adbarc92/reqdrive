#!/usr/bin/env bats
# Unit tests for lib/validate.sh (v0.2.0)

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
# Field display
# ============================================================================

@test "validate.sh shows configured requirementsDir" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"requirementsDir": "custom/requirements"}
EOF
  mkdir -p "$TEST_TEMP_DIR/custom/requirements"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"requirementsDir"* ]]
  [[ "$output" == *"custom/requirements"* ]]
}

@test "validate.sh shows configured testCommand" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"testCommand": "npm test"}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"testCommand"* ]]
  [[ "$output" == *"npm test"* ]]
}

@test "validate.sh shows configured model" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"model": "claude-opus-4-5-20251101"}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"model"* ]]
  [[ "$output" == *"claude-opus-4-5-20251101"* ]]
}

@test "validate.sh shows configured baseBranch" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"baseBranch": "develop"}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"baseBranch"* ]]
  [[ "$output" == *"develop"* ]]
}

# ============================================================================
# Path existence validation
# ============================================================================

@test "validate.sh warns when requirementsDir does not exist" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"requirementsDir": "nonexistent"}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  # Should warn but still pass
  [[ "$output" == *"WARN"* ]] || [[ "$output" == *"does not exist"* ]]
}

@test "validate.sh shows requirement file count" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01" "Feature 1"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-02" "Feature 2"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 requirement files"* ]]
}

# ============================================================================
# Default values
# ============================================================================

@test "validate.sh passes with minimal empty config" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Validation PASSED"* ]]
}

@test "validate.sh warns about missing fields" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{}
EOF
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  # Empty config should show warnings for unset fields
  [[ "$output" == *"WARN"* ]] || [[ "$output" == *"not set"* ]]
}
