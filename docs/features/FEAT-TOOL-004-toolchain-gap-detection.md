# Feature Specification: `Deterministic Toolchain Gap Detection ([ToolchainGap])`

```yaml
---
id: FEAT-TOOL-004
title: "Deterministic Toolchain Gap Detection ([ToolchainGap])"
phase: 1
status: IMPLEMENTED # PROPOSED | APPROVED | IN_PROGRESS | IMPLEMENTED | VERIFIED | DEPRECATED
target_release: "v0.4.0"
scope: "TOOLING" # e.g. AUTH, CORE, UI, API, STORAGE
depends_on: ["FEAT-TOOL-001", "FEAT-GOV-002"]
---
```

> **Specification Path**: `docs/features/FEAT-TOOL-004-toolchain-gap-detection.md`  
> **Parent Hub / Index**: [ROADMAP.md](../ROADMAP.md)

This document is an **isolated, living feature specification**. It is authored incrementally, updated in-place without rewriting the rest of the documentation, and loaded lazily by AI agents to keep token usage minimal.

---

## 1. Executive Summary & Objective
Eliminates silent fail-open `PASS` results when `agent-skills` runs in repositories with unsupported or only partially supported tech stacks (e.g., Flutter/Dart, Swift/iOS, or C++/Node setups missing local linters). By computing `support_level` and `support_gaps` deterministically inside `detect-tech-stack` and surfacing `[ToolchainGap]` warnings inside `run-fast-gate`, AI agents inform the user transparently in the Stage-2 Zero-Trust Diff-Report with **zero extra LLM turns or happy-path token overhead**.

---

## 2. User Story
> **As a** developer using `agent-skills` across diverse repositories,  
> **I want** `detect-tech-stack` and `run-fast-gate` to detect missing build, test, linter, Clean-Architecture, or AST-outline coverage automatically and emit a `[ToolchainGap]` warning,  
> **so that** an unsupported or partial stack never produces a deceptive silent green Stage-1 result.

---

## 3. Acceptance Criteria (Given-When-Then)
Each acceptance criterion must be verifiable and formulated using Arrange-Act-Assert / Given-When-Then:

- [x] **AC-1 (`detect-tech-stack` `support_level` & `support_gaps`)**: **Given** a target repository scanned by `scripts/detect-tech-stack.ps1` / `.sh`, **When** it outputs JSON, **Then** it includes `support_level` (`"full"` | `"partial"` | `"unsupported"`) and `support_gaps` (string array): `"unsupported"` when `stack == "unknown"` and executable code files (e.g. `.dart`, `.swift`, `.php`, `.rb`, `.zig`) exist; `"partial"` when `stack` is known but `lint_cmd` or `format_check_cmd` is empty, `language` lacks `lint-clean-architecture` / `get-code-outline` coverage, or framework markers (e.g. `react-native`, `compose.multiplatform`) lack dedicated guardrails; and `"full"` when all core gates are active.
- [x] **AC-2 (`run-fast-gate` `[ToolchainGap]` Warning on Code Changes)**: **Given** working-tree changes to executable code files where `support_level != "full"` or `lint-clean-architecture` reports `scanned_source_files == 0` despite modified code files, **When** `scripts/run-fast-gate.ps1` / `.sh` runs, **Then** it emits a structured `[ToolchainGap]` warning in `warnings` listing the missing deterministic checks instead of a silent `PASS`.
- [x] **AC-3 (Zero-Overhead Anti-Ceremony Bypass)**: **Given** a Profile 0 query or working-tree changes affecting only markdown/documentation files (`*.md`), **When** `scripts/run-fast-gate.ps1` / `.sh` runs, **Then** `bypassed_code_gate = true` remains active and zero `[ToolchainGap]` warnings are emitted.
- [x] **AC-4 (Reactive Stage-2 Governance Rule)**: **Given** a `[ToolchainGap]` warning emitted by Stage-1 `run-fast-gate`, **When** `Control` concludes Stage 2 in [ask-control/SKILL.md](../../skills/ask-control/SKILL.md) and [copilot-instructions.md](../../.github/copilot-instructions.md), **Then** the agent explicitly surfaces the missing automated checks in the Stage-2 Zero-Trust Diff-Report without adding any proactive pre-task LLM checks on supported stacks.
- [x] **AC-5 (Cross-Script Parity & Regression Evals)**: **Given** `.ps1`/`.sh` parity scripts and a new benchmark case (`EVAL-TOOL-004`) in `evals/eval-cases.json`, **When** `scripts/test-skills.ps1` / `.sh` and `scripts/run-evals.ps1` / `.sh` run, **Then** 100% of cross-file synchronization, script parity, and regression eval checks pass.

---

## 4. Non-Goals / Out of Scope
Explicitly bound the feature scope to prevent scope creep:
- Creating a separate specialist skill or proactive LLM pre-flight prompt check (would violate Rule 17 and add token/KV-cache overhead).
- Hard-failing Stage-1 Fast-Gate (`exit 1`) on `partial` support (emits `[ToolchainGap]` in `warnings` so working builds/tests still succeed while informing the user).
- Implementing full build/test runners for every unsupported language inside this feature (covered by stack-specific `FEAT-TOOL-*` specs).

---

## 5. Architecture & Technical Constraints
- **Target Module / Layer**: Deterministic Script Toolkit ([detect-tech-stack.ps1](../../scripts/detect-tech-stack.ps1), [run-fast-gate.ps1](../../scripts/run-fast-gate.ps1) + `.sh` parity) + Governance ([ask-control/SKILL.md](../../skills/ask-control/SKILL.md), [copilot-instructions.md](../../.github/copilot-instructions.md)) + Eval Harness ([eval-cases.json](../../evals/eval-cases.json))
- **Clean Architecture Boundaries**: Purely deterministic, stateless inspection; zero extra I/O on happy-path supported stacks to preserve frozen prompt prefixes and KV-cache hits.
- **Safety Invariants**: Backward-compatible JSON schemas (`detect-tech-stack` adds optional `support_level`/`support_gaps`; `run-fast-gate` reuses `warnings` array).
- **Data Model & Contracts**:
  - `support_level`: `"full" | "partial" | "unsupported"`
  - `support_gaps`: `string[]` (e.g. `"no_build_or_test_runner"`, `"lint_cmd_missing"`, `"format_check_cmd_missing"`, `"unsupported_clean_arch_extension:.dart"`)

---

## 6. Implementation & Phasing Details
- **Phase**: `1` (Dynamic Project Extension)
- **Estimated Complexity**: `Profile B (Standard)`
- **Prerequisites / Dependencies**: `FEAT-TOOL-001`, `FEAT-GOV-002`

---

## 7. Traceability & Verification
- **Target Test Suite**: `scripts/test-skills.ps1`, `scripts/run-evals.ps1`, `evals/eval-cases.json`
- **Test Types**: Deterministic script invariant tests, `.ps1`/`.sh` parity checks, synthetic unsupported/partial stack fixture evals (AAA pattern)
- **Associated Commits / PRs**: `<Filled upon implementation>`

---

## 8. Revision & Delta History
Atomic change log for this specific feature document (avoids full-document diffing):

| Date | Version / Status | Nature of Change | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-11-25 | `PROPOSED` | Initial feature specification for deterministic `[ToolchainGap]` detection | User / Agent |
