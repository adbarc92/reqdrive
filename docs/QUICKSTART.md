# reqdrive Quick Start Guide (v0.2.0)

This guide walks you through using reqdrive with a real project.

## Prerequisites

### On Windows

reqdrive requires a Bash environment. Use one of:

1. **Git Bash** (recommended for quick setup)
   ```bash
   # Open Git Bash, then:
   export PATH="$PATH:/d/Coding/reqdrive/bin"
   ```

2. **WSL2** (recommended for full functionality)
   ```bash
   # In WSL:
   export PATH="$PATH:/mnt/d/Coding/reqdrive/bin"
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
- `reqdrive.json` - Pipeline configuration
- `docs/requirements/` - Where you'll put requirement files
- `.reqdrive/agent/` - Agent workspace

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

```bash
reqdrive run REQ-01
```

This will:
1. Create branch `reqdrive/req-01` from your base branch
2. Start the agent loop:
   - Agent reads the requirement
   - Agent creates a PRD with user stories
   - Agent implements each story, one at a time
   - Agent runs tests and commits after each story
3. Create a GitHub PR when all stories are complete

## Step 5: Monitor Progress

Watch the terminal output as the agent works. You can also check:

```bash
# View the generated PRD
cat .reqdrive/agent/prd.json | jq .

# View the progress log
cat .reqdrive/agent/progress.txt

# View iteration logs
ls .reqdrive/agent/iteration-*.log
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
  "requirementsDir": "docs/requirements",
  "testCommand": "npm test",
  "model": "claude-sonnet-4-20250514",
  "maxIterations": 10,
  "baseBranch": "main",
  "prLabels": ["agent-generated"],
  "projectName": "My Project"
}
```

| Option | Description |
|--------|-------------|
| `requirementsDir` | Where to find REQ-*.md files |
| `testCommand` | Command to run tests |
| `model` | Claude model to use |
| `maxIterations` | Max agent iterations |
| `baseBranch` | Branch to create features from |
| `prLabels` | Labels for created PRs |
| `projectName` | Name shown in PR titles |

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
- Review `.reqdrive/agent/prd.json` to see story status
- Check `.reqdrive/agent/iteration-*.log` for errors

### Tests fail
- Verify `testCommand` is correct
- Make sure tests pass before running the pipeline

## Security Warning

v0.2.0 uses `--dangerously-skip-permissions` mode by default. This grants the AI agent unrestricted system access.

**Only run reqdrive in:**
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
│   └── agent/                 # Agent workspace (gitignore this)
│       ├── prompt.md
│       ├── prd.json
│       └── progress.txt
└── src/                       # Your source code
```

## Tips

1. **Keep requirements focused** - One feature per REQ file
2. **Write clear acceptance criteria** - Agent uses these to create user stories
3. **Start small** - Test with a simple requirement first
4. **Review PRs carefully** - AI-generated code needs human validation
5. **Gitignore agent state** - Add `.reqdrive/agent/` to `.gitignore`
