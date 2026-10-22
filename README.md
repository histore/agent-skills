# Agent Skills & Subagent Roles (`agent-skills`)

A modular, reusable repository of specialized AI subagent roles, skills, zero-token automation scripts, and governance rules designed for modern software development with Antigravity / Gemini agents and cross-platform AI assistants.

**Core Mission — High Engineering Quality at Minimum Necessary Cost**:
1. **Maximum Result Quality**: Enforces **Clean Architecture**, **Clean Code** (SOLID, Safe Rust), **Inner-Loop TDD**, **Two-Stage Shift-Left Quality Gates**, and **Zero-Data-Loss Safety Guardrails**.
2. **Minimum Necessary Cost**: Slashes token and compute expenditure via **Compound Phased Execution** (75–90% KV-cache discounts), **Adaptive T-Shirt Profiles** (70–80% fast-track savings), **Sweet-Spot Model & Reasoning Allocation**, **Zero-Token Deterministic Scripts**, and strict **Anti-Ceremony / Context Isolation Guardrails**.

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
2. **RequirementEngineer** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 / Gemini 3.8 Flash (High)`): Translates user requirements into Given-When-Then acceptance criteria, managing single-file or modular requirements scaling (`docs/requirements/modules/*.md`), namespaced IDs, and duplicate/conflict detection (Tier 1 for Complex/Architectural profiles).
3. **Architekt** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 / Gemini 3.8 Flash (High)`): Defines contracts, interfaces, dependency management, and layer boundaries following Clean Architecture. Authors modular specifications and optional skeleton stubs for complex decoupling (Tier 1 for Complex/Architectural profiles).
4. **Developer** (`Tier 3 | Balanced Reasoning` - Ref: `Gemini 3.8 Flash (Medium) / Claude Sonnet 5.5 (Medium)`): Implements production code and unit tests via **Inner-Loop TDD** (Red-Green-Refactor), adhering to Clean Code, targeted test feedback loops (max 3 iterations), and test integrity guardrails.
5. **Tester** (`Tier 3 | Balanced Reasoning` - Ref: `Gemini 3.8 Flash (Medium) / Claude Sonnet 5.5 (Medium)`): Designs and implements integration test suites, boundary stress tests, and reproduction tests, certifying 100% pass rates post-implementation via the native quiet test runner (AAA pattern, 0 failures).
6. **Verifikation** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 / Gemini 3.8 Flash (High)`): Two-Stage Quality Gate: deterministic machine checks (build, lint, testrunner) followed by concise requirements, architectural traceability, and logical correctness audit (consulting `CodeReviewer` for deep adversarial defect analysis when needed).
7. **CommitManager** (`Tier 4 | Fast Deterministic` - Ref: `Gemini 3.8 Flash (Low)`): Manages Git commit and push actions with atomic isolation, state-driven prerequisite resolution, interactive message confirmation, and proactive next-step recommendations.
8. **PRManager** (`Tier 4 | Fast Deterministic` - Ref: `Gemini 3.8 Flash (Low)`): Manages the Pull Request lifecycle (`gh pr create`, delayed-polling CI checks, squash-merge, and proactive next steps) strictly on-demand after developer approval.

### General Support Roles (Lifecycle Specialists)
9. **Troubleshooter** (`Tier 1 | High/Extended Thinking` - Ref: `Claude Opus 5.5 / Gemini 3.8 Flash (High)`): Diagnoses bugs, analyzes call stacks and event hierarchies, identifies root causes, and specifies minimal failing reproduction tests for Inner-Loop or Tester TDD handoffs.
10. **RefactoringSpecialist** (`Tier 3 | Balanced Reasoning` - Ref: `Gemini 3.8 Flash (Medium) / Claude Sonnet 5.5 (Medium)`): On-demand specialist auditing code smells and technical debt, designing and executing safe, test-backed Fowler refactorings.
11. **DocumentationSpecialist** (`Tier 3 | Balanced Reasoning` - Ref: `Gemini 3.8 Flash (Medium)`): On-demand specialist authoring API doc comments, user manuals, CHANGELOG.md, and in-app help guides in English.
12. **ReleaseManager** (`Tier 4 | Fast Deterministic` - Ref: `Gemini 3.8 Flash (Low)`): Manages deployment pipelines, packaging, SemVer tag calculation, branch/sync prerequisite validation, and tag creation & push upon user approval.
13. **CodeExplainer** (`Tier 1 | High/Extended Thinking` - Ref: `Claude Opus 5.5 / Gemini 3.8 Flash (High)`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's OS language, inserting didactic comments directly into code files (in English by default, or in a user-specified language).
14. **ArchitectureSync** (`Tier 3 | Balanced Reasoning` - Ref: `Gemini 3.8 Flash (Medium)`): Incrementally audits and synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts (`get-arch-diff`) to eliminate context bloat.
15. **GitTroubleshooter** (`Tier 1 | High/Extended Thinking` - Ref: `Claude Opus 5.5 / Gemini 3.8 Flash (High)`): Diagnoses repository anomalies, resolves complex three-way merge, rebase, and cherry-pick conflicts, safely recovers lost commits or detached states via reflog, and enforces a strict zero-data-loss safety protocol (backup snapshots, automated build & test gates).
16. **DevOpsEngineer** (`Tier 3 | Balanced Reasoning` - Ref: `Gemini 3.8 Flash (Medium) / Claude Sonnet 5.5 (Medium)`): Authors and maintains CI/CD automation workflows (GitHub Actions), multi-stage Dockerfiles, compose environments, build matrices, and deployment configurations.
17. **CodeReviewer** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 (High) / Gemini 3.8 Flash (High)`): Adversarial static code reviewer specialized in hunting subtle bugs, edge-case regressions, logic flaws, race conditions, resource leaks, and unhandled boundary states in diffs, PRs, or target source files.

### Domain Specialists (On-Demand / Consulted by Skills)
Domain specialists are **not** part of the default linear workflow. They are engaged conditionally by `Control` when appropriate for the task, or consulted directly by other skills (Developer, Architekt, Troubleshooter, Verifikation) to resolve domain-specific details:
18. **UIDesigner** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 / Gemini 3.8 Flash (High)`): UI/UX ergonomics, interaction flows, layout hierarchy, and design tokens for the project's UI environment.
19. **LocalizationSpecialist** (`Tier 3 | Balanced Reasoning` - Ref: `Gemini 3.8 Flash (Medium)`): i18n audits, 0% hardcoded strings, and bilingual dictionaries (`de`/`en`) in the project's localization format.
20. **PerformanceOptimizer** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 (High) / Gemini 3.8 Flash (High)`): Low-level profiling, allocation reduction, memory leak prevention, and throughput optimization.
21. **SecurityAuditor** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 (High) / Gemini 3.8 Flash (High)`): Command execution safety, secret leak prevention, dependency CVE audits via ecosystem tools, path traversal prevention, and secure serialization.
22. **DatabaseSpecialist** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 (High) / Gemini 3.8 Flash (High)`): Database schema design, ORM persistence mappings, reversible migrations, indexing strategies, and N+1 query avoidance.
23. **ApiContractSpecialist** (`Tier 2 | High Reasoning` - Ref: `Claude Sonnet 5.5 / Gemini 3.8 Flash (High)`): API design and contract governance specialist for OpenAPI 3.x, gRPC/Protobuf, GraphQL, RFC 7807 Problem Details, and non-breaking contract evolution.

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
> **Cost-Efficiency & Sweet-Spot Policy**: Always hit the "sweet spot" balancing cognitive capability and cost-efficiency. Avoid wasteful over-provisioning (flagship models for simple deterministic tasks or file grepping) as well as destructive under-provisioning (starving complex architectural, diagnostic, or security analysis with underpowered models that cause hallucination loops, test thrashing, or flawed system designs). In multi-agent environments, subagents default to `inherit` to preserve session fidelity without artificial downgrades. For divergent research, dispatch lightweight models (`flash`). For mechanical lifecycle tasks (commit, PR, release), dispatch reliable models (`flash`), strictly avoiding underpowered tiers (`flash_lite`). For complex profiles (Profile C) or persistent diagnostic impasses, escalate to flagship models (`pro`) or high reasoning depth.
> **Cost-Guardrail (Budget Protection)**: Automatically throttles subagent dispatches or triggers an advisory confirmation gate when expensive flagship models (> $4.00/M input, > $20.00/M output) are active for routine or mechanical operations.

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
| `detect-models.ps1/.sh` | `Control` | Probes active environment, model catalog, and cost-guardrail thresholds with 24-hour persistent local disk caching. |
| `detect-tech-stack.ps1/.sh` | `Control`, `Developer` | Auto-detects programming languages, build systems, package managers, and test runners. |
| `run-fast-gate.ps1/.sh` | `Verifikation`, `Developer` | Stage 1 Zero-Token compiler, linter, and quiet test suite fast gate. |
| `run-all-gates.ps1/.sh` | `Verifikation`, `Control` | Unified quality gates orchestrator running all static zero-token linters and Stage 1 fast gate. |
| `lint-clean-architecture.ps1/.sh` | `CodeReviewer`, `Verifikation` | Evaluates declarative layer import boundaries ([`rules/clean-architecture.json`](rules/clean-architecture.json)) and code metric limits. |
| `scan-guardrails.ps1/.sh` | `SecurityAuditor`, `CommitManager` | Pre-commit scanner enforcing Safe Rust (0 `unsafe`), secret leak prevention, and terminal hygiene. |
| `lint-requirements.ps1/.sh` | `RequirementEngineer` | Validates requirement formatting, duplicate detection, and allocates scoped IDs (`REQ-<SCOPE>-XXX`). |
| `calculate-semver.ps1/.sh` | `ReleaseManager` | Parses Conventional Commits to deterministically calculate next SemVer tag (`major`, `minor`, `patch`). |
| `generate-changelog.ps1/.sh` | `ReleaseManager`, `DocumentationSpecialist` | Generates Keep-a-Changelog compatible release notes from git commits since last tag. |
| `audit-i18n.ps1/.sh` | `LocalizationSpecialist` | Verifies key parity between German (`de`) and English (`en`) localization resource files. |
| `generate-pr-summary.ps1/.sh` | `PRManager` | Generates structured PR descriptions, commit listings, and test evidence summaries. |
| `diagnose-git-state.ps1/.sh` | `GitTroubleshooter` | Analyzes branch state, dirty working tree, diverged commits, and merge/rebase status. |
| `create-safety-backup.ps1/.sh` | `GitTroubleshooter` | Creates zero-data-loss backup branches and stashes prior to destructive Git operations. |
| `run-security-audit.ps1/.sh` | `SecurityAuditor`, `DevOpsEngineer` | Universal dependency CVE audit runner (`dotnet list package --vulnerable`, `cargo audit`, `npm audit`, `pip-audit`). |
| `check-test-coverage.ps1/.sh` | `Tester`, `Verifikation` | Parses Cobertura XML, LCOV, and coverage JSON to assert coverage threshold compliance. |
| `collect-test-failures.ps1/.sh` | `Tester`, `Troubleshooter` | Parses JUnit/TRX test reports and extracts compacted failure messages and stack traces. |
| `benchmark-startup.ps1/.sh` | `PerformanceOptimizer` | Measures cold/warm CLI or application startup latency (min, avg, median, p95, max). |
| `lint-db-migrations.ps1/.sh` | `DatabaseSpecialist` | Lints database migrations for versioning, `.up.sql`/`.down.sql` symmetry, and destructive DDL statements. |
| `lint-api-contracts.ps1/.sh` | `ApiContractSpecialist` | Validates OpenAPI schema structure, internal `$ref` pointers, Protobuf tags, and GraphQL schemas. |
| `find-orphaned-assets.ps1/.sh` | `RefactoringSpecialist`, `DocumentationSpecialist` | Detects unreferenced media files and unindexed modular documentation files. |
| `lint-ci-workflows.ps1/.sh` | `DevOpsEngineer` | Lints GitHub Actions workflows for syntax, least-privilege `permissions:`, and `-NoProfile` hygiene. |
| `lint-docs.ps1/.sh` | `DocumentationSpecialist` | Validates relative markdown links (ignoring fenced/inline code) and modular architecture parity. |
| `get-arch-diff.ps1/.sh` | `ArchitectureSync` | Identifies modified host files since last sync commit, strictly excluding submodules. |
| `record-telemetry.ps1/.sh` | `Control` | Zero-overhead lifecycle event and duration recorder. |
| `show-telemetry.ps1/.sh` | `Control` | Formats local telemetry run history. |
| `run-evals.ps1/.sh` | `Control` | Runs synthetic evaluation cases ([`evals/eval-cases.json`](evals/eval-cases.json)) against governance and skill file invariants. |
| `setup-agent-skills.ps1/.sh` | Setup / Admin | Automates integration of agent-skills globally (user level) or into target projects (project level) for Antigravity and Copilot. |
| `test-skills.ps1/.sh` | CI / Quality Gate | Comprehensive 41-step test harness validating all skills, scripts, links, and line endings. |

## Lifecycle Action Execution Governance

Defined lifecycle actions (`commit`, `push`, `pr merge`, `release`) adhere to seven core execution principles:

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
7. **Clean Release Tagging Invariant**:
   Release tags (`vX.Y.Z`) must be applied directly to the existing production/merge commit on `main`. Standalone metadata commits (such as `docs(changelog): release v...`) directly on `main` during release tagging are strictly prohibited to maintain an uncluttered Git commit history focused on actual functional changes. Release notes belong in tag annotations or GitHub Releases.

## Integration & Usage Guide (Project & User Level)

`agent-skills` can be deployed at two distinct scopes depending on your workflow:
- **User Level (Global Machine Scope)**: Configured once per developer workstation. All skills, governance rules, and the `ask-control` orchestrator are instantly active across every folder and project you open without modifying repository files or adding submodules.
- **Project Level (Repository / Team Scope)**: Embedded directly into a specific project (via lightweight directory link or Git submodule). Shares rules, architecture contracts, and deterministic CI/CD verification scripts with the entire team.

Both **Google Antigravity (AGY / Gemini)** and **GitHub Copilot (VS Code & CLI)** are fully supported at both levels.

---

### Integration Matrix: At a Glance

| AI Assistant | User Level (Global Machine Scope) | Project Level (Project Scope) |
| :--- | :--- | :--- |
| **Google Antigravity (AGY / Gemini)** | Links in `~/.gemini/config/` (`skills`, `rules`) + global `~/.gemini/GEMINI.md` | Directory link or submodule in `_agents/` (or `.agents/`) + project `AGENTS.md` |
| **GitHub Copilot (VS Code Chat)** | VS Code User `settings.json`: `"github.copilot.chat.customInstructions"` pointing to global `copilot-instructions.md` | Provision `.github/copilot-instructions.md` in repository root |
| **GitHub Copilot (CLI & Skills)** | Import skills via `copilot skill add` or link to `~/.copilot/skills/` | Directory link or submodule in `.agents/` (Copilot natively checks `.agents/skills/`) |
| **Automated 1-Click Setup** | `pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -Global`<br>`./scripts/setup-agent-skills.sh --global` | `pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject <dir>`<br>`./scripts/setup-agent-skills.sh -p <dir>` |

---

### Quickstart: 1-Click Automated Setup Scripts

The repository includes dedicated automation scripts ([`scripts/setup-agent-skills.ps1`](scripts/setup-agent-skills.ps1) and [`scripts/setup-agent-skills.sh`](scripts/setup-agent-skills.sh)) to set up both Antigravity and Copilot in a single step.

#### Option 1: Global User-Level Setup (All Projects)
Provisions global Antigravity links (`~/.gemini/config/skills`, `~/.gemini/config/rules`) and creates the global Copilot instructions file (`~/.gemini/config/copilot-instructions.md`).

- **Windows (PowerShell)**:
  ```powershell
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -Global
  ```
- **macOS / Linux (Bash)**:
  ```bash
  ./scripts/setup-agent-skills.sh --global
  ```

#### Option 2: Project-Level Setup (Specific Project)
Creates the directory link (`_agents` and/or `.agents`) pointing to this repository and provisions `.github/copilot-instructions.md` in the target project.

- **Windows (PowerShell)**:
  ```powershell
  # Default: creates _agents link and .github/copilot-instructions.md
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\path\to\target-project"

  # Create both _agents (Antigravity) and .agents (Copilot) links:
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\path\to\target-project" -FolderType both
  ```
- **macOS / Linux (Bash)**:
  ```bash
  # Default: creates _agents link and .github/copilot-instructions.md
  ./scripts/setup-agent-skills.sh -p /path/to/target-project

  # Create both _agents (Antigravity) and .agents (Copilot) links:
  ./scripts/setup-agent-skills.sh -p /path/to/target-project -t both
  ```

**Script Parameters**:
- `-TargetProject <dir>` / `-p, --project <dir>`: Path to the target project directory.
- `-Global` / `-g, --global`: Installs globally in the user configuration.
- `-FolderType <type>` / `-t, --folder-type <type>`: `_agents` (default), `.agents`, or `both`.
- `-SkipCopilot` / `--skip-copilot`: Skips creating `.github/copilot-instructions.md`.
- `-Force` / `-f, --force`: Overwrites existing symlinks/junctions or files.

---

### Manual Setup: Google Antigravity (AGY / Gemini)

#### A. User Level (Global Machine Scope)
Enables all 23 skills, model tier mappings, and the `ask-control` orchestrator globally across all projects on your workstation.

1. **Link Skills and Rules into User Gemini Config**:
   - **Windows (PowerShell)**:
     ```powershell
     # Replace C:\path\to\agent-skills with your local clone path
     $skillsTarget = "C:\path\to\agent-skills\skills"
     $rulesTarget = "C:\path\to\agent-skills\rules"
     $geminiConfig = "$env:USERPROFILE\.gemini\config"

     New-Item -ItemType Directory -Path $geminiConfig -Force | Out-Null
     New-Item -ItemType Junction -Path "$geminiConfig\skills" -Target $skillsTarget -Force
     New-Item -ItemType Junction -Path "$geminiConfig\rules" -Target $rulesTarget -Force
     ```
   - **macOS / Linux (Bash)**:
     ```bash
     mkdir -p ~/.gemini/config
     ln -sfn /path/to/agent-skills/skills ~/.gemini/config/skills
     ln -sfn /path/to/agent-skills/rules ~/.gemini/config/rules
     ```

2. **Configure Global Default Orchestrator (`ask-control`)**:
   Add the default orchestrator directive to your global instructions (`~/.gemini/GEMINI.md` or `%USERPROFILE%\.gemini\GEMINI.md`):
   ```markdown
   ## Default Role & Orchestration
   - Default to the `Control` persona (`ask-control`) as the central orchestrator for all tasks.
   - Automatically classify requests into adaptive execution profiles (Profile 0, A, B, C) and coordinate downstream roles.
   ```
   Now, any Antigravity conversation across any workspace automatically initializes in the `Control` orchestrator mindset.

#### B. Project Level (Project Scope)

- **Approach 1: Directory Junction / Symlink (Recommended for Local Work)**:
  Zero-overhead integration without Git submodule baggage:
  - **Windows (PowerShell)**:
    ```powershell
    New-Item -ItemType Junction -Path "C:\path\to\target-project\_agents" -Target "C:\path\to\agent-skills"
    ```
  - **macOS / Linux (Bash)**:
    ```bash
    ln -sfn /path/to/agent-skills /path/to/target-project/_agents
    ```
  Antigravity automatically loads customizations from `_agents/skills` and `_agents/rules`. Add project-specific rules in the project root's `AGENTS.md`.

- **Approach 2: Git Submodule (Recommended for Teams & CI/CD)**:
  If your entire team should share the skills and run deterministic CI scripts:
  ```bash
  git submodule add --name agent-skills -b main https://github.com/histore/agent-skills.git _agents
  ```

---

### Manual Setup: GitHub Copilot (VS Code & CLI)

GitHub Copilot operates in **Sequential Persona Mode** (`Control` -> `Developer` -> `Verifikation` -> `CommitManager`) and can be configured globally or per project.

#### A. User Level (Global Machine Scope)

##### 1. VS Code Copilot Chat (Global Custom Instructions)
Applies Clean Code, Clean Architecture, Safe Rust, and Inner-Loop TDD principles across all your VS Code Copilot chats globally.

1. Ensure the global instructions file exists (copied via `setup-agent-skills.ps1 -Global` or manually copied from [`.github/copilot-instructions.md`](.github/copilot-instructions.md) into `~/.gemini/config/copilot-instructions.md`).
2. Open VS Code User Settings JSON (`Ctrl+Shift+P` -> `Preferences: Open User Settings (JSON)`).
3. Add the `github.copilot.chat.customInstructions` configuration:
   ```json
   "github.copilot.chat.customInstructions": [
     {
       "path": "C:/Users/<Username>/.gemini/config/copilot-instructions.md"
     }
   ]
   ```
   *(On macOS/Linux, use `"/home/<username>/.gemini/config/copilot-instructions.md"` or `"~/.gemini/config/copilot-instructions.md"`)*.

##### 2. GitHub Copilot CLI & Slash Commands (`~/.copilot/skills/`)
To use agent skills as slash commands (e.g. `/ask-control`, `/ask-developer`, `/ask-troubleshooter`) in GitHub Copilot CLI:

- **Option 1: Direct Import via Copilot CLI (`copilot skill add`)**:
  ```bash
  # Import all skills into your Copilot user profile:
  copilot skill add C:\path\to\agent-skills\skills

  # Or import a specific skill:
  copilot skill add C:\path\to\agent-skills\skills\ask-control

  # List installed skills:
  copilot skill list
  ```
  *(Inside an interactive Copilot CLI session, you can also use `/skills add <path>` or type `/skills` to toggle available skills).*

- **Option 2: Symlink / Junction to Personal Skills Directory (`~/.copilot/skills`)**:
  - **Windows (PowerShell)**:
    ```powershell
    New-Item -ItemType Directory -Path "$env:USERPROFILE\.copilot\skills" -Force | Out-Null
    Get-ChildItem -Path "C:\path\to\agent-skills\skills" -Directory | ForEach-Object {
        New-Item -ItemType Junction -Path "$env:USERPROFILE\.copilot\skills\$($_.Name)" -Target $_.FullName -Force
    }
    ```
  - **macOS / Linux (Bash)**:
    ```bash
    mkdir -p ~/.copilot/skills
    for skill in /path/to/agent-skills/skills/*; do
      [ -d "$skill" ] && ln -sfn "$skill" ~/.copilot/skills/"$(basename "$skill")"
    done
    ```

#### B. Project Level (Project Scope)

##### 1. Project-Specific Copilot Instructions (`.github/copilot-instructions.md`)
Copy the provided template to enforce lightweight engineering standards in your repository:
```bash
# Inside your project directory:
mkdir -p .github
cp /path/to/agent-skills/.github/copilot-instructions.md .github/copilot-instructions.md
```
GitHub Copilot in VS Code automatically detects and loads `.github/copilot-instructions.md`.

##### 2. Skills Folder (`.agents/skills/`)
Copilot CLI and VS Code automatically detect skills in `.agents/skills/`.
- **Directory Link (Local)**:
  - Windows: `New-Item -ItemType Junction -Path ".\.agents" -Target "C:\path\to\agent-skills"`
  - Linux/macOS: `ln -sfn /path/to/agent-skills ./.agents`
- **Git Submodule (Team / CI)**:
  ```bash
  git submodule add --name agent-skills -b main https://github.com/histore/agent-skills.git .agents
  ```

---

### Dual Compatibility: Antigravity (`_agents`) & Copilot (`.agents`)

Antigravity checks `_agents/` by default, whereas Copilot and universal tools look for `.agents/`. If you want both assistants to work simultaneously with full local skill access in the same project:

1. **Via Setup Script**:
   ```powershell
   pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\path\to\target-project" -FolderType both
   ```
2. **Via Manual Junctions / Symlinks**:
   Link both `_agents` and `.agents` in the target project directory to the `agent-skills` repository.

---

### Submodule Maintenance (Cloning & Updating)

#### Cloning a Repository with Submodules
```bash
git clone --recurse-submodules <repo-url>
# or in an existing clone:
git submodule update --init --recursive
```

#### Updating to Latest Skills
```bash
# For _agents (Antigravity):
git submodule update --remote _agents

# For .agents (Copilot / Universal):
git submodule update --remote .agents
```
