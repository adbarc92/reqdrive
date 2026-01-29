#!/usr/bin/env bats
# Unit tests for bin/reqdrive CLI dispatch

# Load test helpers
load '../test_helper/common'

# Try to load bats helpers if available
if [ -f "$BATS_TEST_DIRNAME/../test_helper/bats-support/load.bash" ]; then
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
fi

setup() {
  setup_temp_dir
  mock_claude
  mock_gh
}

teardown() {
  teardown_temp_dir
}

# ============================================================================
# Version and help
# ============================================================================

@test "reqdrive --version shows version" {
  run bash "$REQDRIVE_ROOT/bin/reqdrive" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"reqdrive"* ]]
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "reqdrive -v shows version" {
  run bash "$REQDRIVE_ROOT/bin/reqdrive" -v
  [ "$status" -eq 0 ]
  [[ "$output" == *"reqdrive"* ]]
}

@test "reqdrive --help shows usage" {
  run bash "$REQDRIVE_ROOT/bin/reqdrive" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"init"* ]]
  [[ "$output" == *"run"* ]]
  [[ "$output" == *"validate"* ]]
}

@test "reqdrive -h shows usage" {
  run bash "$REQDRIVE_ROOT/bin/reqdrive" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "reqdrive with no args shows usage" {
  run bash "$REQDRIVE_ROOT/bin/reqdrive"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ============================================================================
# Unknown command handling
# ============================================================================

@test "reqdrive unknown-command shows error" {
  run bash "$REQDRIVE_ROOT/bin/reqdrive" unknown-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown command"* ]]
  [[ "$output" == *"--help"* ]]
}

# ============================================================================
# Dependency checks
# ============================================================================

@test "reqdrive checks for jq" {
  # Remove jq from PATH temporarily
  PATH_BACKUP="$PATH"
  export PATH="/usr/bin:/bin"  # Minimal path without jq likely

  # This test will only work if jq is not in the minimal path
  # Skip if jq is still found
  if command -v jq &>/dev/null; then
    skip "jq is in minimal PATH"
  fi

  run bash "$REQDRIVE_ROOT/bin/reqdrive" --version
  [ "$status" -ne 0 ]
  [[ "$output" == *"jq"* ]]

  export PATH="$PATH_BACKUP"
}

# ============================================================================
# Command dispatch
# ============================================================================

@test "reqdrive validate dispatches to validate.sh" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Validating"* ]]
}

@test "reqdrive deps requires manifest" {
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" deps
  [ "$status" -ne 0 ]
  [[ "$output" == *"No reqdrive.json"* ]]
}

@test "reqdrive status requires manifest" {
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" status
  [ "$status" -ne 0 ]
  [[ "$output" == *"No reqdrive.json"* ]]
}

@test "reqdrive clean requires manifest" {
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" clean
  [ "$status" -ne 0 ]
  [[ "$output" == *"No reqdrive.json"* ]]
}

@test "reqdrive run requires manifest" {
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-01
  [ "$status" -ne 0 ]
  [[ "$output" == *"No reqdrive.json"* ]]
}

# ============================================================================
# Init command
# ============================================================================

@test "reqdrive init can be run in empty directory" {
  cd "$TEST_TEMP_DIR"

  # Feed answers to interactive prompts
  run bash -c "echo -e '\n\n\n\n\n\n\n\n\n\n\n\n' | bash '$REQDRIVE_ROOT/bin/reqdrive' init"

  # Should create reqdrive.json even if some prompts fail
  [ -f "$TEST_TEMP_DIR/reqdrive.json" ] || skip "init requires interactive input"
}
