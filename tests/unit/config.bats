#!/usr/bin/env bats
# Unit tests for lib/config.sh (v0.2.0)

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
# reqdrive_find_manifest tests
# ============================================================================

@test "reqdrive_find_manifest finds manifest in current directory" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  result=$(reqdrive_find_manifest)

  [ "$result" = "$TEST_TEMP_DIR/reqdrive.json" ]
}

@test "reqdrive_find_manifest finds manifest in parent directory" {
  create_test_manifest "$TEST_TEMP_DIR"
  mkdir -p "$TEST_TEMP_DIR/subdir/nested"
  cd "$TEST_TEMP_DIR/subdir/nested"

  source "$REQDRIVE_ROOT/lib/config.sh"
  result=$(reqdrive_find_manifest)

  [ "$result" = "$TEST_TEMP_DIR/reqdrive.json" ]
}

@test "reqdrive_find_manifest fails when no manifest exists" {
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  run reqdrive_find_manifest

  [ "$status" -ne 0 ]
}

# ============================================================================
# reqdrive_load_config tests
# ============================================================================

@test "reqdrive_load_config sets REQDRIVE_MANIFEST and PROJECT_ROOT" {
  create_test_manifest "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_MANIFEST" = "$TEST_TEMP_DIR/reqdrive.json" ]
  [ "$REQDRIVE_PROJECT_ROOT" = "$TEST_TEMP_DIR" ]
}

@test "reqdrive_load_config loads requirementsDir" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"requirementsDir": "custom/reqs"}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_REQUIREMENTS_DIR" = "custom/reqs" ]
}

@test "reqdrive_load_config loads testCommand" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"testCommand": "pytest"}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_TEST_COMMAND" = "pytest" ]
}

@test "reqdrive_load_config loads model" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"model": "claude-opus-4-5-20251101"}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_MODEL" = "claude-opus-4-5-20251101" ]
}

@test "reqdrive_load_config loads maxIterations" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"maxIterations": 20}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_MAX_ITERATIONS" = "20" ]
}

@test "reqdrive_load_config loads baseBranch" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"baseBranch": "develop"}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_BASE_BRANCH" = "develop" ]
}

@test "reqdrive_load_config loads prLabels" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"prLabels": ["feature", "automated"]}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_PR_LABELS" = "feature,automated" ]
}

@test "reqdrive_load_config loads projectName" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{"projectName": "My Awesome Project"}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_PROJECT_NAME" = "My Awesome Project" ]
}

@test "reqdrive_load_config uses defaults for missing fields" {
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{}
EOF
  cd "$TEST_TEMP_DIR"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config

  [ "$REQDRIVE_REQUIREMENTS_DIR" = "docs/requirements" ]
  [ "$REQDRIVE_MODEL" = "claude-sonnet-4-20250514" ]
  [ "$REQDRIVE_MAX_ITERATIONS" = "10" ]
  [ "$REQDRIVE_BASE_BRANCH" = "main" ]
  [ "$REQDRIVE_PR_LABELS" = "agent-generated" ]
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
