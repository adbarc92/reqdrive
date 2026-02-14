Given where the project is right now, I'd approach this in three phases, ordered by risk reduction.

**Phase 1: Lock in what already works.**

Before you change anything, write tests for the behavior you've manually verified and trust. Your simple test harness already covers config, sanitization, schema, and preflight — those are solid. The gaps are in the pipeline's runtime behavior. Specifically:

Start with the checkpoint round-trip. Write a test that saves a checkpoint, loads it, and confirms the iteration number, branch, and stories_complete all survive. This is pure bash state management with no Claude dependency, so it's easy to test and high value — if resume is broken, you lose expensive completed work.

Then test story selection determinism. Create a `prd.json` fixture with stories in various states (some passed, some not, mixed priorities) and confirm `select_next_story` returns the right one every time. This is the core control logic of your pipeline and it's a pure `jq` query, so it's trivially testable.

Then test the "all stories complete" exit condition. Same fixture approach — a PRD where every story has `passes: true` should produce an empty selection and trigger the completion path.

These three tests cover the pipeline's decision-making backbone without touching Claude at all.

**Phase 2: Fix the heredoc bug, then test the fix.**

This is your highest-priority code change because it's a real injection path, and it's small. Quote the implementation prompt heredoc delimiter and restructure how you inject story variables. Then write a test with a story title containing `$(echo pwned)` and confirm it appears literally in the prompt file rather than being expanded. This is a case where the test should come immediately after the fix — you want to lock the door and then verify it's locked.

**Phase 3: Add the output verification layer.**

This is the big architectural addition, so approach it incrementally. Don't try to build the full verify-retry-rollback loop at once. Instead:

First, add a post-iteration commit check. After each Claude invocation, run `git log --oneline -1` and verify the most recent commit message matches your expected format (`feat: [US-XXX] - *`). If it doesn't, log a warning and mark the iteration as suspect in the checkpoint. Don't abort yet — just observe. This gives you data on how often the agent fails silently before you build retry logic around it.

Second, wire up `testCommand`. You already auto-detect it in `init.sh` and store it in config. After the commit check passes, run the test command if it's configured. Log the exit code. Again, start with warn-don't-abort — you want to see the failure rate before deciding on the retry policy.

Third, add a scope check. Run `git diff --name-only` against the pre-iteration SHA and log which files were touched. You don't need to enforce a policy yet, but having this data lets you spot when the agent modifies files outside the story's expected scope.

Once you've been running with these checks in observation mode and you trust the signal, you can promote them from warnings to hard gates and add retry logic.

**What I'd explicitly avoid right now:** don't build rollback yet. Rollback is complex (you need to handle partial commits, dirty working trees, branch state), and you don't yet have the verification data to know what triggers rollback should look like. Get the observation layer in first, run it on a few real requirements, and let the failure modes tell you what rollback needs to handle.

The general principle here is: **observe before you enforce**. Each verification step starts as a logged warning, graduates to a checkpoint annotation, and only becomes a hard gate once you understand its false-positive rate. This keeps the pipeline usable while you harden it.
