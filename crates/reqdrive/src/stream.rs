//! Pure parser for `claude -p --output-format stream-json --verbose
//! --include-partial-messages` stdout. It turns the lines into usage rows.
//! Unknown is `None`, never 0. No I/O.

use crate::events::UsageRow;
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq)]
pub struct ModelTotals {
    pub input: Option<u64>,
    pub output: Option<u64>,
    pub cache_read: Option<u64>,
    pub cache_write: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FinalResult {
    pub subtype: String,
    pub is_error: bool,
    pub num_turns: Option<u32>,
    pub text: String,
    pub model_usage: BTreeMap<String, ModelTotals>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CallSummary {
    pub next_call_seq: u64,
    pub final_result: Option<FinalResult>,
    pub flushed: Vec<UsageRow>,
    pub residue: Vec<UsageRow>,
}

struct OpenCall {
    model: Option<String>,
    input: Option<u64>,
    cache_write: Option<u64>,
    cache_read: Option<u64>,
}

pub struct StreamParser {
    next_seq: u64,
    provider: String,
    open: Option<OpenCall>,
    final_result: Option<FinalResult>,
    /// Per model: attributed [input, output, cache_read, cache_write] sums.
    sums: BTreeMap<String, [u64; 4]>,
}

fn num(v: &Value, key: &str) -> Option<u64> {
    v.get(key).and_then(Value::as_u64)
}

/// `prompt - cached_prompt + output`, `None` as 0, saturating.
pub fn budget_tokens(row: &UsageRow) -> u64 {
    row.prompt
        .unwrap_or(0)
        .saturating_sub(row.cached_prompt.unwrap_or(0))
        + row.output.unwrap_or(0)
}

impl StreamParser {
    pub fn new(first_call_seq: u64, provider: String) -> Self {
        Self {
            next_seq: first_call_seq,
            provider,
            open: None,
            final_result: None,
            sums: BTreeMap::new(),
        }
    }

    /// Returns the rows completed by this line, in order. Lines that are not
    /// JSON objects are skipped.
    pub fn feed(&mut self, line: &str) -> Vec<UsageRow> {
        let Ok(v @ Value::Object(_)) = serde_json::from_str::<Value>(line.trim()) else {
            return Vec::new();
        };
        match v.get("type").and_then(Value::as_str) {
            Some("stream_event") => {
                let Some(ev) = v.get("event") else {
                    return Vec::new();
                };
                match ev.get("type").and_then(Value::as_str) {
                    Some("message_start") => {
                        let mut rows = Vec::new();
                        if let Some(prev) = self.open.take() {
                            rows.push(self.close(prev, None));
                        }
                        let msg = ev.get("message").unwrap_or(&Value::Null);
                        let usage = msg.get("usage").unwrap_or(&Value::Null);
                        self.open = Some(OpenCall {
                            model: msg.get("model").and_then(Value::as_str).map(String::from),
                            input: num(usage, "input_tokens"),
                            cache_write: num(usage, "cache_creation_input_tokens"),
                            cache_read: num(usage, "cache_read_input_tokens"),
                        });
                        rows
                    }
                    Some("message_delta") => match self.open.take() {
                        Some(call) => {
                            let out = ev.get("usage").and_then(|u| num(u, "output_tokens"));
                            vec![self.close(call, out)]
                        }
                        None => Vec::new(),
                    },
                    _ => Vec::new(),
                }
            }
            Some("result") => {
                self.final_result = Some(parse_result(&v));
                Vec::new()
            }
            _ => Vec::new(),
        }
    }

    fn close(&mut self, call: OpenCall, output: Option<u64>) -> UsageRow {
        let prompt = match (call.input, call.cache_write, call.cache_read) {
            (Some(i), Some(w), Some(r)) => Some(i + w + r),
            _ => None,
        };
        if let Some(model) = &call.model {
            let s = self.sums.entry(model.clone()).or_default();
            s[0] += call.input.unwrap_or(0);
            s[1] += output.unwrap_or(0);
            s[2] += call.cache_read.unwrap_or(0);
            s[3] += call.cache_write.unwrap_or(0);
        }
        let seq = self.next_seq;
        self.next_seq += 1;
        UsageRow {
            call_seq: Some(seq),
            model_id: call.model,
            provider: self.provider.clone(),
            prompt,
            cached_prompt: call.cache_read,
            cache_write: call.cache_write,
            output,
            thinking: None,
            attributed: true,
        }
    }

    pub fn finish(mut self) -> CallSummary {
        let mut flushed = Vec::new();
        if let Some(call) = self.open.take() {
            flushed.push(self.close(call, None));
        }
        let mut residue = Vec::new();
        if let Some(fr) = &self.final_result {
            for (model, t) in &fr.model_usage {
                let s = self.sums.get(model).copied().unwrap_or([0; 4]);
                let totals = [
                    t.input.unwrap_or(0),
                    t.output.unwrap_or(0),
                    t.cache_read.unwrap_or(0),
                    t.cache_write.unwrap_or(0),
                ];
                if totals.iter().zip(s.iter()).all(|(t, s)| t <= s) {
                    continue;
                }
                // A total the result did not report stays unknown in the residue.
                let d: Vec<Option<u64>> = [t.input, t.output, t.cache_read, t.cache_write]
                    .iter()
                    .zip(s.iter())
                    .map(|(t, s)| t.map(|t| t.saturating_sub(*s)))
                    .collect();
                let prompt = match (d[0], d[3], d[2]) {
                    (Some(i), Some(w), Some(r)) => Some(i + w + r),
                    _ => None,
                };
                residue.push(UsageRow {
                    call_seq: None,
                    model_id: Some(model.clone()),
                    provider: self.provider.clone(),
                    prompt,
                    cached_prompt: d[2],
                    cache_write: d[3],
                    output: d[1],
                    thinking: None,
                    attributed: false,
                });
            }
        }
        CallSummary {
            next_call_seq: self.next_seq,
            final_result: self.final_result,
            flushed,
            residue,
        }
    }
}

fn parse_result(v: &Value) -> FinalResult {
    let mut model_usage = BTreeMap::new();
    if let Some(Value::Object(m)) = v.get("modelUsage") {
        for (k, t) in m {
            model_usage.insert(
                k.clone(),
                ModelTotals {
                    input: num(t, "inputTokens"),
                    output: num(t, "outputTokens"),
                    cache_read: num(t, "cacheReadInputTokens"),
                    cache_write: num(t, "cacheCreationInputTokens"),
                },
            );
        }
    }
    FinalResult {
        subtype: v
            .get("subtype")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        is_error: v.get("is_error").and_then(Value::as_bool).unwrap_or(false),
        num_turns: num(v, "num_turns").and_then(|n| u32::try_from(n).ok()),
        text: v
            .get("result")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string(),
        model_usage,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const BASIC: &str = include_str!("../tests/fixtures/stream-basic.jsonl");

    fn run(text: &str) -> (Vec<UsageRow>, CallSummary) {
        let mut p = StreamParser::new(1, "anthropic".into());
        let mut rows = Vec::new();
        for l in text.lines() {
            rows.extend(p.feed(l));
        }
        (rows, p.finish())
    }

    #[test]
    fn basic_fixture_rows() {
        let (rows, sum) = run(BASIC);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].call_seq, Some(1));
        assert_eq!(rows[1].call_seq, Some(2));
        assert_eq!(rows[0].prompt, Some(35));
        assert_eq!(rows[0].cached_prompt, Some(20));
        assert_eq!(rows[0].cache_write, Some(5));
        assert_eq!(rows[0].output, Some(7));
        assert_eq!(rows[0].model_id.as_deref(), Some("claude-a"));
        assert_eq!(rows[0].provider, "anthropic");
        assert!(rows[0].attributed);
        assert_eq!(rows[1].prompt, Some(33));
        assert_eq!(rows[1].output, Some(4));
        assert_eq!(sum.next_call_seq, 3);
    }

    /// Captured from `claude` 2.1.296 on 2026-10-31 (`-p --output-format stream-json --verbose
    /// --include-partial-messages --model haiku --max-turns 1`), with local paths and hook
    /// output removed. Field paths are as the CLI writes them.
    const LIVE: &str = include_str!("../tests/fixtures/stream-live.jsonl");

    #[test]
    fn live_fixture_parses() {
        let (rows, sum) = run(LIVE);
        assert_eq!(rows.len(), 1);
        let r = &rows[0];
        assert_eq!(r.call_seq, Some(1));
        assert_eq!(r.model_id.as_deref(), Some("claude-haiku-5-5"));
        assert_eq!(r.prompt, Some(2 + 43_225));
        assert_eq!(r.cached_prompt, Some(0));
        assert_eq!(r.cache_write, Some(43_225));
        assert_eq!(r.output, Some(4));
        assert!(sum.flushed.is_empty());
        let fr = sum.final_result.as_ref().unwrap();
        assert_eq!(fr.subtype, "success");
        assert_eq!(fr.num_turns, Some(1));
        assert_eq!(fr.text, "ok");
        // modelUsage counts more than the streamed call (the CLI's own side calls), so the
        // difference is a residue row for the same model.
        assert_eq!(sum.residue.len(), 1);
        let res = &sum.residue[0];
        assert_eq!(res.model_id.as_deref(), Some("claude-haiku-5-5"));
        assert_eq!(res.prompt, Some(1_175 - 2));
        assert_eq!(res.output, Some(19 - 4));
        assert_eq!(res.cached_prompt, Some(0));
        assert_eq!(res.cache_write, Some(0));
        assert!(!res.attributed);
    }

    #[test]
    fn residue_for_unattributed_model() {
        let (_, sum) = run(BASIC);
        assert_eq!(sum.residue.len(), 1);
        let r = &sum.residue[0];
        assert_eq!(r.model_id.as_deref(), Some("claude-helper"));
        assert_eq!(r.prompt, Some(2));
        assert_eq!(r.output, Some(1));
        assert_eq!(r.call_seq, None);
        assert!(!r.attributed);
        assert_eq!(r.provider, "anthropic");
    }

    #[test]
    fn residue_unknown_totals_are_null() {
        let mut p = StreamParser::new(1, "p".into());
        p.feed(r#"{"type":"result","subtype":"success","modelUsage":{"other":{"inputTokens":4,"cacheReadInputTokens":3}}}"#);
        let sum = p.finish();
        assert_eq!(sum.residue.len(), 1);
        let r = &sum.residue[0];
        assert_eq!(r.prompt, None, "cache writes are unknown");
        assert_eq!(r.cached_prompt, Some(3));
        assert_eq!(r.cache_write, None);
        assert_eq!(r.output, None);
    }

    #[test]
    fn missing_cache_field_makes_prompt_null() {
        let mut p = StreamParser::new(1, "p".into());
        p.feed(r#"{"type":"stream_event","event":{"type":"message_start","message":{"model":"m","usage":{"input_tokens":10,"cache_read_input_tokens":null}}}}"#);
        let rows = p.feed(r#"{"type":"stream_event","event":{"type":"message_delta","usage":{"output_tokens":3}}}"#);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].prompt, None);
        assert_eq!(rows[0].cached_prompt, None);
        assert_eq!(rows[0].cache_write, None);
        assert_eq!(rows[0].output, Some(3));
    }

    #[test]
    fn start_without_delta_flushes_output_null() {
        let mut p = StreamParser::new(5, "p".into());
        assert!(p.feed(r#"{"type":"stream_event","event":{"type":"message_start","message":{"model":"m","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":2}}}}"#).is_empty());
        let sum = p.finish();
        assert_eq!(sum.flushed.len(), 1);
        assert_eq!(sum.flushed[0].output, None);
        assert_eq!(sum.flushed[0].call_seq, Some(5));
        assert_eq!(sum.flushed[0].prompt, Some(3));
        assert!(sum.flushed[0].attributed);
        assert_eq!(sum.next_call_seq, 6);
    }

    #[test]
    fn second_start_closes_open_call() {
        let start = r#"{"type":"stream_event","event":{"type":"message_start","message":{"model":"m","usage":{"input_tokens":1,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}}"#;
        let mut p = StreamParser::new(1, "p".into());
        assert!(p.feed(start).is_empty());
        let rows = p.feed(start);
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].output, None);
        assert_eq!(rows[0].call_seq, Some(1));
    }

    #[test]
    fn no_result_line_gives_none_final() {
        let (_, sum) = run("{\"type\":\"system\"}\nnot json\n");
        assert!(sum.final_result.is_none());
        assert!(sum.residue.is_empty());
        assert_eq!(sum.next_call_seq, 1);
    }

    #[test]
    fn budget_excludes_cache_reads() {
        let (rows, _) = run(BASIC);
        assert_eq!(budget_tokens(&rows[0]), 22);
    }

    #[test]
    fn budget_counts_none_as_zero_and_saturates() {
        let mut row = run(BASIC).0.remove(0);
        row.prompt = None;
        row.output = None;
        assert_eq!(budget_tokens(&row), 0);
        row.prompt = Some(1);
        row.cached_prompt = Some(9);
        row.output = Some(2);
        assert_eq!(budget_tokens(&row), 2);
    }

    #[test]
    fn final_result_reads_turns_and_text() {
        let (_, sum) = run(BASIC);
        let fr = sum.final_result.expect("result line");
        assert_eq!(fr.subtype, "success");
        assert!(!fr.is_error);
        assert_eq!(fr.num_turns, Some(2));
        assert_eq!(fr.text, "done");
        assert_eq!(fr.model_usage.len(), 2);
        assert_eq!(fr.model_usage["claude-a"].cache_read, Some(50));
    }
}
