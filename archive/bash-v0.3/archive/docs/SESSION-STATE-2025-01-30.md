# reqdrive Session State - January 30, 2025

## Summary

Working on validating and improving the reqdrive requirements-driven development pipeline. Made significant progress on debugging and simplifying the architecture.

---

## Current State

### What Works

1. **PRD Generation** (Phase 1.1) - ✅ Working
   - Generates structured PRD from requirements
   - Creates user stories with acceptance criteria
   - Requires `security.mode: "dangerous"` in reqdrive.json

2. **Agent Iteration** (Phase 1.2) - ✅ Partially Working
   - Successfully implemented stories US-001, US-002, US-003 for REQ-01
   - Creates proper commits with `feat: [US-XXX] - [Title]` format
   - Updates PRD to mark stories as passing

3. **Ralph Pattern Integration** - ✅ Implemented
   - Switched from `-p` flag to piping prompt via stdin
   - Added `tee /dev/stderr` for real-time output
   - Simplified error handling with `|| true`

### What's In Progress

1. **Tasks-Based Agent Prototype**
   - Created `lib/agent-tasks.sh` - single-invocation agent
   - Created `templates/prompt-tasks.md.tpl` - prompt using Claude's Tasks
   - Goal: Eliminate bash iteration loop, let Claude manage tasks internally
   - **Status**: Ready to test but not yet validated

2. **REQ-02 PRD Generation**
   - About to generate PRD for string utilities requirement
   - Will be used to test the Tasks-based approach
   - **Status**: Script ready, needs to be run in terminal

---

## Key Bugs Found & Fixed

### 1. "timed" Input Bug
- **Symptom**: The word "timed" was being input into Claude
- **Cause**: Missing space before `#` comment on line 58 of errors.sh
  ```bash
  # Bad:  ERR_CLAUDE_TIMEOUT=71# Claude timed out
  # Good: ERR_CLAUDE_TIMEOUT=71  # Claude timed out
  ```
- **Status**: Fixed and committed

### 2. Interactive Mode Silent Failure
- **Symptom**: Claude runs but doesn't create files
- **Cause**: In interactive mode, Claude prompts for file permissions. With stdin redirected to `/dev/null`, it can't get permission responses.
- **Fix**: Use `security.mode: "dangerous"` for automated usage
- **Status**: Documented in PHASE1-VALIDATION-GUIDE.md

### 3. Output Not Streaming
- **Symptom**: No real-time output from Claude during agent iterations
- **Cause**: Command substitution captured output; `run_with_timeout` wrapper issues
- **Fix**: Adopted Ralph pattern - pipe prompt, use `tee /dev/stderr`, use `timeout` directly
- **Status**: Fixed in both agent-run.sh and prd-gen.sh

---

## File Locations

### reqdrive (main project)
```
D:/Coding/reqdrive/
├── lib/
│   ├── agent-run.sh      # Loop-based agent (Ralph pattern)
│   ├── agent-tasks.sh    # NEW: Tasks-based agent prototype
│   ├── prd-gen.sh        # PRD generation (Ralph pattern)
│   ├── errors.sh         # Error handling utilities
│   └── config.sh         # Configuration loading
├── templates/
│   ├── prompt.md.tpl     # Original agent prompt
│   └── prompt-tasks.md.tpl # NEW: Tasks-based prompt
└── docs/
    ├── PHASE1-VALIDATION-GUIDE.md
    └── VALIDATION-PLAN.md
```

### Test Project
```
D:/Coding/reqdrive-test-project/
├── .reqdrive/agent/
│   ├── prd-req01.json.bak  # Backed up REQ-01 PRD
│   ├── prompt.md           # Current agent prompt
│   └── *.log               # Iteration logs
├── docs/requirements/
│   ├── REQ-01-calculator.md  # ✅ Partially complete (3/7 stories)
│   └── REQ-02-string-utils.md # 🔄 Ready to generate PRD
├── src/
│   └── index.js            # Has: greet, add, subtract, multiply, divide
├── run-validation.sh       # Phase 1 validation runner
├── run-agent-tasks.sh      # NEW: Tasks-based agent runner
└── generate-prd-req02.sh   # Script to generate REQ-02 PRD
```

### Ralph Reference
```
D:/Coding/scratch/ralph/
├── ralph.sh              # Reference implementation
└── prompt.md             # Reference prompt
```

---

## Git Status

### reqdrive repo
- Branch: `main`
- Last commit: `refactor: Update prd-gen.sh to use Ralph pattern`
- All changes pushed to GitHub

### test project
- Branch: `reqdrive/calculator-functions`
- REQ-01 implementation in progress (3/7 stories complete)
- Some uncommitted progress.txt changes

---

## Next Steps (Tomorrow)

1. **Generate REQ-02 PRD**
   ```bash
   cd D:/Coding/reqdrive-test-project
   export REQDRIVE_ROOT="D:/Coding/reqdrive"
   ./generate-prd-req02.sh
   ```

2. **Test Tasks-Based Agent**
   ```bash
   ./run-agent-tasks.sh
   ```
   - Should complete all REQ-02 stories in single invocation
   - Watch for Claude's internal Tasks being created

3. **Compare Approaches**
   - Loop-based (ralph.sh style) vs Tasks-based
   - Evaluate which is simpler/more reliable

4. **Complete Phase 1 Validation**
   - Phase 1.3: Verification
   - Phase 1.4: PR Creation

---

## Commands Quick Reference

```bash
# Set up environment
export REQDRIVE_ROOT="D:/Coding/reqdrive"
cd D:/Coding/reqdrive-test-project

# Generate PRD
./generate-prd-req02.sh

# Run Tasks-based agent (new prototype)
./run-agent-tasks.sh

# Run loop-based agent (original)
./run-validation.sh 1.2

# Check PRD status
jq '.userStories[] | {id, title, passes}' .reqdrive/agent/prd.json

# Check git status
git status && git log --oneline -5
```

---

## Architecture Decision Pending

**Question**: Should reqdrive use:

| Approach | Pros | Cons |
|----------|------|------|
| **Loop-Based** (current) | External visibility, can resume | Complex bash logic, re-reads PRD each iteration |
| **Tasks-Based** (prototype) | Simpler, Claude manages progress | Single long session, less external visibility |

Need to validate Tasks-based approach to make final decision.
