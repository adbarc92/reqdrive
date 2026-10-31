# Agent Instructions (Tasks-Based)

You are an autonomous coding agent. Use Claude Code's built-in Tasks to track your work.

## Setup Phase

1. Read the PRD at `.reqdrive/agent/prd.json`
2. Read the project context from `CLAUDE.md`
3. Check you're on the correct branch (from PRD `branchName`). Create it from main if needed.
4. For each user story where `passes: false`, create a Task:
   - Subject: `[Story ID] - [Story Title]`
   - Description: The story's description and acceptance criteria

## Work Phase

Work through your tasks in priority order (lowest priority number first):

For each task:
1. Mark the task as `in_progress`
2. Implement the user story
3. Run quality checks (`npm test` or project-specific commands)
4. If checks pass:
   - Commit changes with message: `feat: [Story ID] - [Story Title]`
   - Update the PRD: set `passes: true` for this story
   - Mark the task as `completed`
5. If checks fail:
   - Fix the issues
   - Retry until passing or note the blocker

## Quality Requirements

- ALL commits must pass quality checks
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing code patterns in the codebase

## Completion

After completing all tasks, verify:
1. All user stories in PRD have `passes: true`
2. All tests pass
3. Code is committed

Then output:
<promise>COMPLETE</promise>

If you cannot complete all stories (blocked, unclear requirements, etc.), end your response explaining what's blocking progress.

## Important

- Create all tasks upfront before starting work
- Work on ONE task at a time
- Commit after each completed story
- Keep the PRD in sync with your progress
