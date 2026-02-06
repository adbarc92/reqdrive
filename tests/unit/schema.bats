#!/usr/bin/env bats
# Unit tests for lib/schema.sh (v0.3.0)

# Load test helpers
load '../test_helper/common'

# Try to load bats helpers if available
if [ -f "$BATS_TEST_DIRNAME/../test_helper/bats-support/load.bash" ]; then
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
fi

setup() {
  setup_temp_dir
  source "$REQDRIVE_ROOT/lib/schema.sh"
}

teardown() {
  teardown_temp_dir
}

# ============================================================================
# check_schema_version tests
# ============================================================================

@test "check_schema_version passes for correct version" {
  echo '{"version":"0.3.0"}' > "$TEST_TEMP_DIR/test.json"
  run check_schema_version "$TEST_TEMP_DIR/test.json"
  [ "$status" -eq 0 ]
}

@test "check_schema_version warns on missing version" {
  echo '{"requirementsDir":"docs"}' > "$TEST_TEMP_DIR/test.json"
  run check_schema_version "$TEST_TEMP_DIR/test.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No version field"* ]]
}

@test "check_schema_version errors on incompatible major version" {
  echo '{"version":"9.0.0"}' > "$TEST_TEMP_DIR/test.json"
  run check_schema_version "$TEST_TEMP_DIR/test.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Incompatible"* ]]
}

@test "check_schema_version passes for nonexistent file" {
  run check_schema_version "$TEST_TEMP_DIR/nonexistent.json"
  [ "$status" -eq 0 ]
}

# ============================================================================
# validate_config_schema tests
# ============================================================================

@test "validate_config_schema passes for valid config" {
  run validate_config_schema "$TEST_FIXTURES/valid-manifest.json"
  [ "$status" -eq 0 ]
}

@test "validate_config_schema fails for invalid JSON" {
  echo "not json" > "$TEST_TEMP_DIR/bad.json"
  run validate_config_schema "$TEST_TEMP_DIR/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid JSON"* ]]
}

@test "validate_config_schema fails for wrong types" {
  run validate_config_schema "$TEST_FIXTURES/invalid-manifest-missing-fields.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be"* ]]
}

@test "validate_config_schema passes for empty config" {
  echo '{}' > "$TEST_TEMP_DIR/empty.json"
  run validate_config_schema "$TEST_TEMP_DIR/empty.json"
  [ "$status" -eq 0 ]
}

# ============================================================================
# validate_prd_schema tests
# ============================================================================

@test "validate_prd_schema passes for valid PRD" {
  run validate_prd_schema "$TEST_FIXTURES/valid-prd.json"
  [ "$status" -eq 0 ]
}

@test "validate_prd_schema fails for missing userStories" {
  run validate_prd_schema "$TEST_FIXTURES/invalid-prd-missing-stories.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"userStories"* ]]
}

@test "validate_prd_schema fails for invalid JSON" {
  echo "not json" > "$TEST_TEMP_DIR/bad-prd.json"
  run validate_prd_schema "$TEST_TEMP_DIR/bad-prd.json"
  [ "$status" -eq 1 ]
}

@test "validate_prd_schema fails for stories missing required fields" {
  cat > "$TEST_TEMP_DIR/bad-stories.json" <<'EOF'
{
  "project": "Test",
  "sourceReq": "REQ-01",
  "userStories": [
    {"description": "no id or title"}
  ]
}
EOF
  run validate_prd_schema "$TEST_TEMP_DIR/bad-stories.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing id"* ]]
}

@test "validate_prd_schema fails for non-boolean passes" {
  cat > "$TEST_TEMP_DIR/bad-passes.json" <<'EOF'
{
  "project": "Test",
  "sourceReq": "REQ-01",
  "userStories": [
    {
      "id": "US-001",
      "title": "Test",
      "acceptanceCriteria": ["works"],
      "passes": "yes"
    }
  ]
}
EOF
  run validate_prd_schema "$TEST_TEMP_DIR/bad-passes.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"passes must be a boolean"* ]]
}

# ============================================================================
# validate_checkpoint_schema tests
# ============================================================================

@test "validate_checkpoint_schema passes for valid checkpoint" {
  run validate_checkpoint_schema "$TEST_FIXTURES/valid-checkpoint.json"
  [ "$status" -eq 0 ]
}

@test "validate_checkpoint_schema fails for missing fields" {
  echo '{"req_id": "REQ-01"}' > "$TEST_TEMP_DIR/bad-checkpoint.json"
  run validate_checkpoint_schema "$TEST_TEMP_DIR/bad-checkpoint.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required field"* ]]
}

@test "validate_checkpoint_schema fails for invalid JSON" {
  echo "not json" > "$TEST_TEMP_DIR/bad.json"
  run validate_checkpoint_schema "$TEST_TEMP_DIR/bad.json"
  [ "$status" -eq 1 ]
}

@test "validate_checkpoint_schema fails for non-number iteration" {
  cat > "$TEST_TEMP_DIR/bad-iter.json" <<'EOF'
{
  "req_id": "REQ-01",
  "branch": "reqdrive/req-01",
  "iteration": "three"
}
EOF
  run validate_checkpoint_schema "$TEST_TEMP_DIR/bad-iter.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"iteration must be a number"* ]]
}
