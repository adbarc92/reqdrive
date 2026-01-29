# reqdrive Validation Plan

This document outlines a structured approach to validating reqdrive against real Claude execution before using it on production projects.

## Prerequisites

Before starting validation:

1. **Environment Setup**
   - [ ] Bash 4.0+ available (Git Bash or WSL on Windows)
   - [ ] `jq`, `git`, `gh` installed and working
   - [ ] `claude` CLI installed and authenticated
   - [ ] GitHub CLI authenticated (`gh auth status`)

2. **Test Project**
   - [ ] Isolated test repository (not a real project)
   - [ ] Simple codebase (Node.js, Python, or similar)
   - [ ] Working test suite
   - [ ] No sensitive data or credentials

3. **Safety Configuration**
   ```json
   {
     "agent": {
       "maxIterations": 3,
       "model": "claude-sonnet-4-20250514"
     },
     "verification": {
       "maxRetries": 1
     },
     "security": {
       "mode": "dangerous"
     }
   }
   ```
   **Use `dangerous` mode ONLY in isolated environments (Docker/VM).**

---

## Phase 1: Component Validation

### 1.1 PRD Generation

**Goal:** Verify Claude can generate valid PRD JSON from requirements.

**Test Steps:**
```bash
cd /path/to/test-project

# Create a simple requirement
cat > docs/requirements/REQ-TEST-prd-gen.md << 'EOF'
# REQ-TEST: Add greeting function

## Description
Add a function that returns a greeting message.

## Acceptance Criteria
- [ ] Function accepts a name parameter
- [ ] Returns "Hello, {name}!" format
- [ ] Handles empty name gracefully
EOF

# Run PRD generation only
export REQDRIVE_ROOT="/path/to/reqdrive"
source "$REQDRIVE_ROOT/lib/config.sh"
source "$REQDRIVE_ROOT/lib/errors.sh"
reqdrive_load_config

source "$REQDRIVE_ROOT/lib/prd-gen.sh"
generate_prd "docs/requirements/REQ-TEST-prd-gen.md" "." "claude-sonnet-4-20250514" 300
```

**Expected Outcomes:**
- [ ] `prd.json` created in `.reqdrive/agent/`
- [ ] Valid JSON structure
- [ ] Contains `project`, `sourceReq`, `branchName`, `userStories`
- [ ] Each story has `id`, `title`, `acceptanceCriteria`, `passes: false`
- [ ] 2-5 stories generated for simple requirement

**Validation Checklist:**
```bash
# Check file exists
[ -f ".reqdrive/agent/prd.json" ] && echo "PASS: File exists"

# Validate JSON
jq empty .reqdrive/agent/prd.json && echo "PASS: Valid JSON"

# Check required fields
jq -e '.sourceReq' .reqdrive/agent/prd.json && echo "PASS: Has sourceReq"
jq -e '.userStories | length > 0' .reqdrive/agent/prd.json && echo "PASS: Has stories"

# Check story structure
jq -e '.userStories[0] | .id and .title and .acceptanceCriteria' .reqdrive/agent/prd.json && echo "PASS: Story structure"
```

**Common Failures:**
- Claude outputs markdown instead of JSON → Check prompt
- Missing fields → Strengthen prompt constraints
- Too many stories → Adjust "5-12 stories" guidance

---

### 1.2 Agent Iteration

**Goal:** Verify agent can read PRD, implement one story, and update PRD.

**Test Steps:**
```bash
# Use the PRD from 1.1, or create a minimal one:
cat > .reqdrive/agent/prd.json << 'EOF'
{
  "project": "Test - Greeting",
  "sourceReq": "REQ-TEST",
  "branchName": "reqdrive/req-test",
  "description": "Add greeting function",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add greet function",
      "description": "Create a greet(name) function that returns 'Hello, {name}!'",
      "acceptanceCriteria": [
        "greet('World') returns 'Hello, World!'",
        "Function is exported"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
EOF

# Copy agent prompt
cp "$REQDRIVE_ROOT/templates/prompt.md.tpl" .reqdrive/agent/prompt.md

# Run single agent iteration manually
source "$REQDRIVE_ROOT/lib/agent-run.sh"
run_agent "." 1 "claude-sonnet-4-20250514" 300
```

**Expected Outcomes:**
- [ ] Agent reads PRD and identifies US-001
- [ ] Implements the greet function
- [ ] Runs tests (if configured)
- [ ] Updates PRD to set `passes: true`
- [ ] Creates a commit

**Validation Checklist:**
```bash
# Check if story marked as passing
jq -e '.userStories[0].passes == true' .reqdrive/agent/prd.json && echo "PASS: Story completed"

# Check if code was added
grep -q "greet" src/*.js && echo "PASS: Function added"

# Check for commit
git log -1 --oneline | grep -qi "US-001" && echo "PASS: Commit created"
```

**Common Failures:**
- Agent doesn't follow prompt → Simplify/clarify prompt
- PRD not updated → Check file permissions, prompt instructions
- No commit created → Check git config, prompt instructions

---

### 1.3 Verification Stage

**Goal:** Verify Claude can run tests and determine pass/fail.

**Test Steps:**
```bash
# Ensure tests exist and are configured
# Run verification manually
source "$REQDRIVE_ROOT/lib/verify.sh"
run_verification "." "claude-sonnet-4-20250514" 300
echo "Exit code: $?"
```

**Expected Outcomes:**
- [ ] Runs configured test commands
- [ ] Outputs `VERIFICATION_PASSED` or `VERIFICATION_FAILED`
- [ ] Creates verification report
- [ ] Updates PRD notes on failure

**Validation Checklist:**
```bash
# Check report created
[ -f ".reqdrive/agent/verification-report.txt" ] && echo "PASS: Report created"

# Check for pass/fail signal
grep -E "VERIFICATION_(PASSED|FAILED)" .reqdrive/agent/verification-report.txt && echo "PASS: Has signal"
```

---

### 1.4 PR Creation

**Goal:** Verify PR is created with correct structure.

**Test Steps:**
```bash
# Requires a GitHub repo with push access
# Create branch and push
git checkout -b reqdrive/test-pr
git push -u origin reqdrive/test-pr

# Run PR creation
source "$REQDRIVE_ROOT/lib/pr-create.sh"
create_pr "." "REQ-TEST" "reqdrive/test-pr" "main" ""
```

**Expected Outcomes:**
- [ ] Branch pushed to remote
- [ ] PR created with title from PRD
- [ ] PR body contains validation checklist
- [ ] Labels applied
- [ ] Verification report posted as comment

---

## Phase 2: End-to-End Validation

### 2.1 Minimal Feature (Happy Path)

**Goal:** Full pipeline succeeds for trivial feature.

**Setup:**
```bash
# Create minimal test project
mkdir -p /tmp/reqdrive-e2e-test
cd /tmp/reqdrive-e2e-test
git init
npm init -y
echo 'export function add(a, b) { return a + b; }' > index.js
echo 'import {add} from "./index.js"; console.log(add(1,2)==3?"PASS":"FAIL");' > test.js
git add -A && git commit -m "Initial"

# Initialize reqdrive
reqdrive init
# Configure for dangerous mode, low iterations
```

**Requirement:**
```markdown
# REQ-E2E-01: Add subtract function

Add a subtract(a, b) function that returns a - b.

## Acceptance Criteria
- [ ] subtract(5, 3) returns 2
- [ ] Function is exported
```

**Run:**
```bash
reqdrive run REQ-E2E-01
```

**Expected Timeline:**
1. Worktree created (~5s)
2. PRD generated (~30s)
3. Agent iteration 1 (~60s)
4. Verification (~30s)
5. PR created (~10s)

**Total: ~2-3 minutes**

**Success Criteria:**
- [ ] Pipeline completes without manual intervention
- [ ] PR created (not draft)
- [ ] Tests pass in worktree
- [ ] Code is correct

---

### 2.2 Multi-Story Feature

**Goal:** Agent completes multiple stories across iterations.

**Requirement:** 3-5 acceptance criteria requiring distinct code changes.

**Run with higher iterations:**
```json
{ "agent": { "maxIterations": 5 } }
```

**Success Criteria:**
- [ ] All stories marked as passing
- [ ] Multiple commits (one per story)
- [ ] Completion signal emitted

---

### 2.3 Verification Failure + Retry

**Goal:** Pipeline handles test failure and retries.

**Setup:** Intentionally create a requirement that will fail verification initially.

**Success Criteria:**
- [ ] First verification fails
- [ ] Agent re-runs with error context
- [ ] Second attempt succeeds OR draft PR created

---

### 2.4 Resume After Failure

**Goal:** Pipeline can resume from checkpoint.

**Setup:**
1. Start pipeline
2. Kill it mid-agent (Ctrl+C)
3. Resume with `--resume`

**Success Criteria:**
- [ ] Checkpoint file exists
- [ ] Resume skips completed stages
- [ ] Pipeline completes

---

## Phase 3: Failure Mode Testing

### 3.1 Claude Timeout

**Setup:** Set very short timeout (30s) for complex task.

**Expected:**
- [ ] Timeout detected
- [ ] Error logged
- [ ] Checkpoint saved
- [ ] Can resume

### 3.2 Invalid PRD Output

**Setup:** Use ambiguous requirement that confuses Claude.

**Expected:**
- [ ] PRD validation catches error
- [ ] Retry occurs
- [ ] Eventually fails gracefully

### 3.3 Git Conflicts

**Setup:** Modify base branch while pipeline runs.

**Expected:**
- [ ] Error detected
- [ ] Clear error message
- [ ] Worktree preserved

### 3.4 Network/API Errors

**Setup:** Temporarily disable network mid-run.

**Expected:**
- [ ] Error caught
- [ ] Checkpoint saved
- [ ] Can resume when network restored

---

## Phase 4: Production Readiness Checklist

Before using on a real project, ALL must be checked:

### Required
- [ ] Phase 1 (all components) validated
- [ ] Phase 2.1 (minimal feature) succeeds 3/3 times
- [ ] Phase 2.3 (retry) works correctly
- [ ] Phase 3.1 (timeout) handled gracefully

### Recommended
- [ ] Phase 2.2 (multi-story) succeeds
- [ ] Phase 2.4 (resume) works
- [ ] Phase 3.2-3.4 handled gracefully

### Documentation
- [ ] Prompts tuned for your codebase
- [ ] CLAUDE.md updated with project context
- [ ] Team briefed on review process

---

## Validation Log Template

```markdown
## Validation Session: [DATE]

### Environment
- OS:
- Bash version:
- Claude CLI version:
- reqdrive version:

### Phase 1 Results
| Component | Status | Notes |
|-----------|--------|-------|
| 1.1 PRD Gen | | |
| 1.2 Agent | | |
| 1.3 Verify | | |
| 1.4 PR | | |

### Phase 2 Results
| Test | Status | Duration | Notes |
|------|--------|----------|-------|
| 2.1 Minimal | | | |
| 2.2 Multi-story | | | |
| 2.3 Retry | | | |
| 2.4 Resume | | | |

### Issues Found
1.
2.

### Prompt Adjustments Made
1.
2.

### Ready for Production: [ ] Yes [ ] No
```

---

## Quick Validation Script

For rapid validation of a new environment:

```bash
#!/usr/bin/env bash
# quick-validate.sh - Rapid reqdrive validation

set -e

echo "=== reqdrive Quick Validation ==="

# Check prerequisites
echo "Checking prerequisites..."
command -v bash && echo "✓ bash"
command -v jq && echo "✓ jq"
command -v git && echo "✓ git"
command -v gh && echo "✓ gh"
command -v claude && echo "✓ claude"

# Check Claude auth
echo ""
echo "Checking Claude..."
claude --version || { echo "✗ Claude not configured"; exit 1; }

# Check GitHub auth
echo ""
echo "Checking GitHub..."
gh auth status || { echo "✗ GitHub not authenticated"; exit 1; }

echo ""
echo "=== Prerequisites OK ==="
echo ""
echo "Next steps:"
echo "1. Create isolated test project"
echo "2. Run Phase 1 tests manually"
echo "3. Run Phase 2.1 end-to-end"
echo ""
echo "See docs/VALIDATION-PLAN.md for details."
```
