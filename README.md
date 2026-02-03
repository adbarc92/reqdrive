# reqdrive

Requirements-driven development pipeline. Automates the flow from requirements documents to pull requests using AI agents.

## Version 0.2.0

This version uses a simplified "Ralph pattern" architecture with a single-loop agent execution model.

## How It Works

1. You write requirements as markdown files (`REQ-01-feature-name.md`)
2. Run `reqdrive run REQ-01`
3. The agent creates a PRD with user stories, implements each story, and commits
4. A PR is created with a validation checklist

## Prerequisites

- `bash` (4.0+)
- `jq`
- `git`
- `gh` (GitHub CLI, authenticated)
- `claude` (Claude Code CLI)

**Windows Users:** reqdrive requires a Bash environment. Use Git Bash or WSL2.

## Installation

```bash
git clone https://github.com/user/reqdrive.git ~/.reqdrive
echo 'export PATH="$HOME/.reqdrive/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Quick Start

```bash
cd your-project
reqdrive init         # Interactive setup — creates reqdrive.json
reqdrive validate     # Verify configuration
reqdrive run REQ-01   # Run pipeline for a requirement
```

## Commands

| Command | Description |
|---------|-------------|
| `reqdrive init` | Create `reqdrive.json` configuration and directories |
| `reqdrive run <REQ-ID>` | Run the pipeline for a specific requirement |
| `reqdrive validate` | Validate the configuration file |
| `reqdrive --version` | Show version |
| `reqdrive --help` | Show help |

## Configuration (`reqdrive.json`)

The configuration is minimal with sensible defaults:

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

| Field | Default | Description |
|-------|---------|-------------|
| `requirementsDir` | `docs/requirements` | Directory containing `REQ-*.md` files |
| `testCommand` | (none) | Command to run tests |
| `model` | `claude-sonnet-4-20250514` | Claude model to use |
| `maxIterations` | `10` | Maximum agent iterations |
| `baseBranch` | `main` | Base branch for feature branches |
| `prLabels` | `["agent-generated"]` | Labels to add to PRs |
| `projectName` | (none) | Project name for PR titles |

## Project Layout

After setup, your project will have:

```
your-project/
├── reqdrive.json              # Pipeline configuration
├── docs/requirements/         # Requirement documents
│   ├── REQ-01-auth.md
│   └── REQ-02-dashboard.md
└── .reqdrive/
    └── agent/                 # Agent state (gitignore recommended)
        ├── prompt.md          # Generated prompt
        ├── prd.json           # Generated PRD
        ├── progress.txt       # Progress log
        └── iteration-*.log    # Iteration logs
```

## Writing Requirements

Requirements are markdown files with the REQ ID prefix:

```markdown
# REQ-01: User Authentication

## Description
Implement user login and registration.

## Acceptance Criteria
- [ ] Users can register with email/password
- [ ] Users can log in and receive a session
- [ ] Invalid credentials show error message
```

## Pipeline Stages

When you run `reqdrive run REQ-01`:

1. **Branch Creation** — Creates `reqdrive/req-01` branch from base branch
2. **Agent Loop** — Iterates until all stories complete:
   - If no PRD exists, agent creates one with user stories
   - Agent implements the next incomplete story
   - Agent runs tests and commits changes
   - Agent marks story as complete
   - When all stories pass, agent outputs completion signal
3. **PR Creation** — Creates GitHub PR with validation checklist

## Agent Behavior

The agent (Claude Code) receives a prompt with the requirement embedded and:

1. Creates a PRD (`prd.json`) with user stories if one doesn't exist
2. Picks the highest-priority incomplete story
3. Implements the story and runs tests
4. Commits with format: `feat: [US-001] - Story Title`
5. Updates PRD to mark story as complete
6. Outputs `<promise>COMPLETE</promise>` when all stories are done

## Security

This version uses `--dangerously-skip-permissions` mode by default, which grants the AI agent unrestricted system access.

**Only run reqdrive in:**
- Sandboxed environments (containers, VMs)
- Projects where you trust the codebase
- Systems without sensitive credentials

## Testing

```bash
# Run simple tests (no external dependencies)
./tests/simple-test.sh

# Run full test suite (requires bats-core)
./tests/run-tests.sh
```

## Project Structure

```
reqdrive/
├── bin/reqdrive         # CLI entry point (103 lines)
├── lib/
│   ├── config.sh        # Configuration loading (78 lines)
│   ├── init.sh          # Interactive setup (95 lines)
│   ├── run.sh           # Core Ralph loop (245 lines)
│   ├── pr-create.sh     # PR creation (110 lines)
│   └── validate.sh      # Config validation (59 lines)
├── templates/           # Template files
├── tests/               # Test suite
└── archive/             # Archived v0.1.x code
```

Total: ~590 lines of code.

## Archived v0.1.x Features

The following features from v0.1.x are archived and may return in future versions:

- Parallel execution with git worktrees
- Dependency ordering for multi-requirement runs
- Separate PRD generation step
- Interactive security mode with permission prompts
- Status and clean commands

See `archive/v1-complex/` for the original implementation.

## License

MIT
