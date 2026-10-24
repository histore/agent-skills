# Feature Specification: Deterministic Zero-Token Script Toolkit

```yaml
---
id: FEAT-TOOL-001
title: "Deterministic Zero-Token Script Toolkit"
phase: 0
status: VERIFIED
target_release: "v0.1.0"
scope: "TOOLING"
depends_on: ["FEAT-GOV-001"]
---
```

> **Specification Path**: `docs/features/FEAT-TOOL-001-zero-token-scripts.md`  
> **Parent Hub / Index**: `docs/ROADMAP.md`

## 1. Executive Summary & Objective
Implements dual-platform deterministic scripts (`.ps1` for PowerShell on Windows, `.sh` for Bash on Linux/macOS) that offload mechanical checks, validation gates, SemVer calculations, and linters from LLM tokens to native shell execution.

---

## 2. User Story
> **As a** developer or agent,  
> **I want** native scripts to perform fast-gate checks, linting, and telemetry,  
> **so that** LLM tokens are not wasted on mechanical code checks or parsing tasks.

---

## 3. Acceptance Criteria (Given-When-Then)
- [x] **AC-1**: **Given** any script in `scripts/`, **When** inspected, **Then** both PowerShell (`.ps1`) and Bash (`.sh`) equivalents exist with identical parameter interfaces.
- [x] **AC-2**: **Given** code modifications, **When** validating quality gates, **Then** `run-fast-gate.ps1` checks compilation and tests with 0 errors before LLM semantic analysis.
- [x] **AC-3**: **Given** clean architecture boundaries, **When** audited, **Then** `lint-clean-architecture.ps1` validates layer dependency rules against `rules/clean-architecture.json`.
- [x] **AC-4**: **Given** all repository files, **When** scanned by `scan-guardrails.ps1`, **Then** enforce LF line endings, absence of hardcoded secrets, and no unsafe Rust code.

---

## 4. Non-Goals / Out of Scope
- Running heavy test runners on pure markdown or documentation changes.

---

## 5. Architecture & Technical Constraints
- **Script Directory**: `scripts/`.
- **PowerShell Standard**: `-NoProfile` flag, LF line endings, robust error handling.
- **Unified Orchestrator**: `scripts/run-all-gates.ps1`.

---

## 6. Implementation & Phasing Details
- **Phase**: `0 (Baseline)`
- **Complexity**: `Profile B (Standard)`
- **Prerequisites**: `FEAT-GOV-001`.

---

## 7. Traceability & Verification
- **Test Suite**: `scripts/test-skills.ps1` (Suites 4–41)
- **Status**: Verified 100% pass across all tooling suites.

---

## 8. Revision & Delta History
| Date | Version / Status | Nature of Change | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-10-24 | `VERIFIED` | Baseline freeze of zero-token script infrastructure | User / Antigravity |
