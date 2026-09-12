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
11. **DocumentationSpecialist** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Authors XML doc comments (`///`), keeps architecture docs synchronized, and maintains user help guides in English.
12. **ReleaseManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages deployment pipelines, packaging, Native AOT readiness, and application manifests.
13. **Tester** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements comprehensive automated tests (`xUnit`, AAA pattern, 0 failures).
14. **Verifikation** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Quality gate auditing acceptance criteria, 100% requirements coverage, test pass rate, and architectural compliance.
15. **CommitManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Generates conventional commit messages, stages changes, commits, and pushes strictly on-demand after interactive user confirmation.
16. **PRManager** (`Tier 4 | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages the Pull Request lifecycle (`gh pr create`, CI checks audit, squash-merge) strictly on-demand after approval.
17. **Tiebreaker** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Monitors active operations, detects loops/deadlocks/thrashing, and enforces remediation.
18. **TerminalEngineSpecialist** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Deeply analyzes and optimizes Win32 ConPTY handles, ANSI/VT100 streams, and zero-allocation UTF-8 decoding.
19. **CodeExplainer** (`Tier 1 | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's OS language, inserting English didactic comments directly into code files.
20. **ArchitectureSync** (`Tier 3 | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Incrementally audits and synchronizes modular architecture documentation (`docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts to eliminate context bloat.

## Integration in Projects

### As a Git Submodule (Recommended)

To integrate these skills into any workspace as `.agents`:

```bash
git submodule add --name agent-skills -b main https://github.com/histore/agent-skills.git .agents
```

When cloning a repository that uses this submodule:

```bash
git clone --recurse-submodules <repo-url>
# or update existing clone:
git submodule update --init --recursive
```

### Updating to Latest Skills

```bash
git submodule update --remote .agents
```
