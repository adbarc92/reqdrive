# test-harness (canon)

`tests/**` — 92 governing requirements.

## Purpose

The project's evidence about itself: a 202-assertion dependency-free suite, a
tamper-evidence freeze gate over it, a pipeline harness that fakes only `claude`
and `gh`, and optional bats suites.

## Public interface

| Symbol | Kind | Anchor | Notes |
|--------|------|--------|-------|
| `bash tests/simple-test.sh` | cli | tests/simple-test.sh:1 | the primary suite; exits `[ "$FAIL" -eq 0 ]` (:3242) |
| `test_result` / `test_skip` | function | tests/simple-test.sh:34 / :47 | 202 / 2 call sites |
| `bash tests/oracle-gate.sh [--accept]` | cli | tests/oracle-gate.sh:1 | enforces rules R0–R3, R6, R7 |
| `bash tests/spec-map.sh [--list]` | cli | tests/spec-map.sh:1 | test-name ↔ story totality |
| `bash tests/gate-selftest.sh` | cli | tests/gate-selftest.sh:1 | proves the gate fires |
| `bash tests/mutate.sh <mutation>` | cli | tests/mutate.sh:1 | **mutates the tree** — never run casually |
| `ph_setup` / `ph_fake_claude` / `ph_fake_gh` / `ph_run` / `ph_gh_args` | function | tests/lib/pipeline-harness.sh:8 | fakes only `claude` (:54-106) and `gh` (:108-119) |
| `bash tests/launch-lifecycle.sh` | cli | tests/launch-lifecycle.sh:1 | Linux only; prints `SKIP:` elsewhere (:9-12) |
| `tests/oracle.lock.json` | config | — | 202 `{name, story}` entries + 4 whole-file sha256 |

## Invariants

- **The suite can report a failure.** `set +e` at file scope (:11) with `set -e` as the first statement inside every assertion subshell, each invoked as a simple command whose status feeds `test_result`. Measured: 202/202 correct form, 0 incorrect (no `if ( … )`, no `( … ) && ||`, no subshell missing `set -e`). (tests/simple-test.sh:11)
- Failure propagates to the exit code. (tests/simple-test.sh:3242)
- `TEST_TEMP` is guarded twice before any assertion runs, so the historical `rm -rf .git`-in-the-repo hazard cannot recur. (tests/simple-test.sh:56-57)
- Suite names == lock names == BEHAVIOR-SPEC stories == **202**, enforced by spec-map totality. (measured on all four sources)
- The four frozen files hash identically in worktree, in git, and in the lock. (tests/oracle.lock.json)
- `conditional` is a closed enum whose only member is `claude`; any other value is a hard R3 failure. (tests/oracle-gate.sh:152-164)
- A developer **cannot** silently delete or rename one of the 202 — R7 plus R1/R6 catch it, and `--accept` additionally requires spec-map totality.

## Data flows

- **gate**: tests/oracle-gate.sh:46 run suite → :36 `parse_results` (strip ANSI, split on `": "`) → R7 file hashes :118-137 → R2 locked-test-failed :158 → R3 conditional :152 → R6 unlocked-name :181 → R1/R0 truncation :176,:182
- **pipeline test**: tests/lib/pipeline-harness.sh:125 `set -euo pipefail` → :136 source lib/run.sh → fake claude/gh on PATH → real git repo, real bare origin, real config load

## Dependencies

Internal: every `lib/*.sh`, `bin/reqdrive`, `README.md` (read by the three
doc-coverage rules), `tests/BEHAVIOR-SPEC.md` (read by spec-map). External:
bash 4+, `jq`, `git`, **`sha256sum`** (hard requirement of the gate),
`mktemp`/`comm`/`sort`/`awk`, `tar` and GNU `sed -i` (selftest/mutate),
bats-core (optional), `claude` (optional — gates 2 assertions).

## Gotchas

- The freeze surface is exactly four files: `simple-test.sh`, `oracle-gate.sh`, `pipeline-harness.sh`, `spec-map.sh`. All 52 bats tests, `launch-lifecycle.sh`, `gate-selftest.sh` and `mutate.sh` are **unfrozen**. (tests/oracle-gate.sh:118-137)
- `--accept` locks whatever ran, including a red suite — it stores `{name, story}` with no verdict and never checks `SUITE_RC`. The gate itself still catches a red suite via R2 on the next enforce run, so the exposure is narrow. (tests/oracle-gate.sh:51-88)
- `gate-selftest.sh` demonstrates R7, R2, R6 and R0 — never R1 or R3. (tests/gate-selftest.sh:71-75)
- `tests/mutate.sh` is linted by CI but never executed by it, so the mutation evidence behind the freeze is a one-off human result. (.github/workflows/ci.yml)
- `tests/spec-map.sh` is likewise never a CI step — only invoked transitively under a human `--accept`. (tests/oracle-gate.sh:52-55)
- `bash -n` in CI covers `bin/`, `lib/` and `install.sh` but **not** `tests/*.sh`.
- The suite is very slow under MSYS2/Git-Bash (≈10+ min here vs seconds in CI).
- Many assertions use `source … 2>/dev/null || true`, which swallows sourcing failures. (tests/simple-test.sh:1881, 3094)
- `tests/run-tests.sh` counts failing **suites**, not failing tests. (tests/run-tests.sh:118-123)
- 24 assertions end in a terminal negative and so cannot detect a broken setup — `tests/FINDINGS.md` F4 and `docs/STATUS.md:43` both still say 18. (measured twice, independently) → [drift DES-059](../requirements/drift-report.md#DES-059)

## Requirement coverage

92 governing reqs: **60 satisfied · 8 drifted · 17 intent-met ·
7 not-code-verifiable**. Canon (intended) behavior for the drifted ones:

| REQ | Status | Canon (intended) | Link |
|-----|--------|------------------|------|
| DES-059 / DES-121 | drifted | the pure-negative count is accurate and triaged | [drift-report](../requirements/drift-report.md#DES-059) |
| DES-008 / DES-060 | drifted | the lock is generated in the CI environment configuration | [drift-report](../requirements/drift-report.md#DES-008) |
| DES-101 | drifted | the characterization test pins the summary's identity | [drift-report](../requirements/drift-report.md#DES-101) |
| DES-072 | drifted | the `prd_present == 0` draft branch has a dedicated test | [drift-report](../requirements/drift-report.md#DES-072) |
| DES-081 / US-DOC-02 | drifted | `DOC_EXEMPT` holds the specified 2–3 names, not 5 | [drift-report](../requirements/drift-report.md#DES-081) |

The 17 `intent-met` reqs are mostly P0/P2 mechanism specs the implementation met
by a better route; they are listed in the register's spec-stale table, not here.
The 7 `not-code-verifiable` reqs are process obligations (e.g. "run the suite
before committing") that source cannot confirm.

**Refuted during verification** (do not re-raise): "the oracle gate passes
against a red suite" — R2/R6 catch every failing locked name, and
`gate-selftest.sh:73` demonstrates it.

## Pointers

CI wiring: [ci-and-install.md](ci-and-install.md). Freeze rules:
[../conventions/testing-and-freeze.md](../conventions/testing-and-freeze.md).
