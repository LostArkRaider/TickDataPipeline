# Compliance Assertion Prevention Protocol

## CRITICAL: DO NOT ADD POSITIVE COMPLIANCE ASSERTIONS TO CODE OR DOCUMENTS

### FORBIDDEN COMPLIANCE MARKERS

**NEVER include these types of positive compliance assertions in code files, documents, or version descriptions:**

```
FORBIDDEN EXAMPLES:
 Compliant with R1-R19
 Meets requirements R4, R7, R9
 GPU compatibility verified
 Float32 syntax confirmed
 No forbidden practices detected
 Passes compliance check
 Validated against protocol
 Conforms to development standards
// Compliance: R1-R5 verified
# COMPLIANT: Requirements satisfied
```

### ALLOWED COMPLIANCE MARKERS

**You MAY include negative compliance indicators when issues exist:**

```
ALLOWED EXAMPLES:
 Violates R3 - requires Int32 conversion
 Non-compliant: Uses forbidden Dict structure
 ISSUE: Float64 detected, needs Float32 conversion
TODO: Fix R7 GPU compatibility violation
FIXME: Non-compliant function signature
WARNING: Breaks R15 - modifies test behavior
ERROR: Forbidden practice F8 present
```

### WHY THIS MATTERS

**Problem:** Positive compliance assertions create false audit results because:
1. Later Claude sessions see "✅ Compliant" and skip detailed analysis
2. Code review tools assume compliance without verification
3. Version history gets polluted with incorrect compliance claims
4. Actual violations get missed due to false positive indicators

### COMPLIANCE REPORTING RULES

1. **Code Files**: NEVER include any positive compliance statements
2. **Documents**: NEVER embed compliance assertions in content
3. **Version Descriptions**: NEVER include compliance status
4. **Comments**: NEVER add positive compliance markers
5. **Artifacts**: Keep compliance reporting separate from code content

### CORRECT APPROACH

**Instead of embedding compliance assertions:**
- Report compliance status ONLY in chat responses (not in code)
- Use separate compliance reports outside of artifacts
- Flag actual violations with negative indicators only
- Let compliance verification happen through external auditing

### ENFORCEMENT

**Before outputting any code or document:**
1. Scan for positive compliance markers ("compliant", "verified", etc.)
2. Remove ALL positive compliance assertions
3. Preserve ONLY negative compliance indicators where issues exist
4. Keep compliance discussion in chat, not in artifacts

**CRITICAL:** This rule applies to ALL file types including:
- Source code (.jl, .py, etc.)
- Configuration files (.toml, .yaml, etc.)  
- Documentation (.md, .txt, etc.)
- Test files
- Version descriptions
- Git commit messages
- Any artifact or canvas output