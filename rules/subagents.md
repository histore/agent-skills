# Subagent Orchestration, Clean Architecture & Context Isolation Guidelines

## Core Principles
1. **Compound Phased Execution & KV-Cache Continuity (Default)**:
   - Core development workflows execute within a **continuous conversation thread** via phased persona transitions.
   - Preserving prefix continuity unlocks **75–90% prompt caching / KV-cache discounts** across turns and eliminates subagent serialization and cold-start overhead.
2. **Selective Subagent Forking for Divergent Exploration**:
   - `invoke_subagent` is reserved strictly for noisy, divergent tasks (e.g. broad repository scans via `research`, external web lookups, or background tasks).
   - Isolates exploratory search noise from the primary thread, returning concise executive summaries.
3. **Universal Model Tiering & Execution Modes**:
   - Tier mappings and budgets defined in [`rules/model-tiers.json`](model-tiers.json).
   - Reasoning budgets are throttled to `low/minimal` during implementation and test execution, relying on compiler and testrunner feedback as ground truth rather than burning speculative reasoning tokens.
   - **Terminal & Context Hygiene**: All PowerShell commands must use `-NoProfile`. Testrunners must run in quiet mode (`dotnet test --verbosity quiet`, `cargo test -q`, `pytest -q`) to stop log spam from bloating the context window.
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
   - **Two-Stage Quality Gate (Shift-Left Validation)**:
     - **Stage 1 (Deterministic Fast-Gate - Zero Tokens)**: Native build (`dotnet build`, `cargo check`), project linter, and quiet native test runner (0 errors, 100% pass). If failing, immediately return for remediation without consuming LLM tokens on semantic analysis.
     - **Stage 2 (Concise Traceability Gate)**: `Verifikation` audits acceptance criteria fulfillment and Clean Architecture boundaries.
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

## Subagent Roles & Governance Mappings
All 22 specialized subagent roles, their cognitive tiers, reference models, and thinking budgets are declaratively maintained in the Single Source of Truth: [`rules/model-tiers.json`](model-tiers.json).
- **Core Lifecycle Roles**: `Control`, `RequirementEngineer`, `Architekt`, `Developer`, `Tester`, `Verifikation`, `CommitManager`, `PRManager`.
- **Lifecycle Specialists (On-Demand)**: `Troubleshooter`, `GitTroubleshooter`, `CodeExplainer`, `RefactoringSpecialist`, `DocumentationSpecialist`, `ArchitectureSync`, `DevOpsEngineer`, `ReleaseManager`.
- **Domain Specialists (On-Demand)**: `UIDesigner`, `LocalizationSpecialist`, `PerformanceOptimizer`, `SecurityAuditor`, `DatabaseSpecialist`, `ApiContractSpecialist`.

Operational execution instructions are defined exclusively in each role's skill specification in [`skills/`](../skills/).

---

## Client Directory Compatibility (`.agents` vs. `_agents`)
- **Gemini / Antigravity**: Seamlessly supports and monitors both `_agents` and `.agents` customization roots.
- **GitHub Copilot & Other Clients**: Specifically expect `.agents/` as the standard discovery root. When sharing skills across multiple AI clients or targeting Copilot, use `.agents` (or create a symbolic link / submodule pointing to `.agents`).
