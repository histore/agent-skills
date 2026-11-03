# Feature Specification: Next-Gen LLM Efficiency, Prompt Caching & AST Code Outline Inspection

```yaml
---
id: FEAT-EFF-001
title: "Next-Gen LLM Efficiency, Prompt Caching & AST Code Outline Inspection"
phase: 0
status: VERIFIED
target_release: "v0.2.2"
scope: "EFFICIENCY"
depends_on: ["FEAT-GOV-001", "FEAT-TOOL-001"]
---
```

> **Specification Path**: `docs/features/FEAT-EFF-001-next-gen-llm-efficiency.md`  
> **Parent Hub / Index**: [../ROADMAP.md](../ROADMAP.md)

## 1. Executive Summary & Objective
Integrates next-generation LLM efficiency mechanisms into agent-skills governance and tooling:
1. **Surgical Editing Invariant**: Enforces localized block-level diffs (`edit_file`) over full file rewrites (`write_file`), saving ~85% of expensive output tokens and eliminating regression risks.
2. **Two-Zone Prompt Cache Architecture**: Partitions context into Zone 1 (Static Frozen Prefix: base governance, tool declarations, schemata) and Zone 2 (Dynamic Tail: diffs, logs, user input) to guarantee 75–90% KV-cache discounts.
3. **Adaptive Thinking Budget Clamping**: Throttles reasoning tokens to `minimal`/`low` during deterministic Inner-Loop TDD implementation and Git lifecycle phases.
4. **Split-Phase Profile B Execution**: Specifications run on `BALANCED`, while developer TDD implementation downshifts safely to `ECO (Flash)` under unit-test protection.
5. **Zero-Token AST Code Outline Inspector**: Provides native scripts (`scripts/get-code-outline.ps1`, `scripts/get-code-outline.sh`) to inspect structural declarations across C#, Rust, TypeScript, JavaScript, Python, and Go without loading entire files into LLM context.
6. **Zero-Token Log Compaction**: Compacts build and test failure logs into structured error matrices via `collect-test-failures.ps1` (`-LogText`, `-LogFile`).

---

## 2. User Story
> **As an** AI agent, orchestrator, or human developer,  
> **I want** prompt caching preservation, surgical editing, and AST outline inspection,  
> **so that** token consumption, quota drain, and turn latency are minimized without sacrificing code quality or Clean Architecture principles.

---

## 3. Acceptance Criteria (Given-When-Then)
- [x] **AC-1 (Surgical Editing)**: **Given** an existing file modification, **When** the developer role applies changes, **Then** targeted block edits (`edit_file`) are enforced and full-file rewrites (`write_file`) are prohibited unless creating new files or restructuring > 80% of a file.
- [x] **AC-2 (Two-Zone Prompt Cache)**: **Given** multi-turn conversations, **When** prompts are assembled, **Then** Zone 1 (static prefix) remains 100% byte-identical across turns to maximize server-side KV-cache hits.
- [x] **AC-3 (Thinking Budget Clamping)**: **Given** mechanical TDD implementation or Tier 4 Git lifecycle actions, **When** reasoning models are dispatched, **Then** thinking effort is clamped to `minimal`/`low`.
- [x] **AC-4 (Split-Phase Profile B)**: **Given** Profile B standard feature execution, **When** entering developer implementation, **Then** execution may shift from `BALANCED` to `ECO` under the safety net of unit tests.
- [x] **AC-5 (Zero-Token Code Outline)**: **Given** any codebase in C#, Rust, TypeScript, Python, or Go, **When** invoking `get-code-outline.ps1` or `get-code-outline.sh`, **Then** structural types and method signatures are extracted with zero token overhead.
- [x] **AC-6 (Shift-Left Test Failure Extraction)**: **Given** raw testrunner stdout, **When** invoking `collect-test-failures.ps1 -LogText <Text>`, **Then** extract compact failing assertions and line numbers.

---

## 4. Architecture & Technical Constraints
- **Governance Alignment**: Documented in [../../AGENTS.md](../../AGENTS.md) and [../../rules/model-tiers.json](../../rules/model-tiers.json).
- **Client Synchronization**: Cross-platform parity maintained between Google Antigravity (`ask-control`) and GitHub Copilot (`.github/copilot-instructions.md`).
- **Zero-Token Scripting**: Implemented in native PowerShell 5.1+ and POSIX Bash with `-NoProfile` and LF line endings.

---

## 5. Implementation & Phasing Details
- **Phase**: `0 (Baseline Extension)`
- **Complexity**: `Profile B (Standard)`
- **Prerequisites**: `FEAT-GOV-001`, `FEAT-TOOL-001`.

---

## 6. Traceability & Verification
- **Eval Cases**: `EVAL-EFF-001`, `EVAL-EFF-002` in `evals/eval-cases.json` (verified via `scripts/run-evals.ps1`).
- **Test Suite**: Section 45 in `scripts/test-skills.ps1` (149/149 checks passed).
- **Deterministic Gate**: `scripts/run-fast-gate.ps1` passed in < 1s.

---

## 7. Revision & Delta History
| Date | Version / Status | Nature of Change | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-11-03 | `VERIFIED` | Initial specification and verification of Next-Gen LLM Efficiency & AST Inspector | User / Antigravity |
