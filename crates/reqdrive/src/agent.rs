//! The claude-code adapter: runs one agent call and meters its usage.

use crate::events::{Emitter, Event};
use crate::limits::Limits;
use crate::outcome::Category;
use crate::policy::Choice;
use crate::proc::{kill_all, scrub_repo_env, spawn_grouped, supervise, Exit};
use crate::stream::{budget_tokens, FinalResult, StreamParser};
use crate::workorder::{Isolation, WorkOrder};
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// The least time the stdout reader is given to finish after the agent exits.
const READER_WAIT_MIN: Duration = Duration::from_secs(1);
const READER_POLL: Duration = Duration::from_millis(10);

pub struct ClaudeCode {
    pub bin: PathBuf,
    pub choice: Choice,
    pub permission_args: Vec<String>,
    /// Extra child environment, applied last. Empty in production; tests set it.
    pub extra_env: Vec<(String, String)>,
}

pub struct CallOutcome {
    pub exit: Exit,
    pub final_result: Option<FinalResult>,
    pub next_call_seq: u64,
}

impl ClaudeCode {
    pub fn new(wo: &WorkOrder, choice: Choice, bin: PathBuf, test_command: &str) -> Self {
        let permission_args = match wo.isolation {
            Isolation::Container => vec!["--permission-mode".into(), "bypassPermissions".into()],
            Isolation::None => {
                let mut rules = vec![
                    format!("Bash({test_command})"),
                    format!("Bash({test_command} *)"),
                ];
                rules.extend(wo.agent_allow.iter().cloned());
                vec![
                    "--permission-mode".into(),
                    "acceptEdits".into(),
                    "--allowedTools".into(),
                    rules.join(","),
                ]
            }
        };
        Self {
            bin,
            choice,
            permission_args,
            extra_env: Vec::new(),
        }
    }

    pub fn args(&self, max_turns: u32) -> Vec<String> {
        let mut a: Vec<String> = [
            "-p",
            "--output-format",
            "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--model",
            &self.choice.model,
            "--max-turns",
            &max_turns.to_string(),
            "--disallowedTools",
            "Agent,Skill",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();
        a.extend(self.permission_args.iter().cloned());
        a
    }

    #[allow(clippy::too_many_arguments)]
    pub fn run(
        &self,
        ws: &Path,
        state_dir: &Path,
        index: u32,
        prompt: &str,
        max_turns: u32,
        first_call_seq: u64,
        limits: &Arc<Limits>,
        emitter: &Emitter,
        grace: Duration,
    ) -> io::Result<CallOutcome> {
        let prompt_path = state_dir.join(format!("call-{index}.prompt.md"));
        fs::write(&prompt_path, prompt)?;
        let transcript = File::create(state_dir.join(format!("call-{index}.jsonl")))?;

        let mut cmd = Command::new(&self.bin);
        cmd.args(self.args(max_turns))
            .current_dir(ws)
            .stdin(File::open(&prompt_path)?)
            .stdout(Stdio::piped())
            .stderr(File::create(
                state_dir.join(format!("call-{index}.stderr.log")),
            )?);
        scrub_repo_env(&mut cmd);
        for name in &self.choice.remove_env {
            cmd.env_remove(name);
        }
        for (k, v) in &self.choice.set_env {
            cmd.env(k, v);
        }
        cmd.env("CI", "true")
            .env("CLAUDE_CODE_DISABLE_BACKGROUND_TASKS", "1");
        for (k, v) in &self.extra_env {
            cmd.env(k, v);
        }

        let mut child = spawn_grouped(&mut cmd)?;
        let stdout = child.stdout.take().expect("stdout is piped");
        // The reader owns the parser only through this slot. Whoever takes the parser out
        // stops the reader feeding it, so a reader stuck on a pipe some leftover process
        // still holds can be abandoned without losing what it already read.
        let slot = Arc::new(Mutex::new(Some(StreamParser::new(
            first_call_seq,
            self.choice.provider_label.clone(),
        ))));
        let reader = {
            let (slot, limits, emitter) = (slot.clone(), limits.clone(), emitter.clone());
            std::thread::spawn(move || read_stream(stdout, transcript, &slot, &limits, &emitter))
        };
        let exit = supervise(
            &mut child,
            limits.deadline(),
            &|| limits.tokens_exhausted(),
            grace,
        );
        if exit.is_err() {
            kill_all(&mut child);
            let _ = child.wait();
        }

        // The agent has exited. Its stdout reaches EOF unless something it started still
        // holds the pipe; give the reader `grace` (at least 1 s) to finish, then stop waiting.
        let until = Instant::now() + grace.max(READER_WAIT_MIN);
        while !reader.is_finished() && Instant::now() < until {
            std::thread::sleep(READER_POLL);
        }
        let mut incomplete: Vec<String> = Vec::new();
        if reader.is_finished() {
            if reader.join().is_err() {
                incomplete.push(format!(
                    "call {index}: the agent stdout reader panicked; usage may be incomplete"
                ));
            }
        } else {
            incomplete.push(format!(
                "call {index}: agent stdout still open after exit; stopped reading it, so usage \
                 may be incomplete"
            ));
        }
        let parser = slot.lock().unwrap_or_else(|e| e.into_inner()).take();
        let summary = parser.map(StreamParser::finish);

        for row in summary
            .iter()
            .flat_map(|s| s.flushed.iter().chain(s.residue.iter()))
        {
            limits.add_tokens(budget_tokens(row));
            let _ = emitter.emit(Event::Usage(row.clone()));
        }
        for detail in incomplete {
            let _ = emitter.error(Category::UsageIncomplete, detail);
        }
        let exit = exit?;
        let final_result = summary.as_ref().and_then(|s| s.final_result.clone());
        if final_result.is_none() {
            let _ = emitter.error(
                Category::UsageIncomplete,
                format!("call {index} ended without a result line; usage may be incomplete"),
            );
        }
        Ok(CallOutcome {
            exit,
            final_result,
            next_call_seq: summary.map_or(first_call_seq, |s| s.next_call_seq),
        })
    }
}

/// Reads the agent's stdout to EOF: logs each line, feeds the parser, and meters each row.
/// Stops as soon as the parser has been taken out of `slot`.
fn read_stream(
    stdout: impl io::Read,
    mut transcript: File,
    slot: &Mutex<Option<StreamParser>>,
    limits: &Limits,
    emitter: &Emitter,
) {
    let mut reader = BufReader::new(stdout);
    let mut buf = Vec::new();
    loop {
        buf.clear();
        match reader.read_until(b'\n', &mut buf) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        let mut guard = slot.lock().unwrap_or_else(|e| e.into_inner());
        let Some(parser) = guard.as_mut() else {
            break;
        };
        let text = String::from_utf8_lossy(&buf);
        let line = text.trim_end_matches(['\n', '\r']);
        let _ = writeln!(transcript, "{line}");
        for row in parser.feed(line) {
            limits.add_tokens(budget_tokens(&row));
            let _ = emitter.emit(Event::Usage(row));
        }
    }
}

pub fn bin_from_env() -> PathBuf {
    std::env::var_os("REQDRIVE_CLAUDE_BIN")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("claude"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workorder::parse;

    fn wo(isolation: &str, allow: &str) -> WorkOrder {
        parse(&format!(
            r#"{{"schema":"story-work-order/0","attempt_id":"a","story":{{"id":"s","title":"t","description":"d",
            "acceptance_criteria":[{{"id":"c1","text":"x"}}]}},"workspace":"w","state_dir":"s",
            "repo":{{"remote":"r"}},"base_commit":"b","attempt_branch":"br","tests_ref":"t",
            "inference":{{"allow":[{{"provider":"anthropic","models":["sonnet"]}}]}},
            "limits":{{"turns":10,"wall_clock_secs":60,"tokens":1000}},
            "isolation":"{isolation}","agent_allow":[{allow}]}}"#
        ))
        .unwrap()
    }

    fn choice() -> Choice {
        Choice {
            provider_label: "anthropic".into(),
            model: "sonnet".into(),
            set_env: vec![],
            remove_env: vec![],
        }
    }

    #[test]
    fn args_container_bypass() {
        let cc = ClaudeCode::new(&wo("container", ""), choice(), "claude".into(), "npm test");
        let a = cc.args(7);
        assert_eq!(
            &a[a.len() - 2..],
            ["--permission-mode", "bypassPermissions"]
        );
        assert!(!a.iter().any(|x| x == "--allowedTools"));
        assert!(a.windows(2).any(|w| w == ["--max-turns", "7"]));
        assert!(a.windows(2).any(|w| w == ["--model", "sonnet"]));
    }

    #[test]
    fn args_default_allows_test_prefix() {
        let cc = ClaudeCode::new(
            &wo("none", r#""Bash(git status)""#),
            choice(),
            "claude".into(),
            "npm test",
        );
        let a = cc.args(3);
        assert!(a
            .iter()
            .any(|x| x == "Bash(npm test),Bash(npm test *),Bash(git status)"));
        assert!(a
            .windows(2)
            .any(|w| w == ["--permission-mode", "acceptEdits"]));
        assert!(a
            .windows(2)
            .any(|w| w == ["--disallowedTools", "Agent,Skill"]));
    }
}
