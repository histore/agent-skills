# Project Roadmap & Living Feature Index (`ROADMAP.md`)

> **Role**: Central Hub, Phase Registry, and Lazy-Loading Gateway.  
> **Protocol**: Downstream agents and developers read this lightweight index first to identify relevant features. Individual feature specifications are loaded **lazily and on-demand** to conserve tokens and prevent full-corpus diff thrashing.

---

## 1. Execution Phases

- **Phase 1: Foundation & Core Domain**: Minimal viable architecture, essential domain contracts, and baseline persistence.
- **Phase 2: Core Feature Set**: Primary application workflows, service interfaces, and user journeys.
- **Phase 3: Integrations & Extensions**: External delivery drivers, third-party adapters, and advanced tooling.
- **Phase 4: Hardening & Performance**: Security audits, stress testing, zero-allocation optimization, and release candidate.

---

## 2. Feature Registry & Lifecycle Tracker

Zero-token inspection and scaffolding can be performed via:
```powershell
pwsh -NoProfile -File ./scripts/inspect-feature-specs.ps1 -Phase 1
```

| Phase | Feature ID | Title | Status | Scope | Specification File | Target Release |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| Phase 1 | `FEAT-CORE-001` | Domain Model Baseline | APPROVED | `CORE` | `docs/features/FEAT-CORE-001-domain-baseline.md` | `v0.1.0` |
| Phase 1 | `FEAT-AUTH-001` | Password Authentication | PROPOSED | `AUTH` | `docs/features/FEAT-AUTH-001-password-auth.md` | `v0.1.0` |
| Phase 2 | `FEAT-BILL-001` | Stripe Payment Gateway | PLANNED | `BILLING` | `docs/features/FEAT-BILL-001-stripe-gateway.md` | `v0.2.0` |

---

## 3. Phased Implementation Progress

- **Total Features Registered**: 3
- **Completed / Verified**: 0
- **In Progress**: 0
- **Approved / Ready**: 1
- **Proposed / Under Review**: 2

---

## 4. Context Isolation & Lazy Loading Guidelines

1. **Never parse all feature files at once**: Agents must read this `ROADMAP.md` table to resolve the exact file path for the active task.
2. **Atomic Updates**: When adding a new feature, author a new isolated file in `docs/features/` and append a single line to the table above. Do NOT modify unrelated feature documents.
3. **Phase-Gated Execution**: Only features marked for the active phase should be loaded or tackled during an iteration.
