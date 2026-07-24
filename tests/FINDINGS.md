# Test Quality Findings Register

Weak assertions and known test-quality gaps, recorded rather than silently
frozen. Triaged at the end of the roadmap-completion work (P8).

**Counting rule for "pure negative":** an assertion whose final statement is
a negation (`! cmd`), an emptiness check (`[ -z "$x" ]`), or an inequality
against absence. Such an assertion reports PASS when its own setup fails,
so it cannot detect a silent defect.

## Open

| # | Location | Finding | Status |
|---|---|---|---|
| F1 | `tests/simple-test.sh` implementation-prompt assertions | Two were pure negatives satisfied by an empty prompt file. | **Fixed** — Task 4 added positive content checks (silent mutant now caught by 3 of 3), but this made the two `! grep` negations non-terminal in their subshells; under `set -e`, bash exempts `!`-prefixed commands from errexit, so a violated negative was silently masked and reported PASS. Follow-up commit converts both to `if grep …; then exit 1; fi` guards, which participate in errexit regardless of position. Verified via `tests/mutate.sh` (`impl-prompt-silent`, `impl-prompt-return1`) and a scratch-copy masking proof. |
| F2 | `tests/simple-test.sh` `${VAR}` assertion | Interpolates `$HOME` into an unanchored grep BRE, so its regex-safety depends on the machine's home path. | Open |
| F3 | `lib/run.sh:285-288` | `build_implementation_prompt` writes a prompt with blank Title/Description/Criteria when `jq` fails on malformed story JSON. No guard, no assertion. | Open |
| F4 | Suite-wide | **18 assertions** end in a pure negative (`!` or `[ -z ]`) and cannot detect a setup failure. Measured 2026-07-23 with `awk '/^ *\($/{buf="";inb=1;next} /^ *\)$/{if(inb)print buf;inb=0;next} inb{buf=$0}' tests/simple-test.sh \| grep -cE '^\s*(!\|\[ -z )'`. (Down from a higher count after Task 4 converted two impl-prompt negations to `if grep; then exit 1; fi`.) | Open — triage at Task 35 |
| F5 | `tests/simple-test.sh:346-356` | The `reqdrive validate` assertion checks only `-ne 0`, so it does not pin the exit code. | Closed by Task 31 |
| F6 | `lib/run.sh` draft-PR gate, `prd_present==0` branch | With Phase 1's planning-failure abort restored, `prd_present=0` is reachable only if `prd.json` is deleted *during* implementation (after planning already succeeded) — e.g. a misbehaving agent removing it mid-run. Not currently exercised by a dedicated test; the retargeted `draft gate: planning failure aborts with no PR` test covers the pre-planning-success abort path instead. | Open — candidate for a focused test |

## Closed

| # | Location | Finding | Status |
|---|---|---|---|
| F7 | `lib/run.sh` `select_next_story` (near line 382) | `select_next_story` used `select(.passes == false and ...)` while Phase 3's completion count used `select(.passes != true)`. A story that omitted the optional `passes` field entirely was never selected for implementation (`== false` doesn't match `null`/absent) yet was counted incomplete by Phase 3 — the PR would draft forever and re-running the pipeline could never make progress on that story (a liveness hole). Fixed in this commit by changing the predicate to `select(.passes != true and ...)` to agree with Phase 3, with a red-first regression test (`story: select_next_story selects a story omitting passes`, US-RUN-31). | **Closed** |
| F8 | `lib/run.sh` `write_run_status` | `pr_url` (and possibly other fields) are interpolated into `run.json` without JSON-escaping, so a value containing an embedded newline (raw git/gh stdout) produces INVALID JSON. Any `jq` consumer of run.json then fails; under `set -e` this crashed `cmd_verify` before its guards ran (worked around in Task 30 by making verify's pid-read fail-open). Root cause is in write_run_status and affects the `status` command too. | Fixed (root cause: write_run_status now JSON-escapes pr_url; verify keeps a defensive fail-open) |
