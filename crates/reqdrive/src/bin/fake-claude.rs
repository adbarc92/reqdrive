//! Test-only stand-in for the `claude` CLI, plus a test checker.
//!
//! - `fake-claude check-tests <dir>`: every `expect <relpath> <needle>` line in every file
//!   under `<dir>` must hold (the file exists, relative to the current directory, and contains
//!   the needle). Exit 0 if all hold, 1 otherwise.
//! - `fake-claude spew <bytes>`: prints that many bytes of text and exits 0.
//! - `fake-claude hold <ms>`: sleeps that long and exits 0. A call's `orphan_sleep_ms` starts
//!   one in the background, holding the call's stdout open after the call exits. A call's
//!   `null_orphan_sleep_ms` starts one with stdin, stdout and stderr all null, so it holds only
//!   the handles it inherits implicitly.
//! - Otherwise it acts as `claude`, driven by the JSON script `$FAKE_CLAUDE_SCRIPT`
//!   (`{"calls":[…]}`), picking the call from the counter file `$FAKE_CLAUDE_COUNTER` and
//!   logging its argv to `$FAKE_CLAUDE_LOG`. A call's optional `git_commit_all: "<msg>"` runs
//!   `git add -A` and `git commit` in the current directory after its `writes`.

use serde_json::{json, Value};
use std::fs;
use std::io::{self, BufWriter, Read, Write};
use std::path::Path;
use std::time::Duration;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match args.first().map(String::as_str) {
        Some("check-tests") => check_tests(args.get(1).map(String::as_str).unwrap_or(".")),
        Some("spew") => spew(args.get(1).and_then(|n| n.parse().ok()).unwrap_or(0)),
        Some("hold") => {
            let ms = args.get(1).and_then(|n| n.parse().ok()).unwrap_or(0);
            std::thread::sleep(Duration::from_millis(ms));
            0
        }
        _ => act_as_claude(&args),
    };
    std::process::exit(code);
}

fn files_under(dir: &Path, out: &mut Vec<std::path::PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            files_under(&path, out);
        } else {
            out.push(path);
        }
    }
}

fn check_tests(dir: &str) -> i32 {
    let mut files = Vec::new();
    files_under(Path::new(dir), &mut files);
    let mut ok = true;
    for file in files {
        let text = String::from_utf8_lossy(&fs::read(&file).unwrap_or_default()).into_owned();
        for line in text.lines() {
            let Some(rest) = line.trim_end_matches('\r').strip_prefix("expect ") else {
                continue;
            };
            let (relpath, needle) = rest.split_once(' ').unwrap_or((rest, ""));
            let holds = fs::read(relpath)
                .map(|b| String::from_utf8_lossy(&b).contains(needle))
                .unwrap_or(false);
            if !holds {
                println!("FAIL {}: expect {relpath} {needle}", file.display());
                ok = false;
            }
        }
    }
    if ok {
        0
    } else {
        1
    }
}

fn spew(bytes: usize) -> i32 {
    let mut out = BufWriter::new(io::stdout().lock());
    for i in 0..bytes {
        let b = if i % 100 == 99 { b'\n' } else { b'x' };
        if out.write_all(&[b]).is_err() {
            return 1;
        }
    }
    if out.flush().is_err() {
        return 1;
    }
    0
}

/// Starts `fake-claude hold <ms>` without waiting for it. With `keep_stdout` it inherits our
/// stdout, so the pipe stays open after we exit; without it all three stdio are null. On Unix
/// it leads a process group of its own, as a process that called `setsid` would, so a sweep of
/// our group does not reach it.
fn orphan(ms: u64, keep_stdout: bool) {
    let exe = std::env::current_exe().expect("current_exe");
    let mut cmd = std::process::Command::new(exe);
    // Not the workspace: a live process's cwd cannot be deleted on Windows.
    cmd.args(["hold", &ms.to_string()])
        .current_dir(std::env::temp_dir())
        .stdin(std::process::Stdio::null())
        .stdout(if keep_stdout {
            std::process::Stdio::inherit()
        } else {
            std::process::Stdio::null()
        })
        .stderr(std::process::Stdio::null());
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }
    // Never waited for: we exit at once and the orphan is reparented.
    #[allow(clippy::zombie_processes)]
    cmd.spawn().expect("spawn the orphan");
}

fn act_as_claude(args: &[String]) -> i32 {
    let mut stdin = Vec::new();
    let _ = io::stdin().read_to_end(&mut stdin);

    if let Ok(log) = std::env::var("FAKE_CLAUDE_LOG") {
        let mut f = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(log)
            .expect("open FAKE_CLAUDE_LOG");
        writeln!(f, "{}", json!(args)).expect("write FAKE_CLAUDE_LOG");
    }

    let counter = std::env::var("FAKE_CLAUDE_COUNTER").expect("FAKE_CLAUDE_COUNTER");
    let index: usize = fs::read_to_string(&counter)
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0);
    fs::write(&counter, (index + 1).to_string()).expect("write FAKE_CLAUDE_COUNTER");

    let script_path = std::env::var("FAKE_CLAUDE_SCRIPT").expect("FAKE_CLAUDE_SCRIPT");
    let script: Value =
        serde_json::from_str(&fs::read_to_string(script_path).expect("read FAKE_CLAUDE_SCRIPT"))
            .expect("FAKE_CLAUDE_SCRIPT is JSON");
    let Some(call) = script["calls"].get(index) else {
        return 3;
    };

    if let Some(writes) = call["writes"].as_object() {
        for (rel, content) in writes {
            let path = Path::new(rel);
            if let Some(parent) = path.parent() {
                fs::create_dir_all(parent).expect("create parent dirs");
            }
            fs::write(path, content.as_str().unwrap_or_default()).expect("write file");
        }
    }
    if let Some(deletes) = call["deletes"].as_array() {
        for rel in deletes.iter().filter_map(Value::as_str) {
            let _ = fs::remove_file(rel);
        }
    }
    // An agent that runs git itself, as it can under bypassPermissions.
    if let Some(msg) = call["git_commit_all"].as_str() {
        let git = |args: &[&str]| {
            std::process::Command::new("git")
                .args([
                    "-c",
                    "user.name=f",
                    "-c",
                    "user.email=f@x",
                    "-c",
                    "commit.gpgsign=false",
                ])
                .args(args)
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .status()
                .map(|s| s.success())
                .unwrap_or(false)
        };
        if !(git(&["add", "-A"]) && git(&["commit", "-q", "--no-verify", "-m", msg])) {
            return 4;
        }
    }

    let mut out = io::stdout().lock();
    let sleep = || {
        if let Some(ms) = call["sleep_ms"].as_u64() {
            std::thread::sleep(Duration::from_millis(ms));
        }
    };
    if let Some(lines) = call["lines"].as_array() {
        for line in lines {
            let _ = writeln!(out, "{}", line.as_str().unwrap_or_default());
        }
        let _ = out.flush();
        sleep();
    } else {
        let n = index + 1;
        let subtype = call["subtype"].as_str().unwrap_or("success");
        let num_turns = call["num_turns"].as_u64().unwrap_or(1);
        let text = call["text"].as_str().unwrap_or("");
        let start = json!({"type":"stream_event","event":{"type":"message_start","message":{
            "id": format!("msg_{n}"),
            "model": "claude-fake",
            "usage": {"input_tokens":10,"cache_creation_input_tokens":5,"cache_read_input_tokens":20,"output_tokens":1}
        }}});
        let delta = json!({"type":"stream_event","event":{"type":"message_delta","usage":{"output_tokens":7}}});
        let _ = writeln!(out, "{start}");
        let _ = writeln!(out, "{delta}");
        let _ = out.flush();
        sleep();
        let result = json!({
            "type": "result",
            "subtype": subtype,
            "is_error": subtype != "success",
            "num_turns": num_turns,
            "result": text,
            "modelUsage": {"claude-fake": {
                "inputTokens": 10,
                "outputTokens": 7,
                "cacheReadInputTokens": 20,
                "cacheCreationInputTokens": 5
            }}
        });
        let _ = writeln!(out, "{result}");
        let _ = out.flush();
    }
    drop(out);
    if let Some(ms) = call["orphan_sleep_ms"].as_u64() {
        orphan(ms, true);
    }
    if let Some(ms) = call["null_orphan_sleep_ms"].as_u64() {
        orphan(ms, false);
    }

    call["exit"].as_i64().unwrap_or(0) as i32
}
