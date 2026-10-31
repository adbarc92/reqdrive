//! `reqdrive story` from Green through Check and Deliver.

mod common;

use common::*;
use serde_json::{json, Value};
use std::fs;
use std::io::{BufRead, BufReader};
use std::process::Stdio;
use std::time::{Duration, Instant};

fn defective_text() -> String {
    "The test is wrong.\n\n```json:iteration-summary\n\
     {\"testsDefective\": {\"test\": \"feature.test\", \"reason\": \"it expects the wrong word\"}}\n\
     ```\n"
        .to_string()
}

fn logs(events: &[Value]) -> Vec<String> {
    events
        .iter()
        .filter(|e| e["type"] == "log")
        .map(|e| e["line"].as_str().unwrap_or("").to_string())
        .collect()
}

#[test]
fn happy_path_pushes_branch() {
    let f = Fixture::new();
    let (events, code) = f.run(&f.order(), &script(vec![red_ok(), green_ok()]));
    assert_eq!(code, 0);
    let r = result(&events);
    assert_eq!(r["outcome"], "pushed", "{r}");
    assert!(r["failure"].is_null());
    let head = r["head_sha"].as_str().expect("head_sha");
    assert_eq!(f.remote_ref(BRANCH_REF).as_deref(), Some(head));
    let subs = subjects(&f, head);
    assert_eq!(subs.len(), 2, "{subs:?}");
    assert!(subs[0].starts_with("feat: [S-1] green 1"), "{subs:?}");
    assert!(subs[1].starts_with("test: [S-1]"), "{subs:?}");
    assert_eq!(
        r["tests_ref_sha"],
        f.remote_ref(TESTS_REF).unwrap().as_str()
    );
    assert_eq!(r["red_observed"], true);
    assert_eq!(r["tests_defective"], false);
    assert_eq!(r["evidence"]["exit_code"], 0);
    assert_eq!(
        r["evidence"]["test_command"],
        f.order()["test_command"].as_str().unwrap()
    );
    assert!(events.iter().any(|e| e["type"] == "artifact"
        && e["kind"] == "branch"
        && e["ref"] == BRANCH
        && e["sha"] == head));
    let usage: Vec<&Value> = events.iter().filter(|e| e["type"] == "usage").collect();
    assert!(!usage.is_empty());
    for u in usage {
        assert!(u["thinking"].is_null(), "{u}");
    }
    let stages: Vec<&str> = events
        .iter()
        .filter(|e| e["type"] == "progress")
        .map(|e| e["stage"].as_str().unwrap())
        .collect();
    assert_eq!(
        stages,
        [
            "validate",
            "provision",
            "red",
            "red_published",
            "green",
            "check",
            "deliver",
            "done"
        ]
    );
    let before_last = &events[events.len() - 2];
    assert_eq!(before_last["type"], "progress", "{before_last}");
    assert_eq!(before_last["stage"], "done", "{before_last}");
    assert!(!events.iter().any(|e| e["type"] == "error"));
    assert_eq!(f.calls(), 2);
}

#[test]
fn red_agent_committing_workflow_itself_is_scope_violation() {
    let f = Fixture::new();
    let sneaky = json!({
        "writes": {
            "test/feature.test": "AC-1 AC-2\nexpect src/feature.txt done\n",
            ".github/workflows/x.yml": "on: push\n"
        },
        "git_commit_all": "tests"
    });
    let (events, _) = f.run(&f.order(), &script(vec![sneaky, green_ok()]));
    let r = result(&events);
    assert_eq!(r["failure"]["category"], "scope_violation", "{r}");
    let detail = r["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("the agent ran git"), "{detail}");
    assert!(f.state_dir().join("agent-moved-head-red-1.patch").exists());
    assert!(f.remote_ref(TESTS_REF).is_none());
    assert!(f.remote_ref(BRANCH_REF).is_none());
    assert_eq!(f.calls(), 1);
    assert_eq!(git(&f.ws, &["rev-parse", "HEAD"]), f.base, "HEAD was reset");
    assert!(!f.ws.join(".github").exists());
}

#[test]
fn green_agent_committing_frozen_test_itself_is_scope_violation() {
    let f = Fixture::new();
    let sneaky = json!({
        "writes": {
            "test/feature.test": "AC-1 AC-2\n",
            "src/feature.txt": "done"
        },
        "git_commit_all": "cheat"
    });
    let (events, _) = f.run(&f.order(), &script(vec![red_ok(), sneaky]));
    let r = result(&events);
    assert_eq!(r["failure"]["category"], "scope_violation", "{r}");
    let detail = r["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("the agent ran git"), "{detail}");
    assert!(f
        .state_dir()
        .join("agent-moved-head-green-1.patch")
        .exists());
    let tests_sha = f.remote_ref(TESTS_REF).expect("red was published");
    // The evidence push may carry the red commit, never the agent's own commit.
    if let Some(sha) = f.remote_ref(BRANCH_REF) {
        assert_eq!(sha, tests_sha);
    }
    assert_eq!(
        git(&f.ws, &["rev-parse", "HEAD"]),
        tests_sha,
        "HEAD was reset"
    );
}

#[test]
fn green_editing_frozen_test_is_tests_modified() {
    let f = Fixture::new();
    let cheat = json!({"writes": {
        "test/feature.test": "AC-1 AC-2\n",
        "src/feature.txt": "done"
    }});
    let (events, _) = f.run(&f.order(), &script(vec![red_ok(), cheat]));
    assert_eq!(category(&events), "tests_modified");
    assert_eq!(result(&events)["outcome"], "failed");
    let detail = result(&events)["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("test/feature.test"), "{detail}");
    assert!(f.state_dir().join("tests-modified-green-1.patch").exists());
    assert!(!has_feat_on_remote(&f));
    assert!(
        !f.ws.join("src/feature.txt").exists(),
        "the workspace was reset"
    );
}

#[test]
fn green_editing_frozen_path_is_tests_modified() {
    let mut f = Fixture::new();
    f.commit_file("package.json", "{}\n");
    let mut order = f.order();
    order["frozen_paths"] = json!(["package.json"]);
    let cheat = json!({"writes": {
        "package.json": "{\"scripts\":{}}\n",
        "src/feature.txt": "done"
    }});
    let (events, _) = f.run(&order, &script(vec![red_ok(), cheat]));
    assert_eq!(category(&events), "tests_modified");
    let detail = result(&events)["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("package.json"), "{detail}");
    assert!(!has_feat_on_remote(&f));
}

#[test]
fn green_touching_denied_path_is_scope_violation() {
    let f = Fixture::new();
    let bad = json!({"writes": {
        ".claude/settings.json": "{}",
        "src/feature.txt": "done"
    }});
    let (events, _) = f.run(&f.order(), &script(vec![red_ok(), bad]));
    assert_eq!(category(&events), "scope_violation");
    assert!(f.state_dir().join("scope-violation-green-1.patch").exists());
    assert!(!f.ws.join(".claude").exists(), "the workspace was reset");
    assert!(!has_feat_on_remote(&f));
}

#[test]
fn green_tests_defective_claim_stops() {
    let f = Fixture::new();
    let claim = json!({"text": defective_text()});
    let (events, _) = f.run(&f.order(), &script(vec![red_ok(), claim, green_ok()]));
    let r = result(&events);
    assert_eq!(r["outcome"], "failed");
    assert_eq!(r["tests_defective"], true);
    assert_eq!(r["failure"]["category"], "tests_defective");
    assert_eq!(r["failure"]["retryable"], false);
    let detail = r["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("feature.test"), "{detail}");
    assert!(detail.contains("it expects the wrong word"), "{detail}");
    assert_eq!(f.calls(), 2, "green stops at the claim");
}

#[test]
fn green_defective_claim_ignored_when_tests_pass() {
    let f = Fixture::new();
    let mut green = green_ok();
    green["text"] = json!(defective_text());
    let (events, _) = f.run(&f.order(), &script(vec![red_ok(), green]));
    let r = result(&events);
    assert_eq!(r["outcome"], "pushed", "{r}");
    assert_eq!(r["tests_defective"], false);
    assert!(
        logs(&events)
            .iter()
            .any(|l| l.contains("testsDefective") && l.contains("it expects the wrong word")),
        "{:?}",
        logs(&events)
    );
}

#[test]
fn green_exhausts_calls_is_tests_failed_and_branch_pushed_as_evidence() {
    let f = Fixture::new();
    let mut order = f.order();
    order["green_max_calls"] = json!(2);
    let wrong1 = json!({"writes": {"src/feature.txt": "nope"}});
    let wrong2 = json!({"writes": {"src/feature.txt": "still nope"}});
    let (events, _) = f.run(&order, &script(vec![red_ok(), wrong1, wrong2, green_ok()]));
    let r = result(&events);
    assert_eq!(r["outcome"], "failed");
    assert_eq!(r["failure"]["category"], "tests_failed");
    assert_eq!(f.calls(), 3);
    let head = r["head_sha"]
        .as_str()
        .expect("head_sha set by the evidence push");
    assert_eq!(f.remote_ref(BRANCH_REF).as_deref(), Some(head));
    let subs = subjects(&f, head);
    assert_eq!(subs.len(), 3, "{subs:?}");
    assert!(subs[0].starts_with("feat: [S-1] green 2"), "{subs:?}");
    assert!(subs[1].starts_with("feat: [S-1] green 1"), "{subs:?}");
    assert!(logs(&events).iter().any(|l| l.contains("evidence")));
    let prompt = fs::read_to_string(f.state_dir().join("call-3.prompt.md")).unwrap();
    assert!(
        prompt.contains("FAIL"),
        "the last test tail reaches the prompt"
    );
    assert!(prompt.contains("## Last test run (tail)"), "{prompt}");
    assert!(prompt.contains("call 1: tests failed"), "{prompt}");
}

#[test]
fn green_empty_call_does_not_rerun_tests() {
    let f = Fixture::new();
    let (events, _) = f.run(&f.order(), &script(vec![red_ok(), json!({}), green_ok()]));
    let r = result(&events);
    assert_eq!(r["outcome"], "pushed", "{r}");
    assert_eq!(f.calls(), 3);
    assert!(!f.state_dir().join("test-green-1.log").exists());
    assert!(f.state_dir().join("test-green-2.log").exists());
    let prompt = fs::read_to_string(f.state_dir().join("call-3.prompt.md")).unwrap();
    assert!(prompt.contains("call 1: no change"), "{prompt}");
    let subs = subjects(&f, r["head_sha"].as_str().unwrap());
    assert!(subs[0].starts_with("feat: [S-1] green 2"), "{subs:?}");
}

#[test]
fn token_limit_halts() {
    let f = Fixture::new();
    let mut order = f.order();
    order["limits"]["tokens"] = json!(30);
    let (events, _) = f.run(&order, &script(vec![red_ok(), green_ok()]));
    let r = result(&events);
    assert_eq!(r["outcome"], "halted", "{r}");
    assert_eq!(r["failure"]["category"], "limit_reached");
    assert!(f.remote_ref(TESTS_REF).is_some(), "red was published");
    assert!(!has_feat_on_remote(&f));
    let head = r["head_sha"]
        .as_str()
        .expect("the evidence push set head_sha");
    assert_eq!(f.remote_ref(BRANCH_REF).as_deref(), Some(head));
}

#[test]
fn heartbeat_emitted_while_agent_sleeps() {
    let f = Fixture::new();
    let mut slow = green_ok();
    slow["sleep_ms"] = json!(300);
    let (events, _) = f.run(&f.order(), &script(vec![red_ok(), slow]));
    assert_eq!(result(&events)["outcome"], "pushed");
    assert!(events
        .iter()
        .any(|e| e["type"] == "heartbeat" && e["waiting_on"] == "agent"));
}

#[test]
fn orphan_holding_agent_stdout_does_not_hang_the_run() {
    let f = Fixture::new();
    // The red call exits but leaves a process holding its stdout open for 30 s.
    let mut red = red_ok();
    red["orphan_sleep_ms"] = json!(30_000);
    let running = f.spawn(&f.order(), &script(vec![red, green_ok()]));
    let (events, code, took) = running.wait(Duration::from_secs(20));
    assert_eq!(code, 0);
    // The reader is waited for max(grace, 1 s) after the agent exits.
    assert!(took < Duration::from_secs(12), "took {took:?}");
    let r = result(&events);
    assert_eq!(r["outcome"], "pushed", "{r}");
    assert!(
        events.iter().any(|e| e["type"] == "error"
            && e["category"] == "usage_incomplete"
            && e["detail"]
                .as_str()
                .unwrap_or("")
                .contains("agent stdout still open after exit")),
        "{events:?}"
    );
}

#[test]
fn closed_stdout_halts_the_run_and_keeps_the_logs() {
    let f = Fixture::new();
    // Red sleeps, so the run is waiting on the agent when the reader goes away.
    let mut slow = red_ok();
    slow["sleep_ms"] = json!(5_000);
    let mut cmd = f.command(&f.order().to_string(), &script(vec![slow, green_ok()]));
    cmd.stdout(Stdio::piped()).stderr(Stdio::null());
    let started = Instant::now();
    let mut child = cmd.spawn().expect("spawn reqdrive");
    let mut out = BufReader::new(child.stdout.take().unwrap());
    let mut first = String::new();
    out.read_line(&mut first).unwrap();
    drop(out);
    let status = loop {
        if let Some(s) = child.try_wait().unwrap() {
            break s;
        }
        if started.elapsed() > Duration::from_secs(20) {
            let _ = child.kill();
            panic!("reqdrive did not exit within 20 s of losing its stdout");
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    assert_eq!(status.code(), Some(1), "the result could not be shown");
    assert!(f.calls() <= 1, "no green call after the reader went away");

    let state = f.state_dir();
    let r: Value =
        serde_json::from_str(&fs::read_to_string(state.join("result.json")).unwrap()).unwrap();
    assert_eq!(r["outcome"], "halted", "{r}");
    assert_eq!(r["failure"]["category"], "interrupted", "{r}");
    let log: Vec<Value> = fs::read_to_string(state.join("events.jsonl"))
        .unwrap()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    let seqs: Vec<u64> = log.iter().map(|e| e["seq"].as_u64().unwrap()).collect();
    assert_eq!(
        seqs,
        (1..=log.len() as u64).collect::<Vec<_>>(),
        "complete from seq 1"
    );
    assert_eq!(log.last().unwrap()["type"], "result");
    assert!(f.remote_ref(BRANCH_REF).is_none());
}

const SNEAKY: &str =
    "git -c user.name=t -c user.email=t@x -c commit.gpgsign=false commit --allow-empty -qm sneaky";

#[test]
fn test_command_that_commits_is_scope_violation_and_nothing_is_pushed() {
    let f = Fixture::new();
    let mut order = f.order();
    order["test_command"] = json!(format!("\"{FAKE}\" check-tests test && {SNEAKY}"));
    let (events, code) = f.run(&order, &script(vec![red_ok(), green_ok()]));
    assert_eq!(code, 0);
    let r = result(&events);
    assert_eq!(r["outcome"], "failed", "{r}");
    assert_eq!(category(&events), "scope_violation");
    let detail = r["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("the test command ran git"), "{detail}");
    assert!(f.state_dir().join("test-moved-head-base.patch").exists());
    assert_eq!(f.calls(), 0, "caught at the base, before any agent call");
    assert!(f.remote_ref(BRANCH_REF).is_none());
    assert!(f.remote_ref(TESTS_REF).is_none());
    assert_eq!(
        git(&f.ws, &["rev-parse", "HEAD"]),
        f.base,
        "reset to the base"
    );
}

#[test]
fn test_command_commit_after_green_is_never_pushed() {
    let f = Fixture::new();
    let mut order = f.order();
    // Commits only once green has written src/feature.txt, so red and the base run pass.
    #[cfg(windows)]
    let cmd = format!("\"{FAKE}\" check-tests test && if exist src\\feature.txt {SNEAKY}");
    #[cfg(not(windows))]
    let cmd =
        format!("\"{FAKE}\" check-tests test && if [ -f src/feature.txt ]; then {SNEAKY}; fi");
    order["test_command"] = json!(cmd);
    let (events, code) = f.run(&order, &script(vec![red_ok(), green_ok()]));
    assert_eq!(code, 0);
    let r = result(&events);
    assert_eq!(category(&events), "scope_violation", "{r}");
    assert!(f.state_dir().join("test-moved-head-green-1.patch").exists());
    if let Some(sha) = f.remote_ref(BRANCH_REF) {
        let subjects = subjects(&f, &sha);
        assert!(!subjects.iter().any(|s| s == "sneaky"), "{subjects:?}");
    }
    let head = git(&f.ws, &["log", "-1", "--format=%s"]);
    assert_ne!(head, "sneaky");
}

#[test]
fn turns_spent_by_the_last_call_do_not_stop_tests_or_delivery() {
    let f = Fixture::new();
    let mut order = f.order();
    order["limits"]["turns"] = json!(2);
    // Red and green take one turn each, leaving none for the test runs and pushes after.
    let (events, code) = f.run(&order, &script(vec![red_ok(), green_ok()]));
    assert_eq!(code, 0);
    let r = result(&events);
    assert_eq!(r["outcome"], "pushed", "{r}");
}

#[test]
fn result_without_num_turns_spends_one_turn() {
    let f = Fixture::new();
    let mut order = f.order();
    order["limits"]["turns"] = json!(2);
    let mut red = red_ok();
    red["lines"] = json!([r#"{"type":"result","subtype":"success","is_error":false,"result":""}"#]);
    let (events, code) = f.run(&order, &script(vec![red, green_ok()]));
    assert_eq!(code, 0);
    let r = result(&events);
    assert_eq!(r["outcome"], "pushed", "{r}");
    assert!(
        events
            .iter()
            .any(|e| e["type"] == "log" && e["line"].as_str().unwrap_or("").contains("num_turns")),
        "{events:?}"
    );
}
