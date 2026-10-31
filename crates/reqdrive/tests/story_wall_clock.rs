//! The wall-clock limit, in a test binary of its own. Cargo runs test binaries one at a time,
//! so sibling tests do not load the machine while this run's 5 s budget reaches Green.

mod common;

use common::*;
use serde_json::json;
use std::time::{Duration, Instant};

#[test]
fn wall_clock_limit_halts() {
    let f = Fixture::new();
    let mut order = f.order();
    order["limits"]["wall_clock_secs"] = json!(5);
    let mut slow = green_ok();
    slow["sleep_ms"] = json!(30000);
    let started = Instant::now();
    let (events, code) = f.run(&order, &script(vec![red_ok(), slow]));
    let took = started.elapsed();
    assert_eq!(code, 0);
    let r = result(&events);
    assert_eq!(r["outcome"], "halted", "{r}");
    assert_eq!(r["failure"]["category"], "limit_reached");
    assert_eq!(f.calls(), 2, "green was reached");
    let detail = r["failure"]["detail"].as_str().unwrap();
    assert!(detail.contains("agent call 2"), "{detail}");
    assert!(took < Duration::from_secs(8), "took {took:?}");
    assert!(
        r["head_sha"].is_null(),
        "no evidence push after the deadline"
    );
    assert!(!has_feat_on_remote(&f));
}
