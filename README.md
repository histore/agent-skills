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
├── COMMON_WORKFLOWS.md     # Engineering workflows & invocation cheat sheet (AGY & Copilot)
├── ARCHITECTURE.md         # System architecture baseline
├── rules/
│   ├── clean-architecture.json # Declarative Clean Architecture layer rules and metric thresholds
│   ├── model-tiers.json    # Universal model tier mapping and thinking budgets
│   └── subagents.md        # Architectural rules and context-isolation protocol
├── scripts/                # Zero-token deterministic automation, linting, and verification scripts
└── skills/                 # 5 Consolidated Capability Packs
    ├── ask-control/                # Unified Core Lifecycle Engineer & Orchestrator
    ├── ask-troubleshooter/         # Diagnostics, Bug RCA, Adversarial Review, Refactoring & Profiling
    ├── ask-git-troubleshooter/     # Git Safety, Conflicts & Recovery (Zero Data Loss)
    ├── ask-contract-specialist/    # Living Specs, API Contracts, DB Migrations, Arch Sync & i18n
    └── ask-release-manager/        # Release Automation, DevOps, SemVer & Security Audits
```

> [!TIP]
> **Daily Development Cheat Sheet**:
> For practical prompt patterns, dual-system command mappings, and execution workflows comparing Google Antigravity and GitHub Copilot, see [COMMON_WORKFLOWS.md](COMMON_WORKFLOWS.md).

## Available Roles & Capability Packs (V2 Architecture)

### 1. Unified Core Lifecycle Engineer (`ask-control`)
- **Control** (`Tier 1 | Extended Thinking` / `Tier 3 | Low-Minimal` during Inner-Loop implementation):
  Universal central workflow orchestrator and full-lifecycle software engineer. Executes end-to-end development phases via **Compound Phased Execution** in Antigravity or **Sequential Persona Transitions** in GitHub Copilot:
  - **Dynamic Tech Stack Discovery**: Dynamically identifies project language, framework, and test runners without hardcoded assumptions.
  - **T-Shirt Sizing & Execution Profiles**: Profile 0 (Direct Response, zero git/tests), Profile A (Fast-Track Developer Inner-Loop TDD), Profile B (Standard feature engineering with contracts), Profile C (Complex architecture redesigns).
  - **Inner-Loop TDD**: Author targeted unit tests (AAA pattern), implement Clean Code, in-place refactor, adhere to 3-iteration circuit breaker, and enforce Safe Rust (zero `unsafe`).
  - **Two-Stage Quality Gate**: Single-command deterministic Stage-1 fast-gate (`pwsh -NoProfile -File ./scripts/run-fast-gate.ps1`), followed by Stage-2 concise requirement and Clean Architecture verification.
  - **Lifecycle Action Governance**: Atomic Git commits and PR creation with host workspace scoping and submodule isolation (`_agents`/`.agents`).

### 2. On-Demand Specialist Capability Packs
Four domain-specific capability packs engaged conditionally when deep specialization is required:
1. **Troubleshooter** (`ask-troubleshooter`, `Tier 1 | Deep Reasoning`):
   Consolidated diagnostics and code health: systematic root cause analysis (RCA), failing reproduction test specifications (Phase RED), adversarial code review (hunting edge-case regressions, concurrency hazards, memory leaks), safe Fowler refactoring, and startup/throughput profiling (`benchmark-startup.ps1`).
2. **GitTroubleshooter** (`ask-git-troubleshooter`, `Tier 1 | Deep Reasoning`):
   Git safety and recovery: diagnoses repository anomalies (`diagnose-git-state.ps1`), creates pre-mutation safety snapshots (`create-safety-backup.ps1`), resolves 3-way merge/rebase conflicts, recovers detached states via reflog, and enforces a strict zero-data-loss invariant.
3. **ContractSpecialist** (`ask-contract-specialist`, `Tier 2 | Analytical`):
   System specifications and contracts: authors living feature specs (`docs/features/FEAT-*.md`) and concept tracks (`concept > req > impl` and `concept > impl`) via `inspect-feature-specs.ps1`, requirements governance (`lint-requirements.ps1`), REST OpenAPI / gRPC Protobuf contracts (`lint-api-contracts.ps1`), database migrations and ORM models (`lint-db-migrations.ps1`), incremental architecture synchronization (`get-arch-diff.ps1`), and bilingual i18n audits (`audit-i18n.ps1`).
4. **ReleaseManager** (`ask-release-manager`, `Tier 4 | Fast Deterministic`):
   Release automation, DevOps, and security: calculates SemVer bumps (`calculate-semver.ps1`), generates release notes and `CHANGELOG.md` (`generate-changelog.ps1`), audits GitHub Actions workflows and Dockerfiles (`lint-ci-workflows.ps1`), runs dependency CVE and secret security audits (`run-security-audit.ps1`, `scan-guardrails.ps1`), and creates clean Git release tags on `main`.

## Four-Step Codebase Analysis Protocol

Whenever an agent explores, analyzes, or debugs a codebase, it must strictly proceed in four steps:

1. **Check Current Modular Architecture Baseline**: Check `ARCHITECTURE.md`, module specifications (`docs/architecture/modules/*.md`), and `.arch-sync.json`.
2. **Synchronize Architecture if Needed**: If documentation is missing or outdated compared to recent commits, run `ContractSpecialist` (`ask-contract-specialist` via `get-arch-diff.ps1` / `get-arch-diff.sh`) to synchronize affected module documents.
3. **Deduce State from Modular Documentation**: Derive system structure, contracts, dependencies, and state flows directly from the relevant modular architecture specification (`docs/architecture/modules/<module>.md`).
4. **Targeted Code Inspection Only for Critical Details**: Read concrete source code files strictly when specific low-level implementation details (e.g. algorithmic nuance, interop declarations, precise event binding lines) are indispensable.

> [!IMPORTANT]
> **Modular Architecture Depth & Context Isolation**:
> Architecture documents must be sufficiently detailed (interfaces, records, state transitions, threading guarantees) so that broad, whole-repository code scans are prevented. At the same time, maintaining separate files per module (`docs/architecture/modules/<module>.md`) ensures that agents only load the single relevant module into context, preventing the agent's context window from continuously filling up.

## Living Modular Documentation & Concept Lifecycle

Specifications grow incrementally as isolated files, preventing full-file diffs and context exhaustion. Both **Google Antigravity** and **GitHub Copilot** support two identical lifecycle tracks:

- **Plural Standard (`docs/concepts/`)**: Exploratory RFCs start in `docs/concepts/drafts/` (`inspect-feature-specs.ps1 -NewConcept`) and archive to `docs/concepts/archive/` (`inspect-feature-specs.ps1 -ArchiveConcept`). Tooling provides transparent backward compatibility for singular `docs/concept/`.
- **Track A (`concept > req > impl`)**: Standard and complex features distill refined concepts into formal specifications (`docs/features/FEAT-*.md` with Given-When-Then acceptance criteria). Implementation agents (`Developer`, `Tester`, `Verifikation`) read strictly the single target feature spec and never read concept drafts.
- **Track B (`concept > impl`)**: Fast-track exploratory prototypes or internal developer tools archive the approved concept draft immediately and implement directly via Developer Inner-Loop TDD, bypassing formal `FEAT-*.md` overhead while strictly maintaining Clean Code, Clean Architecture, unit test authoring, and compiler gates.

For practical prompt patterns across both tracks, see [COMMON_WORKFLOWS.md](COMMON_WORKFLOWS.md).

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
| `detect-models.ps1/.sh` | `ask-control` | Probes active environment, model catalog, and cost-guardrail thresholds with 24-hour persistent local disk caching. |
| `detect-tech-stack.ps1/.sh` | `ask-control` | Auto-detects programming languages, build systems, package managers, and test runners. |
| `run-fast-gate.ps1/.sh` | `ask-control` | Stage 1 Zero-Token compiler, linter, and quiet test suite fast gate. |
| `run-all-gates.ps1/.sh` | `ask-control` | Unified quality gates orchestrator running all static zero-token linters and Stage 1 fast gate. |
| `lint-clean-architecture.ps1/.sh` | `ask-control`, `ask-troubleshooter` | Evaluates declarative layer import boundaries ([`rules/clean-architecture.json`](rules/clean-architecture.json)) and code metric limits. |
| `scan-guardrails.ps1/.sh` | `ask-release-manager`, `ask-control` | Pre-commit scanner enforcing Safe Rust (0 `unsafe`), secret leak prevention, and terminal hygiene. |
| `lint-requirements.ps1/.sh` | `ask-contract-specialist` | Validates requirement formatting, duplicate detection, and allocates scoped IDs (`REQ-<SCOPE>-XXX`). |
| `calculate-semver.ps1/.sh` | `ask-release-manager` | Parses Conventional Commits to deterministically calculate next SemVer tag (`major`, `minor`, `patch`). |
| `generate-changelog.ps1/.sh` | `ask-release-manager` | Generates Keep-a-Changelog compatible release notes from git commits since last tag. |
| `audit-i18n.ps1/.sh` | `ask-contract-specialist` | Verifies key parity between German (`de`) and English (`en`) localization resource files. |
| `generate-pr-summary.ps1/.sh` | `ask-control` | Generates structured PR descriptions, commit listings, and test evidence summaries. |
| `diagnose-git-state.ps1/.sh` | `ask-git-troubleshooter` | Analyzes branch state, dirty working tree, diverged commits, and merge/rebase status. |
| `create-safety-backup.ps1/.sh` | `ask-git-troubleshooter` | Creates zero-data-loss backup branches and stashes prior to destructive Git operations. |
| `run-security-audit.ps1/.sh` | `ask-release-manager` | Universal dependency CVE audit runner (`dotnet list package --vulnerable`, `cargo audit`, `npm audit`, `pip-audit`). |
| `check-test-coverage.ps1/.sh` | `ask-control` | Parses Cobertura XML, LCOV, and coverage JSON to assert coverage threshold compliance. |
| `collect-test-failures.ps1/.sh` | `ask-troubleshooter`, `ask-control` | Parses JUnit/TRX test reports and extracts compacted failure messages and stack traces. |
| `benchmark-startup.ps1/.sh` | `ask-troubleshooter` | Measures cold/warm CLI or application startup latency (min, avg, median, p95, max). |
| `lint-db-migrations.ps1/.sh` | `ask-contract-specialist` | Lints database migrations for versioning, `.up.sql`/`.down.sql` symmetry, and destructive DDL statements. |
| `lint-api-contracts.ps1/.sh` | `ask-contract-specialist` | Validates OpenAPI schema structure, internal `$ref` pointers, Protobuf tags, and GraphQL schemas. |
| `find-orphaned-assets.ps1/.sh` | `ask-troubleshooter`, `ask-contract-specialist` | Detects unreferenced media files and unindexed modular documentation files. |
| `lint-ci-workflows.ps1/.sh` | `ask-release-manager` | Lints GitHub Actions workflows for syntax, least-privilege `permissions:`, and `-NoProfile` hygiene. |
| `lint-docs.ps1/.sh` | `ask-contract-specialist` | Validates relative markdown links (ignoring fenced/inline code) and modular architecture parity. |
| `inspect-feature-specs.ps1/.sh` | `ask-contract-specialist`, `ask-control` | Living modular feature spec inspector, concept scaffolding (`-NewConcept`), and state checkpoint hash tracker. |
| `get-arch-diff.ps1/.sh` | `ask-contract-specialist` | Identifies modified host files since last sync commit, strictly excluding submodules. |
| `record-telemetry.ps1/.sh` | `ask-control` | Zero-overhead lifecycle event and duration recorder. |
| `show-telemetry.ps1/.sh` | `ask-control` | Formats local telemetry run history. |
| `run-evals.ps1/.sh` | `ask-control` | Runs synthetic evaluation cases ([`evals/eval-cases.json`](evals/eval-cases.json)) against governance and skill file invariants. |
| `setup-agent-skills.ps1/.sh` | Setup / Admin | Automates integration of agent-skills globally (user level) or into target projects (with optional `-InitDocs` scaffolding). |
| `test-skills.ps1/.sh` | CI / Quality Gate | Comprehensive test harness validating all skills, scripts, links, and line endings. |

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

| AI Assistant | Canonical Directory | User Level (Global Machine Scope) | Project Level (Project Scope) |
| :--- | :--- | :--- | :--- |
| **Google Antigravity (AGY / Gemini)** | **`_agents`** | `~/_agents/` linked into `~/.gemini/config/` (`skills`, `rules`) + global `~/.gemini/GEMINI.md` | Directory link or submodule in `_agents/` + project `AGENTS.md` |
| **GitHub Copilot (VS Code & CLI)** | **`.agents`** | `~/.agents/` + Zero-Reload inlined `~/.copilot/instructions/agent-skills.instructions.md` | Directory link or submodule in `.agents/` + `.github/copilot-instructions.md` |
| **Automated 1-Click Setup (Both)** | `_agents` & `.agents` | `pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -Global`<br>`./scripts/setup-agent-skills.sh --global` | `pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject <dir>`<br>`./scripts/setup-agent-skills.sh -p <dir>` |

---

### Quickstart: 1-Click Automated Setup Scripts

The repository includes dedicated automation scripts ([`scripts/setup-agent-skills.ps1`](scripts/setup-agent-skills.ps1) and [`scripts/setup-agent-skills.sh`](scripts/setup-agent-skills.sh)) enforcing `_agents` for Antigravity and `.agents` for Copilot across both scopes.

#### Option 1: Global User-Level Setup (All Projects)
Provisions `~/_agents` (linked into `~/.gemini/config/skills` and `~/.gemini/config/rules` for Antigravity) and `~/.agents` (with Zero-Reload inlined `~/.copilot/instructions/agent-skills.instructions.md` for GitHub Copilot CLI & VS Code).

- **Windows (PowerShell)**:
  ```powershell
  # Both AGY (~/_agents) and Copilot (~/.agents):
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -Global

  # Only AGY (~/_agents) or only Copilot (~/.agents):
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -Global -Client agy
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -Global -Client copilot
  ```
- **macOS / Linux (Bash)**:
  ```bash
  ./scripts/setup-agent-skills.sh --global
  # Or target a single client: --client agy | --client copilot
  ```

#### Option 2: Project-Level Setup (Specific Project)
Creates `_agents` (for Antigravity) and `.agents` + `.github/copilot-instructions.md` (for Copilot) in the target project.

- **Windows (PowerShell)**:
  ```powershell
  # Default (-Client all): creates both _agents (AGY) and .agents + .github/copilot-instructions.md (Copilot)
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\path\to\target-project"

  # Copilot only (.agents + .github/copilot-instructions.md):
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\path\to\target-project" -Client copilot

  # Antigravity only (_agents):
  pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\path\to\target-project" -Client agy
  ```
- **macOS / Linux (Bash)**:
  ```bash
  # Default (--client all): creates both _agents (AGY) and .agents + .github/copilot-instructions.md (Copilot)
  ./scripts/setup-agent-skills.sh -p /path/to/target-project

  # Copilot only (.agents) or Antigravity only (_agents):
  ./scripts/setup-agent-skills.sh -p /path/to/target-project -c copilot
  ./scripts/setup-agent-skills.sh -p /path/to/target-project -c agy
  ```

**Script Parameters**:
- `-TargetProject <dir>` / `-p, --project <dir>`: Path to the target project directory.
- `-Client <all|agy|copilot>` / `-c, --client <type>`: Configures `all` (default: `_agents` + `.agents`), `agy` (`_agents` only), or `copilot` (`.agents` only).
- `-Global` / `-g, --global`: Installs globally in user home (`~/_agents` for AGY, `~/.agents` for Copilot).
- `-FolderType <type>` / `-t, --folder-type <type>`: Explicit override (`_agents`, `.agents`, or `both`).
- `-InitDocs` / `--init-docs`: Auto-detects target project stack and scaffolds `ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/features/`, and `docs/concepts/drafts/`.
- `-SkipCopilot` / `--skip-copilot`: Skips Copilot setup (`.agents` and `.github/copilot-instructions.md`).
- `-Force` / `-f, --force`: Overwrites existing symlinks/junctions or files.

---

### Manual Setup: Google Antigravity (AGY / Gemini — `_agents`)

#### A. User Level (Global Machine Scope via `~/_agents`)
Enables all 5 capability packs, model tier mappings, and the `ask-control` orchestrator globally across all projects on your workstation.

1. **Link `~/_agents` and User Gemini Config**:
   - **Windows (PowerShell)**:
     ```powershell
     # Replace C:\path\to\agent-skills with your local clone path
     $repoTarget = "C:\path\to\agent-skills"
     $agyUserRoot = "$env:USERPROFILE\_agents"
     $geminiConfig = "$env:USERPROFILE\.gemini\config"

     New-Item -ItemType Junction -Path $agyUserRoot -Target $repoTarget -Force
     New-Item -ItemType Directory -Path $geminiConfig -Force | Out-Null
     New-Item -ItemType Junction -Path "$geminiConfig\skills" -Target "$agyUserRoot\skills" -Force
     New-Item -ItemType Junction -Path "$geminiConfig\rules" -Target "$agyUserRoot\rules" -Force
     ```
   - **macOS / Linux (Bash)**:
     ```bash
     ln -sfn /path/to/agent-skills ~/_agents
     mkdir -p ~/.gemini/config
     ln -sfn ~/_agents/skills ~/.gemini/config/skills
     ln -sfn ~/_agents/rules ~/.gemini/config/rules
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

### Manual Setup: GitHub Copilot (VS Code & CLI — `.agents`)

GitHub Copilot operates in **Sequential Persona Mode** (`Control` -> `Developer` -> `Verifikation` -> `CommitManager`) and integrates strictly via **`.agents`** at both user level (`~/.agents`) and project level (`./.agents`).

> [!TIP]
> **Copilot Efficiency & Zero-Reload Inlining**:
> Unlike multi-agent platforms (Antigravity/AGY), Copilot executes in a single persistent context window. Core lifecycle engineering (`Control`, contracts, Inner-Loop TDD, verification, atomic commits) is embedded directly into `.github/copilot-instructions.md` (and inlined into `~/.copilot/instructions/agent-skills.instructions.md` on user level) so zero tool calls are spent loading core rules, while the 4 consolidated specialist capability packs are loaded strictly on demand from `.agents/skills/` (or `~/.agents/skills/`).

#### A. User Level (Global Machine Scope via `~/.agents`)

1. **Link `~/.agents` & Generate Zero-Reload Instructions (`~/.copilot/instructions/agent-skills.instructions.md`)**:
   Link `~/.agents` to your `agent-skills` clone (`New-Item -ItemType Junction -Path "$HOME\.agents" -Target "C:\path\to\agent-skills"` or `ln -sfn /path/to/agent-skills ~/.agents`) and run `setup-agent-skills.ps1 -Global -Client copilot` to inline `.github/copilot-instructions.md` with YAML frontmatter `applyTo: "**/*"` referencing `~/.agents/skills/` and `~/.agents/scripts/`.

2. **VS Code Copilot Chat Setup**:
   Add the instruction file to your VS Code User `settings.json`:
   ```json
   "github.copilot.chat.codeGeneration.instructions": [
     {
       "file": "C:/Users/<Username>/.copilot/instructions/agent-skills.instructions.md"
     }
   ]
   ```

3. **GitHub Copilot CLI (`copilot`) Setup**:
   The GitHub Copilot CLI automatically discovers both instructions and personal skills without manual `copilot skill add` loops:
   - **Instructions**: Auto-discovered from `~/.copilot/instructions/*.instructions.md`
   - **Personal Skills**: Auto-discovered from `~/.agents/skills/`
   ```bash
   copilot instruction list
   copilot skill list
   ```

#### B. Project Level (Project Scope via `.agents`)

1. **Skills & Scripts Folder (`.agents/`)**:
   - **Directory Link (Local)**:
     - Windows: `New-Item -ItemType Junction -Path ".\.agents" -Target "C:\path\to\agent-skills"`
     - Linux/macOS: `ln -sfn /path/to/agent-skills ./.agents`
   - **Git Submodule (Team / CI)**:
     ```bash
     git submodule add --name agent-skills -b main https://github.com/histore/agent-skills.git .agents
     ```
2. **Project-Specific Copilot Instructions (`.github/copilot-instructions.md`)**:
   ```bash
   mkdir -p .github
   cp ./.agents/.github/copilot-instructions.md .github/copilot-instructions.md
   ```
   Both GitHub Copilot CLI and VS Code automatically load `.github/copilot-instructions.md` and discover skills in `.agents/skills/`.

---

### Dual Compatibility: Antigravity (`_agents`) & Copilot (`.agents`)

Antigravity uses `_agents/`, whereas GitHub Copilot uses `.agents/`. Running the default setup command configures both side-by-side cleanly:

```powershell
pwsh -NoProfile -File ./scripts/setup-agent-skills.ps1 -TargetProject "C:\path\to\target-project"
```

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
