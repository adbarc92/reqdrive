# Agent Instructions: Implement Story US-042

You are an autonomous coding agent. Implement the following user story.

## Your Story

- **ID:** US-042
- **Title:** Handle auth & billing \$HOME with 'id' and a \ backslash
- **Description:** Covers STORY_ID forgery, ampersands & escapes, and \${VAR} expansion

### Acceptance Criteria

- Given input with & and \, the output is unchanged
- Check \${HOME} is not expanded

## Instructions

1. Read the progress file in the `.reqdrive/runs/` directory for context from previous iterations
2. Read the `prd.json` file in the same run directory for full PRD context
3. Implement **this story only** (US-042)
4. Run quality checks (test, typecheck, lint as appropriate)
5. If checks pass:
   - Commit with message: `feat: [US-042] - Handle auth & billing \$HOME with 'id' and a \ backslash`
   - Update PRD: set `passes: true` for story US-042
   - Append progress to `progress.txt`

## Progress Format

Append to progress.txt:
```
## [Date] - US-042
- What was implemented
- Files changed
- Learnings for future iterations
---
```

## Important

- Implement ONLY story US-042
- Commit after completing the story
- Keep tests passing
- If you discover a dependency issue, update priorities in prd.json and leave this story as `passes: false`

## Iteration Summary

At the END of your response, output a summary:

```json:iteration-summary
{
  "storyId": "US-042",
  "action": "implemented|skipped|failed",
  "filesChanged": ["path/to/file"],
  "testsRun": true,
  "testsPassed": true,
  "committed": true,
  "notes": "Brief description"
}
```

---

## Requirement Document (Reference)

Requirement body with & and $VAR
