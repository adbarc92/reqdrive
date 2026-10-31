use reqdrive::proc::{run_tests, spawn_grouped, supervise, EndedBy, Exit};
use reqdrive::stream::StreamParser;
use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const FAKE: &str = env!("CARGO_BIN_EXE_fake-claude");

/// A `fake-claude` command acting as `claude`, with its own script and counter in `dir`.
fn fake(dir: &Path, script: Value) -> Command {
    let script_path = dir.join("script.json");
    fs::write(&script_path, script.to_string()).unwrap();
    let mut cmd = Command::new(FAKE);
    cmd.current_dir(dir)
        .env("FAKE_CLAUDE_SCRIPT", &script_path)
        .env("FAKE_CLAUDE_COUNTER", dir.join("counter"))
        .env_remove("FAKE_CLAUDE_LOG")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    cmd
}

fn far() -> Instant {
    Instant::now() + Duration::from_secs(60)
}

#[test]
fn supervise_normal_exit_code() {
    let dir = tempfile::tempdir().unwrap();
    let mut cmd = fake(dir.path(), json!({"calls":[{"exit":4}]}));
    let mut child = spawn_grouped(&mut cmd).unwrap();
    let exit = supervise(&mut child, far(), &|| false, Duration::from_millis(200)).unwrap();
    assert_eq!(
        exit,
        Exit {
            code: Some(4),
            ended_by: EndedBy::Normal
        }
    );
}

#[test]
fn supervise_deadline_interrupts() {
    let dir = tempfile::tempdir().unwrap();
    let mut cmd = fake(dir.path(), json!({"calls":[{"sleep_ms":5000}]}));
    let start = Instant::now();
    let mut child = spawn_grouped(&mut cmd).unwrap();
    let deadline = Instant::now() + Duration::from_millis(300);
    let exit = supervise(&mut child, deadline, &|| false, Duration::from_millis(200)).unwrap();
    assert_eq!(exit.ended_by, EndedBy::Deadline);
    assert!(
        start.elapsed() < Duration::from_secs(2),
        "{:?}",
        start.elapsed()
    );
}

#[test]
fn supervise_token_limit() {
    let dir = tempfile::tempdir().unwrap();
    let mut cmd = fake(dir.path(), json!({"calls":[{"sleep_ms":5000}]}));
    let start = Instant::now();
    let mut child = spawn_grouped(&mut cmd).unwrap();
    let exit = supervise(&mut child, far(), &|| true, Duration::from_millis(200)).unwrap();
    assert_eq!(exit.ended_by, EndedBy::TokenLimit);
    assert!(
        start.elapsed() < Duration::from_secs(2),
        "{:?}",
        start.elapsed()
    );
}

#[test]
fn run_tests_captures_and_tails() {
    let dir = tempfile::tempdir().unwrap();
    fs::create_dir_all(dir.path().join("t")).unwrap();
    fs::write(dir.path().join("t/a.test"), "AC-1\nexpect src/x.txt done\n").unwrap();
    let log = dir.path().join("logs").join("tests.log");
    fs::create_dir_all(log.parent().unwrap()).unwrap();
    let run = run_tests(
        &format!("\"{FAKE}\" check-tests t"),
        dir.path(),
        &log,
        far(),
        &|| false,
        Duration::from_millis(200),
    )
    .unwrap();
    assert_eq!(run.exit.code, Some(1));
    assert_eq!(run.exit.ended_by, EndedBy::Normal);
    assert_eq!(run.log, log);
    assert!(log.exists());
    assert!(run.tail.contains("src/x.txt"), "tail: {:?}", run.tail);
}

#[test]
fn run_tests_tail_is_bounded() {
    let dir = tempfile::tempdir().unwrap();
    let log = dir.path().join("tests.log");
    let run = run_tests(
        &format!("\"{FAKE}\" spew 3000000"),
        dir.path(),
        &log,
        far(),
        &|| false,
        Duration::from_millis(200),
    )
    .unwrap();
    assert_eq!(run.exit.code, Some(0));
    assert!(fs::metadata(&log).unwrap().len() >= 3_000_000);
    assert!(run.tail.len() <= 2048, "tail is {} bytes", run.tail.len());
    assert!(run.tail.len() > 1000);
    assert!(run.tail.ends_with('\n'));
}

#[cfg(unix)]
#[test]
fn interrupt_reaches_grandchild() {
    let mut cmd = reqdrive::proc::shell("sleep 30 & wait");
    cmd.stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    let mut child = spawn_grouped(&mut cmd).unwrap();
    let pgid = child.id() as i32;
    std::thread::sleep(Duration::from_millis(200));
    let grace = Duration::from_millis(500);
    let start = Instant::now();
    let past = Instant::now() - Duration::from_secs(1);
    let exit = supervise(&mut child, past, &|| false, grace).unwrap();
    assert_eq!(exit.ended_by, EndedBy::Deadline);
    assert!(start.elapsed() < grace + Duration::from_secs(1));
    // The group is gone once init has reaped the killed `sleep`.
    let gone = (0..50).any(|_| {
        #[allow(unsafe_code)]
        let alive = unsafe { libc::kill(-pgid, 0) } == 0;
        if alive {
            std::thread::sleep(Duration::from_millis(100));
        }
        !alive
    });
    assert!(gone, "a process of group {pgid} is still alive");
}

fn check_tests(dir: &Path) -> i32 {
    Command::new(FAKE)
        .args(["check-tests", "t"])
        .current_dir(dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .unwrap()
        .code()
        .unwrap()
}

#[test]
fn fake_check_tests_semantics() {
    let dir = tempfile::tempdir().unwrap();
    let t = dir.path().join("t");
    fs::create_dir_all(t.join("nested")).unwrap();
    assert_eq!(check_tests(dir.path()), 0, "zero files");

    fs::create_dir_all(dir.path().join("src")).unwrap();
    fs::write(dir.path().join("src/feature.txt"), "all done here").unwrap();
    fs::write(
        t.join("a.test"),
        "AC-1 AC-2\r\nexpect src/feature.txt done\r\n",
    )
    .unwrap();
    assert_eq!(check_tests(dir.path()), 0, "met expectation");

    fs::write(t.join("nested/b.test"), "expect src/feature.txt missing\n").unwrap();
    assert_eq!(
        check_tests(dir.path()),
        1,
        "unmet expectation in a nested file"
    );

    fs::write(t.join("nested/b.test"), "expect src/absent.txt done\n").unwrap();
    assert_eq!(check_tests(dir.path()), 1, "missing file");
}

#[test]
fn fake_claude_scripted_calls() {
    let dir = tempfile::tempdir().unwrap();
    fs::write(dir.path().join("gone.txt"), "x").unwrap();
    let script = json!({"calls":[
        {"writes":{"src/deep/a.txt":"hello"},"deletes":["gone.txt"],"text":"said \"hi\"","num_turns":3},
        {"lines":["not json","{\"type\":\"result\"}"],"exit":2},
    ]});
    let log = dir.path().join("argv.log");

    let out = fake(dir.path(), script)
        .args(["-p", "--max-turns", "7"])
        .env("FAKE_CLAUDE_LOG", &log)
        .stdout(Stdio::piped())
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(0));
    assert_eq!(
        fs::read_to_string(dir.path().join("src/deep/a.txt")).unwrap(),
        "hello"
    );
    assert!(!dir.path().join("gone.txt").exists());
    assert_eq!(
        fs::read_to_string(dir.path().join("counter"))
            .unwrap()
            .trim(),
        "1"
    );
    let argv: Value =
        serde_json::from_str(fs::read_to_string(&log).unwrap().lines().next().unwrap()).unwrap();
    assert_eq!(argv, json!(["-p", "--max-turns", "7"]));

    // The default stream is what the real parser reads.
    let mut parser = StreamParser::new(1, "anthropic".to_string());
    let mut rows = Vec::new();
    for line in String::from_utf8(out.stdout).unwrap().lines() {
        rows.extend(parser.feed(line));
    }
    let summary = parser.finish();
    let fr = summary.final_result.expect("a result line");
    assert_eq!(fr.subtype, "success");
    assert!(!fr.is_error);
    assert_eq!(fr.num_turns, Some(3));
    assert_eq!(fr.text, "said \"hi\"");
    assert!(fr.model_usage.contains_key("claude-fake"));
    assert_eq!(rows.len() + summary.flushed.len(), 1);
    assert!(summary.residue.is_empty(), "{:?}", summary.residue);

    // Second call: verbatim lines and an exit code.
    let out = fake(
        dir.path(),
        json!({"calls":[{}, {"lines":["not json"],"exit":2}]}),
    )
    .stdout(Stdio::piped())
    .output()
    .unwrap();
    assert_eq!(out.status.code(), Some(2));
    assert_eq!(
        String::from_utf8(out.stdout).unwrap().trim_end(),
        "not json"
    );

    // Past the end of the script: nothing printed, exit 3.
    let out = fake(dir.path(), json!({"calls":[{}, {}]}))
        .stdout(Stdio::piped())
        .output()
        .unwrap();
    assert_eq!(out.status.code(), Some(3));
    assert!(out.stdout.is_empty());
}
