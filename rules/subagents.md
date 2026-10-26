# Subagent Orchestration, Clean Architecture & Context Isolation Guidelines

## Core Principles
1. **Compound Phased Execution & KV-Cache Continuity (Default)**:
   - Core development workflows execute within a **continuous conversation thread** via phased persona transitions.
   - Preserving prefix continuity unlocks **75–90% prompt caching / KV-cache discounts** across turns and eliminates subagent serialization and cold-start overhead.
2. **Selective Subagent Forking & Parallel Workspace Isolation**:
   - `invoke_subagent` is reserved primarily for noisy, divergent tasks (e.g. broad repository scans via `research` with `Model: "flash"`, external web lookups, or background tasks) to isolate search noise from the primary KV-cache prefix.
   - **Parallel Worktree Execution (`Workspace: "share"` / `"branch"`)**: For complex Profile C architectures or A/B prototyping where genuinely independent modules can be developed or benchmarked in parallel without file-lock collisions, `Control` may dispatch write-enabled subagents in isolated worktrees (`Workspace: "share"`), reviewing and merging verified changes back into the primary workspace.
3. **Universal Model Tiering & Execution Modes**:
   - Tier mappings, model classes, and budgets defined in [`rules/model-tiers.json`](model-tiers.json).
   - **Task-Complexity-Driven Model Allocation (Dynamic Right-Sizing into 3 Classes)**:
     - **ECO**: Auto-allocated for Profile 0 & Profile A (trivial requests, bugfixes, docs, scripts, Tier 4 Git/lifecycle). Auto-approved, runs on lightweight models (`flash`, `gpt-4o-mini`, `claude-haiku`) with minimal reasoning to minimize token consumption.
     - **BALANCED**: Auto-allocated for Profile B (standard feature engineering, unit tests, Clean Code inner-loop TDD). Auto-approved sweet spot balancing cognitive depth and quota usage (`inherit`, `sonnet`, `flash` with medium reasoning).
     - **PREMIUM**: Allocated for Profile C (complex architectural redesigns, cross-module refactorings, deep deadlocks, security audits). **Subject to Mandatory Quota Protection User Gate**.
   - **Quota Protection User Gate**: Whenever an incoming task is classified as Profile C / Premium, `Control` pauses execution before consuming quota and presents an immediate 3-class selection (`[1] Premium`, `[2] Balanced`, `[3] Eco`) to the user. Direct selection or prompt parameterization (e.g. `--eco`, `--balanced`, `--premium`, or direct prompt instruction) satisfies the gate immediately. In multi-agent environments (Antigravity), this renders as an interactive prompt/modal; in single-model environments (Copilot), it outputs an explicit recommendation gate in chat and modulates the prompt/thinking budget.
   - **Cost-Efficiency & Sweet-Spot Policy (Calibrated Model Allocation)**: Agents, subagents, and skills must always hit the "sweet spot" balancing cognitive capability and cost-efficiency. Avoid wasteful over-provisioning (e.g., flagship models for trivial file searches, simple diffs, or repetitive formatting) as well as destructive under-provisioning (e.g., starving complex architectural, diagnostic, or security tasks with underpowered models that produce hallucinations, broken abstractions, or repetitive TDD test failures). Subagents invoked via `invoke_subagent` default to `inherit` to maintain the fidelity of the active session without artificial downgrades. Divergent exploratory research uses lightweight models (`flash`). Deterministic lifecycle actions (commits, PR manifests, release tags) use fast, reliable models (`flash`), strictly avoiding underpowered tiers (`flash_lite`) that fail at structured output. Strategic and diagnostic roles (`Troubleshooter`, `Architekt`, `CodeReviewer`, `SecurityAuditor`) leverage high reasoning or flagship models (`pro` / high reasoning) when task complexity (Profile C) or deadlock resolution demands it.
   - Reasoning budgets are throttled to `low/minimal` during implementation and test execution, relying on compiler and testrunner feedback as ground truth rather than burning speculative reasoning tokens.
   - **Terminal & Context Hygiene**: All PowerShell commands must use `-NoProfile`. Testrunners must run in quiet mode (`dotnet test --verbosity quiet`, `cargo test -q`, `pytest -q`) to stop log spam from bloating the context window.
   - **Cost-Guardrail (Budget Protection Circuit Breaker)**: Prevents accidental budget-burning when high-cost flagship models (> $4.00/M input, > $20.00/M output, e.g. GPT-6 Astra, Claude Opus, Claude Fable) are active during routine, mechanical, or repetitive operations. In multi-agent environments, subagents for Tier 4 (Commits/PRs) or divergent searches automatically throttle to cost-efficient models. In sequential/single-model environments (Copilot), a Smart Confirmation Gate pauses execution and recommends switching to the Daily Driver (Gemini Flash / GPT-6.1 Sol / Luna) before consuming large token volumes on routine tasks, unless explicitly confirmed by the user.
4. **Clean Architecture & Clean Code Enforcement**:
   - **Clean Architecture**: Dependency rule (dependencies point inward), clear layer boundaries (`Models`, `Services`, `Interface Adapters/ViewModels`, `Views/Frameworks`), independent of external UI, database, or OS details.
   - **Clean Code**: SOLID, DRY, KISS, YAGNI, Boy Scout Rule, small focused classes/functions, descriptive naming, English comments.
   - **Safe Language Paradigms**: In Rust, `unsafe` code blocks must not be used; enforce safe language idioms, type safety, and memory guarantees.
   - **Relative Paths Invariant in Documentation**: All documentation files (`*.md`), architecture contracts, requirements, and feature specs must strictly use **relative paths** for links and references. Absolute local paths (`C:\...`, `/home/...`, `/Users/...`, `file:///...`) are strictly prohibited in repository documentation.
   - **Dynamic Tech Stack Specialization**: No language or framework is hardcoded. Agents discover the project stack dynamically from configuration and manifests (e.g. `Directory.Build.props`, `Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod`).
5. **Core Workflow & Inner-Loop TDD vs. On-Demand Specialists**:
   - **Default Entry Point & Orchestrator Invariant**: All interactions across all AI assistants (Google Antigravity, GitHub Copilot, Cursor) MUST start with the `Control` persona (`ask-control`). The agent classifies requests into adaptive execution profiles (Profile 0, A, B, C) and coordinates downstream roles. In single-thread environments like GitHub Copilot (Sequential Persona Mode), the agent seamlessly transitions personas sequentially (`Control` -> `Developer` -> `Verifikation` -> `CommitManager`) within the conversation thread without requiring the user to invoke `ask-control` manually.
   - **Adaptive Workflow Pipelines (T-Shirt Sizing)**:
     - **Profile 0 (Direct Response - Informational / Read-Only / Trivial)**: Answer directly. **Zero Git operations and zero test execution.**
     - **Profile A (Fast-Track - Bugs, Tweaks, Small Features)**: `Developer` executes **Inner-Loop TDD** (writing unit tests + implementing production code + in-place Clean Code refactoring in a single, fast pass) -> `Verifikation` -> `Developer Review Gate` -> `CommitManager` -> `PRManager`. Slashes token cost and latency by 70–80%. If the change affects only non-executable files (documentation, markdown, text resources, comments) or codebases without test suites, test execution is omitted.
     - **Profile B (Standard Features)**: `RequirementEngineer` (Tier 2) -> `Architekt` (Tier 2 modular contracts) -> `Developer` (Tier 3 Inner-Loop TDD) -> `Verifikation` (Tier 2) -> `ArchitectureSync` (conditional on `get-arch-diff`) -> `Developer Review Gate` -> `CommitManager` -> `PRManager`.
     - **Profile C (Complex / Architectural)**: Codebase Analysis -> Requirements (`RequirementEngineer`, Tier 1/2) -> Modular Architecture & Optional Skeleton Stubs (`Architekt`, Tier 1) -> Integration & Comprehensive Test Suite (`Tester`, Tier 3) -> Implementation (`Developer`, Tier 3) -> On-Demand Specialists -> `Verifikation` -> Review Gate -> `CommitManager` -> `PRManager`.
   - **Purpose-Driven Test Execution**: Tests and test runners must **ONLY** be executed when executable production code has been modified and relevant automated tests exist or need to be authored. Do NOT run test suites for documentation, markdown files, comments, static text assets, simple scripts without test suites, or when tests are unrelated to the edited file.
   - **Targeted Test Execution**: During inner loops, test runners target only affected test classes/files (`--filter`, specific test path) to prevent full-suite build thrashing. The full test suite runs once during final verification.
   - **Two-Stage Quality Gate (Shift-Left Validation)**:
     - **Stage 1 (Deterministic Fast-Gate - Zero Tokens)**: Native build (`dotnet build`, `cargo check`), project linter, and quiet native test runner (0 errors, 100% pass) executed deterministically via `run-fast-gate.ps1` (`run-fast-gate.sh`), followed by `check-test-coverage.ps1` (`check-test-coverage.sh`) when coverage reports are present. If failing, immediately return for remediation without consuming LLM tokens on semantic analysis. Only triggered when testable code changes were made.
     - **Stage 2 (Concise Traceability Gate)**: `Verifikation` audits acceptance criteria fulfillment and Clean Architecture boundaries (enforced deterministically via `lint-clean-architecture.ps1` and [`rules/clean-architecture.json`](clean-architecture.json)).
   - **Circuit Breaker**: The `Developer`'s local targeted feedback loop (`Code` -> `Run Targeted Tests` -> `Fix`) is limited to a maximum of 3 cycles before escalation.
   - **On-Demand Specialist Capability Packs**: Four high-value specialist capability packs engage selectively on-demand:
     - `Troubleshooter` (`ask-troubleshooter`): Root Cause Analysis, reproduction tests, adversarial code review, safe Fowler refactoring, performance profiling.
     - `GitTroubleshooter` (`ask-git-troubleshooter`): Git safety, 3-way merge/rebase conflict resolution, reflog recovery, safety backups.
     - `ContractSpecialist` (`ask-contract-specialist`): Living feature specs, concept tracks, requirements governance, API contracts, DB migrations, architecture sync, i18n.
     - `ReleaseManager` (`ask-release-manager`): Release automation, SemVer calculation, changelog generation, CI/CD workflows, security audits, Git release tags.
6. **Systematic Root Cause Analysis & Reproduction TDD**:
   - `Troubleshooter` diagnoses bugs, analyzes event hierarchies and call stacks, and delivers an explicit reproduction test specification (Phase RED) before or alongside the code fix.
7. **Full Internationalization (i18n & l10n)**:
   - Enforced via `ContractSpecialist` (0% hardcoded UI strings, bilingual German `de` and English `en` resource files).
8. **Performance, Security, Persistence, DevOps & Code Health**:
   - `Troubleshooter` enforces zero-allocation patterns, memory leak prevention, Fowler refactoring, and adversarial review.
   - `ContractSpecialist` governs API contracts (OpenAPI/gRPC), database migrations, and incremental architecture synchronization (`get-arch-diff.ps1`).
   - `ReleaseManager` governs CI/CD automation, security CVE audits, and clean Git release tagging on `main`.
   - `GitTroubleshooter` governs repository anomalies, 3-way merge/rebase conflict resolutions, and state recovery under zero-data-loss invariants.
9. **Strict Requirements Governance & Modular Architecture**:
   - **Check Against Existing Requirements**: Every new requirement must be validated against existing requirements.
   - **Single-File vs. Modular Hub-and-Spoke Architecture**:
     - *Single-File (`REQUIREMENTS.md`)*: Used for smaller projects or initial prototypes (< ~30–50 requirements).
     - *Modular Architecture (`docs/requirements/modules/<module>.md`)*: For growing codebases or multi-module projects, requirements are segmented per module. The root `REQUIREMENTS.md` serves as the central Hub, Index, ID Registry, and Non-Functional Requirements (NFR) Baseline.
   - **Living Modular Documentation & Phased Feature Specs**:
     - *Append-Only / Delta Growth*: Never generate or mutate monolithic specifications. Documents grow step-by-step as isolated feature files (`docs/features/FEAT-<SCOPE>-XXX-<slug>.md` or `docs/requirements/modules/<module>.md`).
     - *Zero-Full-Diff Guarantee*: Changes and additions affect strictly the single target feature file and append a 1-line link to `docs/ROADMAP.md` or `REQUIREMENTS.md`, eliminating multi-page diff thrashing.
     - *Phase-Driven Progression*: Group features into distinct implementation phases (`phase: 1`, `phase: 2`, etc.) with explicit lifecycle status (`PROPOSED`, `APPROVED`, `IN_PROGRESS`, `IMPLEMENTED`, `VERIFIED`).
     - *Lazy Loading & Token-Hygiene Protocol (Zero Full-Parse Invariant)*: On subsequent runs, agents inspect only the central index table first. Load strictly the single target feature file into context. Never bulk-read or parse all specification files.
     - *Zero-Token Offloading*: Query features by phase and scaffold templates without token usage via `scripts/inspect-feature-specs.ps1` (`inspect-feature-specs.sh`).
   - **Namespaced IDs & Lifecycle Tracking**: Standardized IDs (`REQ-<SCOPE>-XXX`) and explicit lifecycle status (`PROPOSED`, `APPROVED`, `IMPLEMENTED`, `VERIFIED`, `DEPRECATED`).
   - **User Decision on Conflicts/Duplicates**: Contradictions or duplicates must be escalated to the user for explicit decision.
   - **Immutability of Existing Requirements**: Existing requirements may only be modified with explicit user instruction.
   - **100% Coverage for Functional Features**: 100% of newly introduced functional features in Enterprise mode must be covered by approved requirements. Trivial bug fixes, minor tweaks, refactorings, documentation updates, and prototype work do not require bureaucratic requirement documentation.
10. **Branch & PR Process Model with Developer Testing & Review Gate**: All development must occur on dedicated branches (`feat/`, `fix/`, `refactor/`, `chore/`, `docs/`). Prior to Pull Request creation, the developer is provided with the opportunity to review the code, test application functionality interactively/manually, and request adjustments or fixes. Merging into `main` occurs solely via Pull Requests using Squash-and-Merge after explicit user sign-off and passing CI per [CONTRIBUTING.md](../CONTRIBUTING.md).
    - **Purpose-Bound Git Operations**: Git status checks, branch creation, or checkout commands must **ONLY** be executed when changes are actively being committed or pushed, or when explicitly requested by the user. Do **NOT** invoke git commands proactively during read-only queries or local edits.
11. **Four-Step Codebase Analysis Protocol & Modular Architecture Depth**:
    Whenever a codebase is analyzed, explored, or investigated for structural or architectural tasks, agents must strictly follow a 4-step workflow:
    1. **Check Current Modular Architecture Baseline**: Check `ARCHITECTURE.md`, module specifications in `docs/architecture/modules/*.md`, and `.arch-sync.json`.
    2. **Synchronize Architecture if Needed**: If the documentation is missing, outdated, or desynchronized from recent git commits, invoke `ArchitectureSync` (`get-arch-diff.ps1` / `get-arch-diff.sh`) to synchronize affected module specifications.
    3. **Deduce State from Modular Architecture Documentation**: Derive component responsibilities, public contracts, data flows, and runtime state directly from the relevant modular architecture specification (`docs/architecture/modules/<module>.md`).
    4. **Targeted Code Inspection Only for Critical Details**: Read concrete source code files strictly when specific low-level implementation details (e.g. algorithmic nuance, interop declarations, exact event routing lines) are indispensable.
    **Pragmatic Bypass**: For localized questions, simple queries, or isolated bugfixes within a single known file, bypass this multi-step protocol and inspect the relevant file directly without checking git deltas or architecture synchronizations.
12. **Lifecycle Action Execution Governance (Commit, Push, PR Merge, Release)**:
    Defined Git and release actions adhere to seven explicit execution principles:
    1. **Strict Action Execution (Atomic Scope)**: When the user requests a specific action (e.g. `commit`), execute only that action (e.g. commit only, do not automatically push).
    2. **State-Driven Prerequisite Resolution**: If the requested action requires preceding steps based on current workspace or repository state (e.g. uncommitted changes present when `push` is requested), automatically resolve the necessary prerequisites first.
    3. **Proactive Next-Step Offering**: When an action completes and a logical subsequent step is derivable, proactively offer the user to execute it directly.
    4. **Adaptive Gate Resolution (Intention Matching with Anomaly Fallback)**: When the user's prompt directly instructs or parameterizes an action (e.g. "erstelle einen minor release", "commit with message ..."), the review/confirmation gate is satisfied by the prompt and executes directly without redundant re-confirmation. However, an interactive confirmation gate remains mandatory and pauses execution if: (a) uncommitted/untracked changes exceed the task's scope, (b) SemVer rules in commit history contradict the requested release bump (e.g. breaking changes detected on a minor request), (c) branch protection/quality gates are violated, or (d) an atypical repository state occurs.
    5. **Explicit User Override**: The user may explicitly instruct deviating or combined behavior at any time (e.g. "commit and push directly").
    6. **Atypical State & Anomaly Gate**: If following these instructions would produce an unusual state or require non-standard/atypical measures (e.g. detached HEAD, merge conflicts, unexpected untracked files, unverified release states, cross-cutting multi-scope changes), the agent must pause, describe the situation, and prompt the user for explicit confirmation before proceeding.
    7. **Clean Release Tagging Invariant**: Release tags (`vX.Y.Z`) must be applied directly to the existing production/merge commit on `main`. Standalone metadata commits (such as `docs(changelog): release v...`) directly on `main` during release tagging are strictly prohibited to maintain an uncluttered Git commit history focused on actual functional changes. Release notes belong in tag annotations or GitHub Releases.
13. **Purpose-Driven Execution & Anti-Ceremony Guardrail (No Process for Process's Sake)**:
    - All actions, checks, and tool invocations must serve a tangible, practical purpose for the user's specific request. Steps must **NEVER** be executed merely to satisfy formal process definitions, checklists, or pipelines if they have no functional value for the task at hand:
      - **Informational & Read-Only Requests**: When the user asks a question, requests an explanation, code review, or exploratory analysis, agents must **NEVER** run git checks (`git status`, `git branch`), test runners, or architecture synchronization. Answer directly and concisely.
      - **Purpose-Bound Git Operations**: Git commands (`git status`, branch switching, etc.) are strictly forbidden unless a git-persisted action (commit, push, branch creation, PR) is actively being executed or explicitly requested by the user. Do not check git status proactively during simple file edits.
      - **Context-Relevant Testing**: Test runners and compilation gates are executed strictly when executable production code has been modified and relevant automated tests exist or need to be authored. Do NOT run test suites for documentation, markdown files, comments, static text assets, simple scripts without test suites, or when tests are unrelated to the edited file.
      - **Lightweight Trivial Changes**: Bug fixes, minor tweaks, configuration adjustments, and refactorings do not require bureaucratic upfront ceremonies (e.g. creating formal `REQ-` entries or checking `.arch-sync.json` drift) unless explicitly requested or when architectural boundaries are structurally changed.
      - **MCP & External Tool Governance (Local-First Priority)**: Deterministic local scripts (`scripts/*.ps1`, `scripts/*.sh`) always take precedence over external MCP server calls for repository, build, lint, or Git operations. Read-only MCP tools (documentation, schema inspection) are permitted on demand; state-mutating MCP operations (database writes, remote issue/PR mutations) strictly obey Atomic Lifecycle Action Governance.

---

## Subagent Roles & Governance Mappings
All 5 consolidated subagent capability packs, their cognitive tiers, reference models, and thinking budgets are declaratively maintained in the Single Source of Truth: [`rules/model-tiers.json`](model-tiers.json).
- **Core Lifecycle Engineer**: `Control` (`ask-control` — Unified Core Lifecycle Engineer & Orchestrator: Planning, Contracts, Inner-Loop TDD, Two-Stage Quality Gate, Lifecycle Git).
- **On-Demand Specialist Capability Packs**:
  - `Troubleshooter` (`ask-troubleshooter`): Systematic RCA, reproduction tests, adversarial code review, safe Fowler refactoring, performance profiling.
  - `GitTroubleshooter` (`ask-git-troubleshooter`): Git safety, 3-way merge/rebase conflict resolution, reflog recovery, safety backups.
  - `ContractSpecialist` (`ask-contract-specialist`): Living feature specs, concept tracks, requirements governance, API contracts, DB migrations, architecture sync, UI/UX tokens, a11y, and i18n.
  - `ReleaseManager` (`ask-release-manager`): Release automation, SemVer calculation, changelog generation, CI/CD workflows, security CVE audits, Git release tags.

Operational execution instructions are defined exclusively in each role's skill specification in [`skills/`](../skills/).

---

## Client Directory Compatibility (`.agents` vs. `_agents`)
- **Gemini / Antigravity**: Uses `_agents` as the standard customization root (keeping `.agents` available for repository-specific customizations).
- **GitHub Copilot & Other Clients**: Specifically expect `.agents/`. When sharing skills across multiple AI clients or targeting Copilot, configure skills under `.agents` (or create a symbolic link from `.agents` to `_agents`).

