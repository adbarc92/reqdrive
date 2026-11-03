use serde::Deserialize;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

pub const SCHEMA: &str = "story-work-order/0";

const EVIDENCE_CAP: usize = 8192;
/// The longest wall clock a work order may ask for: 7 days.
pub const MAX_WALL_CLOCK_SECS: u64 = 604_800;

#[derive(Debug, Clone, Deserialize)]
pub struct WorkOrder {
    pub schema: String,
    pub attempt_id: String,
    pub story: Story,
    pub workspace: PathBuf,
    pub state_dir: PathBuf,
    pub repo: Repo,
    pub base_commit: String,
    pub attempt_branch: String,
    pub tests_ref: String,
    #[serde(default)]
    pub failure_evidence: Vec<FailureEvidence>,
    pub inference: Inference,
    pub limits: LimitsSpec,
    pub test_command: Option<String>,
    #[serde(default)]
    pub test_paths: Vec<String>,
    #[serde(default)]
    pub frozen_paths: Vec<String>,
    #[serde(default)]
    pub denied_paths: Vec<String>,
    #[serde(default)]
    pub isolation: Isolation,
    #[serde(default)]
    pub agent_allow: Vec<String>,
    pub green_max_calls: Option<u32>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Story {
    pub id: String,
    pub title: String,
    pub description: String,
    pub acceptance_criteria: Vec<Criterion>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Criterion {
    pub id: String,
    pub text: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Repo {
    pub remote: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct FailureEvidence {
    pub attempt_id: String,
    pub summary: String,
    #[serde(default)]
    pub detail: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct Inference {
    pub allow: Vec<AllowEntry>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AllowEntry {
    pub provider: String,
    pub models: Vec<String>,
    pub base_url: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct LimitsSpec {
    pub turns: u32,
    pub wall_clock_secs: u64,
    pub tokens: u64,
}

#[derive(Debug, Clone, Copy, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Isolation {
    Container,
    #[default]
    None,
}

pub fn parse(json: &str) -> Result<WorkOrder, String> {
    serde_json::from_str(json).map_err(|e| format!("work order is not valid: {e}"))
}

fn valid_id(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'_' || b == b'-')
}

pub fn validate_shape(wo: &WorkOrder) -> Result<(), String> {
    if wo.schema != SCHEMA {
        return Err(format!("schema must be {SCHEMA:?}, got {:?}", wo.schema));
    }
    if !valid_id(&wo.attempt_id) {
        return Err("attempt_id must be non-empty and match [A-Za-z0-9._-]+".into());
    }
    if !valid_id(&wo.story.id) {
        return Err("story.id must be non-empty and match [A-Za-z0-9._-]+".into());
    }
    if wo.story.acceptance_criteria.is_empty() {
        return Err("story.acceptance_criteria must not be empty".into());
    }
    let mut seen = HashSet::new();
    for c in &wo.story.acceptance_criteria {
        if !valid_id(&c.id) {
            return Err(format!(
                "criterion id {:?} must be non-empty and match [A-Za-z0-9._-]+",
                c.id
            ));
        }
        if !seen.insert(c.id.as_str()) {
            return Err(format!(
                "story.acceptance_criteria has duplicate id {:?}",
                c.id
            ));
        }
    }
    for (i, e) in wo.failure_evidence.iter().enumerate() {
        if !valid_id(&e.attempt_id) {
            return Err(format!(
                "failure_evidence[{i}].attempt_id must be non-empty and match [A-Za-z0-9._-]+"
            ));
        }
    }
    let bc = &wo.base_commit;
    if bc.len() != 40 || !bc.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f')) {
        return Err("base_commit must be 40 lowercase hex characters".into());
    }
    if !wo.workspace.is_absolute() {
        return Err("workspace must be an absolute path".into());
    }
    if !wo.state_dir.is_absolute() {
        return Err("state_dir must be an absolute path".into());
    }
    if wo.state_dir.starts_with(&wo.workspace) {
        return Err("state_dir must not be inside workspace".into());
    }
    if wo.limits.turns == 0 {
        return Err("limits.turns must be greater than 0".into());
    }
    if wo.limits.wall_clock_secs == 0 || wo.limits.wall_clock_secs > MAX_WALL_CLOCK_SECS {
        return Err(format!(
            "limits.wall_clock_secs must be between 1 and {MAX_WALL_CLOCK_SECS} (7 days)"
        ));
    }
    if wo.limits.tokens == 0 {
        return Err("limits.tokens must be greater than 0".into());
    }
    if wo.attempt_branch.is_empty() {
        return Err("attempt_branch must not be empty".into());
    }
    if wo.tests_ref.is_empty() || !wo.tests_ref.starts_with("refs/") {
        return Err("tests_ref must be non-empty and start with refs/".into());
    }
    if wo.attempt_branch.starts_with("refs/") {
        return Err("attempt_branch must be a branch name, without refs/".into());
    }
    // A ref cannot be both a file and a directory: these could never both be pushed.
    let branch_ref = format!("refs/heads/{}", wo.attempt_branch);
    if wo.tests_ref == branch_ref
        || wo.tests_ref.starts_with(&format!("{branch_ref}/"))
        || branch_ref.starts_with(&format!("{}/", wo.tests_ref))
    {
        return Err(format!(
            "tests_ref {:?} collides with attempt_branch {:?} ({branch_ref})",
            wo.tests_ref, wo.attempt_branch
        ));
    }
    if wo.repo.remote.is_empty() {
        return Err("repo.remote must not be empty".into());
    }
    if let Some(n) = wo.green_max_calls {
        if !(1..=20).contains(&n) {
            return Err("green_max_calls must be between 1 and 20".into());
        }
    }
    Ok(())
}

/// Without isolation the test command and `agent_allow` become one comma-joined
/// `--allowedTools` value, so a comma in any of them would split a rule. `test_command` is the
/// resolved one (the work order's or `reqdrive.json`'s).
pub fn check_allow_rules(wo: &WorkOrder, test_command: &str) -> Result<(), String> {
    if wo.isolation != Isolation::None {
        return Ok(());
    }
    if test_command.contains(',') {
        return Err(format!(
            "test_command {test_command:?} contains ',', which would split its --allowedTools \
             rule; wrap it in a script"
        ));
    }
    if let Some(rule) = wo.agent_allow.iter().find(|r| r.contains(',')) {
        return Err(format!(
            "agent_allow rule {rule:?} contains ',', which would split it in --allowedTools"
        ));
    }
    Ok(())
}

/// What `/proc/1/cgroup` may mention inside a container.
const CGROUP_WORDS: [&str; 5] = ["docker", "kubepods", "containerd", "libpod", "lxc"];

/// Evidence that this process runs inside a container, looked for under `root` (`/` in
/// production) and in `env`. Returns a short description of the first signal found: the file
/// `/.dockerenv` or `/run/.containerenv`, a non-empty `container` variable, a container runtime
/// named in `/proc/1/cgroup`, or a non-empty `KUBERNETES_SERVICE_HOST`.
pub fn container_evidence(root: &Path, env: &dyn Fn(&str) -> Option<String>) -> Option<String> {
    let set = |name: &str| env(name).filter(|v| !v.is_empty());
    if root.join(".dockerenv").exists() {
        return Some("/.dockerenv".into());
    }
    if root.join("run").join(".containerenv").exists() {
        return Some("/run/.containerenv".into());
    }
    if let Some(v) = set("container") {
        return Some(format!("container={v}"));
    }
    if let Ok(text) = fs::read_to_string(root.join("proc").join("1").join("cgroup")) {
        if let Some(word) = CGROUP_WORDS.iter().find(|w| text.contains(*w)) {
            return Some(format!("/proc/1/cgroup mentions {word}"));
        }
    }
    if set("KUBERNETES_SERVICE_HOST").is_some() {
        return Some("KUBERNETES_SERVICE_HOST is set".into());
    }
    None
}

/// [`container_evidence`] for this process. There is no detection off Linux, so `None` there.
pub fn detect_container() -> Option<String> {
    #[cfg(target_os = "linux")]
    {
        container_evidence(Path::new("/"), &|name| std::env::var(name).ok())
    }
    #[cfg(not(target_os = "linux"))]
    {
        None
    }
}

/// Why `isolation: "container"` is refused when [`detect_container`] finds nothing.
pub fn no_container_detail() -> String {
    let checked = if cfg!(target_os = "linux") {
        "checked /.dockerenv, /run/.containerenv, $container, /proc/1/cgroup and \
         $KUBERNETES_SERVICE_HOST"
            .to_string()
    } else {
        format!(
            "detection runs only on Linux, and this is {}",
            std::env::consts::OS
        )
    };
    format!(r#"isolation is "container" but no container was detected ({checked})"#)
}

fn truncate_on_boundary(s: &mut String, max: usize) {
    if s.len() <= max {
        return;
    }
    let mut cut = max;
    while !s.is_char_boundary(cut) {
        cut -= 1;
    }
    s.truncate(cut);
}

/// Cap each failure-evidence entry at 8 192 bytes, cutting on a char boundary.
pub fn cap_evidence(wo: &mut WorkOrder) {
    for e in &mut wo.failure_evidence {
        truncate_on_boundary(&mut e.summary, EVIDENCE_CAP);
        truncate_on_boundary(&mut e.detail, EVIDENCE_CAP);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(windows)]
    const ROOT: &str = "C:/t";
    #[cfg(not(windows))]
    const ROOT: &str = "/t";

    fn base() -> serde_json::Value {
        serde_json::json!({
            "schema": "story-work-order/0",
            "attempt_id": "att-1",
            "story": {
                "id": "US-001",
                "title": "t",
                "description": "d",
                "acceptance_criteria": [{"id": "AC1", "text": "x"}, {"id": "AC2", "text": "y"}]
            },
            "workspace": format!("{ROOT}/ws"),
            "state_dir": format!("{ROOT}/state"),
            "repo": {"remote": "origin"},
            "base_commit": "0123456789abcdef0123456789abcdef01234567",
            "attempt_branch": "reqdrive/US-001",
            "tests_ref": "refs/reqdrive/tests/US-001",
            "inference": {"allow": [{"provider": "p", "models": ["m"]}]},
            "limits": {"turns": 10, "wall_clock_secs": 60, "tokens": 1000},
            "test_command": null,
            "extra_unknown": 1
        })
    }

    fn parsed(v: serde_json::Value) -> WorkOrder {
        parse(&v.to_string()).expect("parses")
    }

    fn rejects(mutate: impl FnOnce(&mut serde_json::Value), field: &str) {
        let mut v = base();
        mutate(&mut v);
        let wo = parsed(v);
        let err = validate_shape(&wo).expect_err("should reject");
        assert!(err.contains(field), "error {err:?} should name {field}");
    }

    #[test]
    fn parse_minimal_valid_order() {
        let wo = parsed(base());
        assert_eq!(wo.isolation, Isolation::None);
        assert!(wo.failure_evidence.is_empty());
        assert!(wo.test_command.is_none());
        assert!(wo.green_max_calls.is_none());
        assert!(wo.inference.allow[0].base_url.is_none());
        validate_shape(&wo).expect("valid");
    }

    #[test]
    fn parse_reports_json_errors() {
        assert!(parse("{").is_err());
        assert!(parse("{}").is_err());
    }

    #[test]
    fn parse_isolation_container() {
        let mut v = base();
        v["isolation"] = "container".into();
        assert_eq!(parsed(v).isolation, Isolation::Container);
    }

    #[test]
    fn shape_rejects_schema() {
        rejects(|v| v["schema"] = "other/1".into(), "schema");
    }

    #[test]
    fn shape_rejects_attempt_id() {
        rejects(|v| v["attempt_id"] = "".into(), "attempt_id");
        rejects(|v| v["attempt_id"] = "a b".into(), "attempt_id");
    }

    #[test]
    fn shape_rejects_evidence_attempt_id() {
        for bad in ["", "a b", "x\n## Evil", "a`b"] {
            rejects(
                |v| {
                    v["failure_evidence"] = serde_json::json!([
                        {"attempt_id": "ok-1", "summary": "s"},
                        {"attempt_id": bad, "summary": "s"}
                    ])
                },
                "failure_evidence[1].attempt_id",
            );
        }
        let mut v = base();
        v["failure_evidence"] = serde_json::json!([{"attempt_id": "att.0_1-x", "summary": "s"}]);
        validate_shape(&parsed(v)).expect("valid evidence id");
    }

    #[test]
    fn shape_rejects_story_id() {
        rejects(|v| v["story"]["id"] = "".into(), "story.id");
        rejects(|v| v["story"]["id"] = "a/b".into(), "story.id");
    }

    #[test]
    fn shape_rejects_criterion_id() {
        rejects(
            |v| v["story"]["acceptance_criteria"][0]["id"] = "".into(),
            "criterion",
        );
        rejects(
            |v| v["story"]["acceptance_criteria"][0]["id"] = "A C".into(),
            "criterion",
        );
    }

    #[test]
    fn shape_rejects_empty_criteria() {
        rejects(
            |v| v["story"]["acceptance_criteria"] = serde_json::json!([]),
            "acceptance_criteria",
        );
    }

    #[test]
    fn shape_rejects_duplicate_criteria() {
        rejects(
            |v| v["story"]["acceptance_criteria"][1]["id"] = "AC1".into(),
            "acceptance_criteria",
        );
    }

    #[test]
    fn shape_rejects_base_commit() {
        rejects(|v| v["base_commit"] = "abc".into(), "base_commit");
        rejects(
            |v| v["base_commit"] = "0123456789ABCDEF0123456789abcdef01234567".into(),
            "base_commit",
        );
        rejects(
            |v| v["base_commit"] = "g123456789abcdef0123456789abcdef01234567".into(),
            "base_commit",
        );
    }

    #[test]
    fn shape_rejects_relative_workspace() {
        rejects(|v| v["workspace"] = "ws".into(), "workspace");
    }

    #[test]
    fn shape_rejects_relative_state_dir() {
        rejects(|v| v["state_dir"] = "state".into(), "state_dir");
    }

    #[test]
    fn shape_rejects_state_dir_inside_workspace() {
        rejects(
            |v| v["state_dir"] = format!("{ROOT}/ws/.state").into(),
            "state_dir",
        );
        rejects(
            |v| v["state_dir"] = format!("{ROOT}/ws").into(),
            "state_dir",
        );
    }

    #[test]
    fn shape_allows_state_dir_sibling_with_shared_prefix() {
        let mut v = base();
        v["state_dir"] = format!("{ROOT}/ws-state").into();
        validate_shape(&parsed(v)).expect("component-wise, not string prefix");
    }

    #[test]
    fn shape_rejects_zero_limits() {
        rejects(|v| v["limits"]["turns"] = 0.into(), "limits.turns");
        rejects(
            |v| v["limits"]["wall_clock_secs"] = 0.into(),
            "limits.wall_clock_secs",
        );
        rejects(|v| v["limits"]["tokens"] = 0.into(), "limits.tokens");
        rejects(
            |v| v["limits"]["wall_clock_secs"] = (MAX_WALL_CLOCK_SECS + 1).into(),
            "limits.wall_clock_secs",
        );
        rejects(
            |v| v["limits"]["wall_clock_secs"] = u64::MAX.into(),
            "limits.wall_clock_secs",
        );
        let mut v = base();
        v["limits"]["wall_clock_secs"] = MAX_WALL_CLOCK_SECS.into();
        validate_shape(&parsed(v)).expect("7 days is allowed");
    }

    #[test]
    fn shape_rejects_empty_attempt_branch() {
        rejects(|v| v["attempt_branch"] = "".into(), "attempt_branch");
    }

    #[test]
    fn shape_rejects_bad_tests_ref() {
        rejects(|v| v["tests_ref"] = "".into(), "tests_ref");
        rejects(|v| v["tests_ref"] = "heads/x".into(), "tests_ref");
    }

    #[test]
    fn shape_rejects_tests_ref_colliding_with_attempt_branch() {
        rejects(
            |v| v["tests_ref"] = "refs/heads/reqdrive/US-001".into(),
            "tests_ref",
        );
        rejects(
            |v| v["tests_ref"] = "refs/heads/reqdrive/US-001/tests".into(),
            "tests_ref",
        );
        rejects(
            |v| v["tests_ref"] = "refs/heads/reqdrive".into(),
            "tests_ref",
        );
        rejects(
            |v| v["attempt_branch"] = "refs/heads/x".into(),
            "attempt_branch",
        );
        for ok in [
            "refs/heads/reqdrive/US-001.tests",
            "refs/heads/reqdrive/US-0010",
            "refs/reqdrive/tests/US-001",
        ] {
            let mut v = base();
            v["tests_ref"] = ok.into();
            validate_shape(&parsed(v)).expect(ok);
        }
    }

    #[test]
    fn shape_rejects_empty_remote() {
        rejects(|v| v["repo"]["remote"] = "".into(), "repo.remote");
    }

    #[test]
    fn shape_rejects_green_max_calls_out_of_range() {
        rejects(|v| v["green_max_calls"] = 0.into(), "green_max_calls");
        rejects(|v| v["green_max_calls"] = 21.into(), "green_max_calls");
        for ok in [1, 5, 20] {
            let mut v = base();
            v["green_max_calls"] = ok.into();
            validate_shape(&parsed(v)).expect("in range");
        }
    }

    #[test]
    fn allow_rules_reject_commas_without_isolation() {
        let wo = parsed(base());
        check_allow_rules(&wo, "npm test").expect("no comma");
        let err = check_allow_rules(&wo, "pytest -k 'a,b'").unwrap_err();
        assert!(err.contains("test_command"), "{err}");
        let mut v = base();
        v["agent_allow"] = serde_json::json!(["Bash(git status)", "Bash(ls a,b)"]);
        let err = check_allow_rules(&parsed(v), "npm test").unwrap_err();
        assert!(err.contains("agent_allow"), "{err}");
        let mut v = base();
        v["isolation"] = "container".into();
        v["agent_allow"] = serde_json::json!(["Bash(ls a,b)"]);
        check_allow_rules(&parsed(v), "pytest -k 'a,b'").expect("no --allowedTools in a container");
    }

    fn no_env(_: &str) -> Option<String> {
        None
    }

    fn evidence_with_env(name: &'static str, value: &'static str) -> Option<String> {
        let root = tempfile::tempdir().unwrap();
        container_evidence(root.path(), &|k| (k == name).then(|| value.to_string()))
    }

    fn evidence_with_file(rel: &[&str], content: &str) -> Option<String> {
        let root = tempfile::tempdir().unwrap();
        let path = rel.iter().fold(root.path().to_path_buf(), |p, c| p.join(c));
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(&path, content).unwrap();
        container_evidence(root.path(), &no_env)
    }

    #[test]
    fn container_evidence_none_on_a_bare_root() {
        let root = tempfile::tempdir().unwrap();
        assert_eq!(container_evidence(root.path(), &no_env), None);
    }

    #[test]
    fn container_evidence_dockerenv() {
        assert_eq!(
            evidence_with_file(&[".dockerenv"], "").as_deref(),
            Some("/.dockerenv")
        );
    }

    #[test]
    fn container_evidence_containerenv() {
        assert_eq!(
            evidence_with_file(&["run", ".containerenv"], "").as_deref(),
            Some("/run/.containerenv")
        );
    }

    #[test]
    fn container_evidence_container_env_var() {
        assert_eq!(
            evidence_with_env("container", "podman").as_deref(),
            Some("container=podman")
        );
        assert_eq!(evidence_with_env("container", ""), None);
    }

    #[test]
    fn container_evidence_kubernetes_env_var() {
        assert_eq!(
            evidence_with_env("KUBERNETES_SERVICE_HOST", "10.0.0.1").as_deref(),
            Some("KUBERNETES_SERVICE_HOST is set")
        );
        assert_eq!(evidence_with_env("KUBERNETES_SERVICE_HOST", ""), None);
    }

    #[test]
    fn container_evidence_cgroup() {
        for word in ["docker", "kubepods", "containerd", "libpod", "lxc"] {
            let cgroup = format!("0::/system.slice/{word}-abc123.scope\n");
            assert_eq!(
                evidence_with_file(&["proc", "1", "cgroup"], &cgroup),
                Some(format!("/proc/1/cgroup mentions {word}")),
                "{word}"
            );
        }
        assert_eq!(
            evidence_with_file(&["proc", "1", "cgroup"], "0::/init.scope\n"),
            None
        );
    }

    #[test]
    fn container_refusal_names_what_was_checked() {
        let detail = no_container_detail();
        assert!(
            detail.starts_with(r#"isolation is "container" but no container was detected"#),
            "{detail}"
        );
        if cfg!(target_os = "linux") {
            for signal in [
                "/.dockerenv",
                "/run/.containerenv",
                "container",
                "/proc/1/cgroup",
                "KUBERNETES_SERVICE_HOST",
            ] {
                assert!(detail.contains(signal), "{detail} should name {signal}");
            }
        } else {
            assert!(detail.contains("only on Linux"), "{detail}");
        }
    }

    #[cfg(not(target_os = "linux"))]
    #[test]
    fn detect_container_is_none_off_linux() {
        assert_eq!(detect_container(), None);
    }

    #[test]
    fn cap_evidence_cuts_on_char_boundary() {
        let mut v = base();
        v["failure_evidence"] = serde_json::json!([
            {"attempt_id": "a", "summary": "é".repeat(9000), "detail": "é".repeat(9000)},
            {"attempt_id": "b", "summary": "short"}
        ]);
        let mut wo = parsed(v);
        cap_evidence(&mut wo);
        let e = &wo.failure_evidence[0];
        assert!(e.detail.len() <= 8192);
        assert!(e.summary.len() <= 8192);
        assert!(e.detail.chars().all(|c| c == 'é'));
        assert_eq!(wo.failure_evidence[1].summary, "short");
        assert_eq!(wo.failure_evidence[1].detail, "");
    }
}
