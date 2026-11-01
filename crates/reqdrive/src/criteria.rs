//! The criterion check: every acceptance-criterion id must appear in the lines the
//! tests commit added.

/// Lines of a `git diff -U0` that were added, without the leading `+` and any trailing `\r`.
/// The `+++` file header is not an added line.
pub fn added_lines(diff_u0: &str) -> String {
    let mut out = Vec::new();
    let mut prev = "";
    for l in diff_u0.lines() {
        // A real file header is `+++ ` right after `--- `; `+++i;` is an added `++i;`.
        let header = l.starts_with("+++") && prev.starts_with("--- ");
        if l.starts_with('+') && !header {
            out.push(l[1..].trim_end_matches('\r'));
        }
        prev = l;
    }
    out.join("\n")
}

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

fn contains_word(hay: &str, needle: &str) -> bool {
    let h = hay.as_bytes();
    hay.match_indices(needle).any(|(i, m)| {
        let before_ok = i == 0 || !is_word(h[i - 1]);
        let after_ok = h.get(i + m.len()).is_none_or(|b| !is_word(*b));
        before_ok && after_ok
    })
}

/// The ids that do not occur in `added`. An id occurs when neither neighbour is an ASCII
/// alphanumeric or `_` (the `grep -w` rule), so `AC-10` does not satisfy `AC-1`.
pub fn missing_ids(added: &str, ids: &[String]) -> Vec<String> {
    ids.iter()
        .filter(|id| !contains_word(added, id))
        .cloned()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ac10_does_not_satisfy_ac1() {
        assert_eq!(
            missing_ids("covers AC-10", &["AC-1".to_string()]),
            vec!["AC-1".to_string()]
        );
    }

    #[test]
    fn id_at_line_end_with_crlf() {
        let added = added_lines("+test AC-2\r\n");
        assert!(missing_ids(&added, &["AC-2".to_string()]).is_empty());
    }

    #[test]
    fn added_line_starting_with_plus_plus_is_kept() {
        let diff = "--- a/t.c\n+++ b/t.c\n@@ -1 +1 @@\n-x\n+++i; // AC-3\n";
        let added = added_lines(diff);
        assert_eq!(added, "++i; // AC-3");
        assert!(missing_ids(&added, &["AC-3".to_string()]).is_empty());
    }

    #[test]
    fn plus_plus_plus_header_ignored() {
        let diff = "--- a/t.rs\n+++ b/t.rs\n@@ -0,0 +1 @@\n+// AC-3\n";
        let added = added_lines(diff);
        assert_eq!(added, "// AC-3");
        assert!(!added.contains("b/t.rs"));
    }
}
