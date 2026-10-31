//! The event stream: one JSON object per line, with a common envelope.

use crate::outcome::{Category, ResultEvent};
use serde::Serialize;
use serde_json::{json, Map, Value};
use std::fs::{File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::SystemTime;

const LOG_LINE_CAP: usize = 2000;

#[derive(Serialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Stage {
    Validate,
    Provision,
    Red,
    RedPublished,
    Green,
    Check,
    Deliver,
    Done,
}

#[derive(Serialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum WaitingOn {
    Agent,
    Tests,
    Push,
}

#[derive(Serialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LogStream {
    Agent,
    Test,
    System,
}

#[derive(Serialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ArtifactKind {
    TestsRef,
    Branch,
    CriteriaMap,
    LogFile,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct UsageRow {
    pub call_seq: Option<u64>,
    pub model_id: Option<String>,
    pub provider: String,
    pub prompt: Option<u64>,
    pub cached_prompt: Option<u64>,
    pub cache_write: Option<u64>,
    pub output: Option<u64>,
    pub thinking: Option<u64>,
    pub attributed: bool,
}

#[derive(Serialize, Debug, Clone)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    Progress {
        stage: Stage,
    },
    Heartbeat {
        waiting_on: WaitingOn,
    },
    Usage(UsageRow),
    Log {
        stream: LogStream,
        line: String,
    },
    Artifact {
        kind: ArtifactKind,
        #[serde(rename = "ref")]
        reference: String,
        sha: Option<String>,
    },
    Error {
        category: Category,
        retryable: bool,
        detail: String,
    },
}

struct Inner {
    out: Box<dyn Write + Send>,
    log: Option<(File, PathBuf)>,
    attempt_id: Option<String>,
    seq: u64,
    closed: bool,
}

impl Inner {
    /// Add the envelope (last, so it overrides the body), write one line, flush.
    fn write_line(&mut self, mut obj: Map<String, Value>) -> io::Result<Map<String, Value>> {
        let seq = self.seq + 1;
        obj.insert("v".into(), json!(1));
        obj.insert("attempt_id".into(), json!(self.attempt_id));
        obj.insert("seq".into(), json!(seq));
        obj.insert(
            "ts".into(),
            json!(humantime::format_rfc3339_millis(SystemTime::now()).to_string()),
        );
        let mut line = serde_json::to_string(&obj).map_err(io::Error::other)?;
        line.push('\n');
        self.out.write_all(line.as_bytes())?;
        self.out.flush()?;
        self.seq = seq;
        if let Some((file, _)) = self.log.as_mut() {
            file.write_all(line.as_bytes())?;
            file.flush()?;
        }
        Ok(obj)
    }
}

#[derive(Clone)]
pub struct Emitter(Arc<Mutex<Inner>>);

impl Emitter {
    pub fn new(out: Box<dyn Write + Send>) -> Emitter {
        Emitter(Arc::new(Mutex::new(Inner {
            out,
            log: None,
            attempt_id: None,
            seq: 0,
            closed: false,
        })))
    }

    fn lock(&self) -> MutexGuard<'_, Inner> {
        self.0.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn set_attempt_id(&self, id: &str) {
        self.lock().attempt_id = Some(id.to_string());
    }

    /// From now on every line is also appended to `path`.
    pub fn attach_log(&self, path: &Path) -> io::Result<()> {
        let file = OpenOptions::new().create(true).append(true).open(path)?;
        self.lock().log = Some((file, path.to_path_buf()));
        Ok(())
    }

    /// Does nothing after `finish`. A `Log` line is cut to 2 000 chars.
    pub fn emit(&self, mut ev: Event) -> io::Result<()> {
        if let Event::Log { line, .. } = &mut ev {
            if line.chars().count() > LOG_LINE_CAP {
                *line = line.chars().take(LOG_LINE_CAP).collect();
            }
        }
        let obj = match serde_json::to_value(&ev).map_err(io::Error::other)? {
            Value::Object(m) => m,
            _ => return Err(io::Error::other("event did not serialize to an object")),
        };
        let mut inner = self.lock();
        if inner.closed {
            return Ok(());
        }
        inner.write_line(obj).map(|_| ())
    }

    pub fn error(&self, category: Category, detail: impl Into<String>) -> io::Result<()> {
        self.emit(Event::Error {
            category,
            retryable: category.retryable(),
            detail: detail.into(),
        })
    }

    /// Write the result line (and `result.json` beside the attached log), then close.
    /// A second call writes nothing.
    pub fn finish(&self, result: &ResultEvent) -> io::Result<()> {
        let mut obj = match serde_json::to_value(result).map_err(io::Error::other)? {
            Value::Object(m) => m,
            _ => return Err(io::Error::other("result did not serialize to an object")),
        };
        obj.insert("type".into(), json!("result"));
        let mut inner = self.lock();
        if inner.closed {
            return Ok(());
        }
        inner.closed = true;
        let written = inner.write_line(obj)?;
        if let Some(dir) = inner
            .log
            .as_ref()
            .and_then(|(_, p)| p.parent().map(Path::to_path_buf))
        {
            let pretty = serde_json::to_string_pretty(&written).map_err(io::Error::other)?;
            std::fs::write(dir.join("result.json"), pretty)?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct SharedBuf(Arc<Mutex<Vec<u8>>>);

    impl Write for SharedBuf {
        fn write(&mut self, b: &[u8]) -> io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(b);
            Ok(b.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    impl SharedBuf {
        fn text(&self) -> String {
            String::from_utf8(self.0.lock().unwrap().clone()).unwrap()
        }
        fn lines(&self) -> Vec<serde_json::Value> {
            self.text()
                .lines()
                .map(|l| serde_json::from_str(l).unwrap())
                .collect()
        }
    }

    fn emitter() -> (Emitter, SharedBuf) {
        let buf = SharedBuf::default();
        (Emitter::new(Box::new(buf.clone())), buf)
    }

    fn log(line: &str) -> Event {
        Event::Log {
            stream: LogStream::System,
            line: line.to_string(),
        }
    }

    #[test]
    fn envelope_overrides_body() {
        let (em, buf) = emitter();
        em.set_attempt_id("att-1");
        em.emit(log("hi")).unwrap();
        let l = &buf.lines()[0];
        assert_eq!(l["seq"], 1);
        assert_eq!(l["v"], 1);
        assert_eq!(l["attempt_id"], "att-1");
        assert_eq!(l["type"], "log");
        assert_eq!(l["stream"], "system");
        humantime::parse_rfc3339(l["ts"].as_str().unwrap()).unwrap();
    }

    #[test]
    fn attempt_id_is_null_until_set() {
        let (em, buf) = emitter();
        em.emit(log("hi")).unwrap();
        assert!(buf.lines()[0]["attempt_id"].is_null());
    }

    #[test]
    fn seq_is_total_across_threads() {
        let (em, buf) = emitter();
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let em = em.clone();
                std::thread::spawn(move || {
                    for i in 0..50 {
                        em.emit(log(&format!("line {i}"))).unwrap();
                    }
                })
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
        let mut seqs: Vec<u64> = buf
            .lines()
            .iter()
            .map(|l| l["seq"].as_u64().unwrap())
            .collect();
        seqs.sort_unstable();
        assert_eq!(seqs, (1..=400).collect::<Vec<u64>>());
    }

    #[test]
    fn usage_unknowns_serialize_as_null() {
        let (em, buf) = emitter();
        em.emit(Event::Usage(UsageRow {
            call_seq: None,
            model_id: None,
            provider: "p".into(),
            prompt: None,
            cached_prompt: None,
            cache_write: None,
            output: None,
            thinking: None,
            attributed: false,
        }))
        .unwrap();
        let text = buf.text();
        assert!(text.contains("\"prompt\":null"), "{text}");
        assert!(text.contains("\"thinking\":null"), "{text}");
        assert!(text.contains("\"type\":\"usage\""), "{text}");
    }

    #[test]
    fn artifact_and_error_shapes() {
        let (em, buf) = emitter();
        em.emit(Event::Artifact {
            kind: ArtifactKind::TestsRef,
            reference: "refs/x".into(),
            sha: None,
        })
        .unwrap();
        em.error(Category::BaseBroken, "boom").unwrap();
        let ls = buf.lines();
        assert_eq!(ls[0]["type"], "artifact");
        assert_eq!(ls[0]["kind"], "tests_ref");
        assert_eq!(ls[0]["ref"], "refs/x");
        assert!(ls[0]["sha"].is_null());
        assert_eq!(ls[1]["type"], "error");
        assert_eq!(ls[1]["category"], "base_broken");
        assert_eq!(ls[1]["retryable"], false);
        assert_eq!(ls[1]["detail"], "boom");
    }

    #[test]
    fn log_line_is_truncated() {
        let (em, buf) = emitter();
        em.emit(log(&"x".repeat(5000))).unwrap();
        let n = buf.lines()[0]["line"].as_str().unwrap().chars().count();
        assert!(n <= 2000, "{n}");
    }

    #[test]
    fn finish_writes_once_and_closes() {
        let dir = tempfile::tempdir().unwrap();
        let (em, buf) = emitter();
        em.set_attempt_id("a");
        em.attach_log(&dir.path().join("events.log")).unwrap();
        em.emit(log("before")).unwrap();
        let r = ResultEvent::pushed("deadbeef".into());
        em.finish(&r).unwrap();
        let n = buf.lines().len();
        em.emit(log("after")).unwrap();
        em.finish(&r).unwrap();
        assert_eq!(buf.lines().len(), n);
        let last = buf.lines().pop().unwrap();
        assert_eq!(last["type"], "result");
        assert_eq!(last["outcome"], "pushed");
        assert_eq!(last["head_sha"], "deadbeef");
        assert_eq!(last["attempt_id"], "a");
        let rj: serde_json::Value =
            serde_json::from_str(&std::fs::read_to_string(dir.path().join("result.json")).unwrap())
                .unwrap();
        assert_eq!(rj, last);
        let logtext = std::fs::read_to_string(dir.path().join("events.log")).unwrap();
        assert_eq!(logtext.lines().count(), n);
        assert!(logtext
            .lines()
            .last()
            .unwrap()
            .contains("\"type\":\"result\""));
    }

    #[test]
    fn finish_without_log_skips_result_json() {
        let (em, buf) = emitter();
        em.finish(&ResultEvent::pushed("x".into())).unwrap();
        assert_eq!(buf.lines().len(), 1);
    }

    #[test]
    fn emitter_is_send_sync() {
        fn check<T: Send + Sync + Clone>() {}
        check::<Emitter>();
    }
}
