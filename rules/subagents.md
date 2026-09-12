# Subagent Orchestration, Clean Architecture & Context Isolation Guidelines

## Core Principles
1. **Isolated Context**: Each subagent role operates within an isolated task context to prevent context bloat and distraction.
2. **Minimal Context Transfer**: Only essential information (inputs, specific requirements, direct dependencies) is passed between roles.
3. **Dynamic Model & Reasoning Assignment**: The `Control` agent dynamically assigns capability tiers (Tier 1 to Tier 4) and reasoning levels (Thinking Budget: High/Extended, Medium, Low/Fast) matched to the active LLM environment, referencing the modern Gemini 3.8 family (Pro / Flash) as the primary baseline.
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
   - `DocumentationSpecialist` maintains XML doc comments (`///`) and architecture documents.
   - `ReleaseManager` manages packaging, self-contained single-file publishing, SemVer tags, and manifests.
8. **Strict Requirements Governance**:
   - **Check Against Existing Requirements**: Every new requirement must be validated against `REQUIREMENTS.md`.
   - **User Decision on Conflicts/Duplicates**: Contradictions or duplicates must be escalated to the user for explicit decision.
   - **Immutability of Existing Requirements**: Existing requirements may only be modified with explicit user instruction.
   - **Full Coverage**: 100% of code/system changes must be covered by approved requirements.
9. **Maximum User Usability & Aesthetic Excellence**: The dedicated `UIDesigner` role ensures every UI component provides effortless keyboard navigation, intuitive ergonomics, and rich visual aesthetics.
10. **Branch & PR Process Model with Developer Testing & Review Gate**: All development must occur on dedicated branches (`feat/`, `fix/`, `refactor/`, `chore/`, `docs/`). Prior to Pull Request creation, the developer is provided with the opportunity to review the code, test application functionality interactively/manually, and request adjustments or fixes. Merging into `main` occurs solely via Pull Requests using Squash-and-Merge after explicit user sign-off and passing CI per [CONTRIBUTING.md](CONTRIBUTING.md).

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
11. **DocumentationSpecialist** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Authors XML doc comments (`///`), keeps `ARCHITECTURE.md` synchronized, and maintains user help guides in English.
12. **ReleaseManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages deployment pipelines, single-file self-contained packaging, Native AOT readiness, and application manifests.
13. **Tester** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Implements comprehensive automated tests (`<Project>.Tests` / test suite) and executes `dotnet test` (AAA pattern, 0 failures).
14. **Verifikation** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Quality gate auditing acceptance criteria, 100% requirements coverage, test pass rate, Clean Code, i18n, performance, security, and architectural compliance prior to developer testing.
15. **CommitManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Generates conventional commit messages from diffs, stages changes, commits, and pushes to remote branches strictly on-demand after interactive user confirmation.
16. **PRManager** (`Tier 4 - Fast & Deterministic | Low/Fast Reasoning` - Ref: `Gemini 3.8 Flash`): Manages the Pull Request lifecycle (template drafting, `gh pr create`, efficient CI checks audit via `gh pr checks --watch` with ~75-80s deadtime, squash-merge, and branch cleanup) strictly on-demand after developer review approval.
17. **Tiebreaker** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Monitors active operations, detects loops/deadlocks/thrashing, and enforces remediation via strategy pivots, model upgrades, context purges, or user escalation.
18. **TerminalEngineSpecialist** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Deeply analyzes and optimizes Win32 ConPTY handles, ANSI/VT100 streams, OSC 7/9/133 integration, TrueColor palettes, and zero-allocation UTF-8 decoding.
19. **CodeExplainer** (`Tier 1 - Deep Reasoning | High/Extended Thinking` - Ref: `Gemini 3.8 Pro`): Analyzes and explains source code, control/data flows, and architectural decisions in the user's operating system language, inserting clear English didactic comments directly into code files.
20. **ArchitectureSync** (`Tier 3 - Balanced Implementation | Medium Reasoning` - Ref: `Gemini 3.8 Flash`): Incrementally audits and synchronizes modular architecture documentation (`docs/architecture/modules/*.md`) from git deltas, using zero-token pre-filtering scripts to avoid context bloat and unnecessary scans.
