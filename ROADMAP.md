# Roadmap

This is the only roadmap file. Every future intention lives here: planned work, deferred scope,
follow-ups, known defects not yet scheduled, and open questions. The "next steps" in
[`docs/STATUS.md`](docs/STATUS.md) are a short list that points into this file.

The design is
[`docs/superpowers/specs/2026-10-30-story-harness-mode-design.md`](docs/superpowers/specs/2026-10-30-story-harness-mode-design.md)
(section numbers below refer to it).

## Next

- **A live end-to-end story.** The single-call live check is done (2026-10-31, `claude` 2.1.296):
  the parser's field paths matched, and `live_fixture_parses` runs on the captured, scrubbed
  output (`crates/reqdrive/tests/fixtures/stream-live.jsonl`). `--max-turns` is accepted though
  `claude --help` does not list it. Still to do, with the owner's go-ahead since it spends more:
  run one story on a sandbox repository and confirm that two attempts in parallel give two
  branches, two tests refs, and a usage ledger that reconciles with `modelUsage`.
- **Thinking tokens.** The live output now reports `output_tokens_details.thinking_tokens` on
  `message_delta` and `thinkingTokens` in `modelUsage`. The spec says `thinking` is always `null`
  in v1; filling it from these fields is a small change to the parser and the spec.

## Deferred from v1 (spec section 10.5)

- PR routes: the `pr` work-order field and the GitHub and Forgejo AGit delivery routes (Q3). In v1
  the orchestrator opens PRs.
- A second agent adapter, which is what a local-only inference policy needs (section 2.2). Until
  then such a policy is refused with `policy_unsatisfiable`.
- The `harness-protocol` transport (Q2). v1 is the CLI with JSON lines.
- Docker workspaces. Isolation stays the orchestrator's job (section 3.9).
- A hash lock over contract tests, as the factory plans have it (spec section 10.4).
- The factory plans' crates and gates (spec section 10.5; see also "Not the current path" below).

## Planned improvements

- **Windows Job Objects.** On Windows only the direct child can be killed, so grandchildren (for
  example `npm` under `cmd`) can survive an interrupt, and `REQDRIVE_CLAUDE_BIN` must name a real
  `.exe`. A Job Object would stop the whole tree.
- **Windows object-store race.** Concurrent attempts in one repository that produce byte-identical
  objects can fail transiently with "Permission denied" while committing or pushing. Consider one
  bounded retry on that stderr pattern. Distinct content, or separate clones, avoids it.
- **Windows missing runner.** On Windows `cmd` reports a missing command as exit 1, so a missing
  test runner shows up as `base_broken` at provision rather than `harness_error`.
- **Hermetic Check.** Check runs after `reset --hard` and `clean -fd`, which keep ignored files, so
  ignored build output or dependencies can make it pass. Freezing or removing ignored files before
  Check would make it hermetic. Until then the orchestrator runs its own tests.
- **Stronger isolation proof.** `isolation: "container"` is accepted on local evidence (marker
  files, environment variables, `/proc/1/cgroup`), which a process on the host could fake. An
  attestation the orchestrator signs, and detection of Windows containers (where `container` is
  refused today), would make the claim checkable.
- **A second Ctrl-C to force exit.** Today every interrupt waits for the current child's grace.
- **An abandoned stdout reader** (the agent exited but a leftover process holds its pipe) stays
  blocked on its thread until that process closes the pipe or the harness exits.

## Open questions

These are the owner's questions in spec section 8 that have no ruling yet. Q1 to Q3 are ruled
(Rust, the CLI with JSON lines, the orchestrator opens PRs). Each has a recommendation in the spec.

- **Q4:** must the harness wait for the orchestrator to confirm red? Recommended: no.
- **Q5:** where is the tests ref published and under what name? Recommended: the work order names
  it in full and it goes to the same remote as the branch.
- **Q6:** is the reading of `tests_defective` right (the agent concluded a frozen test contradicts
  its criterion)?
- **Q7:** which outcome values? v1 has `pushed`, `no_change`, `failed`, `halted`.
- **Q8:** usage details: residue rows, a `cache_write` field, `thinking: null`, and which counts
  `limits.tokens` covers (uncached input, cache writes and output; cache reads excluded).
- **Q9:** a local-only inference policy: refuse it, try an unsupported local server, or wait for a
  second adapter? v1 refuses.
- **Q10:** isolation, permissions and `--bare`: containers per attempt, and an API credential
  versus a subscription login. Without `--bare`, user hooks and plugins and the repository's own
  `.claude/` hooks and `.mcp.json` servers load in every agent call.
- **Q11:** work-order additions (`state_dir`, `test_paths`, `frozen_paths`, `isolation`,
  `agent_allow`), who fills `frozen_paths`, and the preconditions (clean workspace, empty
  `state_dir`, one run per work order, test runs that leave no un-ignored byproducts).
- **Q12:** is "the criterion id appears as a whole word in a test's name or a comment beside it" an
  acceptable mechanical check?
- **Q13:** the live check spends a few cents. Go ahead? (See Next.)
- **Q14:** is bypassing the target repository's own hooks (`--no-verify`, an empty hooks path)
  acceptable, given that the orchestrator runs its own checks?

## Not the current path

- The factory M0 and M1 plans (`docs/superpowers/plans/2026-10-04-factory-m0-foundations.md` and
  `…-m1-harness.md`) are not the current path. The owner ruled (Q1) that the story harness is built
  standalone in Rust and does not execute them. They stay in the repository for reference.
- `docs/superpowers/plans/2026-07-23-reqdrive-roadmap-completion.md` is about the archived Bash
  tree.

## Known minor issues

Found in review and deliberately left for later. None blocks v1.

- CI installs the pinned toolchain with `rustup show`, which relies on rustup's implicit install.
- The crate version (0.4.0) and licence (MIT) were chosen during the build and should be confirmed.
- `cap_evidence`'s test does not cover a 3-byte character at the cut. Serialization of `Evidence`
  and `Failure` is not asserted. A `starts_with` path check in work-order validation is case-sensitive on
  Windows.
- The criterion check skips self-overlapping ids. `Emitter::finish` closes before it writes, so a
  failed write cannot be retried. The envelope-override test cannot exercise a real override.
- `added_lines` can drop a `++` line that follows a removed `-- ` line. Path normalisation does not
  collapse `//` or `..`, and does no non-ASCII folding, alternate-data-stream or 8.3 handling.
- The stream parser adds with plain `u64 +` on untrusted JSON (use `saturating_add`), and has no
  direct tests for a delta without an open call or for a non-object line.
- A backtick in a story title can open inline code in a prompt (cosmetic). The `curl | sh` pattern
  gives a false positive on `sha256sum`.
- `fake-claude` writes JSON keys in alphabetical order. The grandchild test needs a reaping init.
  A test-log tail can exceed 2 048 bytes when invalid bytes expand to U+FFFD. A `try_wait` error
  leaves the child running.
- Patches and paths are decoded lossily as UTF-8. `is_work_tree` cannot tell "no git" from "not a repository". Two push tests assert
  less than their names say.
- No tests for an agent spawn error, a flushed open call, a token or deadline kill through the
  adapter, a panicking stdout reader, or the panic path's `progress{done}`.
- A push failure is classified by its stderr prefix. Untested paths: the `reqdrive.json` fallback, the red-violations retry, the
  empty-change retry, exit 126 and 127 at Red, the criteria-map artifact, the dangerous-pattern
  logs and the heartbeat.
- The wall-clock test depends on timing (it allows 15 s for a 5 s budget).
- When `modelUsage` omits a cache total, the residue row's `prompt` is `null`, so `limits.tokens`
  adds 0 for that row's input. On a panic the heartbeat thread is not joined, so a heartbeat can
  follow `progress{done}`. A git failure during an interrupt (mapped to `halted/interrupted`) has no
  test.
- `git::tests::push_to_bare_remote_without_upstream` failed once on Windows and was not reproduced
  in eight further runs under load.
