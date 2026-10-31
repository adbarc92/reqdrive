//! The driver: runs one work order through its stages and returns the result.
//!
//! Every path ends in a [`ResultEvent`]. A failing path goes through [`Driver::end`] (or
//! [`fail`] before the driver exists), which also emits the fatal `error` event. The heartbeat
//! thread is stopped and joined before [`run`] returns.

// A stage's `Err` is the terminal result, built once per run, so its size does not matter.
#![allow(clippy::result_large_err)]

use crate::agent::{self, CallOutcome, ClaudeCode};
use crate::criteria::{added_lines, missing_ids};
use crate::events::{ArtifactKind, Emitter, Event, LogStream, Stage, WaitingOn};
use crate::git::{Git, GitError};
use crate::limits::Limits;
use crate::outcome::{Category, Outcome, ResultEvent};
use crate::paths::PathRules;
use crate::policy;
use crate::proc::{self, EndedBy, TestRun};
use crate::prompts::{dangerous_patterns, read_claims, red_prompt};
use crate::workorder::{self, WorkOrder};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

const DEFAULT_HEARTBEAT_MS: u64 = 30_000;
const RED_ATTEMPTS: u32 = 2;
const TEST_LOG_LINES: usize = 20;

/// What the driver takes from its process environment.
#[derive(Debug, Clone)]
pub struct Env {
    pub claude_bin: PathBuf,
    pub heartbeat: Duration,
    pub grace: Duration,
}

impl Env {
    /// `REQDRIVE_CLAUDE_BIN`, `REQDRIVE_HEARTBEAT_MS` (default 30 000) and `REQDRIVE_GRACE_MS`.
    pub fn from_process() -> Env {
        let heartbeat_ms = std::env::var("REQDRIVE_HEARTBEAT_MS")
            .ok()
            .and_then(|v| v.trim().parse::<u64>().ok())
            .filter(|ms| *ms > 0)
            .unwrap_or(DEFAULT_HEARTBEAT_MS);
        Env {
            claude_bin: agent::bin_from_env(),
            heartbeat: Duration::from_millis(heartbeat_ms),
            grace: proc::grace_from_env(),
        }
    }
}

/// Runs the work order at `work_order`. Never panics on bad input: every failure is a result.
pub fn run(work_order: &Path, emitter: &Emitter, env: &Env) -> ResultEvent {
    let waiting: Arc<Mutex<Option<WaitingOn>>> = Arc::new(Mutex::new(None));
    let heartbeat = Heartbeat::start(emitter.clone(), waiting.clone(), env.heartbeat);
    let result = match validate(work_order, emitter, env, waiting) {
        Ok(mut driver) => driver.drive(),
        Err(r) => r,
    };
    match heartbeat.stop() {
        Ok(()) => result,
        Err(detail) => fail(emitter, Outcome::Failed, Category::HarnessError, detail),
    }
}

// ---------------------------------------------------------------------------------------------
// The heartbeat
// ---------------------------------------------------------------------------------------------

/// A thread that emits `heartbeat` every interval while something is being waited on.
/// Dropping it stops and joins the thread, so a panic cannot leave it running.
struct Heartbeat {
    stop: Arc<AtomicBool>,
    handle: Option<JoinHandle<()>>,
}

impl Heartbeat {
    fn start(emitter: Emitter, waiting: Arc<Mutex<Option<WaitingOn>>>, every: Duration) -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        let flag = stop.clone();
        let handle = std::thread::spawn(move || {
            let mut next = Instant::now() + every;
            while !flag.load(Ordering::SeqCst) {
                let now = Instant::now();
                if now < next {
                    std::thread::park_timeout(next - now);
                    continue;
                }
                next = now + every;
                let on = *waiting.lock().unwrap_or_else(|e| e.into_inner());
                if let Some(waiting_on) = on {
                    let _ = emitter.emit(Event::Heartbeat { waiting_on });
                }
            }
        });
        Heartbeat {
            stop,
            handle: Some(handle),
        }
    }

    fn stop(mut self) -> Result<(), String> {
        self.halt()
    }

    fn halt(&mut self) -> Result<(), String> {
        self.stop.store(true, Ordering::SeqCst);
        match self.handle.take() {
            Some(h) => {
                h.thread().unpark();
                h.join()
                    .map_err(|_| "the heartbeat thread panicked".to_string())
            }
            None => Ok(()),
        }
    }
}

impl Drop for Heartbeat {
    fn drop(&mut self) {
        let _ = self.halt();
    }
}

/// Marks what the driver is waiting on for as long as it lives.
struct Waiting(Arc<Mutex<Option<WaitingOn>>>);

impl Waiting {
    fn on(slot: &Arc<Mutex<Option<WaitingOn>>>, what: WaitingOn) -> Waiting {
        *slot.lock().unwrap_or_else(|e| e.into_inner()) = Some(what);
        Waiting(slot.clone())
    }
}

impl Drop for Waiting {
    fn drop(&mut self) {
        *self.0.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}

// ---------------------------------------------------------------------------------------------
// Ending
// ---------------------------------------------------------------------------------------------

fn outcome_name(o: Outcome) -> &'static str {
    match o {
        Outcome::Pushed => "pushed",
        Outcome::NoChange => "no_change",
        Outcome::Failed => "failed",
        Outcome::Halted => "halted",
    }
}

/// Emits the fatal `error` event and builds the result. Used before the driver exists.
fn fail(
    emitter: &Emitter,
    outcome: Outcome,
    category: Category,
    detail: impl Into<String>,
) -> ResultEvent {
    let detail = detail.into();
    let cat = serde_json::to_value(category)
        .ok()
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_default();
    eprintln!(
        "[reqdrive] result: {} ({cat}): {detail}",
        outcome_name(outcome)
    );
    let _ = emitter.error(category, detail.clone());
    ResultEvent::end(outcome, category, detail)
}

fn log(emitter: &Emitter, stream: LogStream, line: impl Into<String>) {
    let _ = emitter.emit(Event::Log {
        stream,
        line: line.into(),
    });
}

fn progress(emitter: &Emitter, stage: Stage, what: &str) {
    let name = serde_json::to_value(stage)
        .ok()
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_default();
    eprintln!("[reqdrive] {name}: {what}");
    let _ = emitter.emit(Event::Progress { stage });
}

// ---------------------------------------------------------------------------------------------
// validate
// ---------------------------------------------------------------------------------------------

/// Drops Windows' `\\?\` verbatim prefix from a canonical path, which git and `cmd` reject.
fn plain_path(p: PathBuf) -> PathBuf {
    #[cfg(windows)]
    {
        let s = p.to_string_lossy();
        if let Some(rest) = s.strip_prefix(r"\\?\UNC\") {
            return PathBuf::from(format!(r"\\{rest}"));
        }
        if let Some(rest) = s.strip_prefix(r"\\?\") {
            return PathBuf::from(rest);
        }
    }
    p
}

fn canonical(p: &Path) -> std::io::Result<PathBuf> {
    fs::canonicalize(p).map(plain_path)
}

/// The test command: the work order's, then `<ws>/reqdrive.json`'s `testCommand`.
fn resolve_test_command(wo: &WorkOrder, ws: &Path) -> Result<String, String> {
    if let Some(c) = wo.test_command.as_deref().filter(|c| !c.trim().is_empty()) {
        return Ok(c.to_string());
    }
    let config = ws.join("reqdrive.json");
    match fs::read_to_string(&config) {
        Ok(text) => {
            let v: serde_json::Value = serde_json::from_str(&text)
                .map_err(|e| format!("{} is not valid JSON: {e}", config.display()))?;
            v.get("testCommand")
                .and_then(|c| c.as_str())
                .filter(|c| !c.trim().is_empty())
                .map(str::to_string)
                .ok_or_else(|| {
                    "no test_command in the work order and no testCommand in reqdrive.json"
                        .to_string()
                })
        }
        Err(_) => {
            Err("no test_command in the work order and no reqdrive.json in the workspace".into())
        }
    }
}

fn validate(
    path: &Path,
    emitter: &Emitter,
    env: &Env,
    waiting: Arc<Mutex<Option<WaitingOn>>>,
) -> Result<Driver, ResultEvent> {
    let start = Instant::now();
    let invalid =
        |detail: String| fail(emitter, Outcome::Failed, Category::WorkOrderInvalid, detail);
    if proc::interrupted() {
        return Err(fail(
            emitter,
            Outcome::Halted,
            Category::Interrupted,
            "interrupted before validation",
        ));
    }
    progress(emitter, Stage::Validate, "checking the work order");

    // 1. Shape.
    let text = fs::read_to_string(path)
        .map_err(|e| invalid(format!("cannot read work order {}: {e}", path.display())))?;
    let mut wo = workorder::parse(&text).map_err(invalid)?;
    workorder::validate_shape(&wo).map_err(invalid)?;
    workorder::cap_evidence(&mut wo);

    // 2. From here on every event carries the attempt id.
    emitter.set_attempt_id(&wo.attempt_id);

    // 3. The workspace exists; state_dir is empty and outside it.
    let ws = canonical(&wo.workspace).map_err(|e| {
        invalid(format!(
            "workspace {} is not accessible: {e}",
            wo.workspace.display()
        ))
    })?;
    let existed = wo.state_dir.exists();
    fs::create_dir_all(&wo.state_dir).map_err(|e| {
        invalid(format!(
            "cannot create state_dir {}: {e}",
            wo.state_dir.display()
        ))
    })?;
    let state_dir = canonical(&wo.state_dir).map_err(|e| {
        invalid(format!(
            "state_dir {} is not accessible: {e}",
            wo.state_dir.display()
        ))
    })?;
    if state_dir.starts_with(&ws) {
        if !existed {
            let _ = fs::remove_dir(&state_dir);
        }
        return Err(invalid(format!(
            "state_dir {} is inside the workspace",
            state_dir.display()
        )));
    }
    let mut entries = fs::read_dir(&state_dir).map_err(|e| {
        invalid(format!(
            "cannot read state_dir {}: {e}",
            state_dir.display()
        ))
    })?;
    if entries.next().is_some() {
        return Err(invalid(format!(
            "state_dir {} is not empty; a retry needs a new attempt and a new state_dir",
            state_dir.display()
        )));
    }
    let hooks = state_dir.join("no-hooks");
    fs::create_dir_all(&hooks).map_err(|e| invalid(format!("state_dir is not writable: {e}")))?;
    emitter
        .attach_log(&state_dir.join("events.jsonl"))
        .map_err(|e| invalid(format!("cannot write events.jsonl in state_dir: {e}")))?;

    // 4–7. The repository.
    let git = Git::new(&ws, &hooks);
    if !git.is_work_tree() {
        return Err(invalid(format!(
            "workspace {} is not a git work tree",
            ws.display()
        )));
    }
    if !git.commit_exists(&wo.base_commit) {
        return Err(fail(
            emitter,
            Outcome::Failed,
            Category::BaseMissing,
            format!("base_commit {} does not exist locally", wo.base_commit),
        ));
    }
    let head = git
        .head()
        .map_err(|e| invalid(format!("cannot read HEAD: {e}")))?;
    if head != wo.base_commit {
        return Err(invalid(format!(
            "HEAD is {head}, not base_commit {}",
            wo.base_commit
        )));
    }
    match git.is_clean() {
        Ok(true) => {}
        Ok(false) => {
            return Err(invalid(
                "the workspace has uncommitted or untracked changes".into(),
            ))
        }
        Err(e) => return Err(invalid(format!("cannot read the workspace status: {e}"))),
    }
    if !git.ref_format_ok(&wo.attempt_branch) {
        return Err(invalid(format!(
            "attempt_branch {:?} is not a valid branch name",
            wo.attempt_branch
        )));
    }
    if !git.ref_format_ok(&wo.tests_ref) {
        return Err(invalid(format!(
            "tests_ref {:?} is not a valid ref name",
            wo.tests_ref
        )));
    }

    // 8. The test command.
    let test_command = resolve_test_command(&wo, &ws).map_err(invalid)?;

    // 9. The inference policy.
    let choice = policy::choose(&wo.inference)
        .map_err(|e| fail(emitter, Outcome::Failed, Category::PolicyUnsatisfiable, e))?;

    // 10. Warn-only scan of the untrusted text.
    let mut texts: Vec<(String, &str)> = vec![
        ("story title".into(), wo.story.title.as_str()),
        ("story description".into(), wo.story.description.as_str()),
    ];
    for c in &wo.story.acceptance_criteria {
        texts.push((format!("criterion {}", c.id), c.text.as_str()));
    }
    for e in &wo.failure_evidence {
        texts.push((
            format!("failure evidence {}", e.attempt_id),
            e.summary.as_str(),
        ));
        texts.push((
            format!("failure evidence {}", e.attempt_id),
            e.detail.as_str(),
        ));
    }
    for (what, text) in texts {
        for pattern in dangerous_patterns(text) {
            log(
                emitter,
                LogStream::System,
                format!("warning: {what} contains a dangerous pattern: {pattern}"),
            );
        }
    }

    let agent = ClaudeCode::new(&wo, choice, env.claude_bin.clone(), &test_command);
    Ok(Driver {
        limits: Limits::new(&wo.limits, start),
        rules: PathRules::from_order(&wo),
        wo,
        emitter: emitter.clone(),
        env: env.clone(),
        git,
        ws,
        state_dir,
        test_command,
        agent,
        waiting,
        call_index: 0,
        next_call_seq: 1,
        red_sha: None,
        red_files: Vec::new(),
        tests_ref_sha: None,
        red_observed: None,
    })
}

// ---------------------------------------------------------------------------------------------
// The driver
// ---------------------------------------------------------------------------------------------

type Step<T = ()> = Result<T, ResultEvent>;

struct Driver {
    wo: WorkOrder,
    emitter: Emitter,
    env: Env,
    git: Git,
    limits: Limits,
    rules: PathRules,
    ws: PathBuf,
    state_dir: PathBuf,
    test_command: String,
    agent: ClaudeCode,
    waiting: Arc<Mutex<Option<WaitingOn>>>,
    /// Agent calls made so far; Red's are 1..=2 and Green continues the numbering.
    call_index: u32,
    next_call_seq: u64,
    red_sha: Option<String>,
    red_files: Vec<String>,
    tests_ref_sha: Option<String>,
    red_observed: Option<bool>,
}

impl Driver {
    fn drive(&mut self) -> ResultEvent {
        match self.stages() {
            Ok(r) | Err(r) => r,
        }
    }

    fn stages(&mut self) -> Step<ResultEvent> {
        self.provision()?;
        self.red()?;
        self.publish_red()?;
        Err(self.end(
            Outcome::Failed,
            Category::HarnessError,
            "green not implemented",
        ))
    }

    /// Emits the fatal `error` and builds the result, carrying what the run established.
    fn end(&self, outcome: Outcome, category: Category, detail: impl Into<String>) -> ResultEvent {
        let mut r = fail(&self.emitter, outcome, category, detail);
        r.tests_ref_sha = self.tests_ref_sha.clone();
        r.red_observed = self.red_observed;
        r
    }

    fn harness_error(&self, detail: impl Into<String>) -> ResultEvent {
        self.end(Outcome::Failed, Category::HarnessError, detail)
    }

    fn git_fail(&self, what: &str, e: GitError) -> ResultEvent {
        self.harness_error(format!("{what}: {e}"))
    }

    fn warn(&self, line: impl Into<String>) {
        log(&self.emitter, LogStream::System, line);
    }

    /// Checked before every stage, agent call, test run and push.
    fn gate(&self) -> Step {
        if proc::interrupted() {
            return Err(self.end(Outcome::Halted, Category::Interrupted, "interrupted"));
        }
        let why = if self.limits.remaining().is_none() {
            Some("the wall-clock limit was reached")
        } else if self.limits.turns_left() == 0 {
            Some("the turn limit was reached")
        } else if self.limits.tokens_exhausted() {
            Some("the token limit was reached")
        } else {
            None
        };
        match why {
            Some(why) => Err(self.end(Outcome::Halted, Category::LimitReached, why)),
            None => Ok(()),
        }
    }

    fn stage(&self, stage: Stage, what: &str) -> Step {
        self.gate()?;
        progress(&self.emitter, stage, what);
        Ok(())
    }

    /// One agent call, with its exit mapped to a result and its turns and tokens counted.
    fn agent_call(&mut self, prompt: &str) -> Step<CallOutcome> {
        self.gate()?;
        self.call_index += 1;
        let index = self.call_index;
        let max_turns = self.limits.turns_left();
        let called = {
            let _w = Waiting::on(&self.waiting, WaitingOn::Agent);
            self.agent.run(
                &self.ws,
                &self.state_dir,
                index,
                prompt,
                max_turns,
                self.next_call_seq,
                &self.limits,
                &self.emitter,
                self.env.grace,
            )
        };
        let out = called
            .map_err(|e| self.harness_error(format!("agent call {index} could not run: {e}")))?;
        self.next_call_seq = out.next_call_seq;
        match out.exit.ended_by {
            EndedBy::Deadline => {
                return Err(self.end(
                    Outcome::Halted,
                    Category::LimitReached,
                    format!("agent call {index} hit the wall-clock limit"),
                ))
            }
            EndedBy::TokenLimit => {
                return Err(self.end(
                    Outcome::Halted,
                    Category::LimitReached,
                    format!("agent call {index} hit the token limit"),
                ))
            }
            EndedBy::Interrupted => {
                return Err(self.end(
                    Outcome::Halted,
                    Category::Interrupted,
                    format!("agent call {index} was interrupted"),
                ))
            }
            EndedBy::Normal => {}
        }
        let final_result = out.final_result.as_ref();
        if final_result.is_some_and(|f| f.subtype == "error_max_turns") {
            return Err(self.end(
                Outcome::Halted,
                Category::LimitReached,
                format!("agent call {index} stopped at --max-turns {max_turns}"),
            ));
        }
        if out.exit.code != Some(0) {
            let code = out
                .exit
                .code
                .map_or_else(|| "no exit code".to_string(), |c| format!("exit {c}"));
            return Err(self.end(
                Outcome::Failed,
                Category::AgentError,
                format!("agent call {index} failed ({code}); see call-{index}.stderr.log"),
            ));
        }
        self.limits
            .spend_turns(final_result.and_then(|f| f.num_turns).unwrap_or(max_turns));
        if self.limits.tokens_exhausted() {
            return Err(self.end(
                Outcome::Halted,
                Category::LimitReached,
                format!("the token limit was reached after agent call {index}"),
            ));
        }
        Ok(out)
    }

    /// Runs the test command, announces its log, resets the tree, and maps a limit or an
    /// interrupt. The caller judges the exit code.
    fn run_tests(&self, label: &str) -> Step<TestRun> {
        self.gate()?;
        let log_path = self.state_dir.join(format!("test-{label}.log"));
        let ran = {
            let _w = Waiting::on(&self.waiting, WaitingOn::Tests);
            proc::run_tests(
                &self.test_command,
                &self.ws,
                &log_path,
                self.limits.deadline(),
                &|| self.limits.tokens_exhausted(),
                self.env.grace,
            )
        };
        let run =
            ran.map_err(|e| self.harness_error(format!("the test command could not run: {e}")))?;
        let lines: Vec<&str> = run.tail.lines().collect();
        let last = lines[lines.len().saturating_sub(TEST_LOG_LINES)..].join("\n");
        log(&self.emitter, LogStream::Test, last);
        let _ = self.emitter.emit(Event::Artifact {
            kind: ArtifactKind::LogFile,
            reference: log_path.display().to_string(),
            sha: None,
        });
        self.git
            .reset_clean()
            .map_err(|e| self.harness_error(format!("cannot reset after the tests: {e}")))?;
        match run.exit.ended_by {
            EndedBy::Normal => Ok(run),
            EndedBy::Deadline | EndedBy::TokenLimit => Err(self.end(
                Outcome::Halted,
                Category::LimitReached,
                format!("the {label} test run hit a limit"),
            )),
            EndedBy::Interrupted => Err(self.end(
                Outcome::Halted,
                Category::Interrupted,
                format!("the {label} test run was interrupted"),
            )),
        }
    }

    // --- provision -----------------------------------------------------------------------

    fn provision(&mut self) -> Step {
        self.stage(Stage::Provision, "preparing the attempt branch")?;
        let branch = self.wo.attempt_branch.clone();
        let base = self.wo.base_commit.clone();
        match self
            .git
            .branch_sha(&branch)
            .map_err(|e| self.git_fail("cannot look up the attempt branch", e))?
        {
            Some(sha) if sha != base => {
                return Err(self.end(
                    Outcome::Failed,
                    Category::BranchConflict,
                    format!("branch {branch} already exists at {sha}, not at base {base}"),
                ))
            }
            Some(_) => {
                let current = self
                    .git
                    .current_branch()
                    .map_err(|e| self.git_fail("cannot read the current branch", e))?;
                if current.as_deref() != Some(branch.as_str()) {
                    self.git
                        .switch(&branch)
                        .map_err(|e| self.git_fail("cannot switch to the attempt branch", e))?;
                }
            }
            None => self
                .git
                .switch_create(&branch, &base)
                .map_err(|e| self.git_fail("cannot create the attempt branch", e))?,
        }
        eprintln!("[reqdrive] provision: running the tests at base");
        let run = self.run_tests("base")?;
        if run.exit.code != Some(0) {
            let code = run
                .exit
                .code
                .map_or_else(|| "no exit code".to_string(), |c| format!("exit {c}"));
            return Err(self.end(
                Outcome::Failed,
                Category::BaseBroken,
                format!(
                    "the test command fails at base ({code}); see {}",
                    run.log.display()
                ),
            ));
        }
        Ok(())
    }

    // --- red -----------------------------------------------------------------------------

    fn red(&mut self) -> Step {
        self.stage(Stage::Red, "writing the failing tests")?;
        let ids: Vec<String> = self
            .wo
            .story
            .acceptance_criteria
            .iter()
            .map(|c| c.id.clone())
            .collect();
        let mut prev: Option<String> = None;
        for n in 1..=RED_ATTEMPTS {
            let last = n == RED_ATTEMPTS;
            eprintln!("[reqdrive] red: attempt {n}");
            let prompt = red_prompt(&self.wo, prev.as_deref());
            let out = self.agent_call(&prompt)?;
            let claims = out.final_result.as_ref().map(|f| read_claims(&f.text));

            // Checks 1 and 2, on the staged paths, before anything is committed.
            self.git
                .stage_all()
                .map_err(|e| self.git_fail("cannot stage the red change", e))?;
            let paths = self
                .git
                .staged_paths()
                .map_err(|e| self.git_fail("cannot list the staged paths", e))?;
            let denied = self.rules.denied_hits(&paths);
            if !denied.is_empty() {
                let patch_path = self
                    .state_dir
                    .join(format!("scope-violation-red-{n}.patch"));
                let saved = self
                    .git
                    .staged_patch()
                    .map_err(|e| self.git_fail("cannot save the staged patch", e))
                    .and_then(|p| {
                        fs::write(&patch_path, p).map_err(|e| {
                            self.harness_error(format!("cannot write the patch file: {e}"))
                        })
                    });
                self.git
                    .reset_clean()
                    .map_err(|e| self.git_fail("cannot reset the workspace", e))?;
                saved?;
                return Err(self.end(
                    Outcome::Failed,
                    Category::ScopeViolation,
                    format!(
                        "red attempt {n} changed denied paths: {}; patch saved to {}",
                        denied.join(", "),
                        patch_path.display()
                    ),
                ));
            }
            if paths.is_empty() {
                prev = Some("no files changed".into());
                self.warn(format!("red attempt {n}: no files changed"));
                continue;
            }
            let outside = self.rules.red_violations(&paths);
            if !outside.is_empty() {
                self.git
                    .reset_clean()
                    .map_err(|e| self.git_fail("cannot reset the workspace", e))?;
                let why = format!(
                    "changed files outside test_paths and frozen_paths: {}",
                    outside.join(", ")
                );
                self.warn(format!("red attempt {n}: {why}"));
                prev = Some(why);
                continue;
            }
            if self.rules.tests.is_empty() {
                self.warn(
                    "warning: test_paths is not set, so red's changed paths were not checked",
                );
            }

            // Check 3, on the commit's added lines.
            let message = format!(
                "test: [{}] failing tests for {}",
                self.wo.story.id,
                ids.join(", ")
            );
            let red_sha = self
                .git
                .commit(&message)
                .map_err(|e| self.git_fail("cannot commit the red change", e))?;
            let diff = self
                .git
                .diff_u0(&self.wo.base_commit, &red_sha)
                .map_err(|e| self.git_fail("cannot diff the red commit", e))?;
            let missing = missing_ids(&added_lines(&diff), &ids);
            if !missing.is_empty() {
                self.git
                    .reset_to(&self.wo.base_commit)
                    .map_err(|e| self.git_fail("cannot reset to base", e))?;
                let why = format!(
                    "these criterion ids appear in no added test line: {}",
                    missing.join(", ")
                );
                self.warn(format!("red attempt {n}: {why}"));
                prev = Some(why);
                continue;
            }

            // Check 4: the tests fail at the red commit.
            eprintln!("[reqdrive] red: running the tests at the red commit");
            let run = self.run_tests(&format!("red-{n}"))?;
            match run.exit.code {
                Some(c @ (126 | 127)) => {
                    return Err(self.harness_error(format!(
                        "the test command could not run at the red commit (exit {c}); see {}",
                        run.log.display()
                    )))
                }
                Some(0) => {
                    self.git
                        .reset_to(&self.wo.base_commit)
                        .map_err(|e| self.git_fail("cannot reset to base", e))?;
                    let why = "the new tests pass at the red commit; they must fail until the story is implemented";
                    if last {
                        self.red_observed = Some(false);
                        return Err(self.end(Outcome::NoChange, Category::RedNotFailing, why));
                    }
                    self.warn(format!("red attempt {n}: {why}"));
                    prev = Some(why.to_string());
                    continue;
                }
                _ => self.red_observed = Some(true),
            }

            if let Some(map) = claims.and_then(|c| c.criteria_map) {
                let map_path = self.state_dir.join("criteria-map.json");
                let text = serde_json::to_string_pretty(&map).unwrap_or_default();
                fs::write(&map_path, text).map_err(|e| {
                    self.harness_error(format!("cannot write criteria-map.json: {e}"))
                })?;
                let _ = self.emitter.emit(Event::Artifact {
                    kind: ArtifactKind::CriteriaMap,
                    reference: map_path.display().to_string(),
                    sha: None,
                });
            }
            self.red_files = self
                .git
                .changed_files(&self.wo.base_commit, &red_sha)
                .map_err(|e| self.git_fail("cannot list the red commit's files", e))?;
            self.red_sha = Some(red_sha);
            return Ok(());
        }
        Err(self.end(
            Outcome::Failed,
            Category::RedInvalid,
            format!(
                "red failed its checks after {RED_ATTEMPTS} attempts: {}",
                prev.unwrap_or_default()
            ),
        ))
    }

    // --- red_published -------------------------------------------------------------------

    fn publish_red(&mut self) -> Step {
        self.stage(Stage::RedPublished, "pushing the red commit")?;
        let Some(red_sha) = self.red_sha.clone() else {
            return Err(self.harness_error("no red commit to publish"));
        };
        let pushed = {
            let _w = Waiting::on(&self.waiting, WaitingOn::Push);
            self.git.push(
                &self.wo.repo.remote,
                &red_sha,
                &self.wo.tests_ref,
                self.limits.deadline(),
                self.env.grace,
            )
        };
        if let Err(e) = pushed {
            let (outcome, category) = if e.stderr.starts_with("interrupted") {
                (Outcome::Halted, Category::Interrupted)
            } else if e.stderr.starts_with("deadline") {
                (Outcome::Halted, Category::LimitReached)
            } else {
                (Outcome::Failed, Category::PushFailed)
            };
            return Err(self.end(outcome, category, format!("cannot push the tests ref: {e}")));
        }
        let _ = self.emitter.emit(Event::Artifact {
            kind: ArtifactKind::TestsRef,
            reference: self.wo.tests_ref.clone(),
            sha: Some(red_sha.clone()),
        });
        self.tests_ref_sha = Some(red_sha);
        Ok(())
    }
}
