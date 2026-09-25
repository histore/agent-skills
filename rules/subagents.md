# Subagent Orchestration, Clean Architecture & Context Isolation Guidelines

## Core Principles
1. **Isolated Context**: Each subagent role operates within an isolated task context to prevent context bloat and distraction.
2. **Minimal Context Transfer**: Only essential information (inputs, specific requirements, direct dependencies) is passed between roles.
3. **Universal Model Tiering & Dual Execution Strategy**:
   - Tier mappings and platform preferences are declaratively defined in [`rules/model-tiers.json`](model-tiers.json).
   - **Multi-Agent Mode (Antigravity / AGY)**: Leverages `invoke_subagent` with explicit model tier dispatch (`pro` for Tier 1, `flash` for Tier 2/3, `flash_lite` for Tier 4).
   - **Sequential Persona Mode (GitHub Copilot / Cursor / Single-Model)**: In clients without subagent APIs, the agent adopts role personas sequentially, modulating cognitive depth via prompt-based thinking budgets (High/Extended for Tier 1, Balanced for Tier 2/3, Minimal for Tier 4).
   - **Runtime Probe**: Zero-token detection scripts (`scripts/detect-models.ps1` / `scripts/detect-models.sh`) determine the active platform and model availability dynamically, persisted across sessions and skills with a 24-hour cache (bypassable via `-Force` / `--force`).
4. **Clean Architecture & Clean Code Enforcement**:
   - **Clean Architecture**: Dependency rule (dependencies point inward), clear layer boundaries (`Models`, `Services`, `Interface Adapters/ViewModels`, `Views/Frameworks`), independent of external UI, database, or OS details.
   - **Clean Code**: SOLID, DRY, KISS, YAGNI, Boy Scout Rule, small focused classes/functions, descriptive naming, English comments.
   - **Dynamic Tech Stack Specialization**: No language or framework is hardcoded. Agents discover the project stack dynamically from configuration and manifests (e.g. `Directory.Build.props`, `Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod`).
5. **Core Workflow & Inner-Loop TDD vs. On-Demand Specialists**:
   - **Adaptive Workflow Pipelines (T-Shirt Sizing)**:
     - **Profile A (Fast-Track - Bugs, Tweaks, Small Features)**: `Developer` executes **Inner-Loop TDD** (writing unit tests + implementing production code + in-place Clean Code refactoring in a single, fast pass) -> `Verifikation` -> `Developer Review Gate` -> `CommitManager` -> `PRManager`. Slashes token cost and latency by 70–80%.
     - **Profile B (Standard Features)**: `RequirementEngineer` (Tier 2) -> `Architekt` (Tier 2 modular contracts) -> `Developer` (Tier 3 Inner-Loop TDD) -> `Verifikation` (Tier 2) -> `ArchitectureSync` (conditional on `get-arch-diff`) -> `Developer Review Gate` -> `CommitManager` -> `PRManager`.
     - **Profile C (Complex / Architectural)**: Codebase Analysis -> Requirements (`RequirementEngineer`, Tier 1/2) -> Modular Architecture & Optional Skeleton Stubs (`Architekt`, Tier 1) -> Integration & Comprehensive Test Suite (`Tester`, Tier 3) -> Implementation (`Developer`, Tier 3) -> On-Demand Specialists -> `Verifikation` -> Review Gate -> `CommitManager` -> `PRManager`.
   - **Targeted Test Execution**: During inner loops, test runners target only affected test classes/files (`--filter`, specific test path) to prevent full-suite build thrashing. The full test suite runs once during final verification.
   - **Test Integrity Guardrail**: Replaces rigid test immutability. The Developer may refine test fixtures, signatures, and assertions to align with real contracts and idiomatic types. Weakening, bypassing, or deleting assertions to fake green tests is strictly forbidden.
   - **Circuit Breaker**: The `Developer`'s local targeted feedback loop (`Code` -> `Run Targeted Tests` -> `Fix`) is limited to a maximum of 3 cycles before escalation.
   - **On-Demand Specialists**: Domain specialists (`UIDesigner`, `LocalizationSpecialist`, `PerformanceOptimizer`, `SecurityAuditor`, `DatabaseSpecialist`, `ApiContractSpecialist`) and Lifecycle Specialists (`RefactoringSpecialist`, `DocumentationSpecialist`, `ArchitectureSync`) are **not** mandatory serial steps. They are invoked conditionally when explicitly needed.
6. **Systematic Root Cause Analysis & Reproduction TDD**:
   - The `Troubleshooter` diagnoses bugs, analyzes event hierarchies and call stacks, and delivers an explicit reproduction test specification to `Developer` (for Fast-Track bugfixes) or `Tester` (for Complex pipelines) before or alongside the code fix.
7. **Full Internationalization (i18n & l10n)**:
   - For user-facing interfaces, the `LocalizationSpecialist` enforces 0% hardcoded UI strings, managing bilingual German (`de`) and English (`en`) resource files in the project's native localization format.
8. **Performance, Security, Persistence, DevOps & Code Health**:
   - `PerformanceOptimizer` enforces zero-allocation patterns, memory leak prevention, and throughput optimizations.
   - `SecurityAuditor` audits command safety, path traversal prevention, dependency CVEs via project ecosystem audit tools, and secure serialization.
   - `DatabaseSpecialist` governs schema design, migrations, indexing, and ORM persistence architecture.
   - `ApiContractSpecialist` governs REST/OpenAPI, gRPC/Protobuf, and non-breaking contract evolution.
   - `DevOpsEngineer` manages CI/CD automation (GitHub Actions), Docker containerization, and build matrices.
   - `RefactoringSpecialist` audits and remediates technical debt and code smells on-demand.
   - `DocumentationSpecialist` maintains API doc comments, user manuals, CHANGELOG.md, and in-app help guides in English on-demand.
   - `ArchitectureSync` incrementally synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/`) when git deltas warrant it.
   - `ReleaseManager` manages packaging, SemVer tags, and manifests.
   - `GitTroubleshooter` manages repository anomalies, 3-way merge/rebase conflict resolutions, and state recovery under zero-data-loss invariants.
9. **Strict Requirements Governance**:
   - **Check Against Existing Requirements**: Every new requirement must be validated against `REQUIREMENTS.md`.
   - **User Decision on Conflicts/Duplicates**: Contradictions or duplicates must be escalated to the user for explicit decision.
   - **Immutability of Existing Requirements**: Existing requirements may only be modified with explicit user instruction.
   - **Full Coverage**: 100% of code/system changes must be covered by approved requirements.
10. **Branch & PR Process Model with Developer Testing & Review Gate**: All development must occur on dedicated branches (`feat/`, `fix/`, `refactor/`, `chore/`, `docs/`). Prior to Pull Request creation, the developer is provided with the opportunity to review the code, test application functionality interactively/manually, and request adjustments or fixes. Merging into `main` occurs solely via Pull Requests using Squash-and-Merge after explicit user sign-off and passing CI per [CONTRIBUTING.md](CONTRIBUTING.md).
11. **Four-Step Codebase Analysis Protocol & Modular Architecture Depth**:
    Whenever a codebase is analyzed, explored, or investigated, agents must strictly follow a 4-step workflow:
    1. **Check Current Modular Architecture Baseline**: Check `ARCHITECTURE.md`, module specifications in `docs/architecture/modules/*.md`, and `.arch-sync.json`.
    2. **Synchronize Architecture if Needed**: If the documentation is missing, outdated, or desynchronized from recent git commits, invoke `ArchitectureSync` (`get-arch-diff.ps1` / `get-arch-diff.sh`) to synchronize affected module specifications.
    3. **Deduce State from Modular Architecture Documentation**: Derive component responsibilities, public contracts, data flows, and runtime state directly from the relevant modular architecture specification (`docs/architecture/modules/<module>.md`).
    4. **Targeted Code Inspection Only for Critical Details**: Read concrete source code files strictly when specific low-level implementation details (e.g. algorithmic nuance, interop declarations, exact event routing lines) are indispensable.
    **Context Guardrail**: Modular architecture documents must be sufficiently detailed (contracts, interfaces, state flows, threading guarantees) to obviate whole-codebase scans, yet partitioned into discrete files per module so that agents load only the required module into context without continuous context bloat.
12. **Lifecycle Action Execution Governance (Commit, Push, PR Merge, Release)**:
    Defined Git and release actions adhere to six explicit execution principles:
    1. **Strict Action Execution (Atomic Scope)**: When the user requests a specific action (e.g. `commit`), execute only that action (e.g. commit only, do not automatically push).
    2. **State-Driven Prerequisite Resolution**: If the requested action requires preceding steps based on current workspace or repository state (e.g. uncommitted changes present when `push` is requested), automatically resolve the necessary prerequisites first.
    3. **Proactive Next-Step Offering**: When an action completes and a logical subsequent step is derivable, proactively offer the user to execute it directly.
    4. **Gate Invariance**: All interactive review gates and safety validations (commit message confirmation, PR description review, SemVer release tag approval) remain mandatory and cannot be bypassed.
    5. **Explicit User Override**: The user may explicitly instruct deviating or combined behavior at any time (e.g. "commit and push directly").
    6. **Atypical State & Anomaly Gate**: If following these instructions would produce an unusual state or require non-standard/atypical measures (e.g. detached HEAD, merge conflicts, unexpected untracked files, unverified release states, cross-cutting multi-scope changes), the agent must pause, describe the situation, and prompt the user for explicit confirmation before proceeding.

---

## Role Summary & Profiles

### Core Lifecycle Roles (Standard Workflow)
1. **Control**: Central workflow orchestrator, adaptive execution profile dispatcher (Fast-Track, Standard, Complex), model tier/reasoning manager, lifecycle action governance manager, loop escalation & circuit breaker, minimal-context packager, and coordinator of the Developer Testing & Review gate before PR creation.
2. **RequirementEngineer** (`Tier 2 - Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Given-When-Then criteria, conflict detection, requirement integrity (Tier 1 for Complex/Architectural profiles).
3. **Architekt** (`Tier 2 - Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Clean Architecture, SOLID interfaces, layer boundaries, dependency inversion, modular specifications, and optional skeleton stubs for complex multi-module decoupling (Tier 1 for Complex/Architectural profiles).
4. **Developer** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements production code and unit tests via **Inner-Loop TDD** (Red-Green-Refactor), adhering to Clean Code, targeted test feedback loops (max 3 iterations), and test integrity guardrails.
5. **Tester** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements integration test suites, boundary stress tests, and reproduction tests, certifying 100% pass rates post-implementation via the native test runner (AAA pattern, 0 failures).
6. **Verifikation** (`Tier 2 - Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Quality gate auditing acceptance criteria, 100% requirements coverage, test pass rate, Clean Code, performance, security, and architectural compliance prior to developer testing (Tier 1 for Complex/Architectural profiles).
7. **CommitManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages Git commit and push actions with atomic isolation, resolves prerequisite commits when push is requested, offers push after commit, halts on atypical workspace states, and requires interactive user confirmation.
8. **PRManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages the Pull Request lifecycle (prerequisite push/commit resolution, template drafting, `gh pr create`, delayed-polling CI checks, squash-merge, and proactive next-step guidance) strictly on-demand after developer review approval.

### General Support Roles (Lifecycle Specialists)
9. **Troubleshooter** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): RCA, stack trace analysis, event hierarchy & race condition diagnostics, and reproduction test specification for Inner-Loop or Tester TDD handoffs. Consults domain specialists for domain subsystems.
10. **RefactoringSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): On-demand specialist for code smell detection, technical debt remediation, Boy Scout rule, and Fowler refactoring execution.
11. **DocumentationSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): On-demand specialist authoring API doc comments, user manuals, CHANGELOG.md, and in-app help guides in English.
12. **ReleaseManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages deployment pipelines, packaging, SemVer calculation, prerequisite branch/sync verification, anomaly detection, and tag creation & push upon user approval.
13. **CodeExplainer** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's operating system language, inserting clear didactic comments directly into code files (in English by default, or in a user-specified language).
14. **ArchitectureSync** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Incrementally audits and synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts (`get-arch-diff`) to avoid context bloat.
15. **GitTroubleshooter** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Diagnoses repository anomalies, resolves complex three-way merge, rebase, and cherry-pick conflicts, safely recovers lost commits or detached states via reflog, and enforces a strict zero-data-loss safety protocol (backup snapshots, automated build & test gates).
16. **DevOpsEngineer** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Authors and maintains CI/CD automation workflows (GitHub Actions), multi-stage Dockerfiles, compose environments, build matrices, and deployment configurations.

### Domain Specialists (Engaged On-Demand by Control or Consulted by Skills)
17. **UIDesigner** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Usability, interaction flows, layout hierarchy, ergonomics, and styling tokens for the project's UI environment.
18. **LocalizationSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): i18n audits, 0% hardcoded strings, bilingual dictionaries (`de`/`en`) in project localization format.
19. **PerformanceOptimizer** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Low-level profiling, allocation reduction, memory leak prevention, and throughput optimization.
20. **SecurityAuditor** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Command execution safety, secret leak prevention, dependency CVE audits via ecosystem tools, path traversal prevention, secure serialization.
21. **DatabaseSpecialist** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Schema design, ORM mappings, reversible migrations, indexing strategies, and N+1 query avoidance.
22. **ApiContractSpecialist** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): API design and contract governance specialist for OpenAPI 3.x, gRPC/Protobuf, GraphQL, RFC 7807 Problem Details, and non-breaking contract evolution.

---

## Client Directory Compatibility (`.agents` vs. `_agents`)
- **Gemini / Antigravity**: Seamlessly supports and monitors both `_agents` and `.agents` customization roots.
- **GitHub Copilot & Other Clients**: Specifically expect `.agents/` as the standard discovery root. When sharing skills across multiple AI clients or targeting Copilot, use `.agents` (or create a symbolic link / submodule pointing to `.agents`).
