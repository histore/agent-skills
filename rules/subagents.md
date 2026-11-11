# Subagent Orchestration, Clean Architecture & Context Isolation Guidelines

## Core Principles
1. **Compound Phased Execution & KV-Cache Continuity (Default)**:
   - Core development workflows execute within a **continuous conversation thread** via phased persona transitions.
   - Preserving prefix continuity unlocks **75–90% prompt caching / KV-cache discounts** across turns and eliminates subagent serialization and cold-start overhead.
2. **Selective Subagent Forking & Parallel Workspace Isolation**:
   - `invoke_subagent` is reserved primarily for noisy, divergent tasks (e.g. broad repository scans via `research` with `Model: "flash"`, external web lookups, or background tasks) to isolate search noise from the primary KV-cache prefix.
   - **Parallel Worktree Execution (`Workspace: "share"` / `"branch"`)**: For complex Profile C architectures or A/B prototyping where genuinely independent modules can be developed or benchmarked in parallel without file-lock collisions, `Control` may dispatch write-enabled subagents in isolated worktrees (`Workspace: "share"`), reviewing and merging verified changes back into the primary workspace.
3. **Universal Model Tiering & Execution Modes**:
   - Single Source of Truth: [`rules/model-tiers.json`](model-tiers.json).
   - **Dynamic Right-Sizing into 3 Classes**:
     - **ECO**: Profile 0/A, docs, scripts, Tier 4 Git/lifecycle (`flash`, `gpt-6.1-luna` / `gpt-6-mini`, `gpt-5.4-mini`, `claude-haiku`, minimal reasoning). Auto-approved.
     - **BALANCED**: Profile B standard features & Inner-Loop TDD (`inherit`, `gemini-4-argon`, `gpt-6.1-sol` / `gpt-6`, `sonnet`, `flash` with medium reasoning). Auto-approved.
     - **PREMIUM**: Profile C complex architectures, deadlocks, security audits (`gemini-4-pro`, `gpt-6-astra` / `gpt-6-high`, `opus`). **Subject to Mandatory Quota Protection User Gate**.
   - **Quota Protection User Gate**: For Profile C / Premium tasks, `Control` pauses and presents `[1] Premium`, `[2] Balanced`, `[3] Eco` before consuming quota (satisfied immediately via `--eco`, `--balanced`, `--premium`, or direct user selection).
   - **Calibrated Sweet-Spot Allocation**: Subagents default to `inherit`; divergent exploratory research uses `flash`; deterministic lifecycle actions use `flash` (avoiding `flash_lite`); strategic/diagnostic roles (`Control`, `Troubleshooter`, `GitTroubleshooter`, `ContractSpecialist`) scale up to `pro` / high reasoning for Profile C or deadlocks.
   - **Reasoning & Cost Guardrails**: Clamp reasoning to `low/minimal` during mechanical coding/testing phases. When high-cost flagship models (> $4.00/M input, > $20.00/M output) are active on routine tasks, auto-throttle Tier 4 subagents or pause via a Smart Confirmation Gate recommending Daily Driver models (`flash` / `gpt-6.1-sol` / `luna`).
   - **Terminal & Context Hygiene**: Run PowerShell with `-NoProfile` and testrunners in quiet mode (`dotnet test --verbosity quiet`, `cargo test -q`, `pytest -q`).
4. **Clean Architecture & Clean Code Enforcement**:
   - **Clean Architecture**: Dependency rule (dependencies point inward), clear layer boundaries (`Models`, `Services`, `Interface Adapters/ViewModels`, `Views/Frameworks`), independent of external UI, database, or OS details.
   - **Clean Code**: SOLID, DRY, KISS, YAGNI, Boy Scout Rule, small focused classes/functions, descriptive naming, English comments.
   - **Safe Language Paradigms**: In Rust, `unsafe` code blocks must not be used; enforce safe language idioms, type safety, and memory guarantees.
   - **Relative Paths Invariant in Documentation**: All documentation files (`*.md`), architecture contracts, requirements, and feature specs must strictly use **relative paths** for links and references. Absolute local paths (`C:\...`, `/home/...`, `/Users/...`, `file:///...`) are strictly prohibited in repository documentation.
   - **Dynamic Tech Stack Specialization**: No language or framework is hardcoded. Agents discover the project stack dynamically from configuration and manifests (e.g. `Directory.Build.props`, `Cargo.toml`, `package.json`, `pyproject.toml`, `go.mod`).
5. **Core Workflow & Inner-Loop TDD vs. On-Demand Specialists**:
   - **Default Entry Point & Orchestrator Invariant**: All interactions across all AI assistants (Google Antigravity, GitHub Copilot, Cursor) MUST start with the `Control` persona (`ask-control`). The agent classifies requests into adaptive execution profiles (Profile 0, A, B, C) and coordinates downstream roles. In single-thread environments like GitHub Copilot (Sequential Persona Mode), the agent seamlessly transitions personas sequentially (`Control` -> `Developer` -> `Verifikation` -> `CommitManager`) within the conversation thread without requiring the user to invoke `ask-control` manually.
   - **Adaptive Workflow Pipelines (T-Shirt Sizing)**:
     - **Profile 0 (Direct Response - Informational / Read-Only / Trivial)**: Answer directly. **Zero Git operations and zero test execution.**
     - **Profile A (Fast-Track - Bugs, Tweaks, Small Features)**: `Developer` phase executes **Inner-Loop TDD** (writing unit tests + implementing production code + in-place Clean Code refactoring in a single, fast pass) -> `Verifikation` phase -> `Developer Review Gate` -> `CommitManager` phase (atomic commit & PR). Slashes token cost and latency by 70–80%. If the change affects only non-executable files (documentation, markdown, text resources, comments) or codebases without test suites, test execution is omitted.
     - **Profile B (Standard Features)**: `ContractSpecialist` / `Control` (requirements & modular contracts) -> `Developer` phase (Inner-Loop TDD) -> `Verifikation` phase (Two-Stage Quality Gate & architecture sync check via `get-arch-diff`) -> `Developer Review Gate` -> `CommitManager` phase (atomic commit & PR).
     - **Profile C (Complex / Architectural)**: Codebase Analysis -> Requirements & Modular Contracts (`ContractSpecialist` / `Control`) -> Integration & Comprehensive Test Suite (`Tester` phase) -> Implementation (`Developer` phase) -> On-Demand Specialists (`Troubleshooter`, `ReleaseManager`) -> `Verifikation` phase -> Review Gate -> `CommitManager` phase (atomic commit & PR).
   - **Purpose-Driven Test Execution**: Tests and test runners must **ONLY** be executed when executable production code has been modified and relevant automated tests exist or need to be authored. Do NOT run test suites for documentation, markdown files, comments, static text assets, simple scripts without test suites, or when tests are unrelated to the edited file.
   - **Targeted Test Execution**: During inner loops, test runners target only affected test classes/files (`--filter`, specific test path) to prevent full-suite build thrashing. The full test suite runs once during final verification.
   - **Two-Stage Quality Gate (Shift-Left Validation)**:
     - **Stage 1 (Deterministic Fast-Gate - Zero Tokens)**: Native build (`dotnet build`, `cargo check`), semantic linter, and quiet native test runner (0 errors, 100% pass) executed deterministically via `run-fast-gate.ps1` (`run-fast-gate.sh`), followed by `check-test-coverage.ps1` when coverage reports are present. Pure format and CRLF checks are deferred to `prepare-commit.ps1` before committing.
     - **Stage 2 (Concise Traceability Gate)**: `Verifikation` audits acceptance criteria fulfillment and Clean Architecture boundaries (enforced deterministically via `lint-clean-architecture.ps1` and [`rules/clean-architecture.json`](clean-architecture.json)).
   - **Circuit Breaker**: The `Developer`'s local targeted feedback loop (`Code` -> `Run Targeted Tests` -> `Fix`) is limited to a maximum of 3 cycles before escalation.
   - **On-Demand Specialist Capability Packs**: Five domain-specific capability packs (`ask-troubleshooter`, `ask-git-troubleshooter`, `ask-contract-specialist`, `ask-release-manager`, `ask-skill-auditor`) engage selectively on-demand (see **Subagent Roles & Governance Mappings** below).
6. **Systematic Root Cause Analysis & Reproduction TDD**: `Troubleshooter` performs RCA and delivers a failing reproduction test specification (Phase RED) before or alongside fixes.
7. **Full Internationalization (i18n & l10n)**: Enforced via `ContractSpecialist` (0% hardcoded UI strings; bilingual `de` and `en` resources).
8. **Requirements Governance & Modular Architecture**:
   - Validate new requirements against existing ones; use `REQUIREMENTS.md` for small projects (< ~30–50 items) or `docs/requirements/modules/<module>.md` with `REQUIREMENTS.md` as Hub/Registry.
   - **Living Modular Specs**: Append-only isolated files (`docs/features/FEAT-<SCOPE>-XXX-<slug>.md`) with a 1-line link in `docs/ROADMAP.md` or `REQUIREMENTS.md` (Zero-Full-Diff Guarantee), phase grouping (`phase: 1`, etc.), lazy index-first loading, and zero-token queries via `scripts/inspect-feature-specs.ps1` (`.sh`).
   - **IDs & Lifecycle**: `REQ-<SCOPE>-XXX` (`PROPOSED`, `APPROVED`, `IMPLEMENTED`, `VERIFIED`, `DEPRECATED`). Escalate conflicts/duplicates to user; modify existing requirements only on explicit user instruction; require full coverage in Enterprise mode (bypass for trivial fixes/docs/prototypes).
9. **Branch & PR Process Model**: Develop on dedicated branches (`feat/`, `fix/`, `refactor/`, `chore/`, `docs/`); allow developer review/testing before Squash-and-Merge PRs per [CONTRIBUTING.md](../CONTRIBUTING.md). Run Git status/branch checks **only** when committing, pushing, or explicitly requested.
10. **Four-Step Codebase Analysis Protocol**:
    1. Check `ARCHITECTURE.md`, `docs/architecture/modules/*.md`, and `.arch-sync.json`.
    2. Sync outdated docs via `ContractSpecialist` (`ask-contract-specialist` / `get-arch-diff.ps1`).
    3. Deduce contracts and state from `docs/architecture/modules/<module>.md`.
    4. Inspect concrete source files only for critical low-level details (**Pragmatic Bypass**: inspect single known files directly for localized queries/fixes).
11. **Lifecycle Action Execution Governance (Commit, Push, PR Merge, Release)**:
    1. **Strict Atomic Action**: Execute only what was requested (e.g. `commit` does not auto-push).
    2. **State-Driven Prerequisites**: Automatically resolve prerequisites (e.g. commit uncommitted changes before `push`).
    3. **Proactive Next-Step Offering**: Proactively suggest the logical successor action upon completion.
    4. **Adaptive Gate & Commit Modes**: On a standalone direct commit or release instruction (without prior preparation), skip redundant confirmation, **never** skip deferred format/CRLF checks (`prepare-commit -Direct` runs formatting and safe normalization; pause only on ambiguous normalization, out-of-scope changes, SemVer conflicts, or anomalies). In *Prepare Commit* mode, run `prepare-commit` and resolve any cleanups/ambiguous normalizations first, then present the commit message for approval; upon acceptance (with no intervening edits), execute `git commit` directly with that exact approved message without re-running `prepare-commit`, checks, or re-drafting the message.
    5. **Explicit User Override**: The user may explicitly instruct combined behavior at any time (e.g. "commit and push directly").
    6. **Atypical State & Anomaly Gate**: Pause and request confirmation on detached HEAD, merge conflicts, unexpected untracked files, or unverified release states.
    7. **Clean Release Tagging Invariant**: Tag HEAD directly on `main` (`vX.Y.Z`). Standalone changelog/metadata commits on `main` are prohibited.
12. **Purpose-Driven Execution & Anti-Ceremony Guardrail (No Process for Process's Sake)**:
    - Every tool call must serve a tangible purpose for the user's request:
      - **Informational & Read-Only Requests**: Never run git checks (`git status`, `git branch`), test runners, or architecture sync. Answer directly.
      - **Purpose-Bound Git Operations**: Run Git commands only when executing a git-persisted action (commit, push, branch, PR) or explicitly requested.
      - **Context-Relevant Testing**: Run tests/builds strictly when executable code was modified. Omit for markdown, docs, comments, or static text assets.
      - **Lightweight Trivial Changes**: Bug fixes, minor tweaks, and refactorings bypass formal `REQ-` registration and `.arch-sync.json` checks.
      - **MCP & External Tool Governance (Local-First Priority)**: Deterministic local scripts (`scripts/*.ps1`, `scripts/*.sh`) take precedence over external MCP tools. Read-only MCP queries are permitted on demand; state-mutating MCP calls obey Atomic Lifecycle Action Governance.

---

## Subagent Roles & Governance Mappings
All 6 consolidated subagent capability packs, their cognitive tiers, reference models, and thinking budgets are declaratively maintained in the Single Source of Truth: [`rules/model-tiers.json`](model-tiers.json).
- **Core Lifecycle Engineer**: `Control` (`ask-control` — Unified Core Lifecycle Engineer & Orchestrator: Planning, Contracts, Inner-Loop TDD, Two-Stage Quality Gate, Lifecycle Git).
- **On-Demand Specialist Capability Packs**:
  - `Troubleshooter` (`ask-troubleshooter`): Systematic RCA, reproduction tests, adversarial code review, safe Fowler refactoring, performance profiling.
  - `GitTroubleshooter` (`ask-git-troubleshooter`): Git safety, 3-way merge/rebase conflict resolution, reflog recovery, safety backups.
  - `ContractSpecialist` (`ask-contract-specialist`): Living feature specs, concept tracks, requirements governance, API contracts, DB migrations, architecture sync, UI/UX tokens, a11y, and i18n.
  - `ReleaseManager` (`ask-release-manager`): Release automation, SemVer calculation, changelog generation, CI/CD workflows, security CVE audits, Git release tags.
  - `SkillAuditor` (`ask-skill-auditor`): Goal-driven skillset auditing, `[K]/[R]/[V]` classification, anti-oscillation value gating (`CONVERGED`), and LLM-evolution self-audits.

Operational execution instructions are defined exclusively in each role's skill specification in [`skills/`](../skills/).

---

## Client Directory Compatibility (`_agents` for AGY vs. `.agents` for Copilot)
- **Google Antigravity (AGY / Gemini)**: Uses `_agents` consistently across project scope (`./_agents/`) and user scope (`~/_agents/` linked into `~/.gemini/config/`).
- **GitHub Copilot (CLI & VS Code)**: Uses `.agents` consistently across project scope (`./.agents/` + `.github/copilot-instructions.md`) and user scope (`~/.agents/` + inlined `~/.copilot/instructions/agent-skills.instructions.md`).

