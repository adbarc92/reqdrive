---
name: project-journal
description: Generate and maintain a personalized project documentation file (FOR[username].md) that explains the codebase architecture, tracks significant changes, and captures lessons learned. Trigger this skill when (1) a significant feature is completed, (2) the user says they want to end the session, (3) the user asks for a summary of work done, or (4) the user explicitly requests a project journal update.
---

# Project Journal

Maintain a `FOR[username].md` file in the project root that serves as a living document of the project's architecture, evolution, and lessons learned. Replace `[username]` with the user's name if known, otherwise use `FORYOU.md`.

## When to Update

- After completing a significant feature or refactor
- When the user indicates they want to end the session
- When the user asks for a summary of work done
- On explicit request

## File Structure

```markdown
# [Project Name]

## What This Project Does
[2-3 sentence plain-language summary]

## Architecture Overview
[How the system is structured and why]

## Key Technical Decisions
[Important choices and their rationale]

## Codebase Map
[How files/directories connect to each other]

## Change Log
[Reverse chronological list of significant changes]

## Lessons Learned
[Bugs encountered, pitfalls avoided, new patterns discovered]
```

## Update Process

1. Check if `FOR*.md` exists in project root
2. If exists, read current contents to understand existing state
3. Identify what has changed since last update by examining:
   - Recent git commits (if available): `git log --oneline -20`
   - Files modified in current session
   - New files created
   - Bugs fixed or issues resolved
4. Update only the sections affected by changes
5. For the Change Log, prepend new entries (most recent first)
6. For Lessons Learned, append new insights without removing old ones

## Writing Guidelines

- Use plain language; avoid jargon where simpler terms work
- Be specific about file paths and function names
- For technical decisions, always include the "why"
- In Lessons Learned, describe the problem, what went wrong, and the fix
- Keep entries concise—one paragraph per item maximum

## Change Log Entry Format

```markdown
### [Date] - [Brief Description]
- What changed and why
- Files affected: `path/to/file.js`, `path/to/other.py`
- Related lesson (if any): See Lessons Learned #N
```

## Lessons Learned Entry Format

```markdown
### #N - [Short Title]
**Problem:** What went wrong or was confusing
**Cause:** Why it happened
**Fix:** How it was resolved
**Avoid in future:** What to do differently next time
```

## First-Time Creation

When creating a new journal file:

1. Scan the codebase structure: `find . -type f -name "*.{js,ts,py,go,rs}" | head -50`
2. Identify entry points and main configuration files
3. Read key files to understand architecture
4. Check for existing documentation (README.md, docs/, etc.)
5. Generate initial Architecture Overview and Codebase Map
6. Leave Change Log and Lessons Learned sections with placeholder text indicating they will be populated as work progresses

## Example Entries

**Change Log example:**
```markdown
### 2025-01-25 - Added user authentication
- Implemented JWT-based auth with refresh tokens
- Files affected: `src/auth/`, `src/middleware/auth.js`, `prisma/schema.prisma`
- Related lesson: See Lessons Learned #3
```

**Lessons Learned example:**
```markdown
### #3 - JWT secrets must be loaded before routes initialize
**Problem:** Auth middleware threw "secret not defined" errors intermittently
**Cause:** Environment variables were loaded asynchronously; sometimes routes registered first
**Fix:** Made env loading synchronous in `config/index.js`, imported it at top of `app.js`
**Avoid in future:** Always load configuration synchronously and before any modules that depend on it
```
