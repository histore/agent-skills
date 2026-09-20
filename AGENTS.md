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
4. **Core Workflow vs. Domain Specialists**:
   - **Core Lifecycle Roles** handle the general development lifecycle: `RequirementEngineer`, `Architekt`, `Developer`, `Tester`, `Verifikation`, `CommitManager`, `PRManager`, supported by generalists (`Troubleshooter`, `RefactoringSpecialist`, `ArchitectureSync`, `DocumentationSpecialist`, `Tiebreaker`).
   - **Domain Specialists** (e.g., `UIDesigner`, `LocalizationSpecialist`, `TerminalEngineSpecialist`, `PerformanceOptimizer`, `SecurityAuditor`) are bound to their specific technical domain rather than a single library or framework.
   - **On-Demand Domain Invocation**: Domain specialists are **NOT** part of the mandatory linear development pipeline. They are engaged selectively:
     - `Control` includes them when the feature or bug involves that specific domain (e.g., UI layout changes, terminal protocol streaming, deep performance profiling, security vulnerability auditing).
     - Other roles (such as `Developer`, `Architekt`, or `Troubleshooter`) can consult or delegate to these domain specialists to clarify domain-specific nuances, edge cases, and technical constraints.
5. **Automated Testing, Quality & Stub-First TDD**:
   - Standard feature development and bugfixing adhere strictly to **Stub-First Test-Driven Development (TDD)** (Red-Green-Refactor).
   - **Phase RED**: The `Tester` authors unit/integration tests against acceptance criteria and the `Architekt`'s compilable stubs *before* production code is implemented, verifying that tests compile cleanly and fail semantically via the native test runner.
   - **Phase GREEN**: The `Developer` implements production code strictly to turn failing tests green. The **Test Immutability Constraint** strictly forbids the developer from altering test files or relaxing assertions.
   - **Circuit Breaker**: The `Developer`'s local feedback loop (`Code` -> `Run Tests` -> `Fix`) is capped at a maximum of 3 iterations before escalating to `Tiebreaker` or the user.
   - **Comprehensive Scenario Coverage**: Unit and integration tests follow the Arrange-Act-Assert (AAA) pattern.
   - Automated test execution relies on the project's native test runner (e.g., `dotnet test`, `cargo test`, `npm test`, `pytest`, `go test`), requiring a 100% pass rate with 0 failures before verification sign-off.
6. **Internationalization & Localization (i18n / l10n)**:
   - When user-facing interfaces are present, maintain 0% hardcoded user strings; manage texts in structured bilingual resources in **German (`de`)** and **English (`en`)** using the project's native localization format.
7. **Consistency & Deduplication**: All new requirements must be validated against existing requirements in `REQUIREMENTS.md`.
8. **User Decision on Conflicts**: In case of contradictions or duplicates, the user must make the decision.
9. **Immutability of Existing Requirements**: Existing requirements may only be modified with explicit user instruction.
10. **100% Coverage**: 100% of code/system changes must be covered by approved requirements.
11. **Dynamic Model Allocation & Universal Execution Strategy**:
    - Model tiers and execution modes are declaratively defined in [`rules/model-tiers.json`](file:///rules/model-tiers.json).
    - In **Antigravity / AGY**, roles execute in isolated subagents via `invoke_subagent` mapped to model classes (`pro`, `flash`, `flash_lite`).
    - In **GitHub Copilot / Cursor / Single-Model environments**, roles execute in **Sequential Persona Mode** using prompt-modulated thinking budgets (High/Extended, Medium, Low/Fast) with zero overhead.
    - Runtime capabilities can be probed deterministically at zero token cost via `scripts/detect-models.ps1` / `scripts/detect-models.sh`.
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

## Subagent Roles & Model Profiles

### Core Lifecycle Roles (Standard Workflow)
1. **Control**: Orchestrates Stub-First TDD workflow pipelines, breaks down tasks, enforces lifecycle action governance and iteration caps, assigns model capability tiers / reasoning levels, incorporates domain specialists when appropriate, provides strictly minimal context packages, and facilitates the Developer Testing & Review gate before PR creation.
2. **RequirementEngineer** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Translates user requirements into explicit user stories and Given-When-Then acceptance criteria, checking for duplicates/conflicts.
3. **Architekt** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Defines contracts, interfaces, dependency management, and layer structure following Clean Architecture. Generates compilable skeleton stubs (`todo!()`, `NotImplementedException`) to enable Phase RED testing. Consults domain specialists for domain-specific constraints when needed.
4. **Tester** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements Phase RED unit/integration and reproduction tests against stubs/spec before code implementation, verifies semantic failures, and certifies 100% pass rates post-implementation via the native test runner (AAA pattern, 0 failures).
5. **Developer** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements Phase GREEN production code strictly to satisfy failing tests without modifying test files, adhering to Clean Code, project conventions, and the 3-iteration circuit breaker.
6. **Verifikation** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Quality gate auditing acceptance criteria, 100% requirements coverage, test pass rate, Clean Code, performance, security, test immutability compliance, and architectural integrity before handing over to developer testing.
7. **CommitManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages Git commit and push actions with atomic isolation, resolves prerequisite commits when push is requested, offers push after commit, halts on atypical workspace states, and requires interactive user confirmation.
8. **PRManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages the Pull Request lifecycle (prerequisite push/commit resolution, template drafting, `gh pr create`, delayed-polling CI checks, squash-merge, and proactive next-step guidance) strictly on-demand after approval.

### General Support Roles (Lifecycle Specialists)
9. **Troubleshooter** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Diagnoses bugs, analyzes call stacks and event hierarchies, identifies root causes, and specifies minimal failing reproduction tests for the Tester (Phase RED handoff). Consults domain specialists for domain-specific subsystems.
10. **RefactoringSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Audits code smells and technical debt, designing safe, test-backed refactorings.
11. **DocumentationSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Authors API doc comments (in project-standard format), user manuals, and in-app help guides in English.
12. **ReleaseManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages deployment pipelines, packaging, SemVer tag calculation, prerequisite branch/sync verification, anomaly detection, and tag creation & push upon user approval.
13. **Tiebreaker** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Monitors active operations, detects loops/deadlocks/thrashing, and enforces remediation via strategy pivots, model upgrades, context purges, or user escalation.
14. **CodeExplainer** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's operating system language, inserting clear didactic comments directly into code files (in English by default, or in a user-specified language).
15. **ArchitectureSync** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Incrementally audits and synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts to avoid unnecessary scans and prevent context degradation.

### Domain Specialists (Engaged On-Demand by Control or Consulted by Skills)
16. **UIDesigner** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Designs intuitive, aesthetically outstanding, and accessible user interfaces, component layouts, and interaction flows for the project's UI environment.
17. **LocalizationSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Audits code and templates for i18n compliance, extracts hardcoded strings, and maintains complete bilingual resources (`de`/`en`) in the project's localization format.
18. **TerminalEngineSpecialist** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Deep domain specialist for terminal subsystems, pseudo-terminals (PTY/ConPTY), ANSI/VT escape sequences, OSC shell integration, streaming, and character encoding.
19. **PerformanceOptimizer** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Identifies allocation hotspots, memory leaks, and throughput bottlenecks, prescribing high-performance, language-idiomatic optimizations.
20. **SecurityAuditor** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Audits process execution safety, secret leak prevention, dependency CVEs via project ecosystem audit tools, injection risks, safe path handling, and state serialization security.

## Context Isolation Protocol
- Subagents must be called with only the minimum context required for their specific role.
- Intermediate results (e.g. root cause reports, UX blueprints, i18n dictionaries, architecture contracts, diffs, acceptance criteria) are passed downstream sequentially.
- No role shall receive bloated discussion history or unrelated files.

## Client Directory Compatibility (`.agents` vs. `_agents`)
- **Gemini / Antigravity**: Seamlessly supports both `_agents` and `.agents` customization roots.
- **GitHub Copilot & Other Clients**: Specifically expect `.agents/` as the standard discovery root. When sharing skills across multiple AI clients or targeting Copilot, use `.agents` (or create a symbolic link / submodule pointing to `.agents`).

Detailed skill definitions can be found in `skills/` (or `_agents/skills/` / `.agents/skills/` when consumed as a submodule) and rules in `rules/` (or `_agents/rules/` / `.agents/rules/`).
