use serde::Deserialize;
use std::collections::HashSet;
use std::path::PathBuf;

pub const SCHEMA: &str = "story-work-order/0";

const EVIDENCE_CAP: usize = 8192;

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
    if wo.limits.wall_clock_secs == 0 {
        return Err("limits.wall_clock_secs must be greater than 0".into());
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
