#!/usr/bin/env bash
# setup-validation-env.sh — Set up isolated environment for reqdrive validation
# Usage: ./scripts/setup-validation-env.sh [target-dir]

set -e

TARGET_DIR="${1:-$HOME/reqdrive-validation}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQDRIVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "  reqdrive Validation Environment Setup"
echo "=========================================="
echo ""
echo "Target directory: $TARGET_DIR"
echo "reqdrive location: $REQDRIVE_ROOT"
echo ""

# ── Check Prerequisites ───────────────────────────────────────────────
echo "=== Checking Prerequisites ==="

check_command() {
  if command -v "$1" &>/dev/null; then
    echo "✓ $1 found: $(command -v "$1")"
    return 0
  else
    echo "✗ $1 NOT FOUND"
    return 1
  fi
}

PREREQ_OK=true
check_command bash || PREREQ_OK=false
check_command git || PREREQ_OK=false
check_command jq || PREREQ_OK=false
check_command node || PREREQ_OK=false
check_command npm || PREREQ_OK=false

echo ""
echo "Optional (for full validation):"
check_command gh || echo "  (GitHub CLI - needed for PR creation)"
check_command claude || echo "  (Claude CLI - needed for actual validation)"

if [ "$PREREQ_OK" = false ]; then
  echo ""
  echo "ERROR: Missing required prerequisites. Install them and retry."
  exit 1
fi

# ── Create Directory Structure ────────────────────────────────────────
echo ""
echo "=== Creating Directory Structure ==="

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# ── Create Test Project ───────────────────────────────────────────────
echo ""
echo "=== Creating Test Project ==="

if [ -d "test-project" ]; then
  echo "test-project already exists. Remove it? (y/N)"
  read -r response
  if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
    rm -rf test-project
  else
    echo "Keeping existing project."
    cd test-project
    export REQDRIVE_ROOT
    echo ""
    echo "Setup complete. REQDRIVE_ROOT=$REQDRIVE_ROOT"
    exit 0
  fi
fi

mkdir -p test-project/src test-project/tests
cd test-project

# Initialize git
git init
git config user.email "validation@reqdrive.local"
git config user.name "reqdrive Validation"

# Create package.json
cat > package.json << 'PACKAGE_EOF'
{
  "name": "reqdrive-validation-project",
  "version": "1.0.0",
  "description": "Test project for reqdrive validation",
  "type": "module",
  "scripts": {
    "test": "node --test tests/*.js"
  }
}
PACKAGE_EOF

# Create initial source
cat > src/math.js << 'SRC_EOF'
// Math utilities

export function add(a, b) {
  return a + b;
}
SRC_EOF

# Create initial test
cat > tests/math.test.js << 'TEST_EOF'
import { test } from 'node:test';
import assert from 'node:assert';
import { add } from '../src/math.js';

test('add returns sum of two numbers', () => {
  assert.strictEqual(add(2, 3), 5);
});
TEST_EOF

# Create CLAUDE.md
cat > CLAUDE.md << 'CLAUDE_EOF'
# Validation Test Project

A minimal Node.js project for validating reqdrive.

## Structure
- `src/math.js` - Math utility functions
- `tests/*.js` - Tests using Node.js test runner

## Commands
- `npm test` - Run tests

## Conventions
- Use ES modules (import/export)
- Export all public functions
- Follow existing code patterns
CLAUDE_EOF

# Verify tests work
echo ""
echo "Verifying tests..."
npm test

# Initial commit
git add -A
git commit -m "Initial commit: minimal test project"

echo ""
echo "✓ Test project created"

# ── Initialize reqdrive ───────────────────────────────────────────────
echo ""
echo "=== Initializing reqdrive ==="

mkdir -p docs/requirements .reqdrive/agent

# Create manifest
cat > reqdrive.json << 'MANIFEST_EOF'
{
  "project": {
    "name": "validation-project",
    "title": "Validation Test Project"
  },
  "paths": {
    "requirementsDir": "docs/requirements",
    "agentDir": ".reqdrive/agent",
    "appDir": ".",
    "contextFile": "CLAUDE.md"
  },
  "requirements": {
    "pattern": "REQ-*-*.md",
    "idRegex": "REQ-[0-9]+",
    "dependencies": {}
  },
  "commands": {
    "install": null,
    "test": "npm test",
    "typecheck": null,
    "lint": null
  },
  "agent": {
    "model": "claude-sonnet-4-20250514",
    "maxIterations": 3,
    "branchPrefix": "reqdrive",
    "worktreePrefix": "reqdrive",
    "completionSignal": "<promise>COMPLETE</promise>"
  },
  "verification": {
    "maxRetries": 2,
    "checks": [
      {"name": "Tests", "command": "npm test"}
    ],
    "generateTests": true
  },
  "pr": {
    "labels": ["validation-test"],
    "reqLabel": true,
    "setupSteps": [],
    "regressionChecks": [],
    "footer": "Validation test PR"
  },
  "orchestration": {
    "maxParallel": 1,
    "worktreeRoot": "../worktrees",
    "baseBranch": "main",
    "stateDir": ".reqdrive/state"
  },
  "security": {
    "mode": "dangerous"
  }
}
MANIFEST_EOF

# Copy agent prompt
cp "$REQDRIVE_ROOT/templates/prompt.md.tpl" .reqdrive/agent/prompt.md

# Create sample requirement
cat > docs/requirements/REQ-01-subtract.md << 'REQ_EOF'
# REQ-01: Subtract Function

## Overview
Add a subtract function to the math utilities.

## Functional Requirements
- Create a `subtract(a, b)` function that returns `a - b`
- The function should be exported from `src/math.js`
- Handle negative numbers correctly

## Acceptance Criteria
- [ ] `subtract(5, 3)` returns `2`
- [ ] `subtract(3, 5)` returns `-2`
- [ ] `subtract(-1, -1)` returns `0`
- [ ] Function is exported from src/math.js
- [ ] Unit tests exist and pass
REQ_EOF

# Commit setup
git add -A
git commit -m "Add reqdrive configuration and REQ-01"

echo "✓ reqdrive initialized"

# ── Create Helper Script ──────────────────────────────────────────────
cat > run-validation.sh << 'HELPER_EOF'
#!/usr/bin/env bash
# Quick validation runner

set -e

if [ -z "$REQDRIVE_ROOT" ]; then
  echo "ERROR: REQDRIVE_ROOT not set"
  echo "Run: export REQDRIVE_ROOT=/path/to/reqdrive"
  exit 1
fi

source "$REQDRIVE_ROOT/lib/config.sh"
source "$REQDRIVE_ROOT/lib/errors.sh"
reqdrive_load_config

PHASE="${1:-all}"

case "$PHASE" in
  1.1|prd)
    echo "=== Phase 1.1: PRD Generation ==="
    source "$REQDRIVE_ROOT/lib/prd-gen.sh"
    generate_prd "docs/requirements/REQ-01-subtract.md" "." "claude-sonnet-4-20250514" 300
    echo ""
    echo "Result:"
    [ -f .reqdrive/agent/prd.json ] && jq . .reqdrive/agent/prd.json || echo "FAILED"
    ;;
  1.2|agent)
    echo "=== Phase 1.2: Agent Iteration ==="
    source "$REQDRIVE_ROOT/lib/agent-run.sh"
    run_agent "." 1 "claude-sonnet-4-20250514" 300
    ;;
  1.3|verify)
    echo "=== Phase 1.3: Verification ==="
    source "$REQDRIVE_ROOT/lib/verify.sh"
    run_verification "." "claude-sonnet-4-20250514" 300
    ;;
  all)
    echo "Run individual phases:"
    echo "  ./run-validation.sh 1.1   # PRD Generation"
    echo "  ./run-validation.sh 1.2   # Agent Iteration"
    echo "  ./run-validation.sh 1.3   # Verification"
    ;;
  *)
    echo "Unknown phase: $PHASE"
    echo "Valid: 1.1, 1.2, 1.3, prd, agent, verify, all"
    exit 1
    ;;
esac
HELPER_EOF

chmod +x run-validation.sh

# ── Validate Setup ────────────────────────────────────────────────────
echo ""
echo "=== Validating Setup ==="

source "$REQDRIVE_ROOT/lib/config.sh"
reqdrive_load_config_path
source "$REQDRIVE_ROOT/lib/validate.sh" 2>&1 | tail -5

# ── Print Summary ─────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo ""
echo "Test project: $PWD"
echo ""
echo "To use:"
echo "  export REQDRIVE_ROOT=\"$REQDRIVE_ROOT\""
echo "  cd \"$PWD\""
echo ""
echo "Run validation phases:"
echo "  ./run-validation.sh 1.1   # Test PRD generation"
echo "  ./run-validation.sh 1.2   # Test agent iteration"
echo "  ./run-validation.sh 1.3   # Test verification"
echo ""
echo "Or run full pipeline:"
echo "  source \"\$REQDRIVE_ROOT/lib/config.sh\""
echo "  source \"\$REQDRIVE_ROOT/lib/errors.sh\""
echo "  reqdrive_load_config"
echo "  # Then run individual components..."
echo ""
echo "See docs/PHASE1-VALIDATION-GUIDE.md for detailed instructions."
