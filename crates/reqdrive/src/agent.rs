//! The claude-code adapter: runs one agent call and meters its usage.

use crate::events::{Emitter, Event};
use crate::limits::Limits;
use crate::outcome::Category;
use crate::policy::Choice;
use crate::proc::{spawn_grouped, supervise, Exit};
use crate::stream::{budget_tokens, FinalResult, StreamParser};
use crate::workorder::{Isolation, WorkOrder};
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;

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
        limits: &Limits,
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
        let parser = StreamParser::new(first_call_seq, self.choice.provider_label.clone());

        let (exit, summary) = std::thread::scope(|s| {
            let reader = s.spawn(move || read_stream(stdout, transcript, parser, limits, emitter));
            let exit = supervise(
                &mut child,
                limits.deadline(),
                &|| limits.tokens_exhausted(),
                grace,
            );
            let parser = reader.join().expect("reader thread panicked");
            (exit, parser.finish())
        });
        let exit = exit?;

        for row in summary.flushed.iter().chain(summary.residue.iter()) {
            limits.add_tokens(budget_tokens(row));
            let _ = emitter.emit(Event::Usage(row.clone()));
        }
        if summary.final_result.is_none() {
            let _ = emitter.error(
                Category::UsageIncomplete,
                format!("call {index} ended without a result line; usage may be incomplete"),
            );
        }
        Ok(CallOutcome {
            exit,
            final_result: summary.final_result,
            next_call_seq: summary.next_call_seq,
        })
    }
}

/// Reads the agent's stdout to EOF: logs each line, feeds the parser, and meters each row.
fn read_stream(
    stdout: impl io::Read,
    mut transcript: File,
    mut parser: StreamParser,
    limits: &Limits,
    emitter: &Emitter,
) -> StreamParser {
    let mut reader = BufReader::new(stdout);
    let mut buf = Vec::new();
    loop {
        buf.clear();
        match reader.read_until(b'\n', &mut buf) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        let text = String::from_utf8_lossy(&buf);
        let line = text.trim_end_matches(['\n', '\r']);
        let _ = writeln!(transcript, "{line}");
        for row in parser.feed(line) {
            limits.add_tokens(budget_tokens(&row));
            let _ = emitter.emit(Event::Usage(row));
        }
    }
    parser
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
