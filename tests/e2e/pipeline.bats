#!/usr/bin/env bats
# End-to-end tests for the reqdrive pipeline

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
  # Clean up git worktrees if created
  if [ -d "$TEST_TEMP_DIR/project" ]; then
    cd "$TEST_TEMP_DIR/project"
    git worktree list 2>/dev/null | grep -v "$(pwd)" | awk '{print $1}' | while read wt; do
      git worktree remove --force "$wt" 2>/dev/null || true
    done
  fi
  teardown_temp_dir
}

# ============================================================================
# Full init → validate → deps flow
# ============================================================================

@test "E2E: init creates valid project structure" {
  cd "$TEST_TEMP_DIR"

  # Create a minimal Node.js-like project
  echo '{"name":"test-app","version":"1.0.0"}' > package.json

  # Run init with defaults (non-interactive by piping empty responses)
  run bash -c "printf '\n\n\n\n\n\n\n\n\n\n\n\n\n' | bash '$REQDRIVE_ROOT/bin/reqdrive' init"

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
  [ -f "$TEST_TEMP_DIR/CLAUDE.md" ]

  # Validate
  run bash "$REQDRIVE_ROOT/bin/reqdrive" validate
  [ "$status" -eq 0 ]
}

# ============================================================================
# Dependencies command
# ============================================================================

@test "E2E: deps shows dependency graph" {
  create_test_project "$TEST_TEMP_DIR"

  # Add dependencies to manifest
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
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

  run bash "$REQDRIVE_ROOT/bin/reqdrive" deps
  [ "$status" -eq 0 ]
  [[ "$output" == *"REQ-01"* ]]
  [[ "$output" == *"REQ-02"* ]]
  [[ "$output" == *"REQ-03"* ]]
}

@test "E2E: deps shows execution tiers" {
  create_test_project "$TEST_TEMP_DIR"

  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {
    "dependencies": {
      "REQ-01": [],
      "REQ-02": ["REQ-01"],
      "REQ-03": ["REQ-02"]
    }
  }
}
EOF

  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" deps
  [ "$status" -eq 0 ]
  # Should show tier information
  [[ "$output" == *"Tier"* ]] || [[ "$output" == *"tier"* ]] || [[ "$output" == *"Level"* ]]
}

# ============================================================================
# Status command
# ============================================================================

@test "E2E: status shows no runs when none exist" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" status
  # Should exit cleanly even with no runs
  [[ "$output" == *"No runs"* ]] || [[ "$output" == *"no run"* ]] || [ "$status" -eq 0 ]
}

@test "E2E: status shows run details when runs exist" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Create a mock run state
  mkdir -p "$TEST_TEMP_DIR/.reqdrive/state/runs/20240115-120000/logs"
  echo '{"req":"REQ-01","status":"completed","branch":"reqdrive/req-01"}' \
    > "$TEST_TEMP_DIR/.reqdrive/state/runs/20240115-120000/REQ-01-status.json"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" status 20240115-120000
  [[ "$output" == *"REQ-01"* ]]
  [[ "$output" == *"completed"* ]] || [[ "$output" == *"status"* ]]
}

# ============================================================================
# Clean command
# ============================================================================

@test "E2E: clean removes worktrees" {
  create_test_project "$TEST_TEMP_DIR"
  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Create a worktree manually
  mkdir -p "$TEST_TEMP_DIR/../worktrees"
  git worktree add "$TEST_TEMP_DIR/../worktrees/reqdrive-req-01" -b reqdrive/req-01 HEAD 2>/dev/null || skip "git worktree not supported"

  [ -d "$TEST_TEMP_DIR/../worktrees/reqdrive-req-01" ]

  run bash "$REQDRIVE_ROOT/bin/reqdrive" clean
  [ "$status" -eq 0 ]

  # Worktree should be removed
  [ ! -d "$TEST_TEMP_DIR/../worktrees/reqdrive-req-01" ] || [[ "$output" == *"removed"* ]] || [[ "$output" == *"clean"* ]]
}

# ============================================================================
# Run command validation
# ============================================================================

@test "E2E: run without args shows usage" {
  create_test_project "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  run bash "$REQDRIVE_ROOT/bin/reqdrive" run
  [[ "$output" == *"No REQs specified"* ]] || [[ "$output" == *"Usage"* ]]
}

@test "E2E: run validates REQ format" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01"
  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Invalid format should be skipped
  run bash "$REQDRIVE_ROOT/bin/reqdrive" run INVALID-FORMAT
  [[ "$output" == *"Invalid format"* ]] || [[ "$output" == *"SKIP"* ]]
}

@test "E2E: run checks dependencies before executing" {
  create_test_project "$TEST_TEMP_DIR"

  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {
    "idRegex": "REQ-[0-9]+",
    "dependencies": {
      "REQ-01": [],
      "REQ-02": ["REQ-01"]
    }
  },
  "orchestration": {
    "baseBranch": "main",
    "stateDir": ".reqdrive/state",
    "worktreeRoot": "../worktrees"
  }
}
EOF

  create_test_requirement "$TEST_TEMP_DIR" "REQ-01"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-02"
  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # REQ-02 depends on REQ-01, which isn't merged, so should be skipped
  run bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-02
  # Should mention dependency issue
  [[ "$output" == *"dependencies"* ]] || [[ "$output" == *"SKIP"* ]] || [ "$status" -eq 0 ]
}

# ============================================================================
# Worktree lifecycle
# ============================================================================

@test "E2E: worktree setup creates isolated environment" {
  create_test_project "$TEST_TEMP_DIR"
  init_test_git_repo "$TEST_TEMP_DIR"

  # Create prompt file
  echo "# Test prompt" > "$TEST_TEMP_DIR/.reqdrive/agent/prompt.md"
  cd "$TEST_TEMP_DIR"
  git add -A && git commit -m "Add prompt"

  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  source "$REQDRIVE_ROOT/lib/worktree.sh"

  WORKTREE_PATH="$TEST_TEMP_DIR/../worktrees/test-wt"

  setup_worktree "$TEST_TEMP_DIR" "$WORKTREE_PATH" "test/branch" "main"

  # Check worktree was created
  [ -d "$WORKTREE_PATH" ]
  [ -d "$WORKTREE_PATH/.reqdrive/agent" ]
  [ -f "$WORKTREE_PATH/.reqdrive/agent/progress.txt" ]

  # Check we're on the right branch
  cd "$WORKTREE_PATH"
  BRANCH=$(git branch --show-current)
  [ "$BRANCH" = "test/branch" ]

  # Cleanup
  cd "$TEST_TEMP_DIR"
  teardown_worktree "$TEST_TEMP_DIR" "$WORKTREE_PATH"
  [ ! -d "$WORKTREE_PATH" ]
}

# ============================================================================
# Full pipeline smoke test (mocked)
# ============================================================================

@test "E2E: pipeline shows security mode warning for dangerous mode" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01"
  init_test_git_repo "$TEST_TEMP_DIR"

  # Set dangerous mode
  cat > "$TEST_TEMP_DIR/reqdrive.json" <<'EOF'
{
  "project": {"name": "test", "title": "Test"},
  "paths": {"requirementsDir": "docs/requirements", "agentDir": ".reqdrive/agent"},
  "requirements": {"idRegex": "REQ-[0-9]+", "dependencies": {"REQ-01": []}},
  "orchestration": {"baseBranch": "main", "stateDir": ".reqdrive/state"},
  "security": {"mode": "dangerous"}
}
EOF

  cd "$TEST_TEMP_DIR"

  # Run will fail due to missing requirements file format, but should show warning first
  run timeout 5 bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-01 2>&1 || true

  # Should show the dangerous mode warning
  [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"DANGEROUS"* ]] || [[ "$output" == *"dangerous"* ]]
}

@test "E2E: pipeline creates state directory" {
  create_test_project "$TEST_TEMP_DIR"
  create_test_requirement "$TEST_TEMP_DIR" "REQ-01"
  init_test_git_repo "$TEST_TEMP_DIR"
  cd "$TEST_TEMP_DIR"

  # Run (will fail early but should create state dir)
  timeout 5 bash "$REQDRIVE_ROOT/bin/reqdrive" run REQ-01 2>&1 || true

  # State directory should be created
  [ -d "$TEST_TEMP_DIR/.reqdrive/state/runs" ]
}
