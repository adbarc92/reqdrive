<!-- graph:state -->
# State

What survives between sessions. Read at the start of a session, append at the end.
Source: [STATUS](STATUS.md), [ROADMAP](../ROADMAP.md).

## Current

- Rust story harness built and on main (PR #7); fmt, clippy and tests pass in CI on Ubuntu and Windows, 155 tests on the PR #10 branch. See [STATUS](STATUS.md).
- PR #10 (container isolation check) was open with CI green, waiting for the owner to merge, as of 2026-10-31.

## Decisions

- Build in Rust as a standalone harness; Bash tree archived in `archive/bash-v0.3/` (owner ruling Q1, [design](superpowers/specs/2026-10-30-story-harness-mode-design.md)).
- CLI with JSON lines as transport for now (Q2, same design).
- Rulings R1 to R11 recorded during the build; see [STATUS](STATUS.md) session log.

## Dead ends

- Nothing recorded yet.

## Open

- Rule on Q10 (`--bare` and credentials); the live end-to-end story depends on it ([ROADMAP](../ROADMAP.md)).
- Run a live end-to-end story on a sandbox repository with owner go-ahead.
- Rule on Q4 to Q9, Q11, Q12, Q14; follow-ups: thinking tokens, Windows Job Objects, hermetic Check.
