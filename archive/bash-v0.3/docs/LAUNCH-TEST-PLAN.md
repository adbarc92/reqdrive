# Launch Command Test Plan

This plan's 8 manual cases for the fire-and-forget pipeline (`reqdrive launch`,
`status`, `logs`) are now automated. This doc is a pointer from each case to
the test that covers it.

- **Cases 2, 5, 7, 8** (status transitions, exit-code/PR-URL reporting,
  completion hook, re-launch) assert on `run.json` state directly — no
  background process is spawned. They run cross-platform as part of
  `bash tests/simple-test.sh`, in the "Launch Lifecycle" section.
- **Cases 1, 4, 6** (detached launch, duplicate-launch block, crash
  detection via a real `kill -9`) depend on `nohup` detachment, PID
  liveness over time, and signal semantics — unreliable under MSYS2 (see
  `CLAUDE.md`, Known Pitfalls). They run only in the `launch-lifecycle`
  Linux CI job (`.github/workflows/ci.yml`), via `bash tests/launch-lifecycle.sh`.
- **Case 3** (`logs` tailing) asserts process behavior, not interactive
  Ctrl+C handling — covered by the existing `cli: logs with missing log
  file shows error` test in the main suite.

## Case → test map

| # | Case | Covered by |
|---|------|------------|
| 1 | Launch starts a detached run | `tests/launch-lifecycle.sh` (Linux CI job) |
| 2 | Status shows a running process | `tests/simple-test.sh` — Launch Lifecycle |
| 3 | Logs tails output | `tests/simple-test.sh` — `cli: logs with missing log file shows error` |
| 4 | Duplicate launch blocked | `tests/launch-lifecycle.sh` (Linux CI job) |
| 5 | Status after completion | `tests/simple-test.sh` — `launch: status reports a completed run with its PR URL` |
| 6 | Status detects crashed process | `tests/simple-test.sh` — `launch: status reports a crashed run when the PID is gone` (state check); `tests/launch-lifecycle.sh` — real `kill -9` (Linux CI job) |
| 7 | Completion hook fires | `tests/simple-test.sh` — `launch: completion hook passes REQ_ID, STATUS and EXIT_CODE` |
| 8 | Re-launch after completion | `tests/simple-test.sh` — `launch: re-launch is permitted after the previous run completed` |

## Manual exploration setup

Still useful if you want to poke at the real pipeline by hand. Create a
minimal requirement for testing:

```bash
mkdir -p docs/requirements
cat > docs/requirements/REQ-TEST-launch-smoke.md <<'EOF'
# REQ-TEST: Launch Smoke Test

Add a file called `LAUNCH_TEST.md` to the repo root with the text "Launch test passed".

## Acceptance Criteria
- File `LAUNCH_TEST.md` exists at repo root
- Contains the text "Launch test passed"
EOF
```

Then drive it directly:

```bash
reqdrive launch REQ-TEST
reqdrive status REQ-TEST
reqdrive logs REQ-TEST
```

Cleanup:

```bash
rm -f docs/requirements/REQ-TEST-launch-smoke.md
rm -rf .reqdrive/runs/req-test
rm -f /tmp/reqdrive-hook-test.log
git checkout -- .  # discard any agent-created files
```
