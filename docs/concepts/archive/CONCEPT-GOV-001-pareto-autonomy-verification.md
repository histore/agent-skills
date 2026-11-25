# Concept & RFC Draft: `Pareto Autonomy & Deterministic Verification`

```yaml
---
id: CONCEPT-GOV-001
title: "Pareto Autonomy & Deterministic Verification"
status: ARCHIVED # DRAFT | UNDER_REVIEW | APPROVED | ARCHIVED
scope: "GOV"
target_feature: "FEAT-GOV-002"
author: "User / Agent"
created: "2026-11-24"
---
```

> **Concept Path**: `docs/concepts/archive/CONCEPT-GOV-001-pareto-autonomy-verification.md`  
> **Lifecycle**: Draft / Under Review $\rightarrow$ Distill to `docs/features/FEAT-GOV-002-pareto-autonomy-verification.md` $\rightarrow$ Archive to `docs/concepts/archive/`

---

## 1. Problem Statement & Motivation
- **Context & Need**: To achieve maximum agentic autonomy without manual line-by-line reviews, minimal rework loops, and consistent result quality across platforms (Antigravity Multi-Agent + GitHub Copilot Sequential Persona), purely linguistic rules ("LLM appeals") are not enough. At the same time, new mechanisms must not violate KV-cache continuity (75–90% discount), inner-loop speed, or the Anti-Ceremony Guardrail from [AGENTS.md](../../../AGENTS.md).
- **Desired Outcome**: Introduce exclusively genuine **Pareto optimizations**—meaning deterministic script checks, compact output schemas, and situative context hygiene that measurably increase verification reliability and autonomy without causing additional token costs, latency spikes, or false-positive ceremony.

---

## 2. Solution Approaches & Trade-Offs
Compare viable approaches before solidifying requirements:

### Approach A (Recommended): Strict Pareto Optimizations (Zero-Token Gates + Situative Hygiene)
- **Description**: Implementation of 6 targeted, low-risk extensions in `scripts/`, `skills/ask-control/`, `AGENTS.md`, and `evals/`:
  1. **Deterministic `AC-*` Traceability Check** in `run-fast-gate.ps1`/`.sh` (active only when active feature specs with `AC-*` exist).
  2. **Diff-Size Guardrail** in `run-fast-gate.ps1`/`.sh` (`git diff --numstat` threshold warning/flag against sprawling edits).
  3. **Zero-Trust Diff-Report** as a compact Stage-2 completion format in `ask-control` (files, `AC-*` status, guardrails, open assumptions).
  4. **Stricter Progressive Disclosure Rule** (signatures via `get-code-outline` first; full read only on direct `AC-*` edits).
  5. **Situative `.agent-state.json`** exclusively on Context Purge (Circuit-Breaker Level 3) or explicit Copilot thread switch.
  6. **Regression Evals** in `evals/eval-cases.json` for real governance and autonomy failure classes.
- **Pros**:
  - Virtually 0 additional LLM tokens and < 20 ms added runtime in the fast-gate.
  - Full preservation of *Compound Phased Execution* and *Two-Zone Prompt Cache Architecture*.
  - Zero impact on Profile 0 / Profile A (Anti-Ceremony remains 100% intact).
- **Cons / Risks**:
  - Does not cover semantic logic bugs that lie *inside* passing alibi tests (mutation testing remains intentionally excluded / on-demand).
  - Cross-platform parity between `.ps1` and `.sh` must be maintained for new fast-gate checks.

### Approach B (Alternative): Maximum Verification with Non-Pareto Trade-Offs
- **Description**: Additional mandatory fresh-context subagent review (`ask-troubleshooter`) after every Profile-B/C task, regex mutation testing in the fast-gate, and permanent `HANDOVER.md` after every phase.
- **Pros / Cons**: Higher theoretical verification depth, but rejected because it breaks KV-cache reuse, significantly increases latency and token consumption, and leads to false positives and Git noise in the inner loop.

---

## 3. High-Level Architecture & Clean Architecture Boundaries
- **Target Layer**: Infrastructure / Deterministic Tooling (`scripts/`) + Governance Contracts (`AGENTS.md`, `skills/ask-control/SKILL.md`, `evals/eval-cases.json`)
- **Clean Architecture Invariants**: All deterministic checks live as language-agnostic, stateless scripts in `scripts/` (PowerShell `.ps1` + Bash `.sh` parity) and return compact JSON or single-line gate outputs without LLM dependencies.
- **Safety Invariants**: Scripts operate strictly read-only on the working tree (exception: explicitly situative `.agent-state.json` in the `.gitignore` / scratch area). Submodules (`_agents/`, `.agents/`) remain isolated.
- **Data Flow & Components**:
  - `docs/features/FEAT-*.md` (`AC-*` IDs) $\rightarrow$ `run-fast-gate.ps1/.sh` (regex traceability + `git diff --numstat` guardrail) $\rightarrow$ JSON/CLI status.
  - `run-fast-gate` + `git diff --stat` $\rightarrow$ `ask-control` Stage 2 $\rightarrow$ **Zero-Trust Diff-Report**.
  - Circuit-Breaker Level 3 / thread switch $\rightarrow$ `.agent-state.json` (compact state snapshot) $\rightarrow$ next thread.

---

## 4. Phased Implementation Plan

### Phase 1: Deterministic Fast-Gate Extensions (`AC-*` Traceability & Diff-Size Guardrail)
- **Scope & Deliverables**:
  - Extend `scripts/run-fast-gate.ps1` and `scripts/run-fast-gate.sh` with:
    1. `AC-*` traceability check (only when active/modified `docs/features/FEAT-*.md` with `AC-*` exist).
    2. `git diff --numstat` diff-size check (configurable threshold, e.g., 400 changed code lines).
  - Unit/smoke verification via `scripts/test-skills.ps1` / `scripts/run-evals.ps1`.
- **Target Feature(s)**: `FEAT-GOV-002`
- **Exit Criteria / DoD**: `.ps1` and `.sh` produce identical JSON schemas, Profile-A workflows without a feature spec are automatically bypassed, `test-skills.ps1` green.

### Phase 2: Governance, Output Schema & Context Hygiene (`ask-control` & `AGENTS.md`)
- **Scope & Deliverables**:
  - Integrate the compact **Zero-Trust Diff-Report** into Stage 2 of `skills/ask-control/SKILL.md`.
  - Clarify the **Progressive Disclosure Rule** in `AGENTS.md` and `skills/ask-control/SKILL.md` (full read only when directly affected by `AC-*`).
  - Define the situative **`.agent-state.json`** schema for Circuit-Breaker Level 3 and Copilot thread switches (including `.gitignore` recommendation).
- **Target Feature(s)**: `FEAT-GOV-002`
- **Exit Criteria / DoD**: Cross-file sync passes 100% via `scripts/test-skills.ps1`, zero contradictions with existing invariants.

### Phase 3: Regression Evals & Hardening
- **Scope & Deliverables**:
  - Add regression cases to `evals/eval-cases.json` for `AC-*` traceability, diff-size guardrail, Zero-Trust Diff-Report, and situative `.agent-state.json`.
  - Update `scripts/run-evals.ps1` / `scripts/run-evals.sh` if new invariant types must be verified.
- **Target Feature(s)**: `FEAT-GOV-002`
- **Exit Criteria / DoD**: `run-evals.ps1` and `test-skills.ps1` pass 100%, `lint-docs.ps1` reports 0 broken links.

---

## 5. Open Questions, Edge Cases & Clarifications (Resolved)
- [x] **Q-1 (Diff-Size Limit)**: **Warning** – Exceeding the diff-size limit (e.g., > 400 changed code lines) emits a warning in the fast-gate output and in the Zero-Trust Diff-Report (no hard fail).
- [x] **Q-2 (`AC-*` Traceability Strictness)**: **Option A (Stage-1 Fail)** – When an active feature spec (`FEAT-*.md` with `AC-*`) exists, missing test coverage sets `run-fast-gate` directly to `fail` (exit code `1`), ensuring the gap is mechanically blocked and cannot go unnoticed. In Profile A without a feature spec, the check is skipped.
- [x] **Q-3 (`.agent-state.json` Storage Location)**: **Scratch Directory** – Stored exclusively in the respective scratch/temp directory (no file in repo root, no Git noise).

---

## 6. Distillation Target & Proposed Acceptance Criteria Preview
Preliminary preview of acceptance criteria to be extracted into `docs/features/FEAT-GOV-002-pareto-autonomy-verification.md`:
- **Preview AC-1 (`AC-*` Traceability)**: Given an active or modified feature spec with `AC-1` and `AC-2`, When `run-fast-gate` is executed, Then the script checks via regex whether both IDs are referenced in test files and reports missing coverage compactly.
- **Preview AC-2 (Anti-Ceremony Bypass)**: Given a Profile-A bugfix without an active feature spec, When `run-fast-gate` is executed, Then the `AC-*` traceability check is skipped without overhead.
- **Preview AC-3 (Diff-Size Guardrail)**: Given more than the configured threshold of changed code lines in the working tree, When `run-fast-gate` runs, Then a clear diff-size warning/flag is emitted.
- **Preview AC-4 (Zero-Trust Diff-Report)**: Given completed Stage 1 in Profile B or C, When `ask-control` completes Stage 2, Then the compact risk matrix (files, `AC-*` status, guardrails, open assumptions) is output.
- **Preview AC-5 (Situative `.agent-state.json`)**: Given a regular single-thread run without Context Purge, When switching phases, Then **no** `.agent-state.json` is written (only on Circuit-Breaker Level 3 or thread switch).
- **Preview AC-6 (Regression Evals)**: Given the new eval cases in `evals/eval-cases.json`, When `run-evals.ps1` is executed, Then 100% of cases pass without errors.

---

## 7. Revision & Discussion History
| Date | Status | Changes & Decision Notes | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-11-24 | `DRAFT` | Created initial concept for the 6 Pareto optimizations | User / Agent |
| 2026-11-24 | `APPROVED` | Resolved and approved Q-1 (Warning), Q-2 (Option A: Stage-1 Fail), and Q-3 (Scratch directory) | User / Agent |
| 2026-11-24 | `ARCHIVED` | Distilled into `docs/features/FEAT-GOV-002-pareto-autonomy-verification.md` | User / Agent |
