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
| F1 | `tests/simple-test.sh` implementation-prompt assertions | Two were pure negatives satisfied by an empty prompt file. | **Partially fixed** (Task 4) — positive content checks added; silent mutant now caught by 3 of 3. |
| F2 | `tests/simple-test.sh` `${VAR}` assertion | Interpolates `$HOME` into an unanchored grep BRE, so its regex-safety depends on the machine's home path. | Open |
| F3 | `lib/run.sh:285-288` | `build_implementation_prompt` writes a prompt with blank Title/Description/Criteria when `jq` fails on malformed story JSON. No guard, no assertion. | Open |
| F4 | Suite-wide | ~21 assertions end in a pure negative and cannot detect setup failure. Exact count to be reproduced during P1. | Open |
| F5 | `tests/simple-test.sh:346-356` | The `reqdrive validate` assertion checks only `-ne 0`, so it does not pin the exit code. | Closed by Task 31 |

## Closed

_None yet._
