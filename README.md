# Agent Skills & Subagent Roles (`agent-skills`)

A modular, reusable repository of specialized AI subagent roles, skills, and governance rules designed for modern software development with Antigravity / Gemini agents.

## Structure

```text
agent-skills/
├── AGENTS.md               # Master guidelines and subagent governance rules
├── rules/
│   └── subagents.md        # Architectural rules and context-isolation protocol
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

1. **Control**: Orchestrates workflow pipelines, breaks down tasks, assigns model capability tiers / reasoning levels, provides minimal context packages.
2. **RequirementEngineer** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Translates user requirements into Given-When-Then acceptance criteria, checking for duplicates/conflicts.
3. **Troubleshooter** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Diagnoses bugs, analyzes call stacks and UI event hierarchies, identifies root causes, and specifies test-driven remediation plans.
4. **UIDesigner** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Designs intuitive, aesthetically outstanding, and accessible user interfaces and interaction flows.
5. **LocalizationSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Audits code and XAML for i18n compliance, extracts hardcoded strings, and maintains bilingual resources (`de`/`en`).
6. **Architekt** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Defines contracts, interfaces, dependency management, and layer boundaries following Clean Architecture & MVVM.
7. **Developer** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements clean, maintainable code adhering to architectural blueprints, UI designs, requirements, and reviews.
8. **RefactoringSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Audits code smells and technical debt, designing safe, test-backed refactorings.
9. **PerformanceOptimizer** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Identifies allocation hotspots, memory leaks, and streaming bottlenecks, optimizing throughput.
10. **SecurityAuditor** (`Tier 2 | High Reasoning` - Ref: `Gemini 3.8 Flash`): Audits process execution safety, secret leaks, dependency CVEs, command injection risks, and safe path handling.
11. **DocumentationSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Authors XML doc comments (`///`), user manuals, and in-app help guides in English.
12. **ReleaseManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages deployment pipelines, packaging, Native AOT readiness, and application manifests.
13. **Tester** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements comprehensive automated tests (`xUnit`, AAA pattern, 0 failures).
14. **Verifikation** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Quality gate auditing acceptance criteria, 100% requirements coverage, test pass rate, and architectural compliance.
15. **CommitManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Generates conventional commit messages, stages changes, commits, and pushes strictly on-demand after interactive user confirmation.
16. **PRManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages the Pull Request lifecycle (`gh pr create`, CI checks audit, squash-merge) strictly on-demand after approval.
17. **Tiebreaker** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Monitors active operations, detects loops/deadlocks/thrashing, and enforces remediation.
18. **TerminalEngineSpecialist** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Deeply analyzes and optimizes Win32 ConPTY handles, ANSI/VT100 streams, and zero-allocation UTF-8 decoding.
19. **CodeExplainer** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's OS language, inserting English didactic comments directly into code files.
20. **ArchitectureSync** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Incrementally audits and synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts to eliminate context bloat.

## Four-Step Codebase Analysis Protocol

Whenever an agent explores, analyzes, or debugs a codebase, it must strictly proceed in four steps:

1. **Check Current Modular Architecture Baseline**: Check `ARCHITECTURE.md`, module specifications (`docs/architecture/modules/*.md`), and `.arch-sync.json`.
2. **Synchronize Architecture if Needed**: If documentation is missing or outdated compared to recent commits, run `ArchitectureSync` (`get-arch-diff.ps1` / `get-arch-diff.sh`) to synchronize affected module documents.
3. **Deduce State from Modular Documentation**: Derive system structure, contracts, dependencies, and state flows directly from the relevant modular architecture specification (`docs/architecture/modules/<module>.md`).
4. **Targeted Code Inspection Only for Critical Details**: Read concrete source code files strictly when specific low-level implementation details (e.g. exact logic, native P/Invoke declarations, precise event binding lines) are indispensable.

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
