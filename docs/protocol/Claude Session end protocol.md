## 🚨 **Critical Session End Requirements**

### **Mandatory Session End Actions (R21 + Git Compliance):**
1. **Complete session log** with final summary
2. **Update session_state.md** with current status  
3. **Document next priorities** clearly
4. **Verify protocol compliance** for all changes
5. **Assess impact** on dependent systems
6. **Execute required Git operations** (see Git section below)

### **Quality Checks:**
1. **All code in proper locations** (not in chat)
2. **No unauthorized design changes** made
3. **All changes logged** in real-time
4. **Test status** documented
5. **Performance validated** if applicable

### **Git Operations at Session End:**

#### **MANDATORY Git Actions:**
1. **Stage ALL modified files** relevant to session work
   ```bash
   git add .
   ```

2. **Commit with descriptive message** following this format:
   ```bash
   git commit -m "Session YYYYMMDD_HHMM: [One-line summary]
   
   COMPLETED:
   • [Specific accomplishment 1]
   • [Specific accomplishment 2]
   
   TESTED:
   • [Test results or new tests]
   
   PROTOCOL:
   • [R/F compliance verification]
   
   FILES:
   • src/file.jl - [what changed]
   • test/test_file.jl - [what added]
   
   NEXT: [Priority for next session]"
   ```

3. **Verify no uncommitted work** remains
   ```bash
   git status  # Should show clean working tree
   ```

4. **Push to remote** if working on shared repository
   ```bash
   git push
   ```

5. **Document commit hash** in session log if needed

#### **FORBIDDEN Git Actions:**
❌ Committing without proper message
❌ Leaving modified files unstaged  
❌ Force pushing without justification
❌ Committing broken/failing tests
❌ Omitting session documentation

#### **Pre-Commit Validation:**
```bash
# Check for protocol violations
grep -r "@test_broken" test/  # Should return nothing (T37)
grep -r "Dict{" src/        # Check for GPU violations

# Ensure session log is complete  
ls -la change_tracking/sessions/session_$(date +%Y%m%d)*.md
```

---

## 📋 **Quick Reference**

### **Session End Input Command:**
```
"FINALIZE SESSION: Complete session log, update session_state.md with progress, stage and commit all changes with descriptive message, and prepare handoff for next session"
```

### **Essential Commands for Sessions**
```bash
# Session startup
cat change_tracking/session_state.md
touch change_tracking/sessions/session_YYYYMMDD_HHMM_description.md

# Code investigation  
cat src/TargetModule.jl
cat test/test_target_module.jl

# Session logging
echo "Progress update" >> change_tracking/sessions/current_session.md

# Status updates
cat > change_tracking/session_state.md << EOF
Updated status content
EOF

# Git operations (session end)
git add .
git status
git commit -m "Session $(date +%Y%m%d_%H%M): [Description]..."
git push
```

These commands are fundamental for navigating and documenting work in the ComplexBiquadGA project, especially for maintaining the strict session logging requirements (R21) and following the three-tier documentation system with proper Git workflow.