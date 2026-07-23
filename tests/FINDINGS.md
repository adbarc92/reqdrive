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

## Closed

_None yet._
