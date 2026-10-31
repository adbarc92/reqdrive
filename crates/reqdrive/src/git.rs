//! Git operations for the driver. Every call runs
//! `git -C <ws> -c core.hooksPath=<hooks_dir> <args>` with no stdin and no prompts.

use std::fmt;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};

use crate::proc::{spawn_grouped, supervise, EndedBy};

#[derive(Debug)]
pub struct GitError {
    pub args: String,
    pub code: Option<i32>,
    pub stderr: String,
}

impl fmt::Display for GitError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.code {
            Some(c) => write!(
                f,
                "git {} failed ({}): {}",
                self.args,
                c,
                self.stderr.trim()
            ),
            None => write!(f, "git {} failed: {}", self.args, self.stderr.trim()),
        }
    }
}

impl std::error::Error for GitError {}

type Res<T> = Result<T, GitError>;

pub struct Git {
    ws: PathBuf,
    hooks_dir: PathBuf,
    env: Vec<(String, String)>,
}

impl Git {
    pub fn new(ws: &Path, hooks_dir: &Path) -> Git {
        Git {
            ws: ws.to_path_buf(),
            hooks_dir: hooks_dir.to_path_buf(),
            env: Vec::new(),
        }
    }

    /// Adds env vars to every call (tests use this to isolate git config).
    pub fn with_env(mut self, vars: Vec<(String, String)>) -> Git {
        self.env.extend(vars);
        self
    }

    fn base(&self) -> Command {
        let mut cmd = Command::new("git");
        cmd.arg("-C")
            .arg(&self.ws)
            .arg("-c")
            .arg(format!("core.hooksPath={}", self.hooks_dir.display()))
            .stdin(Stdio::null())
            .env("GIT_TERMINAL_PROMPT", "0");
        for (k, v) in &self.env {
            cmd.env(k, v);
        }
        cmd
    }

    fn run(&self, args: &[&str]) -> Res<String> {
        let joined = args.join(" ");
        let mut cmd = self.base();
        cmd.args(args).stdout(Stdio::piped()).stderr(Stdio::piped());
        let out = cmd.output().map_err(|e| GitError {
            args: joined.clone(),
            code: None,
            stderr: e.to_string(),
        })?;
        if out.status.success() {
            Ok(String::from_utf8_lossy(&out.stdout).into_owned())
        } else {
            Err(GitError {
                args: joined,
                code: out.status.code(),
                stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
            })
        }
    }

    pub fn is_work_tree(&self) -> bool {
        self.run(&["rev-parse", "--is-inside-work-tree"])
            .map(|s| s.trim() == "true")
            .unwrap_or(false)
    }

    pub fn commit_exists(&self, sha: &str) -> bool {
        self.run(&["cat-file", "-e", &format!("{sha}^{{commit}}")])
            .is_ok()
    }

    pub fn head(&self) -> Res<String> {
        Ok(self.run(&["rev-parse", "HEAD"])?.trim().to_string())
    }

    pub fn is_clean(&self) -> Res<bool> {
        Ok(self
            .run(&["status", "--porcelain", "--untracked-files=all"])?
            .trim()
            .is_empty())
    }

    pub fn branch_sha(&self, name: &str) -> Res<Option<String>> {
        match self.run(&[
            "rev-parse",
            "--verify",
            "--quiet",
            &format!("refs/heads/{name}"),
        ]) {
            Ok(s) => Ok(Some(s.trim().to_string())),
            Err(e) if e.code == Some(1) && e.stderr.trim().is_empty() => Ok(None),
            Err(e) => Err(e),
        }
    }

    /// `None` when HEAD is detached.
    pub fn current_branch(&self) -> Res<Option<String>> {
        match self.run(&["symbolic-ref", "--quiet", "--short", "HEAD"]) {
            Ok(s) => Ok(Some(s.trim().to_string())),
            Err(e) if e.code == Some(1) && e.stderr.trim().is_empty() => Ok(None),
            Err(e) => Err(e),
        }
    }

    pub fn switch(&self, name: &str) -> Res<()> {
        self.run(&["switch", name]).map(|_| ())
    }

    pub fn switch_create(&self, name: &str, at: &str) -> Res<()> {
        self.run(&["switch", "-c", name, at]).map(|_| ())
    }

    pub fn ref_format_ok(&self, refname: &str) -> bool {
        let full = if refname.starts_with("refs/") {
            refname.to_string()
        } else {
            format!("refs/heads/{refname}")
        };
        self.run(&["check-ref-format", &full]).is_ok()
    }

    pub fn stage_all(&self) -> Res<()> {
        self.run(&["add", "-A"]).map(|_| ())
    }

    pub fn staged_paths(&self) -> Res<Vec<String>> {
        let out = self.run(&[
            "diff",
            "--cached",
            "--name-only",
            "--no-renames",
            "-z",
            "HEAD",
        ])?;
        Ok(split_nul(&out))
    }

    pub fn staged_patch(&self) -> Res<String> {
        self.run(&["diff", "--cached", "--binary", "HEAD"])
    }

    /// Commits the index without hooks or signing, and returns the new HEAD.
    pub fn commit(&self, msg: &str) -> Res<String> {
        self.run(&[
            "-c",
            "user.name=reqdrive",
            "-c",
            "user.email=reqdrive@localhost",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "--no-verify",
            "-m",
            msg,
        ])?;
        self.head()
    }

    pub fn reset_clean(&self) -> Res<()> {
        self.run(&["reset", "--hard", "HEAD"])?;
        self.run(&["clean", "-fd"]).map(|_| ())
    }

    pub fn reset_to(&self, sha: &str) -> Res<()> {
        self.run(&["reset", "--hard", sha])?;
        self.run(&["clean", "-fd"]).map(|_| ())
    }

    pub fn diff_u0(&self, from: &str, to: &str) -> Res<String> {
        self.run(&["diff", "-U0", "--no-color", from, to])
    }

    pub fn changed_files(&self, from: &str, to: &str) -> Res<Vec<String>> {
        let out = self.run(&["diff", "--name-only", "--no-renames", "-z", from, to])?;
        Ok(split_nul(&out))
    }

    /// `git push --no-verify <remote> <sha>:<refname>` under supervision, so a hung push
    /// cannot outlive `deadline` (plus `grace`). A deadline or interrupt gives a `GitError`
    /// whose stderr starts `deadline` or `interrupted`.
    pub fn push(
        &self,
        remote: &str,
        sha: &str,
        refname: &str,
        deadline: Instant,
        grace: Duration,
    ) -> Res<()> {
        static N: AtomicU64 = AtomicU64::new(0);
        let refspec = format!("{sha}:{refname}");
        let args = ["push", "--no-verify", remote, refspec.as_str()];
        let joined = args.join(" ");
        let fail = |code: Option<i32>, stderr: String| GitError {
            args: joined.clone(),
            code,
            stderr,
        };
        // stderr goes to a file, not a pipe: `supervise` only waits, so a full pipe would hang.
        let log = std::env::temp_dir().join(format!(
            "reqdrive-push-{}-{}.log",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let err = File::create(&log).map_err(|e| fail(None, e.to_string()))?;
        let mut cmd = self.base();
        cmd.args(args).stdout(Stdio::null()).stderr(err);
        let spawned = spawn_grouped(&mut cmd);
        drop(cmd);
        let result = match spawned {
            Err(e) => Err(fail(None, e.to_string())),
            Ok(mut child) => match supervise(&mut child, deadline, &|| false, grace) {
                Err(e) => Err(fail(None, e.to_string())),
                Ok(exit) => {
                    let mut text = String::new();
                    if let Ok(mut f) = File::open(&log) {
                        let mut buf = Vec::new();
                        let _ = f.read_to_end(&mut buf);
                        text = String::from_utf8_lossy(&buf).into_owned();
                    }
                    match exit.ended_by {
                        EndedBy::Normal if exit.code == Some(0) => Ok(()),
                        EndedBy::Normal => Err(fail(exit.code, text)),
                        EndedBy::Interrupted => {
                            Err(fail(exit.code, format!("interrupted: {}", text.trim())))
                        }
                        EndedBy::Deadline | EndedBy::TokenLimit => {
                            Err(fail(exit.code, format!("deadline: {}", text.trim())))
                        }
                    }
                }
            },
        };
        let _ = std::fs::remove_file(&log);
        result
    }
}

fn split_nul(s: &str) -> Vec<String> {
    s.split('\0')
        .filter(|p| !p.is_empty())
        .map(str::to_string)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    fn plain(dir: &Path, args: &[&str]) -> std::process::Output {
        let o = Command::new("git")
            .arg("-C")
            .arg(dir)
            .args(args)
            .output()
            .unwrap();
        assert!(
            o.status.success(),
            "git {args:?}: {}",
            String::from_utf8_lossy(&o.stderr)
        );
        o
    }

    struct Fixture {
        tmp: tempfile::TempDir,
        ws: PathBuf,
        hooks: PathBuf,
    }

    impl Fixture {
        fn new() -> Fixture {
            let tmp = tempfile::tempdir().unwrap();
            let ws = tmp.path().join("ws dir");
            let hooks = tmp.path().join("no-hooks");
            fs::create_dir_all(&ws).unwrap();
            fs::create_dir_all(&hooks).unwrap();
            plain(&ws, &["init", "-q", "-b", "main"]);
            plain(&ws, &["config", "user.name", "fixture"]);
            plain(&ws, &["config", "user.email", "fixture@localhost"]);
            plain(&ws, &["config", "commit.gpgsign", "false"]);
            fs::create_dir_all(ws.join("test")).unwrap();
            fs::write(ws.join("test/a.test"), "one\n").unwrap();
            fs::write(ws.join("keep.txt"), "keep\n").unwrap();
            plain(&ws, &["add", "-A"]);
            plain(&ws, &["commit", "-q", "-m", "init"]);
            Fixture { tmp, ws, hooks }
        }

        fn git(&self) -> Git {
            Git::new(&self.ws, &self.hooks)
        }
    }

    #[test]
    fn clean_detects_untracked() {
        let f = Fixture::new();
        let g = f.git();
        assert!(g.is_work_tree());
        assert!(g.is_clean().unwrap());
        fs::write(f.ws.join("new.txt"), "x").unwrap();
        assert!(!g.is_clean().unwrap());
    }

    #[test]
    fn switch_create_and_branch_sha() {
        let f = Fixture::new();
        let g = f.git();
        let head = g.head().unwrap();
        assert!(g.commit_exists(&head));
        assert!(!g.commit_exists("0000000000000000000000000000000000000001"));
        assert_eq!(g.branch_sha("feat/x").unwrap(), None);
        g.switch_create("feat/x", &head).unwrap();
        assert_eq!(g.branch_sha("feat/x").unwrap(), Some(head.clone()));
        assert_eq!(g.current_branch().unwrap(), Some("feat/x".to_string()));
        g.switch("main").unwrap();
        assert_eq!(g.current_branch().unwrap(), Some("main".to_string()));
        plain(&f.ws, &["checkout", "-q", "--detach"]);
        assert_eq!(g.current_branch().unwrap(), None);
    }

    #[test]
    fn staged_paths_lists_add_delete_rename() {
        let f = Fixture::new();
        let g = f.git();
        fs::create_dir_all(f.ws.join("src")).unwrap();
        plain(&f.ws, &["mv", "test/a.test", "src/a.txt"]);
        fs::write(f.ws.join("added.txt"), "a").unwrap();
        fs::remove_file(f.ws.join("keep.txt")).unwrap();
        g.stage_all().unwrap();
        let mut paths = g.staged_paths().unwrap();
        paths.sort();
        assert_eq!(
            paths,
            vec!["added.txt", "keep.txt", "src/a.txt", "test/a.test"]
        );
        assert!(g.staged_patch().unwrap().contains("diff --git"));
    }

    #[test]
    fn commit_works_without_identity_config() {
        let f = Fixture::new();
        let empty = f.tmp.path().join("empty.gitconfig");
        fs::write(&empty, "").unwrap();
        // Remove the fixture's repo-local identity so only the -c flags can supply it.
        plain(&f.ws, &["config", "--unset", "user.name"]);
        plain(&f.ws, &["config", "--unset", "user.email"]);
        let g = f.git().with_env(vec![
            ("GIT_CONFIG_GLOBAL".into(), empty.display().to_string()),
            ("GIT_CONFIG_NOSYSTEM".into(), "1".into()),
        ]);
        let before = g.head().unwrap();
        fs::write(f.ws.join("n.txt"), "n").unwrap();
        g.stage_all().unwrap();
        let sha = g.commit("msg").unwrap();
        assert_ne!(sha, before);
        assert_eq!(g.head().unwrap(), sha);
    }

    #[test]
    fn commit_bypasses_failing_hooks() {
        let f = Fixture::new();
        for name in ["pre-commit", "prepare-commit-msg"] {
            let p = f.ws.join(".git/hooks").join(name);
            fs::write(&p, "#!/bin/sh\nexit 1\n").unwrap();
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
            }
        }
        let g = f.git();
        fs::write(f.ws.join("n.txt"), "n").unwrap();
        g.stage_all().unwrap();
        assert!(g.commit("msg").is_ok());
    }

    #[test]
    fn reset_clean_removes_untracked_but_keeps_ignored() {
        let f = Fixture::new();
        let g = f.git();
        fs::write(f.ws.join(".gitignore"), "ignored.txt\n").unwrap();
        plain(&f.ws, &["add", "-A"]);
        plain(&f.ws, &["commit", "-q", "-m", "ignore"]);
        let base = g.head().unwrap();
        fs::write(f.ws.join("ignored.txt"), "i").unwrap();
        fs::write(f.ws.join("junk.txt"), "j").unwrap();
        fs::write(f.ws.join("keep.txt"), "changed").unwrap();
        g.reset_clean().unwrap();
        assert!(f.ws.join("ignored.txt").exists());
        assert!(!f.ws.join("junk.txt").exists());
        assert_eq!(fs::read_to_string(f.ws.join("keep.txt")).unwrap(), "keep\n");
        // reset_to goes back to an earlier commit.
        fs::write(f.ws.join("later.txt"), "l").unwrap();
        g.stage_all().unwrap();
        g.commit("later").unwrap();
        g.reset_to(&base).unwrap();
        assert_eq!(g.head().unwrap(), base);
        assert!(!f.ws.join("later.txt").exists());
    }

    #[test]
    fn diff_helpers() {
        let f = Fixture::new();
        let g = f.git();
        let a = g.head().unwrap();
        fs::write(f.ws.join("keep.txt"), "keep\nmore\n").unwrap();
        g.stage_all().unwrap();
        let b = g.commit("two").unwrap();
        assert_eq!(g.changed_files(&a, &b).unwrap(), vec!["keep.txt"]);
        assert!(g.diff_u0(&a, &b).unwrap().contains("+more"));
    }

    #[test]
    fn push_to_bare_remote_without_upstream() {
        let f = Fixture::new();
        let g = f.git();
        let bare = f.tmp.path().join("remote.git");
        fs::create_dir_all(&bare).unwrap();
        plain(&bare, &["init", "-q", "--bare"]);
        plain(&f.ws, &["remote", "add", "origin", bare.to_str().unwrap()]);
        let sha = g.head().unwrap();
        g.push(
            "origin",
            &sha,
            "refs/heads/pushed",
            Instant::now() + Duration::from_secs(30),
            Duration::from_secs(5),
        )
        .unwrap();
        let out = plain(&bare, &["rev-parse", "refs/heads/pushed"]);
        assert_eq!(String::from_utf8_lossy(&out.stdout).trim(), sha);
        let cfg = Command::new("git")
            .arg("-C")
            .arg(&f.ws)
            .args(["config", "--get", "branch.main.remote"])
            .output()
            .unwrap();
        assert!(!cfg.status.success());
        // A failing push carries stderr.
        let err = g
            .push(
                "nowhere",
                &sha,
                "refs/heads/x",
                Instant::now() + Duration::from_secs(30),
                Duration::from_secs(5),
            )
            .unwrap_err();
        assert!(err.code.is_some());
        assert!(!err.stderr.is_empty());
    }

    #[test]
    fn ref_format_rejects_bad_names() {
        let f = Fixture::new();
        let g = f.git();
        assert!(!g.ref_format_ok("a..b"));
        assert!(g.ref_format_ok("feat/ok"));
        assert!(g.ref_format_ok("refs/heads/ok"));
        assert!(!g.ref_format_ok("refs/heads/a b"));
    }
}
