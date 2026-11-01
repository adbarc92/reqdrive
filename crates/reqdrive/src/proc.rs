//! Supervised child processes: process groups, deadlines, interrupts and the test runner.
//!
//! On Unix every child leads its own process group, so an interrupt or a kill reaches
//! grandchildren too. On Windows only the direct child can be killed.

use std::fs::File;
use std::io::{self, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

static INTERRUPTED: AtomicBool = AtomicBool::new(false);

const POLL: Duration = Duration::from_millis(100);
const TAIL_BYTES: u64 = 2048;
const DEFAULT_GRACE_MS: u64 = 30_000;
/// The largest `REQDRIVE_GRACE_MS` (and `REQDRIVE_HEARTBEAT_MS`) honoured: one hour.
pub const MAX_ENV_MS: u64 = 3_600_000;

/// Env vars that point git at a repository other than the workspace. Every child the harness
/// starts (git, the agent, the test command) runs without them.
pub const REPO_ENV: [&str; 6] = [
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_INDEX_FILE",
    "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY",
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
];

/// Removes [`REPO_ENV`] from `cmd`'s environment.
pub fn scrub_repo_env(cmd: &mut Command) {
    for name in REPO_ENV {
        cmd.env_remove(name);
    }
}

/// Makes the harness's own stdin, stdout and stderr non-inheritable, so no child (or its
/// descendants) holds them. Call it first thing in `main`.
///
/// std spawns every Windows child with handle inheritance on, so without this each child
/// would hold the harness's stdout whatever its own `Stdio` is: a leftover descendant would
/// keep the orchestrator's pipe open, and a child could write events. `Stdio::inherit` is
/// unaffected (std duplicates the handle as inheritable for that child). Best effort: every
/// handle is tried, a missing one is skipped, and the first failure is returned.
#[cfg(windows)]
#[allow(unsafe_code)]
pub fn stop_std_handle_inheritance() -> io::Result<()> {
    type Handle = *mut std::ffi::c_void;
    const STD_INPUT_HANDLE: u32 = -10i32 as u32;
    const STD_OUTPUT_HANDLE: u32 = -11i32 as u32;
    const STD_ERROR_HANDLE: u32 = -12i32 as u32;
    const HANDLE_FLAG_INHERIT: u32 = 0x1;
    const INVALID_HANDLE_VALUE: Handle = -1isize as Handle;
    #[link(name = "kernel32")]
    extern "system" {
        fn GetStdHandle(n_std_handle: u32) -> Handle;
        fn SetHandleInformation(h_object: Handle, dw_mask: u32, dw_flags: u32) -> i32;
    }
    let mut first_err = None;
    for which in [STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, STD_ERROR_HANDLE] {
        // SAFETY: GetStdHandle takes a plain constant and returns a handle, null or
        // INVALID_HANDLE_VALUE; SetHandleInformation only changes the flag on a handle the
        // process owns, and is given only a real one.
        unsafe {
            let h = GetStdHandle(which);
            if h.is_null() || h == INVALID_HANDLE_VALUE {
                continue;
            }
            if SetHandleInformation(h, HANDLE_FLAG_INHERIT, 0) == 0 && first_err.is_none() {
                first_err = Some(io::Error::last_os_error());
            }
        }
    }
    first_err.map_or(Ok(()), Err)
}

/// A no-op: on Unix std gives a child's fds 0 to 2 from its `Stdio` and opens everything else
/// close-on-exec.
#[cfg(not(windows))]
pub fn stop_std_handle_inheritance() -> io::Result<()> {
    Ok(())
}

/// Sets [`interrupted`] on SIGINT/SIGTERM (Ctrl-C on Windows). Safe to call more than once.
pub fn install_signal_handler() -> Result<(), String> {
    match ctrlc::set_handler(|| INTERRUPTED.store(true, Ordering::SeqCst)) {
        Ok(()) | Err(ctrlc::Error::MultipleHandlers) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

pub fn interrupted() -> bool {
    INTERRUPTED.load(Ordering::SeqCst)
}

/// Asks the run to stop as if it were interrupted, for example because the orchestrator stopped
/// reading the event stream. [`interrupted`] reports it.
pub fn request_stop() {
    INTERRUPTED.store(true, Ordering::SeqCst);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndedBy {
    Normal,
    Deadline,
    Interrupted,
    TokenLimit,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Exit {
    pub code: Option<i32>,
    pub ended_by: EndedBy,
}

/// Spawns `cmd` as the leader of a new process group on Unix. Every child in the crate is
/// spawned through here.
pub fn spawn_grouped(cmd: &mut Command) -> io::Result<Child> {
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }
    cmd.spawn()
}

/// Waits for `child`, polling every 100 ms. On the deadline, an interrupt or `over_budget()`,
/// it interrupts the child once and records the first reason; `grace` later it kills the
/// group and waits. A child that exits before any trigger ended `Normal`. Once the leader has
/// exited, for any reason, anything left in its group is killed at once (on Unix).
pub fn supervise(
    child: &mut Child,
    deadline: Instant,
    over_budget: &dyn Fn() -> bool,
    grace: Duration,
) -> io::Result<Exit> {
    let mut stopping: Option<(EndedBy, Instant)> = None;
    loop {
        if let Some(status) = child.try_wait()? {
            // The leader is gone; sweep anything left in its group.
            kill_all(child);
            let ended_by = match stopping {
                Some((why, _)) => why,
                None => EndedBy::Normal,
            };
            return Ok(Exit {
                code: status.code(),
                ended_by,
            });
        }
        match stopping {
            None => {
                let why = if interrupted() {
                    Some(EndedBy::Interrupted)
                } else if Instant::now() >= deadline {
                    Some(EndedBy::Deadline)
                } else if over_budget() {
                    Some(EndedBy::TokenLimit)
                } else {
                    None
                };
                if let Some(why) = why {
                    interrupt(child);
                    stopping = Some((why, Instant::now()));
                }
            }
            Some((why, since)) => {
                if since.elapsed() >= grace {
                    kill_all(child);
                    let status = child.wait()?;
                    return Ok(Exit {
                        code: status.code(),
                        ended_by: why,
                    });
                }
            }
        }
        std::thread::sleep(POLL);
    }
}

#[cfg(unix)]
#[allow(unsafe_code)]
fn interrupt(child: &mut Child) {
    // SAFETY: kill(2) takes plain integers; the negative pid names the child's group.
    unsafe {
        libc::kill(-(child.id() as libc::pid_t), libc::SIGINT);
    }
}

#[cfg(windows)]
fn interrupt(child: &mut Child) {
    let _ = child.kill();
}

/// Kills the child's whole group on Unix, and the child itself everywhere. Harmless once the
/// child has been waited for.
#[cfg(unix)]
#[allow(unsafe_code)]
pub fn kill_all(child: &mut Child) {
    // SAFETY: as in `interrupt`.
    unsafe {
        libc::kill(-(child.id() as libc::pid_t), libc::SIGKILL);
    }
    let _ = child.kill();
}

/// Kills the child. Only the direct child can be killed on Windows.
#[cfg(windows)]
pub fn kill_all(child: &mut Child) {
    let _ = child.kill();
}

/// `sh -c <cmdline>` on Unix, `cmd /S /C "<cmdline>"` on Windows, with `CI=true`.
pub fn shell(cmdline: &str) -> Command {
    #[cfg(unix)]
    let mut cmd = {
        let mut c = Command::new("sh");
        c.arg("-c").arg(cmdline);
        c
    };
    #[cfg(windows)]
    let mut cmd = {
        use std::os::windows::process::CommandExt;
        let mut c = Command::new("cmd");
        c.raw_arg(format!("/S /C \"{cmdline}\""));
        c
    };
    cmd.env("CI", "true");
    scrub_repo_env(&mut cmd);
    cmd
}

#[derive(Debug)]
pub struct TestRun {
    pub exit: Exit,
    pub log: PathBuf,
    pub tail: String,
}

/// Runs the test command through [`shell`] in `cwd`, with stdin null and stdout and stderr
/// both written to `log`. `tail` is the last 2 048 bytes of the log.
pub fn run_tests(
    cmdline: &str,
    cwd: &Path,
    log: &Path,
    deadline: Instant,
    over_budget: &dyn Fn() -> bool,
    grace: Duration,
) -> io::Result<TestRun> {
    let out = File::create(log)?;
    let err = out.try_clone()?;
    let mut cmd = shell(cmdline);
    cmd.current_dir(cwd)
        .stdin(Stdio::null())
        .stdout(out)
        .stderr(err);
    let mut child = spawn_grouped(&mut cmd)?;
    drop(cmd);
    let exit = supervise(&mut child, deadline, over_budget, grace)?;
    Ok(TestRun {
        exit,
        log: log.to_path_buf(),
        tail: tail(log)?,
    })
}

/// The last 2 048 bytes of `path`, read lossily as UTF-8. Leading UTF-8 continuation bytes
/// are dropped, so a cut character cannot grow the tail past 2 048 bytes.
fn tail(path: &Path) -> io::Result<String> {
    let mut f = File::open(path)?;
    let len = f.metadata()?.len();
    f.seek(SeekFrom::Start(len.saturating_sub(TAIL_BYTES)))?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)?;
    let start = buf
        .iter()
        .take(3)
        .take_while(|b| (**b & 0xC0) == 0x80)
        .count();
    Ok(String::from_utf8_lossy(&buf[start..]).into_owned())
}

/// `REQDRIVE_GRACE_MS`, default 30 000 ms, at most [`MAX_ENV_MS`].
pub fn grace_from_env() -> Duration {
    let ms = std::env::var("REQDRIVE_GRACE_MS")
        .ok()
        .and_then(|v| v.trim().parse::<u64>().ok())
        .unwrap_or(DEFAULT_GRACE_MS)
        .min(MAX_ENV_MS);
    Duration::from_millis(ms)
}
