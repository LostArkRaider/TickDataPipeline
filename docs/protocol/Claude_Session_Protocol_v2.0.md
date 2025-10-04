# Claude Session Protocol for ComplexBiquadGA Project
## Complete Guide for AI-Assisted Development Sessions
### Version 2.0

---

## Quick Start

### Session Initialization Checklist
```
1. Declare session type: "[TYPE] session for [specific task]"
   Types: DESIGN | DEVELOPMENT | TESTING | TROUBLESHOOTING | REVIEW
   
2. Read current state:
   - change_tracking/session_state.md (active issues)
   - change_tracking/change_index.md (recent work)
   
3. Create session log:
   change_tracking/sessions/session_YYYYMMDD_HHMM_[type].md
   
4. Confirm: "PROTOCOL ACKNOWLEDGED - READY TO [TYPE]"
```

### Critical Rules (Zero Tolerance)
- **R1**: ALL code → Artifacts/Canvas/Filesystem (never in chat)
- **R15**: NEVER modify tests to pass - fix implementation only
- **F13**: NO design changes without explicit permission
- **F18**: NO naming conflicts (module/struct collisions)
- **GPU**: NO Dict/Set/push!/pop!/IO in computational code

---

## Part 1: Claude Integration Requirements

### 1.1 Output Methods
```
Priority Order:
1. Claude Desktop Filesystem (when available)
2. Artifacts (for code generation)
3. Canvas (for documentation)

NEVER: Code blocks in chat (```julia)
```

### 1.2 Token Management
```
Constraints:
- Max readable file: ~100KB (25,000 tokens)
- Safe target: 50KB files
- Test output limit: 500 lines
- Error samples: First 5 of each type

Strategies:
- Use summary statistics over raw data
- Aggregate similar errors
- Sample output at intervals
- Reference instead of embed
```

### 1.3 Context Preservation
```
Between Sessions:
- session_state.md (450 tokens) - current handoff
- change_index.md (300 tokens) - topic navigation
- Session logs - detailed history (read rarely)

Within Session:
- Real-time documentation (Change_Tracking_Protocol.md)
- Incremental updates to session_state.md
- Complete session log in progress
```

### 1.4 Required Confirmations
Each session type requires specific acknowledgment:
- **Development**: "DEVELOPMENT PROTOCOL ACKNOWLEDGED - READY TO BUILD"
- **Testing**: "TESTING PROTOCOL ACKNOWLEDGED - READY FOR TEST ANALYSIS"
- **Troubleshooting**: "TROUBLESHOOTING PROTOCOL ACKNOWLEDGED - READY TO DIAGNOSE"
- **Code Review**: "CODE REVIEW PROTOCOL ACKNOWLEDGED - GPU COMPLIANCE MANDATORY"

---

## Part 2: Session Workflows

### 2.1 DEVELOPMENT Sessions

#### Purpose
Build new features, implement components, extend functionality

#### Workflow Cycle
```
Task Assignment → Analysis → Implementation → Documentation → Validation → Next Task
```

#### Required Analysis Before Code
```
TASK ANALYSIS:
• Task Description: [what needs to be built]
• Affected Components: [files/modules to modify]
• Dependencies: [what this relies on]
• Protocol Requirements: [applicable R/F rules]
• Implementation Strategy: [approach]

WAIT for "proceed with implementation"
```

#### Implementation Requirements
- Request needed files via filesystem
- Generate code via Artifacts/filesystem
- Follow naming conventions (PascalCase types, snake_case instances)
- Maintain GPU compatibility
- Document changes in real-time

#### Success Criteria
- [ ] Feature implemented completely
- [ ] All protocol requirements met
- [ ] No GPU-incompatible code
- [ ] Tests provided/updated
- [ ] Documentation complete

---

### 2.2 TESTING Sessions

#### Purpose
Execute tests, analyze failures, fix implementation issues

#### Workflow Cycle
```
Test Execution → Result Analysis → Implementation Fixes → Re-test → Documentation
```

#### Test Analysis Protocol
```
ERROR ANALYSIS REPORT:
• Total Errors Found: [number]
• Error Categories: [types]
• Root Cause Summary: [analysis]
• Proposed Fix Strategy: [approach]
• Protocol Compliance: [R/F verification]
```

#### Critical Testing Rules
- **NEVER** modify tests to pass (R15)
- Fix only implementation
- Preserve test assertions exactly
- Document each fix with rationale
- Verify no protocol violations

#### Common Test Issues
- Type mismatches (SubArray vs Vector)
- Channel saturation at ~1487 ticks
- Module loading order problems
- Naming conflicts (F18 violations)

---

### 2.3 TROUBLESHOOTING Sessions

#### Purpose
Diagnose issues, find root causes, implement targeted fixes

#### Workflow Cycle
```
Issue Report → Diagnosis → Root Cause Analysis → Solution → Verification → Documentation
```

#### Diagnostic Requirements
```
DIAGNOSTIC REPORT:
• Issue Summary: [concise description]
• Error Type: [compilation/runtime/logic/configuration]
• Affected Components: [list of files/modules]
• Root Cause Hypotheses: [ordered by likelihood]
• Protocol Implications: [R/F requirements affected]
```

#### Before Proposing Solutions
1. Check `docs/findings/` for similar issues
2. Review `change_index.md` for related work
3. Verify no design changes needed (F13)
4. Confirm GPU compatibility maintained

#### Common Issue Categories
- Module/import errors (forward references)
- Type system violations (64-bit usage)
- Channel saturation (consumer drainage)
- Naming conflicts (module/struct collisions)
- GPU violations (Dict/IO usage)

---

### 2.4 REVIEW Sessions

#### Purpose
Ensure code quality, protocol compliance, and GPU compatibility

#### Workflow Cycle
```
File Selection → Compliance Check → Issue Analysis → Corrections → Documentation
```

#### GPU Compatibility Check (CRITICAL)
```regex
Forbidden Pattern: \b(Dict|Set|push!|pop!|append!|@warn|@error|println|try|catch|eval|ccall|string\()\b
Result: ANY match = CRITICAL violation = AUTOMATIC REJECTION
```

#### Review Checklist
- [ ] GPU compatibility scan
- [ ] Protocol compliance (R1-R23)
- [ ] Forbidden practices (F1-F18)
- [ ] Type consistency (Float32/Int32)
- [ ] Module dependencies correct
- [ ] No naming conflicts (F18)

#### Severity Classification
- **CRITICAL**: GPU violations, F18 conflicts, crashes
- **HIGH**: Protocol violations, type inconsistencies
- **MEDIUM**: Quality issues, missing tests
- **LOW**: Style, formatting, comments

---

### 2.5 DESIGN Sessions

#### Purpose
Define new features, Describe code, extend functionality

#### Workflow Cycle
```
Task Asssignment → Analysis → Description → Approval → Implementation Plan
```
#### Required Analyis Before Writing Implementation Plan
```
TASK ANALYSIS:
• Task Description: [what needs to be built]
• Affected Components: [files/modules to modify]
• Dependencies: [what this relies on]
• Protocol Requirements: [applicable R/F rules]
• Implementation Strategy: [approach]

WAIT for "proceed with implementation"
```
#### Implementation Requirements
- Inspect needed files via filesystem
- Generate documents via filesystem to docs/chunks/ folder
- Follow naming conventions (PascalCase types, snake_case instances)
- Maintain GPU compatibility
- Make change_tracking changes in real-time

#### Success Criteria
- [ ] Feature ready for full implementation
- [ ] All protocol requirements met
- [ ] No GPU-incompatible code
- [ ] Tests provided/updated

---

## Part 3: Protocol Enforcement

### 3.1 Development Protocol Rules (R1-R23)

#### Critical Requirements
```
R1:  ALL code in Artifacts/Canvas/Filesystem
R15: NEVER modify tests - fix implementation
R20: Module dependency order is critical
R21: Real-time session documentation
R22: Project root file paths only
R23: Fully qualified function calls
```

#### GPU Compatibility (R7-R10, R18-R19)
```julia
# REQUIRED patterns:
Float32(1.0)              # NOT 1.0 or 1.0f0
Int32(100)                # NOT 100
similar(array, size)      # NOT zeros()/Matrix{}()
Vector{T}(slice)          # NOT raw slice
```

### 3.2 Forbidden Practices (F1-F18)

#### Zero Tolerance Violations
```
F1:  NO code in main chat
F13: NO unauthorized design changes
F14: NO forward references
F15: NO session changes without logging
F18: NO naming conflicts (module = struct name)
```

#### F18 Naming Conflict Examples
```julia
# ❌ VIOLATION - Automatic rejection:
module Pipeline
    struct Pipeline    # Name collision
    end
end

# ✅ CORRECT:
module Pipeline
    struct PipelineData    # Different name
    end
end
```

### 3.3 Design Change Protocol

#### When Design Change Needed
```
1. STOP - Do not implement
2. REQUEST using this format:

DESIGN CHANGE REQUEST:
• Component: [what needs changing]
• Current Design: [existing approach]
• Proposed Change: [new approach]
• Justification: [why necessary]
• Impact: [what else affected]

3. WAIT for "APPROVED: [component]"
4. DOCUMENT approval in session log
```

---

## Part 4: Documentation Standards

### 4.1 Change Tracking (Real-time)

#### Session State Updates (Immediate)
```markdown
File: change_tracking/session_state.md

## Active Issues
- [x] Fixed: [description]
- [ ] Remaining: [description]

## Recent Fixes (last 3 sessions only)
- Session [ID]: [what was fixed]

## Next Actions
- Priority 1: [specific task]
```

#### Session Log Entry (Per Change)
```markdown
CHANGE #N: [DESCRIPTION]
FILE: [path]
LINES: [modified]
TYPE: [Bug Fix/Feature/Refactor]
BEFORE: [code]
AFTER: [code]
RATIONALE: [why]
PROTOCOL: ✅ R1, R15, F13 compliant
```

### 4.2 Error Documentation

#### Root Cause Template
```markdown
ROOT CAUSE ANALYSIS:
• Confirmed Cause: [detailed explanation]
• Evidence: [specific code/config]
• Impact Scope: [what else affected]
• Fix Applied: [what was changed]
• Prevention: [future avoidance]
```

#### Finding Document (for significant issues)
```markdown
File: docs/findings/finding_YYYYMMDD_[issue_type].md

# Finding: [Title]
**Date**: YYYY-MM-DD
**Severity**: [Critical/High/Medium/Low]

## Symptoms
[Observable behavior]

## Root Cause
[Detailed explanation]

## Solution
[Step-by-step fix]

## Prevention
[How to avoid in future]
```

---

## Part 5: Quick Reference

### 5.1 Common Patterns

#### File Paths
```julia
✅ "data/raw/YM 06-25.Last.txt"          # From project root
❌ joinpath(@__DIR__, "../data/raw/...")  # Directory navigation
```

#### Type Declarations
```julia
✅ value = Float32(1.0); count = Int32(100)
❌ value = 1.0; count = 100    # Defaults to 64-bit
```

#### Naming Conventions
```julia
✅ struct ConfigData; config_instance = ConfigData()
❌ struct Config; Config = Config()    # Shadowing
```

#### Module Qualification
```julia
✅ ModernConfigSystem.parse_config(file)
❌ parse_config(file)    # Ambiguous
```

### 5.2 GPU Compatibility Quick Check
```julia
# FORBIDDEN in computational code:
Dict(), Set()              # Dynamic structures
push!(), pop!(), append!() # Dynamic allocation
println(), @warn, @info    # I/O operations
try/catch                  # Exception handling
string(), split(), join()  # String operations

# ALLOWED alternatives:
Vector{T}(undef, n)        # Pre-allocated
similar(existing)          # GPU-compatible
error codes                # Instead of exceptions
pre-computed strings       # Not runtime generation
```

### 5.3 Session Commands

#### Status Updates
```markdown
✅ Completed: [component]
🔄 In Progress: [current work]
❌ Blocked: [issue description]
📋 Next: [upcoming task]
```

#### Quick Confirmations
- "Proceed with implementation"
- "APPROVED: [design change]"
- "SESSION ENDED"
- "Tests ready for execution"

---

## Part 6: Session Completion

### 6.1 Required Actions
1. Update `session_state.md` with final status
2. Complete session log with summary
3. Document next actions clearly
4. Save all work to filesystem
5. Confirm "SESSION ENDED"

### 6.2 Session Summary Template
```markdown
## Session Summary
Duration: [time]
Type: [DEVELOPMENT/TESTING/TROUBLESHOOTING/REVIEW]
Completed:
- [achievement 1]
- [achievement 2]
Remaining:
- [task 1]
- [task 2]
Next Priority: [specific action]
Blockers: [if any]
```

### 6.3 Weekly Update (Fridays)
Update `change_index.md` with:
- Completed work grouped by category
- Session references for details
- Unresolved mysteries section
- Line number updates if needed

---

## Part 7: Version Control Integration

### 7.1 Current Branch Context
**Active Branch**: `refactor` (long-lived feature branch)
- Create new branches FROM: `refactor` (not master)
- Merge completed work TO: `refactor` (not master)
- See `Git_Operations_Protocol.md` section 3.3 for long-lived branch workflow

### 7.2 Git Commit Points
Claude should suggest commits at:
- After each successful implementation
- Before session end
- When switching session types
- After fixing critical bugs
- When tests pass

### 7.3 Commit Message Format
```
[TYPE] Component: Brief description

- Detail 1
- Detail 2

Session: YYYYMMDD_HHMM
Branch: refactor->feature/[name] (during refactor)
Refs: change_tracking/sessions/session_YYYYMMDD_HHMM.md
```

### 7.4 Claude Git Limitations
- Claude **suggests** commit messages only
- Human **executes** all git commands
- Claude **cannot** push, merge, or create branches
- Claude **tracks** changes for commit grouping

### 7.5 Session-Git Alignment
```
Session Documentation ↔ Git Commits
- Session log references commit intentions
- Commit messages reference session ID
- Change index tracks both git and session history
```

For complete git workflow and commands, see: `docs/protocol/Git_Operations_Protocol.md`

---

## Emergency Procedures

### Context Loss Recovery
1. Read `session_state.md` for current state
2. Check latest session log for recent work
3. Review `change_index.md` for topic history
4. Restore working context from these documents

### Session Handoff
When switching Claude instances:
1. Complete current change documentation
2. Update session_state.md thoroughly
3. Note specific file being worked on
4. Document exact line numbers if mid-edit
5. Create clear "HANDOFF POINT" marker

---

## Protocol References

Primary documents (in project):
- `Complex Biquad GA Development Protocol_v1.7_Project.md`
- `Julia_Test_Creation_Protocol.md`
- `Change_Tracking_Protocol.md`

Review targets:
- `docs/reviews/code_file_list.md`

Session logs:
- `change_tracking/session_state.md` (current)
- `change_tracking/change_index.md` (weekly)
- `change_tracking/sessions/` (detailed)

---

*End of Claude Session Protocol v2.0*
