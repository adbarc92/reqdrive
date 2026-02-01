# reqdrive v0.2.0 Verification Plan

**Purpose:** Validate that the simplified reqdrive pipeline works end-to-end on a real project.

## Overview

We'll test reqdrive against a real codebase with a simple requirement to verify:
1. CLI commands work (`init`, `validate`, `run`)
2. Agent creates PRD and implements stories
3. PR is created with proper structure

## Test Project Options

### Option A: elevation-broker (Recommended)
- Already has Ralph working in `scripts/ralph/`
- Spring Boot + React codebase
- Has existing test infrastructure
- Can create a simple test requirement

### Option B: Fresh test project
- Create minimal Node.js or Python project
- More controlled but less realistic
- Good for CI/CD integration later

## Pre-Verification Checklist

- [ ] reqdrive is in PATH or use full path
- [ ] Prerequisites installed: `jq`, `git`, `gh`, `claude`
- [ ] GitHub CLI authenticated: `gh auth status`
- [ ] Claude CLI working: `claude --version`
- [ ] Test project has clean git state

## Verification Steps

### Phase 1: CLI Validation

```bash
# 1. Navigate to test project
cd /path/to/test-project

# 2. Initialize reqdrive
reqdrive init
# Expected: Creates reqdrive.json, .reqdrive/agent/, docs/requirements/

# 3. Validate config
reqdrive validate
# Expected: "Validation PASSED"

# 4. Check help
reqdrive --help
reqdrive --version
# Expected: Shows help, shows "0.2.0"
```

### Phase 2: Create Test Requirement

Create a minimal requirement that's easy to verify:

```markdown
# docs/requirements/REQ-01-hello.md

# REQ-01: Hello World Endpoint

## Overview
Add a simple hello world endpoint to verify the agent pipeline works.

## Requirements

1. Create a new endpoint at `/api/hello`
2. Endpoint returns JSON: `{"message": "Hello, World!"}`
3. Add a test that verifies the endpoint works

## Acceptance Criteria
- [ ] GET /api/hello returns 200
- [ ] Response body is valid JSON
- [ ] Test passes in CI
```

### Phase 3: Run Pipeline

```bash
# Run the pipeline
reqdrive run REQ-01

# Expected behavior:
# 1. Creates branch: reqdrive/req-01
# 2. Builds prompt with requirement embedded
# 3. Agent creates prd.json with user stories
# 4. Agent implements each story
# 5. Agent commits changes
# 6. Agent outputs <promise>COMPLETE</promise>
# 7. PR is created
```

### Phase 4: Verify Outputs

#### Check branch and commits
```bash
git log --oneline main..reqdrive/req-01
# Expected: One or more commits with "feat: US-XXX" format
```

#### Check PRD was created
```bash
cat .reqdrive/agent/prd.json | jq '.userStories | length'
# Expected: 1-3 stories

cat .reqdrive/agent/prd.json | jq '.userStories[] | select(.passes == true) | .id'
# Expected: All story IDs listed (all passed)
```

#### Check progress log
```bash
cat .reqdrive/agent/progress.txt
# Expected: Progress entries for each completed story
```

#### Check PR was created
```bash
gh pr view reqdrive/req-01
# Expected: PR exists with validation checklist
```

#### Verify the implementation works
```bash
# For Node.js
npm test

# For Spring Boot
./mvnw test

# Manual verification
curl http://localhost:3000/api/hello
# Expected: {"message": "Hello, World!"}
```

## Success Criteria

| Check | Expected Result |
|-------|-----------------|
| `reqdrive init` | Creates config and directories |
| `reqdrive validate` | Passes validation |
| `reqdrive run REQ-01` | Completes without error |
| Branch created | `reqdrive/req-01` exists |
| PRD created | `.reqdrive/agent/prd.json` has stories |
| All stories pass | All `passes: true` in PRD |
| Commits made | At least one `feat: US-XXX` commit |
| PR created | PR exists on GitHub |
| Tests pass | Project tests still pass |
| Feature works | `/api/hello` returns expected response |

## Failure Scenarios to Test

### 1. Agent doesn't complete
- **Symptom:** Reaches max iterations without `COMPLETE`
- **Check:** `.reqdrive/agent/prd.json` for incomplete stories
- **Check:** `.reqdrive/agent/iteration-*.log` for errors

### 2. Tests fail
- **Symptom:** Agent commits but tests don't pass
- **Check:** Did agent run tests? Check progress.txt
- **Action:** May need to adjust testCommand in config

### 3. PR creation fails
- **Symptom:** Branch exists but no PR
- **Check:** `gh auth status` - authentication issue?
- **Check:** Does branch have commits? `git log`

### 4. Claude times out
- **Symptom:** Pipeline hangs or exits after 30 min
- **Check:** Is requirement too complex?
- **Action:** Break into smaller requirements

## Automated CI Test (Future)

```yaml
# .github/workflows/reqdrive-test.yml
name: Test reqdrive

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup test project
        run: |
          mkdir test-project && cd test-project
          npm init -y
          echo '{"requirementsDir": "requirements", "testCommand": "npm test"}' > reqdrive.json
          mkdir -p requirements
          cat > requirements/REQ-01-test.md << 'EOF'
          # REQ-01: Add test file
          Create a file called hello.txt with "Hello" in it.
          EOF

      - name: Run reqdrive
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          cd test-project
          reqdrive run REQ-01

      - name: Verify
        run: |
          cd test-project
          test -f hello.txt
          grep "Hello" hello.txt
```

## Test Matrix

| Project Type | Test Command | Complexity |
|--------------|--------------|------------|
| Node.js + Jest | `npm test` | Low |
| Python + pytest | `uv run pytest` | Low |
| Spring Boot | `./mvnw test` | Medium |
| React + Vite | `npm test` | Medium |
| Full-stack | Multiple | High |

## Estimated Time

| Phase | Duration |
|-------|----------|
| Phase 1: CLI validation | 5 min |
| Phase 2: Create requirement | 5 min |
| Phase 3: Run pipeline | 10-30 min (depends on complexity) |
| Phase 4: Verify outputs | 10 min |
| **Total** | **30-50 min** |

## Next Session Checklist

- [ ] Choose test project (elevation-broker or fresh)
- [ ] Ensure all prerequisites installed
- [ ] Create simple test requirement
- [ ] Run full pipeline
- [ ] Document any issues found
- [ ] Fix issues and re-test
- [ ] Update docs with lessons learned
