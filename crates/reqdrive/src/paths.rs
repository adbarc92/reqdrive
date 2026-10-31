use crate::workorder::WorkOrder;

pub const DEFAULT_DENIED: [&str; 5] = [".github", ".husky", ".claude", ".mcp.json", ".gitmodules"];

fn norm(s: &str) -> String {
    s.replace('\\', "/")
}

/// True if `path == prefix` or `path` starts with `prefix + "/"`. `\` counts as `/`, and a
/// trailing `/` on `prefix` is ignored. An empty prefix matches nothing.
pub fn under(path: &str, prefix: &str) -> bool {
    let path = norm(path);
    let prefix = norm(prefix);
    let prefix = prefix.trim_end_matches('/');
    if prefix.is_empty() {
        return false;
    }
    path == prefix
        || path
            .strip_prefix(prefix)
            .is_some_and(|rest| rest.starts_with('/'))
}

fn under_any(path: &str, prefixes: &[String]) -> bool {
    prefixes.iter().any(|p| under(path, p))
}

#[derive(Debug, Clone)]
pub struct PathRules {
    pub denied: Vec<String>,
    pub frozen: Vec<String>,
    pub tests: Vec<String>,
}

impl PathRules {
    pub fn from_order(wo: &WorkOrder) -> PathRules {
        let mut denied: Vec<String> = DEFAULT_DENIED.iter().map(|s| s.to_string()).collect();
        denied.extend(wo.denied_paths.iter().cloned());
        PathRules {
            denied,
            frozen: wo.frozen_paths.clone(),
            tests: wo.test_paths.clone(),
        }
    }

    /// Paths under a denied prefix.
    pub fn denied_hits(&self, paths: &[String]) -> Vec<String> {
        paths
            .iter()
            .filter(|p| under_any(p, &self.denied))
            .cloned()
            .collect()
    }

    /// Paths under neither `tests` nor `frozen`. Empty when `tests` is empty; the caller warns.
    pub fn red_violations(&self, paths: &[String]) -> Vec<String> {
        if self.tests.is_empty() {
            return Vec::new();
        }
        paths
            .iter()
            .filter(|p| !under_any(p, &self.tests) && !under_any(p, &self.frozen))
            .cloned()
            .collect()
    }

    /// Paths that are red files, or under `tests` or `frozen`.
    pub fn green_violations(&self, paths: &[String], red_files: &[String]) -> Vec<String> {
        let red: Vec<String> = red_files.iter().map(|f| norm(f)).collect();
        paths
            .iter()
            .filter(|p| {
                red.contains(&norm(p)) || under_any(p, &self.tests) || under_any(p, &self.frozen)
            })
            .cloned()
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::workorder::WorkOrder;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    fn rules() -> PathRules {
        PathRules {
            denied: s(&[".github", ".mcp.json"]),
            frozen: s(&["fixtures"]),
            tests: s(&["tests"]),
        }
    }

    #[test]
    fn under_prefix_semantics() {
        assert!(under("src/auth", "src/auth"));
        assert!(under("src/auth/x", "src/auth/"));
        assert!(!under("src/authz", "src/auth"));
        assert!(under("a\\b", "a"));
        assert!(!under("a", ""));
    }

    #[test]
    fn denied_defaults_hit_workflows() {
        let wo: WorkOrder = serde_json::from_value(serde_json::json!({
            "schema": "story-work-order/0", "attempt_id": "a1",
            "story": {"id":"S","title":"t","description":"d","acceptance_criteria":[]},
            "workspace": "/w", "state_dir": "/s", "repo": {"remote": "origin"},
            "base_commit": "abc", "attempt_branch": "b", "tests_ref": "r",
            "inference": {"allow": []},
            "limits": {"turns": 1, "wall_clock_secs": 1, "tokens": 1}
        }))
        .unwrap();
        let r = PathRules::from_order(&wo);
        let hits = r.denied_hits(&s(&[".github/workflows/ci.yml", ".mcp.json", "src/x.rs"]));
        assert_eq!(hits, s(&[".github/workflows/ci.yml", ".mcp.json"]));
        assert_eq!(r.denied.len(), DEFAULT_DENIED.len());
    }

    #[test]
    fn red_violations_outside_tests_and_frozen() {
        let r = rules();
        let v = r.red_violations(&s(&["tests/a.rs", "fixtures/f", "src/x.rs"]));
        assert_eq!(v, s(&["src/x.rs"]));
    }

    #[test]
    fn red_violations_empty_when_no_test_paths() {
        let mut r = rules();
        r.tests.clear();
        assert!(r.red_violations(&s(&["src/x.rs"])).is_empty());
    }

    #[test]
    fn green_violations_cover_red_files_tests_and_frozen() {
        let r = rules();
        let v = r.green_violations(
            &s(&[
                "src/x.rs",
                "red/one.rs",
                "tests/a.rs",
                "fixtures/f",
                "src/ok.rs",
            ]),
            &s(&["red/one.rs"]),
        );
        assert_eq!(v, s(&["red/one.rs", "tests/a.rs", "fixtures/f"]));
    }
}
