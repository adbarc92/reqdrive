<!-- graph:index -->
# Index

One line per doc: link | keywords | one sentence. A link ending in "/" covers a whole folder.
Regenerate with `graph.mjs init`; check with `graph.mjs lint`.

- [Status](STATUS.md) | status, next steps, session log, pr 10, container isolation, rulings | Living status: state summary, next steps, session log (container isolation, Windows), newest first. Open at the start of every session.
- [reqdrive Roadmap Completion Implementation Plan](superpowers/plans/2026-07-23-reqdrive-roadmap-completion.md) | bash, readiness ladder, mutation harness, bats | Task plan taking the old Bash reqdrive from L0 to L3. CLAUDE.md says it is not the current path; open for Bash-era history.
- [Factory M0: reqdrive foundations — Implementation Plan](superpowers/plans/2026-10-04-factory-m0-foundations.md) | factory, m0, walking skeleton, rust workspace, conformance kit | Lane plan for the factory foundations: archive Bash, Rust workspace, fake harness. CLAUDE.md says it is not the current path.
- [Factory M1: the harness — Implementation Plan](superpowers/plans/2026-10-04-factory-m1-harness.md) | factory, m1, docker, git bundle, seven stages | Lane plan for the factory harness driven by a control plane with Docker and Claude Code. CLAUDE.md says it is not the current path.
- [Story Harness in Rust Implementation Plan](superpowers/plans/2026-10-30-story-harness-rust.md) | story harness, tasks, file map, review focus, fake-claude | Current implementation plan for `reqdrive story` in Rust, task by task. Open to build or trace a module; CLAUDE.md says the design wins where they disagree.
- [Design — Completing the reqdrive Roadmap](superpowers/specs/2026-07-23-reqdrive-roadmap-completion-design.md) | bash, phases, freeze mechanism, critique rounds, decisions | Design for the Bash-era readiness work: phases P0 onward, freeze mechanism, decisions and critique log. Older design, before the Rust rewrite.
- [Design — Story-harness mode](superpowers/specs/2026-10-30-story-harness-mode-design.md) | work order, outcome table, test freeze, red stage, green stage, owner rulings | The design for `reqdrive story` (CLAUDE.md treats it as the authority over the plan): behaviour (section 3), outcome table (3.5.1), Rust implementation (10), open questions.
