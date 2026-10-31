//! Two attempts running at once from worktrees of the same repository do not disturb each
//! other or the shared repository state.

mod common;

use common::*;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};

struct Attempt {
    id: String,
    branch: String,
    tests_ref: String,
    state_dir: PathBuf,
    harness: PathBuf,
    child: Option<Child>,
}

fn prepare(f: &Fixture, n: u32) -> Attempt {
    let id = format!("a{n}");
    let branch = format!("attempt/S-1/{id}");
    let tests_ref = format!("refs/heads/{branch}.tests");
    let root = f.root.path();
    let wt = root.join(format!("wt{n}"));
    git(
        &f.ws,
        &[
            "worktree",
            "add",
            "-q",
            "--detach",
            wt.to_str().unwrap(),
            &f.base,
        ],
    );
    let state_dir = root.join(format!("state-{id}"));
    let h = root.join(format!("harness-{id}"));
    fs::create_dir_all(&h).unwrap();
    let mut order = f.order();
    order["attempt_id"] = json!(id);
    order["attempt_branch"] = json!(branch);
    order["tests_ref"] = json!(tests_ref);
    order["workspace"] = json!(wt);
    order["state_dir"] = json!(state_dir);
    let order_path = h.join("order.json");
    let script_path = h.join("script.json");
    fs::write(&order_path, order.to_string()).unwrap();
    fs::write(&script_path, script(vec![red_ok(), green_ok()]).to_string()).unwrap();
    Attempt {
        id,
        branch,
        tests_ref,
        state_dir,
        harness: h,
        child: None,
    }
}

fn start(a: &mut Attempt) {
    let h = &a.harness;
    a.child = Some(
        Command::new(REQDRIVE)
            .arg("story")
            .arg(h.join("order.json"))
            .env("REQDRIVE_CLAUDE_BIN", FAKE)
            .env("FAKE_CLAUDE_SCRIPT", h.join("script.json"))
            .env("FAKE_CLAUDE_COUNTER", h.join("counter"))
            .env("FAKE_CLAUDE_LOG", h.join("argv.log"))
            .env("REQDRIVE_HEARTBEAT_MS", "50")
            .env("REQDRIVE_GRACE_MS", "200")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("spawn reqdrive"),
    );
}

fn finish(a: &mut Attempt) -> Vec<Value> {
    let out = a.child.take().unwrap().wait_with_output().expect("wait");
    eprintln!(
        "--- {} stderr ---\n{}",
        a.id,
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(out.status.code(), Some(0), "{}", a.id);
    String::from_utf8_lossy(&out.stdout)
        .lines()
        .map(|l| serde_json::from_str(l).unwrap_or_else(|e| panic!("bad line {l:?}: {e}")))
        .collect()
}

fn refs(ws: &Path) -> Vec<String> {
    git(ws, &["for-each-ref", "--format=%(refname) %(objectname)"])
        .lines()
        .map(str::to_string)
        .collect()
}

#[test]
fn two_attempts_in_parallel_worktrees() {
    let f = Fixture::new();
    let common_dir = {
        let d = git(&f.ws, &["rev-parse", "--git-common-dir"]);
        let p = PathBuf::from(&d);
        if p.is_absolute() {
            p
        } else {
            f.ws.join(p)
        }
    };
    let config_path = common_dir.join("config");
    // Worktree creation is part of the setup; the baseline is taken once it is done.
    let mut a1 = prepare(&f, 1);
    let mut a2 = prepare(&f, 2);
    let config_before = fs::read(&config_path).unwrap();
    let refs_before = refs(&f.ws);
    start(&mut a1);
    start(&mut a2);
    let ev1 = finish(&mut a1);
    let ev2 = finish(&mut a2);
    let config_after = fs::read(&config_path).unwrap();
    let refs_after = refs(&f.ws);

    for (a, ev) in [(&a1, &ev1), (&a2, &ev2)] {
        let r = result(ev);
        assert_eq!(r["outcome"], "pushed", "{}: {r}", a.id);
        assert!(a.state_dir.join("events.jsonl").is_file(), "{}", a.id);
        assert_eq!(
            f.remote_ref(&format!("refs/heads/{}", a.branch)).as_deref(),
            r["head_sha"].as_str()
        );
        assert!(f.remote_ref(&a.tests_ref).is_some());
    }
    assert_ne!(
        fs::read(a1.state_dir.join("events.jsonl")).unwrap(),
        fs::read(a2.state_dir.join("events.jsonl")).unwrap()
    );

    let before: std::collections::BTreeSet<&String> = refs_before.iter().collect();
    let added: Vec<String> = refs_after
        .iter()
        .filter(|r| !before.contains(r))
        .map(|r| r.split(' ').next().unwrap().to_string())
        .collect();
    let mut expected: Vec<String> = Vec::new();
    for a in [&a1, &a2] {
        expected.push(format!("refs/heads/{}", a.branch));
        expected.push(format!("refs/remotes/origin/{}", a.branch));
        expected.push(format!(
            "refs/remotes/origin/{}",
            a.tests_ref.trim_start_matches("refs/heads/")
        ));
    }
    let mut added_sorted = added.clone();
    added_sorted.sort();
    expected.sort();
    assert_eq!(added_sorted, expected, "refs added");
    // Nothing that existed before changed or vanished.
    let after: std::collections::BTreeSet<&String> = refs_after.iter().collect();
    for r in &refs_before {
        assert!(after.contains(r), "ref changed or removed: {r}");
    }
    assert_eq!(config_before, config_after, ".git/config changed");
}
