//! Signal handling of `reqdrive story`: a SIGTERM during an agent call ends the run with a
//! `halted` / `interrupted` result as the last line of stdout.
#![cfg(unix)]

mod common;

use common::*;
use serde_json::{json, Value};
use std::fs;
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

#[test]
fn sigterm_mid_call_gives_halted_interrupted() {
    let f = Fixture::new();
    let mut slow = green_ok();
    slow["sleep_ms"] = json!(10_000);
    let h = f.harness_dir();
    fs::create_dir_all(&h).unwrap();
    let order_path = h.join("order.json");
    let script_path = h.join("script.json");
    fs::write(&order_path, f.order().to_string()).unwrap();
    fs::write(&script_path, script(vec![red_ok(), slow]).to_string()).unwrap();

    let mut child = Command::new(REQDRIVE)
        .arg("story")
        .arg(&order_path)
        .env("REQDRIVE_CLAUDE_BIN", FAKE)
        .env("FAKE_CLAUDE_SCRIPT", &script_path)
        .env("FAKE_CLAUDE_COUNTER", f.counter_path())
        .env("FAKE_CLAUDE_LOG", h.join("argv.log"))
        .env("REQDRIVE_HEARTBEAT_MS", "50")
        .env("REQDRIVE_GRACE_MS", "200")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn reqdrive");
    let pid = child.id() as i32;
    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel::<String>();
    let reader = std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if tx.send(line).is_err() {
                break;
            }
        }
    });

    let mut lines: Vec<Value> = Vec::new();
    let mut seen_green = false;
    let mut signalled_at: Option<Instant> = None;
    let deadline = Instant::now() + Duration::from_secs(30);
    while Instant::now() < deadline {
        let Ok(line) = rx.recv_timeout(Duration::from_millis(100)) else {
            if signalled_at.is_some() && child.try_wait().unwrap().is_some() {
                break;
            }
            continue;
        };
        let v: Value =
            serde_json::from_str(&line).unwrap_or_else(|e| panic!("bad line {line:?}: {e}"));
        if signalled_at.is_none() {
            if v["type"] == "progress" && v["stage"] == "green" {
                seen_green = true;
            } else if seen_green && v["type"] == "heartbeat" && v["waiting_on"] == "agent" {
                #[allow(unsafe_code)]
                let rc = unsafe { libc::kill(pid, libc::SIGTERM) };
                assert_eq!(rc, 0, "kill failed");
                signalled_at = Some(Instant::now());
            }
        }
        let is_result = v["type"] == "result";
        lines.push(v);
        if is_result {
            break;
        }
    }
    let signalled_at = signalled_at.expect("never saw green then an agent heartbeat");

    // The process must exit 0 within 3 s of the signal.
    let status = loop {
        if let Some(s) = child.try_wait().unwrap() {
            break s;
        }
        if signalled_at.elapsed() > Duration::from_secs(3) {
            let _ = child.kill();
            panic!("reqdrive did not exit within 3 s of SIGTERM");
        }
        std::thread::sleep(Duration::from_millis(20));
    };
    assert!(signalled_at.elapsed() <= Duration::from_secs(3));
    assert_eq!(status.code(), Some(0));

    // Nothing may follow the result.
    reader.join().unwrap();
    let trailing: Vec<String> = rx.try_iter().collect();
    assert!(trailing.is_empty(), "lines after the result: {trailing:?}");
    let r = result(&lines);
    assert_eq!(r["outcome"], "halted", "{r}");
    assert_eq!(r["failure"]["category"], "interrupted", "{r}");
}
