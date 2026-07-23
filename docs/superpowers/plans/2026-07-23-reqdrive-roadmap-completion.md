# reqdrive Roadmap Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take reqdrive from L0 to L3 on the Readiness Ladder and finish every remaining CLAUDE.md Tier 2 item, with each behavior change locked in by a test that was observed failing first.

**Architecture:** Strictly sequential. The test harness is repaired so failures are reportable (P0), every assertion gets a written criterion (P1), the baseline is frozen against tampering (P2), and only then does any behavior change land. A pipeline test harness (P3) unlocks testing of `run_pipeline`, which the fail-closed draft gate (P4) and the `verify` command (P6b) both need.

**Tech Stack:** Bash 4.0+, jq, git, gh, coreutils (`sha256sum`, `timeout`, `mktemp`), bats-core (CI only), GitHub Actions.

**Source spec:** [`docs/superpowers/specs/2026-07-23-reqdrive-roadmap-completion-design.md`](../specs/2026-07-23-reqdrive-roadmap-completion-design.md)

## Global Constraints

- **Bash floor is 4.0.** No feature may require 5.x. `patsub_replacement` does not exist before 5.2, so any `shopt` touching it must be suffixed `|| true`.
- **No new runtime dependencies** beyond the documented set: `bash`, `jq`, `git`, `gh`, `claude`, plus `timeout` and `sha256sum` (both coreutils, both to be documented in README during P3).
- **Schema version is `0.3.0`** in every JSON artifact reqdrive writes.
- `set -euo pipefail` in entry points (`bin/reqdrive`), `set -e` in libraries (`lib/*.sh`). Exception: `tests/simple-test.sh` becomes `set +e` at top with `set -e` inside each assertion body — this is Task 2 and is deliberate.
- **Run `bash -n` on every modified `.sh` file before committing.** CI enforces it.
- **shellcheck must stay clean.** CI lints `bin/reqdrive`, `lib/*.sh`, `install.sh`, `tests/simple-test.sh`, `tests/run-tests.sh`. Any new script added to those paths must be added to the lint list in the same commit.
  - **shellcheck is not installed natively on this machine.** Run it as `./scripts/shellcheck FILE...` — a Docker wrapper around `koalaman/shellcheck:stable`, verified working. Wherever a task step says `shellcheck X`, run `./scripts/shellcheck X`. It is a real lint run, not a stub: it exits 1 on findings.
  - **Known incoming finding:** Task 34's `policy_classify_paths $changed` relies on word-splitting and will trip **SC2086**. Resolve it by iterating with `while IFS= read -r path` over `git diff --name-only` output rather than by adding a blanket disable — filenames with spaces are a real case and the loop handles both concerns at once.
- **All tests must pass before any commit:** `bash tests/simple-test.sh` exits 0. **Red-first tasks squash red into green** — write the failing test, *run it and record the failure output in your report*, then implement, then commit test and implementation together. The red evidence lives in the task report, not in a red commit. This overrides any task step that says to commit failing tests on their own (notably Task 17 Step 3, which is superseded: fold it into Task 18's commit).
- **From Task 14 onward**, `bash tests/oracle-gate.sh` must also exit 0 before any commit.
- **From Task 16 onward**, `bats tests/unit tests/e2e` must pass with **zero skips in `tests/e2e/`**.
- **No `Co-Authored-By` lines and no "Generated with Claude Code" footers** in commit messages (user's standing convention).
- **Never modify `lib/sanitize.sh`.** Its backtick neutralization is load-bearing for `tests/simple-test.sh:1186`.
- **Never modify a test name** except where a task explicitly says to. Renames are `NEEDS_HUMAN` events after Task 12.

---

## File Structure

| Path | Status | Responsibility |
|---|---|---|
| `tests/simple-test.sh` | Modify | The assertion suite. Gains a `mktemp` guard, per-body `set -e`, and all new assertions. |
| `tests/mutate.sh` | Create | Applies a named mutation to a scratch copy of the repo and reports the resulting FAIL count. Proves the harness can detect defects. |
| `tests/oracle-gate.sh` | Create | Parses a suite run, enforces gate rules R7/R2/R3/R6/R1/R0, and regenerates the lock under `--accept`. |
| `tests/oracle.lock.json` | Create | The frozen baseline: file hashes, test names, story IDs. |
| `tests/lib/pipeline-harness.sh` | Create | Fake `claude`, fake `gh`, scratch git repo; lets assertions invoke `run_pipeline`. |
| `tests/BEHAVIOR-SPEC.md` | Modify | Behavioral contract. Extended from 4 modules to all 10. |
| `tests/FINDINGS.md` | Create | Register of weak assertions and known test-quality gaps, triaged at Task 35. |
| `tests/e2e/pipeline.bats` | Modify | Six `\|\| skip` escape hatches converted to hard assertions. |
| `lib/verification.sh` | Create | Verification phase extracted from `run_pipeline`, shared by `run` and `verify`. |
| `lib/run.sh` | Modify | Draft gate inverted; prompt heredoc rewritten; Phase 3 delegated to `lib/verification.sh`; scope check added. |
| `lib/errors.sh` | Modify | Adds `EXIT_VERIFICATION_FAILED=9`, `EXIT_CONCURRENT_RUN=10`. |
| `lib/schema.sh` | Modify | Validates the new `policy` config object. |
| `lib/validate.sh` | Modify | Exit codes aligned to `EXIT_CONFIG_ERROR`. |
| `lib/policy.sh` | Create | Risk-tier path matching and scope-check evaluation. |
| `bin/reqdrive` | Modify | Adds the `verify` command and its `--ref` flag. |
| `README.md` | Modify | Documents the full public surface; enforced by doc-coverage tests. |
| `docs/audits/2026-02-16-pipeline-audit.md` | Create (move) | Relocated `reqdrive-audit.md` with a correction preamble. |
| `docs/STATUS.md` | Create | Canonical living status doc. |
| `.github/workflows/ci.yml` | Modify | Adds `oracle-gate` job and a Linux-only `launch-lifecycle` job. |

---

# Phase P0 — Make the harness able to report failure

**Why first:** `tests/simple-test.sh:11` sets `set -e` and every assertion is a bare subshell followed by `test_result "name" $?`. A failing subshell kills the script before `test_result` runs, so the FAIL branch is unreachable and "0 failed" is guaranteed by construction. Nothing in this plan can be verified until this is fixed.

---

### Task 1: Guard `mktemp` before removing the protection `set -e` provides

**Files:**
- Modify: `tests/simple-test.sh:56-57` (temp dir creation), `tests/simple-test.sh:743` (`rm -rf .git`)

**Interfaces:**
- Consumes: nothing.
- Produces: a `TEST_TEMP` that is guaranteed non-empty and a real directory before any assertion runs. Every later task depends on this.

**Context:** `tests/simple-test.sh:56` is `TEST_TEMP=$(mktemp -d)` with no error check. Line 743 runs `rm -rf .git` after `cd "$TEST_TEMP"`. Today `set -e` at line 11 aborts the script if `mktemp` fails. Task 2 removes that. **`cd ""` returns 0 and leaves you in the invocation directory** — verified — so an unguarded empty `TEST_TEMP` would run `rm -rf .git` in the repo root, and the test would report PASS while doing it.

- [ ] **Step 1: Write the failing test**

Add this at the end of `tests/simple-test.sh`, immediately before the `echo ""` that precedes the results banner at line 2306:

```bash
echo ""
echo "--- Harness Safety ---"

# Test: suite refuses to run when mktemp fails
(
  set -e
  fake_bin="$TEST_TEMP/fakebin"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/mktemp" <<'MKEOF'
#!/usr/bin/env bash
exit 1
MKEOF
  chmod +x "$fake_bin/mktemp"
  out=$(PATH="$fake_bin:$PATH" bash "$REQDRIVE_ROOT/tests/simple-test.sh" 2>&1) && rc=0 || rc=$?
  [ "$rc" -ne 0 ]
  echo "$out" | grep -q "FATAL: mktemp failed"
)
test_result "harness: aborts when mktemp fails" $?
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/simple-test.sh 2>&1 | tail -20`

Expected: the suite aborts (no results banner printed) because the inner run currently succeeds despite the fake `mktemp` — `set -e` at line 11 kills the outer script when the assertion's `[ "$rc" -ne 0 ]` fails. That abort *is* the red signal; note the last `PASS:` line printed so you can confirm it advances after the fix.

- [ ] **Step 3: Write minimal implementation**

Replace `tests/simple-test.sh:56-57`:

```bash
# Create temp directory
TEST_TEMP=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$TEST_TEMP" ] && [ -d "$TEST_TEMP" ] || { echo "FATAL: bad TEST_TEMP" >&2; exit 1; }
trap 'rm -rf "$TEST_TEMP"' EXIT
```

Note the trap changes from double to single quotes so it resolves `$TEST_TEMP` at trap time rather than baking in a possibly-empty value.

Then replace line 743 inside the `check_git_repo` assertion:

```bash
  rm -rf "$TEST_TEMP/.git" 2>/dev/null || true
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/simple-test.sh 2>&1 | tail -8`

Expected:
```
PASS: harness: aborts when mktemp fails
  Results: 158 passed, 0 failed, 0 skipped, 158 total
```

- [ ] **Step 5: Verify the repo was not harmed**

Run: `git status --short && ls -d .git`

Expected: `.git` exists; no unexpected deletions in `git status`.

- [ ] **Step 6: Syntax check and commit**

```bash
bash -n tests/simple-test.sh
git add tests/simple-test.sh
git commit -m "fix(tests): guard mktemp and scope the .git removal to TEST_TEMP

cd \"\" returns 0 and stays in the invocation directory, so an empty
TEST_TEMP would make the check_git_repo assertion run rm -rf .git in
the repo root. set -e was masking a failed mktemp; the next commit
removes that protection, so make the guard explicit first."
```

---

### Task 2: Make `errexit` active inside each assertion body

**Files:**
- Modify: `tests/simple-test.sh:11` and 157 assertion bodies

**Interfaces:**
- Consumes: Task 1's guarded `TEST_TEMP`.
- Produces: a suite where `test_result` receives a real status and the FAIL branch is reachable. Every red-first task in this plan depends on it.

**Context:** Bash ignores `errexit` inside a compound command used as an `if` condition, and **the suppression propagates into the subshell body even when the body sets `set -e` itself**. Measured:

| Form | `errexit` active inside? |
|---|---|
| `if ( ... ); then rc=0; else rc=$?; fi` | no |
| `if ( set -e; ... ); then ...` | no |
| `( ... ) && rc=0 \|\| rc=$?` | no |
| `set +e` at top; body without `set -e` | no |
| **`set +e` at top; `set -e` first in body; invoked as a simple command** | **yes** |

Only the last form works. Do not substitute any other.

- [ ] **Step 1: Confirm the body shapes before transforming**

Run:
```bash
grep -c '^($' tests/simple-test.sh
grep -c '^  ($' tests/simple-test.sh
grep -c 'test_result ' tests/simple-test.sh
```

Expected: `156` col-0 open parens (155 original + 1 from Task 1), `2` indented (the two `HAS_CLAUDE` blocks at lines 1260 and 1787), `158` `test_result` calls. If these numbers differ, stop — the transformation is not safe and the mismatch must be understood first.

- [ ] **Step 2: Apply the transformation**

```bash
awk '
  /^\($/   { print; print "  set -e"; next }
  /^  \($/ { print; print "    set -e"; next }
             { print }
' tests/simple-test.sh > /tmp/st.new && mv /tmp/st.new tests/simple-test.sh
```

Then change line 11 from `set -e` to:

```bash
set +e
```

- [ ] **Step 3: Verify the transformation landed exactly**

Run:
```bash
grep -c '^  set -e$' tests/simple-test.sh
grep -c '^    set -e$' tests/simple-test.sh
sed -n '11p' tests/simple-test.sh
bash -n tests/simple-test.sh
```

Expected: `156`, `2`, `set +e`, and no syntax errors.

The assertion added in Task 1 already begins with `set -e`, so it now has two consecutive `set -e` lines — harmless. The assertion at `tests/simple-test.sh:346-356` sets `set +e` inside its own body immediately after; the inserted `set -e` is cancelled there and is a deliberate no-op, keeping the edit uniform.

- [ ] **Step 4: Run the suite**

Run: `bash tests/simple-test.sh 2>&1 | tail -4; echo "EXIT=$?"`

Expected:
```
  Results: 158 passed, 0 failed, 0 skipped, 158 total
EXIT=0
```

- [ ] **Step 5: Commit**

```bash
git add tests/simple-test.sh
git commit -m "fix(tests): make errexit active inside each assertion body

set -e at the top of the suite aborted the script on a failing
subshell before test_result could run, so the FAIL branch was
unreachable and '0 failed' was guaranteed by construction.

The obvious fix does not work: bash suppresses errexit inside a
subshell used as an if condition, and the suppression propagates
into the body even with an explicit set -e. The only form that
preserves the semantics is set +e at top plus set -e as the first
statement of each body, invoked as a simple command."
```

---

### Task 3: Build the mutation harness that proves failures surface

**Files:**
- Create: `tests/mutate.sh`
- Modify: `.github/workflows/ci.yml` (add `tests/mutate.sh` to the shellcheck list at line 29)

**Interfaces:**
- Consumes: Task 2's repaired suite.
- Produces: `bash tests/mutate.sh <name>` printing `MUTANT=<name> EXIT=<n> FAILS=<n>`. Task 4 consumes the `FAILS` count.

**Context:** Assertion inversion cannot validate Task 2 — inverting a body's last line flips the status under both the correct and the broken form. Only mutation discriminates. The harness copies the repo to a scratch directory so the working tree is never mutated.

- [ ] **Step 1: Write the mutation harness**

Create `tests/mutate.sh`:

```bash
#!/usr/bin/env bash
# Apply a named mutation to a scratch copy of the repo, run the suite,
# and report how many assertions detected it.
#
# Usage: bash tests/mutate.sh <mutation-name>
# Mutations: impl-prompt-return1 | load-checkpoint-return1 | impl-prompt-silent | none
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MUTANT="${1:-none}"

WORK=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: bad WORK" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Copy tracked files only — no .git, no run state.
(cd "$PROJECT_ROOT" && git ls-files -z | tar --null -T - -cf -) | (cd "$WORK" && tar -xf -)

apply_mutation() {
  case "$MUTANT" in
    none) ;;
    impl-prompt-return1)
      # Total failure with an error status.
      sed -i 's|^build_implementation_prompt() {|build_implementation_prompt() {\n  return 1|' \
        "$WORK/lib/run.sh"
      ;;
    load-checkpoint-return1)
      sed -i 's|^load_checkpoint() {|load_checkpoint() {\n  return 1|' \
        "$WORK/lib/run.sh"
      ;;
    impl-prompt-silent)
      # Total failure with a SUCCESS status: writes an empty prompt, returns 0.
      sed -i 's|^build_implementation_prompt() {|build_implementation_prompt() {\n  : > "$1"; return 0|' \
        "$WORK/lib/run.sh"
      ;;
    *)
      echo "FATAL: unknown mutation '$MUTANT'" >&2
      exit 1
      ;;
  esac
}

apply_mutation
bash -n "$WORK/lib/run.sh" || { echo "FATAL: mutation broke syntax" >&2; exit 1; }

out=$(cd "$WORK" && bash tests/simple-test.sh 2>&1)
rc=$?
fails=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -c '^FAIL: ')
lines=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -cE '^(PASS|FAIL|SKIP): ')

echo "MUTANT=$MUTANT EXIT=$rc FAILS=$fails RESULT_LINES=$lines"
printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep '^FAIL: ' || true
```

- [ ] **Step 2: Prove the baseline is clean**

Run: `bash tests/mutate.sh none`

Expected: `MUTANT=none EXIT=0 FAILS=0 RESULT_LINES=158`

- [ ] **Step 3: Prove an error-status mutant is caught**

Run: `bash tests/mutate.sh impl-prompt-return1`

Expected: `EXIT=1`, `FAILS=3`, `RESULT_LINES=158`. The three named failures are the implementation-prompt sanitization assertions. **The suite must run to completion** — `RESULT_LINES=158`, not a truncated count. Under the broken `if ( ... )` form this same mutant yields `FAILS=0`, which is exactly what this step exists to rule out.

- [ ] **Step 4: Prove a second error-status mutant is caught**

Run: `bash tests/mutate.sh load-checkpoint-return1`

Expected: `EXIT=1`, `FAILS` at least 3.

- [ ] **Step 5: Add to the lint list and commit**

In `.github/workflows/ci.yml`, change line 29 to:

```yaml
        run: shellcheck tests/simple-test.sh tests/run-tests.sh tests/mutate.sh
```

```bash
bash -n tests/mutate.sh
shellcheck tests/mutate.sh
git add tests/mutate.sh .github/workflows/ci.yml
git commit -m "test: add mutation harness proving failures surface

Assertion inversion cannot validate the errexit fix — inverting a
body's last line flips the status under both the correct and the
broken form. Mutation discriminates: impl-prompt-return1 yields 3
FAILs under the correct harness and 0 under the broken one."
```

---

### Task 4: Strengthen weak assertions until a silent mutant is caught

**Files:**
- Modify: `tests/simple-test.sh` (the implementation-prompt sanitization assertions, lines ~1180-1215 after Task 2's insertions)
- Create: `tests/FINDINGS.md`

**Interfaces:**
- Consumes: `tests/mutate.sh` from Task 3.
- Produces: `tests/FINDINGS.md`, the register Task 35 triages.

**Context:** `return 1` mutants are caught at the call site by `errexit` — the assertions never have to discriminate. A *silent* mutant (empty output, success status) is the real test of assertion quality. Measured today: the silent mutant produces only **1** FAIL of 3, because two of the three assertions are pure negatives (`! grep -q '\`whoami\`'` at `tests/simple-test.sh:1186` and `! grep -q "$HOME"` at `:1206`, pre-Task-2 numbering) that an empty file satisfies. This task raises that to ≥2 by adding positive content checks, and records the remaining weak assertions rather than pretending they are fine.

- [ ] **Step 1: Measure the silent mutant before changing anything**

Run: `bash tests/mutate.sh impl-prompt-silent`

Expected: `FAILS=1`. Record the number — Step 5 must show it increase.

- [ ] **Step 2: Add positive assertions to the two pure negatives**

In the backtick assertion body, after the existing `! grep -q '\`whoami\`' "$prompt_file"` line, add:

```bash
  # Positive: the sanitized description must actually be present.
  grep -q "Use 'whoami' to attack" "$prompt_file"
  grep -q '\*\*Title:\*\* Safe title' "$prompt_file"
```

In the `${VAR}` assertion body, after the existing `! grep -q "$HOME" "$prompt_file"` line, add:

```bash
  # Positive: the criterion text must actually be present.
  grep -q 'Check \\${HOME} variable' "$prompt_file"
  grep -q 'US-003' "$prompt_file"
```

- [ ] **Step 3: Run the suite**

Run: `bash tests/simple-test.sh 2>&1 | tail -4`

Expected: `158 passed, 0 failed`. If the `\\${HOME}` pattern does not match, print the file and match what is actually emitted — the current builder escapes `$` to `\$`, which is the defect Task 28 corrects later. Assert what is true today; Task 28 updates it in an enumerated commit.

- [ ] **Step 4: Verify the silent mutant is now caught by more assertions**

Run: `bash tests/mutate.sh impl-prompt-silent`

Expected: `FAILS` is now at least `2` (was 1).

- [ ] **Step 5: Verify the error mutants still behave**

Run:
```bash
bash tests/mutate.sh none
bash tests/mutate.sh impl-prompt-return1
```

Expected: `FAILS=0` and `FAILS=3` respectively.

- [ ] **Step 6: Create the findings register**

Create `tests/FINDINGS.md`:

```markdown
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
| F1 | `tests/simple-test.sh` implementation-prompt assertions | Two were pure negatives satisfied by an empty prompt file. | **Partially fixed** (Task 4) — positive content checks added; silent mutant now caught by 2 of 3. |
| F2 | `tests/simple-test.sh` `${VAR}` assertion | Interpolates `$HOME` into an unanchored grep BRE, so its regex-safety depends on the machine's home path. | Open |
| F3 | `lib/run.sh:285-288` | `build_implementation_prompt` writes a prompt with blank Title/Description/Criteria when `jq` fails on malformed story JSON. No guard, no assertion. | Open |
| F4 | Suite-wide | ~21 assertions end in a pure negative and cannot detect setup failure. Exact count to be reproduced during P1. | Open |
| F5 | `tests/simple-test.sh:346-356` | The `reqdrive validate` assertion checks only `-ne 0`, so it does not pin the exit code. | Closed by Task 31 |

## Closed

_None yet._
```

- [ ] **Step 7: Commit**

```bash
bash -n tests/simple-test.sh
git add tests/simple-test.sh tests/FINDINGS.md
git commit -m "test: add positive checks to prompt assertions, open findings register

Two of the three implementation-prompt assertions were pure negatives
that an empty file satisfies, so a silent mutant (empty output,
success status) was caught by only 1 of 3. Positive content checks
raise that to 2 of 3. Remaining weak assertions are recorded in
tests/FINDINGS.md rather than frozen silently."
```

---

### Task 5: Rename the two exit-code test names before the freeze

**Files:**
- Modify: `tests/simple-test.sh:653`, `tests/simple-test.sh:668` (pre-Task-2 line numbers; locate by name)

**Interfaces:**
- Consumes: nothing.
- Produces: test names that stay truthful after Tasks 30 and 32 add exit codes 9 and 10.

**Context:** The names `errors: defines all exit codes (0-8)` and `errors: EXIT_MESSAGES covers all codes` become lies once Task 30 adds `EXIT_VERIFICATION_FAILED=9` and `EXIT_CONCURRENT_RUN=10`. After Task 12 a rename is a `NEEDS_HUMAN` event. Do it now, while the rename surface is still declared zero. The assertion bodies are unchanged — they enumerate 0-8 explicitly and stay correct as a subset check.

- [ ] **Step 1: Rename**

```bash
sed -i 's|test_result "errors: defines all exit codes (0-8)"|test_result "errors: defines the base exit codes 0-8"|' tests/simple-test.sh
sed -i 's|test_result "errors: EXIT_MESSAGES covers all codes"|test_result "errors: EXIT_MESSAGES covers the base codes 0-8"|' tests/simple-test.sh
```

- [ ] **Step 2: Verify both renames landed**

Run: `grep -n 'test_result "errors: defines\|test_result "errors: EXIT_MESSAGES' tests/simple-test.sh`

Expected: two lines showing the new names, no occurrences of the old ones.

- [ ] **Step 3: Run the suite**

Run: `bash tests/simple-test.sh 2>&1 | tail -3`

Expected: `158 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
bash -n tests/simple-test.sh
git add tests/simple-test.sh
git commit -m "test: rename exit-code assertions to survive codes 9 and 10

The names claimed coverage of 'all codes'. Codes 9 and 10 arrive in
P6/P7, and after the freeze lands a rename is a NEEDS_HUMAN event —
so rename now, while the rename surface is declared zero. Bodies are
unchanged; they enumerate 0-8 and remain correct as a subset check."
```

---

**P0 exit gate.** Before starting P1, confirm all four mutation criteria:

```bash
bash tests/mutate.sh none                    # FAILS=0  EXIT=0  RESULT_LINES=158
bash tests/mutate.sh impl-prompt-return1     # FAILS=3  EXIT=1  RESULT_LINES=158
bash tests/mutate.sh load-checkpoint-return1 # FAILS>=3 EXIT=1
bash tests/mutate.sh impl-prompt-silent      # FAILS>=2 EXIT=1
bash tests/simple-test.sh                    # 158 passed, 0 failed, exit 0
```

Plus the `mktemp` criterion, which is now assertion `harness: aborts when mktemp fails` inside the suite itself.

---

# Phase P1 — Spec retrofit

**Why:** 60 stories cover 4 modules, but those modules contain 96 test names — so ~36 assertions *inside the specced modules* have no story, and 61 more in unspecced modules have none either. The freeze in P2 keys every test to a story ID, so this must come first. Expect ~97 new stories plus reconciliation of the existing 60. **No file under `bin/` or `lib/` may be modified in this phase.**

---

### Task 6: Build the name→story mapping checker

**Files:**
- Create: `tests/spec-map.sh`
- Modify: `.github/workflows/ci.yml` (add `tests/spec-map.sh` to the shellcheck list)

**Interfaces:**
- Consumes: `tests/simple-test.sh` (runtime names), `tests/BEHAVIOR-SPEC.md` (story IDs).
- Produces: `bash tests/spec-map.sh` exiting 0 only when every runtime test name maps to exactly one story ID, and printing unmapped names otherwise. Tasks 7-9 use it as their completion oracle; Task 10 consumes its output to build the lock.

**Context:** Stories are linked to tests by a machine-readable annotation on the story heading. Source text and runtime text differ for 4 of 158 names (e.g. the source reads `test_result "impl prompt: neutralizes \$(cmd) in story title"` and renders at runtime as `... neutralizes $(cmd) ...`), so names must come from an actual run, never from scraping source.

The annotation format added to `tests/BEHAVIOR-SPEC.md` is a `**Test:**` line immediately under each story heading:

```markdown
### US-CFG-01: find_manifest — finds in current directory
**Test:** `find_manifest: finds manifest in current dir`
```

- [ ] **Step 1: Write the mapping checker**

Create `tests/spec-map.sh`:

```bash
#!/usr/bin/env bash
# Verify every runtime test name maps to exactly one BEHAVIOR-SPEC story.
#
# Usage: bash tests/spec-map.sh [--list]
#   (no args) validate; exit 0 only if the mapping is total and unambiguous
#   --list    print "NAME<TAB>STORY" for every mapped name
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC="$SCRIPT_DIR/BEHAVIOR-SPEC.md"
MODE="${1:-validate}"

WORK=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: bad WORK" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Runtime names, from an actual run. Strip ANSI, match the three verdicts,
# split on the FIRST ": " only, drop the trailing " (reason)" from SKIP lines.
bash "$SCRIPT_DIR/simple-test.sh" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' \
  | grep -E '^(PASS|FAIL|SKIP): ' \
  | while IFS= read -r line; do
      verdict="${line%%: *}"
      name="${line#*: }"
      [ "$verdict" = "SKIP" ] && name="${name% (*}"
      printf '%s\n' "$name"
    done | sort -u > "$WORK/runtime.txt"

# Story -> test-name pairs, from the spec.
awk '
  /^### US-[A-Z]+-[0-9]+:/ { story = $2; sub(/:$/, "", story); next }
  /^\*\*Test:\*\* / {
    if (story == "") next
    line = $0
    sub(/^\*\*Test:\*\* /, "", line)
    gsub(/^`|`$/, "", line)
    printf "%s\t%s\n", line, story
    story = ""
  }
' "$SPEC" | sort > "$WORK/mapped.txt"

cut -f1 "$WORK/mapped.txt" | sort > "$WORK/mapped-names.txt"

if [ "$MODE" = "--list" ]; then
  cat "$WORK/mapped.txt"
  exit 0
fi

rc=0

unmapped=$(comm -23 "$WORK/runtime.txt" "$WORK/mapped-names.txt")
if [ -n "$unmapped" ]; then
  echo "UNMAPPED — these tests ran but have no story:" >&2
  printf '%s\n' "$unmapped" | sed 's/^/  /' >&2
  rc=1
fi

phantom=$(comm -13 "$WORK/runtime.txt" "$WORK/mapped-names.txt")
if [ -n "$phantom" ]; then
  echo "PHANTOM — these stories name a test that did not run:" >&2
  printf '%s\n' "$phantom" | sed 's/^/  /' >&2
  rc=1
fi

dupes=$(cut -f1 "$WORK/mapped.txt" | uniq -d)
if [ -n "$dupes" ]; then
  echo "AMBIGUOUS — these test names are claimed by more than one story:" >&2
  printf '%s\n' "$dupes" | sed 's/^/  /' >&2
  rc=1
fi

total=$(wc -l < "$WORK/runtime.txt" | tr -d ' ')
mapped=$(wc -l < "$WORK/mapped-names.txt" | tr -d ' ')
echo "spec-map: $mapped of $total runtime test names mapped"
exit "$rc"
```

- [ ] **Step 2: Run it to see the true size of the gap**

Run: `bash tests/spec-map.sh; echo "EXIT=$?"`

Expected: `EXIT=1`, with all 158 names listed as UNMAPPED — no story carries a `**Test:**` line yet. Record the count; it is the work Tasks 7-9 must close.

- [ ] **Step 3: Annotate the existing 60 stories**

For each of the 60 existing `### US-` headings in `tests/BEHAVIOR-SPEC.md`, add a `**Test:**` line naming the runtime test it describes. Work module by module using the runtime list. Example — `tests/BEHAVIOR-SPEC.md` currently reads:

```markdown
### US-CFG-01: find_manifest — finds in current directory
**As** a CLI user,
**When** I run from a directory containing `reqdrive.json`,
**Then** `reqdrive_find_manifest` returns the full path to that file.
```

It becomes:

```markdown
### US-CFG-01: find_manifest — finds in current directory
**Test:** `find_manifest: finds manifest in current dir`

**As** a CLI user,
**When** I run from a directory containing `reqdrive.json`,
**Then** `reqdrive_find_manifest` returns the full path to that file.
```

Where one existing story covers several runtime tests — `US-SAN-14` describes ten dangerous patterns tested by several assertions — **split it into one story per test**. One story, one test, one criterion. That is what makes the mapping total.

- [ ] **Step 4: Re-run the checker**

Run: `bash tests/spec-map.sh`

Expected: the mapped count rises to roughly 96 (the four specced modules), and the remaining ~62 names still list as UNMAPPED. No PHANTOM and no AMBIGUOUS entries — if any appear, a `**Test:**` line has a typo or two stories claim one test.

- [ ] **Step 5: Add to lint list and commit**

In `.github/workflows/ci.yml` line 29:

```yaml
        run: shellcheck tests/simple-test.sh tests/run-tests.sh tests/mutate.sh tests/spec-map.sh
```

```bash
bash -n tests/spec-map.sh
shellcheck tests/spec-map.sh
bash tests/simple-test.sh
git add tests/spec-map.sh tests/BEHAVIOR-SPEC.md .github/workflows/ci.yml
git commit -m "test: add spec-map checker, annotate the existing 60 stories

Every story now names the runtime test that proves it. Names come
from an actual run because source and runtime text differ for 4 of
158 assertions. Stories covering several tests were split so the
mapping is one story, one test, one criterion."
```

---

### Task 7: Write stories for the `run.sh`-adjacent assertions

**Files:**
- Modify: `tests/BEHAVIOR-SPEC.md` (new section: Module 5 — run.sh)

**Interfaces:**
- Consumes: `bash tests/spec-map.sh` from Task 6.
- Produces: ~30 stories with IDs `US-RUN-01`…`US-RUN-30`.

**Context:** These 30 assertions cover run-state writing, checkpoint save/load, story selection, prompt builders, the completion hook, iteration-summary extraction, the run summary, and the review phase. They currently prove behavior nobody wrote down.

- [ ] **Step 1: List exactly which names still need stories**

Run: `bash tests/spec-map.sh 2>&1 | sed -n '/^UNMAPPED/,/^PHANTOM\|^spec-map/p'`

Work only the names in the run-state, checkpoint, story-selection, prompt-builder, completion-hook, iteration-summary, run-summary and review groups.

- [ ] **Step 2: Add the module section using this exact form**

Append to `tests/BEHAVIOR-SPEC.md`:

```markdown
---

## Module 5: run.sh

### US-RUN-01: write_run_status — creates valid run.json
**Test:** `run_status: creates valid run.json`

**As** a pipeline runner,
**When** I call `write_run_status` with a run directory, status, req ID and iteration,
**Then** `run.json` exists in that directory and parses as valid JSON.

### US-RUN-02: write_run_status — records the PID
**Test:** `run_status: run.json includes pid`

**As** a status reporter,
**When** `write_run_status` writes `run.json`,
**Then** the `pid` field holds the writing process's PID, so `reqdrive status` can test liveness.
```

Continue in that shape for every remaining name in this group. Each story must have exactly one `**Test:**` line, and its **Then** clause must state a pass/fail condition — not "works correctly". If a test name does not suggest a binary condition, read the assertion body and write what it actually checks.

- [ ] **Step 3: Verify progress**

Run: `bash tests/spec-map.sh`

Expected: mapped count rises by ~30; no PHANTOM, no AMBIGUOUS.

- [ ] **Step 4: Commit**

```bash
git add tests/BEHAVIOR-SPEC.md
git commit -m "docs(spec): add Module 5 behavior stories for run.sh

30 assertions covering run state, checkpoints, story selection,
prompt builders, the completion hook and the review phase had tests
but no written criterion."
```

---

### Task 8: Write stories for the CLI assertions

**Files:**
- Modify: `tests/BEHAVIOR-SPEC.md` (new section: Module 6 — bin/reqdrive)

**Interfaces:**
- Consumes: `bash tests/spec-map.sh`.
- Produces: ~13 stories with IDs `US-CLI-01`…`US-CLI-13`.

**Context:** Two of these — `cli: run requires REQ-ID argument` and `cli: plan without args shows usage` — are gated on the `claude` binary. They run as `test_result` where `claude` is installed and as `test_skip` under the *same name* where it is not. Their stories must say so, because Task 11's gate exempts exactly those two from the SKIP rule.

- [ ] **Step 1: List the CLI names still needing stories**

Run: `bash tests/spec-map.sh 2>&1 | grep '^  cli:'`

- [ ] **Step 2: Add the module section**

```markdown
---

## Module 6: bin/reqdrive (CLI)

### US-CLI-01: Unknown command is rejected
**Test:** `cli: unknown command exits non-zero`

**As** a CLI user,
**When** I run `reqdrive frobnicate`,
**Then** the process exits with `EXIT_GENERAL_ERROR` (1) and prints `Unknown command: frobnicate` to stderr.

### US-CLI-02: run requires a REQ-ID
**Test:** `cli: run requires REQ-ID argument`
**Environment:** requires the `claude` binary; skipped under the same test name when absent.

**As** a CLI user,
**When** I run `reqdrive run` with no argument,
**Then** usage text matching `Usage: reqdrive run` is printed and the process exits non-zero.
```

Continue for every remaining CLI name. Add the `**Environment:**` line to exactly the two `claude`-gated stories.

- [ ] **Step 3: Verify**

Run: `bash tests/spec-map.sh`

Expected: mapped count rises by ~13.

- [ ] **Step 4: Commit**

```bash
git add tests/BEHAVIOR-SPEC.md
git commit -m "docs(spec): add Module 6 behavior stories for the CLI

Marks the two claude-gated stories explicitly — they run as
test_result where claude is installed and as test_skip under the
same name where it is not."
```

---

### Task 9: Write stories for preflight, pr-create, init and review

**Files:**
- Modify: `tests/BEHAVIOR-SPEC.md` (new sections: Modules 7-10)

**Interfaces:**
- Consumes: `bash tests/spec-map.sh`.
- Produces: ~18 stories (`US-PRE-*`, `US-PR-*`, `US-INIT-*`, `US-REV-*`). After this task the mapping is **total** — that is P1's exit gate.

- [ ] **Step 1: List what remains**

Run: `bash tests/spec-map.sh 2>&1 | sed -n '/^UNMAPPED/,/^spec-map/p'`

- [ ] **Step 2: Add the four module sections**

Follow the exact shape used in Tasks 7 and 8. Module headings: `## Module 7: preflight.sh`, `## Module 8: pr-create.sh`, `## Module 9: init.sh`, `## Module 10: review phase`. Story ID prefixes `US-PRE`, `US-PR`, `US-INIT`, `US-REV`. Also cover the harness-safety assertion added in Task 1 — put it under a `## Module 11: test harness` section with ID `US-HARN-01`:

```markdown
---

## Module 11: test harness

### US-HARN-01: Suite refuses to run when mktemp fails
**Test:** `harness: aborts when mktemp fails`

**As** a test runner,
**When** `mktemp -d` fails and the suite is invoked,
**Then** it prints `FATAL: mktemp failed` and exits non-zero before any assertion runs, so no assertion can operate on an empty `TEST_TEMP`.
```

- [ ] **Step 3: Verify the mapping is total — this is the phase gate**

Run: `bash tests/spec-map.sh; echo "EXIT=$?"`

Expected:
```
spec-map: 158 of 158 runtime test names mapped
EXIT=0
```

No UNMAPPED, no PHANTOM, no AMBIGUOUS.

- [ ] **Step 4: Confirm no source was touched in this phase**

Run: `git diff --name-only 172d1e3..HEAD -- bin lib`

Expected: empty output. P1 is documentation only.

- [ ] **Step 5: Reproduce the pure-negative count for the findings register**

Run:
```bash
awk '/^ *\($/{buf=""; inb=1; next} /^ *\)$/{if(inb){print buf}; inb=0; next} inb{buf=$0}' tests/simple-test.sh \
  | grep -cE '^\s*(!|\[ -z )'
```

Update `tests/FINDINGS.md` finding **F4** with the number this produces, replacing "~21 … Exact count to be reproduced during P1" with the measured value and the command used.

- [ ] **Step 6: Commit**

```bash
bash tests/simple-test.sh
git add tests/BEHAVIOR-SPEC.md tests/FINDINGS.md
git commit -m "docs(spec): complete behavior spec — all 158 tests mapped

Modules 7-11 close the gap. spec-map.sh now exits 0: every runtime
test name maps to exactly one story, with no phantom or ambiguous
entries. F4's pure-negative count is now measured, not estimated."
```

---

# Phase P2 — Freeze the oracle

**Why:** A green suite is only evidence if it cannot be silently weakened. DOCTRINE B2 requires content-hashing the test set; B3 requires that a branch may add tests but never weaken a baseline.

**Design note carried from the spec:** the freeze is a **whole-file hash** of `tests/simple-test.sh` plus `tests/oracle-gate.sh` — not per-test body hashes, not append-only lock diffs, not base-ref CI execution. Those three lose to a six-line edit of `test_result`, which sits outside every subshell and therefore outside every body hash: with all of `lib/*.sh` emptied and the reporter patched to print PASS unconditionally, every name-and-body rule stays green. One file hash covers the reporter, the bodies, the names and the trailer, needs no git remote, and behaves identically on a laptop and in CI.

---

### Task 10: Build the gate's parser and lock generator

**Files:**
- Create: `tests/oracle-gate.sh`
- Create: `tests/oracle.lock.json` (generated)
- Modify: `.github/workflows/ci.yml` (shellcheck list)

**Interfaces:**
- Consumes: `tests/spec-map.sh --list` from Task 6, which prints `NAME<TAB>STORY`.
- Produces: `bash tests/oracle-gate.sh --accept` writing `tests/oracle.lock.json`; and the parsing functions `strip_ansi`, `parse_results`, `hash_file` used by Task 11's rules.

- [ ] **Step 1: Write the parser and generator**

Create `tests/oracle-gate.sh`:

```bash
#!/usr/bin/env bash
# Freeze gate — DOCTRINE B2/B3.
#
# Usage:
#   bash tests/oracle-gate.sh            enforce the lock
#   bash tests/oracle-gate.sh --accept   regenerate the lock (deliberate human act)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$SCRIPT_DIR/simple-test.sh"
GATE="$SCRIPT_DIR/oracle-gate.sh"
LOCK="$SCRIPT_DIR/oracle.lock.json"
MODE="${1:-enforce}"

command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "FATAL: sha256sum required" >&2; exit 1; }

WORK=$(mktemp -d) || { echo "FATAL: mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "FATAL: bad WORK" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

hash_file() { sha256sum "$1" | cut -d' ' -f1; }

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# Emit "VERDICT<TAB>NAME" for every result line.
# Split on the FIRST ": " only — 158 of 158 names contain ": " themselves,
# so cut -d: would truncate every one.
parse_results() {
  grep -E '^(PASS|FAIL|SKIP): ' | while IFS= read -r line; do
    verdict="${line%%: *}"
    name="${line#*: }"
    [ "$verdict" = "SKIP" ] && name="${name% (*}"
    printf '%s\t%s\n' "$verdict" "$name"
  done
}

# Run the suite once; keep both the output and the exit code.
bash "$SUITE" > "$WORK/raw.txt" 2>&1
SUITE_RC=$?
strip_ansi < "$WORK/raw.txt" | parse_results > "$WORK/results.tsv"
cut -f2 "$WORK/results.tsv" | sort > "$WORK/ran.txt"

if [ "$MODE" = "--accept" ]; then
  bash "$SCRIPT_DIR/spec-map.sh" >/dev/null || {
    echo "FATAL: spec-map is not total; every test needs a story before locking" >&2
    exit 1
  }
  bash "$SCRIPT_DIR/spec-map.sh" --list | sort > "$WORK/map.tsv"

  jq -Rn \
    --arg suite "$(hash_file "$SUITE")" \
    --arg gate "$(hash_file "$GATE")" \
    --arg generated "$(date +%Y-%m-%d)" \
    --arg claude "$(command -v claude >/dev/null && echo true || echo false)" \
    --rawfile map "$WORK/map.tsv" '
    {
      version: "0.3.0",
      generated: $generated,
      environment: { claude: ($claude == "true") },
      suiteSha256: $suite,
      gateSha256: $gate,
      tests: ($map | rtrimstr("\n") | split("\n") | map(
        (split("\t")) as $p | { name: $p[0], story: $p[1] }
      ))
    }' > "$LOCK"

  # The two claude-gated tests are the only conditional entries.
  jq '(.tests[] | select(.name == "cli: run requires REQ-ID argument" or
                         .name == "cli: plan without args shows usage"))
      |= . + { conditional: "claude" }' "$LOCK" > "$LOCK.tmp" && mv "$LOCK.tmp" "$LOCK"

  echo "Lock regenerated: $(jq '.tests | length' "$LOCK") tests"
  echo "  suiteSha256 $(jq -r .suiteSha256 "$LOCK")"
  echo "  gateSha256  $(jq -r .gateSha256 "$LOCK")"
  exit 0
fi

echo "oracle-gate: parsed $(wc -l < "$WORK/results.tsv" | tr -d ' ') result lines, suite exit $SUITE_RC"
```

- [ ] **Step 2: Generate the lock**

Run: `bash tests/oracle-gate.sh --accept`

Expected:
```
Lock regenerated: 158 tests
  suiteSha256 <64 hex chars>
  gateSha256  <64 hex chars>
```

- [ ] **Step 3: Verify the lock's shape**

Run:
```bash
jq '.tests | length' tests/oracle.lock.json
jq '[.tests[] | select(.conditional)] | length' tests/oracle.lock.json
jq -r '.tests[0]' tests/oracle.lock.json
jq -e '[.tests[] | select(.story == null)] | length == 0' tests/oracle.lock.json
```

Expected: `158`, `2`, a well-formed first entry with `name` and `story`, and `true` for the no-null-story check.

- [ ] **Step 4: Commit**

```bash
bash -n tests/oracle-gate.sh
shellcheck tests/oracle-gate.sh
git add tests/oracle-gate.sh tests/oracle.lock.json .github/workflows/ci.yml
git commit -m "test: add oracle gate parser and lock generator

Runtime names come from a real suite run; the parser strips ANSI and
splits on the first ': ' only, because all 158 names contain ': '
themselves. Integrity comes from whole-file hashes of the suite and
the gate."
```

Also add `tests/oracle-gate.sh` to the shellcheck list in `.github/workflows/ci.yml` line 29 as part of this commit.

---

### Task 11: Implement the gate rules

**Files:**
- Modify: `tests/oracle-gate.sh`

**Interfaces:**
- Consumes: `tests/oracle.lock.json`, the parser from Task 10.
- Produces: `bash tests/oracle-gate.sh` exiting 0 on an unmodified tree and non-zero with a named rule on any violation.

**Context — rules in strict precedence order.** Precedence matters because the suite's last command is `[ "$FAIL" -eq 0 ]`, so after P0 *any* FAIL makes the suite exit non-zero. Without precedence, an exit-code-based truncation rule would re-label every weakening as truncation — re-conflating the two signals P0 exists to separate.

| Rule | Condition | Verdict |
|---|---|---|
| R7 | `suiteSha256` or `gateSha256` mismatch | `NEEDS_HUMAN` |
| R2 | A locked name reported `FAIL` | Baseline weakened |
| R3 | A locked name reported `SKIP` | Silent weakening — exempted when its `conditional` is unmet |
| R6 | A result name is absent from the lock | `NEEDS_HUMAN` — register it with `--accept` |
| R1 | A locked name absent from output | Renamed or deleted (diagnostic) |
| R0 | Result count < `len(tests)` **and** no FAIL parsed | `SUITE_TRUNCATED` |

- [ ] **Step 1: Replace the final `echo` line in `tests/oracle-gate.sh` with the rules**

```bash
[ -f "$LOCK" ] || { echo "FATAL: no lock at $LOCK — run --accept first" >&2; exit 1; }

jq -r '.tests[].name' "$LOCK" | sort > "$WORK/locked.txt"
LOCK_COUNT=$(jq '.tests | length' "$LOCK")
RAN_COUNT=$(wc -l < "$WORK/ran.txt" | tr -d ' ')
FAIL_COUNT=$(awk -F'\t' '$1=="FAIL"' "$WORK/results.tsv" | wc -l | tr -d ' ')

fail() { echo "GATE FAIL [$1] $2" >&2; VERDICT=1; }
VERDICT=0

# ── R7: file integrity ──────────────────────────────────────────────────
locked_suite=$(jq -r .suiteSha256 "$LOCK")
locked_gate=$(jq -r .gateSha256 "$LOCK")
actual_suite=$(hash_file "$SUITE")
actual_gate=$(hash_file "$GATE")
if [ "$locked_suite" != "$actual_suite" ]; then
  fail R7 "NEEDS_HUMAN: tests/simple-test.sh changed (locked $locked_suite, actual $actual_suite). Review the diff, then re-lock with --accept."
fi
if [ "$locked_gate" != "$actual_gate" ]; then
  fail R7 "NEEDS_HUMAN: tests/oracle-gate.sh changed (locked $locked_gate, actual $actual_gate). Review the diff, then re-lock with --accept."
fi

# ── R2: a locked test reported FAIL ─────────────────────────────────────
while IFS=$'\t' read -r verdict name; do
  [ "$verdict" = "FAIL" ] || continue
  if grep -qxF "$name" "$WORK/locked.txt"; then
    fail R2 "baseline weakened: '$name' FAILED"
  fi
done < "$WORK/results.tsv"

# ── R3: a locked test reported SKIP (conditional entries exempted) ───────
while IFS=$'\t' read -r verdict name; do
  [ "$verdict" = "SKIP" ] || continue
  grep -qxF "$name" "$WORK/locked.txt" || continue
  cond=$(jq -r --arg n "$name" '.tests[] | select(.name == $n) | .conditional // ""' "$LOCK")
  case "$cond" in
    "")
      fail R3 "silent weakening: '$name' SKIPPED and is not conditional"
      ;;
    claude)
      if command -v claude >/dev/null; then
        fail R3 "'$name' SKIPPED but its condition (claude) is met"
      fi
      ;;
    *)
      fail R3 "unknown conditional '$cond' on '$name' — the enum is {claude}"
      ;;
  esac
done < "$WORK/results.tsv"

# ── R6: a test ran that the lock does not know about ────────────────────
unregistered=$(comm -23 "$WORK/ran.txt" "$WORK/locked.txt")
if [ -n "$unregistered" ]; then
  fail R6 "NEEDS_HUMAN: unregistered tests ran; add them with --accept:"
  printf '%s\n' "$unregistered" | sed 's/^/    /' >&2
fi

# ── R1: a locked test did not run (diagnostic) ──────────────────────────
missing=$(comm -13 "$WORK/ran.txt" "$WORK/locked.txt")
if [ -n "$missing" ]; then
  fail R1 "locked tests did not run (renamed or deleted):"
  printf '%s\n' "$missing" | sed 's/^/    /' >&2
fi

# ── R0: truncation, only when nothing failed ────────────────────────────
if [ "$RAN_COUNT" -lt "$LOCK_COUNT" ] && [ "$FAIL_COUNT" -eq 0 ]; then
  fail R0 "SUITE_TRUNCATED: $RAN_COUNT of $LOCK_COUNT results emitted, no FAIL parsed"
fi

if [ "$VERDICT" -eq 0 ]; then
  echo "oracle-gate: OK — $RAN_COUNT/$LOCK_COUNT locked tests ran, suite exit $SUITE_RC"
fi
exit "$VERDICT"
```

- [ ] **Step 2: Re-lock, because the gate hashed itself before these rules existed**

Run: `bash tests/oracle-gate.sh --accept`

Expected: `Lock regenerated: 158 tests` with a new `gateSha256`.

- [ ] **Step 3: Run the gate on a clean tree**

Run: `bash tests/oracle-gate.sh; echo "EXIT=$?"`

Expected:
```
oracle-gate: OK — 158/158 locked tests ran, suite exit 0
EXIT=0
```

- [ ] **Step 4: Commit**

```bash
bash -n tests/oracle-gate.sh
shellcheck tests/oracle-gate.sh
git add tests/oracle-gate.sh tests/oracle.lock.json
git commit -m "test: implement freeze gate rules R7/R2/R3/R6/R1/R0

Strict precedence: after P0 any FAIL makes the suite exit non-zero,
so a truncation rule keyed on the exit code would re-label every
weakening as truncation. R0 therefore fires only when the result
count is short AND no FAIL was parsed.

conditional is a closed enum of one member (claude); an unrecognized
value hard-fails rather than exempting, so it cannot be used as a
one-word kill switch."
```

---

### Task 12: Prove every gate rule actually fires

**Files:**
- Create: `tests/gate-selftest.sh`
- Modify: `.github/workflows/ci.yml` (shellcheck list)

**Interfaces:**
- Consumes: `tests/oracle-gate.sh`, `tests/oracle.lock.json`.
- Produces: `bash tests/gate-selftest.sh` exiting 0 only when each of R7, R2, R6, R0 has been demonstrated to fire on a scratch copy.

**Context:** A gate nobody has seen fire is a gate nobody knows works. Each rule gets a scratch copy of the repo, one targeted violation, and an assertion that the gate names that rule. **After this task, changing any test name is a `NEEDS_HUMAN` event** — R7 will fire on any edit to `tests/simple-test.sh`.

- [ ] **Step 1: Write the self-test**

Create `tests/gate-selftest.sh`:

```bash
#!/usr/bin/env bash
# Demonstrate that each freeze-gate rule fires. Operates on scratch copies;
# the working tree is never modified.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASSED=0; FAILED=0

scratch() {
  local d
  d=$(mktemp -d) || return 1
  (cd "$PROJECT_ROOT" && git ls-files -z | tar --null -T - -cf -) | (cd "$d" && tar -xf -)
  printf '%s\n' "$d"
}

# expect_rule <rule> <description> <mutator-function>
expect_rule() {
  local rule="$1" desc="$2" mutate="$3" dir out rc
  dir=$(scratch) || { echo "FAIL: $desc (scratch failed)"; FAILED=$((FAILED+1)); return; }
  "$mutate" "$dir"
  out=$(cd "$dir" && bash tests/oracle-gate.sh 2>&1); rc=$?
  rm -rf "$dir"
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "GATE FAIL \[$rule\]"; then
    echo "PASS: $rule fires — $desc"; PASSED=$((PASSED+1))
  else
    echo "FAIL: $rule did not fire — $desc (exit $rc)"
    printf '%s\n' "$out" | sed 's/^/    /'
    FAILED=$((FAILED+1))
  fi
}

mut_r7_reporter() {
  # The attack a per-body hash misses: patch the reporter, leave every body intact.
  sed -i 's|  if \[ "\$status" -eq 0 \]; then|  if true; then|' "$1/tests/simple-test.sh"
}
mut_r7_body() {
  sed -i '0,/^  set -e$/s/^  set -e$/  set -e\n  true/' "$1/tests/simple-test.sh"
}
mut_r2_fail() {
  # Break a library function so a locked test genuinely fails, then re-lock
  # the suite hash so R7 does not mask R2.
  sed -i 's|^load_checkpoint() {|load_checkpoint() {\n  return 1|' "$1/lib/run.sh"
  (cd "$1" && bash tests/oracle-gate.sh --accept >/dev/null 2>&1)
}
mut_r6_unregistered() {
  cat >> "$1/tests/simple-test.sh" <<'EOF'

(
  set -e
  true
)
test_result "selftest: an unregistered assertion" $?
EOF
  # Re-lock only the file hashes, not the test list, to isolate R6 from R7.
  (cd "$1" && jq --arg s "$(sha256sum tests/simple-test.sh | cut -d' ' -f1)" \
    '.suiteSha256 = $s' tests/oracle.lock.json > /tmp/l.json && mv /tmp/l.json tests/oracle.lock.json)
}
mut_r0_truncate() {
  # Add a locked-but-unrunnable tail: exit early so later results never print.
  sed -i '60i exit 0' "$1/tests/simple-test.sh"
  (cd "$1" && jq --arg s "$(sha256sum tests/simple-test.sh | cut -d' ' -f1)" \
    '.suiteSha256 = $s' tests/oracle.lock.json > /tmp/l.json && mv /tmp/l.json tests/oracle.lock.json)
}

echo "=== oracle-gate self-test ==="
expect_rule R7 "reporter patched to always PASS"        mut_r7_reporter
expect_rule R7 "an assertion body edited"               mut_r7_body
expect_rule R2 "a locked test genuinely fails"          mut_r2_fail
expect_rule R6 "an unregistered assertion ran"          mut_r6_unregistered
expect_rule R0 "the suite exits before emitting results" mut_r0_truncate

echo "=== $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ]
```

- [ ] **Step 2: Run the self-test**

Run: `bash tests/gate-selftest.sh; echo "EXIT=$?"`

Expected:
```
PASS: R7 fires — reporter patched to always PASS
PASS: R7 fires — an assertion body edited
PASS: R2 fires — a locked test genuinely fails
PASS: R6 fires — an unregistered assertion ran
PASS: R0 fires — the suite exits before emitting results
=== 5 passed, 0 failed ===
EXIT=0
```

If R2 does not fire, check that `mut_r2_fail`'s `--accept` re-lock succeeded — `--accept` refuses when `spec-map` is not total, and the mutated tree's suite still maps fine, so a refusal means something else broke.

- [ ] **Step 3: Confirm the working tree is untouched**

Run: `git status --short`

Expected: only the new `tests/gate-selftest.sh` as untracked. No modification to `tests/simple-test.sh` or `tests/oracle.lock.json`.

- [ ] **Step 4: Commit**

```bash
bash -n tests/gate-selftest.sh
shellcheck tests/gate-selftest.sh
bash tests/oracle-gate.sh
git add tests/gate-selftest.sh .github/workflows/ci.yml
git commit -m "test: demonstrate every freeze-gate rule fires

The R7 reporter case is the one that matters: all lib/*.sh emptied
and test_result patched to print PASS unconditionally leaves every
assertion body byte-identical, which is why a per-body hash was not
enough and the freeze is a whole-file hash."
```

Add `tests/gate-selftest.sh` to the shellcheck list in `.github/workflows/ci.yml` line 29 in this same commit.

---

### Task 13: Wire the gate into CI

**Files:**
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `tests/oracle-gate.sh`, `tests/gate-selftest.sh`.
- Produces: a CI job that fails the build on any freeze violation. **From here on, every commit must leave `bash tests/oracle-gate.sh` exiting 0.**

- [ ] **Step 1: Add the job**

Append to `.github/workflows/ci.yml`:

```yaml
  oracle-gate:
    name: Freeze gate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Enforce the frozen oracle
        run: bash tests/oracle-gate.sh

      - name: Prove the gate rules fire
        run: bash tests/gate-selftest.sh
```

No `fetch-depth` is needed: the gate compares file hashes against the lock in the same tree and never consults a remote or a merge base.

- [ ] **Step 2: Verify the whole CI surface locally**

Run:
```bash
for f in bin/reqdrive lib/*.sh install.sh tests/simple-test.sh tests/run-tests.sh \
         tests/mutate.sh tests/spec-map.sh tests/oracle-gate.sh tests/gate-selftest.sh; do
  bash -n "$f" || echo "SYNTAX FAIL: $f"
  shellcheck "$f" || echo "LINT FAIL: $f"
done
bash tests/simple-test.sh > /dev/null && echo "suite OK"
bash tests/oracle-gate.sh
```

Expected: no `SYNTAX FAIL` or `LINT FAIL` lines, `suite OK`, and `oracle-gate: OK — 158/158`.

- [ ] **Step 3: Confirm the gate runs where `claude` is absent**

Run: `PATH=$(echo "$PATH" | tr ':' '\n' | grep -v 'npm' | paste -sd: -) bash tests/oracle-gate.sh; echo "EXIT=$?"`

Expected: `EXIT=0`. The two `claude`-gated tests now emit `SKIP` under their locked names, and R3 exempts them because their `conditional` is `claude` and the condition is unmet. This is the CI configuration, so it must be green here.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: enforce the freeze gate and prove its rules fire

The gate needs no fetch-depth and no base-ref checkout — it compares
file hashes against the lock in the same tree, so it behaves
identically on a laptop with no remote and in CI."
```

---

**P2 exit gate.** Before starting P3:

```bash
bash tests/simple-test.sh      # 158 passed, 0 failed, exit 0
bash tests/spec-map.sh         # 158 of 158 mapped, exit 0
bash tests/oracle-gate.sh      # OK — 158/158, exit 0
bash tests/gate-selftest.sh    # 5 passed, 0 failed, exit 0
```

From this point, any change to `tests/simple-test.sh` fires R7 and must be re-locked with `bash tests/oracle-gate.sh --accept` in the same commit that makes the change — a deliberate, reviewable act. Every later task that adds an assertion says so explicitly.

---

# Phase P3 — Pipeline test harness

**Why:** Nothing in the repo invokes `run_pipeline` — `grep -n 'run_pipeline' tests/simple-test.sh` returns nothing. P4's fail-closed draft gate and P6b's `verify` command both need to drive a real pipeline run.

---

### Task 14: Build the fake-agent pipeline harness

**Files:**
- Create: `tests/lib/pipeline-harness.sh`
- Modify: `tests/simple-test.sh` (new "Pipeline Harness" section)
- Modify: `tests/oracle.lock.json` (via `--accept`)
- Modify: `README.md` (prerequisites)

**Interfaces:**
- Consumes: `lib/run.sh`.
- Produces these functions, used by Tasks 17-19 and 29-30:
  - `ph_setup <dir>` — builds a scratch git repo with `reqdrive.json`, a base branch, and `docs/requirements/REQ-01-demo.md`; exports `PH_ROOT`, `PH_BIN`.
  - `ph_fake_claude <mode>` — installs a fake `claude` on `PATH`. Modes: `full` (emits a 2-story PRD then per-story summaries then the completion signal), `noprd` (never writes `prd.json`), `nopasses` (writes a PRD whose stories omit `passes`).
  - `ph_fake_gh` — installs a fake `gh` recording every invocation to `$PH_ROOT/gh-args.log`, printing a PR URL on `pr create`.
  - `ph_run <req-id>` — runs `run_pipeline` in a subshell with `set -euo pipefail`; echoes the exit code.
  - `ph_gh_args` — prints the recorded `gh` invocation log.

**Context, three fidelity traps:**
1. `lib/run.sh:6` sets bare `set -e`, not `pipefail`. But `run_claude_iteration` detects agent failure through `if timeout 1800 claude ... | tee ...` — a pipeline whose status is `tee`'s unless `pipefail` is on. A harness that sources `lib/run.sh` without `set -o pipefail` validates a path that can never fail, so `ph_run` sets `set -euo pipefail` explicitly.
2. `run_pipeline` terminates with `exit` (`lib/run.sh:1186`, `:1189`), not `return`. `ph_run` must call it in a subshell and capture the code.
3. `timeout` (coreutils) is a hard runtime dependency of `run_claude_iteration` and is undocumented. This task adds it to README prerequisites.

- [ ] **Step 1: Write the harness**

Create `tests/lib/pipeline-harness.sh`:

```bash
#!/usr/bin/env bash
# Drive lib/run.sh's run_pipeline against fake claude/gh binaries in a
# scratch git repo. Sourced by tests/simple-test.sh.
# shellcheck disable=SC2317  # fake-binary bodies look unreachable to shellcheck

ph_setup() {
  PH_ROOT="$1"
  PH_BIN="$PH_ROOT/bin"
  mkdir -p "$PH_ROOT/docs/requirements" "$PH_BIN"

  git -C "$PH_ROOT" init -q
  git -C "$PH_ROOT" config user.email "test@example.com"
  git -C "$PH_ROOT" config user.name "Test"
  git -C "$PH_ROOT" checkout -q -b main

  cat > "$PH_ROOT/reqdrive.json" <<'EOF'
{
  "version": "0.3.0",
  "requirementsDir": "docs/requirements",
  "testCommand": "",
  "maxIterations": 3,
  "baseBranch": "main"
}
EOF

  cat > "$PH_ROOT/docs/requirements/REQ-01-demo.md" <<'EOF'
# REQ-01: Demo requirement

Add a marker file.

## Acceptance Criteria
- A file named MARKER.txt exists
EOF

  git -C "$PH_ROOT" add -A
  git -C "$PH_ROOT" commit -q -m "chore: scaffold"
  export PH_ROOT PH_BIN
}

# ph_fake_claude full|noprd|nopasses
ph_fake_claude() {
  local mode="$1"
  cat > "$PH_BIN/claude" <<PHEOF
#!/usr/bin/env bash
# Fake agent. Reads a prompt on stdin, writes artifacts, prints a summary.
set -u
cat > /dev/null   # consume the prompt
mode="$mode"
run_dir="\$(ls -d "$PH_ROOT"/.reqdrive/runs/* 2>/dev/null | head -1)"
[ -n "\$run_dir" ] || { echo "no run dir"; exit 0; }
prd="\$run_dir/prd.json"

if [ ! -f "\$prd" ] && [ "\$mode" != "noprd" ]; then
  if [ "\$mode" = "nopasses" ]; then
    cat > "\$prd" <<'JEOF'
{"version":"0.3.0","project":"demo","sourceReq":"REQ-01",
 "userStories":[
   {"id":"US-001","title":"First","description":"d","acceptanceCriteria":["a"],"priority":1},
   {"id":"US-002","title":"Second","description":"d","acceptanceCriteria":["a"],"priority":2}]}
JEOF
  else
    cat > "\$prd" <<'JEOF'
{"version":"0.3.0","project":"demo","sourceReq":"REQ-01",
 "userStories":[
   {"id":"US-001","title":"First","description":"d","acceptanceCriteria":["a"],"priority":1,"passes":false},
   {"id":"US-002","title":"Second","description":"d","acceptanceCriteria":["a"],"priority":2,"passes":false}]}
JEOF
  fi
  echo "Planning complete."
  exit 0
fi

# Implementation turn: mark the highest-priority incomplete story done.
if [ -f "\$prd" ] && [ "\$mode" = "full" ]; then
  next=\$(jq -r '[.userStories[] | select(.passes == false)] | sort_by(.priority) | .[0].id // empty' "\$prd")
  if [ -n "\$next" ]; then
    jq --arg id "\$next" '(.userStories[] | select(.id == \$id)).passes = true' "\$prd" > "\$prd.t" && mv "\$prd.t" "\$prd"
    echo "impl \$next" >> "$PH_ROOT/MARKER.txt"
    git -C "$PH_ROOT" add -A
    git -C "$PH_ROOT" commit -q -m "feat: [\$next] - work"
    echo '\`\`\`json:iteration-summary'
    echo "{\"storyId\":\"\$next\",\"action\":\"implemented\",\"filesChanged\":[\"MARKER.txt\"],\"testsRun\":true,\"testsPassed\":true,\"committed\":true,\"notes\":\"ok\"}"
    echo '\`\`\`'
    remaining=\$(jq '[.userStories[] | select(.passes == false)] | length' "\$prd")
    [ "\$remaining" -eq 0 ] && echo "<promise>COMPLETE</promise>"
    exit 0
  fi
fi
echo "nothing to do"
exit 0
PHEOF
  chmod +x "$PH_BIN/claude"
}

ph_fake_gh() {
  cat > "$PH_BIN/gh" <<PHEOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$PH_ROOT/gh-args.log"
case "\$1 \$2" in
  "pr create") echo "https://github.com/test/repo/pull/1" ;;
  *) : ;;
esac
exit 0
PHEOF
  chmod +x "$PH_BIN/gh"
}

# ph_run <req-id> — returns run_pipeline's exit code
ph_run() {
  local req="$1"
  (
    set -euo pipefail
    export PATH="$PH_BIN:$PATH"
    export REQDRIVE_ROOT="$REQDRIVE_ROOT"
    export REQDRIVE_INTERACTIVE=false
    export REQDRIVE_UNSAFE=true
    cd "$PH_ROOT"
    source "$REQDRIVE_ROOT/lib/errors.sh"
    source "$REQDRIVE_ROOT/lib/schema.sh"
    source "$REQDRIVE_ROOT/lib/sanitize.sh"
    source "$REQDRIVE_ROOT/lib/config.sh"
    source "$REQDRIVE_ROOT/lib/preflight.sh"
    source "$REQDRIVE_ROOT/lib/run.sh"
    reqdrive_load_config
    run_pipeline "$req"
  ) >"$PH_ROOT/run.log" 2>&1
  echo $?
}

ph_gh_args() { cat "$PH_ROOT/gh-args.log" 2>/dev/null || true; }
```

- [ ] **Step 2: Write the failing end-to-end assertion**

Append to `tests/simple-test.sh`, before the "Harness Safety" section added in Task 1:

```bash
echo ""
echo "--- Pipeline Harness ---"

# Test: a scripted run reaches PR creation
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/ph-e2e"
  ph_fake_claude full
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "0" ]
  ph_gh_args | grep -q "pr create"
)
test_result "pipeline: scripted run reaches PR creation" $?
```

- [ ] **Step 3: Run to verify it fails**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'pipeline:|Results:'`

Expected: `FAIL: pipeline: scripted run reaches PR creation` — `tests/lib/pipeline-harness.sh` does not exist yet if you wrote Step 2 first, or the fake agent is not yet wired. Read `$TEST_TEMP/ph-e2e/run.log` to see where the pipeline stopped. Iterate on the harness until it passes; the harness is the deliverable, so debugging it here is the work, not a detour.

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'pipeline:|Results:'`

Expected:
```
PASS: pipeline: scripted run reaches PR creation
  Results: 159 passed, 0 failed, 0 skipped, 159 total
```

- [ ] **Step 5: Document `timeout` and `sha256sum` as prerequisites**

In `README.md`, find the Prerequisites list and add:

```markdown
- `timeout` and `sha256sum` (GNU coreutils — present by default on Linux, macOS via `brew install coreutils`, and in Git-Bash/MSYS2)
```

- [ ] **Step 6: Re-lock and commit**

```bash
bash -n tests/lib/pipeline-harness.sh tests/simple-test.sh
shellcheck tests/lib/pipeline-harness.sh
bash tests/oracle-gate.sh --accept
bash tests/oracle-gate.sh
git add tests/lib/pipeline-harness.sh tests/simple-test.sh tests/oracle.lock.json README.md
git commit -m "test: add pipeline harness driving run_pipeline end to end

Nothing invoked run_pipeline before this. Three fidelity traps are
handled explicitly: ph_run sets pipefail (lib/run.sh sets bare set -e,
but agent failure is detected through a claude|tee pipeline), it
captures run_pipeline's exit rather than its return, and README now
documents the undocumented timeout dependency."
```

Note: `tests/lib/pipeline-harness.sh` is sourced, not linted by the CI list — add it to the shellcheck line in `.github/workflows/ci.yml` in this commit as well.

---

### Task 15: Convert the bats escape hatches to hard assertions

**Files:**
- Modify: `tests/e2e/pipeline.bats:146, 223, 253, 301, 302, 338`

**Interfaces:**
- Consumes: the deterministic fake `claude` from Task 14.
- Produces: an e2e suite that can actually fail. **From here on, `bats tests/unit tests/e2e` must pass with zero skips in `tests/e2e/`.**

**Context:** All six sites end in `|| skip`. Round-3 verification gutted `build_implementation_prompt` to write an empty file and return 0; bats reported `ok 11 ... # skip` and exited 0. Three of these six guard the exact function P6a rewrites, so until they are hard assertions, "bats green" is not evidence of anything. The hatches exist because a real `claude` was unavailable; Task 14's fake removes that reason.

- [ ] **Step 1: Replace each hatch with a hard assertion**

`tests/e2e/pipeline.bats:146`:

```bash
  git branch | grep -q "reqdrive/req-01"
```

`:223`:

```bash
  grep -q "XYZ123" "$TEST_TEMP_DIR/.reqdrive/runs/req-01/prompt.md"
```

`:253`:

```bash
  [[ -f "$TEST_TEMP_DIR/.reqdrive/runs/req-01/iteration-plan-1.log" ]]
```

`:301-302`:

```bash
  grep -q "US-001" "$TEST_TEMP_DIR/.reqdrive/runs/req-01/prompt.md"
  grep -q "First story" "$TEST_TEMP_DIR/.reqdrive/runs/req-01/prompt.md"
```

`:338`:

```bash
  grep -q "claude-opus-4-5-20251101" /tmp/claude-args.log
```

- [ ] **Step 2: Run bats and fix what genuinely breaks**

Run: `bats tests/e2e/pipeline.bats`

Expected: all 12 tests pass with **zero** `# skip` markers. If a test now fails, its setup is incomplete — make the setup deterministic using the same fake-agent approach as Task 14 rather than restoring the hatch.

If bats is unavailable on Git-Bash, run it in Docker:

```bash
docker run --rm -v "$PWD":/w -w /w bats/bats:latest tests/e2e tests/unit
```

- [ ] **Step 3: Prove the e2e suite can now fail**

```bash
cp lib/run.sh /tmp/run.sh.bak
sed -i 's|^build_implementation_prompt() {|build_implementation_prompt() {\n  : > "$1"; return 0|' lib/run.sh
bats tests/e2e/pipeline.bats; echo "EXIT=$?"
cp /tmp/run.sh.bak lib/run.sh
```

Expected: `EXIT=1` with at least one `not ok`. Before this task the same mutation produced `EXIT=0`. Confirm `lib/run.sh` is restored: `git diff --stat lib/run.sh` must be empty.

- [ ] **Step 4: Verify the skip count is zero**

Run: `bats --formatter tap tests/e2e | grep -c '# skip'`

Expected: `0`.

- [ ] **Step 5: Commit**

```bash
bash tests/simple-test.sh > /dev/null && bash tests/oracle-gate.sh
git add tests/e2e/pipeline.bats
git commit -m "test: convert the six e2e skip hatches to hard assertions

Gutting build_implementation_prompt used to produce 'ok ... # skip'
and a green bats run, so the three e2e tests named as the safety net
for the P6 heredoc rewrite could not fail. The deterministic fake
agent removes the reason the hatches existed."
```

---

### Task 16: Add the zero-skip check to CI

**Files:**
- Modify: `.github/workflows/ci.yml` (the `test-bats` job)

**Interfaces:**
- Consumes: Task 15's hard assertions.
- Produces: CI that fails if any `tests/e2e/` test skips.

- [ ] **Step 1: Add the check to the bats job**

In the `test-bats` job, after the existing bats run step:

```yaml
      - name: Fail on any e2e skip
        run: |
          skips=$(bats --formatter tap tests/e2e | grep -c '# skip' || true)
          echo "e2e skips: $skips"
          [ "$skips" -eq 0 ]
```

- [ ] **Step 2: Verify locally**

Run: `bats --formatter tap tests/e2e | grep -c '# skip' || true`

Expected: `0`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: fail the build on any e2e skip

'bats green' meant nothing while six tests could skip themselves."
```

---

**P3 exit gate.**

```bash
bash tests/simple-test.sh                          # 159 passed, 0 failed
bash tests/oracle-gate.sh                          # OK — 159/159
bats tests/unit tests/e2e                          # all pass
bats --formatter tap tests/e2e | grep -c '# skip'  # 0
```

---

# Phase P4 — Close all three draft-gate fail-opens

**Why:** The draft gate at `lib/run.sh:1168-1173` fail-opens three ways, so a PR can present as ready-to-merge with no evidence behind it:

- **(A)** `verification_passed: null` when no `testCommand` is configured (`:1116`) — the gate tests only for the literal string `"false"`.
- **(B)** Missing `prd.json` — `final_remaining` initializes to the sentinel `"?"` (`:1077`) and is overwritten only inside `if [ -f "$prd_file" ]` (`:1082-1092`), so a run whose planning failed ships a **non-draft PR with no PRD at all**.
- **(C)** `passes` omitted from a story — `lib/schema.sh:138` guards with `has("passes")`, so the field is optional, and `select(.passes == false)` does not match `null`. Verified: 3 stories, 1 passing, 2 omitting the field yields `remaining: 0` and no draft, while `lib/pr-create.sh:138-139` prints "1/3 completed."

Enumerating negatives is a losing game, so the gate is **inverted to fail-closed**: draft by default, cleared only on positive evidence.

---

### Task 17: Write the three failing assertions

**Files:**
- Modify: `tests/simple-test.sh` (new "Draft Gate" section)
- Modify: `tests/oracle.lock.json` (via `--accept`)

**Interfaces:**
- Consumes: `ph_setup`, `ph_fake_claude`, `ph_fake_gh`, `ph_run`, `ph_gh_args` from Task 14.
- Produces: four assertions — three fail-open cases plus a positive control — that Task 18 must turn green.

- [ ] **Step 1: Write all four assertions**

Append to `tests/simple-test.sh` before the "Harness Safety" section:

```bash
echo ""
echo "--- Draft Gate ---"

# Test: fail-open A — no testCommand means no evidence, so draft
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-a"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  ph_gh_args | grep -q "pr create" 
  ph_gh_args | grep "pr create" | grep -q -- "--draft"
)
test_result "draft gate: no testCommand forces draft" $?

# Test: fail-open B — no prd.json means no plan, so draft
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-b"
  ph_fake_claude noprd
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  ph_gh_args | grep "pr create" | grep -q -- "--draft"
)
test_result "draft gate: missing prd.json forces draft" $?

# Test: fail-open C — stories omitting 'passes' are not complete, so draft
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-c"
  ph_fake_claude nopasses
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  ph_gh_args | grep "pr create" | grep -q -- "--draft"
)
test_result "draft gate: stories omitting passes force draft" $?

# Test: positive control — full evidence produces a non-draft PR
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-ok"
  jq '.testCommand = "true"' "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.tmp"
  mv "$PH_ROOT/r.tmp" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: enable testCommand"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  ph_gh_args | grep -q "pr create"
  ! ph_gh_args | grep "pr create" | grep -q -- "--draft"
)
test_result "draft gate: full evidence produces non-draft PR" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'draft gate:|Results:'`

Expected — the three fail-open assertions FAIL, the positive control PASSES:
```
FAIL: draft gate: no testCommand forces draft
FAIL: draft gate: missing prd.json forces draft
FAIL: draft gate: stories omitting passes force draft
PASS: draft gate: full evidence produces non-draft PR
  Results: 160 passed, 3 failed, 0 skipped, 163 total
```

This is the first genuine red-first moment in the plan, and it is only observable because of P0. If the suite truncates instead of reporting three FAILs, P0 regressed — stop and re-run `bash tests/mutate.sh impl-prompt-return1`.

- [ ] **Step 3: Commit the red tests**

Commit the failing tests on their own so the red state is in history, then make them green in Task 18. Do **not** run `--accept` yet — the lock must not record a failing baseline.

```bash
bash -n tests/simple-test.sh
git add tests/simple-test.sh
git commit -m "test: add failing assertions for all three draft-gate fail-opens

Red first. A run with no testCommand, a run with no prd.json, and a
run whose stories omit 'passes' all currently produce a non-draft PR
with no evidence behind it. The positive control passes already, so
the fix cannot simply force --draft unconditionally."
```

---

### Task 18: Invert the draft gate to fail-closed

**Files:**
- Modify: `lib/run.sh:1077` (sentinel), `lib/run.sh:1082-1092` (story counting), `lib/run.sh:1167-1173` (draft decision)
- Modify: `tests/oracle.lock.json` (via `--accept`)

**Interfaces:**
- Consumes: Task 17's four assertions.
- Produces: `PRD_PRESENT` (`0|1`) and an integer `final_remaining` inside `run_pipeline`. Task 29 replaces both with `VERIFY_PRD_PRESENT` and `VERIFY_STORIES_REMAINING` when the phase is extracted.

- [ ] **Step 1: Replace the sentinel with an explicit presence flag**

At `lib/run.sh:1077`, replace:

```bash
  local final_remaining="?"
```

with:

```bash
  local final_remaining=0
  local prd_present=0
```

- [ ] **Step 2: Set the flag and count `passes != true`**

In the `if [ -f "$prd_file" ]` block at `lib/run.sh:1082-1092`, set the flag and change the counting so a missing `passes` field counts as incomplete:

```bash
  if [ -f "$prd_file" ]; then
    prd_present=1
    stories_total=$(jq '.userStories | length' "$prd_file" 2>/dev/null || echo "0")
    stories_completed=$(jq '[.userStories[] | select(.passes == true)] | length' "$prd_file" 2>/dev/null || echo "0")
    final_remaining=$(jq '[.userStories[] | select(.passes != true)] | length' "$prd_file" 2>/dev/null || echo "0")

    local max_story_retries_check="${REQDRIVE_MAX_STORY_RETRIES:-3}"
    stories_failed=$(jq --argjson max "$max_story_retries_check" \
      '[.userStories[] | select(.passes != true and ((.attempts // 0) >= $max))] | length' \
      "$prd_file" 2>/dev/null || echo "0")
  fi
```

- [ ] **Step 3: Keep the JSON artifact honest**

At `lib/run.sh:1132`, the summary currently emits `null` for `remaining` when the sentinel was set. Preserve that contract and record presence explicitly:

```bash
    "remaining": $([ "$prd_present" -eq 1 ] && echo "$final_remaining" || echo "null")
  },
  "prd_present": $([ "$prd_present" -eq 1 ] && echo "true" || echo "false"),
```

Place the `prd_present` line immediately after the closing brace of the `stories` object.

- [ ] **Step 4: Invert the gate**

Replace `lib/run.sh:1167-1173` (the `draft_flag` block) with:

```bash
  # Fail-closed: draft unless every piece of positive evidence is present.
  local draft_flag="--draft"
  if [ "$prd_present" -eq 1 ] && [ "$final_remaining" -eq 0 ] && [ "$verification_passed" = "true" ]; then
    draft_flag=""
  else
    if [ "$prd_present" -ne 1 ]; then
      log_warn "No prd.json — creating draft PR"
    elif [ "$final_remaining" -ne 0 ]; then
      log_warn "$final_remaining stories incomplete — creating draft PR"
    elif [ "$verification_passed" = "null" ]; then
      log_warn "No testCommand configured, so nothing verified the output — creating draft PR"
    else
      log_warn "Final verification failed — creating draft PR"
    fi
  fi
```

Delete the earlier advisory block at `lib/run.sh:1154-1157` that warned about incomplete stories; the message above replaces it and no longer references the `"?"` sentinel.

- [ ] **Step 5: Run the assertions**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'draft gate:|Results:'`

Expected: all four PASS, `163 passed, 0 failed`.

- [ ] **Step 6: Confirm the existing verification assertions survived**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'verification|run_status|^FAIL'`

Expected: the five *Run Summary & Verification* assertions still PASS and no `FAIL:` lines appear.

- [ ] **Step 7: Re-lock and commit**

```bash
bash -n lib/run.sh
shellcheck lib/run.sh
bash tests/oracle-gate.sh --accept
bash tests/oracle-gate.sh
git add lib/run.sh tests/oracle.lock.json
git commit -m "fix: invert the draft gate to fail-closed

The gate cleared --draft on three separate no-evidence paths: null
verification, a missing prd.json left holding the '?' sentinel, and
stories omitting the optional 'passes' field, which select(.passes ==
false) never matched. Enumerating those negatives is a losing game,
so the PR is now a draft unless the PRD exists, zero stories remain,
and verification positively passed.

verification-summary.json keeps emitting remaining: null when no PRD
exists, and gains prd_present so the two cases stay distinguishable."
```

---

### Task 19: Surface the consequence of the default empty `testCommand`

**Files:**
- Modify: `lib/preflight.sh` (new check), `lib/pr-create.sh` (reason line)
- Modify: `tests/simple-test.sh`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: the tri-state distinction between "tests failed" and "no test command configured".
- Produces: `check_test_command_configured` in `lib/preflight.sh`, and a reason line in the PR body.

**Context:** `testCommand` defaults to `""`, so after Task 18 a default-configured project gets a draft PR on **every** run. That is the intended policy, but it must not be a mystery. This task makes the reason visible in two places — at run start and in the PR body — and it is the only thing that makes the `verification_passed: null` state worth distinguishing from `false`.

- [ ] **Step 1: Write the failing assertions**

Append to the "Draft Gate" section of `tests/simple-test.sh`:

```bash
# Test: preflight warns when no testCommand is configured
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  out=$(REQDRIVE_TEST_COMMAND="" check_test_command_configured 2>&1) || true
  echo "$out" | grep -q "all PRs will be created as drafts"
)
test_result "preflight: warns when no testCommand is configured" $?

# Test: preflight is silent when a testCommand exists
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  out=$(REQDRIVE_TEST_COMMAND="npm test" check_test_command_configured 2>&1) || true
  [ -z "$out" ]
)
test_result "preflight: silent when testCommand is configured" $?

# Test: PR body distinguishes 'not configured' from 'tests failed'
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/dg-reason"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  body_file=$(grep -o -- '--body-file [^ ]*' "$PH_ROOT/gh-args.log" | head -1 | cut -d' ' -f2)
  grep -q "no test command configured" "$body_file"
)
test_result "pr: body states why verification was not run" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'preflight: warns|preflight: silent|pr: body states'`

Expected: all three FAIL — `check_test_command_configured` does not exist.

- [ ] **Step 3: Add the preflight check**

Append to `lib/preflight.sh`:

```bash
# Warn when no testCommand is configured. Nothing will independently verify
# the agent's output, so every PR will be created as a draft.
check_test_command_configured() {
  if [ -z "${REQDRIVE_TEST_COMMAND:-}" ]; then
    echo "[WARN]  No testCommand configured — nothing will verify the agent's output, so all PRs will be created as drafts." >&2
    return 0
  fi
  return 0
}
```

Call it from `run_preflight_checks` alongside the existing checks. It always returns 0 — it warns, it does not gate.

- [ ] **Step 4: Add the PR-body reason line**

In `lib/pr-create.sh`, where the verification section is built from `verification-summary.json`, add a reason line driven by `verification_passed`:

```bash
  local vp
  vp=$(jq -r '.verification_passed' "$summary_file" 2>/dev/null || echo "null")
  case "$vp" in
    true)  verification_reason="Verification passed." ;;
    false) verification_reason="Verification failed — tests did not pass." ;;
    *)     verification_reason="Not verified — no test command configured." ;;
  esac
```

and emit `$verification_reason` into the body. The lowercase substring `no test command configured` is what the assertion in Step 1 matches.

- [ ] **Step 5: Run to verify green**

Run: `bash tests/simple-test.sh 2>&1 | tail -4`

Expected: `166 passed, 0 failed`.

- [ ] **Step 6: Re-lock and commit**

```bash
bash -n lib/preflight.sh lib/pr-create.sh
shellcheck lib/preflight.sh lib/pr-create.sh
bash tests/oracle-gate.sh --accept
bash tests/oracle-gate.sh
git add lib/preflight.sh lib/pr-create.sh tests/simple-test.sh tests/oracle.lock.json
git commit -m "feat: explain why a run produced a draft PR

testCommand defaults to empty, so after the fail-closed inversion a
default-configured project gets a draft on every run. Preflight now
says so at run start and the PR body distinguishes 'no test command
configured' from 'tests failed' — which is what makes the tri-state
worth carrying rather than collapsing to a boolean."
```

---

**P4 exit gate.**

```bash
bash tests/simple-test.sh      # 166 passed, 0 failed
bash tests/oracle-gate.sh      # OK
bash tests/gate-selftest.sh    # 5 passed
bats tests/unit tests/e2e      # all pass, zero e2e skips
```

L2 is now earned: every PR that presents as ready-to-merge has a PRD, zero incomplete stories, and a test command that positively passed.

---

# Phase P5 — Make L3 a standing gate, not a milestone

**Why:** The measured L3 blocker is undocumented public surface. WORKFLOW.md's L3 criterion — "a cold agent completes a canonical task from docs alone" — is not reproducible in CI, but the thing that actually blocks the cold agent is: commands, config fields and flags that exist in code and not in `README.md`. Three coverage tests turn that into a standing gate, so P6 and P7 cannot ship undocumented surface either.

---

### Task 20: Doc-coverage rule 1 — every command is documented

**Files:**
- Modify: `tests/simple-test.sh` (new "Doc Coverage" section), `README.md`
- Modify: `tests/oracle.lock.json` (via `--accept`)

**Interfaces:**
- Consumes: the dispatch block at `bin/reqdrive:538-582`.
- Produces: an assertion that fails whenever a dispatch label has no README row. Tasks 30 (`verify`) depends on it firing.

**Context:** The dispatch `case` runs from `bin/reqdrive:538` to `esac` at `:582`. Labels are indented two spaces, so trim leading whitespace before matching. Keep only labels matching `^[a-z][a-z-]*)$` — that excludes `-v|--version)`, `-h|--help|"")` and `*)`, none of which is a command. Nine labels qualify: `init run validate status migrate plan orchestrate launch logs`. `README.md:45-55` documents seven, so this test **fails on `plan` and `orchestrate`**.

- [ ] **Step 1: Write the failing assertion**

Append to `tests/simple-test.sh` before the "Harness Safety" section:

```bash
echo ""
echo "--- Doc Coverage ---"

# Test: every dispatch command appears in README
(
  set -e
  cmds=$(awk '/^case "\$\{1:-\}" in$/,/^esac$/' "$REQDRIVE_ROOT/bin/reqdrive" \
    | sed 's/^[[:space:]]*//' \
    | grep -E '^[a-z][a-z-]*\)$' \
    | tr -d ')')
  [ -n "$cmds" ]
  missing=""
  for c in $cmds; do
    grep -q "reqdrive $c" "$REQDRIVE_ROOT/README.md" || missing="$missing $c"
  done
  [ -z "$missing" ] || { echo "undocumented commands:$missing" >&2; false; }
)
test_result "docs: every CLI command is documented in README" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep -A1 'docs: every CLI'`

Expected:
```
undocumented commands: plan orchestrate
FAIL: docs: every CLI command is documented in README
```

If the extracted `cmds` list is empty the `awk` range did not match — check the exact text of the `case` line in `bin/reqdrive:538` and adjust the pattern to match it literally.

- [ ] **Step 3: Document both commands**

Add to the Commands table in `README.md` (after the `reqdrive migrate` row):

```markdown
| `reqdrive plan <REQ-ID>` | Generate `prd.json` only — planning phase without implementation. Useful for reviewing the plan before committing agent time. |
| `reqdrive orchestrate` | Multi-requirement sequencing. **Not implemented** — prints a "coming soon" notice and exits 0. |
```

- [ ] **Step 4: Run to verify green**

Run: `bash tests/simple-test.sh 2>&1 | grep 'docs: every CLI'`

Expected: `PASS: docs: every CLI command is documented in README`

- [ ] **Step 5: Re-lock and commit**

```bash
bash -n tests/simple-test.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add tests/simple-test.sh README.md tests/oracle.lock.json
git commit -m "docs: document plan and orchestrate, gated by a coverage test

The dispatch block accepts nine commands; README documented seven.
The test parses the live case block, so adding a command in a later
phase reddens the suite until README catches up."
```

---

### Task 21: Doc-coverage rule 2 — every config field is documented

**Files:**
- Modify: `tests/simple-test.sh`, `README.md`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: `lib/config.sh`'s `REQDRIVE_*` exports.
- Produces: an assertion that fails whenever a config field has no README entry. Task 32 (`policy`) depends on it firing.

**Context:** `lib/config.sh` exports 12 `REQDRIVE_*` variables. Two are derived paths rather than config fields and must be exempted with a justifying comment: `REQDRIVE_MANIFEST` (the resolved manifest path) and `REQDRIVE_PROJECT_ROOT` (its parent directory). `REQDRIVE_ROOT` is the install directory, also not a config field. Of the remainder, README documents eight — this test **fails on `maxStoryRetries` and `reviewCommand`**.

- [ ] **Step 1: Write the failing assertion**

Append to the "Doc Coverage" section:

```bash
# Test: every config-backed REQDRIVE_* variable is documented in README
(
  set -e
  # DOC_EXEMPT — derived at runtime, not settable in reqdrive.json:
  #   REQDRIVE_MANIFEST      resolved path of the found manifest
  #   REQDRIVE_PROJECT_ROOT  parent directory of the manifest
  #   REQDRIVE_ROOT          reqdrive's own install directory
  exempt="REQDRIVE_MANIFEST REQDRIVE_PROJECT_ROOT REQDRIVE_ROOT"
  vars=$(grep -oE 'REQDRIVE_[A-Z_]+' "$REQDRIVE_ROOT/lib/config.sh" | sort -u)
  [ -n "$vars" ]
  missing=""
  for v in $vars; do
    case " $exempt " in *" $v "*) continue ;; esac
    # REQDRIVE_MAX_STORY_RETRIES -> maxStoryRetries
    field=$(printf '%s\n' "${v#REQDRIVE_}" | awk -F_ '{
      out = tolower($1)
      for (i = 2; i <= NF; i++) out = out toupper(substr($i,1,1)) tolower(substr($i,2))
      print out
    }')
    grep -q "$field" "$REQDRIVE_ROOT/README.md" || missing="$missing $field"
  done
  [ -z "$missing" ] || { echo "undocumented config fields:$missing" >&2; false; }
)
test_result "docs: every config field is documented in README" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep -A1 'docs: every config'`

Expected:
```
undocumented config fields: maxStoryRetries reviewCommand
FAIL: docs: every config field is documented in README
```

- [ ] **Step 3: Document both fields**

Add to the configuration table in `README.md`:

```markdown
| `maxStoryRetries` | `3` | number | Maximum attempts per user story. `select_next_story` skips a story once its `attempts` counter reaches this value, so a story that cannot be implemented does not consume the whole iteration budget. |
| `reviewCommand` | `""` | string | Post-PR review step. `"builtin"` runs a Claude review of the diff; any other non-empty string is executed as a shell command. Findings are appended to the PR body. Warn-only — it never aborts the pipeline, and it runs after PR creation, so it cannot change the draft decision. |
```

- [ ] **Step 4: Run to verify green**

Run: `bash tests/simple-test.sh 2>&1 | grep 'docs: every config'`

Expected: `PASS: docs: every config field is documented in README`

- [ ] **Step 5: Re-lock and commit**

```bash
bash -n tests/simple-test.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add tests/simple-test.sh README.md tests/oracle.lock.json
git commit -m "docs: document maxStoryRetries and reviewCommand, gated by a test

Both have lived in config.sh without a README entry. The exemption
list covers the three derived REQDRIVE_* variables that are not
config fields, each with a justifying comment."
```

---

### Task 22: Doc-coverage rule 3 — every flag is documented

**Files:**
- Modify: `tests/simple-test.sh`, `README.md`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: the option-parsing `case` blocks at `bin/reqdrive:95-126` and `:400-422`.
- Produces: an assertion that fails whenever a flag has no README entry. Task 30's `--ref` depends on it firing — without this rule, `--ref` would ship undocumented while the suite read green.

**Context:** Parse **case labels**, not free `--[a-z-]+` literals: `bin/reqdrive:114` contains `echo "Run 'reqdrive run --help' for usage."`, and a free-literal parse would false-positive on that `--help`. The real labels are `-i|--interactive)`, `--unsafe|--dangerously-skip-permissions)`, `--force)`, `--resume)`. README's Run Options table at `:59-64` documents four — this test **fails on `--dangerously-skip-permissions`**, which is a genuine accepted flag.

- [ ] **Step 1: Write the failing assertion**

Append to the "Doc Coverage" section:

```bash
# Test: every accepted CLI flag is documented in README
(
  set -e
  flags=$(sed -n '90,130p;395,425p' "$REQDRIVE_ROOT/bin/reqdrive" \
    | sed 's/^[[:space:]]*//' \
    | grep -E '^(-[a-z]\|)?--[a-z-]+(\|--[a-z-]+)*\)$' \
    | tr -d ')' | tr '|' '\n' \
    | grep -E '^--' | sort -u)
  [ -n "$flags" ]
  missing=""
  for f in $flags; do
    grep -q -- "$f" "$REQDRIVE_ROOT/README.md" || missing="$missing $f"
  done
  [ -z "$missing" ] || { echo "undocumented flags:$missing" >&2; false; }
)
test_result "docs: every CLI flag is documented in README" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep -A1 'docs: every CLI flag'`

Expected:
```
undocumented flags: --dangerously-skip-permissions
FAIL: docs: every CLI flag is documented in README
```

If the extracted list is empty, widen the `sed` line ranges — the option blocks may have shifted by a line or two from earlier edits. The ranges are deliberately a few lines wider than the blocks themselves for that reason.

- [ ] **Step 3: Document the alias**

Add to the Run Options table in `README.md`, under the `--unsafe` row:

```markdown
| `--dangerously-skip-permissions` | Alias for `--unsafe`. Accepted for parity with the `claude` CLI's own flag name. Grants the agent unrestricted system access; `launch` always uses this mode because a detached run cannot answer permission prompts. |
```

- [ ] **Step 4: Run to verify green**

Run: `bash tests/simple-test.sh 2>&1 | grep 'docs: every CLI flag'`

Expected: `PASS: docs: every CLI flag is documented in README`

- [ ] **Step 5: Re-lock and commit**

```bash
bash -n tests/simple-test.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add tests/simple-test.sh README.md tests/oracle.lock.json
git commit -m "docs: document --dangerously-skip-permissions, gated by a test

Parses case labels rather than free -- literals, so the --help inside
the usage string at bin/reqdrive:114 is not a false positive."
```

---

### Task 23: Relocate and correct the stale audit

**Files:**
- Move: `reqdrive-audit.md` → `docs/audits/2026-02-16-pipeline-audit.md`

**Interfaces:**
- Consumes: nothing.
- Produces: an audit whose false claim is retracted in place.

**Context:** `reqdrive-audit.md` is untracked, 626 lines, and states reqdrive "validates inputs exhaustively but never verifies outputs." That is false: `lib/run.sh:1106-1117` re-runs `testCommand` and derives `verification_passed` from the real exit code. The reasoning that produced the Tier 1/2/3 roadmap is worth keeping, so correct it rather than delete it.

- [ ] **Step 1: Move the file**

```bash
mkdir -p docs/audits
git mv reqdrive-audit.md docs/audits/2026-02-16-pipeline-audit.md 2>/dev/null \
  || mv reqdrive-audit.md docs/audits/2026-02-16-pipeline-audit.md
```

`git mv` fails if the file was never tracked; the fallback handles that.

- [ ] **Step 2: Add the correction preamble**

Insert at the very top of `docs/audits/2026-02-16-pipeline-audit.md`, above the existing `# reqdrive Pipeline — Audit Report` heading:

```markdown
> **Historical document — dated 2026-02-16. Corrections appended 2026-07-23.**
>
> **Retracted claim:** this audit states that reqdrive "validates inputs
> exhaustively but never verifies outputs." That is **false** as of the
> verification phase. `lib/run.sh:1106-1117` re-runs the configured
> `testCommand` and derives `verification_passed` from the process exit
> code — an independent output check, not agent self-report.
>
> **Still true, and worse than this audit found:** the draft-PR gate
> fail-opened three ways (null verification, missing `prd.json`, and
> stories omitting the optional `passes` field). All three are closed by
> the fail-closed inversion in
> [`docs/superpowers/specs/2026-07-23-reqdrive-roadmap-completion-design.md`](../superpowers/specs/2026-07-23-reqdrive-roadmap-completion-design.md).
>
> The Tier 1/2/3 recommendations below drove the roadmap in `CLAUDE.md`
> and are retained as the reasoning behind it.

```

- [ ] **Step 3: Verify the retraction is findable**

Run: `head -20 docs/audits/2026-02-16-pipeline-audit.md | grep -c 'Retracted claim'`

Expected: `1`.

- [ ] **Step 4: Commit**

```bash
git add docs/audits/2026-02-16-pipeline-audit.md
git rm --cached reqdrive-audit.md 2>/dev/null || true
git commit -m "docs: relocate the pipeline audit and retract its false claim

The audit says reqdrive 'never verifies outputs'. lib/run.sh:1106-1117
re-runs testCommand and reads the real exit code, so that is false.
The reasoning that produced the roadmap is kept; only the claim is
corrected, in place and dated."
```

---

### Task 24: Automate the launch lifecycle plan

**Files:**
- Modify: `tests/simple-test.sh`, `docs/LAUNCH-TEST-PLAN.md`, `tests/oracle.lock.json`
- Create: `tests/launch-lifecycle.sh`
- Modify: `.github/workflows/ci.yml` (new Linux-only job)

**Interfaces:**
- Consumes: `ph_setup` from Task 14.
- Produces: `bash tests/launch-lifecycle.sh` covering the process-dependent cases, run only on Linux CI.

**Context:** `docs/LAUNCH-TEST-PLAN.md` is 8 manual cases. Cases **2, 5, 7, 8** (status of a finished run, exit-code reporting, completion hook, re-launch) assert on `run.json` state and go into the main suite. Cases **1, 4, 6** (detached launch, duplicate-launch block, crash detection) depend on real background processes, PID liveness and `kill -9` semantics, which `CLAUDE.md` records as unreliable under MSYS2. They go into a **Linux-only CI job** rather than a `conditional` lock exemption: an always-exempt test on the primary platform is a deleted test with ceremony. Case 3 (`logs` tailing) asserts process behavior, not interactivity.

- [ ] **Step 1: Add the state-transition assertions to the main suite**

Append to `tests/simple-test.sh` a "Launch Lifecycle" section covering cases 2, 5, 7 and 8 by writing `run.json` directly and invoking `cmd_status` / the completion hook, rather than spawning processes. Example for case 5:

```bash
echo ""
echo "--- Launch Lifecycle ---"

# Test: status reports a completed run with its exit code and PR URL
(
  set -e
  run_dir="$TEST_TEMP/ll-completed/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  cat > "$run_dir/run.json" <<'EOF'
{"version":"0.3.0","req_id":"REQ-01","status":"completed","pid":999999,
 "iteration":2,"exit_code":0,"pr_url":"https://github.com/test/repo/pull/7",
 "started":"2026-07-23T10:00:00Z","updated":"2026-07-23T10:05:00Z"}
EOF
  out=$(cd "$TEST_TEMP/ll-completed" && "$REQDRIVE_ROOT/bin/reqdrive" status REQ-01 2>&1) || true
  echo "$out" | grep -q "completed"
  echo "$out" | grep -q "pull/7"
)
test_result "launch: status reports a completed run with its PR URL" $?

# Test: status reports a crashed run when the PID is gone
(
  set -e
  run_dir="$TEST_TEMP/ll-crashed/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  cat > "$run_dir/run.json" <<'EOF'
{"version":"0.3.0","req_id":"REQ-01","status":"running","pid":999999,
 "iteration":1,"started":"2026-07-23T10:00:00Z","updated":"2026-07-23T10:01:00Z"}
EOF
  out=$(cd "$TEST_TEMP/ll-crashed" && "$REQDRIVE_ROOT/bin/reqdrive" status REQ-01 2>&1) || true
  echo "$out" | grep -qi "crashed"
)
test_result "launch: status reports a crashed run when the PID is gone" $?
```

Add equivalent assertions for case 7 (completion hook fires with `REQ_ID`, `STATUS`, `EXIT_CODE` in the environment — `run_completion_hook` already has coverage, so extend it to assert the variable values) and case 8 (re-launch after completion is permitted because `run.json` status is not `running`).

PID `999999` is used because it is above the default `pid_max` on Linux and therefore reliably dead; if `kill -0 999999` succeeds on the test machine, pick another.

- [ ] **Step 2: Write the Linux-only process tests**

Create `tests/launch-lifecycle.sh` covering cases 1, 4 and 6: launch a detached run against the Task 14 fake agent, assert `Launched` output and a `running` status; attempt a second launch and assert it is refused with a non-zero exit; `kill -9` the PID and assert `status` reports `crashed`. Guard the whole file:

```bash
#!/usr/bin/env bash
# Launch lifecycle cases that need real background processes.
# Linux only — nohup, PID liveness and signal trapping are unreliable
# under MSYS2 (see CLAUDE.md, Known Pitfalls).
set -uo pipefail

case "$(uname -s)" in
  Linux) ;;
  *) echo "SKIP: launch lifecycle requires Linux (got $(uname -s))"; exit 0 ;;
esac
```

- [ ] **Step 3: Add the CI job**

```yaml
  launch-lifecycle:
    name: Launch lifecycle (Linux only)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run launch lifecycle tests
        run: bash tests/launch-lifecycle.sh
```

- [ ] **Step 4: Convert the manual plan into a pointer**

Replace the body of `docs/LAUNCH-TEST-PLAN.md` with a short document stating which automated test now covers each of the eight cases, and noting that cases 1, 4 and 6 run only in the Linux CI job. Keep the setup snippet — it is still useful for manual exploration.

- [ ] **Step 5: Run everything**

```bash
bash tests/simple-test.sh 2>&1 | tail -3
bash tests/launch-lifecycle.sh
```

Expected: suite green; `launch-lifecycle.sh` either passes or prints the Linux-only skip line and exits 0 on Windows.

- [ ] **Step 6: Re-lock and commit**

```bash
bash -n tests/simple-test.sh tests/launch-lifecycle.sh
shellcheck tests/launch-lifecycle.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add tests/simple-test.sh tests/launch-lifecycle.sh docs/LAUNCH-TEST-PLAN.md \
        .github/workflows/ci.yml tests/oracle.lock.json
git commit -m "test: automate the launch lifecycle plan

Cases 2/5/7/8 assert run.json state transitions and join the main
suite. Cases 1/4/6 need real background processes and PID liveness,
unreliable under MSYS2, so they run in a Linux-only CI job rather
than via a lock exemption — an always-exempt test is a deleted test
with ceremony."
```

Add `tests/launch-lifecycle.sh` to the shellcheck list in `.github/workflows/ci.yml` in this commit.

---

**P5 exit gate.**

```bash
bash tests/simple-test.sh      # all green
bash tests/oracle-gate.sh      # OK
bats tests/unit tests/e2e      # all pass, zero e2e skips
```

Adding a command, config field or flag from here on reddens the suite until `README.md` documents it. L3 is now a standing gate rather than a milestone.

---

# Phase P6 — Tier 2 mechanical work

Two independent pieces: the heredoc structural fix (Tasks 25-28) and the verification extraction plus `reqdrive verify` (Tasks 29-30).

**Discipline note:** Tasks 26 and 29 are *refactors*, so they get characterization tests — lock the current output, require it unchanged. Red-green is the wrong tool there. Task 28 is a deliberate behavior *correction*, so it changes the locked output in its own commit with every changed byte-range enumerated. Task 30 is new behavior and is red-first.

---

### Task 25: Freeze the current prompt output in a golden file

**Files:**
- Create: `tests/fixtures/golden-impl-prompt.md`, `tests/fixtures/golden-story.json`
- Modify: `tests/simple-test.sh`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: `build_implementation_prompt` at `lib/run.sh:279`.
- Produces: `tests/fixtures/golden-impl-prompt.md`, the byte-exact oracle Tasks 26-28 are measured against. **This is the sole named oracle for the rewrite** — the bats e2e tests are a secondary check and only trustworthy after Task 15 removed their skip hatches.

**Context:** The fixture must exercise every hazard the rewrite could break: `&` (bash ≥5.2 `patsub_replacement` expands it in an unquoted replacement), `\`, a backtick, a `$`, and the literal `@@STORY_ID@@` placeholder token.

- [ ] **Step 1: Write the fixture**

Create `tests/fixtures/golden-story.json`:

```json
{
  "id": "US-042",
  "title": "Handle auth & billing $HOME with `id` and a \\ backslash",
  "description": "Covers @@STORY_ID@@ forgery, ampersands & escapes, and ${VAR} expansion",
  "acceptanceCriteria": [
    "Given input with & and \\, the output is unchanged",
    "Check ${HOME} is not expanded"
  ],
  "priority": 1,
  "passes": false
}
```

- [ ] **Step 2: Generate the golden file from current behavior**

```bash
bash -c '
  export REQDRIVE_ROOT="$PWD"
  source lib/errors.sh; source lib/sanitize.sh; source lib/schema.sh
  source lib/preflight.sh; source lib/run.sh
  build_implementation_prompt tests/fixtures/golden-impl-prompt.md \
    "US-042" "$(cat tests/fixtures/golden-story.json)" "Requirement body with & and \$VAR"
'
```

- [ ] **Step 3: Inspect what current behavior actually produces**

Run: `grep -n 'Title:\|Commit with message\|progress file' tests/fixtures/golden-impl-prompt.md`

Expected: you will see stray backslashes before `$` — e.g. `**Title:** Handle auth & billing \$HOME with 'id' ...`. That is the live defect from `lib/sanitize.sh:43` (`$` → `\$`), which bash does not re-scan out of an expanded variable's value. **Do not fix it here.** Task 26 must reproduce it byte-for-byte; Task 28 removes it deliberately.

- [ ] **Step 4: Write the characterization assertion**

Append to `tests/simple-test.sh` in the "Prompt Builders" area:

```bash
# Test: implementation prompt matches the frozen golden file byte for byte
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true
  out="$TEST_TEMP/golden-check.md"
  build_implementation_prompt "$out" "US-042" \
    "$(cat "$REQDRIVE_ROOT/tests/fixtures/golden-story.json")" \
    'Requirement body with & and $VAR'
  diff -u "$REQDRIVE_ROOT/tests/fixtures/golden-impl-prompt.md" "$out"
)
test_result "prompt: implementation prompt matches golden file" $?
```

- [ ] **Step 5: Verify it passes against current code**

Run: `bash tests/simple-test.sh 2>&1 | grep 'prompt: implementation prompt matches'`

Expected: `PASS`. A characterization test passes immediately by construction — that is the point. Its value arrives in Task 26.

- [ ] **Step 6: Re-lock and commit**

```bash
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add tests/fixtures/golden-story.json tests/fixtures/golden-impl-prompt.md \
        tests/simple-test.sh tests/oracle.lock.json
git commit -m "test: freeze the implementation prompt in a golden file

Characterization, not red-green — this locks current behavior so the
heredoc rewrite can be proven byte-identical. The fixture carries &,
backslash, backtick, \$ and a literal @@STORY_ID@@ so every hazard
the rewrite could introduce is in the oracle."
```

---

### Task 26: Rewrite the heredoc as quoted with parameter injection

**Files:**
- Modify: `lib/run.sh:279-364` (`build_implementation_prompt`)

**Interfaces:**
- Consumes: the golden file from Task 25.
- Produces: `build_implementation_prompt` with the same signature and byte-identical output. No caller changes.

**Context, four traps:**
1. The body between `lib/run.sh:298` and `:363` contains **24 backtick characters, all backslash-escaped, zero bare** — at lines `:315, :316, :320, :321, :322, :327, :333, :340, :346, :356`, with the three fence lines carrying 3 each. A quoted heredoc performs no escape processing, so every one must be de-escaped or the output gains literal backslashes. This is a hand-edit, not a delimiter flip.
2. Replacement expressions must be **quoted**: `${tpl//@@TOKEN@@/"$val"}`. Unquoted, bash ≥5.2's `patsub_replacement` (verified `on` by default) expands `&` in the replacement to the matched text, so the `&` in the fixture title would inject a live `@@STORY_TITLE@@` into the prompt.
3. `shopt -u patsub_replacement 2>/dev/null` **must** be suffixed `|| true`. The option does not exist before bash 5.2, `shopt -u` on an unknown option returns 1, `2>/dev/null` hides the message but not the status, and `lib/run.sh:6` sets `set -e` — so without `|| true` the pipeline aborts on exactly the bash 4.x/5.0/5.1 versions the control exists to protect. Verified.
4. Order the substitutions so `@@REQUIREMENT@@` (the largest, least controlled value) goes last.

- [ ] **Step 1: Rewrite the function**

Replace `lib/run.sh:279-364` entirely:

```bash
build_implementation_prompt() {
  local prompt_file="$1"
  local story_id="$2"
  local story_json="$3"
  local sanitized_content="$4"

  # Pin replacement semantics: bash >= 5.2 expands & in a //-replacement to
  # the matched text. The option does not exist before 5.2 and shopt -u
  # returns 1 on an unknown option, which set -e would turn into an abort.
  shopt -u patsub_replacement 2>/dev/null || true

  local story_title story_description story_criteria
  story_title=$(echo "$story_json" | jq -r '.title')
  story_description=$(echo "$story_json" | jq -r '.description')
  story_criteria=$(echo "$story_json" | jq -r '.acceptanceCriteria | map("- " + .) | join("\n")')

  # Sanitize PRD-derived fields. The heredoc below is quoted, so this is no
  # longer shell-escaping — it is prompt-injection defence (backticks) and
  # placeholder-forgery defence (@@ tokens).
  story_id=$(sanitize_for_prompt "$story_id")
  story_title=$(sanitize_for_prompt "$story_title")
  story_description=$(sanitize_for_prompt "$story_description")
  story_criteria=$(sanitize_for_prompt "$story_criteria")

  # Strip placeholder tokens so PRD content cannot forge one.
  story_id="${story_id//@@/}"
  story_title="${story_title//@@/}"
  story_description="${story_description//@@/}"
  story_criteria="${story_criteria//@@/}"

  local tpl
  tpl=$(cat <<'PROMPT_IMPL'
# Agent Instructions: Implement Story @@STORY_ID@@

You are an autonomous coding agent. Implement the following user story.

## Your Story

- **ID:** @@STORY_ID@@
- **Title:** @@STORY_TITLE@@
- **Description:** @@STORY_DESCRIPTION@@

### Acceptance Criteria

@@STORY_CRITERIA@@

## Instructions

1. Read the progress file in the `.reqdrive/runs/` directory for context from previous iterations
2. Read the `prd.json` file in the same run directory for full PRD context
3. Implement **this story only** (@@STORY_ID@@)
4. Run quality checks (test, typecheck, lint as appropriate)
5. If checks pass:
   - Commit with message: `feat: [@@STORY_ID@@] - @@STORY_TITLE@@`
   - Update PRD: set `passes: true` for story @@STORY_ID@@
   - Append progress to `progress.txt`

## Progress Format

Append to progress.txt:
```
## [Date] - @@STORY_ID@@
- What was implemented
- Files changed
- Learnings for future iterations
---
```

## Important

- Implement ONLY story @@STORY_ID@@
- Commit after completing the story
- Keep tests passing
- If you discover a dependency issue, update priorities in prd.json and leave this story as `passes: false`

## Iteration Summary

At the END of your response, output a summary:

```json:iteration-summary
{
  "storyId": "@@STORY_ID@@",
  "action": "implemented|skipped|failed",
  "filesChanged": ["path/to/file"],
  "testsRun": true,
  "testsPassed": true,
  "committed": true,
  "notes": "Brief description"
}
```

---

## Requirement Document (Reference)

@@REQUIREMENT@@
PROMPT_IMPL
)

  # Quoted replacements — unquoted, & in a value expands to the match.
  tpl="${tpl//@@STORY_TITLE@@/"$story_title"}"
  tpl="${tpl//@@STORY_DESCRIPTION@@/"$story_description"}"
  tpl="${tpl//@@STORY_CRITERIA@@/"$story_criteria"}"
  tpl="${tpl//@@STORY_ID@@/"$story_id"}"
  tpl="${tpl//@@REQUIREMENT@@/"$sanitized_content"}"

  printf '%s\n' "$tpl" > "$prompt_file"
}
```

Note the backticks in the template are now **bare** — all 24 escapes removed — because a quoted heredoc does no escape processing.

- [ ] **Step 2: Run the golden check**

Run: `bash tests/simple-test.sh 2>&1 | grep -A20 'prompt: implementation prompt matches'`

Expected: `PASS`. If `diff` output appears, it names the exact byte-ranges that differ — the usual causes are a missed backtick escape, a trailing-newline difference from `printf` versus `cat`, or a substitution ordering problem. Fix the rewrite until the diff is empty; **do not edit the golden file in this task.**

- [ ] **Step 3: Verify the three injection assertions still pass**

Run: `bash tests/simple-test.sh 2>&1 | grep 'impl prompt:'`

Expected: all three PASS, unmodified.

- [ ] **Step 4: Verify the bats e2e prompt tests still pass**

Run: `bats tests/e2e/pipeline.bats`

Expected: all pass, zero skips. These are meaningful now that Task 15 removed the hatches.

- [ ] **Step 5: Prove the `&` hazard is actually handled**

```bash
bash -c '
  export REQDRIVE_ROOT="$PWD"
  source lib/errors.sh; source lib/sanitize.sh; source lib/schema.sh
  source lib/preflight.sh; source lib/run.sh
  build_implementation_prompt /tmp/amp.md "US-1" \
    "{\"id\":\"US-1\",\"title\":\"auth & billing\",\"description\":\"d\",\"acceptanceCriteria\":[\"a\"]}" "body"
  grep -c "@@" /tmp/amp.md
'
```

Expected: `0`. No placeholder token survives into the output.

- [ ] **Step 6: Commit**

```bash
bash -n lib/run.sh && shellcheck lib/run.sh
bash tests/oracle-gate.sh
git add lib/run.sh
git commit -m "refactor: quoted heredoc with parameter injection for the impl prompt

Byte-identical output, proven by the golden file. Three traps handled:
all 24 backslash-escaped backticks de-escaped (a quoted heredoc does
no escape processing), replacements quoted so bash >= 5.2 does not
expand & in a value to the matched text, and shopt -u suffixed with
|| true because the option does not exist before 5.2 and set -e would
turn its exit 1 into an abort."
```

---

### Task 27: Assert the bash-compatibility and forgery guards

**Files:**
- Modify: `tests/simple-test.sh`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: Task 26's rewritten function.
- Produces: assertions pinning the two guards that are invisible in the golden file.

**Context:** The golden file proves the output is unchanged, but it cannot prove the function survives a bash without `patsub_replacement`, nor that `@@` stripping works — the fixture's `@@STORY_ID@@` is inside a description that would look plausible either way. Both need their own assertions.

- [ ] **Step 1: Write the assertions**

```bash
# Test: prompt builder survives a shell without patsub_replacement
(
  set -e
  # Simulate bash < 5.2 by proving the unknown-option path does not abort.
  out=$(bash -c '
    set -e
    shopt -u definitely_not_an_option 2>/dev/null || true
    echo SURVIVED
  ')
  [ "$out" = "SURVIVED" ]
  grep -q 'shopt -u patsub_replacement 2>/dev/null || true' "$REQDRIVE_ROOT/lib/run.sh"
)
test_result "prompt: shopt guard tolerates bash without patsub_replacement" $?

# Test: PRD content cannot forge a placeholder token
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true
  out="$TEST_TEMP/forge.md"
  build_implementation_prompt "$out" "US-1" \
    '{"id":"US-1","title":"@@STORY_ID@@ and @@REQUIREMENT@@","description":"d","acceptanceCriteria":["a"]}' \
    "body text"
  ! grep -q '@@' "$out"
  grep -q 'body text' "$out"
)
test_result "prompt: PRD content cannot forge a placeholder token" $?

# Test: an ampersand in a story title survives verbatim
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true
  out="$TEST_TEMP/amp.md"
  build_implementation_prompt "$out" "US-1" \
    '{"id":"US-1","title":"auth & billing","description":"d","acceptanceCriteria":["a"]}' \
    "body"
  grep -q '\*\*Title:\*\* auth & billing' "$out"
)
test_result "prompt: ampersand in a title is not expanded to the match" $?
```

- [ ] **Step 2: Run**

Run: `bash tests/simple-test.sh 2>&1 | grep 'prompt: shopt\|prompt: PRD content\|prompt: ampersand'`

Expected: all three PASS.

- [ ] **Step 3: Prove the ampersand assertion would have caught the bug**

```bash
cp lib/run.sh /tmp/run.bak
sed -i 's|tpl="${tpl//@@STORY_TITLE@@/"\$story_title"}"|tpl="${tpl//@@STORY_TITLE@@/$story_title}"|' lib/run.sh
sed -i 's|shopt -u patsub_replacement 2>/dev/null \|\| true|shopt -s patsub_replacement 2>/dev/null \|\| true|' lib/run.sh
bash tests/simple-test.sh 2>&1 | grep 'prompt: ampersand'
cp /tmp/run.bak lib/run.sh
```

Expected: `FAIL: prompt: ampersand in a title is not expanded to the match`. Confirm restoration: `git diff --stat lib/run.sh` is empty.

- [ ] **Step 4: Re-lock and commit**

```bash
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add tests/simple-test.sh tests/oracle.lock.json
git commit -m "test: pin the patsub and placeholder-forgery guards

The golden file proves output is unchanged but cannot see either
guard. Both now have assertions, and the ampersand case is proven to
fail when the replacement is unquoted."
```

---

### Task 28: Correct the stray-backslash defect, enumerated

**Files:**
- Modify: `lib/run.sh` (`build_implementation_prompt`), `tests/fixtures/golden-impl-prompt.md`, `tests/simple-test.sh`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: Task 26's byte-identical rewrite.
- Produces: prompts free of shell-escaping artifacts. **This is the only task permitted to change the golden file.**

**Context:** `sanitize_for_prompt` (`lib/sanitize.sh:43`) rewrites `$` → `\$`. That escaping existed because the heredoc was unquoted; it is now pointless, and the backslash reaches the agent — including inside the commit message the agent is instructed to use (`lib/run.sh:320`). `lib/sanitize.sh` is **not** modified: its backtick neutralization is load-bearing for the injection assertion, and it has other callers. The un-escape happens at injection time instead.

- [ ] **Step 1: Un-escape at injection**

In `build_implementation_prompt`, immediately after the four `sanitize_for_prompt` calls and before the `@@`-stripping block, add:

```bash
  # sanitize_for_prompt escapes $ for an unquoted heredoc. The heredoc is
  # quoted now and this file is never re-evaluated by a shell, so the
  # backslash is pure noise that reaches the agent — including inside the
  # commit message it is told to use. Reverse it here rather than changing
  # sanitize_for_prompt, which has other callers.
  story_id="${story_id//\\$/$}"
  story_title="${story_title//\\$/$}"
  story_description="${story_description//\\$/$}"
  story_criteria="${story_criteria//\\$/$}"
  sanitized_content="${sanitized_content//\\$/$}"
```

- [ ] **Step 2: Observe the golden diff and enumerate it**

Run: `bash tests/simple-test.sh 2>&1 | grep -A30 'prompt: implementation prompt matches'`

Expected: `FAIL` with a `diff -u` naming each changed line. Copy that diff — it is the enumeration this task's commit message must carry.

- [ ] **Step 3: Regenerate the golden file**

```bash
bash -c '
  export REQDRIVE_ROOT="$PWD"
  source lib/errors.sh; source lib/sanitize.sh; source lib/schema.sh
  source lib/preflight.sh; source lib/run.sh
  build_implementation_prompt tests/fixtures/golden-impl-prompt.md \
    "US-042" "$(cat tests/fixtures/golden-story.json)" "Requirement body with & and \$VAR"
'
git diff --stat tests/fixtures/golden-impl-prompt.md
```

- [ ] **Step 4: Add the positive assertion**

```bash
# Test: a dollar sign in a story title reaches the prompt verbatim
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/sanitize.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/preflight.sh"
  source "$REQDRIVE_ROOT/lib/run.sh" 2>/dev/null || true
  out="$TEST_TEMP/dollar.md"
  build_implementation_prompt "$out" "US-9" \
    '{"id":"US-9","title":"Fix $HOME handling","description":"d","acceptanceCriteria":["a"]}' \
    "body"
  grep -q '\*\*Title:\*\* Fix \$HOME handling' "$out"
  ! grep -q 'Fix \\\$HOME' "$out"
  # The commit message the agent is told to use must be clean too.
  grep -q 'feat: \[US-9\] - Fix \$HOME handling' "$out"
)
test_result "prompt: dollar signs reach the agent without stray backslashes" $?
```

- [ ] **Step 5: Update the two assertions written in Task 4**

Task 4 added positive checks asserting the escaped form (`Check \\${HOME} variable`). Update them to the un-escaped form now that the defect is fixed — this is expected churn from a deliberate correction, not a regression.

- [ ] **Step 6: Run everything**

```bash
bash tests/simple-test.sh 2>&1 | tail -4
bats tests/e2e/pipeline.bats
```

Expected: suite green; bats green with zero skips.

- [ ] **Step 7: Re-lock and commit with the enumeration**

```bash
bash -n lib/run.sh && shellcheck lib/run.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add lib/run.sh tests/fixtures/golden-impl-prompt.md tests/simple-test.sh tests/oracle.lock.json
git commit -m "fix: stop emitting stray backslashes into the agent's prompt

sanitize_for_prompt escapes \$ to \\\$ for an unquoted heredoc. The
heredoc is quoted now, so the backslash was pure noise reaching the
agent — including inside the commit message it is instructed to use.

Golden-file changes, enumerated:
  - **Title:**       \\\$HOME -> \$HOME
  - **Description:** \\\${VAR} -> \${VAR}
  - criteria line:   Check \\\${HOME} -> Check \${HOME}
  - commit message:  feat: [US-042] - ... \\\$HOME -> \$HOME
  - requirement body: & and \\\$VAR -> & and \$VAR

lib/sanitize.sh is unchanged: its backtick neutralization is
load-bearing for the injection assertion and it has other callers."
```

Update the enumeration to match the actual diff from Step 2.

---

### Task 29: Extract the verification phase into `lib/verification.sh`

**Files:**
- Create: `lib/verification.sh`
- Modify: `lib/run.sh:1067-1157` (Phase 3 block)
- Modify: `tests/simple-test.sh`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: `RUN_SUMMARY_*` globals from the implementation loop.
- Produces, for Task 30:
  - `verify_collect <prd_file> <max_retries>` — sets `VERIFY_STORIES_TOTAL`, `VERIFY_STORIES_COMPLETED`, `VERIFY_STORIES_FAILED`, `VERIFY_STORIES_REMAINING` (always an integer), `VERIFY_PRD_PRESENT` (`0|1`).
  - `verify_run_tests <agent_dir>` — returns `0` pass, `1` fail, `2` not configured. Writes `$agent_dir/verification.test.log`.
  - `verify_write_summary <agent_dir> <req_id> <max_iterations> <mode>` — `mode` is `full` or `merge`. Writes via temp-file + `mv`.

**Context, three traps the signatures must respect:**
1. `max_iterations` is a `run_pipeline` **local** (`lib/run.sh:888`) interpolated into the summary at `:1136`. It is neither a `VERIFY_*` nor a `RUN_SUMMARY_*`, so it must be an explicit parameter — omit it and `cmd_verify` emits `"max": ` and malformed JSON, which `lib/pr-create.sh:147` silently swallows into `"?"`.
2. Bash functions return one integer, so multi-value returns are named globals. State that openly rather than hiding it behind a signature.
3. `merge` mode exists because a standalone `verify` has no implementation loop: `RUN_SUMMARY_*` are all zero, and a fresh write would zero `iterations`, `tests` and `commits` — the evidence trail `lib/pr-create.sh:138-148` renders into the PR table.

- [ ] **Step 1: Write the characterization assertion first**

```bash
# Test: verification-summary.json is unchanged by the extraction
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/vx"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  s="$PH_ROOT/.reqdrive/runs/req-01/verification-summary.json"
  jq -e '.version == "0.3.0"' "$s" > /dev/null
  jq -e '.stories | has("total") and has("completed") and has("failed") and has("remaining")' "$s" > /dev/null
  jq -e '.iterations | has("run") and has("max")' "$s" > /dev/null
  jq -e '.iterations.max != null' "$s" > /dev/null
  jq -e 'has("prd_present")' "$s" > /dev/null
  jq -e '.tests | has("passed") and has("failed") and has("skipped")' "$s" > /dev/null
  jq -e '.commits | has("verified") and has("missing")' "$s" > /dev/null
)
test_result "verification: summary keeps its full shape" $?
```

Run it now — it must PASS against the pre-extraction code. That is what makes it a characterization test.

- [ ] **Step 2: Create the module**

Create `lib/verification.sh` with the three functions, moving the logic from `lib/run.sh:1076-1149` verbatim except that locals become the documented `VERIFY_*` globals and `max_iterations` becomes a parameter. `verify_write_summary` writes to `"$summary.tmp"` then `mv`s it into place. In `merge` mode it reads the existing file first and preserves `iterations`, `tests` and `commits`, exiting 3 if the file does not exist.

Start the file with `set -e` per the library convention, and source it from `lib/run.sh` next to the existing `lib/pr-create.sh` source.

- [ ] **Step 3: Replace the Phase 3 block in `run_pipeline`**

```bash
  source "$REQDRIVE_ROOT/lib/verification.sh"

  verify_collect "$prd_file" "${REQDRIVE_MAX_STORY_RETRIES:-3}"
  stories_total=$VERIFY_STORIES_TOTAL
  stories_completed=$VERIFY_STORIES_COMPLETED
  stories_failed=$VERIFY_STORIES_FAILED
  final_remaining=$VERIFY_STORIES_REMAINING
  prd_present=$VERIFY_PRD_PRESENT

  RUN_SUMMARY_STORIES_TOTAL=$stories_total
  RUN_SUMMARY_STORIES_COMPLETED=$stories_completed
  RUN_SUMMARY_STORIES_FAILED=$stories_failed

  verify_run_tests "$agent_dir"
  case $? in
    0) verification_passed=true ;;
    1) verification_passed=false ;;
    2) verification_passed=null ;;
  esac
  RUN_SUMMARY_VERIFICATION_PASSED=$verification_passed

  verify_write_summary "$agent_dir" "$req_id" "$max_iterations" full
```

- [ ] **Step 4: Run the characterization assertion**

Run: `bash tests/simple-test.sh 2>&1 | grep 'verification: summary keeps'`

Expected: `PASS` — unchanged from Step 1.

- [ ] **Step 5: Confirm the draft gate still works**

Run: `bash tests/simple-test.sh 2>&1 | grep 'draft gate:'`

Expected: all four PASS. The gate now reads `VERIFY_STORIES_REMAINING` and `VERIFY_PRD_PRESENT` through the local aliases assigned in Step 3.

- [ ] **Step 6: Re-lock and commit**

```bash
bash -n lib/verification.sh lib/run.sh
shellcheck lib/verification.sh lib/run.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add lib/verification.sh lib/run.sh tests/simple-test.sh tests/oracle.lock.json
git commit -m "refactor: extract the verification phase into lib/verification.sh

Named verification.sh, not verify.sh, to stay distinct from the
archived archive/v1-complex/lib/verify.sh.

max_iterations is an explicit parameter because it is a run_pipeline
local interpolated into the summary — without it a standalone caller
emits 'max: ' and malformed JSON that pr-create silently degrades to
'?'. verify_run_tests returns a tri-state because the draft gate must
distinguish 'not configured' from 'failed'."
```

---

### Task 30: Add `reqdrive verify <REQ-ID>`

**Files:**
- Modify: `bin/reqdrive` (new `cmd_verify`, dispatch label, option parsing), `lib/errors.sh`, `README.md`
- Modify: `tests/simple-test.sh`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: `verify_collect`, `verify_run_tests`, `verify_write_summary` from Task 29.
- Produces: `reqdrive verify <REQ-ID> [--ref <branch>]`.

**Context:** This task adds **both** new exit codes — `EXIT_VERIFICATION_FAILED=9` and `EXIT_CONCURRENT_RUN=10`. The two exit-code assertions were renamed in Task 5 precisely so they stay truthful here; their bodies enumerate 0-8 and remain correct as a subset check. The doc-coverage rules from Tasks 20 and 22 will redden until `verify` and `--ref` are documented — that is the gate working, not a malfunction.

- [ ] **Step 1: Write the failing assertions**

```bash
echo ""
echo "--- Verify Command ---"

# Test: verify re-runs verification and preserves the evidence trail
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-merge"
  jq '.testCommand = "true"' "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: testCommand"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  s="$PH_ROOT/.reqdrive/runs/req-01/verification-summary.json"
  before_iters=$(jq '.iterations.run' "$s")
  before_commits=$(jq '.commits.verified' "$s")
  (cd "$PH_ROOT" && PATH="$PH_BIN:$PATH" "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-01) 
  [ "$(jq '.iterations.run' "$s")" = "$before_iters" ]
  [ "$(jq '.commits.verified' "$s")" = "$before_commits" ]
)
test_result "verify: merge mode preserves the evidence trail" $?

# Test: verify exits 9 when the test command fails
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-fail"
  jq '.testCommand = "true"' "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: testCommand"
  ph_fake_claude full
  ph_fake_gh
  ph_run REQ-01 > /dev/null
  jq '.testCommand = "false"' "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  rc=0
  (cd "$PH_ROOT" && PATH="$PH_BIN:$PATH" "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-01) || rc=$?
  [ "$rc" -eq 9 ]
)
test_result "verify: exits 9 when verification fails" $?

# Test: verify exits 3 for an unknown REQ-ID
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-unknown"
  rc=0
  out=$(cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-99 2>&1) || rc=$?
  [ "$rc" -eq 3 ]
  echo "$out" | grep -qi "req-99"
)
test_result "verify: exits 3 for an unknown REQ-ID" $?

# Test: verify refuses while the run's PID is alive
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/v-live"
  run_dir="$PH_ROOT/.reqdrive/runs/req-01"
  mkdir -p "$run_dir"
  echo '{"version":"0.3.0"}' > "$run_dir/verification-summary.json"
  cat > "$run_dir/run.json" <<EOF
{"version":"0.3.0","req_id":"REQ-01","status":"running","pid":$$,"iteration":1}
EOF
  rc=0
  (cd "$PH_ROOT" && "$REQDRIVE_ROOT/bin/reqdrive" verify REQ-01 >/dev/null 2>&1) || rc=$?
  [ "$rc" -eq 10 ]
)
test_result "verify: exits 10 while the run PID is alive" $?

# Test: new exit codes exist with messages
(
  set -e
  source "$REQDRIVE_ROOT/lib/errors.sh"
  [ "$EXIT_VERIFICATION_FAILED" -eq 9 ]
  [ "$EXIT_CONCURRENT_RUN" -eq 10 ]
  [ -n "$(get_exit_message 9)" ] && [ "$(get_exit_message 9)" != "Unknown error" ]
  [ -n "$(get_exit_message 10)" ] && [ "$(get_exit_message 10)" != "Unknown error" ]
)
test_result "errors: verification and concurrency codes are defined" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'verify:|errors: verification'`

Expected: all five FAIL.

- [ ] **Step 3: Add the exit codes**

In `lib/errors.sh`:

```bash
export EXIT_VERIFICATION_FAILED=9
export EXIT_CONCURRENT_RUN=10
```

and add to `EXIT_MESSAGES`:

```bash
EXIT_MESSAGES[9]="Verification failed"
EXIT_MESSAGES[10]="Another reqdrive run is active"
```

- [ ] **Step 4: Implement `cmd_verify`**

In `bin/reqdrive`, add `cmd_verify` and a `verify)` dispatch label. The function must:

1. Resolve the run directory from the REQ-ID slug; exit `EXIT_CONFIG_ERROR` naming the path if it or `verification-summary.json` is absent.
2. Read `run.json`'s `pid`; if `kill -0 "$pid" 2>/dev/null` succeeds, exit `EXIT_CONCURRENT_RUN`.
3. Compare the current branch against `checkpoint.json`'s `branch`; if they differ and no `--ref <branch>` was given, exit `EXIT_GIT_ERROR` (4) explaining the mismatch. With `--ref`, check out that ref first.
4. Source `lib/verification.sh`, call `verify_collect`, `verify_run_tests`, then `verify_write_summary "$agent_dir" "$req_id" "$max_iterations" merge` — reading `max_iterations` from the existing summary's `.iterations.max`.
5. Exit `0` when `verify_run_tests` returned 0, `EXIT_VERIFICATION_FAILED` when it returned 1, and `0` with the "not configured" message when it returned 2.

Parse `--ref` in `cmd_verify`'s own option loop, matching the style of the existing `cmd_run` loop.

- [ ] **Step 5: Run to verify green**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'verify:|errors: verification|docs:'`

Expected: the five verify assertions PASS, and **`docs: every CLI command...` and `docs: every CLI flag...` now FAIL** — the coverage gates firing on the new surface exactly as designed.

- [ ] **Step 6: Document the command and flag**

Add to `README.md`'s Commands table:

```markdown
| `reqdrive verify <REQ-ID>` | Re-run verification for an existing run and update its `verification-summary.json` in place. Exits 0 on pass, 9 on failure, 3 if the run or its summary is missing, 4 on branch mismatch, 10 while the run is still active. |
```

and to the Run Options table:

```markdown
| `--ref <branch>` | `reqdrive verify` only. Verify against `<branch>` instead of refusing when the checkout does not match the run's recorded branch. Without it, verifying after the branch was merged and deleted would record an unrelated tree's result as that run's evidence. |
```

- [ ] **Step 7: Run everything green**

Run: `bash tests/simple-test.sh 2>&1 | tail -4`

Expected: all green, 0 failed.

- [ ] **Step 8: Re-lock and commit**

```bash
bash -n bin/reqdrive lib/errors.sh
shellcheck bin/reqdrive lib/errors.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add bin/reqdrive lib/errors.sh README.md tests/simple-test.sh tests/oracle.lock.json
git commit -m "feat: add reqdrive verify <REQ-ID>

Merge mode, so re-verifying preserves iterations/tests/commits — the
evidence trail pr-create renders into the PR table. Refuses when the
checkout does not match the run's branch unless --ref is given, and
while the run's PID is still alive.

Adds EXIT_VERIFICATION_FAILED=9 and EXIT_CONCURRENT_RUN=10. The two
exit-code assertions were renamed in P0 for exactly this moment; their
bodies enumerate 0-8 and stay correct as a subset check.

The doc-coverage gates reddened on both the new command and the new
flag until README documented them, which is the gate working."
```

---

**P6 exit gate.**

```bash
bash tests/simple-test.sh                          # all green
bash tests/oracle-gate.sh                          # OK
bash tests/gate-selftest.sh                        # 5 passed
bats tests/unit tests/e2e                          # all pass
bats --formatter tap tests/e2e | grep -c '# skip'  # 0
```

---

# Phase P7 — Policy cluster

The last three Tier 2 items: a `policy` object in `reqdrive.json`, risk tiers by path, and the scope check. Shipped **warn-only by default** with `"scopeCheck": "block"` available — this resolves the contradiction between the roadmap ("promote to hard gate") and the architectural principle ("warn before enforce, don't make things strict without data"). The knob puts the hard gate one config edit away, and warn-mode data is what would justify flipping the default later.

---

### Task 31: Align validation exit codes

**Files:**
- Modify: `lib/validate.sh:16,70`, `bin/reqdrive` (`cmd_validate`)
- Modify: `tests/simple-test.sh`, `tests/FINDINGS.md`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: `EXIT_CONFIG_ERROR` from `lib/errors.sh`.
- Produces: `reqdrive validate` exiting 3 on any validation failure. Task 32 relies on this for the malformed-`policy` case.

**Context:** `lib/validate.sh:16` and `:70` are bare `exit 1`, and nothing in the file references `EXIT_CONFIG_ERROR`. Task 32 would otherwise make `policy` the only config field whose malformation exits 3 while every other field exits 1. The existing assertion at `tests/simple-test.sh:346-356` checks only `-ne 0`, so it stays green either way — that weakness is finding **F5** in the register, and this task closes it.

- [ ] **Step 1: Write the failing assertion**

```bash
# Test: validate exits with EXIT_CONFIG_ERROR on a malformed config
(
  set -e
  cd "$TEST_TEMP"
  mkdir -p vex && cd vex
  echo 'not json at all' > reqdrive.json
  rc=0
  "$REQDRIVE_ROOT/bin/reqdrive" validate > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 3 ]
)
test_result "validate: exits 3 (EXIT_CONFIG_ERROR) on malformed config" $?

# Test: validate exits 3 on a type violation
(
  set -e
  cd "$TEST_TEMP"
  mkdir -p vex2 && cd vex2
  echo '{"maxIterations":"ten"}' > reqdrive.json
  rc=0
  "$REQDRIVE_ROOT/bin/reqdrive" validate > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 3 ]
)
test_result "validate: exits 3 on a config type violation" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep 'validate: exits 3'`

Expected: both FAIL — the current code exits 1.

- [ ] **Step 3: Replace the bare exits**

In `lib/validate.sh`, source `lib/errors.sh` if it is not already sourced, then change both `exit 1` occurrences (lines 16 and 70) to:

```bash
  exit "$EXIT_CONFIG_ERROR"
```

In `bin/reqdrive`'s `cmd_validate`, change its bare `exit 1` to `exit "$EXIT_CONFIG_ERROR"` as well.

- [ ] **Step 4: Run to verify green**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'validate:|^FAIL'`

Expected: both new assertions PASS, and the pre-existing validation assertions still PASS.

- [ ] **Step 5: Close finding F5**

In `tests/FINDINGS.md`, move F5 from the Open table to the Closed table with a note naming this task and the two new assertions that pin the code.

- [ ] **Step 6: Re-lock and commit**

```bash
bash -n lib/validate.sh bin/reqdrive
shellcheck lib/validate.sh bin/reqdrive
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add lib/validate.sh bin/reqdrive tests/simple-test.sh tests/FINDINGS.md tests/oracle.lock.json
git commit -m "fix: validate exits EXIT_CONFIG_ERROR rather than a bare 1

The existing assertion checked only -ne 0, so the code was never
pinned (finding F5). Aligning it now keeps the policy object from
becoming the only field whose malformation exits 3."
```

---

### Task 32: Add the `policy` config object

**Files:**
- Modify: `lib/schema.sh` (validation), `lib/config.sh` (loading), `README.md`
- Modify: `tests/simple-test.sh`, `tests/oracle.lock.json`
- Modify: `templates/reqdrive.json.example`

**Interfaces:**
- Consumes: `EXIT_CONFIG_ERROR` alignment from Task 31.
- Produces: `REQDRIVE_POLICY_SCOPE_CHECK` (`warn`|`block`) and `REQDRIVE_POLICY_JSON` (the raw `policy` object, or `{}`), both exported by `reqdrive_load_config`. Tasks 33 and 34 consume them.

**Context:** Policy lives as a key inside `reqdrive.json` rather than a separate `.reqdrive/policy.json` — one file, one loader, one schema validator, one `validate` path. **`reqdrive_load_config` is deliberately not changed to schema-validate**: wiring `validate_config_schema` into config load would newly reject configs that work today and put `US-CFG-04`/`US-CFG-05` and every minimal fixture at risk. That stays a recorded deferral.

- [ ] **Step 1: Write the failing assertions**

```bash
echo ""
echo "--- Policy Config ---"

# Test: a well-formed policy object validates
(
  set -e
  cd "$TEST_TEMP" && mkdir -p pol-ok && cd pol-ok
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","policy":{"riskTiers":{"high":["src/auth"],"low":["docs"]},"scopeCheck":"warn"}}
EOF
  "$REQDRIVE_ROOT/bin/reqdrive" validate > /dev/null 2>&1
)
test_result "policy: a well-formed policy object validates" $?

# Test: an invalid scopeCheck value is rejected
(
  set -e
  cd "$TEST_TEMP" && mkdir -p pol-bad && cd pol-bad
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","policy":{"scopeCheck":"maybe"}}
EOF
  rc=0
  out=$("$REQDRIVE_ROOT/bin/reqdrive" validate 2>&1) || rc=$?
  [ "$rc" -eq 3 ]
  echo "$out" | grep -q "scopeCheck"
)
test_result "policy: rejects an invalid scopeCheck value" $?

# Test: riskTiers must map tier names to arrays
(
  set -e
  cd "$TEST_TEMP" && mkdir -p pol-tiers && cd pol-tiers
  cat > reqdrive.json <<'EOF'
{"version":"0.3.0","policy":{"riskTiers":{"high":"src/auth"}}}
EOF
  rc=0
  out=$("$REQDRIVE_ROOT/bin/reqdrive" validate 2>&1) || rc=$?
  [ "$rc" -eq 3 ]
  echo "$out" | grep -q "riskTiers"
)
test_result "policy: rejects a non-array risk tier" $?

# Test: scopeCheck defaults to warn when policy is absent
(
  set -e
  cd "$TEST_TEMP" && mkdir -p pol-default && cd pol-default
  echo '{"version":"0.3.0"}' > reqdrive.json
  source "$REQDRIVE_ROOT/lib/errors.sh"
  source "$REQDRIVE_ROOT/lib/schema.sh"
  source "$REQDRIVE_ROOT/lib/config.sh"
  reqdrive_load_config
  [ "$REQDRIVE_POLICY_SCOPE_CHECK" = "warn" ]
  [ "$REQDRIVE_POLICY_JSON" = "{}" ]
)
test_result "policy: scopeCheck defaults to warn when absent" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep 'policy:'`

Expected: all four FAIL.

- [ ] **Step 3: Extend `validate_config_schema`**

In `lib/schema.sh`, inside `validate_config_schema`, after the existing field checks:

```bash
  # policy (optional object)
  if jq -e 'has("policy")' "$config_file" > /dev/null 2>&1; then
    if ! jq -e '.policy | type == "object"' "$config_file" > /dev/null 2>&1; then
      echo "[SCHEMA] policy must be an object" >&2
      errors=$((errors + 1))
    else
      if jq -e '.policy | has("scopeCheck")' "$config_file" > /dev/null 2>&1; then
        local sc
        sc=$(jq -r '.policy.scopeCheck' "$config_file")
        case "$sc" in
          warn|block) ;;
          *) echo "[SCHEMA] policy.scopeCheck must be \"warn\" or \"block\" (got \"$sc\")" >&2
             errors=$((errors + 1)) ;;
        esac
      fi
      if jq -e '.policy | has("riskTiers")' "$config_file" > /dev/null 2>&1; then
        if ! jq -e '.policy.riskTiers | type == "object"' "$config_file" > /dev/null 2>&1; then
          echo "[SCHEMA] policy.riskTiers must be an object" >&2
          errors=$((errors + 1))
        elif ! jq -e '[.policy.riskTiers[] | type == "array"] | all' "$config_file" > /dev/null 2>&1; then
          echo "[SCHEMA] policy.riskTiers values must be arrays of path prefixes" >&2
          errors=$((errors + 1))
        fi
      fi
    fi
  fi
```

Match the surrounding code's existing error-counting variable name if it differs from `errors`.

- [ ] **Step 4: Load the policy in `lib/config.sh`**

```bash
  REQDRIVE_POLICY_JSON=$(jq -c '.policy // {}' "$REQDRIVE_MANIFEST")
  REQDRIVE_POLICY_SCOPE_CHECK=$(jq -r '.policy.scopeCheck // "warn"' "$REQDRIVE_MANIFEST")
  export REQDRIVE_POLICY_JSON REQDRIVE_POLICY_SCOPE_CHECK
```

- [ ] **Step 5: Run to verify green, then watch the doc gate fire**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'policy:|docs: every config'`

Expected: the four policy assertions PASS and `docs: every config field is documented in README` FAILs on `policy` — the coverage gate from Task 21 doing its job.

- [ ] **Step 6: Document `policy` and update the example config**

Add to `README.md`'s configuration table:

```markdown
| `policy` | `{}` | object | Evidence policy. `policy.riskTiers` maps tier names (`high`, `medium`, `low`) to arrays of path prefixes; `policy.scopeCheck` is `"warn"` (default) or `"block"`. See [Risk tiers and scope checking](#risk-tiers-and-scope-checking). |
```

Add a README section explaining prefix-directory matching (Task 33 defines the exact semantics — write it after that task if you prefer, but the field must be named here for the gate to pass). Add the same block to `templates/reqdrive.json.example`, commented as optional.

- [ ] **Step 7: Re-lock and commit**

```bash
bash -n lib/schema.sh lib/config.sh
shellcheck lib/schema.sh lib/config.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add lib/schema.sh lib/config.sh README.md templates/reqdrive.json.example \
        tests/simple-test.sh tests/oracle.lock.json
git commit -m "feat: add the policy config object with schema validation

Lives inside reqdrive.json rather than a separate policy.json — one
file, one loader, one validator, one validate path.

reqdrive_load_config still does not schema-validate: wiring
validate_config_schema into config load would newly reject configs
that work today and put US-CFG-04/05 and every minimal fixture at
risk. That stays deferred."
```

---

### Task 33: Implement the risk-tier path matcher

**Files:**
- Create: `lib/policy.sh`
- Modify: `tests/simple-test.sh`, `tests/oracle.lock.json`
- Modify: `.github/workflows/ci.yml` is not needed — `lib/*.sh` is already globbed by lint and syntax-check.

**Interfaces:**
- Consumes: `REQDRIVE_POLICY_JSON` from Task 32.
- Produces:
  - `policy_tier_for_path <path>` — prints `high`, `medium`, `low`, or `none`. Highest tier wins when a path matches more than one.
  - `policy_classify_paths <path>...` — prints `TIER<TAB>PATH` per input.

**Context — why not `**`:** in `[[ ]]` pattern matching, `globstar` does not apply. Measured: `[[ src/api/a/b.ts == src/api/** ]]` matches **and** `[[ src/api/a/b.ts == src/api/* ]]` matches — `**` and `*` are indistinguishable there, and both cross `/`. Worse, `[[ src/auth == src/auth/** ]]` does **not** match the directory itself. So a config written as `"high": ["src/auth/**"]` would silently fail to cover `src/auth`. Patterns are therefore **bare prefixes** with explicit semantics: a path matches a pattern when `path == pattern` **or** `path` begins with `pattern/`. That also means `src/auth.sh` must **not** match `src/auth`, which is the sibling-prefix trap.

- [ ] **Step 1: Write the failing assertions**

```bash
echo ""
echo "--- Policy Matcher ---"

(
  set -e
  export REQDRIVE_POLICY_JSON='{"riskTiers":{"high":["src/auth"],"medium":["src/api"],"low":["docs"]}}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  [ "$(policy_tier_for_path 'src/auth/login.ts')" = "high" ]      # nested descendant
  [ "$(policy_tier_for_path 'src/auth')" = "high" ]                # the tier directory itself
  [ "$(policy_tier_for_path 'src/api/v1/users.ts')" = "medium" ]
  [ "$(policy_tier_for_path 'docs/README.md')" = "low" ]
  [ "$(policy_tier_for_path 'src/util/math.ts')" = "none" ]        # no match
)
test_result "policy: matcher classifies paths by tier" $?

(
  set -e
  export REQDRIVE_POLICY_JSON='{"riskTiers":{"high":["src/auth"]}}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  # A sibling that merely shares the prefix must NOT match.
  [ "$(policy_tier_for_path 'src/auth.sh')" = "none" ]
  [ "$(policy_tier_for_path 'src/authorization/x.ts')" = "none" ]
)
test_result "policy: a prefix-sharing sibling does not match" $?

(
  set -e
  # src/auth/keys is in both high and low; highest must win.
  export REQDRIVE_POLICY_JSON='{"riskTiers":{"high":["src/auth"],"low":["src/auth/keys"]}}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  [ "$(policy_tier_for_path 'src/auth/keys/rsa.pem')" = "high" ]
)
test_result "policy: highest tier wins when a path matches two" $?

(
  set -e
  export REQDRIVE_POLICY_JSON='{}'
  source "$REQDRIVE_ROOT/lib/policy.sh"
  [ "$(policy_tier_for_path 'src/auth/login.ts')" = "none" ]
)
test_result "policy: no riskTiers means every path is untiered" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep 'policy: matcher\|policy: a prefix\|policy: highest\|policy: no riskTiers'`

Expected: all four FAIL — `lib/policy.sh` does not exist.

- [ ] **Step 3: Write the matcher**

Create `lib/policy.sh`:

```bash
#!/usr/bin/env bash
# Risk-tier path classification.
#
# Patterns are bare path prefixes, not globs. A path matches a pattern when
# it equals the pattern or begins with "<pattern>/". Globs are deliberately
# not used: inside [[ ]] bash does not honour globstar, so ** and * are
# indistinguishable and both cross "/", while "src/auth/**" fails to match
# "src/auth" itself. Prefix semantics are what a reader expects and what the
# tests can pin.
set -e

# policy_tier_for_path <path> -> high | medium | low | none
policy_tier_for_path() {
  local path="$1"
  local policy="${REQDRIVE_POLICY_JSON:-{\}}"
  local tier pattern

  # Highest tier wins, so probe in descending order of risk.
  for tier in high medium low; do
    while IFS= read -r pattern; do
      [ -n "$pattern" ] || continue
      if [ "$path" = "$pattern" ] || [ "${path#"$pattern"/}" != "$path" ]; then
        printf '%s\n' "$tier"
        return 0
      fi
    done < <(printf '%s' "$policy" | jq -r --arg t "$tier" '.riskTiers[$t][]? // empty' 2>/dev/null)
  done

  printf 'none\n'
}

# policy_classify_paths <path>... -> "TIER<TAB>PATH" per line
policy_classify_paths() {
  local p
  for p in "$@"; do
    printf '%s\t%s\n' "$(policy_tier_for_path "$p")" "$p"
  done
}
```

`${path#"$pattern"/}` strips the prefix plus a separator; if the result differs from the input, the prefix matched at a directory boundary — which is exactly why `src/auth.sh` does not match `src/auth`.

- [ ] **Step 4: Run to verify green**

Run: `bash tests/simple-test.sh 2>&1 | grep 'policy:'`

Expected: all eight policy assertions PASS.

- [ ] **Step 5: Re-lock and commit**

```bash
bash -n lib/policy.sh && shellcheck lib/policy.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add lib/policy.sh tests/simple-test.sh tests/oracle.lock.json
git commit -m "feat: add risk-tier path matching with prefix semantics

Not globs: inside [[ ]] bash ignores globstar, so ** and * are
indistinguishable and both cross '/', while 'src/auth/**' does not
match 'src/auth' itself. Bare prefixes with an explicit boundary
check mean src/auth.sh does not match src/auth — the trap a glob
would have hidden."
```

---

### Task 34: Wire the scope check into the pipeline

**Files:**
- Modify: `lib/run.sh` (implementation loop), `lib/pr-create.sh` (PR body)
- Modify: `tests/simple-test.sh`, `README.md`, `tests/oracle.lock.json`

**Interfaces:**
- Consumes: `policy_classify_paths` from Task 33, `REQDRIVE_POLICY_SCOPE_CHECK` from Task 32.
- Produces: `policy_scope_check <agent_dir> <iteration> <tests_passed>` in `lib/policy.sh`, returning 0 to continue or 1 to abort.

**Context:** The violation condition is **a high-risk path touched in an iteration whose `testCommand` run did not pass**. Under `warn` the finding is logged, recorded in the checkpoint, and rendered into the PR body; the exit code is unchanged. Under `block` the iteration aborts with `EXIT_PREFLIGHT_FAILED` (8) — it is a policy pre-condition, so it reuses the existing code rather than inventing one.

- [ ] **Step 1: Write the failing assertions**

```bash
echo ""
echo "--- Scope Check ---"

# Test: warn mode records a finding and does not abort
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/sc-warn"
  jq '.policy = {"riskTiers":{"high":["MARKER.txt"]},"scopeCheck":"warn"}' \
    "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: policy"
  ph_fake_claude full
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "0" ]
  grep -qi "high-risk" "$PH_ROOT/run.log"
)
test_result "scope: warn mode logs a finding and continues" $?

# Test: block mode aborts with EXIT_PREFLIGHT_FAILED
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/sc-block"
  jq '.policy = {"riskTiers":{"high":["MARKER.txt"]},"scopeCheck":"block"}' \
    "$PH_ROOT/reqdrive.json" > "$PH_ROOT/r.t" && mv "$PH_ROOT/r.t" "$PH_ROOT/reqdrive.json"
  git -C "$PH_ROOT" add -A && git -C "$PH_ROOT" commit -q -m "chore: policy"
  ph_fake_claude full
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "8" ]
)
test_result "scope: block mode aborts with EXIT_PREFLIGHT_FAILED" $?

# Test: no policy means no scope finding at all
(
  set -e
  source "$REQDRIVE_ROOT/tests/lib/pipeline-harness.sh"
  ph_setup "$TEST_TEMP/sc-none"
  ph_fake_claude full
  ph_fake_gh
  rc=$(ph_run REQ-01)
  [ "$rc" = "0" ]
  ! grep -qi "high-risk" "$PH_ROOT/run.log"
)
test_result "scope: absent policy produces no findings" $?
```

- [ ] **Step 2: Run to observe the red**

Run: `bash tests/simple-test.sh 2>&1 | grep 'scope:'`

Expected: the warn and block assertions FAIL; the absent-policy assertion PASSES already (nothing emits "high-risk" yet), which is the control proving the feature is genuinely off by default.

- [ ] **Step 3: Add the scope check to `lib/policy.sh`**

```bash
# policy_scope_check <agent_dir> <iteration> <tests_passed:0|1>
# Returns 0 to continue, 1 when block mode must abort.
policy_scope_check() {
  local agent_dir="$1" iteration="$2" tests_passed="$3"
  local mode="${REQDRIVE_POLICY_SCOPE_CHECK:-warn}"
  local findings_file="$agent_dir/scope-findings.txt"

  local changed
  changed=$(git diff --name-only HEAD~1 HEAD 2>/dev/null || echo "")
  [ -n "$changed" ] || return 0

  local violations=""
  while IFS=$'\t' read -r tier path; do
    [ "$tier" = "high" ] || continue
    [ "$tests_passed" = "1" ] && continue
    violations="$violations $path"
  done < <(policy_classify_paths $changed)

  [ -n "$violations" ] || return 0

  echo "iteration $iteration: high-risk paths changed without a passing test run:$violations" \
    >> "$findings_file"

  if [ "$mode" = "block" ]; then
    echo "[ERROR] Scope check: high-risk paths changed without a passing test run:$violations" >&2
    return 1
  fi
  echo "[WARN]  Scope check: high-risk paths changed without a passing test run:$violations" >&2
  return 0
}
```

- [ ] **Step 4: Call it from the implementation loop**

In `lib/run.sh`, immediately after the commit-verification block (around `lib/run.sh:1030-1038`), add:

```bash
    source "$REQDRIVE_ROOT/lib/policy.sh"
    local iter_tests_passed=0
    [ -n "${REQDRIVE_TEST_COMMAND:-}" ] && [ -f "$agent_dir/iteration-$i.test.log" ] \
      && grep -q . "$agent_dir/iteration-$i.test.log" && iter_tests_passed=1
    if ! policy_scope_check "$agent_dir" "$i" "$iter_tests_passed"; then
      write_run_status "$agent_dir" "failed" "$req_id" "$i" "$EXIT_PREFLIGHT_FAILED"
      run_completion_hook "$req_id" "failed" "" "$branch" "$EXIT_PREFLIGHT_FAILED"
      exit "$EXIT_PREFLIGHT_FAILED"
    fi
```

Set `iter_tests_passed=1` from the same signal the loop already computes for `RUN_SUMMARY_TESTS_PASSED` rather than re-deriving it from the log — replace the `grep` heuristic above with that variable if the loop exposes it directly.

- [ ] **Step 5: Render findings into the PR body**

In `lib/pr-create.sh`, if `$agent_dir/scope-findings.txt` exists and is non-empty, append a `### Scope findings` section listing each line. Warn-mode findings must be visible in the PR, matching the existing review phase's warn-only contract.

- [ ] **Step 6: Run to verify green**

Run: `bash tests/simple-test.sh 2>&1 | grep -E 'scope:|draft gate:|^FAIL'`

Expected: all three scope assertions PASS, all four draft-gate assertions still PASS, no `FAIL:` lines.

- [ ] **Step 7: Document the behavior**

Complete the "Risk tiers and scope checking" README section referenced in Task 32: prefix semantics, the two modes, the violation condition, and that `warn` is the default because the hard gate has no false-positive data behind it yet.

- [ ] **Step 8: Re-lock and commit**

```bash
bash -n lib/policy.sh lib/run.sh lib/pr-create.sh
shellcheck lib/policy.sh lib/run.sh lib/pr-create.sh
bash tests/oracle-gate.sh --accept && bash tests/oracle-gate.sh
git add lib/policy.sh lib/run.sh lib/pr-create.sh README.md tests/simple-test.sh tests/oracle.lock.json
git commit -m "feat: scope-check high-risk paths, warn by default

A high-risk path changed in an iteration whose tests did not pass is
a finding. warn logs it into the checkpoint and the PR body and
continues; block aborts with EXIT_PREFLIGHT_FAILED, reusing the
existing code because it is a policy pre-condition.

Ships warn-only: the roadmap asked for a hard gate, the architecture
principle says warn before enforce. The knob makes the gate one
config edit away, and warn-mode data is what would justify flipping
the default."
```

---

**P7 exit gate.**

```bash
bash tests/simple-test.sh                          # all green
bash tests/oracle-gate.sh                          # OK
bash tests/gate-selftest.sh                        # 5 passed
bats tests/unit tests/e2e                          # all pass, zero e2e skips
```

All Tier 2 items are now complete.

---

# Phase P8 — Close out

### Task 35: Reconcile the documentation and record what was deferred

**Files:**
- Modify: `ROADMAP.md`, `CLAUDE.md`, `tests/FINDINGS.md`
- Create: `docs/STATUS.md`
- Modify: `../../WORKFLOW.md` if it is reachable from this checkout; otherwise record the correction in `docs/STATUS.md` for manual application

**Interfaces:**
- Consumes: everything.
- Produces: documentation that matches the code.

- [ ] **Step 1: Mark `ROADMAP.md` superseded**

Insert at the top of `ROADMAP.md`, above the existing heading:

```markdown
> **Superseded — see the Roadmap section of [`CLAUDE.md`](./CLAUDE.md).**
>
> This is the v0.2.0 simplification plan. Its unchecked Phase 4 and Success
> Criteria boxes describe work that shipped; it is retained as history, not
> as a live plan.

```

Do not rewrite the body.

- [ ] **Step 2: Check off Tier 2 and record the Tier 3 deferrals**

In `CLAUDE.md`, mark every Tier 2 item complete with its implementing file, and add to the Decision Log:

```markdown
- **[2026-07-23] Tier 3 deferred, with reasons.**
  - *Vision-based QA agent* — needs Playwright and binary image data; a Node/Python
    subprocess, i.e. a separate product with its own ladder.
  - *Multi-requirement parallelism (`orchestrate`)* — needs worktree revival; reviving
    `archive/v1-complex/lib/worktree.sh` is its own design cycle.
  - *PR rejection feedback loop* — depends on review-comment parsing; no failure data
    yet to shape it.
  - *CI integration (`gh pr checks` polling)* — cheap in bash but adds a polling loop
    and a new failure mode; wants its own spec.
  - *Cost tracking / token budgets* — the `claude` CLI does not surface per-invocation
    token counts to the shell.
  - *Adaptive retry policies* — needs historical success-rate data that does not exist
    until the pipeline has run at scale.

- **[2026-07-23] Config-load-time schema validation deferred.**
  **Why:** wiring `validate_config_schema` into `reqdrive_load_config` would newly
  reject configs that load today, putting `US-CFG-04`/`US-CFG-05` and every minimal
  test fixture at risk. `reqdrive validate` remains the validation entry point.

- **[2026-07-23] The review agent is not a genuine writer≠grader.**
  **Why:** `run_review_phase` uses the same `$model` as the implementer, returns
  immediately when `reviewCommand` is empty (the default), and runs after `create_pr`,
  so its findings cannot influence the draft decision. Making it real needs a distinct
  `reviewModel` and a pre-PR position. Not claimed as L2 evidence until then.
```

Also update the Known Pitfalls section: the `testCommand` warn-only note and the "agent self-reporting is not authoritative" note both need revising — the draft gate is now fail-closed and no longer trusts `passes` alone.

- [ ] **Step 3: Triage the findings register**

In `tests/FINDINGS.md`, for every remaining Open finding either fix it (with a red-first test) or move it to a new **Accepted risk** table with a one-line reason and the count. F4's pure-negative count must carry the measured number from Task 9.

- [ ] **Step 4: Create `docs/STATUS.md`**

```markdown
# reqdrive — Status

## State summary

**Readiness:** L3 on the Readiness Ladder (target met). L4 is not targeted —
reqdrive is a harness, not a shipped product.

**What changed (2026-07-23):** the test harness could not report a failure, so
"157 passed, 0 failed" was guaranteed by construction and red-first TDD was
impossible. That is fixed and mutation-proven. The behavior spec now covers all
157 original assertions, the suite is frozen against tampering by whole-file
hash, the draft-PR gate is fail-closed, the public surface is documented under
three coverage gates, and every Tier 2 roadmap item is complete.

**Known gaps:**
- `launch` lifecycle coverage is Linux-CI-only; PID liveness and signal trapping
  are unreliable under MSYS2.
- The review agent is not a genuine writer≠grader (same model, off by default,
  post-PR). See the Decision Log.
- Config load does not schema-validate; `reqdrive validate` is the entry point.
- Accepted-risk assertions are listed in `tests/FINDINGS.md`.

**Next steps:** Tier 3, in the order recorded in the CLAUDE.md Decision Log.
The cheapest next item is CI integration; the highest-value is vision-based QA,
which is a separate product.

## Session log

### 2026-07-23 — Roadmap completion (P0-P8)
Design spec and implementation plan in `docs/superpowers/`. Nine phases from
harness repair through the policy cluster. Three adversarial critique rounds on
the spec produced 38 findings, including that the first proposed harness fix
would have made failures *silent* rather than fatal.
```

- [ ] **Step 5: Correct the WORKFLOW.md survey rows**

WORKFLOW.md §10 records reqdrive as **L2, gap docs-only**, and §9 repeats it. Both are wrong: L1's oracle could not report a failure and L2's draft gate fail-opened three ways, of which the survey found one. reqdrive's true starting rung was **L0**. Update the §10 row to show the corrected before/after and rewrite the §9 worked example. If `WORKFLOW.md` lives outside this repo, copy the corrected text into `docs/STATUS.md` under a "Corrections owed to WORKFLOW.md" heading so it is not lost.

- [ ] **Step 6: Final full verification**

```bash
bash tests/simple-test.sh
bash tests/spec-map.sh
bash tests/oracle-gate.sh
bash tests/gate-selftest.sh
bash tests/mutate.sh impl-prompt-return1
bash tests/mutate.sh impl-prompt-silent
bats tests/unit tests/e2e
bats --formatter tap tests/e2e | grep -c '# skip'
for f in bin/reqdrive lib/*.sh install.sh tests/*.sh; do bash -n "$f" && shellcheck "$f"; done
```

Expected: every command exits 0; skip count `0`; mutants still produce FAILs.

- [ ] **Step 7: Commit**

```bash
git add ROADMAP.md CLAUDE.md docs/STATUS.md tests/FINDINGS.md
git commit -m "docs: close out the roadmap and record what was deferred

Tier 2 complete. Tier 3 deferred with a reason per item. ROADMAP.md
marked superseded. STATUS.md created per the global convention.

Corrects the WORKFLOW.md survey: reqdrive was recorded as L2 with a
docs-only gap. Two rungs beneath were red — the suite could not
report a failure at all, and the draft gate fail-opened three ways.
True starting rung was L0."
```

---

## Verification summary

| Gate | Command | Expected |
|---|---|---|
| Suite | `bash tests/simple-test.sh` | all pass, 0 failed, exit 0 |
| Spec coverage | `bash tests/spec-map.sh` | every test name mapped, exit 0 |
| Freeze | `bash tests/oracle-gate.sh` | `OK`, exit 0 |
| Gate rules fire | `bash tests/gate-selftest.sh` | 5 passed, 0 failed |
| Harness detects defects | `bash tests/mutate.sh impl-prompt-return1` | `FAILS=3`, full result count |
| Harness detects silent defects | `bash tests/mutate.sh impl-prompt-silent` | `FAILS>=2` |
| E2E | `bats tests/unit tests/e2e` | all pass |
| E2E honesty | `bats --formatter tap tests/e2e \| grep -c '# skip'` | `0` |
| Lint | `shellcheck bin/reqdrive lib/*.sh install.sh tests/*.sh` | clean |
| Syntax | `bash -n` on every modified `.sh` | clean |
