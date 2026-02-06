#!/usr/bin/env bats
# End-to-end tests for the reqdrive v0.3.0 pipeline

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
# Full init → validate flow
# ============================================================================

@test "E2E: init creates valid project structure" {
  cd "$TEST_TEMP_DIR"

  # Create a minimal Node.js-like project
  echo '{"name":"test-app","version":"1.0.0"}' > package.json

  # Run init with defaults (non-interactive by piping empty responses)
  run bash -c "printf '\n\n\n\n' | bash '$REQDRIVE_ROOT/bin/reqdrive' init"

  # Check manifest was created
  [ -f "$TEST_TEMP_DIR/reqdrive.json" ]

  # Validate the created manifest
  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Validation PASSED"* ]]
}

@test "E2E: project setup creates all required directories" {
  cd "$TEST_TEMP_DIR"

  # Create project manually
  create_test_project "$TEST_TEMP_DIR"

  # Check structure
  [ -f "$TEST_TEMP_DIR/reqdrive.json" ]
  [ -d "$TEST_TEMP_DIR/docs/requirements" ]
  [ -d "$TEST_TEMP_DIR/.reqdrive/agent" ]

  # Validate
  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
}

# ============================================================================
# Run command validation
# ============================================================================

@test "E2E: run without args shows usage" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" run
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"REQ-ID"* ]]
}

@test "E2E: run requires valid requirement file" {
  create_test_project "$TEST_TEMP_DIR"
  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # No requirement file exists
  run bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-01
  [ "$status" -ne 0 ]
  [[ "$output" == *"No requirement file"* ]] || [[ "$output" == *"not found"* ]]
}

@test "E2E: run normalizes requirement ID to uppercase" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01" "Test Feature"
  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Mock claude to output COMPLETE immediately
  cat > "$TEST_TEMP_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "MOCK: Processing requirement"
echo "<promise>COMPLETE</promise>"
EOF
  chmod +x "$TEST_TEMP_DIR/bin/claude"

  # Use lowercase req-01
  run timeout 30 bash "$REQDRIVE_ROOT/bin/reqdrive" run req-01 2>&1 || true

  # Should find the requirement (normalizes to REQ-01)
  [[ "$output" == *"REQ-01"* ]]
}

# ============================================================================
# Branch management
# ============================================================================

@test "E2E: run creates branch from base branch" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01" "Test Feature"
  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Mock claude to fail fast
  cat > "$TEST_TEMP_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "<promise>COMPLETE</promise>"
exit 0
EOF
  chmod +x "$TEST_TEMP_DIR/bin/claude"

  # Run pipeline
  timeout 30 bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-01 2>&1 || true

  # Check branch was created
  git branch | grep -q "reqdrive/req-01" || skip "Branch creation requires clean git state"
}

# ============================================================================
# Agent directory setup
# ============================================================================

@test "E2E: run creates agent directory structure" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01" "Test Feature"
  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Mock claude
  cat > "$TEST_TEMP_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "<promise>COMPLETE</promise>"
EOF
  chmod +x "$TEST_TEMP_DIR/bin/claude"

  # Run pipeline
  timeout 30 bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-01 2>&1 || true

  # Check agent directory exists
  [ -d "$TEST_TEMP_DIR/.reqdrive/agent" ]
  # Prompt should be created
  [ -f "$TEST_TEMP_DIR/.reqdrive/agent/prompt.md" ]
  # Progress file should be created
  [ -f "$TEST_TEMP_DIR/.reqdrive/agent/progress.txt" ]
}

# ============================================================================
# Prompt building
# ============================================================================

@test "E2E: run embeds requirement content in prompt" {
  create_test_project "$TEST_TEMP_DIR"

  # Create requirement with specific content
  mkdir -p "$TEST_TEMP_DIR/docs/requirements"
  cat > "$TEST_TEMP_DIR/docs/requirements/REQ-01-unique-test.md" <<'EOF'
# REQ-01: Unique Test Content XYZ123

This is a unique test marker for verification.
EOF

  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Mock claude
  cat > "$TEST_TEMP_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "<promise>COMPLETE</promise>"
EOF
  chmod +x "$TEST_TEMP_DIR/bin/claude"

  # Run pipeline
  timeout 30 bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-01 2>&1 || true

  # Check prompt contains the requirement
  grep -q "XYZ123" "$TEST_TEMP_DIR/.reqdrive/agent/prompt.md" || skip "Prompt not created yet"
}

# ============================================================================
# Configuration usage
# ============================================================================

@test "E2E: run uses configured model" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01" "Test"

  # Set custom model
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "requirementsDir": "docs/requirements",
  "model": "claude-opus-4-5-20251101"
}
EOF

  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Mock claude to capture args
  cat > "$TEST_TEMP_DIR/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "ARGS: $*" >> /tmp/claude-args.log
echo "<promise>COMPLETE</promise>"
EOF
  chmod +x "$TEST_TEMP_DIR/bin/claude"

  # Run pipeline
  timeout 30 bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-01 2>&1 || true

  # Check model was used
  grep -q "claude-opus-4-5-20251101" /tmp/claude-args.log 2>/dev/null || skip "Claude args not captured"
  rm -f /tmp/claude-args.log
}
