# reqdrive

Requirements-driven development pipeline. Automates the flow from requirements documents to pull requests using AI agents.

## Version 0.3.0

Uses a two-phase architecture: planning (PRD generation) followed by deterministic story-by-story implementation.

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
- `claude` (Claude Code CLI — only needed for `run`/`launch` commands)
- `timeout` and `sha256sum` (GNU coreutils — present by default on Linux, macOS via `brew install coreutils`, and in Git-Bash/MSYS2)

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
| `reqdrive launch <REQ-ID>` | Run pipeline detached in background (`--unsafe` mode) |
| `reqdrive status [REQ-ID]` | Show run status and story completion |
| `reqdrive logs <REQ-ID>` | Tail output log for a background run |
| `reqdrive validate` | Validate the configuration file |
| `reqdrive migrate` | Add version fields to pre-0.3.0 configs/PRDs |
| `reqdrive plan <REQ-ID>` | Generate `prd.json` only — planning phase without implementation. Useful for reviewing the plan before committing agent time. |
| `reqdrive orchestrate` | Multi-requirement sequencing. **Not implemented** — prints a "coming soon" notice and exits 0. |
| `reqdrive --version` | Show version |
| `reqdrive --help` | Show help |

### Run Options

| Flag | Description |
|------|-------------|
| `-i`, `--interactive` | Run in interactive mode (default, safer) |
| `--unsafe` | Skip permission prompts (`--dangerously-skip-permissions`) |
| `--dangerously-skip-permissions` | Alias for `--unsafe`. Accepted for parity with the `claude` CLI's own flag name. Grants the agent unrestricted system access; `launch` always uses this mode because a detached run cannot answer permission prompts. |
| `--force` | Skip pre-flight checks |
| `--resume` | Resume from last checkpoint |

## Configuration (`reqdrive.json`)

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

| Field | Default | Description |
|-------|---------|-------------|
| `version` | `"0.3.0"` | Schema version |
| `requirementsDir` | `docs/requirements` | Directory containing `REQ-*.md` files |
| `testCommand` | (none) | Command to run tests |
| `model` | `claude-sonnet-4-20250514` | Claude model to use |
| `maxIterations` | `10` | Maximum agent iterations |
| `baseBranch` | `main` | Base branch for feature branches |
| `prLabels` | `["agent-generated"]` | Labels to add to PRs |
| `projectName` | (none) | Project name for PR titles |
| `completionHook` | (none) | Shell command executed when pipeline completes |
| `maxStoryRetries` | `3` | Maximum attempts per user story. `select_next_story` skips a story once its `attempts` counter reaches this value, so a story that cannot be implemented does not consume the whole iteration budget |
| `reviewCommand` | (none) | Post-PR review step. `"builtin"` runs a Claude review of the diff; any other non-empty string is executed as a shell command. Findings are appended to the PR body. Warn-only — it never aborts the pipeline, and it runs after PR creation, so it cannot change the draft decision |

## Project Layout

After setup, your project will have:

```
your-project/
├── reqdrive.json              # Pipeline configuration
├── docs/requirements/         # Requirement documents
│   ├── REQ-01-auth.md
│   └── REQ-02-dashboard.md
└── .reqdrive/
    └── runs/
        └── <req-slug>/        # Per-requirement run state (gitignore recommended)
            ├── run.json       # Lifecycle status, PID, timestamps, PR URL
            ├── prd.json       # Generated PRD with user stories
            ├── checkpoint.json # Resume state
            ├── prompt.md      # Current iteration prompt
            ├── progress.txt   # Agent progress log
            └── iteration-*.log # Raw agent output per iteration
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

1. **Pre-flight checks** — Clean working tree, base branch exists, requirement file found
2. **Branch creation** — Creates `reqdrive/req-01` from base branch
3. **Phase 1: Planning** — Agent creates `prd.json` with user stories (up to 2 attempts)
4. **Phase 2: Implementation** — One Claude invocation per story, deterministic selection by priority
5. **PR creation** — Push branch, create GitHub PR with validation checklist from PRD

## Security

By default, reqdrive runs in **interactive mode**, which prompts for permission on sensitive operations. Use `--unsafe` to grant the agent unrestricted access (required for `launch`).

**Only run in `--unsafe` mode in:**
- Sandboxed environments (containers, VMs)
- Projects where you trust the codebase
- Systems without sensitive credentials

Requirement content is scanned for dangerous patterns (shell injection, path traversal). PRD-derived fields are sanitized before prompt expansion.

## Testing

```bash
# Run simple tests (no external dependencies)
bash tests/simple-test.sh

# Run full test suite (requires bats-core)
bash tests/run-tests.sh
```

## Project Structure

```
reqdrive/
├── bin/reqdrive         # CLI entry point
├── lib/
│   ├── config.sh        # Configuration loading
│   ├── errors.sh        # Exit codes and error helpers
│   ├── init.sh          # Interactive setup wizard
│   ├── preflight.sh     # Pre-run safety checks
│   ├── run.sh           # Core pipeline: planning + implementation
│   ├── pr-create.sh     # PR creation with validation checklist
│   ├── sanitize.sh      # Input sanitization
│   ├── schema.sh        # Schema version checking + JSON validation
│   └── validate.sh      # Config validation command
├── templates/           # Template files
├── tests/               # Test suite
├── skills/              # Claude Code skills
└── archive/             # Archived v0.1.x code
```

## Archived v0.1.x Features

The following features from v0.1.x are archived and may return in future versions:

- Parallel execution with git worktrees
- Dependency ordering for multi-requirement runs

See `archive/v1-complex/` for the original implementation.

## License

MIT
