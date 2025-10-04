# /END - Session Completion Protocol

#Session Completion Workflow

## Purpose
Standardized session completion workflow to eliminate confusion and ensure consistent documentation and git operations.

## Usage
When user initiates `/END` command, follow this exact sequence:

## Step 1: Update Session State
```markdown
Update change_tracking/session_state.md with:
- Current session completion status
- Key accomplishments summary (2-3 bullet points max)
- Files modified/created list
- Test results if applicable
- Next steps or recommendations
```

## Step 2: Git Operations Sequence
Read: docs/protocol/Git_Operations_Protocol.md
 
**Important:** Display the commit message, then STOP and wait for approval
**Important:** Display the push command, then STOP and wait for approval

Execute these commands in order:

```bash
# Check current status
git status

# Stage all changes
git add .

# Create commit with standardized format
git commit -m "[SESSION_TYPE] SESSION: Brief Description

## Key Accomplishments
- Accomplishment 1
- Accomplishment 2
- Accomplishment 3

## Files Modified/Created
- file1.jl
- file2.jl
- file3.md

## Results
- Test results or validation status
- Performance metrics if applicable

## Status
Session complete, ready for [next phase/deployment/review]

```

## Step 3: Verify Completion
```bash
# Confirm commit succeeded
git status
```

## Session Types
- `[FEAT]` - Feature development sessions
- `[TESTING]` - Testing and validation sessions
- `[DOCS]` - Documentation sessions
- `[FIX]` - Bug fix sessions
- `[REFACTOR]` - Refactoring sessions

## Commit Message Template
```
[SESSION_TYPE] SESSION: Brief Description (max 50 chars)

## Key Accomplishments
- [Brief bullet point]
- [Brief bullet point]
- [Brief bullet point]

## Files Modified/Created
- [filename with brief description]
- [filename with brief description]

## Results
- [Test results, metrics, or validation status]

## Status
[Current completion status and next steps]

```

## Critical Requirements
1. **Session state MUST be updated first**
2. **Block commit message MUST match session state content**
3. **All changes MUST be staged before commit**
4. **Commit message MUST follow exact template format**
5. **push after user approval**

```
User: /END