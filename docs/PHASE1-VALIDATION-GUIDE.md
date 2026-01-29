# Phase 1 Validation Guide

A step-by-step guide to validating reqdrive components against real Claude execution.

## Overview

**Time Required:** 30-60 minutes
**Prerequisites:** Git Bash or WSL, Claude CLI authenticated
**Risk Level:** Low (isolated test project, no production code)

---

## Step 1: Set Up Isolated Environment

### Option A: Dedicated Directory (Simpler)

```bash
# Create isolated workspace
mkdir -p ~/reqdrive-validation
cd ~/reqdrive-validation

# Clone reqdrive (or use existing)
git clone https://github.com/adbarc92/reqdrive.git
export REQDRIVE_ROOT="$PWD/reqdrive"

# Verify
echo "REQDRIVE_ROOT=$REQDRIVE_ROOT"
ls "$REQDRIVE_ROOT/bin/reqdrive"
```

### Option B: Docker Container (More Isolated)

```dockerfile
# Save as Dockerfile.validation
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    bash \
    git \
    jq \
    curl \
    nodejs \
    npm

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh

# Install Claude CLI (adjust as needed)
RUN npm install -g @anthropic-ai/claude-code

WORKDIR /workspace
```

```bash
# Build and run
docker build -f Dockerfile.validation -t reqdrive-validation .
docker run -it -v ~/reqdrive-validation:/workspace reqdrive-validation bash
```

---

## Step 2: Create Test Project

```bash
cd ~/reqdrive-validation

# Create minimal Node.js project
mkdir -p test-project/src test-project/tests
cd test-project

# Initialize git
git init
git config user.email "test@example.com"
git config user.name "Test User"

# Create package.json
cat > package.json << 'EOF'
{
  "name": "reqdrive-validation-project",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "test": "node --test tests/*.js"
  }
}
EOF

# Create initial source file
cat > src/math.js << 'EOF'
// Math utilities

export function add(a, b) {
  return a + b;
}
EOF

# Create initial test
cat > tests/math.test.js << 'EOF'
import { test } from 'node:test';
import assert from 'node:assert';
import { add } from '../src/math.js';

test('add returns sum of two numbers', () => {
  assert.strictEqual(add(2, 3), 5);
});
EOF

# Create CLAUDE.md context file
cat > CLAUDE.md << 'EOF'
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
- One test file per source file
EOF

# Verify tests work
npm test

# Initial commit
git add -A
git commit -m "Initial commit: minimal test project"

echo ""
echo "✓ Test project created at $PWD"
```

---

## Step 3: Initialize reqdrive

```bash
cd ~/reqdrive-validation/test-project

# Create reqdrive configuration manually (for control)
mkdir -p docs/requirements .reqdrive/agent

# Create manifest with validation-friendly settings
cat > reqdrive.json << 'EOF'
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
EOF

# Copy agent prompt template
cp "$REQDRIVE_ROOT/templates/prompt.md.tpl" .reqdrive/agent/prompt.md

# Commit reqdrive setup
git add -A
git commit -m "Add reqdrive configuration"

# Validate configuration
source "$REQDRIVE_ROOT/lib/config.sh"
source "$REQDRIVE_ROOT/lib/errors.sh"
reqdrive_load_config_path
source "$REQDRIVE_ROOT/lib/validate.sh"

echo ""
echo "✓ reqdrive initialized"
```

---

## Step 4: Validate PRD Generation (Phase 1.1)

### 4.1 Create Test Requirement

```bash
cd ~/reqdrive-validation/test-project

cat > docs/requirements/REQ-01-subtract.md << 'EOF'
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
EOF

git add -A
git commit -m "Add REQ-01 requirement"
```

### 4.2 Run PRD Generation

```bash
cd ~/reqdrive-validation/test-project

# Load reqdrive
source "$REQDRIVE_ROOT/lib/config.sh"
source "$REQDRIVE_ROOT/lib/errors.sh"
reqdrive_load_config

# Set log level for visibility
export REQDRIVE_LOG_LEVEL=debug

# Run PRD generation
source "$REQDRIVE_ROOT/lib/prd-gen.sh"

echo "=== Starting PRD Generation ==="
echo "Requirement: docs/requirements/REQ-01-subtract.md"
echo "Output: .reqdrive/agent/prd.json"
echo ""

generate_prd \
  "docs/requirements/REQ-01-subtract.md" \
  "." \
  "claude-sonnet-4-20250514" \
  300

PRD_STATUS=$?
echo ""
echo "=== PRD Generation Complete ==="
echo "Exit status: $PRD_STATUS"
```

### 4.3 Validate PRD Output

```bash
cd ~/reqdrive-validation/test-project

echo "=== PRD Validation ==="

# Check file exists
if [ -f ".reqdrive/agent/prd.json" ]; then
  echo "✓ prd.json exists"
else
  echo "✗ prd.json NOT FOUND"
  echo "  Check .reqdrive/agent/prd-gen.log for details"
  exit 1
fi

# Check valid JSON
if jq empty .reqdrive/agent/prd.json 2>/dev/null; then
  echo "✓ Valid JSON"
else
  echo "✗ Invalid JSON"
  echo "  Content:"
  cat .reqdrive/agent/prd.json
  exit 1
fi

# Check required fields
echo ""
echo "=== PRD Structure ==="

PROJECT=$(jq -r '.project // "MISSING"' .reqdrive/agent/prd.json)
SOURCE_REQ=$(jq -r '.sourceReq // "MISSING"' .reqdrive/agent/prd.json)
BRANCH=$(jq -r '.branchName // "MISSING"' .reqdrive/agent/prd.json)
STORY_COUNT=$(jq '.userStories | length' .reqdrive/agent/prd.json)

echo "Project: $PROJECT"
echo "Source REQ: $SOURCE_REQ"
echo "Branch: $BRANCH"
echo "Story Count: $STORY_COUNT"

# Validate
[ "$PROJECT" != "MISSING" ] && echo "✓ Has project" || echo "✗ Missing project"
[ "$SOURCE_REQ" != "MISSING" ] && echo "✓ Has sourceReq" || echo "✗ Missing sourceReq"
[ "$BRANCH" != "MISSING" ] && echo "✓ Has branchName" || echo "✗ Missing branchName"
[ "$STORY_COUNT" -gt 0 ] && echo "✓ Has stories ($STORY_COUNT)" || echo "✗ No stories"

# Show stories
echo ""
echo "=== User Stories ==="
jq -r '.userStories[] | "- \(.id): \(.title) [passes=\(.passes)]"' .reqdrive/agent/prd.json

# Validate story structure
echo ""
echo "=== Story Structure Validation ==="
INVALID=$(jq '[.userStories[] | select(.id == null or .title == null or .acceptanceCriteria == null or .passes == null)] | length' .reqdrive/agent/prd.json)
if [ "$INVALID" -eq 0 ]; then
  echo "✓ All stories have required fields"
else
  echo "✗ $INVALID stories missing required fields"
fi

# Check all stories start with passes=false
ALREADY_PASSING=$(jq '[.userStories[] | select(.passes == true)] | length' .reqdrive/agent/prd.json)
if [ "$ALREADY_PASSING" -eq 0 ]; then
  echo "✓ All stories start with passes=false"
else
  echo "⚠ $ALREADY_PASSING stories already marked as passing"
fi

echo ""
echo "=== Phase 1.1 Result ==="
if [ "$STORY_COUNT" -gt 0 ] && [ "$INVALID" -eq 0 ]; then
  echo "✓ PRD GENERATION: PASSED"
else
  echo "✗ PRD GENERATION: FAILED"
fi
```

### 4.4 Record Results

```bash
# Save validation results
cat > .reqdrive/validation-1.1.json << EOF
{
  "phase": "1.1",
  "component": "PRD Generation",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "$([ -f .reqdrive/agent/prd.json ] && echo 'passed' || echo 'failed')",
  "prd_file": ".reqdrive/agent/prd.json",
  "story_count": $(jq '.userStories | length' .reqdrive/agent/prd.json 2>/dev/null || echo 0),
  "notes": ""
}
EOF

echo "Results saved to .reqdrive/validation-1.1.json"
```

---

## Step 5: Validate Agent Iteration (Phase 1.2)

### 5.1 Prepare for Agent Run

```bash
cd ~/reqdrive-validation/test-project

# Ensure we have a valid PRD from Step 4
if [ ! -f ".reqdrive/agent/prd.json" ]; then
  echo "ERROR: No PRD found. Complete Step 4 first."
  exit 1
fi

# Create progress file
echo "# Agent Progress Log" > .reqdrive/agent/progress.txt
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> .reqdrive/agent/progress.txt
echo "---" >> .reqdrive/agent/progress.txt

# Show current state
echo "=== Pre-Agent State ==="
echo "Stories to implement:"
jq -r '.userStories[] | select(.passes == false) | "  - \(.id): \(.title)"' .reqdrive/agent/prd.json
echo ""
echo "Current src/math.js:"
cat src/math.js
```

### 5.2 Run Single Agent Iteration

```bash
cd ~/reqdrive-validation/test-project

source "$REQDRIVE_ROOT/lib/config.sh"
source "$REQDRIVE_ROOT/lib/errors.sh"
reqdrive_load_config

export REQDRIVE_LOG_LEVEL=info

source "$REQDRIVE_ROOT/lib/agent-run.sh"

echo "=== Starting Agent (1 iteration) ==="
echo ""

# Run just ONE iteration to see what happens
run_agent "." 1 "claude-sonnet-4-20250514" 300

AGENT_STATUS=$?
echo ""
echo "=== Agent Complete ==="
echo "Exit status: $AGENT_STATUS"
```

### 5.3 Validate Agent Results

```bash
cd ~/reqdrive-validation/test-project

echo "=== Post-Agent Validation ==="

# Check if any stories were completed
COMPLETED=$(jq '[.userStories[] | select(.passes == true)] | length' .reqdrive/agent/prd.json)
REMAINING=$(jq '[.userStories[] | select(.passes == false)] | length' .reqdrive/agent/prd.json)

echo "Stories completed: $COMPLETED"
echo "Stories remaining: $REMAINING"

# Check if code was modified
echo ""
echo "=== Code Changes ==="
if grep -q "subtract" src/math.js 2>/dev/null; then
  echo "✓ subtract function added to src/math.js"
  echo ""
  echo "Current src/math.js:"
  cat src/math.js
else
  echo "⚠ subtract function NOT found in src/math.js"
fi

# Check if tests were added
echo ""
echo "=== Test Changes ==="
if ls tests/*subtract* 2>/dev/null || grep -q "subtract" tests/*.js 2>/dev/null; then
  echo "✓ Tests for subtract added"
else
  echo "⚠ No subtract tests found"
fi

# Check for commits
echo ""
echo "=== Git Status ==="
git status --short
echo ""
echo "Recent commits:"
git log --oneline -3

# Check iteration log
echo ""
echo "=== Iteration Log ==="
if [ -f ".reqdrive/agent/iteration-1.log" ]; then
  echo "Log exists. Last 20 lines:"
  tail -20 .reqdrive/agent/iteration-1.log
else
  echo "No iteration log found"
fi

# Run tests to verify
echo ""
echo "=== Running Tests ==="
npm test

echo ""
echo "=== Phase 1.2 Result ==="
if [ "$COMPLETED" -gt 0 ]; then
  echo "✓ AGENT ITERATION: PASSED (completed $COMPLETED stories)"
else
  echo "⚠ AGENT ITERATION: PARTIAL (no stories marked complete, but may have made progress)"
fi
```

### 5.4 Record Results

```bash
cat > .reqdrive/validation-1.2.json << EOF
{
  "phase": "1.2",
  "component": "Agent Iteration",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "stories_completed": $(jq '[.userStories[] | select(.passes == true)] | length' .reqdrive/agent/prd.json),
  "stories_remaining": $(jq '[.userStories[] | select(.passes == false)] | length' .reqdrive/agent/prd.json),
  "code_added": $(grep -q "subtract" src/math.js && echo true || echo false),
  "tests_pass": $(npm test >/dev/null 2>&1 && echo true || echo false),
  "notes": ""
}
EOF

echo "Results saved to .reqdrive/validation-1.2.json"
```

---

## Step 6: Validate Verification Stage (Phase 1.3)

### 6.1 Run Verification

```bash
cd ~/reqdrive-validation/test-project

source "$REQDRIVE_ROOT/lib/config.sh"
source "$REQDRIVE_ROOT/lib/errors.sh"
reqdrive_load_config

export REQDRIVE_LOG_LEVEL=info

source "$REQDRIVE_ROOT/lib/verify.sh"

echo "=== Starting Verification ==="
echo ""

run_verification "." "claude-sonnet-4-20250514" 300

VERIFY_STATUS=$?
echo ""
echo "=== Verification Complete ==="
echo "Exit status: $VERIFY_STATUS"
```

### 6.2 Validate Verification Results

```bash
cd ~/reqdrive-validation/test-project

echo "=== Verification Validation ==="

# Check report exists
if [ -f ".reqdrive/agent/verification-report.txt" ]; then
  echo "✓ Verification report exists"
else
  echo "✗ No verification report"
  exit 1
fi

# Check for pass/fail signal
echo ""
echo "=== Verification Signal ==="
if grep -q "VERIFICATION_PASSED" .reqdrive/agent/verification-report.txt; then
  echo "✓ VERIFICATION_PASSED signal found"
  SIGNAL="passed"
elif grep -q "VERIFICATION_FAILED" .reqdrive/agent/verification-report.txt; then
  echo "⚠ VERIFICATION_FAILED signal found"
  SIGNAL="failed"
else
  echo "⚠ No clear signal found"
  SIGNAL="unclear"
fi

# Show report summary
echo ""
echo "=== Report Summary (last 30 lines) ==="
tail -30 .reqdrive/agent/verification-report.txt

echo ""
echo "=== Phase 1.3 Result ==="
if [ "$SIGNAL" = "passed" ]; then
  echo "✓ VERIFICATION: PASSED"
elif [ "$SIGNAL" = "failed" ]; then
  echo "⚠ VERIFICATION: FAILED (this may be expected if agent didn't complete)"
else
  echo "⚠ VERIFICATION: UNCLEAR (check report manually)"
fi
```

### 6.3 Record Results

```bash
cat > .reqdrive/validation-1.3.json << EOF
{
  "phase": "1.3",
  "component": "Verification",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "report_exists": $([ -f .reqdrive/agent/verification-report.txt ] && echo true || echo false),
  "signal": "$(grep -o 'VERIFICATION_[A-Z]*' .reqdrive/agent/verification-report.txt | head -1)",
  "notes": ""
}
EOF

echo "Results saved to .reqdrive/validation-1.3.json"
```

---

## Step 7: Validate PR Creation (Phase 1.4)

> **Note:** This step requires a GitHub repository. If testing locally only, skip to the summary.

### 7.1 Create GitHub Repository

```bash
cd ~/reqdrive-validation/test-project

# Create repo on GitHub (requires gh auth)
gh repo create reqdrive-validation-test --private --source=. --push

# Or if repo exists, just add remote
# git remote add origin https://github.com/YOUR_USER/reqdrive-validation-test.git
# git push -u origin main
```

### 7.2 Run PR Creation

```bash
cd ~/reqdrive-validation/test-project

# Create a branch with changes
git checkout -b reqdrive/req-01-test

# Make sure there are changes to commit
git add -A
git diff --cached --quiet || git commit -m "feat: Add subtract function"

# Push branch
git push -u origin reqdrive/req-01-test

source "$REQDRIVE_ROOT/lib/config.sh"
source "$REQDRIVE_ROOT/lib/errors.sh"
reqdrive_load_config

source "$REQDRIVE_ROOT/lib/pr-create.sh"

echo "=== Creating PR ==="
create_pr "." "REQ-01" "reqdrive/req-01-test" "main" ""

PR_STATUS=$?
echo ""
echo "=== PR Creation Complete ==="
echo "Exit status: $PR_STATUS"
```

### 7.3 Validate PR

```bash
# Check PR was created
gh pr list --head reqdrive/req-01-test

# View PR details
gh pr view reqdrive/req-01-test

echo ""
echo "=== Phase 1.4 Result ==="
if gh pr view reqdrive/req-01-test >/dev/null 2>&1; then
  echo "✓ PR CREATION: PASSED"
else
  echo "✗ PR CREATION: FAILED"
fi
```

---

## Step 8: Compile Results

```bash
cd ~/reqdrive-validation/test-project

echo "=========================================="
echo "  Phase 1 Validation Summary"
echo "=========================================="
echo ""
echo "Date: $(date)"
echo "Project: $PWD"
echo ""

echo "=== Component Results ==="
for f in .reqdrive/validation-1.*.json; do
  if [ -f "$f" ]; then
    PHASE=$(jq -r '.phase' "$f")
    COMPONENT=$(jq -r '.component' "$f")
    echo ""
    echo "Phase $PHASE: $COMPONENT"
    jq -r 'to_entries | .[] | "  \(.key): \(.value)"' "$f" | grep -v "phase\|component"
  fi
done

echo ""
echo "=== Files Generated ==="
ls -la .reqdrive/agent/

echo ""
echo "=== Recommendations ==="

# Check overall status
PRD_OK=$([ -f .reqdrive/agent/prd.json ] && jq -e '.userStories | length > 0' .reqdrive/agent/prd.json >/dev/null 2>&1 && echo 1 || echo 0)
VERIFY_OK=$(grep -q "VERIFICATION_PASSED" .reqdrive/agent/verification-report.txt 2>/dev/null && echo 1 || echo 0)

if [ "$PRD_OK" -eq 1 ] && [ "$VERIFY_OK" -eq 1 ]; then
  echo "✓ All components working. Proceed to Phase 2 (end-to-end testing)."
elif [ "$PRD_OK" -eq 1 ]; then
  echo "⚠ PRD generation works, but verification needs attention."
  echo "  - Check agent prompt for clearer instructions"
  echo "  - Review iteration logs for issues"
else
  echo "✗ PRD generation needs work."
  echo "  - Check Claude's output in prd-gen.log"
  echo "  - May need to adjust the PRD generation prompt"
fi
```

---

## Troubleshooting

### PRD Generation Issues

**Problem:** No prd.json created
```bash
# Check the generation log
cat .reqdrive/agent/prd-gen.log

# Common causes:
# 1. Claude didn't understand the prompt
# 2. Claude output markdown instead of JSON
# 3. Timeout occurred
```

**Problem:** Invalid JSON
```bash
# Try to extract JSON from output
cat .reqdrive/agent/prd-gen.log | sed -n '/{/,/}/p' > extracted.json
jq empty extracted.json && echo "Valid JSON extracted"
```

### Agent Issues

**Problem:** Agent doesn't implement code
```bash
# Check iteration log
cat .reqdrive/agent/iteration-1.log

# Common causes:
# 1. Prompt too complex
# 2. PRD stories unclear
# 3. Agent confused about file locations
```

**Problem:** Agent doesn't update PRD
```bash
# The prompt tells agent to set passes=true
# If not happening, check:
# 1. Agent prompt instructions
# 2. File permissions
# 3. Claude's understanding of the task
```

### Verification Issues

**Problem:** No clear PASSED/FAILED signal
```bash
# Check what Claude output
cat .reqdrive/agent/verification-report.txt

# The prompt asks for explicit signal
# If missing, Claude may need clearer instructions
```

---

## Next Steps

After Phase 1 validation succeeds:

1. **Run Phase 2.1** - Full end-to-end with `reqdrive run REQ-01`
2. **Tune prompts** based on observed behavior
3. **Test failure scenarios** (Phase 3)
4. **Document findings** for your team

See `docs/VALIDATION-PLAN.md` for the complete validation process.
