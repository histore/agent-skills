# Agent Skills & Subagent Roles (`agent-skills`)

A modular, reusable repository of specialized AI subagent roles, skills, and governance rules designed for modern software development with Antigravity / Gemini agents and cross-platform AI assistants.

All skills and rules are designed to be general and reusable across diverse software projects. Programming languages, frameworks, libraries, and toolchains are never hardcoded; agents dynamically discover and adapt to the target project's conventions, manifests, and architecture.

## Structure

```text
agent-skills/
├── AGENTS.md               # Master guidelines and subagent governance rules
├── rules/
│   ├── clean-architecture.json # Declarative Clean Architecture layer rules and metric thresholds
│   ├── model-tiers.json    # Universal model tier mapping and thinking budgets
│   └── subagents.md        # Architectural rules and context-isolation protocol
├── scripts/                # Zero-token deterministic automation, linting, and verification scripts
└── skills/                 # 23 specialized subagent skills
    ├── ask-api-contract-specialist/
    ├── ask-architect/
    ├── ask-architecture-sync/
    ├── ask-code-explainer/
    ├── ask-code-reviewer/
    ├── ask-commit-manager/
    ├── ask-control/
    ├── ask-database-specialist/
    ├── ask-developer/
    ├── ask-devops-engineer/
    ├── ask-documentation-specialist/
    ├── ask-git-troubleshooter/
    ├── ask-localization-specialist/
    ├── ask-performance-optimizer/
    ├── ask-pr-manager/
    ├── ask-refactoring-specialist/
    ├── ask-release-manager/
    ├── ask-requirement-engineer/
    ├── ask-security-auditor/
    ├── ask-tester/
    ├── ask-troubleshooter/
    ├── ask-ui-designer/
    └── ask-verification/
```

## Available Subagent Roles

### Core Lifecycle Roles (Standard Workflow)
1. **Control**: Central workflow orchestrator, adaptive execution profile dispatcher (Fast-Track, Standard, Complex), model tier/reasoning manager, loop circuit breaker, and coordinator of the Developer Testing & Review gate.
2. **RequirementEngineer** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Translates user requirements into Given-When-Then acceptance criteria, managing single-file or modular requirements scaling (`docs/requirements/modules/*.md`), namespaced IDs, and duplicate/conflict detection (Tier 1 for Complex/Architectural profiles).
3. **Architekt** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Defines contracts, interfaces, dependency management, and layer boundaries following Clean Architecture. Authors modular specifications and optional skeleton stubs for complex decoupling (Tier 1 for Complex/Architectural profiles).
4. **Developer** (`Tier 3 | Low Reasoning` - Ref: `Gemini 3.8 Flash`): Implements production code and unit tests via **Inner-Loop TDD** (Red-Green-Refactor), adhering to Clean Code, targeted test feedback loops (max 3 iterations), and test integrity guardrails.
5. **Tester** (`Tier 3 | Low Reasoning` - Ref: `Gemini 3.8 Flash`): Designs and implements integration test suites, boundary stress tests, and reproduction tests, certifying 100% pass rates post-implementation via the native quiet test runner (AAA pattern, 0 failures).
6. **Verifikation** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Two-Stage Quality Gate: deterministic machine checks (build, lint, testrunner) followed by concise requirements, architectural traceability, and logical correctness audit (consulting `CodeReviewer` for deep adversarial defect analysis when needed).
7. **CommitManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages Git commit and push actions with atomic isolation, state-driven prerequisite resolution, interactive message confirmation, and proactive next-step recommendations.
8. **PRManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages the Pull Request lifecycle (`gh pr create`, delayed-polling CI checks, squash-merge, and proactive next steps) strictly on-demand after developer approval.

### General Support Roles (Lifecycle Specialists)
9. **Troubleshooter** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Flash (Extended Thinking)`): Diagnoses bugs, analyzes call stacks and event hierarchies, identifies root causes, and specifies minimal failing reproduction tests for Inner-Loop or Tester TDD handoffs.
10. **RefactoringSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): On-demand specialist auditing code smells and technical debt, designing and executing safe, test-backed Fowler refactorings.
11. **DocumentationSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): On-demand specialist authoring API doc comments, user manuals, CHANGELOG.md, and in-app help guides in English.
12. **ReleaseManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages deployment pipelines, packaging, SemVer tag calculation, branch/sync prerequisite validation, and tag creation & push upon user approval.
13. **CodeExplainer** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Flash (Extended Thinking)`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's OS language, inserting didactic comments directly into code files (in English by default, or in a user-specified language).
14. **ArchitectureSync** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Incrementally audits and synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts (`get-arch-diff`) to eliminate context bloat.
15. **GitTroubleshooter** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Flash (Extended Thinking)`): Diagnoses repository anomalies, resolves complex three-way merge, rebase, and cherry-pick conflicts, safely recovers lost commits or detached states via reflog, and enforces a strict zero-data-loss safety protocol (backup snapshots, automated build & test gates).
16. **DevOpsEngineer** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Authors and maintains CI/CD automation workflows (GitHub Actions), multi-stage Dockerfiles, compose environments, build matrices, and deployment configurations.
17. **CodeReviewer** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Adversarial static code reviewer specialized in hunting subtle bugs, edge-case regressions, logic flaws, race conditions, resource leaks, and unhandled boundary states in diffs, PRs, or target source files.

### Domain Specialists (On-Demand / Consulted by Skills)
Domain specialists are **not** part of the default linear workflow. They are engaged conditionally by `Control` when appropriate for the task, or consulted directly by other skills (Developer, Architekt, Troubleshooter, Verifikation) to resolve domain-specific details:
18. **UIDesigner** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): UI/UX ergonomics, interaction flows, layout hierarchy, and design tokens for the project's UI environment.
19. **LocalizationSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): i18n audits, 0% hardcoded strings, and bilingual dictionaries (`de`/`en`) in the project's localization format.
20. **PerformanceOptimizer** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Low-level profiling, allocation reduction, memory leak prevention, and throughput optimization.
21. **SecurityAuditor** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Command execution safety, secret leak prevention, dependency CVE audits via ecosystem tools, path traversal prevention, and secure serialization.
22. **DatabaseSpecialist** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Database schema design, ORM persistence mappings, reversible migrations, indexing strategies, and N+1 query avoidance.
23. **ApiContractSpecialist** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): API design and contract governance specialist for OpenAPI 3.x, gRPC/Protobuf, GraphQL, RFC 7807 Problem Details, and non-breaking contract evolution.

## Four-Step Codebase Analysis Protocol

Whenever an agent explores, analyzes, or debugs a codebase, it must strictly proceed in four steps:

1. **Check Current Modular Architecture Baseline**: Check `ARCHITECTURE.md`, module specifications (`docs/architecture/modules/*.md`), and `.arch-sync.json`.
2. **Synchronize Architecture if Needed**: If documentation is missing or outdated compared to recent commits, run `ArchitectureSync` (`get-arch-diff.ps1` / `get-arch-diff.sh`) to synchronize affected module documents.
3. **Deduce State from Modular Documentation**: Derive system structure, contracts, dependencies, and state flows directly from the relevant modular architecture specification (`docs/architecture/modules/<module>.md`).
4. **Targeted Code Inspection Only for Critical Details**: Read concrete source code files strictly when specific low-level implementation details (e.g. algorithmic nuance, interop declarations, precise event binding lines) are indispensable.

> [!IMPORTANT]
> **Modular Architecture Depth & Context Isolation**:
> Architecture documents must be sufficiently detailed (interfaces, records, state transitions, threading guarantees) so that broad, whole-repository code scans are prevented. At the same time, maintaining separate files per module (`docs/architecture/modules/<module>.md`) ensures that agents only load the single relevant module into context, preventing the agent's context window from continuously filling up.

## Universal Model Tiering & Compound Execution Strategy

This repository supports cross-platform execution across **Google Antigravity**, **GitHub Copilot**, **Cursor**, and standalone LLM environments. Detailed tier mappings, thinking budgets, and platform preferences are specified in [`rules/model-tiers.json`](rules/model-tiers.json).

> [!TIP]
> **Cost-Efficiency Policy**: As a general rule, high-end and high-cost models (e.g. Pro, Opus, o1, flagship tiers) are not used. Exclusively cost-efficient models (e.g. Flash, Flash-Lite, Haiku, Mini tiers) are utilized by default. High reasoning levels (Thinking Effort: High/Extended) must only be used if they are more cost-efficient than switching models. High-end models are strictly reserved for exceptional cases where the nature or scope of the task genuinely requires them or when switching models is more cost-effective than generating high thinking token volumes.

### Execution Strategy & Modes
1. **Compound Phased Execution (Default & Recommended)**:
   - The primary agent executes role phases sequentially within a single persistent session (Control -> Requirement -> Architekt -> Developer -> Verifikation).
   - **KV-Cache Continuity**: Retaining the conversation history unlocks 75–90% prompt caching discounts across turns, dramatically slashing latency and token expenditure.
   - **Calibrated Thinking Budgets**: Developer and Tester use `low` reasoning budgets because compiler diagnostics and test suites act as deterministic ground truth.
   - **Terminal Hygiene**: Scripts and testrunners run quietly (`dotnet test --verbosity quiet`, `cargo test -q`, PowerShell `-NoProfile`) to eliminate terminal spam.
2. **Selective Subagent Forking (Antigravity / AGY)**:
   - Subagents (`invoke_subagent`) are leveraged selectively for **divergent, high-noise exploration** (broad file searches, web research, multi-repo audits) to prevent polluting the primary thread's cache prefix.
3. **Sequential Persona Mode (GitHub Copilot / Cursor / Single-Model)**:
   - For clients lacking subagent-forking APIs, a single agent executes role phases sequentially using semantic prompt-based thinking budgets.

### Zero-Token Runtime Capability Detection & 24h Persistent Caching
To determine the active environment and available models at zero token cost:

```powershell
# Windows (Cached for 24 hours across sessions & skills)
pwsh -NoProfile -ExecutionPolicy Bypass -File ./_agents/scripts/detect-models.ps1

# Force on-demand re-probe
pwsh -NoProfile -ExecutionPolicy Bypass -File ./_agents/scripts/detect-models.ps1 -Force
```
```bash
# macOS / Linux (Cached for 24 hours across sessions & skills)
bash ./_agents/scripts/detect-models.sh

# Force on-demand re-probe
bash ./_agents/scripts/detect-models.sh --force
```

### Deterministic Automation & Zero-Token Script Toolkit (`scripts/`)

To minimize LLM token consumption, eliminate non-deterministic hallucinations, and protect the context window from massive terminal log dumps, repetitive operational checks are offloaded to high-performance local scripts (PowerShell & Bash parity):

| Script | Relevant Role(s) | Functionality |
| :--- | :--- | :--- |
| `detect-models.ps1/.sh` | `Control` | Probes active environment and models with 24-hour persistent local disk caching. |
| `detect-tech-stack.ps1/.sh` | `Control`, `Developer` | Auto-detects programming languages, build systems, package managers, and test runners. |
| `run-fast-gate.ps1/.sh` | `Verifikation`, `Developer` | Stage 1 Zero-Token compiler, linter, and quiet test suite fast gate. |
| `lint-clean-architecture.ps1/.sh` | `CodeReviewer`, `Verifikation` | Evaluates declarative layer import boundaries ([`rules/clean-architecture.json`](rules/clean-architecture.json)) and code metric limits. |
| `scan-guardrails.ps1/.sh` | `SecurityAuditor`, `CommitManager` | Pre-commit scanner enforcing Safe Rust (0 `unsafe`), secret leak prevention, and terminal hygiene. |
| `lint-requirements.ps1/.sh` | `RequirementEngineer` | Validates requirement formatting, duplicate detection, and allocates scoped IDs (`REQ-<SCOPE>-XXX`). |
| `calculate-semver.ps1/.sh` | `ReleaseManager` | Parses Conventional Commits to deterministically calculate next SemVer tag (`major`, `minor`, `patch`). |
| `generate-changelog.ps1/.sh` | `ReleaseManager`, `DocumentationSpecialist` | Generates Keep-a-Changelog compatible release notes from git commits since last tag. |
| `audit-i18n.ps1/.sh` | `LocalizationSpecialist` | Verifies key parity between German (`de`) and English (`en`) localization resource files. |
| `generate-pr-summary.ps1/.sh` | `PRManager` | Generates structured PR descriptions, commit listings, and test evidence summaries. |
| `diagnose-git-state.ps1/.sh` | `GitTroubleshooter` | Analyzes branch state, dirty working tree, diverged commits, and merge/rebase status. |
| `run-security-audit.ps1/.sh` | `SecurityAuditor`, `DevOpsEngineer` | Universal dependency CVE audit runner (`dotnet list package --vulnerable`, `cargo audit`, `npm audit`, `pip-audit`). |
| `check-test-coverage.ps1/.sh` | `Tester`, `Verifikation` | Parses Cobertura XML, LCOV, and coverage JSON to assert coverage threshold compliance. |
| `lint-db-migrations.ps1/.sh` | `DatabaseSpecialist` | Lints database migrations for versioning, `.up.sql`/`.down.sql` symmetry, and destructive DDL statements. |
| `lint-api-contracts.ps1/.sh` | `ApiContractSpecialist` | Validates OpenAPI schema structure, internal `$ref` pointers, Protobuf tags, and GraphQL schemas. |
| `find-orphaned-assets.ps1/.sh` | `RefactoringSpecialist`, `DocumentationSpecialist` | Detects unreferenced media files and unindexed modular documentation files. |
| `lint-ci-workflows.ps1/.sh` | `DevOpsEngineer` | Lints GitHub Actions workflows for syntax, least-privilege `permissions:`, and `-NoProfile` hygiene. |
| `lint-docs.ps1/.sh` | `DocumentationSpecialist` | Validates relative markdown links and local file references. |
| `get-arch-diff.ps1/.sh` | `ArchitectureSync` | Identifies modified host files since last sync commit, strictly excluding submodules. |
| `record-telemetry.ps1/.sh` | `Control` | Zero-overhead lifecycle event and duration recorder. |
| `show-telemetry.ps1/.sh` | `Control` | Formats local telemetry run history. |
| `run-evals.ps1/.sh` | `Control` | Runs synthetic evaluation cases ([`evals/eval-cases.json`](evals/eval-cases.json)) against governance invariants. |
| `test-skills.ps1/.sh` | CI / Quality Gate | Comprehensive 38-step test harness validating all skills, scripts, links, and line endings. |

## Lifecycle Action Execution Governance

Defined lifecycle actions (`commit`, `push`, `pr merge`, `release`) adhere to six core execution principles:

1. **Strict Action Execution (Atomic Scope)**:
   When an action is explicitly requested (e.g. `commit`), only that action is performed. Unsolicited side-actions (e.g. automatic `push`) are omitted.
2. **State-Driven Prerequisite Resolution**:
   If the repository or workspace state requires preceding actions (e.g. uncommitted workspace changes when `push` is requested), the necessary prerequisites are automatically resolved first.
3. **Proactive Next-Step Offering**:
   Upon successful completion of an action, the logical successor action is proactively offered to the user (e.g. offering `push` after `commit`, or offering PR creation after `push`).
4. **Adaptive Gate Resolution (Intention Matching with Anomaly Fallback)**:
   When the user's prompt directly instructs or parameterizes an action (e.g. "erstelle einen minor release", "commit with message ..."), interactive confirmation is satisfied by the prompt and executes directly. A mandatory confirmation gate pauses execution if: (a) uncommitted/untracked changes exceed the current scope, (b) SemVer history contradicts the requested release bump, or (c) atypical repository states occur.
5. **Explicit User Override**:
   The user may explicitly direct combined or deviating behavior at any time (e.g. "commit and push directly").
6. **Atypical State & Safety Confirmation Gate**:
   If following these rules encounters an unexpected or high-risk state (e.g. detached HEAD, merge conflicts, unexpected untracked files, unverified release states), the agent halts, describes the situation, and requests explicit user confirmation before proceeding.

## Integration in Projects

### Client Directory Compatibility (`.agents` vs. `_agents`)

Different AI coding assistants discover skill directories differently:

- **Gemini / Google Antigravity**: Uses `_agents` as the standard customization root (keeping `.agents` available for repository-specific customizations).
- **GitHub Copilot & Other Clients**: Specifically expect `.agents/` as the default directory. If your repository is used with GitHub Copilot or other AI coding tools, use `.agents` (or create a symlink pointing `.agents` to `_agents`).

### As a Git Submodule

#### Option A: Target Directory `_agents` (Optimized for Gemini / Antigravity)
Adding the shared repository as `_agents` leaves `.agents` free for repository-specific rules and local custom overrides:

```bash
git submodule add --name agent-skills -b main https://github.com/histore/agent-skills.git _agents
```

#### Option B: Target Directory `.agents` (Universal / GitHub Copilot & Gemini)
If your workflow involves GitHub Copilot or tools requiring `.agents/`:

```bash
git submodule add --name agent-skills -b main https://github.com/histore/agent-skills.git .agents
```

### Cloning a Repository with Submodules

```bash
git clone --recurse-submodules <repo-url>
# or in an existing clone:
git submodule update --init --recursive
```

### Updating to Latest Skills

```bash
# For _agents:
git submodule update --remote _agents
# For .agents:
git submodule update --remote .agents
```
