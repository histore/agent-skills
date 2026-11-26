---
applyTo: "docs/concepts/**/*.md"
description: "Mandatory schema, template sections, and dual-track lifecycle rules for Concept Drafts (loaded only when editing concept docs)."
---

# Concept Draft Governance (Mandatory Schema)

Whenever authoring or updating a concept in `docs/concepts/drafts/`, strictly follow `.agents/docs/templates/CONCEPT_TEMPLATE.md` (fallback `~/.agents/docs/templates/CONCEPT_TEMPLATE.md` or `docs/templates/CONCEPT_TEMPLATE.md`).

## Scaffolding & Zero-Test Guardrail
- Always scaffold deterministically via:
  `pwsh -NoProfile -File ./.agents/scripts/inspect-feature-specs.ps1 -NewConcept -ConceptId "CONCEPT-<SCOPE>-XXX" -Title "<Title>" -Scope "<SCOPE>"`
  (Bash: `./.agents/scripts/inspect-feature-specs.sh --new-concept ...`).
- **Zero-Test Concept Guardrail**: Never execute compilers, test runners, formatters, or `run-fast-gate` while authoring or refining concept drafts.

## Mandatory Sections (Free-Form Concepts Are Strictly Prohibited)
1. YAML Frontmatter (`id`, `title`, `status: DRAFT`, `scope`, `target_feature`, `author`, `created`)
2. `## 1. Problem Statement & Motivation` (Context, need, desired outcome)
3. `## 2. Solution Approaches & Trade-Offs` (Recommended vs. alternative with pros/cons)
4. `## 3. High-Level Architecture & Clean Architecture Boundaries` (Layering, invariants, safe Rust)
5. `## 4. Phased Implementation Plan` (Phases 1-3 with Scope, Target Features, Exit Criteria/DoD)
6. `## 5. Open Questions, Edge Cases & Clarifications (Review Checklist)`
7. `## 6. Distillation Target & Proposed Acceptance Criteria Preview` (Given-When-Then criteria)
8. `## 7. Revision & Discussion History`

## Dual Lifecycle Tracks
1. **Track A (`concept > req > impl`)**: Distill approved draft into `docs/features/FEAT-<SCOPE>-XXX-<slug>.md` (escalate contradictions to user) and archive via `-ArchiveConcept` to `docs/concepts/archive/`. Downstream implementation reads only `FEAT-*.md`.
2. **Track B (`concept > impl`)**: Approved draft serves directly as working contract, is archived to `docs/concepts/archive/`, and implemented via Developer Inner-Loop TDD.
