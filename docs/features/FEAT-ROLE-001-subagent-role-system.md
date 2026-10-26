# Feature Specification: Specialized Subagent Role System

```yaml
---
id: FEAT-ROLE-001
title: "Specialized Subagent Role System"
phase: 0
status: VERIFIED
target_release: "v0.1.0"
scope: "ROLES"
depends_on: ["FEAT-GOV-001"]
---
```

> **Specification Path**: `docs/features/FEAT-ROLE-001-subagent-role-system.md`  
> **Parent Hub / Index**: `docs/ROADMAP.md`

## 1. Executive Summary & Objective
Provides the V2 Architecture: 1 Unified Core Lifecycle Engineer (`ask-control`) and 4 On-Demand Specialist Capability Packs (`ask-troubleshooter`, `ask-git-troubleshooter`, `ask-contract-specialist`, `ask-release-manager`). Each role defines unambiguous frontmatter, argument handling, calibrated cognitive tiers, and specialized execution rules.

---

## 2. User Story
> **As an** AI pair-programmer,  
> **I want** modular role specifications with strict separation of concerns,  
> **so that** tasks are executed with domain-expert depth while keeping prompt context isolated and clean.

---

## 3. Acceptance Criteria (Given-When-Then)
- [x] **AC-1**: **Given** all 5 skills in `skills/`, **When** validated by the testing suite, **Then** all directories contain a valid `SKILL.md` with proper YAML frontmatter (`name`, `description`).
- [x] **AC-2**: **Given** specialized tasks (such as i18n, DB migrations, or Git conflicts), **When** triggered, **Then** engage corresponding specialists on-demand without imposing serial overhead on unaffected commits.
- [x] **AC-3**: **Given** model allocations, **When** roles are dispatched, **Then** map roles to cost-efficient models according to `rules/model-tiers.json`.

---

## 4. Non-Goals / Out of Scope
- Mandatory execution of all roles on every commit (anti-ceremony invariant).

---

## 5. Architecture & Technical Constraints
- **Role Specifications**: Located in `skills/<role-name>/SKILL.md`.
- **Model Registration**: All 5 roles registered in `rules/model-tiers.json`.
- **Ghost Role Invariant**: Zero references to deprecated roles.

---

## 6. Implementation & Phasing Details
- **Phase**: `0 (Baseline)`
- **Complexity**: `Profile B (Standard)`
- **Prerequisites**: `FEAT-GOV-001`.

---

## 7. Traceability & Verification
- **Test Suite**: `scripts/test-skills.ps1` (Suites 1–3)
- **Status**: Verified 100% pass across all 23 roles.

---

## 8. Revision & Delta History
| Date | Version / Status | Nature of Change | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-10-24 | `VERIFIED` | Baseline freeze of 23 specialized subagent roles | User / Antigravity |
