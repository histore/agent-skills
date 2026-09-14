# Subagent Orchestration, Clean Architecture & Context Isolation Guidelines

## Core Principles
1. **Isolated Context**: Each subagent role operates within an isolated task context to prevent context bloat and distraction.
2. **Minimal Context Transfer**: Only essential information (inputs, specific requirements, direct dependencies) is passed between roles.
3. **Universal Model Tiering & Dual Execution Strategy**:
   - Tier mappings and platform preferences are declaratively defined in [`rules/model-tiers.json`](file:///rules/model-tiers.json).
   - **Multi-Agent Mode (Antigravity / AGY)**: Leverages `invoke_subagent` with explicit model tier dispatch (`pro` for Tier 1, `flash` for Tier 2/3, `flash_lite` for Tier 4).
   - **Sequential Persona Mode (GitHub Copilot / Cursor / Single-Model)**: In clients without subagent APIs, the agent adopts role personas sequentially, modulating cognitive depth via prompt-based thinking budgets (High/Extended for Tier 1, Balanced for Tier 2/3, Minimal for Tier 4).
   - **Runtime Probe**: Zero-token detection scripts (`scripts/detect-models.ps1` / `scripts/detect-models.sh`) determine the active platform and model availability dynamically.
4. **Clean Architecture & Clean Code Enforcement**:
   - **Clean Architecture**: Dependency rule (dependencies point inward), clear layer boundaries (`Models`, `Services`, `ViewModels`, `Views`), independent of external UI/OS details.
   - **Clean Code**: SOLID, DRY, KISS, YAGNI, Boy Scout Rule, small focused classes/methods, descriptive naming, English comments.
   - **Modern Best Practices**: C# 13 / .NET 10 idioms (file-scoped namespaces, nullability `#nullable enable`, records, collection expressions, pattern matching, async/await with `ConfigureAwait(false)` in service layers, safe native handle disposal), Avalonia UI 11.2 (compiled bindings `x:DataType`, CommunityToolkit.Mvvm source generators, decoupled styles).
5. **Systematic Root Cause Analysis**:
   - The `Troubleshooter` diagnoses bugs, analyzes event hierarchies and call stacks, and isolates root causes before code changes occur.
6. **Full Internationalization (i18n & l10n)**:
   - Dedicated `LocalizationSpecialist` role audits and enforces 0% hardcoded UI strings, managing bilingual German (`de`) and English (`en`) resource dictionaries.
7. **Performance, Security & Code Health**:
   - `PerformanceOptimizer` enforces zero-allocation buffer pooling (`ArrayPool<byte>`) and memory leak prevention.
   - `SecurityAuditor` audits command safety, path traversal prevention, and secure JSON deserialization.
   - `RefactoringSpecialist` continuously eliminates technical debt and code smells.
   - `DocumentationSpecialist` maintains XML doc comments (`///`), user manuals, and in-app help guides.
   - `ArchitectureSync` incrementally synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/`).
   - `ReleaseManager` manages packaging, self-contained single-file publishing, SemVer tags, and manifests.
8. **Strict Requirements Governance**:
   - **Check Against Existing Requirements**: Every new requirement must be validated against `REQUIREMENTS.md`.
   - **User Decision on Conflicts/Duplicates**: Contradictions or duplicates must be escalated to the user for explicit decision.
   - **Immutability of Existing Requirements**: Existing requirements may only be modified with explicit user instruction.
   - **Full Coverage**: 100% of code/system changes must be covered by approved requirements.
9. **Maximum User Usability & Aesthetic Excellence**: The dedicated `UIDesigner` role ensures every UI component provides effortless keyboard navigation, intuitive ergonomics, and rich visual aesthetics.
10. **Branch & PR Process Model with Developer Testing & Review Gate**: All development must occur on dedicated branches (`feat/`, `fix/`, `refactor/`, `chore/`, `docs/`). Prior to Pull Request creation, the developer is provided with the opportunity to review the code, test application functionality interactively/manually, and request adjustments or fixes. Merging into `main` occurs solely via Pull Requests using Squash-and-Merge after explicit user sign-off and passing CI per [CONTRIBUTING.md](CONTRIBUTING.md).
11. **Four-Step Codebase Analysis Protocol & Modular Architecture Depth**:
    Whenever a codebase is analyzed, explored, or investigated, agents must strictly follow a 4-step workflow:
    1. **Check Current Modular Architecture Baseline**: Check `ARCHITECTURE.md`, module specifications in `docs/architecture/modules/*.md`, and `.arch-sync.json`.
    2. **Synchronize Architecture if Needed**: If the documentation is missing, outdated, or desynchronized from recent git commits, invoke `ArchitectureSync` (`get-arch-diff.ps1` / `get-arch-diff.sh`) to synchronize affected module specifications.
    3. **Deduce State from Modular Architecture Documentation**: Derive component responsibilities, public contracts, data flows, and runtime state directly from the relevant modular architecture specification (`docs/architecture/modules/<module>.md`).
    4. **Targeted Code Inspection Only for Critical Details**: Read concrete source code files strictly when specific low-level implementation details (e.g. algorithmic nuance, Win32 P/Invoke declarations, exact event routing lines) are indispensable.
    **Context Guardrail**: Modular architecture documents must be sufficiently detailed (contracts, interfaces, state flows, threading guarantees) to obviate whole-codebase scans, yet partitioned into discrete files per module so that agents load only the required module into context without continuous context bloat.

---

## Role Summary & Profiles

1. **Control**: Central workflow orchestrator, model tier/reasoning dispatcher, minimal-context packager, and coordinator of the Developer Testing & Review gate before PR creation.
2. **RequirementEngineer** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Given-When-Then criteria, conflict detection, requirement integrity.
3. **Troubleshooter** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): RCA, stack trace analysis, event bubbling & race condition diagnostics.
4. **UIDesigner** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Usability, keyboard workflows, visual aesthetics (Catppuccin Mocha), XAML styles.
5. **LocalizationSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): i18n audits, 0% hardcoded strings, bilingual dictionaries (`de`/`en`).
6. **Architekt** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Clean Architecture, SOLID interfaces, layer boundaries, dependency inversion.
7. **Developer** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Clean Code implementation, C# 13, .NET 10, Avalonia 11.2, English comments, iterative refinements from developer review.
8. **RefactoringSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Code smell detection, technical debt remediation, Boy Scout rule.
9. **PerformanceOptimizer** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): Buffer pooling (`ArrayPool`), memory leak auditing, ConPTY stream throughput.
10. **SecurityAuditor** (`Tier 2 - Advanced Analytical | High Reasoning` - Ref: `Gemini 3.8 Flash`): PowerShell command safety, secret leak prevention, dependency CVE audits (NuGetAudit), path traversal prevention, secure deserialization.
11. **DocumentationSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Authors XML doc comments (`///`), user manuals, and in-app help guides in English.
12. **ReleaseManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages deployment pipelines, single-file self-contained packaging, Native AOT readiness, and application manifests.
13. **Tester** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements comprehensive automated tests (`<Project>.Tests` / test suite) and executes `dotnet test` (AAA pattern, 0 failures).
14. **Verifikation** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Quality gate auditing acceptance criteria, 100% requirements coverage, test pass rate, Clean Code, i18n, performance, security, and architectural compliance prior to developer testing.
15. **CommitManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Generates conventional commit messages from diffs, stages changes, commits, and pushes to remote branches strictly on-demand after interactive user confirmation.
16. **PRManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages the Pull Request lifecycle (template drafting, `gh pr create`, efficient CI checks audit via `gh pr checks --watch` with ~75-80s deadtime, squash-merge, and branch cleanup) strictly on-demand after developer review approval.
17. **Tiebreaker** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Monitors active operations, detects loops/deadlocks/thrashing, and enforces remediation via strategy pivots, model upgrades, context purges, or user escalation.
18. **TerminalEngineSpecialist** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Deeply analyzes and optimizes Win32 ConPTY handles, ANSI/VT100 streams, OSC 7/9/133 integration, TrueColor palettes, and zero-allocation UTF-8 decoding.
19. **CodeExplainer** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's operating system language, inserting clear English didactic comments directly into code files.
20. **ArchitectureSync** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Incrementally audits and synchronizes system architecture (`ARCHITECTURE.md` and `docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts to avoid context bloat and unnecessary scans.

---

## Client Directory Compatibility (`.agents` vs. `_agents`)
- **Gemini / Antigravity**: Seamlessly supports and monitors both `_agents` and `.agents` customization roots.
- **GitHub Copilot & Other Clients**: Specifically expect `.agents/` as the standard discovery root. When sharing skills across multiple AI clients or targeting Copilot, use `.agents` (or create a symbolic link / submodule pointing to `.agents`).
