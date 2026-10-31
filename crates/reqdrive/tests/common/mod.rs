//! Shared helpers for the `reqdrive story` integration tests: a temp repository with a bare
//! remote, a default work order, and a runner that drives the real binary with `fake-claude`.
#![allow(dead_code)]

use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use tempfile::TempDir;

pub const FAKE: &str = env!("CARGO_BIN_EXE_fake-claude");
pub const REQDRIVE: &str = env!("CARGO_BIN_EXE_reqdrive");

pub const BRANCH: &str = "attempt/S-1/a-1";
pub const TESTS_REF: &str = "refs/heads/attempt/S-1/a-1.tests";

/// Runs plain git (not the harness's wrapper) in `dir` and returns stdout. Panics on failure.
pub fn git(dir: &Path, args: &[&str]) -> String {
    let o = git_output(dir, args);
    assert!(
        o.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&o.stderr)
    );
    String::from_utf8_lossy(&o.stdout).trim().to_string()
}

fn git_output(dir: &Path, args: &[&str]) -> std::process::Output {
    Command::new("git")
        .arg("-C")
        .arg(dir)
        .args([
            "-c",
            "user.name=fixture",
            "-c",
            "user.email=fixture@localhost",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "core.autocrlf=false",
        ])
        .args(args)
        .stdin(Stdio::null())
        .output()
        .expect("run git")
}

pub struct Fixture {
    pub root: TempDir,
    pub remote: PathBuf,
    pub ws: PathBuf,
    pub base: String,
}

impl Fixture {
    /// A temp root whose path contains a space, a bare `remote.git`, and a clone `ws` with
    /// one commit holding `README.md` and an empty `test/.keep`.
    pub fn new() -> Fixture {
        let root = tempfile::Builder::new()
            .prefix("rd story ")
            .tempdir()
            .expect("temp dir");
        let remote = root.path().join("remote.git");
        let ws = root.path().join("ws");
        git(root.path(), &["init", "-q", "--bare", "remote.git"]);
        git(root.path(), &["clone", "-q", "remote.git", "ws"]);
        fs::write(ws.join("README.md"), "hello\n").unwrap();
        fs::create_dir_all(ws.join("test")).unwrap();
        fs::write(ws.join("test/.keep"), "").unwrap();
        git(&ws, &["add", "-A"]);
        git(&ws, &["commit", "-q", "-m", "init"]);
        git(&ws, &["push", "-q", "origin", "HEAD:refs/heads/main"]);
        let base = git(&ws, &["rev-parse", "HEAD"]);
        Fixture {
            root,
            remote,
            ws,
            base,
        }
    }

    /// Commits `content` at `rel` in the workspace and makes that commit the base.
    pub fn commit_file(&mut self, rel: &str, content: &str) {
        let path = self.ws.join(rel);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
        git(&self.ws, &["add", "-A"]);
        git(&self.ws, &["commit", "-q", "-m", &format!("add {rel}")]);
        self.base = git(&self.ws, &["rev-parse", "HEAD"]);
    }

    pub fn state_dir(&self) -> PathBuf {
        self.root.path().join("state")
    }

    pub fn harness_dir(&self) -> PathBuf {
        self.root.path().join("harness")
    }

    pub fn counter_path(&self) -> PathBuf {
        self.harness_dir().join("counter")
    }

    /// How many agent calls `fake-claude` saw (0 when the counter file was never written).
    pub fn calls(&self) -> u32 {
        fs::read_to_string(self.counter_path())
            .ok()
            .and_then(|s| s.trim().parse().ok())
            .unwrap_or(0)
    }

    /// The sha `refname` points at in the bare remote, if it exists.
    pub fn remote_ref(&self, refname: &str) -> Option<String> {
        let o = git_output(&self.remote, &["rev-parse", "--verify", "--quiet", refname]);
        o.status
            .success()
            .then(|| String::from_utf8_lossy(&o.stdout).trim().to_string())
    }

    /// The default work order: two criteria, the fake checker as the test command.
    pub fn order(&self) -> Value {
        json!({
            "schema": "story-work-order/0",
            "attempt_id": "a-1",
            "story": {
                "id": "S-1",
                "title": "Feature file",
                "description": "The feature file says done.",
                "acceptance_criteria": [
                    {"id": "AC-1", "text": "src/feature.txt exists"},
                    {"id": "AC-2", "text": "src/feature.txt says done"}
                ]
            },
            "workspace": self.ws,
            "state_dir": self.state_dir(),
            "repo": {"remote": "origin"},
            "base_commit": self.base,
            "attempt_branch": BRANCH,
            "tests_ref": TESTS_REF,
            "inference": {"allow": [{"provider": "anthropic", "models": ["claude-sonnet-5-5"]}]},
            "limits": {"turns": 50, "wall_clock_secs": 120, "tokens": 1000000},
            "test_command": format!("\"{FAKE}\" check-tests test"),
            "test_paths": ["test"]
        })
    }

    pub fn run(&self, order: &Value, script: &Value) -> (Vec<Value>, i32) {
        self.run_raw(&order.to_string(), script)
    }

    /// Writes the order text and the script under `root/harness/` (outside the workspace and
    /// the state dir), runs `reqdrive story <order>`, and parses its stdout lines.
    pub fn run_raw(&self, order_text: &str, script: &Value) -> (Vec<Value>, i32) {
        let h = self.harness_dir();
        fs::create_dir_all(&h).unwrap();
        let order_path = h.join("order.json");
        let script_path = h.join("script.json");
        fs::write(&order_path, order_text).unwrap();
        fs::write(&script_path, script.to_string()).unwrap();
        let out = Command::new(REQDRIVE)
            .arg("story")
            .arg(&order_path)
            .env("REQDRIVE_CLAUDE_BIN", FAKE)
            .env("FAKE_CLAUDE_SCRIPT", &script_path)
            .env("FAKE_CLAUDE_COUNTER", self.counter_path())
            .env("FAKE_CLAUDE_LOG", h.join("argv.log"))
            .env("REQDRIVE_HEARTBEAT_MS", "50")
            .env("REQDRIVE_GRACE_MS", "200")
            .stdin(Stdio::null())
            .output()
            .expect("run reqdrive");
        // Shown only when a test fails.
        eprintln!(
            "--- reqdrive stderr ---\n{}",
            String::from_utf8_lossy(&out.stderr)
        );
        let events = String::from_utf8_lossy(&out.stdout)
            .lines()
            .map(|l| serde_json::from_str(l).unwrap_or_else(|e| panic!("bad line {l:?}: {e}")))
            .collect();
        (events, out.status.code().unwrap_or(-1))
    }
}

/// The last event, which must be the result.
pub fn result(events: &[Value]) -> &Value {
    let last = events.last().expect("at least one event");
    assert_eq!(last["type"], "result", "last event: {last}");
    last
}

pub fn category(events: &[Value]) -> String {
    result(events)["failure"]["category"]
        .as_str()
        .unwrap_or("")
        .to_string()
}

pub fn script(calls: Vec<Value>) -> Value {
    json!({ "calls": calls })
}

/// A red call that names both criteria and expects a file green has not written yet.
pub fn red_ok() -> Value {
    json!({"writes": {"test/feature.test": "AC-1 AC-2\nexpect src/feature.txt done\n"}})
}

/// A green call that satisfies `red_ok`'s expectation.
pub fn green_ok() -> Value {
    json!({"writes": {"src/feature.txt": "done"}})
}
