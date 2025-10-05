# Complex Biquad GA Development Protocol
## Strict Adherence Framework
### Version 1.7

---

## 🔴 PROJECT CONTEXT
**Single-File Module System Architecture**

This is a single-file module system where CustomBiquadGA.jl is the only file with include statements. All dependencies must be resolved in the include order within that file. All other modules in the application must have no includes and must reference exports from this main file only.

---

## 🔴 MANDATORY SESSION LOGGING PROTOCOL
**REAL-TIME CHANGE DOCUMENTATION REQUIRED**

### R21: Session Change Log Requirements
```
CRITICAL: Session Documentation Protocol

Claude developers MUST create one .md file for each session in the change_log/ subfolder.
Each and every change made during the session MUST be documented in that file as the changes are made.
Log updates must be done ONE CHANGE AT A TIME, not in bulk at the end of the session.

MANDATORY SESSION LOG STRUCTURE:
- File location: change_log/session_[timestamp]_[description].md
- Timestamp format: YYYYMMDD_HHMM (e.g., 20250906_1430)
- Description: Brief summary of session focus (e.g., "bug_fixes", "gpu_compatibility", "testing")

REQUIRED LOG CONTENT:
1. SESSION HEADER with objective, date, and session identifier
2. REAL-TIME CHANGE ENTRIES as modifications are made
3. Each change must include:
   - File name and status (MODIFIED/CREATED/DELETED)
   - Exact lines modified or range
   - Change type (Bug Fix, Protocol Compliance, Feature Addition, etc.)
   - Detailed change description with before/after code snippets
   - Root cause analysis for bug fixes
   - Protocol compliance verification
   - Impact assessment on dependent systems
4. FINAL SESSION SUMMARY with outcomes and next steps

ENFORCEMENT: Session logs are essential for context continuity when Claude sessions end unexpectedly.
The next Claude session MUST reference the most recent session log to understand context.

SESSION LOG TEMPLATE:
# SESSION [ID] CHANGE LOG
# [Session Description]
# Date: [YYYY-MM-DD]
# Session: [ID] - [Brief Description]

SESSION OBJECTIVE:
[Primary goals and tasks for this session]

[CHANGE #N entries as changes are made...]

FINAL SESSION SUMMARY:
[Outcomes, remaining tasks, next steps]
```

### 85: Session Logging Violations
```
F15. NO Session Changes Without Logging - CRITICAL VIOLATION
    ⛔ NEVER make any code modifications without immediate log entry
    ⛔ NEVER defer logging to end of session - must be real-time
    ⛔ NEVER skip change documentation regardless of change size
    ⛔ NEVER assume changes are obvious or don't need documentation
    ✅ ALWAYS create session log file before making first change
    ✅ ALWAYS document each change as it is made
    ✅ ALWAYS include before/after code for significant changes
    ✅ ALWAYS analyze root cause for bug fixes
    ✅ ALWAYS verify protocol compliance for each change
    ✅ ALWAYS assess impact on dependent systems
    
    RATIONALE: Session logs provide essential context continuity when Claude
    sessions end unexpectedly. Without real-time logging, context is lost
    and subsequent sessions cannot understand the state of modifications.
```

### Session Log File Naming Convention
```
FORMAT: change_log/session_YYYYMMDD_HHMM_[description].md

EXAMPLES:
- change_log/session_20250906_1430_gpu_compatibility_fixes.md
- change_log/session_20250906_1615_module_dependency_errors.md
- change_log/session_20250906_2020_performance_optimization.md
- change_log/session_20250907_0900_test_suite_fixes.md

DESCRIPTION GUIDELINES:
- Use underscores, not spaces
- Keep under 30 characters
- Focus on primary session objective
- Use descriptive keywords: bug_fixes, testing, refactoring, optimization, compatibility
```

### Change Entry Template
```
CHANGE #[N]: [BRIEF DESCRIPTION - ALL CAPS]
================================================================================
FILE: [filepath]
STATUS: [MODIFIED/CREATED/DELETED]
LINES MODIFIED: [specific lines or range]

CHANGE DETAILS:
LOCATION: [specific function/struct/section]
CHANGE TYPE: [Bug Fix/Protocol Compliance/Feature Addition/Refactoring/etc.]

[For Bug Fixes - Include Root Cause Analysis:]
TEST FAILURE ANALYSIS:
Error: [exact error message]
Location: [file:line where error occurred]

ROOT CAUSE:
[Detailed analysis of why the error occurred]

SOLUTION:
[What was changed to fix the issue]

[For All Changes - Include Code Changes:]
SPECIFIC CHANGE:
OLD CODE:
```julia
[before code]
```

NEW CODE:
```julia
[after code]
```

[Include Impact Analysis:]
RATIONALE:
[Why this change was necessary and how it solves the problem]

PROTOCOL COMPLIANCE:
✅/❌ [List relevant R/F requirements and compliance status]

IMPACT ON DEPENDENT SYSTEMS:
[What other parts of the system might be affected]
================================================================================
```

---

## 🔴 MANDATORY OUTPUT RULE
**ALL CODE OUTPUT MUST BE IN ARTIFACTS OR CANVAS**

### Claude Desktop Exception
```
EXCEPTION: When using Claude Desktop with file system access
- Code may be output directly to local files using Filesystem tools
- Direct file modification is preferred for immediate testing/validation
- Reduces errors from Artifact system reliability issues
- Maintains version control through file system
- User explicitly requests file system updates over Artifacts

CONDITIONS FOR EXCEPTION:
- User has Claude Desktop with filesystem access enabled
- User explicitly requests direct file modification
- Files are within accessible project directories
- Changes are for immediate testing/validation workflow
```

### Artifact/Canvas Output Requirements (Default)
```
CRITICAL: All code generation MUST use Artifacts or Canvas (right panel)
- NO code blocks in main chat window
- NO inline code snippets for implementation
- ONLY use Artifacts or Canvas for ALL code output
- Each complete file gets its own Artifact or Canvas
- Update existing Artifacts or Canvas when modifying code

ENFORCEMENT: Any code output in main chat = PROTOCOL VIOLATION
```

---

## 🔴 MANDATORY PRE-CODE CHECKPOINT
**STOP - No code generation until this checkpoint is complete:**

### Required Analysis Output Format
```
1. TASK UNDERSTANDING:
   • State the specific task in one sentence
   • List all affected files
   • Identify potential rule violations

2. FILE VERIFICATION:
   • Confirm all needed files are uploaded
   • Request any missing files BEFORE proceeding
   • List files you will modify with their actual names

3. SESSION LOGGING PREPARATION:
   • Create session log file with timestamp
   • Document session objective and initial analysis
   • Prepare for real-time change logging

4. COMPLIANCE VERIFICATION:
   • Which requirements (R1-R23) apply to this task?
   • Which forbidden practices (F1-F17) could be violated?
   • What validation tests will confirm compliance?

5. IMPLEMENTATION PLAN:
   • Step-by-step approach (numbered)
   • Files to modify/create with justification
   • Expected output format (confirm Artifact or Canvas use)

[AWAIT "proceed with code generation" before continuing]
```

---

## 🔴 MODULE DEPENDENCY PROTOCOL
**JULIA DEPENDENCY ORDERING REQUIREMENTS**

### R20: Module Dependency Rule
```
CRITICAL: Julia Module Dependency Order

When writing Julia code for this project, you MUST ensure that all using and include 
statements appear in dependency order - every module/function/type must be defined 
BEFORE it is referenced by any subsequent code.

Before adding any new include, using, or export statement:
1. Identify what the new code depends on
2. Ensure those dependencies are already included/imported above the new statement
3. Place the new statement after all its dependencies but before any code that will use it
4. Verify no forward references to undefined modules/functions/types

If unsure about dependency order, ask for clarification of the project's module hierarchy before proceeding.

MODULE DEPENDENCY PROTOCOL:
1. All include statements must appear in dependency order (dependencies first)
2. All using statements must come after their corresponding include statements  
3. All export statements must come after the code being exported is defined
4. Never reference a module, function, or type before it has been included and loaded
5. When adding new code, verify its dependencies are already loaded above it

ENFORCEMENT: Any forward reference to undefined code = PROTOCOL VIOLATION
```

### F14: Forward Reference Violation
```
F14. NO Forward References - CRITICAL VIOLATION
    ⛔ NEVER reference modules, functions, or types before they are defined
    ⛔ NEVER call code before it is included or imported
    ⛔ NEVER assume dependencies will be resolved later
    ⛔ NEVER use undefined exports in subsequent modules
    ✅ ALWAYS ensure dependencies are loaded before use
    ✅ ALWAYS verify include order prevents forward references
    ✅ ALWAYS place include statements in dependency order
    ✅ ALWAYS validate that exports are defined before they are exported
    
    RATIONALE: Forward references cause module loading errors that are 
    time-consuming to debug and prevent proper compilation.
```

---

## 🚫 ABSOLUTE DESIGN PRESERVATION MANDATE
**ZERO TOLERANCE FOR UNAUTHORIZED MODIFICATIONS**

### Design Change Authorization Protocol
```
❌ CRITICAL: NO DESIGN CHANGES WITHOUT EXPLICIT WRITTEN PERMISSION ❌

MANDATORY PROCESS FOR ANY DESIGN CHANGE:
1. IMMEDIATE STOP when considering ANY modification to:
   - Function signatures or interfaces
   - Struct field definitions or types
   - Algorithm logic or mathematical operations
   - Data flow or processing patterns
   - Performance characteristics or optimizations
   - Module interfaces or exports
   - Test coverage or validation logic

2. EXPLICIT PERMISSION REQUEST:
   - State EXACTLY what you want to change and WHY
   - Explain potential impacts on existing functionality
   - Wait for explicit written approval: "APPROVED: [specific change]"
   - NO ASSUMPTIONS about "obvious" improvements
   - NO SILENT modifications "for compatibility"

3. DESIGN CHANGE DOCUMENTATION:
   - Document every approved change in modification log
   - Include rationale and user approval timestamp
   - Preserve original behavior unless explicitly authorized to change

VIOLATION CONSEQUENCES:
- Immediate task termination
- Full rollback of any unauthorized changes
- Mandatory re-implementation from clean baseline
```

### Authorized vs Unauthorized Changes
```
✅ ALWAYS AUTHORIZED (No Permission Required):
- Bug fixes that preserve exact original behavior
- Syntax corrections that maintain identical functionality
- Comment improvements and documentation updates
- Code formatting and style standardization per protocol
- Adding missing error handling that doesn't change logic flow
- Performance optimizations that maintain identical outputs

❌ REQUIRES EXPLICIT PERMISSION:
- Changing function parameters or return types
- Modifying algorithm logic or mathematical operations
- Removing or adding functionality
- Changing data structures or field types
- Modifying test assertions or expected behaviors
- Adding new features or capabilities
- Changing performance characteristics
- Refactoring that alters interfaces
- "Improvements" or "modernizations"
- Any change that could affect existing dependent code

❌ ABSOLUTELY FORBIDDEN:
- Silent functionality removal
- Undocumented interface changes
- "Simplifying" complex logic without understanding purpose
- Removing features deemed "unnecessary"
- Changing behavior "for consistency" without authorization
```

---

## 📋 CHECKABLE REQUIREMENTS RULES

### Output Requirements
```
R1. Artifact/Canvas Mandatory: ALL code output MUST be in Artifacts or Canvas only
    EXCEPTION: Claude Desktop users may request direct file system updates
    when explicitly specified for immediate testing/validation workflow
```

### Core Structure Requirements
```
R2. Module Structure: ALL code within properly defined Julia modules
R3. Include Order: Verify dependency order before output
R4. Complete Files: Output ONLY complete files via Artifacts or Canvas
R5. Include Restrictions: ONLY ComplexBiquadGA.jl may use include()
R6. Module Dependencies: Remove all using Main.ModuleName statements
```

### Hardware Compatibility Requirements
```
R7. Struct Parameterization: ALL computational structs must be parameterized
    PATTERN: mutable struct Name{M<:AbstractMatrix, V<:AbstractVector}
    
R8. Function Signatures: ALL functions using parameterized structs need where clause
    PATTERN: function name(ga::Type{M,V}) where {M,V}
    
R9. Array Creation: Replace hardcoded arrays with similar()
    FORBIDDEN: Matrix{Float32}(undef, ...), zeros(...)
    REQUIRED: similar(existing_array, ...)
    
R10. Array Slice Type Compatibility: Never pass array slices directly to functions expecting concrete Vector types
    PROBLEM: filter_outputs[t, :] creates SubArray, not Vector
    SOLUTION: Vector{T}(filter_outputs[t, :]) or collect(slice)
    RATIONALE: Method dispatch fails with SubArrays when Vector{T} is expected
```

### Numeric Literal Requirements
```
R18. Float32 Syntax Standardization: ALL scientific notation MUST use Float32() constructor
    FORBIDDEN: 1e-5f0, 2.5f0, 1.0e-8f0, 0.001f0
    REQUIRED: Float32(1e-5), Float32(2.5), Float32(1e-8), Float32(0.001)
    RATIONALE: Mixed notation causes parser ambiguities and compilation errors
    
    ENFORCEMENT RULES:
    - Apply to ALL numeric literals in ALL files
    - No exceptions for any scientific notation
    - Include test files and implementation files
    - Consistent syntax prevents parser confusion
```

### GPU Compatibility Requirements
```
R19. 64-bit Variable Restriction: 64-bit variables are FORBIDDEN unless explicitly justified
    FORBIDDEN: Int64, UInt64 in computational code
    REQUIRED: Int32, UInt32 for GPU parallel processing compatibility
    
    JUSTIFICATION REQUIRED:
    - Unless additional precision is mathematically required for the specific use case
    - Must provide explicit technical justification for 64-bit usage
    - Must obtain explicit user permission before using 64-bit variables
    - Document why 32-bit precision is insufficient
    
    GPU COMPATIBILITY RATIONALE:
    - GPU kernels perform better with 32-bit aligned data structures
    - Memory bandwidth optimization for parallel processing
    - Consistent data layout for vectorized operations
    - Future-proofing for GPU acceleration implementation
    
    ALLOWED EXCEPTIONS (with justification):
    - Time stamps from system APIs that return Int64 (convert immediately to Int32 where possible)
    - File sizes or memory addresses from system APIs (convert for internal use)
    - High-precision mathematical constants requiring 64-bit precision
    
    CONVERSION PATTERN:
    FORBIDDEN: tick_count::Int64
    REQUIRED: tick_count::Int32
    CONVERSION: Int32(min(int64_value, typemax(Int32))) for overflow protection
```

### Module Dependency Requirements
```
R20. Julia Module Dependency Order: ALL include/using statements must appear in dependency order
    FORBIDDEN: Forward references to undefined modules/functions/types
    REQUIRED: Dependencies loaded before use in all cases
    
    DEPENDENCY PROTOCOL:
    1. All include statements must appear in dependency order (dependencies first)
    2. All using statements must come after their corresponding include statements  
    3. All export statements must come after the code being exported is defined
    4. Never reference a module, function, or type before it has been included and loaded
    5. When adding new code, verify its dependencies are already loaded above it
    
    VALIDATION PROCESS:
    - Before adding any new include, using, or export statement
    - Identify what the new code depends on
    - Ensure those dependencies are already included/imported above the new statement
    - Place the new statement after all its dependencies but before any code that will use it
    - Verify no forward references to undefined modules/functions/types
    
    RATIONALE: Julia module loading is order-dependent. Forward references cause
    compilation errors that are time-consuming to debug and prevent proper execution.
```

### Session Documentation Requirements
```
R21. Session Change Log Documentation: ALL development sessions MUST maintain real-time change logs
    REQUIRED: One .md file per session in change_log/ subfolder with timestamp
    FORMAT: change_log/session_YYYYMMDD_HHMM_[description].md
    
    MANDATORY LOG CONTENT:
    1. Session header with objective, date, and identifier
    2. Real-time change entries as modifications are made (not bulk at end)
    3. Each change must include file, lines, change type, before/after code, rationale
    4. Root cause analysis for bug fixes
    5. Protocol compliance verification for each change
    6. Impact assessment on dependent systems
    7. Final session summary with outcomes and next steps
    
    ENFORCEMENT: Essential for context continuity when Claude sessions end unexpectedly.
    Next Claude session MUST reference most recent session log for context.
    
    RATIONALE: Real-time change documentation prevents context loss during session
    interruptions and enables subsequent sessions to understand modification state
    and continue work effectively.
```

### File Path Requirements
```
R22. Project Root File Paths: ALL file paths MUST be referenced from project root ComplexBiquadGA/
    FORBIDDEN: dirname(@__FILE__), dirname(@__DIR__), joinpath with relative navigation
    REQUIRED: Direct paths from project root directory
    
    EXAMPLES:
    ❌ WRONG: joinpath(dirname(@__FILE__), "..", "data", "raw", "YM 06-25.Last.sample.txt")
    ❌ WRONG: joinpath(dirname(@__DIR__), "config", "filters", "default.toml")
    ❌ WRONG: "../data/processed/output.jld2"
    
    ✅ CORRECT: "data/raw/YM 06-25.Last.sample.txt"
    ✅ CORRECT: "config/filters/default.toml"
    ✅ CORRECT: "data/processed/output.jld2"
    
    RATIONALE: Project root references ensure consistent file access regardless of
    execution context and prevent path resolution errors when running from different
    directories. Eliminates dependency on @__FILE__ and @__DIR__ macros that can
    cause issues in different Julia environments.
    
    ENFORCEMENT: All file I/O operations must use project root relative paths only.
```

### Module Qualification Requirements
```
R23. Fully Qualified Module Names: ALL function calls MUST use fully qualified module names
    FORBIDDEN: Unqualified function calls that could be ambiguous
    REQUIRED: ModuleName.function_name() for all cross-module function calls
    
    EXAMPLES:
    ❌ WRONG: parse_config(filename)  # Ambiguous - which module's parse_config?
    ❌ WRONG: create_filter()         # Could be from multiple modules
    ❌ WRONG: process_data(input)     # Unclear module origin
    
    ✅ CORRECT: ModernConfigSystem.parse_config(filename)
    ✅ CORRECT: ProductionFilterBank.create_filter()
    ✅ CORRECT: EndToEndPipeline.process_data(input)
    
    EXCEPTION: Functions from Base Julia or explicitly imported with 'using'
    ✅ ALLOWED: println(), length(), size()  # Base Julia functions
    ✅ ALLOWED: @test, @testset              # If using Test is declared
    
    RATIONALE: Fully qualified names prevent namespace collisions, improve code
    clarity, make dependencies explicit, and eliminate ambiguity about function
    origins. Critical in single-file module systems where many modules are loaded
    into the same namespace.
    
    ENFORCEMENT: All cross-module function calls must be fully qualified.
```

### Package Structure Requirements
```
R11. Project.toml: Define package name, UUID, version, dependencies
R12. src/ComplexBiquadGA.jl: Main module with includes and exports
R13. test/runtests.jl: Test runner with @testset blocks
R14. Dependency Management: All handled by main ComplexBiquadGA.jl
```

### Testing Requirements
```
R15. Fix All Errors: NEVER modify tests to pass - fix the implementation
R16. Bug Tracking: Maintain list of all encountered bugs
R17. No Workarounds: Address root causes, not symptoms
```

---

## 🚫 FORBIDDEN PRACTICES

<forbidden_practices>
F1. NO Code in Main Chat - ALL code must be in Artifacts or Canvas
    ❌ WRONG: ```julia code``` in chat
    ✅ RIGHT: Code in Artifact or Canvas panel
    ✅ EXCEPTION: Direct file system updates for Claude Desktop users when explicitly requested

F2. NO Triple-Quote Comments - Will cause parsing errors
    ❌ WRONG: """comment"""
    ✅ RIGHT: # comment

F3. NO Dict for Data Structures - Use Vector of structs
    ❌ WRONG: field::Dict{String, Int}
    ✅ RIGHT: field::Vector{StringIntPair}

F4. NO New Files Without Permission - Must justify necessity
F5. NO Skipping Test Failures - Must fix every issue
F6. NO Include in Non-Main Files - Except ComplexBiquadGA.jl
F7. NO Hardcoded Array Types - Must be device-agnostic
F8. NO Old Module Loading - Remove if !isdefined patterns
F9. NO Partial Implementations - Complete files only

F10. NO Code Inference or Boilerplate - CRITICAL VIOLATION
    ⛔ NEVER attempt to guess or infer code structure
    ⛔ NEVER use generic boilerplate implementations
    ⛔ NEVER proceed without the actual file
    ✅ ALWAYS request: "Please upload [filename] for modification"
    ✅ ALWAYS work with real project code only
    
    RATIONALE: Inferred code introduces inconsistencies, breaks
    dependencies, and violates project-specific patterns.

F11. NO Mixed Float32 Syntax - CRITICAL VIOLATION
    ⛔ NEVER use mixed scientific notation (1e-5f0 vs Float32(1e-5))
    ⛔ NEVER use suffix notation for Float32 literals (2.5f0, 1.0e-8f0)
    ✅ ALWAYS use Float32() constructor: Float32(1e-5), Float32(2.5)
    ✅ ALWAYS apply consistently across ALL files
    
    RATIONALE: Mixed syntax causes parser ambiguities and compilation errors.
    Project director requires unified syntax for maintainability.

F12. NO Unauthorized 64-bit Variables - CRITICAL VIOLATION
    ⛔ NEVER use Int64, UInt64 without explicit justification and user permission
    ⛔ NEVER assume 64-bit precision is needed without mathematical proof
    ⛔ NEVER ignore GPU compatibility requirements
    ✅ ALWAYS use Int32, UInt32 for computational code
    ✅ ALWAYS provide technical justification for any 64-bit usage
    ✅ ALWAYS obtain explicit user permission before using 64-bit variables
    
    RATIONALE: GPU parallel processing requires 32-bit aligned data structures
    for optimal performance and memory bandwidth utilization.

F13. NO UNAUTHORIZED DESIGN CHANGES - MAXIMUM CRITICAL VIOLATION
    ⛔ NEVER modify function signatures without explicit written permission
    ⛔ NEVER change algorithm logic or mathematical operations without authorization
    ⛔ NEVER remove or alter existing functionality without explicit approval
    ⛔ NEVER add new features or capabilities without written permission
    ⛔ NEVER change data structures or interfaces without authorization
    ⛔ NEVER modify performance characteristics without explicit approval
    ⛔ NEVER refactor code that alters external behavior without permission
    ⛔ NEVER make "improvements" or "optimizations" that change functionality
    ⛔ NEVER simplify or modernize code without understanding full impact and getting approval
    ⛔ NEVER assume any design change is "obvious" or "safe"
    
    ✅ ALWAYS request explicit permission: "PERMISSION REQUEST: I want to modify [specific component] by [exact change] because [technical justification]. This will affect [list impacts]. Do you authorize this change?"
    ✅ ALWAYS preserve exact original functionality unless explicitly authorized to change
    ✅ ALWAYS document the original design intent before any approved changes
    ✅ ALWAYS provide rollback plan for any approved design changes
    
    MANDATORY PERMISSION REQUEST FORMAT:
    "DESIGN CHANGE PERMISSION REQUEST:
    - COMPONENT: [exact module/function/struct name]
    - PROPOSED CHANGE: [detailed description of modification]
    - TECHNICAL JUSTIFICATION: [why this change is necessary]
    - FUNCTIONALITY IMPACT: [what will work differently]
    - DEPENDENT CODE IMPACT: [what else might be affected]
    - ROLLBACK PLAN: [how to undo if needed]
    
    AUTHORIZATION REQUIRED: Type 'APPROVED: [component]' to authorize this specific change."
    
    RATIONALE: Unauthorized design changes cause functionality regression,
    break dependent systems, and violate tested module specifications.
    Every design decision was made for specific technical reasons that
    must be preserved unless explicitly overridden by user authorization.
    
    ENFORCEMENT: Any unauthorized design change = IMMEDIATE TASK TERMINATION
    and MANDATORY RESTORATION of original functionality.

F14. NO Forward References - CRITICAL VIOLATION
    ⛔ NEVER reference modules, functions, or types before they are defined
    ⛔ NEVER call code before it is included or imported
    ⛔ NEVER assume dependencies will be resolved later
    ⛔ NEVER use undefined exports in subsequent modules
    ✅ ALWAYS ensure dependencies are loaded before use
    ✅ ALWAYS verify include order prevents forward references
    ✅ ALWAYS place include statements in dependency order
    ✅ ALWAYS validate that exports are defined before they are exported
    
    RATIONALE: Forward references cause module loading errors that are 
    time-consuming to debug and prevent proper compilation.

F15. NO Session Changes Without Logging - CRITICAL VIOLATION
    ⛔ NEVER make any code modifications without immediate log entry
    ⛔ NEVER defer logging to end of session - must be real-time
    ⛔ NEVER skip change documentation regardless of change size
    ⛔ NEVER assume changes are obvious or don't need documentation
    ✅ ALWAYS create session log file before making first change
    ✅ ALWAYS document each change as it is made
    ✅ ALWAYS include before/after code for significant changes
    ✅ ALWAYS analyze root cause for bug fixes
    ✅ ALWAYS verify protocol compliance for each change
    ✅ ALWAYS assess impact on dependent systems
    
    RATIONALE: Session logs provide essential context continuity when Claude
    sessions end unexpectedly. Without real-time logging, context is lost
    and subsequent sessions cannot understand the state of modifications.

F16. NO Directory Navigation File Paths - CRITICAL VIOLATION
    ⛔ NEVER use dirname(@__FILE__), dirname(@__DIR__) for file path construction
    ⛔ NEVER use joinpath with ".." relative navigation
    ⛔ NEVER use relative path navigation from arbitrary execution locations
    ⛔ NEVER assume current working directory for file operations
    ✅ ALWAYS use direct paths from project root ComplexBiquadGA/
    ✅ ALWAYS reference files as "data/raw/filename.txt" format
    ✅ ALWAYS use project root relative paths consistently
    ✅ ALWAYS ensure file paths work regardless of execution context
    
    EXAMPLES:
    ❌ FORBIDDEN: joinpath(dirname(@__FILE__), "..", "data", "raw", "YM 06-25.Last.sample.txt")
    ❌ FORBIDDEN: joinpath(dirname(@__DIR__), "config", "filters", "default.toml")
    ❌ FORBIDDEN: "../data/processed/output.jld2"
    
    ✅ REQUIRED: "data/raw/YM 06-25.Last.sample.txt"
    ✅ REQUIRED: "config/filters/default.toml"
    ✅ REQUIRED: "data/processed/output.jld2"
    
    RATIONALE: Directory navigation macros create execution context dependencies
    that cause file not found errors when code runs from different directories.
    Project root references ensure consistent file access regardless of execution
    context and eliminate path resolution ambiguities.

F17. NO Unqualified Function Calls - CRITICAL VIOLATION
    ⛔ NEVER use unqualified function calls for cross-module functions
    ⛔ NEVER assume function origin is obvious from context
    ⛔ NEVER rely on import order to resolve function ambiguity
    ⛔ NEVER use functions without explicit module qualification
    ✅ ALWAYS use ModuleName.function_name() for cross-module calls
    ✅ ALWAYS make function origins explicit and unambiguous
    ✅ ALWAYS qualify functions unless from Base Julia or explicitly imported
    ✅ ALWAYS prevent namespace collisions with explicit qualification
    
    EXAMPLES:
    ❌ FORBIDDEN: parse_config(filename)      # Which module's parse_config?
    ❌ FORBIDDEN: create_filter()             # Ambiguous function origin
    ❌ FORBIDDEN: process_data(input)         # Could be from multiple modules
    
    ✅ REQUIRED: ModernConfigSystem.parse_config(filename)
    ✅ REQUIRED: ProductionFilterBank.create_filter()
    ✅ REQUIRED: EndToEndPipeline.process_data(input)
    
    ✅ ALLOWED: println(), length(), size()  # Base Julia functions
    ✅ ALLOWED: @test, @testset              # If using Test is declared
    
    RATIONALE: Unqualified function calls create namespace ambiguity, make
    dependencies unclear, and can cause method resolution errors in single-file
    module systems where many modules are loaded into the same namespace.
    Explicit qualification improves code clarity and prevents conflicts.
</forbidden_practices>

---

## ✅ VALIDATION PATTERNS

### Pattern 1: Struct Definition Validation
```julia
# REFERENCE PATTERN - All structs must follow:
mutable struct ComplexBiquadStruct{M<:AbstractMatrix, V<:AbstractVector}
    coefficients::M  # Not Matrix{ComplexF64}
    state::V         # Not Vector{ComplexF64}
    tick_count::Int32  # R19: GPU-compatible, NOT Int64
    
    function ComplexBiquadStruct(coeffs::M, state::V) where {M<:AbstractMatrix, V<:AbstractVector}
        new{M,V}(coeffs, state, Int32(0))
    end
end
```

### Pattern 2: Function Signature Validation
```julia
# REFERENCE PATTERN - All functions must follow:
function process_ga(ga::SingleFilterGAComplete{M,V}) where {M<:AbstractMatrix, V<:AbstractVector}
    # Use similar() for new arrays
    workspace = similar(ga.population, size(ga.population))
    # Never: workspace = Matrix{ComplexF64}(undef, ...)
end
```

### Pattern 3: Dict Replacement Pattern
```julia
# FORBIDDEN:
struct BadConfig
    settings::Dict{String, Any}
end

# REQUIRED:
struct ConfigSetting
    key::String
    value::Any
end

struct GoodConfig
    settings::Vector{ConfigSetting}
end
```

### Pattern 4: Array Slice Conversion Pattern
```julia
# FORBIDDEN - Passing slice directly:
matrix_data = rand(10, 5)
process_vector(matrix_data[1, :])  # MethodError if expecting Vector{Float64}

# REQUIRED - Explicit conversion:
process_vector(Vector{Float64}(matrix_data[1, :]))  # Works
process_vector(collect(matrix_data[1, :]))         # Alternative

# BETTER - Update function signature if appropriate:
function process_vector(data::AbstractVector{T}) where T
    # Now accepts both Vector and SubArray
end
```

### Pattern 5: Float32 Syntax Validation
```julia
# FORBIDDEN - Mixed scientific notation syntax:
threshold = 1e-5f0              # Suffix notation
gain = 0.001f0                  # Suffix notation
value = 2.5f0                   # Suffix notation
limit = Float32(1e-8)           # Mixed with above

# REQUIRED - Consistent Float32() constructor:
threshold = Float32(1e-5)       # Constructor notation
gain = Float32(0.001)           # Constructor notation
value = Float32(2.5)            # Constructor notation
limit = Float32(1e-8)           # Constructor notation

# APPLICATION EXAMPLES:
# Test assertions:
@test params.clamping_threshold ≈ Float32(1e-5)    # Not 1e-5f0
@test params.gain >= Float32(0.001)                # Not 0.001f0

# Parameter bounds:
min_val=Float32(1e-8), max_val=Float32(1e-3)       # Not 1e-8f0, 1e-3f0

# Array initialization:
chromosome = Float32[Float32(2.5), Float32(1500)]  # Not [2.5f0, 1500f0]
```

### Pattern 6: GPU-Compatible 64-bit to 32-bit Conversion
```julia
# FORBIDDEN - 64-bit variables without justification:
struct BadCounter
    tick_count::Int64        # Violates R19
    memory_usage::Int64      # Violates R19
end

# REQUIRED - 32-bit variables with overflow protection:
struct GoodCounter
    tick_count::Int32        # GPU-compatible
    memory_usage::Int32      # GPU-compatible
end

# CONVERSION PATTERN - When interfacing with 64-bit APIs:
function process_system_time()
    system_time_ns = time_ns()  # Returns Int64
    # Convert to Int32 with overflow protection
    safe_time = Int32(min(system_time_ns, typemax(Int32)))
    return safe_time
end

# JUSTIFICATION REQUIRED - When 64-bit is mathematically necessary:
struct HighPrecisionCalculation
    # JUSTIFICATION: Accumulated error over 1M+ iterations requires 64-bit precision
    # USER PERMISSION: Obtained on [date] for specific mathematical requirement
    accumulator::Int64       # Exception with documentation
end
```

### Pattern 7: Module Dependency Order Validation
```julia
# FORBIDDEN - Forward references:
include("moduleB.jl")  # ModuleB references functions from ModuleA
include("moduleA.jl")  # ModuleA defines the functions
# ERROR: UndefVarError when ModuleB tries to use ModuleA functions

# REQUIRED - Dependency order:
include("moduleA.jl")  # Dependencies first
include("moduleB.jl")  # Then modules that use those dependencies

# FORBIDDEN - Using undefined exports:
export process_data    # process_data not yet defined
include("processing.jl")  # Defines process_data

# REQUIRED - Export after definition:
include("processing.jl")  # Define first
export process_data       # Export after definition

# FORBIDDEN - Using before including:
using Main.ModuleA     # ModuleA not yet loaded
include("moduleA.jl")  # Loads ModuleA

# REQUIRED - Include before using:
include("moduleA.jl")  # Load first
using Main.ModuleA     # Use after loading
```

### Pattern 8: Session Logging Validation
```julia
# REQUIRED - Session log file creation before first change:
# File: change_log/session_20250906_1430_bug_fixes.md

# SESSION HEADER:
# SESSION 20250906_1430 CHANGE LOG
# Bug Fixes and Protocol Compliance
# Date: 2025-09-06
# Session: 20250906_1430 - Critical bug fixes and GPU compatibility

# SESSION OBJECTIVE:
# Fix module loading errors and implement GPU compatibility requirements

# REAL-TIME CHANGE ENTRY (as change is made):
# CHANGE #1: FIX MODULE LOADING ERROR
# ================================================================================
# FILE: src/ComplexBiquadGA.jl
# STATUS: MODIFIED
# LINES MODIFIED: Line 55 (addition)
# 
# CHANGE DETAILS:
# LOCATION: After StatePreservation.jl include
# CHANGE TYPE: Bug Fix - Missing module import
# 
# ROOT CAUSE:
# StatePreservation module was included but not imported with 'using' statement
# 
# SOLUTION:
# Added 'using .StatePreservation' after include statement
# 
# OLD CODE:
# include("StatePreservation.jl")
# 
# NEW CODE:
# include("StatePreservation.jl")
# using .StatePreservation
# 
# RATIONALE:
# Module was included but not available for symbol resolution
# 
# PROTOCOL COMPLIANCE:
# ✅ R15: Fixed implementation issue
# ✅ F13: No unauthorized design changes
# ================================================================================

# FORBIDDEN - Bulk logging at end:
# [Multiple changes made without individual logging]
# Final bulk documentation at session end

# FORBIDDEN - Missing change documentation:
# Make changes without creating session log entries
```

### Pattern 9: Project Root File Path Validation
```julia
# FORBIDDEN - Directory navigation patterns:
data_file = joinpath(dirname(@__FILE__), "..", "data", "raw", "YM 06-25.Last.sample.txt")
config_file = joinpath(dirname(@__DIR__), "config", "filters", "default.toml")
output_file = "../data/processed/output.jld2"

# REQUIRED - Project root relative paths:
data_file = "data/raw/YM 06-25.Last.sample.txt"
config_file = "config/filters/default.toml"
output_file = "data/processed/output.jld2"

# PRACTICAL EXAMPLES:
# Loading configuration files:
config = load_filter_config("config/filters/production.toml")  # Not joinpath(dirname(@__DIR__), ...)

# Reading data files:
data = CSV.read("data/raw/market_data.csv", DataFrame)  # Not relative navigation

# Writing output files:
save_results(results, "data/processed/filtered_output.jld2")  # Direct project path

# Test file references:
test_config = "config/filters/test_config.toml"  # Simple and clear
```

### Pattern 10: Fully Qualified Function Call Validation
```julia
# FORBIDDEN - Unqualified cross-module function calls:
config = parse_config("config.toml")        # Which module's parse_config?
filter = create_filter(coefficients)        # Ambiguous function origin
results = process_data(input_data)          # Could be from multiple modules
metrics = calculate_metrics(output)         # Unclear module source

# REQUIRED - Fully qualified function calls:
config = ModernConfigSystem.parse_config("config.toml")
filter = ProductionFilterBank.create_filter(coefficients)
results = EndToEndPipeline.process_data(input_data)
metrics = PerformanceMetrics.calculate_metrics(output)

# ALLOWED - Base Julia and explicitly imported functions:
length(data)                                 # Base Julia function
println("Processing complete")               # Base Julia function
@test result ≈ expected                     # If using Test is declared
@testset "My Tests" begin ... end          # If using Test is declared

# PRACTICAL MODULE QUALIFICATION EXAMPLES:
# Configuration operations:
config = ModernConfigSystem.load_filter_config("production.toml")
defaults = ModernConfigSystem.create_default_config()

# Filter bank operations:
bank = ProductionFilterBank.create_fibonacci_filter_bank(config)
filter = ProductionFilterBank.create_complex_biquad(period, q_factor)

# Pipeline operations:
pipeline = EndToEndPipeline.create_pipeline(config)
result = EndToEndPipeline.process_pipeline_data(pipeline, data)

# State preservation operations:
StatePreservation.save_pipeline_state(pipeline, "pipeline_state.jld2")
restored = StatePreservation.load_pipeline_state("pipeline_state.jld2")
```

---

## 🎯 COMPLIANCE VERIFICATION CHECKLIST

### Before Each Session Begins:
```
SESSION PREPARATION CHECKLIST:
• Create session log file with timestamp in change_log/ directory
• Document session objective and planned changes
• Verify all needed files are available
• Review recent session logs for context
• Confirm protocol requirements that apply to planned work
```

### After Each Code Change, Confirm:
```
COMPLIANCE REPORT:
• Output Location: Artifact or Canvas (NOT main chat)
• Session Log Entry: Created for this specific change
• Conforms to: [List R1-R23 numbers that apply]
• Avoids: [List F1-F17 that were checked]
• Float32 Syntax: All scientific notation uses Float32() constructor
• GPU Compatibility: All variables use 32-bit types unless justified
• 64-bit Variables: None used OR explicit justification provided
• Design Changes: None made OR explicit permission obtained and documented
• Module Dependencies: All include/using statements in correct dependency order
• Forward References: None present - all dependencies loaded before use
• File Paths: All use project root references (no dirname/@__DIR__)
• Function Calls: All cross-module calls fully qualified
• Change Documentation: Real-time log entry completed
• Root Cause Analysis: Completed for bug fixes
• Impact Assessment: Evaluated for dependent systems
• Validation: [State how compliance was verified]
• Exceptions: [Explain any with justification]
```

### At Session End:
```
SESSION COMPLETION CHECKLIST:
• All changes documented in session log with real-time entries
• Final session summary completed with outcomes and next steps
• No pending undocumented changes
• Protocol compliance verified for all modifications
• Context adequately preserved for next session
```

---

## 📊 ERROR RESPONSE PROTOCOL

When encountering errors:

1. **IMMEDIATE STOP** - Do not proceed past error
2. **SESSION LOGGING** - Create change log entry for error analysis
3. **DESIGN CHANGE ASSESSMENT**:
   - Is the error fixable with bug fixes only?
   - Would fixing require changing design or functionality?
   - If design change needed: STOP and request permission
4. **PATH AND QUALIFICATION CHECK**:
   - Are file paths using project root references?
   - Are function calls fully qualified?
   - Are there any dirname(@__DIR__) patterns?
5. **DEPENDENCY ORDER CHECK**:
   - Is the error caused by forward references?
   - Are all include statements in dependency order?
   - Are all exports defined before being exported?
6. **FILE CHECK**:
   - Is the actual file uploaded?
   - If not, REQUEST: "Please upload [filename] to proceed"
   - Never attempt to fix without the real code
7. **CATEGORIZE ERROR**:
   - Which requirement violation? (R1-R23)
   - Which forbidden practice? (F1-F17)
   - Is it a logic error or compliance error?
8. **ROOT CAUSE ANALYSIS**:
   - Trace error to source in ACTUAL code
   - Check for Dict usage
   - Check for array slice type mismatches
   - Check for mixed Float32 syntax
   - Check for unauthorized 64-bit variables
   - Check for forward references to undefined code
   - Check for dirname(@__DIR__) file path patterns
   - Check for unqualified function calls
   - Verify struct parameterization
9. **FIX STRATEGY**:
   - Present fix that addresses root cause WITHOUT design changes
   - If design change required: STOP and request permission using mandatory format
   - Ensure no new violations introduced
   - Standardize all Float32 syntax
   - Convert 64-bit to 32-bit variables with justification
   - Correct include/using order to prevent forward references
   - Replace directory navigation with project root paths
   - Add module qualification to function calls
   - Validate against all requirements
   - OUTPUT FIX IN ARTIFACT OR CANVAS ONLY
   - DOCUMENT FIX IN SESSION LOG IMMEDIATELY

---

## 🔄 WORKFLOW ENFORCEMENT

### Phase 1: Analysis (MANDATORY FIRST)
```
1. Read task completely
2. Create session log file with timestamp
3. Document session objective in log file
4. Output compliance analysis using format above (in main chat)
5. Assess if any design changes are needed
6. If design changes needed: Request permission using mandatory format
7. Verify all dependencies can be resolved in correct order
8. Check for file path and function qualification requirements
9. STOP and wait for approval
```

### Phase 2: Implementation (ONLY after approval)
```
1. Generate complete file(s) IN ARTIFACTS OR CANVAS ONLY
2. Ensure all include/using statements are in dependency order
3. Use project root relative file paths only
4. Use fully qualified function calls for cross-module operations
5. Document each change in session log AS CHANGES ARE MADE
6. Include compliance report in main chat
7. Highlight any deviations
8. Document any approved design changes
9. Verify Float32 syntax standardization
10. Confirm GPU compatibility (32-bit variables)
11. Validate no forward references present
```

### Phase 3: Validation
```
1. Run through all checkable rules (R1-R23)
2. Confirm no forbidden practices (F1-F17)
3. Verify Float32 syntax consistency
4. Verify GPU compatibility (no unauthorized 64-bit)
5. Verify no unauthorized design changes
6. Verify module dependency order correctness
7. Verify no forward references to undefined code
8. Verify all file paths use project root references
9. Verify all cross-module function calls are fully qualified
10. Complete session log with final summary
11. Document compliance
12. Verify all code is in Artifacts or Canvas
13. Confirm all changes are logged in session change log
```

---

## 📝 QUICK REFERENCE CARD

### Always Check Before Code:
- [ ] Session log file created with timestamp? (R21/F15)
- [ ] Session objective documented? (R21)
- [ ] Output will be in Artifact/Canvas OR direct file system (if Claude Desktop exception applies)? (R1/F1)
- [ ] No unauthorized design changes? (F13)
- [ ] Module dependencies in correct order? (R20/F14)
- [ ] No forward references to undefined code? (F14)
- [ ] File paths use project root references? (R22/F16)
- [ ] Function calls fully qualified? (R23/F17)
- [ ] No Dict in structs? (F3)
- [ ] All structs parameterized? (R7)
- [ ] Functions have where clauses? (R8)
- [ ] Using similar() not zeros()? (R9)
- [ ] Array slices converted to Vectors? (R10)
- [ ] Only # comments? (F2)
- [ ] Complete file output? (R4)
- [ ] Float32() syntax standardized? (R18/F11)
- [ ] No unauthorized 64-bit variables? (R19/F12)

### After Each Change:
- [ ] Change logged in session file immediately? (R21/F15)
- [ ] Root cause analyzed for bug fixes? (R21)
- [ ] Protocol compliance verified? (R21)
- [ ] Impact on dependent systems assessed? (R21)

### Common Violations to Avoid:
```julia
# ❌ VIOLATIONS:
# Code in main chat window         # F1: Not in Artifact or Canvas
"""docstring"""                    # F2: Triple quotes
struct S; data::Dict; end         # F3: Dict usage
Matrix{Float64}(undef, 10, 10)    # R9: Hardcoded type
include("file.jl")                 # R5: Include outside main
function f(s::MyStruct)            # R8: Missing where clause
process(data[1, :])                # R10: SubArray not converted
threshold = 1e-5f0                 # F11: Mixed Float32 syntax
tick_count::Int64                  # F12: Unauthorized 64-bit
# Removing function parameters     # F13: Unauthorized design change
include("moduleB.jl")              # F14: Forward reference
include("moduleA.jl")              # (ModuleB uses ModuleA)
# Change without logging           # F15: No session documentation
joinpath(dirname(@__DIR__), "data") # F16: Directory navigation
parse_config("file.toml")          # F17: Unqualified function call

# ✅ CORRECTIONS:
# Code in Artifact or Canvas panel           # Use Artifact or Canvas
# docstring                        # Use # only
struct S; data::Vector{Pair}; end # Vector of structs
similar(reference, 10, 10)        # Device-agnostic
# (include only in ComplexBiquadGA.jl)
function f(s::MyStruct{M,V}) where {M,V}  # Parameterized
process(Vector{T}(data[1, :]))            # Explicit conversion
threshold = Float32(1e-5)                 # Standardized syntax
tick_count::Int32                         # GPU-compatible
# Request permission before parameter changes # Get authorization first
include("moduleA.jl")                     # Dependencies first
include("moduleB.jl")                     # Then dependents
# Document change in session log immediately # Real-time logging
"data/raw/filename.txt"                   # Project root path
ModernConfigSystem.parse_config("file.toml") # Fully qualified
```

---

## 🚨 CRITICAL REMINDERS

1. **ALWAYS** output code in Artifacts/Canvas OR direct file system (Claude Desktop exception)
2. **NEVER** generate code without Phase 1 analysis
3. **ALWAYS** wait for "proceed with code generation"
4. **NEVER** infer or guess code - request actual files
5. **IMMEDIATELY** report any Dict usage found
6. **STRICTLY** follow parameterization patterns
7. **COMPLETELY** output full files only
8. **ALWAYS** request missing files before attempting fixes
9. **ALWAYS** convert array slices to proper Vector types
10. **ALWAYS** use Float32() constructor for all scientific notation
11. **ALWAYS** use 32-bit variables unless 64-bit is mathematically justified and approved
12. **ABSOLUTELY NEVER** make design changes without explicit written permission
13. **IMMEDIATELY** stop and request permission if any design modification is needed
14. **ALWAYS** preserve exact original functionality unless explicitly authorized to change
15. **MANDATORY** use the required permission request format for any design changes
16. **ALWAYS** ensure include/using statements are in dependency order
17. **NEVER** create forward references to undefined modules/functions/types
18. **ALWAYS** verify dependencies are loaded before use
19. **MANDATORY** create session log file before making any changes
20. **ALWAYS** document each change in session log as it is made (real-time)
21. **NEVER** defer change documentation to end of session
22. **ALWAYS** include root cause analysis for bug fixes in session log
23. **ALWAYS** assess impact on dependent systems for each change
24. **NEVER** use dirname(@__FILE__) or dirname(@__DIR__) for file paths
25. **ALWAYS** use project root relative file paths (e.g., "data/raw/file.txt")
26. **NEVER** use unqualified function calls for cross-module operations
27. **ALWAYS** use fully qualified module names (ModuleName.function_name())

**⛔ ARTIFACT/CANVAS VIOLATION = IMMEDIATE REJECTION ⛔**
All code MUST be in Artifacts/Canvas OR direct file system (Claude Desktop).

**⛔ INFERENCE VIOLATION = IMMEDIATE REJECTION ⛔**
If you cannot see the actual code, you MUST request it.
No exceptions. No workarounds. No boilerplate.

**⛔ FLOAT32 SYNTAX VIOLATION = IMMEDIATE REJECTION ⛔**
ALL scientific notation MUST use Float32() constructor.
No mixed syntax. No suffix notation. No exceptions.

**⛔ 64-BIT VARIABLE VIOLATION = IMMEDIATE REJECTION ⛔**
ALL computational variables MUST be 32-bit unless explicitly justified and approved.
No unauthorized Int64/UInt64. GPU compatibility is mandatory.

**⛔ UNAUTHORIZED DESIGN CHANGE = MAXIMUM VIOLATION = IMMEDIATE TASK TERMINATION ⛔**
ZERO TOLERANCE for any modification to functionality, interfaces, algorithms, or behavior without explicit written user authorization. ANY design change requires mandatory permission request format and explicit approval. NO EXCEPTIONS. NO ASSUMPTIONS. NO SILENT MODIFICATIONS.

**⛔ FORWARD REFERENCE VIOLATION = IMMEDIATE REJECTION ⛔**
ALL include/using statements MUST be in dependency order. NEVER reference undefined code.
ALL exports MUST be defined before being exported. NO forward references allowed.

**⛔ SESSION LOGGING VIOLATION = IMMEDIATE REJECTION ⛔**
ALL changes MUST be documented in session log as they are made. NO bulk logging at end.
NO changes without immediate documentation. Essential for context continuity.

**⛔ FILE PATH VIOLATION = IMMEDIATE REJECTION ⛔**
NEVER use dirname(@__DIR__) or directory navigation. ALWAYS use project root paths.
ALL file references MUST be "data/raw/file.txt" format from ComplexBiquadGA/ root.

**⛔ FUNCTION QUALIFICATION VIOLATION = IMMEDIATE REJECTION ⛔**
ALL cross-module function calls MUST be fully qualified with ModuleName.function_name().
NO unqualified calls that create namespace ambiguity or unclear dependencies.

**Confirmation Required**: Type "PROTOCOL ACKNOWLEDGED - ARTIFACT OR CANVAS OUTPUT MANDATORY - GPU COMPATIBILITY REQUIRED - DESIGN CHANGE AUTHORIZATION MANDATORY - MODULE DEPENDENCY ORDER REQUIRED - SESSION LOGGING MANDATORY - PROJECT ROOT PATHS MANDATORY - FULLY QUALIFIED FUNCTION CALLS MANDATORY" to confirm understanding of this updated framework.
