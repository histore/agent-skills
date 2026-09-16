# Agent Skills & Subagent Roles (`agent-skills`)

A modular, reusable repository of specialized AI subagent roles, skills, and governance rules designed for modern software development with Antigravity / Gemini agents and cross-platform AI assistants.

All skills and rules are designed to be general and reusable across diverse software projects. Programming languages, frameworks, libraries, and toolchains are never hardcoded; agents dynamically discover and adapt to the target project's conventions, manifests, and architecture.

## Structure

```text
agent-skills/
├── AGENTS.md               # Master guidelines and subagent governance rules
├── rules/
│   ├── model-tiers.json    # Universal model tier mapping and thinking budgets
│   └── subagents.md        # Architectural rules and context-isolation protocol
├── scripts/                # Zero-token runtime capability detection scripts
└── skills/                 # 20 specialized subagent skills
    ├── la-architect/
    ├── la-architecture-sync/
    ├── la-code-explainer/
    ├── la-commit-manager/
    ├── la-control/
    ├── la-developer/
    ├── la-documentation-specialist/
    ├── la-localization-specialist/
    ├── la-performance-optimizer/
    ├── la-pr-manager/
    ├── la-refactoring-specialist/
    ├── la-release-manager/
    ├── la-requirement-engineer/
    ├── la-security-auditor/
    ├── la-terminal-engine-specialist/
    ├── la-tester/
    ├── la-tiebreaker/
    ├── la-troubleshooter/
    ├── la-ui-designer/
    └── la-verification/
```

## Available Subagent Roles

### Core Lifecycle Roles (Standard Workflow)
1. **Control**: Central workflow orchestrator, model tier/reasoning dispatcher, domain specialist coordinator, and manager of the Developer Testing & Review gate.
2. **RequirementEngineer** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Translates user requirements into Given-When-Then acceptance criteria, checking for duplicates/conflicts.
3. **Architekt** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Defines contracts, interfaces, dependency management, and layer boundaries following Clean Architecture.
4. **Developer** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements clean, maintainable code adhering to architectural blueprints, requirements, and reviews, adapting dynamically to the project's language and conventions.
5. **Tester** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements comprehensive automated tests (unit and integration tests) using the project's native test runner (AAA pattern, 0 failures).
6. **Verifikation** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Quality gate auditing acceptance criteria, 100% requirements coverage, test pass rate, Clean Code, and architectural compliance.
7. **CommitManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Generates conventional commit messages, stages changes, commits, and pushes strictly on-demand after interactive user confirmation.
8. **PRManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages the Pull Request lifecycle (`gh pr create`, CI checks audit with delayed polling, squash-merge) strictly on-demand after approval.

### General Support Roles (Lifecycle Specialists)
9. **Troubleshooter** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Diagnoses bugs, analyzes call stacks and event hierarchies, identifies root causes, and specifies test-driven remediation plans.
10. **RefactoringSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Audits code smells and technical debt, designing safe, test-backed refactorings.
11. **DocumentationSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Authors API doc comments (project standard), user manuals, and in-app help guides in English.
12. **ReleaseManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages deployment pipelines, packaging, SemVer tag calculation, and application manifests.
13. **Tiebreaker** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Monitors active operations, detects loops/deadlocks/thrashing, and enforces remediation.
14. **CodeExplainer** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's OS language, inserting didactic comments directly into code files (in English by default, or in a user-specified language).
15. **ArchitectureSync** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Incrementally audits and synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts to eliminate context bloat.

### Domain Specialists (On-Demand / Consulted by Skills)
Domain specialists are **not** part of the default linear workflow. They are engaged conditionally by `Control` when appropriate for the task, or consulted directly by other skills (Developer, Architekt, Troubleshooter) to resolve domain-specific details:
16. **UIDesigner** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): UI/UX ergonomics, interaction flows, layout hierarchy, and design tokens for the project's UI environment.
17. **LocalizationSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): i18n audits, 0% hardcoded strings, and bilingual dictionaries (`de`/`en`) in the project's localization format.
18. **TerminalEngineSpecialist** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Terminal subsystems, pseudo-terminals (PTY/ConPTY), ANSI/VT escape sequences, OSC integration, streaming, and character encoding.
19. **PerformanceOptimizer** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Low-level profiling, allocation reduction, memory leak prevention, and throughput optimization.
20. **SecurityAuditor** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Command execution safety, secret leak prevention, dependency CVE audits via ecosystem tools, path traversal prevention, and secure serialization.

## Four-Step Codebase Analysis Protocol

Whenever an agent explores, analyzes, or debugs a codebase, it must strictly proceed in four steps:

1. **Check Current Modular Architecture Baseline**: Check `ARCHITECTURE.md`, module specifications (`docs/architecture/modules/*.md`), and `.arch-sync.json`.
2. **Synchronize Architecture if Needed**: If documentation is missing or outdated compared to recent commits, run `ArchitectureSync` (`get-arch-diff.ps1` / `get-arch-diff.sh`) to synchronize affected module documents.
3. **Deduce State from Modular Documentation**: Derive system structure, contracts, dependencies, and state flows directly from the relevant modular architecture specification (`docs/architecture/modules/<module>.md`).
4. **Targeted Code Inspection Only for Critical Details**: Read concrete source code files strictly when specific low-level implementation details (e.g. algorithmic nuance, interop declarations, precise event binding lines) are indispensable.

> [!IMPORTANT]
> **Modular Architecture Depth & Context Isolation**:
> Architecture documents must be sufficiently detailed (interfaces, records, state transitions, threading guarantees) so that broad, whole-repository code scans are prevented. At the same time, maintaining separate files per module (`docs/architecture/modules/<module>.md`) ensures that agents only load the single relevant module into context, preventing the agent's context window from continuously filling up.

## Universal Model Tiering & Dual Execution Strategy

This repository supports cross-platform execution across **Google Antigravity**, **GitHub Copilot**, **Cursor**, and standalone LLM environments. Detailed tier mappings and platform preferences are specified in [`rules/model-tiers.json`](file:///rules/model-tiers.json).

### Execution Modes
1. **Multi-Agent Mode (Antigravity / AGY)**:
   - Dispatches isolated, parallel subagents via the platform API (`invoke_subagent`).
   - Dynamically allocates model classes: `pro` (Tier 1), `flash` (Tier 2/3), `flash_lite` (Tier 4).
2. **Sequential Persona Mode (GitHub Copilot / Cursor / Single-Model)**:
   - For clients lacking subagent-forking APIs, a single agent executes role phases sequentially (Architekt -> Developer -> Tester).
   - Modulates cognitive depth semantically via prompt-based thinking budgets (High/Extended for Tier 1, Balanced for Tier 2/3, Minimal for Tier 4).

### Zero-Token Runtime Capability Detection
To determine the active environment and available models at zero token cost:

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File ./scripts/detect-models.ps1
```
```bash
# macOS / Linux
bash ./scripts/detect-models.sh
```

## Integration in Projects

### Client Directory Compatibility (`.agents` vs. `_agents`)

Different AI coding assistants discover skill directories differently:

- **Gemini / Google Antigravity**: Works seamlessly with both `_agents` and `.agents` customization roots.
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
