# Story Harness in Rust Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `reqdrive story <work-order.json>`, a Rust coding harness an external orchestrator
drives: one story with fixed criteria in, a tests-first ref and a pushed attempt branch out, and
JSON-lines events on stdout.

**Architecture:** One cargo package, `crates/reqdrive`. It has a library half (pure modules plus
thin I/O modules), the `reqdrive` binary, and a test-only `fake-claude` binary.

- **The driver** (`story.rs`) runs the stages and owns every decision.
- **The agent** (`agent.rs`) only edits files.
- **Children** run under one supervisor (`proc.rs`) that enforces deadlines, interrupts and token
  limits.
- **One `Emitter`** owns stdout.

**Tech Stack:**
- Rust 1.93.1, edition 2021.
- Crates: `serde` 1, `serde_json` 1, `humantime` 2, `ctrlc` 3 with the `termination` feature, and
  `libc` 0.2 on Unix only. Dev-dependency: `tempfile` 3.
- Tools: the `git` CLI, and the `claude` CLI at run time.

**Spec:** `docs/superpowers/specs/2026-10-30-story-harness-mode-design.md`. Read §3 for behaviour
(the work order, stages, Red and the freeze, events, the §3.5.1 outcome table) and §10 for the Rust
mechanics. The owner rulings at the top of the spec override §2.1 and §3.7.1: v1 has no PR routes,
only a push.

## Global Constraints

**Repository and build:**
- The repository is **public**. Never name or describe any private project, client, employer or
  business plan, in code, comments, commits or PRs.
- Commit messages and PR bodies carry **no `Co-Authored-By` line and no "Generated with"
  footer**.
- Work only in the worktree and on the branch `feat/story-harness-rust` that your dispatch names.
  Never touch the repository's main checkout. Use the `CARGO_TARGET_DIR` the dispatch gives you,
  and do not run more than one cargo build at a time.
- Toolchain: `rust-toolchain.toml` pins `channel = "1.93.1"` with components `rustfmt` and
  `clippy`.
- Edition 2021. `#![deny(unsafe_code)]` in `lib.rs`. `proc.rs`'s Unix-only `kill` calls carry
  `#[allow(unsafe_code)]`. `forbid` cannot be overridden, so it would break the Linux build.
- **Tests that run a bin** (`fake-claude` or `reqdrive`) are integration tests under
  `crates/reqdrive/tests/`, using the public library API. `CARGO_BIN_EXE_*` is not set for unit
  tests inside `src/`.
- **Every `git diff … --name-only`** carries `--no-renames`, so a rename reports both its old and
  new path to the freeze and the denied-path checks.
- Every task ends green on `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings` and
  `cargo test`.

**The event and result format:**
- The work-order `schema` value is exactly `"story-work-order/0"`. The event envelope is
  `{"v":1,"attempt_id":…,"seq":n,"ts":"<RFC 3339, milliseconds, UTC>"}`, and it is applied after
  the body, so it overwrites any key a body sets.
- **Unknown is `null`, never 0.** Every count is an `Option<u64>`, serialized as `null` when
  `None`. `thinking` is always `null`.
- Outcomes are `pushed`, `no_change`, `failed` and `halted`. There is no `pr_open` in v1.

**Child processes:**
- No child ever inherits the harness's stdout. Every `Command` sets `stdin(Stdio::null())`, or a
  file for the agent's prompt, and sets an explicit `stdout`.
- `test_command` runs through `sh -c <cmd>` on Unix. On Windows it runs as
  `cmd` + `raw_arg("/S /C \"<cmd>\"")`. It always has the env `CI=true`.
- Git runs as `git -C <workspace> -c core.hooksPath=<state_dir>/no-hooks …`, where `no-hooks`
  is an empty directory the driver creates. That disables every repository hook. `--no-verify`
  alone leaves hooks such as `prepare-commit-msg`, `post-checkout` and `reference-transaction`
  running. Git also runs with env `GIT_TERMINAL_PROMPT=0`.
- Commits add `-c user.name=reqdrive -c user.email=reqdrive@localhost -c commit.gpgsign=false commit --no-verify`.
  Pushes use `push --no-verify <remote> <sha>:<ref>`, with no `-u`.
- **Process groups (Unix).** Every child is spawned with `CommandExt::process_group(0)`.
  Interrupt and kill go to the whole group (`kill(-pgid, …)`), so grandchildren such as npm under
  `sh -c` stop too.
- **Windows.** Only the direct child can be killed. `REQDRIVE_CLAUDE_BIN` must name a real
  `.exe`, because a `.cmd` shim would leave `node` holding the pipe. Job Objects are a roadmap
  item.
- **Spawn failures.** A spawn `io::Error` for the agent or the test command is `HarnessError`,
  with the error text in the detail.

**Defaults:**
- The denied paths are `.github`, `.husky`, `.claude`, `.mcp.json` and `.gitmodules`, plus the work
  order's `denied_paths`.
- The heartbeat interval is 30 000 ms, overridden by the env `REQDRIVE_HEARTBEAT_MS`.
- The interrupt grace is 30 000 ms, overridden by `REQDRIVE_GRACE_MS`.
- The agent binary is `claude`, overridden by `REQDRIVE_CLAUDE_BIN`.
- Green makes at most `green_max_calls` agent calls, default 5. Red gets two attempts.
- Failure evidence is capped at 8 192 bytes per entry, cut on a char boundary. A test-log tail is
  the last 2 048 bytes. A `log` event line is capped at 2 000 chars.

## Review Focus

1. **A workspace or state path containing a space** (common on Windows). It should work like any
   other path. Pinned in Task 10: the fixture's temp root contains a space.
2. **Non-JSON or partial lines in the agent's stdout**, such as warnings or a truncated last line.
   The parser should skip them and keep going. Pinned in Task 4.
3. **A test command that prints megabytes.** Output should go to a log file, and only a 2 KB tail
   should reach prompts and events. Pinned in Task 6.
4. **A target repository with a failing pre-commit hook.** The shell's commits should still
   succeed (`--no-verify`). Pinned in Task 7.
5. **CRLF in diff output on Windows** (`core.autocrlf`). The criterion check should still find ids
   at the end of a line. Pinned in Task 3.

---

## File map

| File | Responsibility | Task |
|---|---|---|
| `archive/bash-v0.3/**`, `archive/README.md` | The Bash tree, moved unchanged | 1 |
| `Cargo.toml`, `rust-toolchain.toml`, `.gitignore`, `.github/workflows/ci.yml` | Workspace, pin, CI | 1 |
| `crates/reqdrive/Cargo.toml`, `src/lib.rs`, `src/main.rs` | Package; module list; the CLI entry | 1, 11 |
| `src/workorder.rs` | Work-order types, parse, shape validation | 2 |
| `src/outcome.rs` | Outcome, Category, retryable, ResultEvent | 2 |
| `src/events.rs` | Event bodies, UsageRow, Emitter | 3 |
| `src/paths.rs` | Prefix rules | 3 |
| `src/criteria.rs` | Whole-word id check | 3 |
| `src/stream.rs` | stream-json parser, residue | 4 |
| `src/prompts.rs` | Templates, fencing, dangerous patterns, claims | 5 |
| `src/limits.rs`, `src/proc.rs` | Budgets; supervised children; signal flag | 6 |
| `src/bin/fake-claude.rs` | Test stand-in for `claude`; `check-tests` | 6 |
| `src/git.rs` | Git operations | 7 |
| `src/policy.rs`, `src/agent.rs` | Inference policy; the claude-code adapter | 8 |
| `src/story.rs` | The driver | 9, 10 |
| `tests/common/mod.rs`, `tests/story_*.rs` | Integration tests | 9–11 |
| `README.md`, `CLAUDE.md`, `docs/STATUS.md`, `ROADMAP.md` | Docs for the new state | 12 |

All `src/` paths are under `crates/reqdrive/`.

---

### Task 1: Archive the Bash tree and scaffold the workspace

**Files:**
- Move: everything tracked, except `LICENSE`, `.gitignore`, `.gitattributes` and `docs/superpowers/**`,
  to the same relative path under `archive/bash-v0.3/`
- Create: `archive/README.md`, `Cargo.toml`, `rust-toolchain.toml`,
  `crates/reqdrive/Cargo.toml`, `crates/reqdrive/src/lib.rs`, `crates/reqdrive/src/main.rs`,
  `.github/workflows/ci.yml`
- Modify: `.gitignore` (add `/target`), `.gitattributes` (keep the existing rule but re-point the
  path for `tests/oracle.lock.json` to `archive/bash-v0.3/tests/oracle.lock.json`)

**Interfaces:**
- Produces: the package `reqdrive` (lib + bin `reqdrive`), which every later task adds modules to.
  `lib.rs` starts as `#![forbid(unsafe_code)]` with no modules. `main.rs` prints the usage text and
  exits 2.

- [ ] **Step 1: Branch.** From the worktree, with the spec and this plan already committed on the
  parent branch, and `git status --short` empty:

```bash
git switch -c feat/story-harness-rust
```

- [ ] **Step 2: Move the tree** with `git mv`, mirroring factory M0 Task 1 Step 3
  (`docs/superpowers/plans/2026-10-04-factory-m0-foundations.md:298-317`). The differences:
  - `docs/superpowers/` stays at the root, all of it.
  - The old `archive/` folder goes to `archive/bash-v0.3/archive/`.
  - `.github/workflows/ci.yml` goes to `archive/bash-v0.3/.github/workflows/ci.yml`.

  Then verify:

```bash
git status --short | grep -v '^R ' || echo "renames only"
git ls-files | grep -v -e '^archive/bash-v0.3/' -e '^docs/superpowers/'
```

Expected: `renames only`; then exactly `.gitattributes`, `.gitignore`, `LICENSE`.

- [ ] **Step 3: Write `archive/README.md`.** Use the text of factory M0 Task 1 Step 5's
  `archive/README.md` (`…m0-foundations.md:334-352`), but drop the sentence about the Rust
  workspace's xtask.

- [ ] **Step 4: Scaffold.**
  - `Cargo.toml` is a workspace with `members = ["crates/reqdrive"]` and `resolver = "2"`.
  - `crates/reqdrive/Cargo.toml` declares the dependencies in the Tech Stack, `libc` under
    `[target.'cfg(unix)'.dependencies]`, and two bins: `reqdrive` (`src/main.rs`) and
    `fake-claude` (`src/bin/fake-claude.rs`, created in Task 6; until then omit this bin entry).
  - CI is one workflow, triggered on `pull_request` and on `push` to `main`. It runs a matrix over
    `ubuntu-latest` and `windows-latest`, with the steps `actions/checkout@v4`, then
    `cargo fmt --check`, then `cargo clippy --all-targets -- -D warnings`, then `cargo test`. The
    toolchain comes from `rust-toolchain.toml`.

- [ ] **Step 5: Verify and commit**

```bash
cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
git add -A && git commit -m "chore: archive the Bash tree; scaffold the Rust workspace"
```

Expected: all three pass (no tests yet).

### Task 2: The work order and the outcome types

**Files:** Create `src/workorder.rs`, `src/outcome.rs`; modify `src/lib.rs` (`pub mod workorder; pub mod outcome;`).

**Interfaces:**
- Produces (`workorder.rs`), all `#[derive(Debug, Clone, Deserialize)]`, with unknown fields
  ignored:
  - `WorkOrder { schema: String, attempt_id: String, story: Story, workspace: PathBuf, state_dir: PathBuf, repo: Repo, base_commit: String, attempt_branch: String, tests_ref: String, #[serde(default)] failure_evidence: Vec<FailureEvidence>, inference: Inference, limits: LimitsSpec, test_command: Option<String>, #[serde(default)] test_paths: Vec<String>, #[serde(default)] frozen_paths: Vec<String>, #[serde(default)] denied_paths: Vec<String>, #[serde(default)] isolation: Isolation, #[serde(default)] agent_allow: Vec<String>, green_max_calls: Option<u32> }`
  - `Story { id, title, description: String, acceptance_criteria: Vec<Criterion> }`;
    `Criterion { id: String, text: String }`
  - `Repo { remote: String }`
  - `FailureEvidence { attempt_id: String, summary: String, #[serde(default)] detail: String }`
  - `Inference { allow: Vec<AllowEntry> }`;
    `AllowEntry { provider: String, models: Vec<String>, base_url: Option<String> }`
  - `LimitsSpec { turns: u32, wall_clock_secs: u64, tokens: u64 }`
  - `enum Isolation { Container, None }`, snake_case, `Default = None`
  - `pub const SCHEMA: &str = "story-work-order/0";`
  - `pub fn parse(json: &str) -> Result<WorkOrder, String>`
  - `pub fn validate_shape(wo: &WorkOrder) -> Result<(), String>`. It is pure and checks:
    - `schema == SCHEMA`;
    - `attempt_id`, `story.id` and every criterion id are non-empty and match
      `[A-Za-z0-9._-]+`;
    - criteria are non-empty, with unique ids;
    - `base_commit` is 40 lowercase hex;
    - `workspace` and `state_dir` are absolute, and `state_dir` does not start with `workspace`;
    - every limit is > 0;
    - `attempt_branch`, `tests_ref` and `repo.remote` are non-empty, and `tests_ref` starts with
      `refs/`;
    - `green_max_calls`, if set, is 1..=20.
  - `pub fn cap_evidence(wo: &mut WorkOrder)` truncates each `summary` and `detail` to 8 192 bytes
    on a char boundary.
- Produces (`outcome.rs`):
  - `#[derive(Serialize, Debug, Clone, Copy, PartialEq, Eq)] #[serde(rename_all = "snake_case")] pub enum Outcome { Pushed, NoChange, Failed, Halted }`
  - `pub enum Category { WorkOrderInvalid, BaseMissing, PolicyUnsatisfiable, BranchConflict, BaseBroken, RedInvalid, RedNotFailing, HarnessError, ScopeViolation, PushFailed, TestsModified, TestsDefective, TestsFailed, AgentError, LimitReached, Interrupted, UsageIncomplete }`
    (same derives), with `pub fn retryable(self) -> bool`. It is false for `WorkOrderInvalid`,
    `PolicyUnsatisfiable`, `BranchConflict`, `BaseBroken`, `RedNotFailing`, `TestsDefective` and
    `LimitReached`, and true for every other category (spec §3.5.1).
  - `#[derive(Serialize, Debug, Clone, PartialEq)] pub struct Failure { pub category: Category, pub retryable: bool, pub detail: String }`
  - `pub struct Evidence { pub test_command: String, pub exit_code: Option<i32>, pub criteria_map: Option<String> }`
  - `pub struct ResultEvent { pub outcome: Outcome, pub head_sha: Option<String>, pub tests_ref_sha: Option<String>, pub red_observed: Option<bool>, pub tests_defective: bool, pub failure: Option<Failure>, pub evidence: Option<Evidence> }`
    (`Serialize`; `None` → `null`)
  - Constructors: `ResultEvent::end(outcome: Outcome, category: Category, detail: impl Into<String>) -> Self`
    fills `failure`, with `retryable` taken from the category. `ResultEvent::pushed(head_sha: String) -> Self`.

- [ ] **Step 1: Write the failing tests** (`#[cfg(test)]` in each file):
  - `parse_minimal_valid_order`: a JSON literal with every required field parses, and
    `isolation == Isolation::None` and `failure_evidence.is_empty()`.
  - `shape_rejects_*`, one test per rule above, each asserting `Err` whose message names the field.
  - `cap_evidence_cuts_on_char_boundary`: a `detail` of 9 000 copies of `"é"` becomes ≤ 8 192
    bytes and is still valid UTF-8.
  - `retryable_matches_spec_table`: all 17 categories asserted explicitly.
  - `result_serializes_unknowns_as_null`: `serde_json::to_value(ResultEvent::end(Outcome::Failed, Category::BaseBroken, "x"))`
    has `head_sha == null` and `failure.retryable == false`, and `outcome == "failed"`.
- [ ] **Step 2:** `cargo test` → the new tests FAIL (unresolved items).
- [ ] **Step 3:** Implement the items above.
- [ ] **Step 4:** `cargo test` → PASS; fmt and clippy clean.
- [ ] **Step 5:** `git commit -m "feat(story): work order and outcome types"`

### Task 3: Events and the Emitter; path rules; the criterion check

**Files:** Create `src/events.rs`, `src/paths.rs`, `src/criteria.rs`; modify `src/lib.rs`.

**Interfaces:**
- Produces (`events.rs`):
  - `#[serde(rename_all = "snake_case")] pub enum Stage { Validate, Provision, Red, RedPublished, Green, Check, Deliver, Done }`
  - `pub enum WaitingOn { Agent, Tests, Push }`
  - `pub enum LogStream { Agent, Test, System }`
  - `pub enum ArtifactKind { TestsRef, Branch, CriteriaMap, LogFile }`
  - `#[derive(Serialize, Debug, Clone, PartialEq)] pub struct UsageRow { pub call_seq: Option<u64>, pub model_id: Option<String>, pub provider: String, pub prompt: Option<u64>, pub cached_prompt: Option<u64>, pub cache_write: Option<u64>, pub output: Option<u64>, pub thinking: Option<u64>, pub attributed: bool }`
  - `#[derive(Serialize)] #[serde(tag = "type", rename_all = "snake_case")] pub enum Event { Progress { stage: Stage }, Heartbeat { waiting_on: WaitingOn }, Usage(UsageRow), Log { stream: LogStream, line: String }, Artifact { kind: ArtifactKind, #[serde(rename = "ref")] reference: String, sha: Option<String> }, Error { category: Category, retryable: bool, detail: String } }`
  - `#[derive(Clone)] pub struct Emitter(Arc<Mutex<Inner>>)` with:
    - `pub fn new(out: Box<dyn Write + Send>) -> Emitter`
    - `pub fn set_attempt_id(&self, id: &str)`. Until it is called, the envelope's `attempt_id`
      is `null`.
    - `pub fn attach_log(&self, path: &Path) -> io::Result<()>`. From then on every line is also
      appended to that file.
    - `pub fn emit(&self, ev: Event) -> io::Result<()>`. It does nothing after `finish`. A `Log`
      line is truncated to 2 000 chars before serialising.
    - `pub fn error(&self, category: Category, detail: impl Into<String>) -> io::Result<()>`, a
      helper that emits `Error` with `retryable` from the category.
    - `pub fn finish(&self, result: &ResultEvent) -> io::Result<()>`. It writes one line, the
      `ResultEvent` fields plus `"type":"result"` plus the envelope, and closes the emitter. A
      second call returns `Ok(())` and writes nothing. If a log is attached, it also writes the
      same JSON, pretty-printed, to `result.json` in that log's directory (spec §3.10).
  - Each line is serialized to a `serde_json::Value` object. The envelope keys `v`, `attempt_id`,
    `seq` (starting at 1, incremented under the lock) and `ts`
    (`humantime::format_rfc3339_millis(SystemTime::now())`) are inserted last, and the line is
    written with a single `write_all` of `line + "\n"`, then flushed.
- Produces (`paths.rs`):
  - `pub fn under(path: &str, prefix: &str) -> bool`: true if `path == prefix` or `path` starts
    with `prefix + "/"`. Trailing `/` on `prefix` is ignored, and `\` is normalized to `/` in both.
  - `pub const DEFAULT_DENIED: [&str; 5] = [".github", ".husky", ".claude", ".mcp.json", ".gitmodules"];`
  - `pub struct PathRules { pub denied: Vec<String>, pub frozen: Vec<String>, pub tests: Vec<String> }`
    with:
    - `PathRules::from_order(&WorkOrder)`
    - `denied_hits(&self, paths: &[String]) -> Vec<String>`
    - `red_violations(&self, paths: &[String]) -> Vec<String>`: paths under neither `tests` nor
      `frozen`. It returns an empty `Vec` when `tests` is empty, and the caller warns.
    - `green_violations(&self, paths: &[String], red_files: &[String]) -> Vec<String>`: paths in
      `red_files` or under `tests` or `frozen`.
- Produces (`criteria.rs`):
  - `pub fn added_lines(diff_u0: &str) -> String`: lines starting with `+` but not `+++`, with the
    `+` and any trailing `\r` stripped.
  - `pub fn missing_ids(added: &str, ids: &[String]) -> Vec<String>`. An id is present if it
    occurs with neither neighbour being an ASCII alphanumeric or `_`, the same rule as `grep -w`.

- [ ] **Step 1: Write the failing tests:**
  - `envelope_overrides_body`: emit a `Log`, then parse the captured line. `seq == 1`, `v == 1`,
    `attempt_id` equals the set id, and `ts` parses with `humantime::parse_rfc3339`.
  - `seq_is_total_across_threads`: 8 threads × 50 emits into one `Vec<u8>` writer → the lines'
    `seq` values are exactly 1..=400, and every line is valid JSON.
  - `usage_unknowns_serialize_as_null`: a `UsageRow` with all `None` → `"prompt":null`,
    `"thinking":null`.
  - `finish_writes_once_and_closes`: after `finish`, `emit` writes nothing and a second `finish`
    writes nothing. The last line has `"type":"result"`. With a log attached in a temp dir,
    `result.json` exists there.
  - `log_line_is_truncated`: a 5 000-char line → ≤ 2 000 chars.
  - `under_prefix_semantics`: `under("src/auth","src/auth")`, `under("src/auth/x","src/auth/")`,
    `!under("src/authz","src/auth")`, `under("a\\b","a")`.
  - `denied_defaults_hit_workflows`: `.github/workflows/ci.yml` and `.mcp.json` are hit, and
    `src/x.rs` is not.
  - `green_violations_cover_red_files_tests_and_frozen`
  - `ac10_does_not_satisfy_ac1`: `missing_ids("covers AC-10", ["AC-1"]) == ["AC-1"]`.
  - `id_at_line_end_with_crlf`: `added_lines("+test AC-2\r\n")` then `missing_ids(.., ["AC-2"])`
    is empty. (Review Focus 5.)
  - `plus_plus_plus_header_ignored`
- [ ] **Step 2:** run → FAIL. **Step 3:** implement. **Step 4:** run → PASS.
- [ ] **Step 5:** `git commit -m "feat(story): emitter, path rules and criterion check"`

### Task 4: The stream-json parser

**Files:** Create `src/stream.rs`, `tests/fixtures/stream-basic.jsonl`; modify `src/lib.rs`.

**Interfaces:**
- Consumes: `UsageRow` (Task 3).
- Produces:
  - `pub struct ModelTotals { pub input: Option<u64>, pub output: Option<u64>, pub cache_read: Option<u64>, pub cache_write: Option<u64> }`
  - `pub struct FinalResult { pub subtype: String, pub is_error: bool, pub num_turns: Option<u32>, pub text: String, pub model_usage: BTreeMap<String, ModelTotals> }`
  - `pub struct StreamParser`, with:
    - `pub fn new(first_call_seq: u64, provider: String) -> Self`
    - `pub fn feed(&mut self, line: &str) -> Vec<UsageRow>`
    - `pub fn finish(self) -> CallSummary`
    - `pub struct CallSummary { pub next_call_seq: u64, pub final_result: Option<FinalResult>, pub flushed: Vec<UsageRow>, pub residue: Vec<UsageRow> }`
  - `pub fn budget_tokens(row: &UsageRow) -> u64`: `prompt − cached_prompt + output`, with `None`
    counted as 0 and the subtraction saturating.

**The parsing rules.** These pin field paths that the live check (Task 12) confirms.

- Each line is parsed as JSON. A line that fails to parse, or is not an object, is skipped
  (Review Focus 2).
- **`{"type":"stream_event","event":{"type":"message_start","message":{…}}}` opens a call.**
  - The model is read from `event.message.model`.
  - `input` is `event.message.usage.input_tokens`, `cache_write` is
    `cache_creation_input_tokens`, and `cache_read` is `cache_read_input_tokens`. Each is
    `Option<u64>`.
  - If a call is already open, it is closed first and emitted with `output: None`.
- **`…"event":{"type":"message_delta","usage":{"output_tokens":N}}` closes the open call** and
  emits its row:
  - `call_seq` is the next seq.
  - `prompt` is `input + cache_write + cache_read`, but only when all three are `Some`; otherwise
    `None`.
  - `cached_prompt` is `cache_read` and `cache_write` is `cache_write`.
  - `output` is `N`, `thinking` is `None` and `attributed` is `true`.
- **`{"type":"result",…}` sets `final_result`:** `subtype`, `is_error`, `num_turns`, `result` as
  the text, and `modelUsage` as a map of model to `{inputTokens, outputTokens,
  cacheReadInputTokens, cacheCreationInputTokens}`.
- **`finish` flushes a still-open call** (as `flushed`, with output unknown). It then computes the
  residue. For each model in `model_usage`, it compares the totals with the sum of that model's
  attributed rows, treating `None` as 0. If any of the four totals is larger, it adds one
  `attributed: false`, `call_seq: None` row of the differences, saturating. Here `prompt` is
  input + cache_write + cache_read, `cached_prompt` is cache_read, and so on.

- [ ] **Step 1: Write the fixture.** `stream-basic.jsonl` holds:
  1. a `system`/`init` line;
  2. a non-JSON line `warning: something`;
  3. two calls, each a `message_start` and `message_delta` pair, with models `claude-a` and
     `claude-a`, and usage (10, 5, 20 → output 7) and (3, 0, 30 → output 4);
  4. an `assistant` line;
  5. a `result` line whose `modelUsage` for `claude-a` is
     `{inputTokens:13, outputTokens:11, cacheReadInputTokens:50, cacheCreationInputTokens:5}`,
     plus `claude-helper` with `{inputTokens:2, outputTokens:1, cacheReadInputTokens:0, cacheCreationInputTokens:0}`;
  6. a final truncated line `{"type":"stre`.
- [ ] **Step 2: Write the failing tests:**
  - `basic_fixture_rows`: two rows, seq 1 and 2. Row 1 is `prompt 35, cached_prompt 20, cache_write 5, output 7`.
  - `residue_for_unattributed_model`: one residue row, `model_id claude-helper`, `prompt 2`,
    `output 1`. There is no residue for `claude-a`, because its totals equal its rows.
  - `missing_cache_field_makes_prompt_null`
  - `start_without_delta_flushes_output_null`
  - `no_result_line_gives_none_final`
  - `budget_excludes_cache_reads`: the budget for row 1 is 10 + 5 + 7 = 22.
  - `final_result_reads_turns_and_text`
- [ ] **Step 3:** run → FAIL. **Step 4:** implement. **Step 5:** run → PASS.
- [ ] **Step 6:** `git commit -m "feat(story): stream-json usage parser"`

### Task 5: Prompts and the agent's claims

**Files:** Create `src/prompts.rs`; modify `src/lib.rs`.

**Interfaces:**
- Consumes: `WorkOrder` (Task 2).
- Produces:
  - `pub fn fill(template: &str, vars: &[(&str, &str)]) -> String`. It is single-pass: it scans
    left to right for `@@NAME@@`, looks the name up in `vars`, and leaves unknown tokens as they
    are. Inserted text is never rescanned.
  - `pub fn fence(untrusted: &str) -> String` returns ```` ````text\n<body>\n```` ````, where
    `<body>` has every run of three or more backticks replaced with `'''`.
  - `pub fn dangerous_patterns(text: &str) -> Vec<&'static str>` checks plain substrings: `"$("`,
    `` "`" ``, `"${"`, `"rm -rf /"`, `"chmod 777"`, `"eval "`. It also reports `"curl|sh"` when a
    line contains `curl` and later `| sh`, and likewise `"wget|sh"`.
  - `pub fn red_prompt(wo: &WorkOrder, previous_failure: Option<&str>) -> String`
  - `pub struct GreenContext<'a> { pub call: u32, pub red_files: &'a [String], pub last_test_tail: &'a str, pub history: &'a [String] }`
  - `pub fn green_prompt(wo: &WorkOrder, ctx: &GreenContext) -> String`
  - `pub struct TestsDefective { pub test: String, pub reason: String }`
  - `pub struct Claims { pub criteria_map: Option<serde_json::Value>, pub tests_defective: Option<TestsDefective> }`
  - `pub fn read_claims(final_text: &str) -> Claims`. It parses the content of the last
    ```` ```json:criteria-map ```` fenced block, and the `testsDefective` object of the last
    ```` ```json:iteration-summary ```` block. A malformed block yields `None`.

**Template copy** (exact). The story text, criteria, evidence and test tail are each inserted
through `fence`. Criteria render as `- <id>: <text>`, one per line, inside one fence.

```text
# Role: test author

You are writing tests for one story, before it is implemented. Do not implement it.

## Story @@STORY_ID@@: @@TITLE@@

@@DESCRIPTION@@

## Acceptance criteria (fixed; do not add, drop or reword any)

@@CRITERIA@@

## Rules

- Write or change test files only. Do not change any other file.
- Write at least one test per criterion. Put the criterion id (for example AC-1) in the test's
  name or in a comment on the line beside it.
- The tests must fail now, because the behaviour does not exist yet.
- Do not run git. Do not commit. The harness commits for you.
- When done, print a criteria map as the last thing in your reply:

```json:criteria-map
{"<criterion id>": ["<test name>", "..."]}
```

@@EVIDENCE@@
@@PREVIOUS@@
```

```text
# Role: implementer

Implement story @@STORY_ID@@ so that its tests pass. This is call @@CALL@@.

## Story @@STORY_ID@@: @@TITLE@@

@@DESCRIPTION@@

## Acceptance criteria

@@CRITERIA@@

## Frozen tests (do not edit, move or delete these files, or any test or runner configuration)

@@RED_FILES@@

## Rules

- Change source files only. The harness rejects any change to tests or test configuration.
- Do not run git. Do not commit. The harness commits for you and runs the tests after you finish.
- If you are certain a frozen test contradicts its criterion, stop and report it in your summary
  instead of working around it:

```json:iteration-summary
{"testsDefective": {"test": "<test name>", "reason": "<why>"}}
```

@@EVIDENCE@@
@@HISTORY@@
@@LAST_TEST@@
```

`@@EVIDENCE@@` renders as `## Earlier attempts failed like this` followed by each entry's
`summary` and `detail` in a fence, or as an empty string when there is no evidence.
`@@PREVIOUS@@`, `@@HISTORY@@` and `@@LAST_TEST@@` follow the same pattern, with the headings
`## Your previous attempt was rejected`, `## Earlier calls` and `## Last test run (tail)`.

- [ ] **Step 1: Write the failing tests:**
  - `fill_is_single_pass`: `fill("@@A@@ @@B@@", [("A","@@B@@"),("B","x")]) == "@@B@@ x"`.
  - `fence_breaks_backtick_runs`: the body `"a ``` b ````"` contains no run of 3 or more
    backticks after fencing.
  - `dangerous_patterns_found`: `"curl x | sh"` → contains `"curl|sh"`; `"$(id)"` → contains `"$("`.
  - `red_prompt_lists_every_criterion_and_no_raw_tokens`: the output contains `- AC-1:` and
    `- AC-2:` and no `@@`.
  - `red_prompt_with_injected_token_stays_literal`: a description containing `@@CRITERIA@@`
    appears literally, and the criteria block appears exactly once.
  - `claims_read_last_blocks`
  - `claims_tolerate_malformed_json`
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** `git commit -m "feat(story): prompts and agent claims"`

### Task 6: Limits, supervised children, and `fake-claude`

**Files:** Create `src/limits.rs`, `src/proc.rs`, `src/bin/fake-claude.rs`; modify `src/lib.rs`
and `Cargo.toml` (the `fake-claude` bin).

**Interfaces:**
- Consumes: `LimitsSpec` (Task 2).
- Produces (`limits.rs`):
  - `pub struct Limits`, with:
    - `pub fn new(spec: &LimitsSpec, start: Instant) -> Self`
    - `pub fn deadline(&self) -> Instant`
    - `pub fn remaining(&self) -> Option<Duration>`: `None` at or after the deadline.
    - `pub fn turns_left(&self) -> u32`
    - `pub fn spend_turns(&self, n: u32)`, saturating.
    - `pub fn add_tokens(&self, n: u64)`
    - `pub fn tokens_exhausted(&self) -> bool`: true if used ≥ limit.
    - `pub fn tokens_used(&self) -> u64`
  - The counters are atomics, so `&Limits` can be shared with the stream reader thread; `Limits`
    is `Sync`.
- Produces (`proc.rs`):
  - `pub fn install_signal_handler() -> Result<(), String>`: `ctrlc::set_handler` sets a static
    `INTERRUPTED: AtomicBool`.
  - `pub fn interrupted() -> bool`
  - `pub enum EndedBy { Normal, Deadline, Interrupted, TokenLimit }`
  - `pub struct Exit { pub code: Option<i32>, pub ended_by: EndedBy }`
  - `pub fn spawn_grouped(cmd: &mut Command) -> io::Result<Child>`: on Unix it sets
    `process_group(0)` first. Every child in the crate is spawned through it.
  - `pub fn supervise(child: &mut Child, deadline: Instant, over_budget: &dyn Fn() -> bool, grace: Duration) -> io::Result<Exit>`.
    It polls `try_wait` every 100 ms. On the deadline, an interrupt or `over_budget()`, it calls
    `interrupt(child)` once and records why. After `grace` it calls `kill_all(child)`. It then
    waits.
  - `fn interrupt(child: &mut Child)`: on Unix, `libc::kill(-pid, SIGINT)` (the group); on
    Windows, `child.kill()`.
  - `fn kill_all(child: &mut Child)`: on Unix, `libc::kill(-pid, SIGKILL)`; on Windows,
    `child.kill()`.
  - `pub fn shell(cmdline: &str) -> Command`: `sh -c` on Unix, `cmd` with `raw_arg` on Windows
    (Global Constraints), plus `env("CI","true")`. On Windows `cmd` reports a command that is not
    found as exit 1, not 127. The 126/127 rule therefore applies on Unix only, and on Windows a
    missing runner shows up as `base_broken` at provision.
  - `pub struct TestRun { pub exit: Exit, pub log: PathBuf, pub tail: String }`
  - `pub fn run_tests(cmdline: &str, cwd: &Path, log: &Path, deadline: Instant, over_budget: &dyn Fn() -> bool, grace: Duration) -> io::Result<TestRun>`.
    stdin is null, and stdout and stderr both go to the `log` file. `tail` is the last 2 048 bytes
    of the log, read lossily as UTF-8.
  - `pub fn grace_from_env() -> Duration` reads `REQDRIVE_GRACE_MS`, default 30 000.
- Produces (`fake-claude`):
  - **`fake-claude check-tests <dir>`:** for each file under `<dir>`, each line
    `expect <relpath> <needle>` must hold, meaning the file `<relpath>` relative to the current
    directory exists and contains `<needle>`. Exit 0 if every line holds, 1 otherwise. Zero files
    means exit 0.
  - **Otherwise it acts as `claude`.** It reads stdin to the end and appends its argv as a JSON
    array line to `$FAKE_CLAUDE_LOG`, if that is set. It then picks the call `index` by reading and
    incrementing the integer in the file `$FAKE_CLAUDE_COUNTER`, and runs `calls[index]` from the
    JSON file `$FAKE_CLAUDE_SCRIPT`, doing in order:
    1. `writes: {relpath: content}`, creating parent directories;
    2. `deletes: [relpath]`;
    3. `lines: [string]`, printed verbatim if present; otherwise the default stream: one
       `message_start` with model `claude-fake` and usage `(10,5,20)`, one `message_delta` with
       output 7, then the `result` line;
    4. `sleep_ms` before the `result` line, with stdout flushed first;
    5. `exit` (default 0).

    The default `result` line uses `subtype` (default `"success"`), `num_turns` (default 1), and
    `text` (default `""`) as `result`, with a matching `modelUsage`. A call index past the end of
    the script prints nothing and exits 3.

- [ ] **Step 1: Write the failing tests:**
  - `limits_remaining_none_after_deadline`
  - `limits_tokens_exhausted_at_limit`
  - `turns_saturate`
  - **In `crates/reqdrive/tests/proc.rs`** (an integration test), using
    `env!("CARGO_BIN_EXE_fake-claude")` and a temp script:
    - `supervise_normal_exit_code`: a call with `exit: 4` gives `Exit{code:Some(4), ended_by:Normal}`.
    - `supervise_deadline_interrupts`: `sleep_ms: 5000`, a deadline of now + 300 ms and a grace of
      200 ms give `ended_by == Deadline` within 2 s.
    - `supervise_token_limit`: `over_budget` returns true → `TokenLimit`.
    - `run_tests_captures_and_tails`: `shell` running `fake-claude check-tests t` against a
      directory with a failing expectation → code 1, and the log file exists.
    - `run_tests_tail_is_bounded`: a fake-claude call that prints ~3 MB (`lines` with 3 000 lines
      of 1 000 chars), run through `run_tests` as the command, gives a tail of ≤ 2 048 bytes.
      (Review Focus 3.)
    - `#[cfg(unix)] interrupt_reaches_grandchild`: `shell("sh -c 'sleep 30' & wait")` with a
      past deadline ends within grace + 1 s, and no `sleep 30` process from that group remains.
    - `fake_check_tests_semantics`: zero files → 0; a met expectation → 0; an unmet one → 1.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS on Windows locally; Unix-only
  assertions are `#[cfg(unix)]`.
- [ ] **Step 5:** `git add` the source and `tests/proc.rs`, then
  `git commit -m "feat(story): limits, supervised children and the fake agent"`

### Task 7: Git operations

**Files:** Create `src/git.rs`; modify `src/lib.rs`.

**Interfaces:**
- Produces:
  - `pub struct Git { ws: PathBuf }` and `pub struct GitError { pub args: String, pub code: Option<i32>, pub stderr: String }`
    (with `Display`).
  - Every method runs `git -C ws -c core.hooksPath=<hooks_dir> <args>`, captures output, and
    returns `Result<_, GitError>` on a non-zero exit:
    - `new(ws: &Path, hooks_dir: &Path)`. The driver passes `<state_dir>/no-hooks` (an empty
      directory it creates).
    - `with_env(self, vars: Vec<(String, String)>) -> Self` adds env to every call. It is used by
      tests to isolate git config without touching process env.
    - `is_work_tree() -> bool`
    - `commit_exists(sha) -> bool`
    - `head() -> Result<String>`
    - `is_clean() -> Result<bool>`, using `status --porcelain --untracked-files=all`
    - `branch_sha(name) -> Result<Option<String>>`
    - `current_branch() -> Result<Option<String>>`
    - `switch(name) -> Result<()>` and `switch_create(name, at) -> Result<()>`
    - `ref_format_ok(refname: &str) -> bool`, using `check-ref-format`; for a bare branch name it
      checks `refs/heads/<name>`
    - `stage_all() -> Result<()>`
    - `staged_paths() -> Result<Vec<String>>`, using `diff --cached --name-only --no-renames -z HEAD`
    - `staged_patch() -> Result<String>`, using `diff --cached --binary HEAD`
    - `commit(msg) -> Result<String>`, with the identity flags from Global Constraints; it returns
      the new HEAD
    - `reset_clean() -> Result<()>`, which is `reset --hard HEAD` then `clean -fd`
    - `reset_to(sha) -> Result<()>`
    - `diff_u0(from, to) -> Result<String>`
    - `changed_files(from, to) -> Result<Vec<String>>`, with `--no-renames`
    - `push(remote, sha, refname, deadline: Instant, grace: Duration) -> Result<()>`. It is spawned
      through `proc::spawn_grouped` and `supervise`, so a hung push cannot outlive the wall clock.
      A deadline gives a `GitError` whose detail starts `deadline`.
  - Every `Command` has `stdin(Stdio::null())`, piped stdout and stderr, and
    `env("GIT_TERMINAL_PROMPT","0")`.

- [ ] **Step 1: Write the failing tests** (a temp repo built with the real `git`):
  - `clean_detects_untracked`
  - `switch_create_and_branch_sha`
  - `staged_paths_lists_add_delete_rename`: after `git mv test/a.test src/a.txt`, both
    `test/a.test` and `src/a.txt` are listed.
  - `commit_works_without_identity_config`: build a `Git` with `with_env` setting
    `GIT_CONFIG_GLOBAL` to an empty temp file and `GIT_CONFIG_NOSYSTEM=1`, then commit → `Ok`.
  - `commit_bypasses_failing_hooks`: install `.git/hooks/pre-commit` and
    `.git/hooks/prepare-commit-msg`, each `#!/bin/sh\nexit 1\n`, made executable on Unix with
    `std::os::unix::fs::PermissionsExt` → `commit` is `Ok`. (Review Focus 4.)
  - `reset_clean_removes_untracked_but_keeps_ignored`
  - `push_to_bare_remote_without_upstream`: after the push, `git config --get branch.<b>.remote`
    is unset.
  - `ref_format_rejects_bad_names`: `"a..b"` → false.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** `git commit -m "feat(story): git operations"`

### Task 8: Inference policy and the claude-code adapter

**Files:** Create `src/policy.rs`, `src/agent.rs`; modify `src/lib.rs`.

**Interfaces:**
- Consumes: `Inference`, `WorkOrder`, `Isolation` (Task 2); `Emitter`, `Event`, `UsageRow` (Task
  3); `StreamParser`, `budget_tokens`, `FinalResult` (Task 4); `Limits`, `supervise`, `Exit`
  (Task 6).
- Produces (`policy.rs`):
  - `pub struct Choice { pub provider_label: String, pub model: String, pub set_env: Vec<(String, String)>, pub remove_env: Vec<&'static str> }`
  - `pub fn choose(inf: &Inference) -> Result<Choice, String>`. It takes the first entry that
    satisfies both of these:
    - the provider is one of `anthropic`, `bedrock`, `vertex`, `foundry`, or `gateway` with a
      `base_url`;
    - the first model is a Claude model: its id starts with `claude-`, or it is one of the aliases
      `sonnet`, `opus`, `haiku`, `fable`.
  - The environment per provider:
    - **anthropic:** remove `ANTHROPIC_BASE_URL`, `CLAUDE_CODE_USE_BEDROCK`,
      `CLAUDE_CODE_USE_VERTEX` and `CLAUDE_CODE_USE_FOUNDRY`.
    - **bedrock, vertex, foundry:** set `CLAUDE_CODE_USE_<P>=1` and remove the other two flags and
      the base URL.
    - **gateway:** set `ANTHROPIC_BASE_URL` and remove all three flags. Its label is
      `gateway:<host of base_url>`.
  - If no entry qualifies: `Err` naming each entry and why it failed.
- Produces (`agent.rs`):
  - `pub struct ClaudeCode { pub bin: PathBuf, pub choice: Choice, pub permission_args: Vec<String> }`
  - `ClaudeCode::new(wo: &WorkOrder, choice: Choice, bin: PathBuf, test_command: &str) -> Self`.
    `permission_args` depend on isolation:
    - **`Container`:** `["--permission-mode","bypassPermissions"]`.
    - **Otherwise:** `["--permission-mode","acceptEdits","--allowedTools", <comma-joined rules>]`.
      The rules are `Bash(<tc>)`, `Bash(<tc> *)` and every `agent_allow` entry.
  - `pub fn args(&self, max_turns: u32) -> Vec<String>` returns `-p`, `--output-format`,
    `stream-json`, `--verbose`, `--include-partial-messages`, `--model <m>`, `--max-turns <n>` and
    `--disallowedTools Agent,Skill`, followed by `permission_args`.
  - `pub struct CallOutcome { pub exit: Exit, pub final_result: Option<FinalResult>, pub next_call_seq: u64 }`
  - `pub fn run(&self, ws: &Path, state_dir: &Path, index: u32, prompt: &str, max_turns: u32, first_call_seq: u64, limits: &Limits, emitter: &Emitter, grace: Duration) -> io::Result<CallOutcome>`.
    It runs these steps:
    1. Write `state_dir/call-<index>.prompt.md` and use it as stdin.
    2. Spawn the agent through `proc::spawn_grouped` with `current_dir(ws)`, stdout piped, stderr
       to `call-<index>.stderr.log`, and the env `CI=true`,
       `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` and the choice's env. A spawn error is returned as
       `Err`, and the driver maps it to `HarnessError`.
    3. In a reader thread, write each stdout line to `call-<index>.jsonl`, `feed` it to the
       parser, and for each row emit `Event::Usage` and call `limits.add_tokens(budget_tokens(&row))`.
    4. Run `supervise` with `over_budget = || limits.tokens_exhausted()`.
    5. Join the reader and call `finish`, emitting the flushed and residue rows.
    6. If `final_result` is `None`, emit `error(UsageIncomplete, …)`.
  - `pub fn bin_from_env() -> PathBuf`: `REQDRIVE_CLAUDE_BIN`, or `claude`.

- [ ] **Step 1: Write the failing tests:**
  - `choose_refuses_local_only`: `[{provider:"ollama", models:["qwen3-coder"]}]` gives an `Err`
    containing `ollama`.
  - `choose_refuses_non_claude_model_on_gateway`
  - `choose_gateway_label_uses_host`
  - `choose_skips_bad_entry_takes_next`
  - `args_container_bypass`
  - `args_default_allows_test_prefix`: the args contain `Bash(npm test),Bash(npm test *)`.
  - **In `crates/reqdrive/tests/agent.rs`** (an integration test), using `fake-claude` with the
    default stream:
    - `run_emits_usage_rows_and_counts_tokens`: the events captured contain one `usage`, and
      `tokens_used == 22`.
    - `run_without_result_emits_usage_incomplete`: the script gives `lines` with no result line.
    - `run_passes_args`: the `FAKE_CLAUDE_LOG` line contains `--max-turns` and `7`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** `git commit -m "feat(story): inference policy and claude-code adapter"`

### Task 9: The driver, part 1 — validate, provision, Red, publish; the CLI

**Files:** Create `src/story.rs`, `tests/common/mod.rs`, `tests/story_red.rs`; modify `src/main.rs`, `src/lib.rs`.

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `pub struct Env { pub claude_bin: PathBuf, pub heartbeat: Duration, pub grace: Duration }`
    with `Env::from_process()`.
  - `pub fn run(work_order: &Path, emitter: &Emitter, env: &Env) -> ResultEvent`. It never
    panics on bad input: every failure becomes a `ResultEvent` per spec §3.5.1.
  - `main.rs` handles three arguments:
    - **`story <path>`:** build `Emitter::new(Box::new(io::stdout()))` and install the signal
      handler. Then run
      `let r = std::panic::catch_unwind(AssertUnwindSafe(|| story::run(..))).unwrap_or_else(|p| ResultEvent::end(Failed, HarnessError, <panic msg>))`
      and `emitter.finish(&r)`. Exit 0 on `Ok`, or 1 if writing failed. There is no global panic
      hook. Threads the driver starts (the reader and the heartbeat) are joined, and a `join` error
      becomes a `HarnessError` (or `UsageIncomplete` for the reader).
    - **`--version`:** print the version and exit 0.
    - **Anything else:** print the usage text to stderr and exit 2.
- **Stage logic for this task.** It follows spec §3.2, §3.3, §3.4 and §3.5.1 exactly. Each stage
  emits `Progress` first.
  - **`validate`**, in order:
    1. Read and parse the work order, then run `validate_shape` and `cap_evidence`. Any failure →
       `WorkOrderInvalid`.
    2. Call `set_attempt_id`.
    3. Create `state_dir` if it is missing. It must be empty, or it is `WorkOrderInvalid`. Then
       `attach_log(state_dir/events.jsonl)`.
    4. `is_work_tree`, else `WorkOrderInvalid`.
    5. `commit_exists(base)`, else `BaseMissing`.
    6. `head == base` and `is_clean`, else `WorkOrderInvalid`.
    7. `ref_format_ok` for the branch and the tests ref, else `WorkOrderInvalid`.
    8. Resolve `test_command`: the work order's value, then `<ws>/reqdrive.json`'s `testCommand`.
       If neither exists → `WorkOrderInvalid`.
    9. `policy::choose`, else `PolicyUnsatisfiable`.
    10. Run `dangerous_patterns` over the story text and the evidence, emitting each hit as a
        `Log{System}` warning.
  - **`provision`:**
    1. Look up the attempt branch:
       - **At another commit:** `BranchConflict`.
       - **At base:** switch to it if needed.
       - **Absent:** `switch_create`.
    2. Run `run_tests` at the base, with `waiting_on = Tests`. A non-zero code is `BaseBroken`; a
       limit is `Halted LimitReached`; an interrupt is `Halted Interrupted`.
    3. `reset_clean`.
  - **`red`:** at most 2 attempts. Each attempt:
    1. Make an agent call with `red_prompt(wo, prev)`. Map its exit:
       - `Deadline` or `TokenLimit` → `Halted LimitReached`;
       - `Interrupted` → `Halted Interrupted`;
       - a final `subtype == "error_max_turns"` → `Halted LimitReached`;
       - another non-zero code → `AgentError`.
    2. `spend_turns(num_turns.unwrap_or(max_turns))`.
    3. `stage_all`, then `staged_paths`:
       - **Denied hits:** write `state_dir/scope-violation-red-<n>.patch`, `reset_clean`, and end
         `ScopeViolation`. This is never retried.
       - **Nothing staged:** `prev = "no files changed"` and retry.
       - **Red violations:** `reset_clean`, and retry with them as `prev`.
       - **`test_paths` empty:** a `Log` warning.
    4. Commit, then check `missing_ids` against `added_lines(diff_u0(base, red))`. If any are
       missing: `reset_to(base)` and retry.
    5. Run `run_tests` at the red commit, then `reset_clean`:
       - **Exit 126 or 127:** `HarnessError`.
       - **Exit 0:** `red_not_failing`; `reset_to(base)` and retry. On the last attempt this is
         `ResultEvent::end(NoChange, RedNotFailing, …)`.
       - **Otherwise:** set `red_observed = true`.
    6. Write `state_dir/criteria-map.json` from the claims, if present, and emit
       `Artifact{CriteriaMap}`.

    If the last attempt failed checks 1–3, the result is `RedInvalid`.
  - **`red_published`:** `push(remote, red_sha, tests_ref)`, else `PushFailed`. Then emit
    `Artifact{TestsRef, sha}` and set `tests_ref_sha`.
  - **Interrupts and budgets between steps.** Before each stage, and before each agent call, test
    run or push, the driver checks:
    - `proc::interrupted()` → `Halted Interrupted`;
    - `remaining()` is `None`, `turns_left() == 0`, or `tokens_exhausted()` → `Halted LimitReached`.

    After every agent call it checks `tokens_exhausted()` again, which gives the same result. No
    child is ever started with a zero budget (spec §3.6).
  - **One way to end.** `fn end(&self, outcome, category, detail) -> ResultEvent` emits
    `Event::Error` (the fatal error, spec §3.10) and returns the result. Every failing path uses
    it. Paths that end with `no_change` also go through it.
  - **What the driver also emits:**
    - after each test run, a `Log{Test}` event with the last 20 lines of the tail, and
      `Artifact{LogFile, ref: <log path>}`;
    - for each stage, one human-readable line on stderr (`eprintln!`), as the Bash version logged.
  - Until Task 10 adds Green, a successful Red ends with `ResultEvent::end(Failed, HarnessError, "green not implemented")`,
    so the tests can see the stage events.
  - The heartbeat is a thread that ticks every `env.heartbeat` and emits `Heartbeat{waiting_on}`
    while a shared `Mutex<Option<WaitingOn>>` is `Some`. The driver sets it around each agent
    call (`Agent`), test run (`Tests`) and push (`Push`). It is stopped and joined before `run`
    returns.
- **Test helpers** (`tests/common/mod.rs`):
  - `struct Fixture { root: TempDir, remote: PathBuf, ws: PathBuf, base: String }`.
    `Fixture::new()` creates the temp dir with the prefix `"rd story "`, so it contains a space
    (Review Focus 1). It makes a bare `remote.git`, and a clone `ws` with one commit containing
    `README.md` and an empty `test/.keep`.
  - `fn order(&self) -> serde_json::Value`, a default work order:
    - two criteria, `AC-1` and `AC-2`;
    - `test_command = "\"<fake-claude>\" check-tests test"`;
    - `test_paths = ["test"]`;
    - `state_dir = root/state`;
    - limits of 50 turns, 120 s and 1 000 000 tokens;
    - `inference = [{provider:"anthropic", models:["claude-sonnet-5-5"]}]`;
    - `repo.remote = "origin"`.
  - `fn run(&self, order: &Value, script: &Value) -> (Vec<Value> /*events*/, i32 /*exit*/)`. It
    writes the order, the script, `FAKE_CLAUDE_COUNTER` and `FAKE_CLAUDE_LOG` under `root/harness/`,
    outside both the workspace and `state_dir`, so that `git add -A` never sweeps them in and
    `state_dir` starts empty. It then runs `CARGO_BIN_EXE_reqdrive story <order>` with the
    env `REQDRIVE_CLAUDE_BIN=<fake>`, `FAKE_CLAUDE_SCRIPT`, `FAKE_CLAUDE_COUNTER`,
    `REQDRIVE_HEARTBEAT_MS=50` and `REQDRIVE_GRACE_MS=200`, and parses the stdout lines.
  - `fn result(events) -> &Value`
  - Script helpers:
    - `red_ok()` writes `test/feature.test` containing `AC-1 AC-2\nexpect src/feature.txt done\n`.
    - `green_ok()` writes `src/feature.txt` containing `done`.

- [ ] **Step 1: Write the failing integration tests** (`tests/story_red.rs`):
  - `unparsable_order_gives_work_order_invalid_with_null_attempt`
  - `dirty_workspace_is_rejected`
  - `local_only_policy_is_refused_before_any_agent_call`: the counter file is never created.
  - `existing_branch_elsewhere_is_branch_conflict`
  - `base_broken_when_tests_fail_at_base`: commit a failing expectation into the base first.
  - `red_publishes_tests_ref`: the remote has `tests_ref` at the red commit; the red commit's
    message starts `test: [S-1]`; there is a `progress` `red_published` event; and the last event
    is the result.
  - `red_missing_criterion_retries_then_red_invalid`: two calls each write a test naming only
    AC-1, so the result category is `red_invalid` and the counter is 2.
  - `red_not_failing_gives_no_change`: the test's expectation already holds.
  - `red_touching_workflow_is_scope_violation_and_never_pushed`: it writes
    `.github/workflows/x.yml`; the remote has no attempt branch and no tests ref; and the patch
    file exists in the state dir.
  - `agent_exit_1_is_agent_error`
  - `events_have_consecutive_seq_and_result_last`
  - `state_dir_not_empty_is_rejected`
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** `git commit -m "feat(story): driver validate/provision/red and the CLI"`

### Task 10: The driver, part 2 — Green, Check, Deliver

**Files:** Modify `src/story.rs`; create `tests/story_green.rs`.

**Interfaces:**
- Consumes: Task 9's `run` and its helpers.
- **Stage logic** (spec §3.3, §3.4, §3.5.1):
  - **`green`:** for `call` in `1..=green_max_calls.unwrap_or(5)`:
    1. If `remaining()` is `None` or `turns_left() == 0` → `Halted LimitReached`.
    2. Make an agent call with `green_prompt` (the same exit mapping as Red), then read the claims.
    3. `stage_all`, then `staged_paths`:
       - **Denied:** a patch file, `reset_clean`, and `ScopeViolation`.
       - **`green_violations`:** a patch file, `reset_clean`, and `TestsModified`.
       - **Nothing staged:** record `call <n>: no change` in the history. If the claims include
         `tests_defective`, end `TestsDefective` with `tests_defective: true`; otherwise
         `continue`.
    4. Commit `feat: [<story>] green <n>`.
    5. Run `run_tests`, then `reset_clean`:
       - **Exit 126 or 127:** `HarnessError`.
       - **Exit 0:** passed. If `tests_defective` was claimed, emit it as a `Log` and break.
       - **Otherwise:** remember the tail. If `tests_defective` was claimed, end `TestsDefective`.

    If the loop ends without a pass → `TestsFailed`.
  - **`check`:** `run_tests` at a clean HEAD. A non-zero code → `TestsFailed`. Set `evidence`.
  - **`deliver`:** `push(remote, head, "refs/heads/<attempt_branch>")`. Failure → `PushFailed`.
    Success → emit `Artifact{Branch, ref: attempt_branch, sha: head}`, then
    `ResultEvent::pushed(head)` with `tests_ref_sha`, `red_observed` and `evidence`.
  - **Evidence push.** On any `Failed` or `Halted` result after `red_published`, if HEAD differs
    from the base, push the attempt branch as evidence (best effort, logged) and set `head_sha`.
    This happens before returning. It is skipped when the cause is `Interrupted`, because the
    orchestrator is stopping the attempt and an extra network call would delay the exit. This
    narrows spec §3.3's "pushed on halt too" to halts caused by limits, and the spec records it.
    It is also skipped when the deadline has passed.

- [ ] **Step 1: Write the failing integration tests** (`tests/story_green.rs`):
  - `happy_path_pushes_branch`: the script is `[red_ok, green_ok]`. Outcome `pushed`; the remote's
    attempt branch equals `head_sha`; the branch has exactly two commits over base (`test:` then
    `feat:`); and `usage` events have `thinking: null`.
  - `green_editing_frozen_test_is_tests_modified`: the second call rewrites `test/feature.test`.
  - `green_editing_frozen_path_is_tests_modified`: `frozen_paths = ["package.json"]`, and green
    writes it.
  - `green_tests_defective_claim_stops`: green writes nothing and prints the summary block in its
    `text`, so the result has `tests_defective: true` and category `tests_defective`.
  - `green_defective_claim_ignored_when_tests_pass`: the outcome is `pushed`, with a log event.
  - `green_exhausts_calls_is_tests_failed_and_branch_pushed_as_evidence`:
    `green_max_calls = 2`, and green writes the wrong content twice.
  - `green_empty_call_does_not_rerun_tests`: `[red_ok, {}, green_ok]` gives `pushed`, and the
    history shows a no-change call.
  - `wall_clock_limit_halts`: `limits.wall_clock_secs = 2`, and green sleeps 5 000 ms. The outcome
    is `halted`, category `limit_reached`, in under 4 s.
  - `token_limit_halts`: `limits.tokens = 30`; each default call counts 22, so the check after
    the green call (44 ≥ 30) halts. The outcome is `halted`, `limit_reached`, and there is no
    `feat:` commit on the remote.
  - `heartbeat_emitted_while_agent_sleeps`: green sleeps 300 ms, so at least one `heartbeat` with
    `waiting_on: agent` appears.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS.
- [ ] **Step 5:** `git commit -m "feat(story): driver green/check/deliver"`

### Task 11: Signals and parallel safety

**Files:** Create `tests/story_parallel.rs`, `tests/story_signals.rs`; modify `src/story.rs` only
if a test exposes a defect.

- [ ] **Step 1: Write the tests:**
  - `two_attempts_in_parallel_worktrees` (both platforms):
    1. Create two worktrees of the fixture repo with `git worktree add --detach <path> <base>`.
    2. Give them distinct attempt ids, branches, tests refs and state dirs, each with
       `[red_ok, green_ok]` and its own counter file.
    3. Spawn both binaries at once and wait for both.

    Assert:
    - both results are `pushed`;
    - comparing `git for-each-ref` in the main clone before and after, exactly these were added:
      the two local attempt branches, and four remote-tracking refs under `refs/remotes/origin/`
      (each attempt's branch and tests ref). Pushing updates those remote-tracking refs, and each
      is unique to its attempt;
    - `.git/config` is byte-identical to before;
    - each state dir has its own `events.jsonl`.
  - `sigterm_mid_call_gives_halted_interrupted` (`#[cfg(unix)]`): green sleeps 10 000 ms. Read the
    stdout lines as they arrive, and send `SIGTERM` to the reqdrive child via `libc::kill` once a
    `progress` `green` line has been seen, followed by a `heartbeat` with `waiting_on: agent`. Assert:
    - the process exits 0 within 3 s;
    - the last line is the result, with `halted` and `interrupted`;
    - no line follows the result.
- [ ] **Step 2:** run → fix any defect they expose in `story.rs` or `proc.rs` (test first; do not
  weaken the test). **Step 3:** PASS.
- [ ] **Step 4:** `git commit -m "test(story): parallel attempts and signal handling"`

### Task 12: Documents for the new state, and the live check

**Files:** Create `README.md`, `CLAUDE.md`, `docs/STATUS.md`, `ROADMAP.md`. `ROADMAP.md` is the one
roadmap file. Archived copies stay in `archive/bash-v0.3/`.

- **`README.md`:** what `reqdrive story` is (one paragraph), how to build it, how to run it, an
  example work order (the spec §3.2 example, minus `pr`), the event types, the outcome table (a
  link to spec §3.5.1), and the env overrides. It notes that `fake-claude` is a test-only binary.
- **`CLAUDE.md`:**
  - **Architecture:** the file map above.
  - **Principles:**
    - The driver orchestrates and the agent implements.
    - Unknown is `null`.
    - Children never inherit stdout.
    - The seam rules are hard gates, and everything else is warn-only.
  - **Commands:** the cargo commands. Mention that `CARGO_TARGET_DIR` can point at a fast disk,
    without naming any local path. No machine-specific paths go in public docs.
  - **Conventions:** the Global Constraints above, condensed.
  - **Where things stand:** links to the spec, this plan, `docs/STATUS.md` and `ROADMAP.md`.
- **`docs/STATUS.md`:** the state summary (v1 built and offline-tested; the live check pending)
  and a session-log entry for 2026-10-30.
- **`ROADMAP.md`:**
  - spec §10.4's deferred items;
  - questions Q4–Q14 that are still open;
  - the factory M0/M1 plans, marked as not the current path (Q1 ruling);
  - the live check.

- [ ] **Step 1:** Write the four files.
- [ ] **Step 2:** `cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test`
  → PASS.
- [ ] **Step 3:** `git commit -m "docs: README, CLAUDE.md, status and roadmap for the Rust harness"`
- [ ] **Step 4: Live check, only with the owner's go-ahead.** It makes one real call: create a temp
  dir with `git init`, then run

  ```
  claude -p --output-format stream-json --verbose --include-partial-messages --model haiku --max-turns 1 "Reply with the word ok."
  ```

  and save stdout as `crates/reqdrive/tests/fixtures/stream-live.jsonl`. Then add the unit test
  `live_fixture_parses`: at least one row with a known `prompt`, and a `final_result` with
  `num_turns`. If the field paths differ from Task 4's rules, fix the parser test-first, and record
  the correction in the spec's §10. Commit.
