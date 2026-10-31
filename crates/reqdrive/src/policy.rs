//! Inference policy: picks the first allowed provider/model pair the claude-code adapter can run.

use crate::workorder::{AllowEntry, Inference};

const FLAGS: [&str; 3] = [
    "CLAUDE_CODE_USE_BEDROCK",
    "CLAUDE_CODE_USE_VERTEX",
    "CLAUDE_CODE_USE_FOUNDRY",
];
const BASE_URL: &str = "ANTHROPIC_BASE_URL";

/// The provider and model to run, and how to set the child's environment for them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Choice {
    pub provider_label: String,
    pub model: String,
    pub set_env: Vec<(String, String)>,
    pub remove_env: Vec<&'static str>,
}

fn is_claude_model(model: &str) -> bool {
    model.starts_with("claude-") || matches!(model, "sonnet" | "opus" | "haiku" | "fable")
}

/// The `host[:port]` part of a URL: no scheme, credentials, path, query or fragment.
fn host_of(url: &str) -> String {
    let rest = url.split_once("://").map_or(url, |(_, r)| r);
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    authority
        .rsplit_once('@')
        .map_or(authority, |(_, h)| h)
        .to_string()
}

fn try_entry(e: &AllowEntry) -> Result<Choice, String> {
    let model = match e.models.first() {
        Some(m) if is_claude_model(m) => m.clone(),
        Some(m) => return Err(format!("model {m:?} is not a Claude model")),
        None => return Err("no models listed".into()),
    };
    let provider = e.provider.as_str();
    let (label, set_env, remove_env) = match provider {
        "anthropic" => (
            provider.to_string(),
            Vec::new(),
            vec![BASE_URL, FLAGS[0], FLAGS[1], FLAGS[2]],
        ),
        "bedrock" | "vertex" | "foundry" => {
            let on = format!("CLAUDE_CODE_USE_{}", provider.to_uppercase());
            let mut remove: Vec<&'static str> =
                FLAGS.iter().copied().filter(|f| *f != on).collect();
            remove.push(BASE_URL);
            (provider.to_string(), vec![(on, "1".to_string())], remove)
        }
        "gateway" => {
            let Some(url) = e.base_url.as_deref().filter(|u| !u.is_empty()) else {
                return Err("gateway needs a base_url".into());
            };
            (
                format!("gateway:{}", host_of(url)),
                vec![(BASE_URL.to_string(), url.to_string())],
                FLAGS.to_vec(),
            )
        }
        other => return Err(format!("provider {other:?} is not supported")),
    };
    Ok(Choice {
        provider_label: label,
        model,
        set_env,
        remove_env,
    })
}

/// Takes the first allow entry that names a supported provider and a Claude model first.
pub fn choose(inf: &Inference) -> Result<Choice, String> {
    let mut reasons = Vec::new();
    for e in &inf.allow {
        match try_entry(e) {
            Ok(c) => return Ok(c),
            Err(why) => reasons.push(format!("{}: {why}", e.provider)),
        }
    }
    if reasons.is_empty() {
        return Err("inference.allow is empty".into());
    }
    Err(format!(
        "no inference entry can run on claude-code ({})",
        reasons.join("; ")
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(provider: &str, models: &[&str], base_url: Option<&str>) -> AllowEntry {
        AllowEntry {
            provider: provider.into(),
            models: models.iter().map(|m| m.to_string()).collect(),
            base_url: base_url.map(String::from),
        }
    }

    fn inf(allow: Vec<AllowEntry>) -> Inference {
        Inference { allow }
    }

    #[test]
    fn choose_refuses_local_only() {
        let err = choose(&inf(vec![entry("ollama", &["qwen3-coder"], None)])).unwrap_err();
        assert!(err.contains("ollama"), "{err}");
    }

    #[test]
    fn choose_refuses_non_claude_model_on_gateway() {
        let err = choose(&inf(vec![entry(
            "gateway",
            &["gpt-5"],
            Some("https://gw.example.com/v1"),
        )]))
        .unwrap_err();
        assert!(err.contains("gateway") && err.contains("gpt-5"), "{err}");
    }

    #[test]
    fn choose_gateway_label_uses_host() {
        let c = choose(&inf(vec![entry(
            "gateway",
            &["sonnet"],
            Some("https://gw.example.com:8443/v1/x"),
        )]))
        .unwrap();
        assert_eq!(c.provider_label, "gateway:gw.example.com:8443");
        assert_eq!(
            c.set_env,
            vec![(
                "ANTHROPIC_BASE_URL".to_string(),
                "https://gw.example.com:8443/v1/x".to_string()
            )]
        );
        assert_eq!(c.remove_env, FLAGS.to_vec());
    }

    #[test]
    fn choose_skips_bad_entry_takes_next() {
        let c = choose(&inf(vec![
            entry("ollama", &["qwen3-coder"], None),
            entry("bedrock", &["claude-sonnet-4"], None),
        ]))
        .unwrap();
        assert_eq!(c.provider_label, "bedrock");
        assert_eq!(c.model, "claude-sonnet-4");
        assert_eq!(
            c.set_env,
            vec![("CLAUDE_CODE_USE_BEDROCK".to_string(), "1".to_string())]
        );
        assert!(c.remove_env.contains(&"CLAUDE_CODE_USE_VERTEX"));
        assert!(c.remove_env.contains(&"CLAUDE_CODE_USE_FOUNDRY"));
        assert!(c.remove_env.contains(&"ANTHROPIC_BASE_URL"));
        assert!(!c.remove_env.contains(&"CLAUDE_CODE_USE_BEDROCK"));
    }

    #[test]
    fn choose_anthropic_removes_everything() {
        let c = choose(&inf(vec![entry("anthropic", &["opus"], None)])).unwrap();
        assert!(c.set_env.is_empty());
        assert_eq!(c.remove_env.len(), 4);
    }

    #[test]
    fn choose_gateway_without_base_url_is_refused() {
        let err = choose(&inf(vec![entry("gateway", &["sonnet"], None)])).unwrap_err();
        assert!(err.contains("base_url"), "{err}");
    }
}
