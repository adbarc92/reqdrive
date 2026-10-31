//! `reqdrive story` from Green through Check and Deliver.

mod common;

use common::*;
use serde_json::{json, Value};
use std::fs;
use std::time::{Duration, Instant};

const BRANCH_REF: &str = "refs/heads/attempt/S-1/a-1";

fn defective_text() -> String {
    "The test is wrong.\n\n```json:iteration-summary\n\
     {\"testsDefective\": {\"test\": \"feature.test\", \"reason\": \"it expects the wrong word\"}}\n\
     ```\n"
        .to_string()
}

/// The commit subjects on `sha` since the base, newest first.
fn subjects(f: &Fixture, sha: &str) -> Vec<String> {
    git(
        &f.remote,
        &["log", "--format=%s", &format!("{}..{sha}", f.base)],
    )
    .lines()
    .map(str::to_string)
    .collect()
}

fn has_feat_on_remote(f: &Fixture) -> bool {
    match f.remote_ref(BRANCH_REF) {
        Some(sha) => subjects(f, &sha).iter().any(|s| s.starts_with("feat:")),
        None => false,
    }
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
            "deliver"
        ]
    );
    assert!(!events.iter().any(|e| e["type"] == "error"));
    assert_eq!(f.calls(), 2);
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
fn wall_clock_limit_halts() {
    let f = Fixture::new();
    let mut order = f.order();
    order["limits"]["wall_clock_secs"] = json!(2);
    let mut slow = green_ok();
    slow["sleep_ms"] = json!(5000);
    let started = Instant::now();
    let (events, code) = f.run(&order, &script(vec![red_ok(), slow]));
    let took = started.elapsed();
    assert_eq!(code, 0);
    let r = result(&events);
    assert_eq!(r["outcome"], "halted", "{r}");
    assert_eq!(r["failure"]["category"], "limit_reached");
    assert!(took < Duration::from_secs(4), "took {took:?}");
    assert!(!has_feat_on_remote(&f));
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
