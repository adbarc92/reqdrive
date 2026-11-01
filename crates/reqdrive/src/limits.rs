//! The attempt's budget: wall clock, turns and tokens. The counters are atomics, so a
//! `&Limits` can be shared with the stream reader thread.

use crate::workorder::LimitsSpec;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::time::{Duration, Instant};

#[derive(Debug)]
pub struct Limits {
    deadline: Instant,
    turns_left: AtomicU32,
    token_limit: u64,
    tokens_used: AtomicU64,
}

impl Limits {
    pub fn new(spec: &LimitsSpec, start: Instant) -> Self {
        Self {
            deadline: start + Duration::from_secs(spec.wall_clock_secs),
            turns_left: AtomicU32::new(spec.turns),
            token_limit: spec.tokens,
            tokens_used: AtomicU64::new(0),
        }
    }

    pub fn deadline(&self) -> Instant {
        self.deadline
    }

    /// `None` at or after the deadline.
    pub fn remaining(&self) -> Option<Duration> {
        self.deadline
            .checked_duration_since(Instant::now())
            .filter(|d| !d.is_zero())
    }

    pub fn turns_left(&self) -> u32 {
        self.turns_left.load(Ordering::SeqCst)
    }

    /// Saturates at 0.
    pub fn spend_turns(&self, n: u32) {
        let _ = self
            .turns_left
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |t| {
                Some(t.saturating_sub(n))
            });
    }

    pub fn add_tokens(&self, n: u64) {
        let _ = self
            .tokens_used
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |t| {
                Some(t.saturating_add(n))
            });
    }

    /// True once the tokens used reach the limit.
    pub fn tokens_exhausted(&self) -> bool {
        self.tokens_used() >= self.token_limit
    }

    pub fn tokens_used(&self) -> u64 {
        self.tokens_used.load(Ordering::SeqCst)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec(turns: u32, secs: u64, tokens: u64) -> LimitsSpec {
        LimitsSpec {
            turns,
            wall_clock_secs: secs,
            tokens,
        }
    }

    #[test]
    fn limits_remaining_none_after_deadline() {
        let now = Instant::now();
        let l = Limits::new(&spec(5, 60, 100), now);
        assert_eq!(l.deadline(), now + Duration::from_secs(60));
        assert!(l.remaining().is_some());

        let past = Instant::now() - Duration::from_secs(10);
        let l = Limits::new(&spec(5, 1, 100), past);
        assert_eq!(l.remaining(), None);

        let l = Limits::new(&spec(5, 0, 100), Instant::now());
        assert_eq!(l.remaining(), None);
    }

    #[test]
    fn limits_tokens_exhausted_at_limit() {
        let l = Limits::new(&spec(5, 60, 100), Instant::now());
        assert!(!l.tokens_exhausted());
        l.add_tokens(99);
        assert_eq!(l.tokens_used(), 99);
        assert!(!l.tokens_exhausted());
        l.add_tokens(1);
        assert_eq!(l.tokens_used(), 100);
        assert!(l.tokens_exhausted());
        l.add_tokens(50);
        assert!(l.tokens_exhausted());
    }

    #[test]
    fn turns_saturate() {
        let l = Limits::new(&spec(5, 60, 100), Instant::now());
        assert_eq!(l.turns_left(), 5);
        l.spend_turns(3);
        assert_eq!(l.turns_left(), 2);
        l.spend_turns(10);
        assert_eq!(l.turns_left(), 0);
        l.spend_turns(1);
        assert_eq!(l.turns_left(), 0);
    }

    #[test]
    fn limits_is_sync() {
        fn assert_sync<T: Sync>() {}
        assert_sync::<Limits>();
    }
}
