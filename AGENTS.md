# Workspace Agent Guidelines: Subagent Roles & Context Isolation

## Overview
This workspace employs specialized subagent roles to enforce **Clean Code**, **Clean Architecture**, dynamic project stack adaptation, maximum usability, high performance, robust security, systematic **Root Cause Analysis (Troubleshooting)**, high automated test coverage, and strict context isolation.

All skills and rules are designed to be general and reusable across diverse projects. Programming languages, frameworks, libraries, and toolchains are never hardcoded; agents dynamically discover and adapt to the target project's conventions and ecosystem.

## Core Governance & Architecture Rules
1. **Clean Architecture Principles**:
   - Universal separation of concerns across layers (Domain/Entities -> Application/Service Contracts -> Interface Adapters / Presenters / ViewModels -> External Frameworks / UI / Storage / Drivers).
   - Core domain logic and service interfaces must remain strictly agnostic of UI frameworks, databases, and external delivery mechanisms.
2. **Clean Code & Universal Best Practices**:
   - Adhere to SOLID, DRY, KISS, YAGNI, Boy Scout Rule, and clear, descriptive naming conventions.
   - Write clean, idiomatic code adhering to the best practices and type-safety mechanisms of the target project's programming language.
   - All source code comments and docstrings must be written in English.
3. **Dynamic Tech Stack Specialization**:
   - Skills do not hardcode programming languages (e.g., C#, Rust, Python, TypeScript, Go) or specific frameworks/libraries (e.g., Avalonia, React, Tokio, ASP.NET).
   - Agents dynamically detect the project stack by inspecting build configurations, package manifests (e.g., `Directory.Build.props`, `Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod`), and the architecture baseline (`ARCHITECTURE.md`).
4. **Core Workflow vs. Domain & Lifecycle Specialists**:
   - **Core Lifecycle Roles** handle the general development lifecycle: `Control`, `RequirementEngineer`, `Architekt`, `Developer`, `Tester`, `Verifikation`, `CommitManager`, `PRManager`.
   - **Lifecycle & Domain Specialists** (e.g., `Troubleshooter`, `GitTroubleshooter`, `RefactoringSpecialist`, `ArchitectureSync`, `DocumentationSpecialist`, `DevOpsEngineer`, `UIDesigner`, `LocalizationSpecialist`, `PerformanceOptimizer`, `SecurityAuditor`, `DatabaseSpecialist`, `ApiContractSpecialist`) are engaged **on-demand**.
   - **On-Demand Specialist Invocation**: Specialists are **NOT** mandatory serial steps on every commit. They are engaged selectively:
     - `Control` includes them when the feature or task explicitly involves that specific domain (e.g., UI layout changes, database migrations, dedicated technical debt audits, changelog releases, architectural drift sync).
     - Other roles (such as `Developer`, `Architekt`, or `Troubleshooter`) can consult or delegate to these specialists to clarify domain-specific nuances, edge cases, and technical constraints.
5. **Automated Testing, Quality & Inner-Loop TDD**:
   - Development follows **Inner-Loop Test-Driven Development (TDD)** (Red-Green-Refactor) adapted to task complexity:
     - **Profile A (Fast-Track - Bugs, Tweaks, Small Features)**: Developer authors targeted unit tests and implementation code directly in a single, fast red-green-refactor loop (saving 70–80% latency and token cost).
     - **Profile B (Standard Features)**: Architecture contract established -> Developer implements unit tests and code via Inner-Loop TDD -> Verifikation quality gate.
     - **Profile C (Complex / Architectural)**: Modular architecture contracts -> Optional skeleton stubs for parallel decoupling -> Comprehensive integration test suites by `Tester` -> Developer implementation.
   - **Targeted Test Execution**: During inner loops, test runners must target only the affected test file or class (`dotnet test --filter`, `cargo test <name>`, `npm test -- <path>`, `pytest <path>`), executing the full test suite once during final verification to avoid full-suite build thrashing.
   - **Two-Stage Quality Gate (Shift-Left Validation)**:
     - **Stage 1 (Deterministic Fast-Gate - Zero Tokens)**: Native build (`dotnet build`, `cargo check`), project linter, and quiet native test runner (0 errors, 100% pass). If failing, immediately return for remediation without consuming LLM tokens on semantic analysis.
     - **Stage 2 (Concise Traceability Gate)**: `Verifikation` audits acceptance criteria fulfillment and Clean Architecture boundaries.
   - **Test Integrity Guardrail**: Replaces rigid test immutability. The Developer is empowered to adjust and refine test fixtures, signatures, and assertions to match real contracts and idiomatic types. Weakening, bypassing, or deleting assertions to fake passing tests is strictly forbidden.
   - **Circuit Breaker**: The `Developer`'s targeted test-fix feedback loop is capped at a maximum of 3 iterations before escalating.
   - **Comprehensive Scenario Coverage**: Unit and integration tests follow the Arrange-Act-Assert (AAA) pattern.
   - Automated test execution relies on the project's native test runner, requiring a 100% pass rate with 0 failures before verification sign-off.
6. **Internationalization & Localization (i18n / l10n)**:
   - When user-facing interfaces are present, maintain 0% hardcoded user strings; manage texts in structured bilingual resources in **German (`de`)** and **English (`en`)** using the project's native localization format.
7. **Consistency & Deduplication**: All new requirements must be validated against existing requirements in `REQUIREMENTS.md`.
8. **User Decision on Conflicts**: In case of contradictions or duplicates, the user must make the decision.
9. **Immutability of Existing Requirements**: Existing requirements may only be modified with explicit user instruction.
10. **100% Coverage**: 100% of code/system changes must be covered by approved requirements.
11. **Dynamic Model Allocation & Universal Execution Strategy**:
    - Model tiers and execution modes are declaratively defined in [`rules/model-tiers.json`](rules/model-tiers.json).
    - **Compound Phased Execution (Default Strategy)**: Core development workflows (Plan -> Inner-Loop TDD -> Verify -> Commit) execute within a **continuous conversation thread** via phased persona transitions. This preserves prefix continuity, unlocking **75–90% prompt caching / KV-cache discounts** and eliminating multi-agent spawn latency.
    - **Selective Subagent Forking (`invoke_subagent`)**: Reserved strictly for **divergent research**, broad multi-file repository exploration, web lookups, or independent background sidecars to keep exploratory token noise out of the primary thread.
    - **Terminal & Context Hygiene**: All PowerShell commands must use `-NoProfile`. Testrunners must run in quiet mode (`dotnet test --verbosity quiet`, `cargo test -q`, `pytest -q`) to prevent terminal logs from bloating the context window.
    - **Sequential Persona Mode (Copilot / Cursor / Single-Model)**: Uses prompt-modulated thinking budgets (Extended for Tier 1, Low/Minimal for Tier 3/4).
12. **Branch & PR Process Model with Developer Testing & Review Gate**: All development must occur on dedicated branches (`feat/`, `fix/`, `refactor/`, `chore/`, `docs/`). Prior to Pull Request creation, the developer is provided with the opportunity to review the code, test application functionality interactively/manually, and request adjustments or fixes. Merging into `main` occurs solely via Pull Requests using Squash-and-Merge after explicit user sign-off and passing CI per [CONTRIBUTING.md](CONTRIBUTING.md).
13. **Four-Step Codebase Analysis Protocol**:
    When exploring, analyzing, or diagnosing a codebase, agents must strictly follow four progressive steps:
    1. **Check Current Modular Architecture Baseline**: Verify `ARCHITECTURE.md`, module specifications (`docs/architecture/modules/*.md`), and state checkpoint (`.arch-sync.json`).
    2. **Synchronize Architecture if Needed**: If the documentation is missing, outdated, or desynchronized from recent git commits, trigger `ArchitectureSync` to update affected module documents.
    3. **Deduce State from Modular Architecture Documentation**: Derive component responsibilities, public contracts, data flows, and runtime state directly from the relevant modular architecture specification (`docs/architecture/modules/<module>.md`).
    4. **Targeted Code Inspection Only for Critical Details**: Read concrete source code files strictly when specific low-level implementation details (e.g. algorithmic nuance, interop declarations, exact event routing lines) are indispensable.
    **Modular Architecture Depth & Context Guardrail**: Architecture documents must provide rich, granular detail (contracts, interfaces, state flows, threading guarantees) to obviate broad code scans, while maintaining strict modular separation into per-module files so reading documentation never continuously bloats or exhausts the agent's context window.
14. **Lifecycle Action Execution Governance (Commit, Push, PR Merge, Release)**:
    Defined Git and release actions adhere to six explicit execution principles:
    1. **Strict Action Execution (Atomic Scope)**: When the user requests a specific action (e.g. `commit`), execute only that action (e.g. commit only, do not automatically push).
    2. **State-Driven Prerequisite Resolution**: If the requested action requires preceding steps based on the current workspace or repository state (e.g. uncommitted changes present when `push` is requested), automatically resolve the necessary prerequisites first.
    3. **Proactive Next-Step Offering**: When an action completes and a logical subsequent step is derivable, proactively offer the user to execute it directly.
    4. **Gate Invariance**: All interactive review gates and safety validations (e.g. commit message confirmation, PR description review, SemVer release tag approval) remain mandatory and cannot be bypassed.
    5. **Explicit User Override**: The user may explicitly instruct deviating or combined behavior at any time (e.g. "commit and push directly").
    6. **Atypical State & Anomaly Gate**: If following these instructions would produce an unusual state or require non-standard/atypical measures (e.g. detached HEAD, merge conflicts, unexpected untracked files, unverified release states, cross-cutting multi-scope changes), the agent must pause, describe the situation, and prompt the user for explicit confirmation before proceeding.
15. **Adaptive Governance & Strictness Levels**:
    - To prevent architectural overhead on small or legacy tasks, `Control` must establish and propagate a `Strictness Level` context:
      - **Enterprise (Default)**: Strict adherence to Clean Architecture, 100% test coverage, and full Requirement mapping.
      - **Legacy**: Tolerates architectural deviations and missing tests (does not block verification), but requires Stage 1 compilation success.
      - **Prototype**: Focuses on speed (MVP). Architecture documentation and TDD are strictly optional.

## Subagent Roles & Governance Mappings
All 22 specialized subagent roles, their cognitive tiers, reference models, and thinking budgets are declaratively maintained in the Single Source of Truth: [`rules/model-tiers.json`](rules/model-tiers.json).
- **Core Lifecycle Roles**: `Control`, `RequirementEngineer`, `Architekt`, `Developer`, `Tester`, `Verifikation`, `CommitManager`, `PRManager`.
- **Lifecycle Specialists (On-Demand)**: `Troubleshooter`, `GitTroubleshooter`, `CodeExplainer`, `RefactoringSpecialist`, `DocumentationSpecialist`, `ArchitectureSync`, `DevOpsEngineer`, `ReleaseManager`.
- **Domain Specialists (On-Demand)**: `UIDesigner`, `LocalizationSpecialist`, `PerformanceOptimizer`, `SecurityAuditor`, `DatabaseSpecialist`, `ApiContractSpecialist`.

Operational execution instructions are defined exclusively in each role's skill specification in [`skills/`](skills/).

## Context Isolation & Compaction Protocol
- Subagents must be called with only the minimum context required for their specific role.
- Intermediate results (e.g. root cause reports, UX blueprints, i18n dictionaries, architecture contracts, diffs, acceptance criteria) are passed downstream sequentially.
- No role shall receive bloated discussion history or unrelated files.
- **Proactive Context Compaction & Phase Checkpointing**:
  - To prevent "Lost in the Middle" degradation and trim token bloat, `Control` executes explicit context compaction at major phase boundaries (e.g., Plan -> Implementation, or between distinct user tasks).
  - Before transitioning or starting a new task, synthesize a concise **State Checkpoint** (active goal, touched files, verified architecture facts, next concrete steps).
  - Discard obsolete intermediate trial-and-error logs, failed compilation attempts, and transient conversation history, while strictly preserving top-of-context system rules to maximize KV-cache prefix hits.

## Client Directory Compatibility (`.agents` vs. `_agents`)
- **Gemini / Antigravity**: Seamlessly supports both `_agents` and `.agents` customization roots.
- **GitHub Copilot & Other Clients**: Specifically expect `.agents/` as the standard discovery root. When sharing skills across multiple AI clients or targeting Copilot, use `.agents` (or create a symbolic link / submodule pointing to `.agents`).

Detailed skill definitions can be found in `skills/` (or `_agents/skills/` / `.agents/skills/` when consumed as a submodule) and rules in `rules/` (or `_agents/rules/` / `.agents/rules/`).
