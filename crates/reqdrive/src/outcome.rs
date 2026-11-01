use serde::Serialize;

#[derive(Serialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    Pushed,
    NoChange,
    Failed,
    Halted,
}

#[derive(Serialize, Debug, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Category {
    WorkOrderInvalid,
    BaseMissing,
    PolicyUnsatisfiable,
    BranchConflict,
    BaseBroken,
    RedInvalid,
    RedNotFailing,
    HarnessError,
    ScopeViolation,
    PushFailed,
    TestsModified,
    TestsDefective,
    TestsFailed,
    AgentError,
    LimitReached,
    Interrupted,
    UsageIncomplete,
}

impl Category {
    /// Whether a caller may usefully retry the same work order (spec section 3.5.1).
    pub fn retryable(self) -> bool {
        !matches!(
            self,
            Category::WorkOrderInvalid
                | Category::PolicyUnsatisfiable
                | Category::BranchConflict
                | Category::BaseBroken
                | Category::RedNotFailing
                | Category::TestsDefective
                | Category::LimitReached
        )
    }
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct Failure {
    pub category: Category,
    pub retryable: bool,
    pub detail: String,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct Evidence {
    pub test_command: String,
    pub exit_code: Option<i32>,
    pub criteria_map: Option<String>,
}

#[derive(Serialize, Debug, Clone, PartialEq)]
pub struct ResultEvent {
    pub outcome: Outcome,
    pub head_sha: Option<String>,
    pub tests_ref_sha: Option<String>,
    pub red_observed: Option<bool>,
    pub tests_defective: bool,
    pub failure: Option<Failure>,
    pub evidence: Option<Evidence>,
}

impl ResultEvent {
    fn empty(outcome: Outcome) -> Self {
        ResultEvent {
            outcome,
            head_sha: None,
            tests_ref_sha: None,
            red_observed: None,
            tests_defective: false,
            failure: None,
            evidence: None,
        }
    }

    pub fn end(outcome: Outcome, category: Category, detail: impl Into<String>) -> Self {
        ResultEvent {
            failure: Some(Failure {
                category,
                retryable: category.retryable(),
                detail: detail.into(),
            }),
            ..Self::empty(outcome)
        }
    }

    pub fn pushed(head_sha: String) -> Self {
        ResultEvent {
            head_sha: Some(head_sha),
            ..Self::empty(Outcome::Pushed)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn retryable_matches_spec_table() {
        use Category::*;
        let table = [
            (WorkOrderInvalid, false),
            (BaseMissing, true),
            (PolicyUnsatisfiable, false),
            (BranchConflict, false),
            (BaseBroken, false),
            (RedInvalid, true),
            (RedNotFailing, false),
            (HarnessError, true),
            (ScopeViolation, true),
            (PushFailed, true),
            (TestsModified, true),
            (TestsDefective, false),
            (TestsFailed, true),
            (AgentError, true),
            (LimitReached, false),
            (Interrupted, true),
            (UsageIncomplete, true),
        ];
        assert_eq!(table.len(), 17);
        for (c, want) in table {
            assert_eq!(c.retryable(), want, "{c:?}");
        }
    }

    #[test]
    fn result_serializes_unknowns_as_null() {
        let v = serde_json::to_value(ResultEvent::end(Outcome::Failed, Category::BaseBroken, "x"))
            .unwrap();
        assert_eq!(v["outcome"], "failed");
        assert!(v["head_sha"].is_null());
        assert!(v["tests_ref_sha"].is_null());
        assert!(v["red_observed"].is_null());
        assert!(v["evidence"].is_null());
        assert_eq!(v["tests_defective"], false);
        assert_eq!(v["failure"]["retryable"], false);
        assert_eq!(v["failure"]["category"], "base_broken");
        assert_eq!(v["failure"]["detail"], "x");
    }

    #[test]
    fn pushed_sets_head_sha_and_no_failure() {
        let r = ResultEvent::pushed("abc".into());
        assert_eq!(r.outcome, Outcome::Pushed);
        assert_eq!(r.head_sha.as_deref(), Some("abc"));
        let v = serde_json::to_value(&r).unwrap();
        assert_eq!(v["outcome"], "pushed");
        assert!(v["failure"].is_null());
    }

    #[test]
    fn outcomes_serialize_snake_case() {
        let s = |o| serde_json::to_value(o).unwrap();
        assert_eq!(s(Outcome::NoChange), "no_change");
        assert_eq!(s(Outcome::Halted), "halted");
        assert_eq!(s(Outcome::Pushed), "pushed");
    }
}
