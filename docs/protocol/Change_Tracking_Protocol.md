# Change Tracking Protocol

## Token-Optimized Three-Tier Documentation System

### Version 1.0

---

## 🎯 SYSTEM OVERVIEW

This protocol defines a three-tier change tracking system designed to minimize token usage while maintaining comprehensive documentation. The system replaces verbose session-by-session log reading with strategic document hierarchy.

**Token Savings: 90-95% reduction in change tracking overhead**

---

## 📁 DOCUMENT STRUCTURE

### File Organization

```
change_tracking/
├── session_state.md          # Primary handoff (450 tokens) - READ EVERY SESSION
├── change_index.md           # Topic navigation (300 tokens) - READ AS NEEDED
└── sessions/                 # Detailed archives - READ RARELY
    └── session_YYYYMMDD_HHMM_description.md (3000-8000 tokens each)
```

### Document Roles

| Document | Purpose | Update Frequency | Token Cost | When to Read |
|----------|---------|-----------------|------------|--------------|
| session_state.md | Current status & handoff | Every change | ~450 | Every session start |
| change_index.md | Topic-based navigation | Weekly/milestone | ~300 | When searching for specific topics |
| session_*.md | Complete forensic detail | Every session | 3000-8000 | Only for deep debugging |

---

## 📋 SESSION_STATE.MD PROTOCOL

### Purpose

Primary continuity document between sessions. Contains only essential current information.

### Update Instructions

```
"Update session_state.md with [specific change]. Mark previous issue as resolved, add new issue if found."
```

### Required Sections

1. **Active Issues** - Current problems requiring fixes
2. **Recent Fixes** - Last 3 sessions only (older items drop off)
3. **Hot Files** - Currently modified files with line numbers
4. **Next Actions** - Specific tasks for next session
5. **Current Metrics** - Test status, performance benchmarks

### Update Frequency

* After EVERY significant change
* At session end with final status
* Keep under 500 tokens total

### Example Update Command

```
"Mark TypeError in ComplexBiquad.jl:147 as fixed in session\_state.md. Add new issue: performance regression in GA mutations."
```

---

## 📑 CHANGE_INDEX.MD PROTOCOL

### Purpose

Searchable topic index pointing to detailed information in session logs.

### Update Instructions

```
"Update change_index.md:
1. Read session logs from [date] to [date]
2. Add entries for [completed category of work]
3. Group under appropriate sections
4. Include session references and line ranges"
```

### Required Sections

1. **Module \& Dependencies** - Include/import issues
2. **Type System \& GPU Compatibility** - Type errors, conversions
3. **Testing Failures** - Organized by test file
4. **Performance Optimizations** - With measured impact
5. **Protocol Violations Fixed** - By rule number
6. **Design Changes** - With authorization timestamp

### Update Frequency

* Weekly consolidation (e.g., every Friday)
* After completing major feature/fix category
* When switching to different subsystem
* After accumulating 5-10 session logs

### Example Update Commands

**Weekly Update:**

```
"It's Friday. Update change_index.md with this week's completed work. Read session logs from Monday-Friday, consolidate related fixes, update line numbers if needed."
```

**Milestone Update:**

```
"GPU compatibility is complete. Update change_index.md with all Int32 conversions and Float32 standardizations from the last 8 sessions."
```

---

## 📝 SESSION LOG PROTOCOL

### Purpose

Complete forensic record with full code changes, root cause analysis, and protocol compliance.

### File Naming

```
sessions/session_YYYYMMDD_HHMM_description.md
```

### Required Sections

1. **Session Header** - Objective, date, context
2. **Change Entries** - Numbered, with full before/after code
3. **Root Cause Analysis** - For each bug fix
4. **Protocol Compliance** - R/F requirements checked
5. **Session Summary** - Outcomes, test results, next steps

### Update Frequency

* Create at session start
* Update after each change (real-time per R21)
* Finalize at session end

### Storage Strategy

* Keep all session logs as permanent archive
* Do NOT read automatically at session start
* Reference only when debugging specific issues

---

## 🔄 WORKFLOW INTEGRATION

### Session Start Sequence

```
1. User: "Continue development. Read session_state.md for current status."
2. Claude: [Reads 450 tokens, knows current state]
3. Claude: Creates new session log file
4. Claude: Begins work on active issues
```

### During Session

```
After each change:
1. Update session_state.md (one line, ~20 tokens)
2. Add detailed entry to current session log
3. Continue with next change
```

### Session End

```
1. Update session_state.md with final status
2. Complete session summary in session log
3. Do NOT update change_index.md (unless weekly/milestone)
```

### When Deep Dive Needed

```
1. Check change_index.md for topic location
2. Read specific session log section
3. Never read full logs unless absolutely necessary
```

---

## 💡 EFFICIENCY TIPS

### DO:

* ✅ Always start by reading session_state.md only
* ✅ Update session_state.md in real-time
* ✅ Keep change_index.md as a stable reference
* ✅ Create detailed session logs but don't read them by default
* ✅ Use change_index.md to find specific information quickly

### DON'T:

* ❌ Read all session logs at session start
* ❌ Update change_index.md every session
* ❌ Let session_state.md grow beyond 500 tokens
* ❌ Skip creating detailed logs (needed for forensics)
* ❌ Read entire session logs when only specific sections needed

---

## 📊 TOKEN ECONOMICS

### Traditional Approach

```
Read 3 previous session logs: 3 × 5,000 = 15,000 tokens
Create new detailed log:                   5,000 tokens
Total per session:                        20,000 tokens
```

### Optimized Approach

```
Read session_state.md:                       450 tokens
Update session_state.md:                     100 tokens
Read change_index.md (if needed):           300 tokens
Read specific log section (rare):           500 tokens
Total typical session:                      550 tokens
Total with lookups:                       1,350 tokens
```

**Savings: 93-97% reduction in change tracking tokens**

---

## 🎯 QUICK REFERENCE COMMANDS

### For Claude:

**Start session:**

```
"Read session_state.md. Continue with [specific task]."
```

**Update state:**

```
"Update session_state.md: mark [issue] as fixed, add [new issue]."
```

**Weekly index update:**

```
"Update change_index.md with this week's changes from [date] to [date]."
```

**Find information:**

```
"Check change_index.md for [topic], then read that specific section."
```

**End session:**

```
"Finalize session log and update session_state.md with current status and next actions."
```

---

## 🔒 COMPLIANCE WITH R21

This system maintains full compliance with R21 (real-time session logging):

* Detailed logs are still created in real-time
* Every change is documented as it happens
* Full forensic trail maintained
* Only the reading pattern is optimized, not the writing

The optimization is in what we READ, not what we WRITE.

---

*Protocol Version 1.0 - Optimized for token efficiency while maintaining complete documentation*

