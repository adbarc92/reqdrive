<!-- graph:router -->
# reqdrive — router

`reqdrive story <work-order.json>` is a Rust harness that runs one story to one pushed branch, reporting JSON-lines events.
v1 is built and on main and tested offline; live end-to-end run and owner rulings remain ([state](state.md)).

## Where things live

- [index](index.md) lists every doc with one sentence each; [state](state.md) holds status.
- [Agent guide](../CLAUDE.md): architecture, principles, conventions, commands.
- [Design](superpowers/specs/2026-10-30-story-harness-mode-design.md): the authority on behaviour.
- [Plan](superpowers/plans/2026-10-30-story-harness-rust.md): the current implementation plan.
- [STATUS](STATUS.md): state summary and session log.
- [ROADMAP](../ROADMAP.md): the only roadmap, with open questions.
- [README](../README.md): user-facing description.

## Read first, by task

- Pick up a session: [STATUS](STATUS.md), then [state](state.md).
- Change harness behaviour: [design](superpowers/specs/2026-10-30-story-harness-mode-design.md) section 3, then [CLAUDE.md](../CLAUDE.md).
- Add future work or an open question: [ROADMAP](../ROADMAP.md).
- Find any other doc: [index](index.md).

## Never

- Follow the rules in [CLAUDE.md](../CLAUDE.md): public repo (no private names or local paths), the three cargo checks before a commit, no new roadmap file.
