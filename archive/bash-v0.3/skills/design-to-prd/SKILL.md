---
name: design-to-prd
description: "Transform design documentation, concept docs, and high-level ideas into structured requirements and PRDs. Use when you have wireframes, vision docs, architecture docs, or conceptual documents that need to become actionable specifications. Triggers on: design to prd, convert design doc, translate this design, requirements from design, concept to prd, vision to requirements, wireframe to stories."
---

# Design-to-PRD Translator

Transform conceptual and design documentation into structured requirements, user stories, and complete PRDs.

---

## The Job

1. Receive design documentation (vision docs, concept docs, wireframes, architecture docs, etc.)
2. Analyze and extract core concepts, goals, and features
3. Identify stakeholders and user personas
4. Generate structured requirements
5. Create user stories with acceptance criteria
6. Produce a complete PRD ready for implementation

**This is a meta-workflow that bridges the gap between "idea" and "actionable specification."**

---

## Supported Input Types

This skill handles various conceptual document types:

| Document Type | What to Extract |
|--------------|-----------------|
| **Vision Document** | Goals, success metrics, target users, high-level features |
| **Concept Document** | Problem statement, proposed solution, key capabilities |
| **Wireframes/Mockups** | UI elements, user flows, interactions, states |
| **Architecture Doc** | Components, integrations, data models, constraints |
| **Meeting Notes** | Decisions made, requirements mentioned, action items |
| **Brainstorm/Ideas** | Core features, nice-to-haves, out-of-scope items |
| **Competitor Analysis** | Features to include, features to differentiate |
| **User Research** | Pain points, needs, desired outcomes |

---

## Phase 1: Document Analysis

First, understand what you're working with.

### Ask These Clarifying Questions:

```
1. What type of document is this?
   A. Vision/Strategy document
   B. Concept/Proposal document
   C. Wireframes/UI mockups
   D. Architecture/Technical design
   E. Mixed/Multiple documents
   F. Other: [please specify]

2. What is the intended scope?
   A. Full feature set (everything in the doc)
   B. MVP/Phase 1 only
   C. Specific section: [please specify]
   D. Let me determine based on priorities

3. Who is the primary audience for the PRD?
   A. Development team (technical detail needed)
   B. AI agents (very explicit, small stories)
   C. Stakeholders (business context needed)
   D. Mixed audience

4. Are there existing systems this integrates with?
   A. Yes, and they're documented
   B. Yes, but I need to explore the codebase
   C. No, this is greenfield
   D. Unsure
```

---

## Phase 2: Concept Extraction

Extract and organize the core elements from the source document.

### Create a Concept Map:

```markdown
## Concept Map: [Feature Name]

### Problem Statement
[What problem does this solve? Who has this problem?]

### Vision
[What does success look like? What's the end state?]

### Target Users
- **Primary:** [Who benefits most?]
- **Secondary:** [Who else uses it?]
- **Stakeholders:** [Who cares about outcomes?]

### Core Capabilities
1. [Capability 1 - what the system must do]
2. [Capability 2]
3. [Capability 3]

### Key Entities/Objects
- [Entity 1]: [what it represents]
- [Entity 2]: [what it represents]

### User Flows
1. [Flow 1]: [trigger] → [steps] → [outcome]
2. [Flow 2]: [trigger] → [steps] → [outcome]

### Constraints & Boundaries
- Must: [non-negotiable requirements]
- Must Not: [explicit exclusions]
- Should: [important but flexible]
- Could: [nice to have]

### Open Questions
- [Anything unclear in the source document]
```

Present this concept map to the user for validation before proceeding.

---

## Phase 3: Requirements Generation

Transform concepts into formal requirements.

### Requirement Categories:

#### Functional Requirements (FR)
What the system must DO.

```markdown
### Functional Requirements

FR-1: [Action verb] [specific behavior]
  - Context: [when/where this applies]
  - Input: [what triggers it]
  - Output: [what happens]
  - Example: [concrete example]

FR-2: ...
```

#### Data Requirements (DR)
What data the system must STORE and MANAGE.

```markdown
### Data Requirements

DR-1: [Entity] must store [fields]
  - Required fields: [list]
  - Optional fields: [list]
  - Relationships: [to other entities]
  - Constraints: [validation rules]

DR-2: ...
```

#### Interface Requirements (IR)
How users INTERACT with the system.

```markdown
### Interface Requirements

IR-1: [Screen/Component] must display [elements]
  - Layout: [description]
  - Interactions: [click, hover, etc.]
  - States: [loading, empty, error, success]
  - Responsive: [behavior at breakpoints]

IR-2: ...
```

#### Integration Requirements (INT)
How the system connects to OTHER systems.

```markdown
### Integration Requirements

INT-1: Must integrate with [system]
  - Protocol: [REST, GraphQL, webhook, etc.]
  - Authentication: [method]
  - Data exchanged: [what flows between]

INT-2: ...
```

---

## Phase 4: User Story Generation

Convert requirements into implementable user stories.

### Story Sizing Rules

**Each story must be completable in ONE focused session.**

Split by:
- **Layer**: Database → Backend → Frontend
- **Feature**: One capability per story
- **Scope**: One screen/component per story

### Story Template

```markdown
### US-[XXX]: [Short Title]

**Description:** As a [user type], I want [capability] so that [benefit].

**Source:** [Which requirement(s) this implements: FR-1, DR-2, etc.]

**Acceptance Criteria:**
- [ ] [Specific, verifiable criterion]
- [ ] [Another criterion]
- [ ] Typecheck passes
- [ ] [If UI] Verify in browser
```

### Ordering Stories

1. **Foundation first**: Schema, models, types
2. **Backend next**: APIs, services, business logic
3. **Frontend last**: Components that consume the backend
4. **Polish after**: Refinements, edge cases, optimizations

---

## Phase 5: PRD Assembly

Combine everything into the final PRD document.

### PRD Structure

```markdown
# PRD: [Feature Name]

## Source Documents
- [List of input documents analyzed]

## Introduction
[Problem statement and solution overview]

## Goals
- [Measurable goal 1]
- [Measurable goal 2]

## Target Users
[Who this is for]

## User Stories

[All stories from Phase 4, properly ordered]

## Functional Requirements
[From Phase 3]

## Data Requirements
[From Phase 3]

## Interface Requirements
[From Phase 3]

## Integration Requirements
[From Phase 3, if any]

## Non-Goals
[Explicit exclusions from Concept Map]

## Design Considerations
[UI/UX notes, mockup references]

## Technical Considerations
[Architecture notes, constraints, dependencies]

## Success Metrics
[How we measure success]

## Open Questions
[Unresolved items needing decision]

## Appendix: Concept Map
[Include the concept map for reference]
```

---

## Output

- **Concept Map:** `tasks/concept-[feature-name].md` (intermediate artifact)
- **Final PRD:** `tasks/prd-[feature-name].md`

If user wants agent-ready format, also generate:
- **prd.json:** In the agent directory (use the reqdrive conventions)

---

## Handling Incomplete Documents

Design docs are often incomplete. Handle gracefully:

### If Missing Problem Statement:
Ask: "What problem does this solve? Who has this problem today?"

### If Missing Success Metrics:
Ask: "How will we know this feature is successful? What would we measure?"

### If Missing Scope Boundaries:
Ask: "What should this explicitly NOT do? What's out of scope for v1?"

### If Missing User Flows:
Ask: "Walk me through how a user would accomplish [core task]."

### If Ambiguous Requirements:
Flag in Open Questions. Don't guess. Example:
```markdown
## Open Questions
- The wireframe shows a "Share" button but doesn't specify share targets.
  Options: (A) Share via link, (B) Share to specific users, (C) Both?
```

---

## Multi-Document Synthesis

When given multiple source documents:

1. **Identify overlaps**: Same feature described differently
2. **Resolve conflicts**: Flag contradictions, ask user to decide
3. **Merge perspectives**: Combine technical + design + business views
4. **Create unified view**: One concept map, one PRD

```markdown
## Document Reconciliation

### Overlap: [Topic]
- Doc A says: [X]
- Doc B says: [Y]
- Resolution: [Merged understanding or question for user]

### Conflict: [Topic]
- Doc A says: [X]
- Doc B says: [contradictory Y]
- **Needs decision:** Which approach?
```

---

## Example Workflow

**User provides:** "Here's our wireframe for a new dashboard feature" + image/description

**Step 1 - Clarify:**
```
1. What type of document is this?
   → C. Wireframes/UI mockups

2. What is the intended scope?
   → A. Full feature set

3. Who is the primary audience for the PRD?
   → B. AI agents

4. Are there existing systems this integrates with?
   → A. Yes, and they're documented
```

**Step 2 - Concept Map:**
Extract all UI elements, identify data needs, map user flows.

**Step 3 - Requirements:**
Generate FR (features), DR (data), IR (interface) requirements.

**Step 4 - User Stories:**
Create small, ordered stories.

**Step 5 - PRD:**
Assemble final document, save to `tasks/prd-dashboard.md`.

**Step 6 (optional):**
"Would you like me to also generate the prd.json for the agent?"

---

## Checklist

Before producing final output:

- [ ] Clarifying questions answered
- [ ] Concept map validated with user
- [ ] All requirements categorized (FR, DR, IR, INT)
- [ ] User stories sized appropriately for audience
- [ ] Stories ordered by dependency
- [ ] Open questions documented (not guessed)
- [ ] Non-goals explicitly stated
- [ ] PRD saved to `tasks/prd-[feature-name].md`
