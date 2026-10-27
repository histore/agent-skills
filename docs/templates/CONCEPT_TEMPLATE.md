# Concept & RFC Draft: `<Concept Title>`

```yaml
---
id: CONCEPT-<SCOPE>-XXX
title: "<Concept Title>"
status: DRAFT # DRAFT | UNDER_REVIEW | APPROVED | ARCHIVED
scope: "<SCOPE>" # e.g. AUTH, CORE, UI, API, STORAGE
target_feature: "FEAT-<SCOPE>-XXX"
author: "<Author>"
created: "<YYYY-MM-DD>"
---
```

> **Concept Path**: `docs/concepts/drafts/CONCEPT-<SCOPE>-XXX-<slug>.md`  
> **Lifecycle**: Draft / Under Review $\rightarrow$ Distill to `docs/features/FEAT-<SCOPE>-XXX.md` $\rightarrow$ Archive to `docs/concepts/archive/`

---

## 1. Problem Statement & Motivation
- **Context & Need**: `<What problem does this solve? What is the current limitation or business need?>`
- **Desired Outcome**: `<What does success look like once this concept is realized?>`

---

## 2. Solution Approaches & Trade-Offs
Compare viable approaches before solidifying requirements:

### Approach A (Recommended)
- **Description**: `<Summary of primary approach>`
- **Pros**:
  - `<Advantage 1>`
  - `<Advantage 2>`
- **Cons / Risks**:
  - `<Trade-off or complexity factor>`

### Approach B (Alternative)
- **Description**: `<Summary of alternative approach>`
- **Pros / Cons**: `<Why was this deferred or rejected in favor of A?>`

---

## 3. High-Level Architecture & Clean Architecture Boundaries
- **Target Schicht / Layer**: Domain Core | Application Contracts | Adapters | Infrastructure
- **Clean Architecture Invariants**: Core logic remains independent of external frameworks and drivers.
- **Safety Invariants**: In Rust codebases, `unsafe` blocks are strictly forbidden.
- **Data Flow & Components**: `<Key interfaces, interactions, and data contracts>`

---

---

## 4. Phased Implementation Plan (Phasenweise Umsetzung)
Structure implementation into incremental, independently testable phases to reduce risk and ensure verifiable milestones:

### Phase 1: Foundation & Core Contracts (MVP)
- **Scope & Deliverables**: `<Domain entities, contracts/interfaces, core business logic, initial unit tests>`
- **Target Feature(s)**: `FEAT-<SCOPE>-001`
- **Exit Criteria / DoD**: `<Core unit tests passing 100%, fast-gate clean>`

### Phase 2: Feature Integration & Adapters
- **Scope & Deliverables**: `<Adapters, external drivers, UI/CLI integration, integration tests>`
- **Target Feature(s)**: `FEAT-<SCOPE>-002`
- **Exit Criteria / DoD**: `<Integration tests green, end-to-end data flow verified>`

### Phase 3: Rollout, Migration & Hardening
- **Scope & Deliverables**: `<Migrations, telemetry, performance optimization, documentation, release tagging>`
- **Target Feature(s)**: `FEAT-<SCOPE>-003`
- **Exit Criteria / DoD**: `<Full regression passed, zero broken links/docs, user sign-off>`

---

## 5. Open Questions, Edge Cases & Clarifications (Review Checklist)
Items requiring user clarification or design decision before distillation:
- [ ] **Q-1**: `<Open question regarding ambiguous business logic or boundary condition>`
- [ ] **Q-2**: `<Trade-off decision requiring user confirmation>`
- [ ] **Q-3**: `<Integration point or dependency constraint>`

---

## 6. Distillation Target & Proposed Acceptance Criteria Preview
Preliminary preview of acceptance criteria to be extracted into `docs/features/FEAT-<SCOPE>-XXX.md`:
- **Preview AC-1 (Happy Path)**: Given `<precondition>`, When `<trigger>`, Then `<result>`.
- **Preview AC-2 (Boundary / Error Case)**: Given `<invalid input>`, When `<action>`, Then `<graceful error>`.

---

## 7. Revision & Discussion History
| Date | Status | Changes & Decision Notes | Author / Approver |
| :--- | :--- | :--- | :--- |
| <YYYY-MM-DD> | `DRAFT` | Initial concept outline | User / Agent |
