# reqdrive Quick Start Guide

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
- `.reqdrive/agent/prompt.md` - Agent instructions

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

## Step 3: Configure Dependencies (Optional)

Edit `reqdrive.json` to define order:

```json
{
  "requirements": {
    "dependencies": {
      "REQ-01": [],
      "REQ-02": ["REQ-01"],
      "REQ-03": ["REQ-01", "REQ-02"]
    }
  }
}
```

## Step 4: Validate Configuration

```bash
reqdrive validate
```

Expected output:
```
Validating: /path/to/project/reqdrive.json
─────────────────────────────────────
  ✓ Valid JSON
  ✓ project.name = my-project
  ✓ project.title = My Project
  ...
Validation PASSED
```

## Step 5: View Dependency Graph

```bash
reqdrive deps
```

## Step 6: Run the Pipeline

### Single requirement
```bash
reqdrive run REQ-01
```

### Multiple requirements
```bash
reqdrive run REQ-01 REQ-02 REQ-03
```

### All requirements (respects dependencies)
```bash
reqdrive run --all
```

### Auto-detect next available
```bash
reqdrive run --next
```

## Step 7: Monitor Progress

```bash
# Check run status
reqdrive status

# View specific run
reqdrive status 20240115-120000

# Watch logs in real-time
tail -f .reqdrive/state/runs/*/logs/REQ-01.log
```

## Step 8: Review the PR

The pipeline creates a GitHub PR with:
- Summary of changes
- Commit list
- Validation checklist with acceptance criteria
- Verification report

Review the PR, complete the checklist, and merge when satisfied.

## Cleanup

```bash
# Remove worktrees
reqdrive clean
```

## Security Modes

Edit `reqdrive.json` to change how Claude Code handles permissions:

```json
{
  "security": {
    "mode": "interactive"  // Default: prompts for each action
  }
}
```

Options:
- `interactive` - Prompts for permission (recommended for local dev)
- `allowlist` - Only allows specified tools
- `dangerous` - No restrictions (use in sandboxes only)

## Troubleshooting

### "No reqdrive.json found"
Run from your project directory, or run `reqdrive init` first.

### "claude not found"
Install Claude Code: https://claude.ai/code

### "gh: command not found"
Install GitHub CLI: `winget install GitHub.cli`

### Pipeline hangs
- Check `.reqdrive/state/runs/*/logs/` for errors
- In `interactive` mode, Claude may be waiting for permission

### Worktree conflicts
```bash
reqdrive clean
git worktree prune
```

## Example Project Structure

```
my-project/
├── reqdrive.json              # Pipeline config
├── docs/
│   └── requirements/
│       ├── REQ-01-auth.md
│       ├── REQ-02-dashboard.md
│       └── REQ-03-api.md
├── .reqdrive/
│   ├── agent/
│   │   └── prompt.md          # Agent instructions
│   └── state/
│       └── runs/              # Pipeline run history
├── src/                       # Your source code
└── CLAUDE.md                  # Project context for Claude
```

## Tips

1. **Keep requirements focused** - One feature per REQ file
2. **Write clear acceptance criteria** - Agent uses these to verify completion
3. **Use dependencies** - Let complex features build on simpler ones
4. **Review PRs carefully** - AI-generated code needs human validation
5. **Iterate on the prompt** - Customize `.reqdrive/agent/prompt.md` for your codebase
