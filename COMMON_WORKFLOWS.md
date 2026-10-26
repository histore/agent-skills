# Common Engineering Workflows (`COMMON_WORKFLOWS.md`)

This guide outlines standard development workflows and concrete invocation patterns across both **Google Antigravity (AGY / Gemini)** and **GitHub Copilot (VS Code & CLI)**.

All workflows leverage deterministic zero-token helper scripts ([`scripts/`](scripts/)), adaptive execution profiles, and strict engineering invariants (Clean Code, Clean Architecture, Safe Rust, Inner-Loop TDD).

---

## Overview: Execution Paradigm Differences

| Workflow Aspect | Google Antigravity (AGY) | GitHub Copilot |
| :--- | :--- | :--- |
| **Execution Mode** | Multi-Agent Orchestration (`invoke_subagent`) & persistent session | Single-Thread Sequential Persona Transitions (`### [Phase: ...]`) |
| **Default Entry Point** | `/ask-control <task>` or automatic via `~/.gemini/GEMINI.md` | Start conversation directly; governed by `.github/copilot-instructions.md` |
| **Zero-Reload Invariant** | Core roles (`Developer`, `Verifikation`, `CommitManager`) are embedded | Core rules are embedded in `copilot-instructions.md`; never read `SKILL.md` for core roles |
| **On-Demand Specialists** | Loaded dynamically per slash command or subagent dispatch | Referenced explicitly on-demand (e.g. `Consult skills/<name>/SKILL.md`) |
| **Quality Gates** | Native Stage-1 script (`run-fast-gate.ps1`) + interactive modal review | Native Stage-1 script (`run-fast-gate.ps1`) + sequential verification audit |

---

## 1. Informational & Architectural Inquiries (Profile 0)

Read-only analysis, explanations, and codebase orientation.
**Invariants**: Zero Git commands (`git status`, `git branch`), zero test executions, concise direct response.

### Antigravity (AGY)
```text
/ask-control Explain the architecture of the authentication module and the token refresh flow.
```
*Behind the scenes*: `Control` assigns Class ECO (`flash`, minimal reasoning), inspects `ARCHITECTURE.md` and `docs/architecture/modules/`, and answers directly without running test suites or Git commands.

### GitHub Copilot
```text
Explain the architecture of the authentication module and the token refresh flow.
```
*Behind the scenes*: Copilot identifies Profile 0, suppresses build and test executions, and provides an architectural explanation directly in the chat.

---

## 2. Fast-Track Bugfix & Localized Tweaks (Profile A)

Small fixes, compiler warning resolutions, minor documentation updates.
**Invariants**: Bypass upfront requirements/architecture ceremony. Red-Green-Refactor inner loop (max 3 iterations). Zero tests for markdown-only changes.

### Antigravity (AGY)
```text
/ask-control Fix the NullReferenceException in UserMapper when email is null.
```
*Workflow*: `Developer` writes failing reproduction test $\rightarrow$ fixes root cause $\rightarrow$ runs Stage-1 fast gate $\rightarrow$ hands off to `Verifikation` $\rightarrow$ `CommitManager`.

### GitHub Copilot
```text
Fix the NullReferenceException in UserMapper when email is null.
```
*Workflow*: Copilot enters sequential execution:
```markdown
### [Phase: Developer]
- Author failing unit test in test/UserMapperTests.cs
- Implement null-safe fallback in src/UserMapper.cs
- Validate: pwsh -NoProfile -File ./scripts/run-fast-gate.ps1

### [Phase: Verifikation]
- Assert 100% test pass rate and Clean Code compliance.
```

---

## 3. Standard Feature Implementation (Profile B)

Typical domain or application service features requiring contracts, unit tests, and Stage-2 verification.

### Antigravity (AGY)
```text
/ask-control Implement a new ExportService supporting JSON and CSV formats.
```
*Workflow*:
1. `ContractSpecialist` / `Control`: Acceptance criteria (Given-When-Then).
2. `Architekt` (Phase): Service interfaces and Clean Architecture boundary contracts.
3. `Developer` (Phase): Inner-Loop TDD authoring unit tests before production code.
4. `Verifikation` (Phase): Stage 1 machine checks + Stage 2 traceability review.
5. `CommitManager` (Phase): Conventional commit proposal & interactive confirmation.

### GitHub Copilot
```text
Implement a new ExportService supporting JSON and CSV formats.
```
*Workflow*:
Copilot executes in sequential phases:
1. `### [Phase: Architekt]`: Outlines contracts in `IExportService`.
2. `### [Phase: Developer]`: Inner-Loop TDD, runs `pwsh -NoProfile -File ./scripts/run-fast-gate.ps1`.
3. `### [Phase: Verifikation]`: Two-stage verification sign-off.
4. Proactively suggests commit command.

---

## 4. Complex Subsystem Redesign & Architectural Shifts (Profile C)

Cross-cutting refactorings, persistence redesigns, or stubborn distributed deadlocks.
**Invariants**: Mandatory Quota Protection User Gate before token-heavy consumption.

### Antigravity (AGY)
```text
/ask-control --premium Refactor the entire persistence and transaction layer to Unit of Work.
```
*(If `--premium` or `--eco` is omitted, `Control` displays an interactive selection modal via `ask_question`: `[1] Premium`, `[2] Balanced`, `[3] Eco`.)*

### GitHub Copilot
```text
Refactor the entire persistence and transaction layer to Unit of Work.
```
*Workflow*: Copilot outputs the Quota Protection Gate in chat:
> `[Quota Gate] Profile C detected. Choose [1] Premium (Deep Thinking), [2] Balanced (70% savings), or [3] Eco (Fast).`
After the user confirms, Copilot executes sequentially.

---

## 5. Concept Ideation, Refinement & Distillation

Before committing code or formal specifications, exploratory ideas, architectural RFCs, and user proposals start as drafts in `docs/concepts/drafts/`.

Depending on task complexity and governance needs, teams choose between two identical workflows across both **Antigravity (AGY)** and **GitHub Copilot**:
- **Track A (`concept > req > impl`)**: Standard / Complex Lifecycle (Full traceability, Living Modular Docs).
- **Track B (`concept > impl`)**: Fast-Track / Prototype Lifecycle (Direct implementation from approved concept).

```text
+-------------------------------------------------------------------------------------------------+
|                                Step 1: Concept Drafting                                         |
|                 docs/concepts/drafts/CONCEPT-<SCOPE>-XXX-<slug>.md                              |
|                 (Scaffolded via: inspect-feature-specs.ps1 -NewConcept)                         |
+------------------------------------------------+------------------------------------------------+
                                                 |
                        +------------------------+------------------------+
                        |                                                 |
                        v                                                 v
         [Track A: concept > req > impl]                     [Track B: concept > impl]
        (Standard / Enterprise Features)                   (Fast-Track / MVP / Prototypes)
                        |                                                 |
                        v                                                 v
           Step 2: Formal Distillation                       Step 2: Direct Implementation
     - Distill to docs/features/FEAT-*.md               - Refined draft acts as contract
     - Given-When-Then Acceptance Criteria              - Inner-Loop TDD (Developer)
     - Archive draft to docs/concepts/archive/          - Archive draft to docs/concepts/archive/
                        |                                                 |
                        v                                                 v
           Step 3: Implementation Gate                       Step 3: Quality Verification
     - Architekt defines contracts                      - Stage-1 Fast Gate (run-fast-gate.ps1)
     - Developer Inner-Loop TDD                         - Zero-reload verification audit
     - Verifikation against FEAT-*.md AC
```

---

### Step 1: Scaffold Concept Draft (Identical in Both Systems)
Always start by generating the concept draft from [`docs/templates/CONCEPT_TEMPLATE.md`](docs/templates/CONCEPT_TEMPLATE.md) using the deterministic zero-token script:

```powershell
# Windows (PowerShell)
pwsh -NoProfile -File ./scripts/inspect-feature-specs.ps1 -NewConcept -ConceptId "CONCEPT-AUTH-001" -Title "OAuth2 PKCE Login"

# Linux / macOS (Bash)
bash ./scripts/inspect-feature-specs.sh --new-concept --concept-id "CONCEPT-AUTH-001" --title "OAuth2 PKCE Login"
```
*(Creates `docs/concepts/drafts/CONCEPT-AUTH-001-oauth2-pkce-login.md`. Standard is plural `docs/concepts/`; automatically supports legacy `docs/concept/` projects without path collisions.)*

---

### Track A: Full Lifecycle (`concept > req > impl`)
Use for standard features (Profile B) and complex architectures (Profile C) where formal requirements, living roadmap registration, and long-term traceability are required.

#### Step A.1: Refine Concept & Distill into Formal Requirement Specification
Review and refine the draft in-place with the user. Distill into a formal feature specification (`docs/features/FEAT-<SCOPE>-XXX-<slug>.md`) with Given-When-Then acceptance criteria, resolving or escalating any contradictions with existing requirements.
* **Antigravity (AGY)**:
  ```text
  /ask-contract-specialist Refine concept CONCEPT-AUTH-001 with me, distill it into docs/features/FEAT-AUTH-001-oauth2-pkce.md, and archive the concept draft.
  ```
* **GitHub Copilot**:
  ```text
  Consult skills/ask-contract-specialist/SKILL.md. Review docs/concepts/drafts/CONCEPT-AUTH-001-*.md, distill into docs/features/FEAT-AUTH-001-oauth2-pkce.md with Given-When-Then criteria, and archive the draft via ./scripts/inspect-feature-specs.ps1 -ArchiveConcept "CONCEPT-AUTH-001".
  ```

#### Step A.2: Implement from Formal Feature Specification
Downstream implementation reads **strictly** the single target `FEAT-*.md` specification. It **never** reads `docs/concepts/`, preserving KV-cache and preventing context drift.
* **Antigravity (AGY)**:
  ```text
  /ask-control Implement feature specification docs/features/FEAT-AUTH-001-oauth2-pkce.md via Profile B.
  ```
* **GitHub Copilot**:
  ```text
  Implement docs/features/FEAT-AUTH-001-oauth2-pkce.md according to .github/copilot-instructions.md (Profile B: contracts -> Developer Inner-Loop TDD -> Two-Stage Quality Gate).
  ```

---

### Track B: Fast-Track Direct Implementation (`concept > impl`)
Use for rapid exploratory prototypes, internal developer tooling, or small focused capabilities where formal requirement registration (`docs/features/` or `REQUIREMENTS.md`) would add unnecessary ceremony.

#### Step B.1: Refine Concept Draft
Refine the problem statement, selected technical approach, and core invariants directly inside `docs/concepts/drafts/CONCEPT-<SCOPE>-XXX.md` with the user.

#### Step B.2: Direct Implementation & Archival
The refined concept serves directly as the temporary working contract. The concept draft is archived immediately to `docs/concepts/archive/` to keep active context pristine, and implementation proceeds directly via Developer Inner-Loop TDD:
* **Antigravity (AGY)**:
  ```text
  /ask-control Implement concept docs/concepts/drafts/CONCEPT-AUTH-001-*.md directly via Profile A (Fast-Track), archive the draft via inspect-feature-specs.ps1 -ArchiveConcept, and run Stage-1 fast-gate.
  ```
* **GitHub Copilot**:
  ```text
  Implement docs/concepts/drafts/CONCEPT-AUTH-001-*.md directly via Profile A (Fast-Track) Developer Inner-Loop TDD. Archive the concept via pwsh -NoProfile -File ./scripts/inspect-feature-specs.ps1 -ArchiveConcept "CONCEPT-AUTH-001" and validate via ./scripts/run-fast-gate.ps1.
  ```

#### Invariant for Both Systems in Track B:
- **Zero-Stale-Draft Invariant**: The draft in `docs/concepts/drafts/` MUST be archived to `docs/concepts/archive/` so that unverified drafts do not linger in the active workspace.
- **Clean Architecture & Safe Rust Invariant**: Direct implementation skips requirement ceremony, but NEVER skips Clean Code, Clean Architecture, unit test authoring, or compiler validation (`run-fast-gate.ps1`).

---

## 6. Adversarial Code Review & Security Auditing

Hunting subtle boundary flaws, race conditions, memory leaks, and dependency CVEs.

### Antigravity (AGY)
```text
# Adversarial Code Review & Refactoring Audit
/ask-troubleshooter Perform an adversarial review of changes in src/auth for concurrency bugs and edge cases.

# Security & Secret Audit
/ask-release-manager Audit the project for secret leaks, dependency CVEs, and safe Rust integrity.
```

### GitHub Copilot
```text
# Adversarial Code Review
Consult skills/ask-troubleshooter/SKILL.md and inspect current changes in src/auth for race conditions, boundary state errors, and resource leaks.

# Security Audit (with zero-token script)
pwsh -NoProfile -File ./scripts/run-security-audit.ps1
Consult skills/ask-release-manager/SKILL.md to analyze the security audit findings.
```

---

## 7. Git Anomalies, Merge Conflicts & Safe Recovery

Strict **Zero-Data-Loss Safety Protocol**: Always create safety backup snapshots before rebase/merge operations.

### Step 1: Diagnose Git State (Zero-Token CLI)
```powershell
pwsh -NoProfile -File ./scripts/diagnose-git-state.ps1
```

### Step 2: Resolve Conflict
* **Antigravity (AGY)**:
  ```text
  /ask-git-troubleshooter Rebase onto origin/main failed. Create a safety backup and resolve three-way merge conflicts safely.
  ```
* **GitHub Copilot**:
  ```text
  Load skills/ask-git-troubleshooter/SKILL.md. Create a safety backup via ./scripts/create-safety-backup.ps1 and guide me step-by-step through the conflict resolution.
  ```

---

## 8. Architecture Synchronization from Git Deltas

Keeps `ARCHITECTURE.md` and `docs/architecture/modules/*.md` synchronized with production commits without reading the whole repository. Supports both **in-repository** storage (`internal`, default) and **external zero-footprint** storage (`external`, stored in `.git/config` under `arch-sync.doc-dir`).

### Optional: Configure External Zero-Footprint Storage
```powershell
# Store architecture docs outside the repository (0 git footprint)
pwsh -NoProfile -File ./scripts/get-arch-diff.ps1 -SetDocDir "C:\arch-docs\my-project" -SetMode external
```

### Step 1: Pre-Filter Git Deltas (Zero-Token CLI)
```powershell
pwsh -NoProfile -File ./scripts/get-arch-diff.ps1
```

### Step 2: Synchronize Specifications & Advance Checkpoint
* **Antigravity (AGY)**:
  ```text
  /ask-contract-specialist Synchronize module architecture documentation based on recent git commits.
  ```
* **GitHub Copilot**:
  ```text
  Consult skills/ask-contract-specialist/SKILL.md, update the architecture documentation at the resolved doc_dir based on get-arch-diff.ps1, and advance the checkpoint via -UpdateCheckpoint.
  ```

---

## 9. Atomic Git Commit & Remote Push Governance

Strictly atomic: `commit` never auto-pushes; `push` automatically initiates prerequisite commit checks.

### Antigravity (AGY)
```text
# Commit only (no push)
/ask-control Commit the changes with an appropriate conventional commit message.

# Push (resolves uncommitted changes beforehand)
/ask-control Push the current feature branch to origin.
```

### GitHub Copilot
```text
# Pre-Commit Guardrail Scan
pwsh -NoProfile -File ./scripts/scan-guardrails.ps1

# Commit via Copilot
Draft a conventional commit message for current changes and commit upon my confirmation (do not push).
```

---

## 10. SemVer Tagging & Release Workflow

Deterministically calculate the next SemVer bump from Conventional Commits and tag directly on `main`.

### Step 1: Calculate Next SemVer Version (Zero-Token CLI)
```powershell
# Windows
pwsh -NoProfile -File ./scripts/calculate-semver.ps1

# Linux / macOS
bash ./scripts/calculate-semver.sh
```

### Step 2: Execute Release
* **Antigravity (AGY)**:
  ```text
  /ask-release-manager Create a new release tag for changes on main.
  ```
* **GitHub Copilot**:
  ```text
  Consult skills/ask-release-manager/SKILL.md. Generate the changelog via ./scripts/generate-changelog.ps1 and apply the calculated Git tag directly to HEAD on main.
  ```

---

## 11. Dual-Assistant Cheat Sheet (Quick Reference)

| Task | Deterministic Script | AGY Command | Copilot Prompt |
| :--- | :--- | :--- | :--- |
| **Stage 1 Fast Gate** | `./scripts/run-fast-gate.ps1` | `/ask-control` | `pwsh -NoProfile -File ./scripts/run-fast-gate.ps1` |
| **All Quality Gates** | `./scripts/run-all-gates.ps1` | `/ask-control` | `pwsh -NoProfile -File ./scripts/run-all-gates.ps1` |
| **Scaffold Concept** | `./scripts/inspect-feature-specs.ps1 -NewConcept` | `/ask-contract-specialist` | `inspect-feature-specs.ps1 -NewConcept` + prompt |
| **Archive Concept** | `./scripts/inspect-feature-specs.ps1 -ArchiveConcept` | `/ask-contract-specialist` | `inspect-feature-specs.ps1 -ArchiveConcept` |
| **Living Spec Status**| `./scripts/inspect-feature-specs.ps1 -CheckDrift` | `/ask-contract-specialist` | `inspect-feature-specs.ps1 -CheckDrift` |
| **Secret & Rust Scan**| `./scripts/scan-guardrails.ps1` | `/ask-release-manager` | `scan-guardrails.ps1` + prompt |
| **Merge / Git Fix** | `./scripts/diagnose-git-state.ps1` | `/ask-git-troubleshooter` | `Consult skills/ask-git-troubleshooter/SKILL.md` |
| **Clean Architecture**| `./scripts/lint-clean-architecture.ps1` | `/ask-troubleshooter` | `lint-clean-architecture.ps1` + prompt |
| **i18n Key Parity** | `./scripts/audit-i18n.ps1` | `/ask-contract-specialist` | `audit-i18n.ps1` + prompt |
| **Next SemVer Tag** | `./scripts/calculate-semver.ps1` | `/ask-release-manager` | `calculate-semver.ps1` + prompt |
