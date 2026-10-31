use reqdrive::agent::ClaudeCode;
use reqdrive::events::Emitter;
use reqdrive::limits::Limits;
use reqdrive::policy::Choice;
use reqdrive::proc::EndedBy;
use reqdrive::workorder::{parse, LimitsSpec};
use serde_json::{json, Value};
use std::fs;
use std::io::{self, Write};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const FAKE: &str = env!("CARGO_BIN_EXE_fake-claude");

#[derive(Clone, Default)]
struct Buf(Arc<Mutex<Vec<u8>>>);

impl Write for Buf {
    fn write(&mut self, b: &[u8]) -> io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(b);
        Ok(b.len())
    }
    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

impl Buf {
    fn events(&self) -> Vec<Value> {
        String::from_utf8_lossy(&self.0.lock().unwrap())
            .lines()
            .map(|l| serde_json::from_str(l).unwrap())
            .collect()
    }
}

fn adapter(dir: &Path, script: Value) -> ClaudeCode {
    let wo = parse(
        r#"{"schema":"story-work-order/0","attempt_id":"a","story":{"id":"s","title":"t","description":"d",
        "acceptance_criteria":[{"id":"c1","text":"x"}]},"workspace":"w","state_dir":"s",
        "repo":{"remote":"r"},"base_commit":"b","attempt_branch":"br","tests_ref":"t",
        "inference":{"allow":[{"provider":"anthropic","models":["sonnet"]}]},
        "limits":{"turns":10,"wall_clock_secs":60,"tokens":1000}}"#,
    )
    .unwrap();
    let choice = Choice {
        provider_label: "anthropic".into(),
        model: "sonnet".into(),
        set_env: vec![],
        remove_env: vec![],
    };
    let script_path = dir.join("script.json");
    fs::write(&script_path, script.to_string()).unwrap();
    let mut cc = ClaudeCode::new(&wo, choice, FAKE.into(), "npm test");
    cc.extra_env = vec![
        (
            "FAKE_CLAUDE_SCRIPT".into(),
            script_path.to_string_lossy().into_owned(),
        ),
        (
            "FAKE_CLAUDE_COUNTER".into(),
            dir.join("counter").to_string_lossy().into_owned(),
        ),
        (
            "FAKE_CLAUDE_LOG".into(),
            dir.join("argv.log").to_string_lossy().into_owned(),
        ),
    ];
    cc
}

fn limits() -> Arc<Limits> {
    Arc::new(Limits::new(
        &LimitsSpec {
            turns: 10,
            wall_clock_secs: 60,
            tokens: 1000,
        },
        Instant::now(),
    ))
}

struct Ran {
    events: Vec<Value>,
    limits: Arc<Limits>,
    outcome: reqdrive::agent::CallOutcome,
}

fn run(dir: &Path, script: Value, max_turns: u32) -> Ran {
    let cc = adapter(dir, script);
    let buf = Buf::default();
    let emitter = Emitter::new(Box::new(buf.clone()));
    let limits = limits();
    // A directory with a space, like many Windows workspaces.
    let ws = dir.join("work space");
    fs::create_dir_all(&ws).unwrap();
    let outcome = cc
        .run(
            &ws,
            dir,
            1,
            "do the thing",
            max_turns,
            1,
            &limits,
            &emitter,
            Duration::from_millis(200),
        )
        .unwrap();
    Ran {
        events: buf.events(),
        limits,
        outcome,
    }
}

#[test]
fn run_emits_usage_rows_and_counts_tokens() {
    let dir = tempfile::tempdir().unwrap();
    let r = run(dir.path(), json!({"calls":[{}]}), 5);
    let usage: Vec<_> = r.events.iter().filter(|e| e["type"] == "usage").collect();
    assert_eq!(usage.len(), 1, "{:?}", r.events);
    assert_eq!(r.limits.tokens_used(), 22);
    assert_eq!(r.outcome.exit.ended_by, EndedBy::Normal);
    assert!(r.outcome.final_result.is_some());
    assert_eq!(r.outcome.next_call_seq, 2);
    assert!(!r.events.iter().any(|e| e["type"] == "error"));
    let transcript = fs::read_to_string(dir.path().join("call-1.jsonl")).unwrap();
    assert!(transcript.contains("message_start"));
    assert_eq!(
        fs::read_to_string(dir.path().join("call-1.prompt.md")).unwrap(),
        "do the thing"
    );
}

#[test]
fn run_without_result_emits_usage_incomplete() {
    let dir = tempfile::tempdir().unwrap();
    let r = run(
        dir.path(),
        json!({"calls":[{"lines":["not json at all"]}]}),
        5,
    );
    assert!(r.outcome.final_result.is_none());
    let err: Vec<_> = r.events.iter().filter(|e| e["type"] == "error").collect();
    assert_eq!(err.len(), 1, "{:?}", r.events);
    assert_eq!(err[0]["category"], "usage_incomplete");
}

#[test]
fn run_passes_args() {
    let dir = tempfile::tempdir().unwrap();
    run(dir.path(), json!({"calls":[{}]}), 7);
    let log = fs::read_to_string(dir.path().join("argv.log")).unwrap();
    let argv: Vec<String> = serde_json::from_str(log.lines().next().unwrap()).unwrap();
    assert!(
        argv.windows(2).any(|w| w == ["--max-turns", "7"]),
        "{argv:?}"
    );
    assert!(log.contains("--max-turns") && log.contains('7'));
}
