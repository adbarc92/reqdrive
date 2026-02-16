# reqdrive Quick Start Guide (v0.3.0)

This guide walks you through using reqdrive with a real project.

## Prerequisites

### On Windows

reqdrive requires a Bash environment. Use one of:

1. **Git Bash** (recommended for quick setup)
   ```bash
   # Open Git Bash, then:
   export PATH="$PATH:/path/to/reqdrive/bin"
   ```

2. **WSL2** (recommended for full functionality)
   ```bash
   # In WSL:
   export PATH="$PATH:/mnt/path/to/reqdrive/bin"
   ```

### Required Tools

```bash
# Verify all tools are available
which bash jq git gh claude

# Authenticate GitHub CLI
gh auth login

# Verify Claude is configured
claude --version
```

## Step 1: Initialize in Your Project

```bash
cd /path/to/your-project

# Run interactive setup
reqdrive init
```

This creates:
- `reqdrive.json` - Pipeline configuration (with `"version": "0.3.0"`)
- `docs/requirements/` - Where you'll put requirement files
- `.reqdrive/runs/` - Run state directory (per-requirement isolation)

## Step 2: Write a Requirement

Create `docs/requirements/REQ-01-user-auth.md`:

```markdown
# REQ-01: User Authentication

## Overview
Add basic user authentication to the application.

## Functional Requirements
- Users can register with email/password
- Users can log in with email/password
- Users can log out
- Session persists across page refreshes

## Technical Notes
- Use JWT for session management
- Hash passwords with bcrypt
- Store users in the existing database

## Acceptance Criteria
- [ ] Registration form validates email format
- [ ] Login shows error for invalid credentials
- [ ] Protected routes redirect to login
- [ ] Logout clears session state
```

## Step 3: Validate Configuration

```bash
reqdrive validate
```

Expected output:
```
Validating: /path/to/project/reqdrive.json
─────────────────────────────────────
  ✓ Valid JSON
  ✓ requirementsDir = docs/requirements
  ✓ testCommand = npm test
  ...
Validation PASSED
```

## Step 4: Run the Pipeline

### Foreground (interactive, default)

```bash
reqdrive run REQ-01
```

### Background (detached, unsafe mode)

```bash
reqdrive launch REQ-01
```

The pipeline will:
1. Create branch `reqdrive/req-01` from your base branch
2. **Phase 1: Planning** — Agent creates a PRD with user stories
3. **Phase 2: Implementation** — Agent implements each story one at a time, runs tests, commits
4. Create a GitHub PR when all stories are complete

## Step 5: Monitor Progress

### Foreground run

Watch the terminal output as the agent works.

### Background run

```bash
# Check status of all runs
reqdrive status

# Check a specific run
reqdrive status REQ-01

# Tail the output log
reqdrive logs REQ-01
```

### Inspect run state

```bash
# View the generated PRD
cat .reqdrive/runs/req-01/prd.json | jq .

# View the progress log
cat .reqdrive/runs/req-01/progress.txt

# View iteration logs
ls .reqdrive/runs/req-01/iteration-*.log
```

## Step 6: Review the PR

The pipeline creates a GitHub PR with:
- Summary of changes
- Commit list
- Validation checklist with acceptance criteria

Review the PR, complete the checklist, and merge when satisfied.

## Configuration Options

Edit `reqdrive.json` to customize:

```json
{
  "version": "0.3.0",
  "requirementsDir": "docs/requirements",
  "testCommand": "npm test",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 10,
  "baseBranch": "main",
  "prLabels": ["agent-generated"],
  "projectName": "My Project",
  "completionHook": ""
}
```

| Option | Description |
|--------|-------------|
| `version` | Schema version (must be `"0.3.0"`) |
| `requirementsDir` | Where to find REQ-*.md files |
| `testCommand` | Command to run tests |
| `model` | Claude model to use |
| `maxIterations` | Max agent iterations |
| `baseBranch` | Branch to create features from |
| `prLabels` | Labels for created PRs |
| `projectName` | Name shown in PR titles |
| `completionHook` | Shell command run when pipeline ends (receives `REQ_ID`, `STATUS`, `PR_URL`, `BRANCH`, `EXIT_CODE` env vars) |

## Troubleshooting

### "No reqdrive.json found"
Run from your project directory, or run `reqdrive init` first.

### "claude not found"
Install Claude Code: https://claude.ai/code

### "gh: command not found"
Install GitHub CLI: `winget install GitHub.cli`

### "No requirement file found"
Make sure your requirement file is in the configured `requirementsDir` and starts with `REQ-XX`.

### Agent doesn't complete
- Check if `maxIterations` is too low
- Review `.reqdrive/runs/<req-slug>/prd.json` to see story status
- Check `.reqdrive/runs/<req-slug>/iteration-*.log` for errors
- Resume an interrupted run: `reqdrive run REQ-01 --resume`

### Tests fail
- Verify `testCommand` is correct
- Make sure tests pass before running the pipeline

## Security

v0.3.0 defaults to **interactive mode**, which prompts for permission on sensitive operations.

Use `--unsafe` to run without permission prompts (required for `launch` and background runs).

**Only run in `--unsafe` mode in:**
- Sandboxed environments (containers, VMs)
- Projects where you trust the codebase
- Systems without sensitive credentials

## Example Project Structure

```
my-project/
├── reqdrive.json              # Pipeline config
├── docs/
│   └── requirements/
│       ├── REQ-01-auth.md
│       └── REQ-02-dashboard.md
├── .reqdrive/
│   └── runs/                  # Run state (gitignore this)
│       └── req-01/
│           ├── run.json
│           ├── prd.json
│           ├── checkpoint.json
│           └── progress.txt
└── src/                       # Your source code
```

## Tips

1. **Keep requirements focused** - One feature per REQ file
2. **Write clear acceptance criteria** - Agent uses these to create user stories
3. **Start small** - Test with a simple requirement first
4. **Review PRs carefully** - AI-generated code needs human validation
5. **Gitignore run state** - Add `.reqdrive/runs/` to `.gitignore`
6. **Use `launch` for fire-and-forget** - Great for mobile SSH sessions
7. **Set a `completionHook`** - Get notified when the pipeline finishes
