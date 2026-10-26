# Workspace Agent Guidelines: Subagent Roles & Context Isolation

## Overview
Workspace governance combining adaptive execution profiles with zero-token deterministic scripts:
1. **Ensure Maximum Quality**: Clean Code, Clean Architecture, Root Cause Analysis, Inner-Loop TDD, two-stage quality gates, data-loss guardrails.
2. **Minimize Cost**: Compound Phased Execution (75–90% KV-cache reuse), Adaptive T-Shirt Sizing (70–80% fast-track savings), Calibrated Thinking Budgets, Zero-Token Scripts, Anti-Ceremony Guardrails.

Toolchains and languages are dynamically detected from project manifests (`Cargo.toml`, `Directory.Build.props`, `package.json`, `pyproject.toml`, `go.mod`, `ARCHITECTURE.md`).

## Core Governance & Architecture Rules
1. **Clean Architecture Principles**: Strict layer separation (Domain -> Application Contracts -> Adapters/Presenters/ViewModels -> Infrastructure/UI/Drivers). Core domain logic remains framework- and DB-agnostic.
2. **Clean Code & Best Practices**: SOLID, DRY, KISS, YAGNI, Boy Scout Rule, English comments. In Rust codebases, `unsafe` blocks must not be used.
   - **Relative Paths Invariant**: All documentation (`*.md`), specifications, and feature links MUST strictly use **relative paths** (e.g. `../ARCHITECTURE.md`, `docs/features/FEAT-001.md`). Absolute local paths (`C:\...`, `/home/...`, `file:///...`) are strictly prohibited in committed files.
3. **Dynamic Tech Stack Specialization**: Discover language, framework, and test commands dynamically without hardcoded assumptions.
4. **Core Lifecycle vs. On-Demand Specialist Capability Packs**:
   - **Unified Core Lifecycle Engineer**: `Control` (`ask-control`). In both multi-agent (Antigravity) and single-thread (Copilot Sequential Persona Mode), `Control` executes planning, contracts, Inner-Loop TDD, two-stage verification, and atomic Git lifecycle actions directly.
   - **On-Demand Specialist Capability Packs**: Four high-value specialist packs engage selectively on-demand:
     - `Troubleshooter` (`ask-troubleshooter`): Systematic Root Cause Analysis, reproduction tests, adversarial code review, Fowler refactoring, and performance profiling.
     - `GitTroubleshooter` (`ask-git-troubleshooter`): Safety-first Git recovery, 3-way merge/rebase conflict resolution, reflog recovery, and safety backups.
     - `ContractSpecialist` (`ask-contract-specialist`): Living feature specifications, concept tracks, requirements governance, API contracts, DB migrations, architecture sync, and i18n.
     - `ReleaseManager` (`ask-release-manager`): Release automation, SemVer calculation, changelog generation, CI/CD workflows, security CVE audits, and Git release tags.
5. **Automated Testing, Quality & Inner-Loop TDD**:
   - **Profile 0 (Direct Response - Informational / Read-Only / Trivial)**: Answer directly. **Zero Git operations and zero test execution.**
   - **Profile A (Fast-Track - Bugs, Tweaks, Small Features)**: Direct developer loop (`Developer` -> `Verifikation` -> `CommitManager`). Tests run only when executable code was modified; omitted for markdown, docs, comments, or non-testable files.
   - **Profile B (Standard Features)**: Architecture Contract -> `Developer` Inner-Loop TDD -> `Verifikation` gate.
   - **Profile C (Complex / Architectural)**: Modular Contracts -> Skeletons/Integration Tests (`Tester`) -> Implementation (`Developer`) -> Verification.
   - **Purpose-Driven & Targeted Test Execution**: Tests run ONLY when executable code was modified and tests apply. Target only affected test files/classes (`--filter`, specific paths); full suite runs during final verification.
   - **Two-Stage Quality Gate (Shift-Left Validation)**:
     - **Stage 1 (Deterministic Fast-Gate - Zero Tokens)**: Native build, linter, quiet tests, Clean Architecture check, and safe-Rust guardrails via `pwsh -NoProfile -File ./scripts/run-fast-gate.ps1` (`run-fast-gate.sh`). Immediate return on failure.
     - **Stage 2 (Concise Traceability Gate)**: `Verifikation` audits acceptance criteria, Clean Architecture, and correctness.
   - **Test Integrity & Circuit Breaker**: Adjust test fixtures to match contracts, but never weaken or delete assertions. The `Developer` test-fix loop is capped at a maximum of 3 iterations before escalating. All tests follow AAA and require 100% pass rate (0 failures).
   - **Synthetic Evaluation Suite (Eval-Harness)**: Asserted via `evals/eval-cases.json` and `scripts/run-evals.ps1` (`run-evals.sh`).
6. **Internationalization & Localization (i18n / l10n)**: 0% hardcoded user strings; bilingual resources in German (`de`) and English (`en`).
7. **Requirements Governance & Modular Architecture**:
   - Small projects (< ~30–50 items) use single `REQUIREMENTS.md`. Scaled systems partition into `docs/requirements/modules/<module>.md` with `REQUIREMENTS.md` as Hub/Registry.
   - **Living Modular Documentation**: Grow specs as isolated files (`docs/features/FEAT-<SCOPE>-XXX-<slug>.md`). Updates touch only the single feature file and append a line to `docs/ROADMAP.md` (zero-full-diff guarantee).
   - **Concept Workflows & Isolation**: Draft in `docs/concepts/drafts/` (`inspect-feature-specs.ps1 -NewConcept`), review/refine with user. Plural standard is `docs/concepts/` (matching `docs/features/`), with tooling compatibility for singular `docs/concept/`. Supports two identical tracks across all clients:
     1. **`concept > req > impl` (Standard / Complex Features)**: Distill draft into `docs/features/FEAT-*.md` (escalating contradictions to user) and archive to `docs/concepts/archive/` (`inspect-feature-specs.ps1 -ArchiveConcept`). Downstream implementation roles never read concept files.
     2. **`concept > impl` (Fast-Track / Prototypes)**: Approved draft serves directly as working contract, is archived to `docs/concepts/archive/`, and implemented directly via Developer Inner-Loop TDD.
   - **Lazy Loading Protocol**: Query features via `scripts/inspect-feature-specs.ps1` or read only the Hub index to load strictly the single affected file. Scoped IDs: `REQ-<SCOPE>-XXX` (`PROPOSED`, `APPROVED`, `IN_PROGRESS`, `IMPLEMENTED`, `VERIFIED`, `DEPRECATED`).
8. **User Decision on Conflicts**: Escalate discrepancies, distillation contradictions, or requirement conflicts directly to user.
9. **Immutability of Existing Requirements**: Modified only with explicit user instruction.
10. **100% Coverage for Functional Features**: Enterprise features require approved requirements; minor tweaks do not require requirement overhead.
11. **Dynamic Model Allocation & Universal Execution Strategy**:
    - **Right-Sizing into 3 Classes** ([rules/model-tiers.json](rules/model-tiers.json)):
      - **ECO**: Profile 0/A, docs, scripts, Tier 4 Git/lifecycle (`flash`, `gpt-4o-mini`, minimal reasoning).
      - **BALANCED**: Profile B standard features (`inherit`, `sonnet`, medium reasoning).
      - **PREMIUM**: Profile C complex architectures/deadlocks. **Subject to Mandatory Quota Protection User Gate**.
    - **Quota Protection User Gate**: For Profile C / Premium tasks, `Control` pauses and offers `[1] Premium`, `[2] Balanced`, `[3] Eco` to protect quota (bypassed if specified in prompt via `--eco`, `--balanced`, `--premium`).
    - **Compound Phased Execution & Zero-Reload Invariant (Default Strategy)**: Single-context phased persona transitions preserve prefix continuity, unlocking 75–90% KV-cache discounts.
      - **Zero-Reload Core Invariant**: In Profile 0/A/B, core rules for planning, contracts, Inner-Loop TDD, verification, and atomic commits are embedded here. Do NOT spend tool calls reading skill files for core tasks; load `SKILL.md` strictly for the 4 On-Demand Specialists.
      - **Zero-Probe Environment Detection**: Determine environment (`multi_agent` if `invoke_subagent` present, else `sequential_persona`) directly from tool declarations without executing `detect-models.ps1` during normal tasks.
    - **Selective Subagent Forking (`invoke_subagent`)**: Reserved strictly for divergent research; dispatch `research` subagents with `Model: "flash"`.
    - **Terminal & Context Hygiene**: Run PowerShell with `-NoProfile` and testrunners in quiet mode (`-q`, `--verbosity quiet`). Telemetry recorded via `scripts/record-telemetry.ps1`.
12. **Branch & PR Process Model**: Dedicated branches (`feat/`, `fix/`, `refactor/`). Squash-and-merge via PRs after developer testing and passing CI.
    - **Purpose-Bound Git Operations**: Git status/branch checks execute ONLY when committing, pushing, or creating PRs, never proactively during read-only queries or edits.
13. **Four-Step Codebase Analysis Protocol**: Check baseline (`ARCHITECTURE.md`) -> Sync if needed (`ask-contract-specialist`) -> Deduce state from module docs -> Targeted code inspection only when essential. Localized fixes inspect the single file directly.
14. **Lifecycle Action Execution Governance (Commit, Push, PR Merge, Release)**:
    - **Strict Atomic Action**: Execute only what was requested (commit does not auto-push).
    - **State-Driven Prerequisites**: Automatically resolve prerequisites (e.g. commit uncommitted changes before push).
    - **Proactive Next-Step Offering**: Proactively suggest the logical successor action upon completion.
    - **Adaptive Gate Resolution**: Direct user instructions execute without redundant confirmation unless out-of-scope changes or anomalies occur.
    - **Clean Release Tagging**: Tag HEAD directly on `main` (`vX.Y.Z`). No standalone changelog commits on `main`.
15. **Adaptive Governance Strictness Levels**: `Standard` (Default), `Enterprise` (strict formal coverage), `Legacy` (pragmatic compiler-first), `Prototype` (speed-first MVP).
16. **Purpose-Driven Execution & Anti-Ceremony Guardrail (No Process for Process's Sake)**:
    - Every tool call must serve a tangible purpose. Zero Git operations and zero test execution on read-only tasks. No test execution for markdown, docs, comments, or static text assets. Small fixes and refactorings bypass requirement registration and architecture sync.

## Subagent Roles & Governance Mappings
Single Source of Truth: [`rules/model-tiers.json`](rules/model-tiers.json):
- **Core Lifecycle**: `Control` (Unified Core Lifecycle Engineer & Orchestrator: Planning, Contracts, Inner-Loop TDD, Two-Stage Quality Gate, Lifecycle Git).
- **On-Demand Specialist Capability Packs**:
  - `Troubleshooter` (`ask-troubleshooter`): RCA, reproduction tests, adversarial review, Fowler refactoring, performance profiling.
  - `GitTroubleshooter` (`ask-git-troubleshooter`): Git safety, merge/rebase conflict resolution, reflog recovery, safety backups.
  - `ContractSpecialist` (`ask-contract-specialist`): Living feature specs, concept tracks, requirements governance, API contracts, DB migrations, architecture sync, i18n.
  - `ReleaseManager` (`ask-release-manager`): Release automation, SemVer calculation, changelog generation, CI/CD workflows, security audits, Git release tags.

## Context Isolation & Compaction Protocol
- Pass downstream agents only the strictly necessary scoped context.
- **Proactive Context Compaction**: At phase boundaries (Plan -> Implementation, or between tasks), synthesize a concise State Checkpoint and prune intermediate chatter/logs to maximize reasoning and maintain KV-cache prefix hits.

## Client Directory Compatibility (`.agents` vs. `_agents`)
- Gemini/Antigravity uses `_agents`, GitHub Copilot expects `.agents/`. When mounted as a submodule, operations target the host repository root. Skills in `skills/` (or `_agents/skills/` / `.agents/skills/`), rules in `rules/`.
