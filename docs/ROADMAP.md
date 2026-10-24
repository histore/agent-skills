# Project Roadmap & Living Feature Index (`docs/ROADMAP.md`)

> **System Baseline**: Agent Skills Toolkit  
> **Architecture Specification**: [ARCHITECTURE.md](../ARCHITECTURE.md)  
> **Status Registry**: Phase 0 Baseline is **VERIFIED** and frozen via `docs/.spec-state.json`.

---

## 1. Execution Phases

- **Phase 0: Baseline Architecture & Tooling (VERIFIED)**:
  - Core Governance, Dynamic Model Allocation & Adaptive Execution Profiles
  - Complete 23-Role Specialized Catalog (Core Lifecycle, Lifecycle Specialists, Domain Specialists)
  - Deterministic Zero-Token Script Toolkit & Quality Gate Orchestration
  - Living Modular Documentation, Lazy Loading & Hash-Based Spec Freeze
- **Phase 1: Dynamic Project Extension (PLANNED)**:
  - Additional Domain Specialist integrations
  - Automated project onboarding wizards

---

## 2. Feature Registry & Lifecycle Tracker

Zero-token phase inspection and scaffolding:
```powershell
pwsh -NoProfile -File ./scripts/inspect-feature-specs.ps1 -Phase 0
```

| Phase | Feature ID | Title | Status | Scope | Specification File | Target Release |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Phase 0 | `FEAT-GOV-001` | Governance & Adaptive Orchestration Engine | VERIFIED | `GOV` | [features/FEAT-GOV-001-governance-and-orchestration.md](features/FEAT-GOV-001-governance-and-orchestration.md) | `v0.1.0` |
| Phase 0 | `FEAT-ROLE-001` | Specialized Subagent Role System | VERIFIED | `ROLES` | [features/FEAT-ROLE-001-subagent-role-system.md](features/FEAT-ROLE-001-subagent-role-system.md) | `v0.1.0` |
| Phase 0 | `FEAT-TOOL-001` | Deterministic Zero-Token Script Toolkit | VERIFIED | `TOOLING` | [features/FEAT-TOOL-001-zero-token-scripts.md](features/FEAT-TOOL-001-zero-token-scripts.md) | `v0.1.0` |
| Phase 0 | `FEAT-SPEC-001` | Living Modular Documentation & Phased Specs | VERIFIED | `SPEC` | [features/FEAT-SPEC-001-living-modular-docs.md](features/FEAT-SPEC-001-living-modular-docs.md) | `v0.1.0` |

---

## 3. Implementation Progress Summary

- **Total Features Registered**: 4
- **Completed & Verified (Phase 0 Baseline)**: 4 (100%)
- **In Progress**: 0
- **Proposed / Planned (Phase 1)**: 0

---

## 4. Context Isolation & Lazy Loading Guidelines

1. **Lazy Loading**: AI agents and tools must read this `ROADMAP.md` table first to resolve the specific feature file needed for a task. Never load all feature files simultaneously.
2. **Append-Only Growth**: When proposing a new feature for Phase 1, create a new isolated document `docs/features/FEAT-<SCOPE>-XXX-<slug>.md` and append a single row to the table above.
3. **State Checkpointing**: Persist state freezes using:
   ```powershell
   pwsh -NoProfile -File ./scripts/inspect-feature-specs.ps1 -CheckDrift -UpdateState
   ```
