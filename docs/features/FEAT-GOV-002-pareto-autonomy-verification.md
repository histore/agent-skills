# Feature Specification: `Pareto Autonomy & Deterministic Verification`

```yaml
---
id: FEAT-GOV-002
title: "Pareto Autonomy & Deterministic Verification"
phase: 1
status: IMPLEMENTED # PROPOSED | APPROVED | IN_PROGRESS | IMPLEMENTED | VERIFIED | DEPRECATED
target_release: "v0.3.0"
scope: "GOV"
depends_on: ["FEAT-GOV-001", "FEAT-TOOL-001", "FEAT-SPEC-001"]
---
```

> **Specification Path**: `docs/features/FEAT-GOV-002-pareto-autonomy-verification.md`  
> **Parent Hub / Index**: [ROADMAP.md](../ROADMAP.md)  
> **Source Concept**: [CONCEPT-GOV-001-pareto-autonomy-verification.md](../concepts/archive/CONCEPT-GOV-001-pareto-autonomy-verification.md)

This document is an **isolated, living feature specification**. It is authored incrementally, updated in-place without rewriting the rest of the documentation, and loaded lazily by AI agents to keep token usage minimal.

---

## 1. Executive Summary & Objective
Extends the `agent-skills` toolkit with six pure **Pareto optimizations** to increase autonomous result quality without manual line-by-line review and without extra KV-cache, latency, or anti-ceremony overhead. These include a deterministic `AC-*` traceability check and a diff-size guardrail in the Stage-1 fast-gate, a compact Zero-Trust Diff-Report in Stage 2, a stricter Progressive Disclosure rule, situative `.agent-state.json` snapshots in the scratch directory, and regression evals.

---

## 2. User Story
> **As a** developer and orchestrator of `agent-skills` (Antigravity & GitHub Copilot),  
> **I want** deterministic fast-gate checks for acceptance criteria and diff sizes, a compact Stage-2 risk report, and situative context hygiene,  
> **so that** autonomous agent runs can be completed reliably without silently skipped requirements and without manual line-by-line review.

---

## 3. Acceptance Criteria (Given-When-Then)
Each acceptance criterion must be verifiable and formulated using Arrange-Act-Assert / Given-When-Then:

- [x] **AC-1 (`AC-*` Traceability Stage-1 Fail)**: **Given** an active or working-tree-modified feature specification (`docs/features/FEAT-*.md`) with defined `AC-*` IDs, **When** `scripts/run-fast-gate.ps1` or `scripts/run-fast-gate.sh` is executed, **Then** the script checks via regex whether every `AC-*` ID is referenced in at least one test file (test name or comment), and fails with `status: fail` (exit code `1`) if coverage is missing.
- [x] **AC-2 (Anti-Ceremony Bypass in Profile A / without Spec)**: **Given** a repository or change without an active `FEAT-*.md` file containing `AC-*` criteria (e.g., Profile-A bugfix or documentation-only edit), **When** `scripts/run-fast-gate.ps1` / `.sh` is executed, **Then** the `AC-*` traceability check is skipped without overhead.
- [x] **AC-3 (Diff-Size Guardrail as Warning)**: **Given** working-tree changes to executable code that exceed the configured threshold (default: > 400 changed code lines per `git diff --numstat`), **When** `scripts/run-fast-gate.ps1` / `.sh` runs, **Then** a clear diff-size warning is emitted in the fast-gate output (and JSON field) without hard-failing the run.
- [x] **AC-4 (Zero-Trust Diff-Report in Stage 2)**: **Given** a completed Stage-1 fast-gate run in Profile B or Profile C, **When** `ask-control` completes Stage 2, **Then** instead of unstructured prose, the agent outputs a compact risk matrix (`Modified Files`, `AC-* Status`, `Fast-Gate / Guardrails & Diff-Size Warnings`, `Open Assumptions / Untested Paths`).
- [x] **AC-5 (Progressive Disclosure & Situative `.agent-state.json`)**: **Given** a regular single-thread run in `ask-control`, **When** transitioning between phases, **Then** **no** `.agent-state.json` is written and implementation files are read in full only when directly modified by the active `AC-*` (inspecting signatures via `get-code-outline` beforehand); **only** on Circuit-Breaker Level 3 (*Context Purge*) or an explicit Copilot thread switch is `.agent-state.json` created in the scratch/temp directory.
- [x] **AC-6 (Regression Evals)**: **Given** new benchmark cases in `evals/eval-cases.json` for `AC-*` traceability, diff-size warning, Zero-Trust Diff-Report, and situative `.agent-state.json`, **When** `scripts/run-evals.ps1` / `.sh` and `scripts/test-skills.ps1` / `.sh` are executed, **Then** 100% of checks pass without errors and with full cross-file synchronization.

---

## 4. Non-Goals / Out of Scope
Explicitly bound the feature scope to prevent scope creep:
- Permanent `HANDOVER.md` after every phase within the same thread (violates KV-cache continuity and anti-ceremony).
- Language-agnostic regex mutation testing in the Stage-1 fast-gate (high runtime and false-positive risk).
- Mandatory fresh-context subagent review (`ask-troubleshooter` remains on-demand in Profile B/C).
- Hard blocking on diff-size threshold exceedance (remains a warning per `Q-1`).

---

## 5. Architecture & Technical Constraints
- **Target Module / Layer**: Deterministic Script Toolkit (`scripts/`) + Governance Contracts ([AGENTS.md](../../AGENTS.md), [ask-control](../../skills/ask-control/SKILL.md)) + Eval Harness ([eval-cases.json](../../evals/eval-cases.json))
- **Clean Architecture Boundaries**: All deterministic checks remain stateless and language-agnostic in `scripts/` with strict parity between PowerShell (`.ps1`) and Bash (`.sh`).
- **Safety Invariants**: Scripts do not modify host repository files; `.agent-state.json` is stored exclusively in the scratch/temp directory to avoid Git noise.
- **Data Model & Contracts**:
  - `run-fast-gate.ps1` / `.sh` JSON output remains backward-compatible (`status`, `failed_step`, `duration_ms`, `bypassed_code_gate`, `errors`, optional `warnings`).
  - `.agent-state.json` (Scratch): compact JSON with `decisions`, `touched_files`, `open_ac_ids`, `constraints`.

---

## 6. Implementation & Phasing Details
- **Phase**: `1` (Dynamic Project Extension)
- **Estimated Complexity**: `Profile B (Standard)`
- **Prerequisites / Dependencies**: `FEAT-GOV-001`, `FEAT-TOOL-001`, `FEAT-SPEC-001`

---

## 7. Traceability & Verification
- **Target Test Suite**: `scripts/test-skills.ps1`, `scripts/run-evals.ps1`, `scripts/lint-docs.ps1`
- **Test Types**: Deterministic script invariant tests, cross-file sync check, eval-harness regression tests
- **Associated Commits / PRs**: `<Filled upon implementation>`

---

## 8. Revision & Delta History
Atomic change log for this specific feature document (avoids full-document diffing):

| Date | Version / Status | Nature of Change | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-11-24 | `PROPOSED` | Distilled from `CONCEPT-GOV-001` (including resolved decisions Q-1, Q-2, Q-3) | User / Agent |
