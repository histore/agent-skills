# System Architecture Baseline: Agent Skills Toolkit

> **Status**: APPROVED  
> **Last Synchronized**: 2026-10-24  
> **Governance Authority**: `AGENTS.md`  

This document describes the architectural baseline of the **Agent Skills Toolkit**, providing specialized subagent roles, adaptive execution pipelines, deterministic zero-token helper scripts, and automated quality gates for Google Antigravity and GitHub Copilot.

---

## 1. Clean Architecture & Layered Organization

The toolkit is structured in strict accordance with Clean Architecture principles:

```text
+---------------------------------------------------------------+
| Layer 1: Governance & Rules (AGENTS.md, rules/, .github/)     |
|   - Adaptive Execution Profiles (0, A, B, C)                  |
|   - Dynamic Model Allocation & Quota Protection Gate          |
|   - Safe-Rust Invariants & Anti-Ceremony Guardrails           |
+-------------------------------+-------------------------------+
                                |
                                v
+---------------------------------------------------------------+
| Layer 2: Specialized Subagent Roles (skills/*/SKILL.md)       |
|   - Core Lifecycle (Control, Requirements, Architecture, TDD) |
|   - On-Demand Specialists (Troubleshooter, Reviewer, etc.)    |
|   - Domain Specialists (Security, DB, API, i18n, UX, Perf)    |
+-------------------------------+-------------------------------+
                                |
                                v
+---------------------------------------------------------------+
| Layer 3: Deterministic Zero-Token Tooling (scripts/*.ps1, .sh)|
|   - Native Quality Gates & Fast Validation                    |
|   - Link, Clean Architecture & Requirements Linters           |
|   - Feature Spec Inspector, Scaffolding & State Drift Hash    |
+-------------------------------+-------------------------------+
                                |
                                v
+---------------------------------------------------------------+
| Layer 4: Evaluation & Observability (evals/, telemetry)       |
|   - 9 Synthetic Scenario Benchmarks (eval-cases.json)         |
|   - Local Telemetry Logging & Reporting                       |
+---------------------------------------------------------------+
```

---

## 2. Core Subsystems

### 2.1 Governance & Adaptive Execution Engine
- **Single Source of Truth**: `rules/model-tiers.json` defines all 5 roles across cognitive tiers (Eco, Balanced, Premium).
- **Execution Profiles**:
  - `Profile 0 (Direct Response)`: Informational only; zero git/test operations.
  - `Profile A (Fast-Track)`: Bug fixes and small tweaks; targeted Inner-Loop TDD; 70–80% token savings.
  - `Profile B (Standard)`: Architectural contract -> Inner-Loop TDD -> Verification Quality Gate.
  - `Profile C (Complex)`: Deep architectural analysis, integration testing, modular contracts, subject to Quota Protection User Gate.

### 2.2 Role Catalog (5 Consolidated Capability Packs)
- **Core Lifecycle**: `ask-control` (Unified Core Lifecycle Engineer & Orchestrator: Planning, Contracts, Inner-Loop TDD, Two-Stage Quality Gate, Lifecycle Git).
- **On-Demand Specialist Capability Packs**:
  - `ask-troubleshooter`: Systematic Diagnostics, Bug RCA, Reproduction Tests, Adversarial Code Review, Fowler Refactoring, Performance Profiling.
  - `ask-git-troubleshooter`: Git Safety, Merge/Rebase Conflict Resolution, Reflog Recovery, Safety Backups.
  - `ask-contract-specialist`: Living Feature Specifications, Concept Tracks, Requirements Governance, API Contracts, DB Migrations, Architecture Sync, i18n.
  - `ask-release-manager`: Release Automation, SemVer Bump Calculation, Changelog Generation, CI/CD Workflows, Security CVE Audits, Git Release Tags.

### 2.3 Living Modular Documentation & Lazy Loading
- **Hub-and-Spoke Pattern**: Central `docs/ROADMAP.md` acts as the lightweight registry.
- **Atomic Feature Specs**: Individual feature documents live in `docs/features/FEAT-*.md`.
- **Lazy Loading**: AI agents read only the central roadmap index first, loading solely the active feature spec into context.
- **Hash-Based State Tracking**: `docs/.spec-state.json` tracks SHA-256 hashes of all feature documents, eliminating redundant file parsing.

### 2.4 Deterministic Zero-Token Script Toolkit
- Over 20 dual-platform script pairs (`.ps1` and `.sh`) that execute natively without consuming LLM tokens:
  - Fast-Gate & Tech Stack detection (`detect-tech-stack`, `run-fast-gate`)
  - Architectural & code linters (`lint-clean-architecture`, `lint-docs`, `scan-guardrails`)
  - SemVer and release calculators (`calculate-semver`, `generate-changelog`)
  - Living specs inspector & scaffolding (`inspect-feature-specs`)
  - Unified quality gates runner (`run-all-gates`)

---

## 3. Architectural Decisions (ADR), Evidence-Based Evolution & Anti-Churn Policy

1. **Structural Baseline Saturation (`1 + 4` V2 Invariant)**:
   - The consolidation into **1 Unified Core Engineer (`ask-control`) + 4 On-Demand Specialist Capability Packs** (`ask-troubleshooter`, `ask-git-troubleshooter`, `ask-contract-specialist`, `ask-release-manager`) is an intentional, permanent architectural decision optimized for modern LLM context windows and KV-cache prefix reuse.
   - Internal execution phases (`Architekt`, `Developer`, `Tester`, `Verifikation`, `CommitManager`) are **in-thread persona phases** within `ask-control` and must **never** be split back into standalone `SKILL.md` directories.
2. **Evidence-Based LLM Behavioral Evolution (Allowed & Desired)**:
   - The toolkit actively evolves when **real LLM behaviors, model generations, or client platform capabilities change** (e.g., updating model catalogs and reasoning budgets in `rules/model-tiers.json`, refining prompt guardrails against newly observed LLM failure modes, or adapting to new IDE/CLI tool APIs).
3. **Prohibition of Speculative Structural Churn (No Action-Bias Overhauls)**:
   - When asked to review or audit this package, AI agents must **not** invent speculative structural reorganizations, role splits, or new capability packs merely out of conversational "suggestion bias".
   - If `scripts/test-skills.ps1` and `scripts/run-evals.ps1` pass 100% and no concrete LLM behavioral issue or platform change is present, the agent must confirm that the structural baseline is **saturated and consistent**, proposing changes strictly where empirical LLM behavior or explicit user requirements justify them.
4. **100% Cross-File SSOT Synchronization Gate**:
   - Any adaptation to roles, skills, or governance rules must update all affected files atomically and pass the dynamic Single-Source-of-Truth (SSOT) check in `scripts/test-skills.ps1` (zero orphan `ask-*` references, zero legacy V1 role names across all repository files).
