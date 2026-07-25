# Convention: testing and freeze (canon)

## Rule

Every assertion in `tests/simple-test.sh` has exactly one `### US-` story in
`tests/BEHAVIOR-SPEC.md`, and the pairing is frozen in `tests/oracle.lock.json`
together with whole-file sha256 hashes. The suite must be able to **report** a
failure — the assertion form is `set +e` at file scope with `set -e` as the
first statement inside each `( … )` subshell, invoked as a simple command.

## Applies to

`tests/**`, `.github/**`

## Examples

- The one correct assertion form (measured 202/202 conforming, 0 deviations): file-scope `set +e` at tests/simple-test.sh:11, subshell body opening with `set -e`, closing `)` followed by `test_result "name" $?`
- Totality: 202 test names == 202 lock entries == 202 spec stories, enforced by `tests/spec-map.sh`
- Freeze: four whole-file hashes — `simple-test.sh`, `oracle-gate.sh`, `pipeline-harness.sh`, `spec-map.sh` (tests/oracle-gate.sh:118-137)
- Gate rules R0–R3, R6, R7 all evaluate (no short-circuit) at tests/oracle-gate.sh:114-184; `tests/gate-selftest.sh` proves R7, R2, R6 and R0 fire
- Doc-coverage gates, frozen as US-DOC-01/02/03: every command (tests/simple-test.sh:2963), every config field (:2979) and every flag (:3005) must appear in README.md
- Warn-before-enforce ladder: log → checkpoint annotation → hard gate (CLAUDE.md:54); `testCommand` and the commit check sit at rung one, the scope check at rung one-and-a-half (warn default, `block` opt-in)

## Exceptions

- The freeze covers **four files**. All 52 bats tests, `launch-lifecycle.sh`, `gate-selftest.sh` and `mutate.sh` are unfrozen.
- `--accept` regenerates the lock without checking the suite's exit status, so it will lock a red suite (tests/oracle-gate.sh:51-88). *Refuted as a gate hole:* R2 catches any failing locked name on the very next enforce run, so the exposure is a stale-lock window, not a green-on-red gate.
- `spec-map.sh` and `mutate.sh` are linted by CI but never executed by it — the mutation evidence behind the freeze is a one-off human result.
- `bash -n` in CI omits `tests/**`.
- 24 assertions end in a terminal negative and cannot detect a broken setup; `tests/FINDINGS.md` and `docs/STATUS.md:43` still say 18. → [drift DES-059](../requirements/drift-report.md#DES-059)
- `spec-map.sh` checks name totality only — a story whose *body* has drifted from its test's behavior is invisible to every gate.
- The lock records `environment.claude: true` but CI installs no `claude`, and the gate never reads that field. → [drift DES-008](../requirements/drift-report.md#DES-008)
- The suite exercises the real `run_pipeline` in only 12 of 202 assertions; `tests/lib/pipeline-harness.sh` fakes just `claude` and `gh` (git, config load and all of `lib/` are real). The bats "e2e" suite does not use that harness and never reaches PR creation.
- No test asserts on the rendered PR body's checklist or scope-findings sections — which is why two rendering defects survived. → [drift RDM-077](../requirements/drift-report.md#RDM-077)
- No Windows/macOS CI runner exists, so the MSYS2 support README.md:25 promises is unverified.
