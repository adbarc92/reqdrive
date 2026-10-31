# reqdrive

`reqdrive story <work-order.json>` is a coding harness that an external orchestrator drives. It
takes one story with acceptance criteria and runs it to one pushed branch. The agent works in two
stages. In Red, an agent writes tests only, and the harness checks that every criterion id appears
in them and that they fail. In Green, an agent makes them pass without touching the tests. The
harness, not the agent, makes every commit, runs the test command, checks the scope rules and
pushes. It writes events to stdout as JSON lines, and the last line is the result. It does not open
pull requests and it does not merge: the orchestrator does both.

The design is in
[`docs/superpowers/specs/2026-10-30-story-harness-mode-design.md`](docs/superpowers/specs/2026-10-30-story-harness-mode-design.md).
The earlier Bash implementation is kept unchanged in `archive/bash-v0.3/`.

## Build

The toolchain is pinned to Rust 1.93.1 in `rust-toolchain.toml`, and `rustup` installs it on first
use.

```
cargo build --release
```

This produces `reqdrive`. The package also builds `fake-claude`, a **test-only** stand-in for the
`claude` CLI that the integration tests use. It has no use outside the tests.

## Run

```
reqdrive story <work-order.json>
reqdrive --version
```

- **stdout:** events, one JSON object per line. The last line is the result.
- **stderr:** human-readable diagnostics.
- **Exit code:** `0` once a result line has been written, whatever the outcome. `1` if the result
  could not be written. `2` for a usage error. To learn what happened, read the result line, not
  the exit code.

The agent is the `claude` CLI in print mode. It must be installed and logged in.

### Work order

A work order is one JSON file. The `schema` value must be exactly `story-work-order/0`.

```json
{
  "schema": "story-work-order/0",
  "attempt_id": "a-7f3c",
  "story": {
    "id": "S-12",
    "title": "Short title",
    "description": "What the story asks for.",
    "acceptance_criteria": [
      {"id": "AC-1", "text": "First criterion."},
      {"id": "AC-2", "text": "Second criterion."}
    ]
  },
  "workspace": "/abs/path/to/clone",
  "state_dir": "/abs/path/outside/the/clone",
  "repo": {"remote": "origin", "url": "..."},
  "base_commit": "<40 lowercase hex characters>",
  "base_branch": "main",
  "attempt_branch": "attempt/S-12/a-7f3c",
  "tests_ref": "refs/heads/attempt/S-12/a-7f3c.tests",
  "failure_evidence": [{"attempt_id": "a-11aa", "summary": "...", "detail": "..."}],
  "inference": {"allow": [{"provider": "anthropic", "models": ["claude-sonnet-5-5"]}]},
  "limits": {"turns": 200, "wall_clock_secs": 3600, "tokens": 4000000},
  "test_command": "npm test",
  "test_paths": ["test/"],
  "frozen_paths": ["package.json", "jest.config.js"],
  "isolation": "container",
  "agent_allow": ["Bash(npm run typecheck)"]
}
```

Notes:

- `state_dir` must be absolute, empty, writable and outside `workspace`. Each work order runs once.
  A retry is a new attempt with a new id, branch, tests ref and state directory.
- `workspace` must be a git work tree at `base_commit` with a clean tree, untracked files included.
- `test_command` is required. If it is missing, the harness reads `testCommand` from
  `<workspace>/reqdrive.json`.
- `green_max_calls` (1 to 20, default 5) and `denied_paths` are optional. `denied_paths` adds to
  the built-in list: `.github`, `.husky`, `.claude`, `.mcp.json` and `.gitmodules`.
- `isolation` is `container` or `none` (the default). It sets the agent's permission mode; see
  Isolation below.
- `repo.url` and `base_branch` are accepted and unused in v1. Unknown fields are ignored.

## Events

Every line is a JSON object with the envelope
`{"v":1,"attempt_id":"…","seq":n,"ts":"<RFC 3339, milliseconds, UTC>"}` and a `type`:

| `type` | Fields | When |
|---|---|---|
| `progress` | `stage` (`validate`, `provision`, `red`, `red_published`, `green`, `check`, `deliver`, `done`) | A stage begins |
| `heartbeat` | `waiting_on` (`agent`, `tests`, `push`) | Every 30 s while a child runs |
| `usage` | `call_seq`, `model_id`, `provider`, `prompt`, `cached_prompt`, `cache_write`, `output`, `thinking`, `attributed` | One per API response, plus residue rows |
| `log` | `stream` (`agent`, `test`, `system`), `line` | Selected lines: warnings and test-log tails |
| `artifact` | `kind` (`tests_ref`, `branch`, `criteria_map`, `log_file`), `ref`, `sha` | When produced |
| `error` | `category`, `retryable`, `detail` | Each failure, fatal or not |
| `result` | `outcome`, `head_sha`, `tests_ref_sha`, `red_observed`, `tests_defective`, `failure`, `evidence` | Once, last |

Unknown is `null`, never 0. `thinking` is always `null`, because the CLI does not report it. The
result is also written to `<state_dir>/result.json`, and every event to
`<state_dir>/events.jsonl`. Every result field is a claim. The orchestrator should re-read git and
run the tests itself.

## Outcomes

The outcomes are `pushed`, `no_change`, `failed` and `halted`. The table of which condition
produces which outcome, category and retry flag is spec
[section 3.5.1](docs/superpowers/specs/2026-10-30-story-harness-mode-design.md). It is the
contract. The Rust implementation notes are in section 10 of the same document.

## Environment overrides

| Variable | Default | Meaning |
|---|---|---|
| `REQDRIVE_CLAUDE_BIN` | `claude` | The agent binary |
| `REQDRIVE_HEARTBEAT_MS` | `30000` | Heartbeat interval |
| `REQDRIVE_GRACE_MS` | `30000` | How long a child gets after an interrupt before it is killed |

On Windows, `REQDRIVE_CLAUDE_BIN` must name a real `.exe`. Only the direct child can be killed
there, and a `.cmd` shim leaves `node` running and holding the pipe.

## Isolation

The harness runs the repository's test command, and the agent writes tests, so **agent-written
tests run arbitrary code as the user that runs the harness.** The harness limits its own writes: it
keeps state in `state_dir`, writes only the attempt branch, the tests ref and the remote-tracking
refs that a push updates, and never writes the shared git config. It cannot contain what an agent
or a test does. Isolating each attempt is the orchestrator's job:

- Run each attempt in its own container, or in its own full clone.
- Never let an untrusted attempt share a `.git` with a checkout you care about. Git worktrees share
  config, hooks and the object store, so a test running in one worktree can poison the others.
- The permission mode follows `isolation`. `container` means the orchestrator has isolated the
  attempt, and the agent runs with `--permission-mode bypassPermissions`. `none` (the default) runs
  the agent with `acceptEdits`, plus an allow-list of the test command and `agent_allow`.
- Every git call the harness makes disables repository hooks (`core.hooksPath` points at an empty
  directory), fsmonitor and external diff programs. That keeps the harness's own commits and
  pushes predictable. It does not make a hostile repository safe.

## Processes and signals

- On Unix, every child runs in its own process group. Interrupt and kill go to the whole group, so
  processes started by a test command stop too. The grace period applies to the group's leader; once
  the leader has exited after an interrupt, the rest of the group is killed at once.
- On Windows only the direct child is killed, and it is killed at the interrupt without a grace
  period.
- SIGINT, SIGTERM and SIGHUP (Ctrl-C and Ctrl-Break on Windows) make the harness stop the current
  child, write a `halted` result with category `interrupted`, and exit 0.
- Concurrent attempts are safe when each has its own workspace (isolated as above) and `state_dir`.

## Development

```
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test
```

CI runs the same three commands on Linux and Windows. [`CLAUDE.md`](CLAUDE.md) describes the code
layout, and [`ROADMAP.md`](ROADMAP.md) lists what is planned.

## License

MIT. See `LICENSE`.
