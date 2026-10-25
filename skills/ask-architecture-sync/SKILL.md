---
name: ask-architecture-sync
description: Synchronizes modular architecture and design documents incrementally from git deltas, filtering non-architectural changes with zero-token helper scripts.
argument-hint: "[module or documentation scope to synchronize]"
---

# Role: ArchitectureSync (Architecture Synchronization Specialist)

## User Request / Arguments
$ARGUMENTS

When `$ARGUMENTS` is provided (e.g. via `/ask-architecture-sync <scope>`), treat it as the target module or synchronization scope.
If `$ARGUMENTS` is empty or omitted, analyze git diffs from the checkpoint to detect and synchronize architectural drift.

## Objective
Keep the top-level architecture blueprint (`ARCHITECTURE.md`) and modular specifications (`docs/architecture/modules/`) precisely synchronized with ongoing codebase changes. Minimize token consumption and context bloat by relying on git revision checkpoints and deterministic local pre-filtering scripts (`.ps1` / `.sh`) rather than re-scanning the entire codebase.

Maintain module documents at a level of depth (public contracts, interfaces, state flows, dependencies, threading guarantees) that enables subsequent agents to deduce system state directly and obviates large-scale source code scans. Concurrently, strict file modularity (`docs/architecture/modules/<module>.md`) ensures that agents only need to load the single relevant module into context, preventing continuous context window exhaustion.

Model capability tiers, reference models, and calibrated thinking budgets are dynamically resolved from the Single Source of Truth: [`rules/model-tiers.json`](../../rules/model-tiers.json) (Tier 3: Balanced).

---

## Operating Principles & Context Guardrails
1. **Single Entry Point & Modular Specifications**:
   - The top-level `ARCHITECTURE.md` serves as the primary system entry point (system purpose, Clean Architecture layers, cross-cutting rules, and module index).
   - Component details, contracts, and data flows are maintained modularly in `docs/architecture/modules/<module>.md`.
   - Never create duplicate overview documents (e.g. do not maintain a redundant `docs/architecture/overview.md`).
2. **High Architectural Depth to Prevent Broad Code Scans**:
   - Specifications must capture public interfaces, records/DTOs, component lifecycle, event propagation, and concurrency constraints.
   - Depth must be sufficient that 90%+ of architectural and investigative queries can be answered solely from the module document without inspecting raw source code.
3. **Strict Modular Isolation Against Context Bloat**:
   - Isolate each logical component into its own file (`docs/architecture/modules/<module>.md`).
   - Consumers (Control, Explainer, Troubleshooter, Developer) load *only* the specific module file relevant to their task, ensuring the LLM context window remains lean and never fills up continuously.
4. **Never Re-Scan Unchanged Code**:
   - Only modules with structural source code modifications (`.cs`, `.rs`, `.ts`, etc.) are reviewed.
5. **Deterministic Script Pre-Filtering**:
   - Before consuming LLM tokens, execute the local platform script to detect real architectural changes:
     - **Windows**: `pwsh -NoProfile -ExecutionPolicy Bypass -File <path-to-scripts>/get-arch-diff.ps1`
     - **macOS / Linux**: `bash <path-to-scripts>/get-arch-diff.sh`
     - If the script returns `reason: "NO_ARCH_CHANGES"` or `"UP_TO_DATE"`, **exit immediately**. Token cost = 0.
6. **In-Place Living Documentation (No Changelog Bloat)**:
   - Architecture documents reflect the *current truth* of the system.
   - Do not append historical change narratives (e.g. "In commit X, developer renamed method Y"). Update diagrams, component contracts, and interface descriptions directly in-place.
7. **Context Isolation**:
   - Pass only the specific module document being updated along with its relevant source diff (`git diff -U2 <last_commit>..HEAD -- <file>`). Never load unrelated modules or entire solution trees.

---

## Storage Modes & Zero-Footprint Configuration (Internal vs. External)

Architecture documentation and checkpoints can be stored either **internally** within the project repository or **externally** in a separate directory/repository.

### Storage Modes:
- **Internal Mode (Default)**:
  - Documentation resides in `<RepoRoot>/docs/architecture/` (with root `ARCHITECTURE.md`).
  - Checkpoint resides in `<RepoRoot>/docs/architecture/.arch-sync.json`.
- **External Mode**:
  - Documentation and checkpoints reside completely outside the project repository (e.g. in a centralized architecture hub).
  - **Zero Project Footprint**: The project repository contains **no files, no directories, and no git diffs** related to the architecture documentation.

### Project-Level Configuration Without Repository Footprint:
To configure external storage on project level without creating tracked files or git noise in the workspace, utilize Git's private local configuration:
```bash
# Configure via git directly:
git config --local arch-sync.doc-dir "C:/path/to/external-architecture-docs/project-a"

# Or via the script helper:
pwsh -NoProfile -File ./_agents/scripts/get-arch-diff.ps1 -SetDocDir "C:/path/to/external-architecture-docs/project-a"
# Or if mounted under .agents (e.g. Copilot):
# pwsh -NoProfile -File ./.agents/scripts/get-arch-diff.ps1 -SetDocDir "C:/path/to/external-architecture-docs/project-a"
# macOS / Linux:
bash ./_agents/scripts/get-arch-diff.sh --set-doc-dir "/path/to/external-architecture-docs/project-a"
```
*The setting is recorded in `.git/config` which is strictly local and never tracked or committed by Git.*

### Intentional Override Hierarchy:
The target documentation directory is resolved dynamically in strict priority order (highest to lowest):
1. **CLI Parameter (Immediate Override)**: `-DocDir <path>` / `--doc-dir <path>`
2. **Environment Variable**: `$env:ARCH_SYNC_DOC_DIR` / `ARCH_SYNC_DOC_DIR`
3. **Project-Level Git Config (Zero Footprint)**: `git config --local --get arch-sync.doc-dir`
4. **User Global Git Config**: `git config --global --get arch-sync.external-base-dir` (appended with repository name)
5. **Default Fallback**: `<RepoRoot>/docs/architecture`

---

## Tooling & Path Compatibility (`.agents` vs. `_agents`)
- **Embedding Host Project Target**: When mounted as a submodule (`_agents/` for Antigravity, `.agents/` for Copilot), all operations target the embedding host repository.
- **Submodule Asset Resolution**: Internal skill assets and rules reside in `./_agents/`, `./.agents/`, or `./`.
