//! `reqdrive story` from validation through publishing the red commit.

mod common;

use common::*;
use serde_json::json;
use std::fs;
use std::process::Command;

#[test]
fn unparsable_order_gives_work_order_invalid_with_null_attempt() {
    let f = Fixture::new();
    let (events, code) = f.run_raw("{ not json", &script(vec![]));
    assert_eq!(code, 0);
    let r = result(&events);
    assert_eq!(r["outcome"], "failed");
    assert_eq!(r["failure"]["category"], "work_order_invalid");
    assert_eq!(r["failure"]["retryable"], false);
    assert!(r["attempt_id"].is_null(), "{r}");
    assert_eq!(f.calls(), 0);
    let done: Vec<&serde_json::Value> = events
        .iter()
        .filter(|e| e["type"] == "progress" && e["stage"] == "done")
        .collect();
    assert_eq!(done.len(), 1, "done is emitted once on a failure path too");
    assert_eq!(events[events.len() - 2]["stage"], "done");
}

#[test]
fn container_isolation_needs_a_detected_container() {
    let f = Fixture::new();
    let mut order = f.order();
    order["isolation"] = json!("container");
    let (events, code) = f.run(&order, &script(vec![red_ok(), green_ok()]));
    assert_eq!(code, 0);
    // The harness inherits this process's environment and filesystem, so the same detection
    // decides what it must do. Off Linux, and on a CI VM, nothing is detected.
    match reqdrive::workorder::detect_container() {
        None => {
            assert_eq!(category(&events), "work_order_invalid");
            let r = result(&events);
            assert_eq!(r["attempt_id"], "a-1");
            let detail = r["failure"]["detail"].as_str().unwrap();
            assert!(detail.contains("no container was detected"), "{detail}");
            assert_eq!(f.calls(), 0);
            assert!(!f.counter_path().exists(), "the agent must never be called");
            assert!(
                !f.state_dir().exists(),
                "refused before anything is provisioned"
            );
        }
        Some(found) => {
            assert_ne!(category(&events), "work_order_invalid");
            let line = format!("container detected: {found}");
            assert!(
                events
                    .iter()
                    .any(|e| e["type"] == "log" && e["line"] == line.as_str()),
                "expected a log event {line:?}"
            );
        }
    }
}

#[test]
fn dirty_workspace_is_rejected() {
    let f = Fixture::new();
    fs::write(f.ws.join("stray.txt"), "x").unwrap();
    let (events, code) = f.run(&f.order(), &script(vec![red_ok()]));
    assert_eq!(code, 0);
    assert_eq!(category(&events), "work_order_invalid");
    assert_eq!(result(&events)["attempt_id"], "a-1");
    let detail = result(&events)["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("uncommitted"), "{detail}");
    assert_eq!(f.calls(), 0);
}

#[test]
fn local_only_policy_is_refused_before_any_agent_call() {
    let f = Fixture::new();
    let mut order = f.order();
    order["inference"] = json!({"allow": [{"provider": "ollama", "models": ["qwen3-coder"]}]});
    let (events, _) = f.run(&order, &script(vec![red_ok()]));
    assert_eq!(category(&events), "policy_unsatisfiable");
    assert!(!f.counter_path().exists(), "the agent must never be called");
}

#[test]
fn existing_branch_elsewhere_is_branch_conflict() {
    let f = Fixture::new();
    let other = git(
        &f.ws,
        &["commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "other"],
    );
    git(&f.ws, &["branch", BRANCH, &other]);
    let (events, _) = f.run(&f.order(), &script(vec![red_ok()]));
    assert_eq!(category(&events), "branch_conflict");
    assert_eq!(result(&events)["outcome"], "failed");
    assert_eq!(f.calls(), 0);
}

#[test]
fn base_broken_when_tests_fail_at_base() {
    let mut f = Fixture::new();
    f.commit_file("test/base.test", "expect README.md not-there\n");
    let (events, _) = f.run(&f.order(), &script(vec![red_ok()]));
    assert_eq!(category(&events), "base_broken");
    assert_eq!(f.calls(), 0);
    assert!(
        events
            .iter()
            .any(|e| e["type"] == "artifact" && e["kind"] == "log_file"),
        "the base test log is announced"
    );
}

#[test]
fn red_publishes_tests_ref() {
    let f = Fixture::new();
    let (events, code) = f.run(&f.order(), &script(vec![red_ok(), green_ok()]));
    assert_eq!(code, 0);
    let r = result(&events);
    let tests_sha = f.remote_ref(TESTS_REF).expect("tests ref pushed");
    assert_eq!(r["tests_ref_sha"], tests_sha.as_str());
    assert_eq!(r["red_observed"], true);
    let subject = git(&f.remote, &["log", "-1", "--format=%s", &tests_sha]);
    assert!(subject.starts_with("test: [S-1]"), "{subject}");
    let parent = git(&f.remote, &["rev-parse", &format!("{tests_sha}^")]);
    assert_eq!(parent, f.base);
    assert!(events
        .iter()
        .any(|e| e["type"] == "progress" && e["stage"] == "red_published"));
    assert!(events.iter().any(|e| e["type"] == "artifact"
        && e["kind"] == "tests_ref"
        && e["sha"] == tests_sha.as_str()));
    assert_eq!(f.calls(), 2);
}

#[test]
fn red_missing_criterion_retries_then_red_invalid() {
    let f = Fixture::new();
    let only_ac1 = json!({"writes": {"test/feature.test": "AC-1\nexpect src/feature.txt done\n"}});
    let (events, _) = f.run(&f.order(), &script(vec![only_ac1.clone(), only_ac1]));
    assert_eq!(category(&events), "red_invalid");
    assert_eq!(f.calls(), 2);
    assert!(f.remote_ref(TESTS_REF).is_none());
}

#[test]
fn red_not_failing_gives_no_change() {
    let f = Fixture::new();
    let passing = json!({"writes": {"test/feature.test": "AC-1 AC-2\nexpect README.md hello\n"}});
    let (events, _) = f.run(&f.order(), &script(vec![passing.clone(), passing]));
    let r = result(&events);
    assert_eq!(r["outcome"], "no_change");
    assert_eq!(r["failure"]["category"], "red_not_failing");
    assert_eq!(f.calls(), 2);
    assert!(f.remote_ref(TESTS_REF).is_none());
}

#[test]
fn red_touching_workflow_is_scope_violation_and_never_pushed() {
    let f = Fixture::new();
    let bad = json!({"writes": {
        "test/feature.test": "AC-1 AC-2\nexpect src/feature.txt done\n",
        ".github/workflows/x.yml": "on: push\n"
    }});
    let (events, _) = f.run(&f.order(), &script(vec![bad]));
    assert_eq!(category(&events), "scope_violation");
    assert_eq!(f.calls(), 1, "a scope violation is never retried");
    assert!(f.remote_ref(&format!("refs/heads/{BRANCH}")).is_none());
    assert!(f.remote_ref(TESTS_REF).is_none());
    assert!(f.state_dir().join("scope-violation-red-1.patch").exists());
    assert!(!f.ws.join(".github").exists(), "the workspace was reset");
}

#[test]
fn unwritable_patch_keeps_scope_violation_with_one_error() {
    let f = Fixture::new();
    // A directory where the patch file would go (`state` is the workspace's sibling).
    let bad = json!({"writes": {
        "test/feature.test": "AC-1 AC-2\nexpect src/feature.txt done\n",
        ".github/workflows/x.yml": "on: push\n",
        "../state/scope-violation-red-1.patch/blocker": ""
    }});
    let (events, _) = f.run(&f.order(), &script(vec![bad]));
    assert_eq!(category(&events), "scope_violation");
    let detail = result(&events)["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("could not be written"), "{detail}");
    let errors = events.iter().filter(|e| e["type"] == "error").count();
    assert_eq!(errors, 1, "{events:?}");
    assert!(!f.ws.join(".github").exists(), "the workspace was reset");
}

#[test]
fn comma_in_test_command_is_work_order_invalid() {
    let f = Fixture::new();
    let mut order = f.order();
    order["test_command"] = json!(format!("\"{FAKE}\" check-tests test,other"));
    let (events, code) = f.run(&order, &script(vec![red_ok()]));
    assert_eq!(code, 0);
    assert_eq!(category(&events), "work_order_invalid");
    let detail = result(&events)["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("test_command"), "{detail}");
    assert_eq!(f.calls(), 0);
}

#[cfg(unix)]
#[test]
fn red_test_run_killed_by_a_signal_is_harness_error() {
    let f = Fixture::new();
    let mut order = f.order();
    // Passes at the base; at the red commit the checker fails and the shell kills itself.
    order["test_command"] = json!(format!("\"{FAKE}\" check-tests test || kill -9 $$"));
    let (events, code) = f.run(&order, &script(vec![red_ok()]));
    assert_eq!(code, 0);
    assert_eq!(category(&events), "harness_error");
    let r = result(&events);
    assert!(r["red_observed"].is_null(), "{r}");
    assert!(f.remote_ref(TESTS_REF).is_none());
}

#[test]
fn agent_exit_1_is_agent_error() {
    let f = Fixture::new();
    let (events, _) = f.run(&f.order(), &script(vec![json!({"exit": 1})]));
    assert_eq!(category(&events), "agent_error");
    assert_eq!(result(&events)["failure"]["retryable"], true);
}

#[test]
fn events_have_consecutive_seq_and_result_last() {
    let f = Fixture::new();
    let (events, _) = f.run(&f.order(), &script(vec![red_ok(), green_ok()]));
    let seqs: Vec<u64> = events.iter().map(|e| e["seq"].as_u64().unwrap()).collect();
    assert_eq!(seqs, (1..=events.len() as u64).collect::<Vec<_>>());
    let results = events.iter().filter(|e| e["type"] == "result").count();
    assert_eq!(results, 1);
    result(&events);
    for e in &events {
        assert_eq!(e["v"], 1);
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
    let durable = fs::read_to_string(f.state_dir().join("events.jsonl")).unwrap();
    assert!(durable
        .lines()
        .last()
        .unwrap()
        .contains("\"type\":\"result\""));
    assert!(f.state_dir().join("result.json").exists());
}

#[test]
fn state_dir_not_empty_is_rejected() {
    let f = Fixture::new();
    fs::create_dir_all(f.state_dir()).unwrap();
    fs::write(f.state_dir().join("old.txt"), "x").unwrap();
    let (events, _) = f.run(&f.order(), &script(vec![red_ok()]));
    assert_eq!(category(&events), "work_order_invalid");
    let detail = result(&events)["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("not empty"), "{detail}");
    assert_eq!(f.calls(), 0);
}

#[test]
fn cli_version_and_usage() {
    let v = Command::new(REQDRIVE).arg("--version").output().unwrap();
    assert_eq!(v.status.code(), Some(0));
    assert_eq!(
        String::from_utf8_lossy(&v.stdout).trim(),
        format!("reqdrive {}", env!("CARGO_PKG_VERSION"))
    );
    let u = Command::new(REQDRIVE).arg("nope").output().unwrap();
    assert_eq!(u.status.code(), Some(2));
    assert!(u.stdout.is_empty());
    assert!(String::from_utf8_lossy(&u.stderr).contains("usage"));
}
