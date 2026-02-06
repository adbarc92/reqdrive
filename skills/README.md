# reqdrive Skills

This directory contains standalone Claude Code skills that complement the reqdrive pipeline. These skills are designed to be used interactively via Claude Code's `/skill` invocation, **not** as part of the automated pipeline.

## Available Skills

| Skill | Description |
|-------|-------------|
| `design-to-prd` | Converts design documents into structured PRD format |
| `prd` | Assists with creating and refining product requirement documents |
| `project-journal` | Maintains a running journal of project decisions and progress |
| `verification-workflow` | Guides test creation and verification for implemented features |

## Usage

Skills are invoked via Claude Code:

```
/skill design-to-prd
/skill prd
/skill project-journal
/skill verification-workflow
```

## Future Integration

These skills may be integrated into the automated pipeline in future versions:

- **`reqdrive plan`** (coming soon) — May use `prd` and `design-to-prd` skills to generate and validate PRDs from requirements before running the agent.
- **`reqdrive verify`** (future) — May use `verification-workflow` to automate post-implementation verification.
