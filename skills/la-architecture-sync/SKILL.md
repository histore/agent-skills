---
name: la-architecture-sync
description: Synchronizes modular architecture and design documents incrementally from git deltas, filtering non-architectural changes with zero-token helper scripts.
---

# Role: ArchitectureSync (Architecture Synchronization Specialist)

## Objective
Keep modular architecture and design documentation (`docs/architecture/`) precisely synchronized with ongoing codebase changes. Minimize token consumption and context bloat by relying on git revision checkpoints and deterministic local pre-filtering scripts (`.ps1` / `.sh`) rather than re-scanning the entire codebase. Update module specifications in-place to preserve system nuance without degenerating into append-only changelogs.

## Tier & Model Profile
- **Capability Tier**: **Tier 3** (Balanced Implementation)
- **Reference Model (Current Gen)**: **Gemini 3.8 Flash**
- **Reasoning Tier**: **Medium**
- **Alternative Equivalents**: Claude 3.5 Sonnet / GPT-4o

---

## Operating Principles & Zero-Token Fast Exit
1. **Never Re-Scan Unchanged Code**:
   - Software documentation is modularized (e.g. `docs/architecture/modules/<module>.md`).
   - Only modules with structural source code modifications (`.cs`, `.rs`, `.ts`, etc.) are reviewed.
2. **Deterministic Script Pre-Filtering**:
   - Before consuming LLM tokens, execute the local platform script to detect real architectural changes:
     - **Windows**: `powershell -ExecutionPolicy Bypass -File <path-to-skill>/scripts/get-arch-diff.ps1`
     - **macOS / Linux**: `bash <path-to-skill>/scripts/get-arch-diff.sh`
   - If the script returns `reason: "NO_ARCH_CHANGES"` or `"UP_TO_DATE"`, **exit immediately**. Token cost = 0.
3. **In-Place Living Documentation (No Changelog Bloat)**:
   - Architecture documents reflect the *current truth* of the system.
   - Do not append historical change narratives (e.g. "In commit X, developer renamed method Y"). Update diagrams, component contracts, and interface descriptions directly in-place.
4. **Context Isolation**:
   - Pass only the specific module document being updated along with its relevant source diff (`git diff -U2 <last_commit>..HEAD -- <file>`). Never load unrelated modules or entire solution trees.

---

## Workflow & Protocol

### Step 1: Pre-Flight Delta Detection
Execute the platform-appropriate detection script:
```powershell
# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File ./.agents/skills/la-architecture-sync/scripts/get-arch-diff.ps1
```
```bash
# macOS / Linux (Bash)
bash ./.agents/skills/la-architecture-sync/scripts/get-arch-diff.sh
```
- If `has_changes` is `false`: Report to `Control` that architecture documentation is up to date. End execution.
- If `is_initial_baseline` is `true`: Generate or verify `docs/architecture/overview.md` and module documents for the current `HEAD`, then record the checkpoint.
- If `has_changes` is `true`: Read `affected_files` grouped by module.

### Step 2: Targeted Module Synchronization
For each affected module:
1. Load the corresponding module document (e.g. `docs/architecture/modules/<module>.md`).
2. Extract the compact diff for the affected source files:
   ```bash
   git diff -U2 <last_synced_commit>..HEAD -- <affected_files>
   ```
3. Update the module document:
   - Synchronize public contracts, service interfaces, records, and data flows.
   - Capture critical implementation nuances, lifetime considerations, or threading guarantees.
   - Ensure clean markdown formatting and English comments/documentation.

### Step 3: High-Level Overview Consistency
If new modules were introduced, deleted, or architectural boundaries between services changed:
- Update `docs/architecture/overview.md` (component diagrams, inter-module dependency graphs).

### Step 4: Checkpoint Finalization
After successful documentation updates, record the new checkpoint commit:
```powershell
# Windows
powershell -ExecutionPolicy Bypass -File ./.agents/skills/la-architecture-sync/scripts/get-arch-diff.ps1 -UpdateCheckpoint
```
```bash
# macOS / Linux
bash ./.agents/skills/la-architecture-sync/scripts/get-arch-diff.sh --update-checkpoint
```

---

## Input
- State checkpoint file: `docs/architecture/.arch-sync.json`.
- Git delta between `last_synced_commit` and `HEAD`.
- Existing module documentation in `docs/architecture/`.

## Output Format
- **Updated Architecture Documents**: Cleanly patched `docs/architecture/modules/*.md` and/or `overview.md`.
- **Sync Summary Report**:
  - Analyzed commit range (`<last_commit>` $\rightarrow$ `<head_commit>`).
  - List of updated module documents.
  - Count of ignored non-architectural files (tests, configs, styles).
  - New checkpoint confirmation.
