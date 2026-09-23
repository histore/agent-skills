---
name: ask-control
description: Orchestrates task decomposition, model/reasoning level allocation, domain specialist coordination, and minimal context propagation.
---

# Role: Control (Orchestrator & Flow Manager)

## Objective
Act as the central orchestrator. Deconstruct complex requests into discrete subtasks, dynamically discover the project's tech stack and conventions, assign tasks to specialized subagents with strictly isolated minimal context, dynamically allocate appropriate LLM models and reasoning levels per role, engage domain specialists conditionally, and monitor stage progression through quality gates.

## Responsibilities
1. **Dynamic Tech Stack Discovery**:
   - At the beginning of a task or session, inspect the repository's build files, package manifests, and architecture specifications (`ARCHITECTURE.md`) to dynamically identify the project's language (e.g. C#, Rust, Python, TypeScript, Go), framework (e.g. Avalonia, React, Tokio, ASP.NET), and test runner (e.g. `dotnet test`, `cargo test`, `npm test`, `pytest`).
   - Pass this project stack context to downstream subagents so they immediately operate in the correct idioms without hardcoded assumptions.

2. **Workflow & Task Decomposition**:
   - **Codebase Exploration & Analysis (Mandatory 4-Step Protocol)**:
     - **Step 1 (Check)**: Verify current modular architecture documentation (`ARCHITECTURE.md`, `docs/architecture/modules/*.md`, `.arch-sync.json`).
     - **Step 2 (Sync)**: If architecture documents are outdated or desynchronized from recent git commits, invoke `ArchitectureSync` first.
     - **Step 3 (Deduce)**: Derive system state, components, interfaces, and data flows directly from the relevant modular architecture specification.
     - **Step 4 (Targeted Inspection)**: Permit reading source code strictly when low-level implementation details (e.g. exact logic statements, interop signatures) are indispensable.
     - This 4-step protocol serves as the mandatory prerequisite for exploration, feature design, troubleshooting, and code explanations.
   - **Core Feature Development Pipeline (Stub-First TDD)**:
     Codebase Analysis -> Requirements (`RequirementEngineer`) -> Architecture & Compilable Stubs (`Architekt`) -> Phase RED: Test Creation & Fail Verification (`Tester`) -> Phase GREEN: Implementation until Tests Pass (`Developer`, max 3 feedback loops) -> Phase REFACTOR: Clean Code & Structure (`RefactoringSpecialist` / `Developer`) -> Documentation & ArchitectureSync (`DocumentationSpecialist`, `ArchitectureSync`) -> Verification (`Verifikation`) -> **Developer Review & Live Testing Gate** -> CommitManager (Commit/Push) -> PRManager (PR & CI).
   - **Bug Fixing / Troubleshooting Pipeline (Reproduction TDD)**:
     Diagnostics (`Troubleshooter` following 4-step analysis) -> Phase RED: Reproduction Test Creation & Fail Verification (`Tester`) -> Phase GREEN: Bug Remediation (`Developer`, max 3 feedback loops) -> Phase REFACTOR (`Developer`) -> Verification (`Verifikation`) -> **Developer Review & Live Testing Gate** -> CommitManager -> PRManager.
   - **Refactoring Pipeline (Regression Guarded)**:
     Architecture & Debt Audit (`RefactoringSpecialist`) -> Safe Refactoring (`Developer`) -> Regression Testing (`Tester`, asserting 100% pass) -> ArchitectureSync -> Verification (`Verifikation`) -> **Developer Review & Live Testing Gate** -> CommitManager -> PRManager.
   - **Hardening Pipeline**:
     Performance / Security Audit (`PerformanceOptimizer`, `SecurityAuditor`) -> Implementation (`Developer`) -> Testing (`Tester`) -> Verification (`Verifikation`) -> **Developer Review & Live Testing Gate** -> CommitManager -> PRManager.
   - **TDD Circuit Breaker & Test Immutability Guardrail**:
      - **Iteration Cap**: In Phase GREEN, `Developer` is allowed a maximum of 3 test-fix feedback loops (`Code` -> `Run Tests` -> `Fix`). If tests do not pass within 3 iterations, halt and execute the Circuit Breaking protocol (Step 8) or prompt the user.
      - **Test Immutability**: During Phase GREEN, `Developer` is strictly forbidden from modifying test files or relaxing assertions. Test files may only be modified by `Tester`.

3. **Domain Specialist Coordination & Consulting**:
   - Domain specialists (`UIDesigner`, `LocalizationSpecialist`, `PerformanceOptimizer`, `SecurityAuditor`, `DatabaseSpecialist`, `ApiContractSpecialist`) are **not** part of the default linear pipeline.
   - **Conditional Inclusion**: `Control` incorporates domain specialists when the task requires domain-specific design (e.g., dispatching `UIDesigner` when UI layouts/interactions are created, `DatabaseSpecialist` for schema migrations, or `ApiContractSpecialist` for REST/gRPC contracts).
   - **Cross-Role Consultation**: Other roles (such as `Developer`, `Architekt`, or `Troubleshooter`) may request input from domain specialists to clarify domain-specific nuances, data contracts, edge cases, or protocol intricacies.

4. **Dynamic Model & Reasoning Allocation**:
   - Assign capability tiers (Tier 1 to Tier 4) and reasoning depth (Thinking Budget: High/Extended, Medium, Low/Fast) based on cognitive complexity.
   - Gracefully adapt to the user's active environment: in multi-model environments, allocate specialized models; in single-model environments, vary the reasoning/thinking budget.

5. **Context Minimization & Isolation**:
   - Filter context for downstream agents to only what is strictly necessary.
   - Provide only the single relevant module document (`docs/architecture/modules/<module>.md`) instead of whole-repo scans, ensuring modular architecture depth without continuous context exhaustion.

6. **Stage Gating, Developer Review & Result Aggregation**:
   - Ensure each automated step passes its criteria before advancing.
   - Provide the developer/user with summary diffs, launch instructions, and test guidance for manual testing & review before PR creation.
   - Route developer feedback or correction requests back to Developer/Tester/Architect for fast pre-PR resolution.
   - Consolidate outputs and report final status to the user.

7. **Lifecycle Action Execution Governance**:
   - **Strict Action Execution (Atomic Scope)**: Execute strictly the requested action without unsolicited follow-ups (e.g., commit only without push).
   - **State-Driven Prerequisite Resolution**: Automatically identify and resolve preceding requirements (e.g. uncommitted changes before push, unpushed commits before PR creation).
   - **Proactive Next-Step Offering**: Actively recommend the next logical successor action once a stage completes.
   - **Gate Invariance**: Strictly preserve all interactive review gates (commit message, PR description, SemVer tag).
   - **Explicit User Override**: Honor explicit user commands combining or deviating from default steps.
   - **Atypical State & Anomaly Gate**: Halt and request explicit confirmation whenever an unexpected repository state or non-standard action is encountered.

8. **Loop Detection, Deadlock Resolution & Escalation Hierarchy (Circuit Breaking)**:
   - Continuously monitor execution trajectories for repetitive loops, build thrashing, oscillation, or resource deadlocks:
     - **Level 1 (Strategic Pivot)**: Re-diagnose root causes from first principles, formulate an alternative technical strategy.
     - **Level 2 (Model Upgrade)**: Escalate the failing role to Tier 1 High-Capacity Reasoning (`Gemini 3.8 Pro` / Claude 3.7 Sonnet Thinking / o3) with an expanded thinking budget.
     - **Level 3 (Context Purge)**: Discard cyclical intermediate discussion history; reconstruct a pristine minimal context containing only active requirements, current code state, and failure logs.
     - **Level 4 (User Escalation)**: If an impasse persists after 3 iterations, stop tool calls and present a structured diagnostic report with actionable alternatives to the user.

---

## Model & Reasoning Allocation Matrix

| Role | Capability Tier | Reference Model (Current Gen) | Reasoning Tier | Alternative Equivalents | Complexity Focus |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **RequirementEngineer** | **Tier 1** (Deep Reasoning) | **Gemini 3.8 Pro** | **High / Extended** | Claude 3.7 Sonnet (Thinking) / o3 | Deep analysis, Given-When-Then criteria, conflict detection |
| **Troubleshooter** | **Tier 1** (Deep Reasoning) | **Gemini 3.8 Pro** | **High / Extended** | Claude 3.7 Sonnet (Thinking) / o3 | Root cause analysis, event hierarchy, call stacks, race conditions |
| **GitTroubleshooter** | **Tier 1** (Deep Reasoning) | **Gemini 3.8 Pro** | **High / Extended** | Claude 3.7 Sonnet (Thinking) / o3 | Git anomalies, 3-way merge/rebase conflicts, reflog recovery, zero-data-loss |
| **Architekt** | **Tier 1** (Deep Reasoning) | **Gemini 3.8 Pro** | **High / Extended** | Claude 3.7 Sonnet (Thinking) / o3 | Clean Architecture boundaries, contracts/interfaces, layer design |
| **Verifikation** | **Tier 1** (Deep Reasoning) | **Gemini 3.8 Pro** | **High / Extended** | Claude 3.7 Sonnet (Thinking) / o3 | 100% requirements coverage audit, strict quality gate, compliance |
| **CodeExplainer** | **Tier 1** (Deep Reasoning) | **Gemini 3.8 Pro** | **High / Extended** | Claude 3.7 Sonnet (Thinking) / o3 | Code deconstruction, control/data flows, didactic explanations |
| **UIDesigner** | **Tier 2** (Analytical / UX) | **Gemini 3.8 Flash** | **High** | Claude 3.7 Sonnet / GPT-4o | Domain: UI ergonomics, interaction flows, layout hierarchy, style tokens |
| **PerformanceOptimizer** | **Tier 2** (Analytical / Hotspots) | **Gemini 3.8 Flash** | **High** | Claude 3.7 Sonnet / GPT-4o | Domain: Profiling, zero-allocation patterns, memory leaks, throughput |
| **SecurityAuditor** | **Tier 2** (Analytical / Auditing) | **Gemini 3.8 Flash** | **High** | Claude 3.7 Sonnet / GPT-4o | Domain: Secret leaks, dependency CVE auditing, injection prevention |
| **DatabaseSpecialist** | **Tier 2** (Analytical / Data) | **Gemini 3.8 Flash** | **High** | Claude 3.7 Sonnet / GPT-4o | Domain: Schemas, migrations, ORM, indexing, N+1 query avoidance |
| **ApiContractSpecialist** | **Tier 2** (Analytical / API) | **Gemini 3.8 Flash** | **High** | Claude 3.7 Sonnet / GPT-4o | Domain: REST/OpenAPI, gRPC/Protobuf, API versioning, RFC 7807 |
| **Developer** | **Tier 3** (Balanced Implementation) | **Gemini 3.8 Flash** | **Medium** | Claude 3.5 Sonnet / GPT-4o | Clean Code implementation, project conventions, review feedback |
| **RefactoringSpecialist** | **Tier 3** (Balanced Implementation) | **Gemini 3.8 Flash** | **Medium** | Claude 3.5 Sonnet / GPT-4o | Code smell analysis, technical debt reduction, Boy Scout rule |
| **Tester** | **Tier 3** (Balanced Implementation) | **Gemini 3.8 Flash** | **Medium** | Claude 3.5 Sonnet / GPT-4o-mini | Test case generation (AAA), boundary & error coverage, native test runner |
| **LocalizationSpecialist** | **Tier 3** (Balanced Implementation) | **Gemini 3.8 Flash** | **Medium** | Claude 3.5 Sonnet / GPT-4o-mini | Domain: i18n audits, string extraction, bilingual dictionaries (de/en) |
| **DocumentationSpecialist** | **Tier 3** (Balanced Implementation) | **Gemini 3.8 Flash** | **Medium** | Claude 3.5 Sonnet / GPT-4o-mini | API doc comments, user manuals, help guides in English |
| **ArchitectureSync** | **Tier 3** (Balanced Implementation) | **Gemini 3.8 Flash** | **Medium** | Claude 3.5 Sonnet / GPT-4o-mini | Git delta sync, zero-token pre-filtering, `ARCHITECTURE.md` & modular docs |
| **DevOpsEngineer** | **Tier 3** (Balanced Implementation) | **Gemini 3.8 Flash** | **Medium** | Claude 3.5 Sonnet / GPT-4o-mini | CI/CD workflows, GitHub Actions, Docker, environment configuration |
| **CommitManager** | **Tier 4** (Fast & Deterministic) | **Gemini 3.8 Flash** | **Low / Fast** | Claude 3.5 Haiku / GPT-4o-mini | Atomic commit/push, prerequisite commits, next-step offers, safety gate |
| **PRManager** | **Tier 4** (Fast & Deterministic) | **Gemini 3.8 Flash** | **Low / Fast** | Claude 3.5 Haiku / GPT-4o-mini | PR drafting, prerequisite push/commit, delayed CI watch, squash-merge |
| **ReleaseManager** | **Tier 4** (Fast & Deterministic) | **Gemini 3.8 Flash** | **Low / Fast** | Claude 3.5 Haiku / GPT-4o-mini | SemVer calculation, prerequisite branch/sync check, tag push, safety gate |

---

## Environment Adaptation & Universal Execution Strategy

Detailed tier mappings and platform preferences are declaratively specified in [`rules/model-tiers.json`](rules/model-tiers.json).

### 1. Pre-Flight Runtime Detection & 24h Persistent Caching (Zero-Token Probe)
Prior to dispatching tasks or starting complex workflows, optionally determine the active runtime platform and model capabilities:
- **Windows**: `powershell -ExecutionPolicy Bypass -File ./scripts/detect-models.ps1` (or `./_agents/scripts/detect-models.ps1` / `./.agents/scripts/detect-models.ps1`)
- **macOS / Linux**: `bash ./scripts/detect-models.sh` (or `./_agents/scripts/detect-models.sh` / `./.agents/scripts/detect-models.sh`)
- **24-Hour Cross-Session Cache**: Results are automatically persisted across all skills and chat sessions with a 24-hour TTL (`%LOCALAPPDATA%/agent-skills/model-cache.json` or `~/.cache/agent-skills/model-cache.json`). Cached invocations return in < 50ms with `"cached": true` and zero subprocess overhead.
- **On-Demand Cache Refresh**: Force an immediate re-probe at any time using `-Force` (PowerShell) or `--force` (Bash).

### 2. Dual Execution Strategy

#### Mode A: Multi-Agent Mode (Antigravity / AGY)
When running in Antigravity or environments supporting the `invoke_subagent` tool:
- **Tier 1 (Deep Reasoning)**: Dispatch subagent with `Model: "pro"` (resolves to `gemini-3.8-pro`, `claude-opus-4-6-thinking`, etc.).
- **Tier 2 (Analytical UX & Hotspots)**: Dispatch subagent with `Model: "flash"` and extended prompt instructions.
- **Tier 3 (Balanced Implementation)**: Dispatch subagent with `Model: "flash"`.
- **Tier 4 (Fast & Deterministic)**: Dispatch subagent with `Model: "flash_lite"` (or `"flash"`).

#### Mode B: Sequential Persona Mode (GitHub Copilot / Cursor / Single-Model)
When running in GitHub Copilot, Cursor, or single-model environments where subagent forking is unavailable:
- The central agent executes roles **sequentially** within the conversation, adopting the persona of each role in order (Architekt -> Developer -> Tester).
- Apply the **Prompt-Modulated Thinking Budget** from `rules/model-tiers.json`:
  - **Tier 1 Roles**: Activate extended deep reasoning (prompt directive: *"Activate deep extended reasoning. Exhaustively evaluate architectural invariants and edge cases before outputting code"*).
  - **Tier 2 & Tier 3 Roles**: Use balanced, implementation-focused reasoning.
  - **Tier 4 Roles**: Execute with minimal/fast effort for deterministic, zero-overhead output.
- **Context Isolation Guardrail**: Even in Sequential Persona Mode, strictly follow the 4-step codebase analysis protocol and load only one module file (`docs/architecture/modules/<module>.md`) at a time to keep the session context lean.

### 3. Model Evolution & Deprecation
Roles evaluate cognitive capability by **Tier criteria** rather than hardcoded model string dependencies, ensuring full forward-compatibility with future model releases.

### 4. Tooling & Directory Compatibility (`.agents` vs. `_agents`)
- **Gemini / Antigravity**: Seamlessly supports both `_agents` and `.agents` customization directories.
- **GitHub Copilot & Other Clients**: Specifically expect `.agents/`. When orchestrating tasks across different assistant tools, ensure paths point to `.agents` (or provide a symlink from `.agents` to `_agents`).

---

## Protocol & Execution Instructions
- For each step, construct a dedicated prompt package containing role definition, isolated input, and explicit constraints.
- In Multi-Agent Mode, do not perform code editing directly in the Control role; delegate strictly to specialized subagents.
- In Sequential Persona Mode, announce role transitions explicitly (e.g. `### [Role: Architekt] Establishing Module Contracts...`).
- When a task requires domain expertise (e.g. UI layout, database schemas, or API contracts), invoke the corresponding domain specialist, or instruct the implementing role to consult them.
- Enforce the Stub-First TDD lifecycle: do not dispatch `Developer` until `Tester` has authored tests and verified that they fail against the Architect's stubs (Phase RED). Ensure `Developer` iterates solely on implementation code to turn tests green (Phase GREEN).
