# Feature Specification: `Android & Kotlin Toolchain Guardrails`

```yaml
---
id: FEAT-TOOL-002
title: "Android & Kotlin Toolchain Guardrails"
phase: 1
status: IMPLEMENTED # PROPOSED | APPROVED | IN_PROGRESS | IMPLEMENTED | VERIFIED | DEPRECATED
target_release: "v0.4.0"
scope: "TOOLING" # e.g. AUTH, CORE, UI, API, STORAGE
depends_on: ["FEAT-TOOL-001", "FEAT-GOV-002"]
---
```

> **Specification Path**: `docs/features/FEAT-TOOL-002-android-kotlin-guardrails.md`  
> **Parent Hub / Index**: [ROADMAP.md](../ROADMAP.md)

This document is an **isolated, living feature specification**. It is authored incrementally, updated in-place without rewriting the rest of the documentation, and loaded lazily by AI agents to keep token usage minimal.

---

## 1. Executive Summary & Objective
Extends the deterministic zero-token script toolkit (`scripts/`) and Clean Architecture rules (`rules/clean-architecture.json`) with first-class **Kotlin and Android (AGP, `ContentProvider`, Jetpack Compose)** support. Eliminates existing blind spots in static analysis, AST outlining, test/coverage discovery, and cross-file contract verification so cost-efficient workhorse models (e.g., `MAI Code 2` at `medium` reasoning) can implement multi-module Android features safely without silent runtime regressions.

---

## 2. User Story
> **As a** developer and orchestrator working across an Android ecosystem (Jetpack Compose framework, `ContentResolver`/`Flow` client library, and `ContentProvider` host app),  
> **I want** deterministic Stage-1 guardrails for Kotlin Clean Architecture, AGP Gradle tasks, `Cursor`-leak prevention, `notifyChange()` invariants, and Compose `testTag`/URI contract consistency,  
> **so that** AI-driven Inner-Loop TDD catches Android-specific silent bugs at zero LLM token cost before Stage-2 review.

---

## 3. Acceptance Criteria (Given-When-Then)
Each acceptance criterion must be verifiable and formulated using Arrange-Act-Assert / Given-When-Then:

- [x] **AC-1 (Android Gradle Plugin Stack Detection)**: **Given** a Gradle project containing `com.android.application` or `com.android.library` in `build.gradle(.kts)` or `libs.versions.toml`, **When** `scripts/detect-tech-stack.ps1` / `.sh` runs, **Then** it emits Android-compatible Gradle tasks (`compileDebugUnitTestKotlin` / `testDebugUnitTestClasses` for `build_cmd`, `testDebugUnitTest` for `test_cmd`, and `testDebugUnitTest --tests {filter}` for `test_filter_syntax` with `-x spotlessCheck -q` when Spotless is configured) and optionally populates `lint_cmd` (`lintDebug -q`).
- [x] **AC-2 (Kotlin Clean Architecture & Android Layer Rules)**: **Given** Kotlin/Java source files (`.kt`, `.kts`, `.java`) in `domain/` or `application/` layers importing forbidden Android framework packages (`android.*`, `androidx.compose.*`, `android.content.ContentProvider`, `android.database.Cursor`), **When** `scripts/lint-clean-architecture.ps1` / `.sh` runs against [clean-architecture.json](../../rules/clean-architecture.json), **Then** `.kt`/`.kts`/`.java` files are scanned (including `fun`, `suspend fun`, and `@Composable fun` declarations) and illegal layer imports fail with exit code `1`.
- [x] **AC-3 (Kotlin AST Signature Outlining)**: **Given** `.kt` source files in an Android module, **When** `scripts/get-code-outline.ps1` / `.sh` is invoked, **Then** it extracts `class`, `data class`, `sealed class`, `interface`, `object`, `enum class`, `fun`, `suspend fun`, and `@Composable` signatures without loading function bodies into LLM context.
- [x] **AC-4 (Fast-Gate Android Manifest & Test Discovery)**: **Given** working-tree changes to `AndroidManifest.xml` (or `src/androidTest/` / `*Test.kt` test files), **When** `scripts/run-fast-gate.ps1` / `.sh` executes, **Then** `AndroidManifest.xml` changes do not trigger `bypassed_code_gate = true`, and the `AC-*` traceability check discovers test files matching `src[\\/](test|androidTest)[\\/]` as well as `*Test.kt` / `*Test.java`.
- [x] **AC-5 (Gradle JUnit XML & JaCoCo Discovery)**: **Given** Android Gradle test or coverage artifacts under `**/build/test-results/**/*.xml` or `**/build/reports/jacoco/**/*.xml`, **When** `scripts/collect-test-failures.ps1` / `.sh` or `scripts/check-test-coverage.ps1` / `.sh` executes without explicit `-ResultsPath` / `-ReportPath`, **Then** the artifacts are auto-discovered and parsed accurately into compact JSON diagnostics or coverage percentages.
- [x] **AC-6 (Deterministic Android Contract & Resource Guardrails)**: **Given** modified `.kt` files in the working tree implementing a `ContentProvider`, calling `contentResolver.query(` / `.rawQuery(`, or defining `@Composable` UI components, **When** `scripts/lint-android-contracts.ps1` / `.sh` (invoked by `run-fast-gate` when Android/Kotlin is detected) runs, **Then** it deterministically flags: (a) unclosed `Cursor` queries missing `.use {` or `try`/`finally { ... close() }`, (b) modified `ContentProvider` `insert`/`update`/`delete` overrides missing a `notifyChange(` call in the same file, (c) newly added `UriMatcher.addURI(...)` / URI constants not referenced in both a client wrapper and a `*Test.kt` file, and (d) public `@Composable` components missing a `Modifier` parameter.
- [x] **AC-7 (Cross-Script Parity & Regression Evals)**: **Given** updated scripts (`.ps1` and `.sh` parity) and new Android/Kotlin test fixtures in `evals/eval-cases.json`, **When** `scripts/test-skills.ps1` / `.sh` and `scripts/run-evals.ps1` / `.sh` run, **Then** 100% of cross-file synchronization, script parity, and regression eval checks pass.

---

## 4. Non-Goals / Out of Scope
Explicitly bound the feature scope to prevent scope creep:
- Executing full Android Instrumentation tests (`connectedDebugAndroidTest`) on emulators/devices inside Stage-1 Fast-Gate (remains restricted to JVM/Robolectric unit tests for sub-minute inner-loop speed).
- Full Kotlin compiler AST parsing (`kotlinc` / PSI plugin dependency); all scripts remain zero-dependency PowerShell/Bash regex & structural scanners.
- Automatic refactoring or fixing of `Cursor` leaks or missing `notifyChange()` calls (guardrails report violations; the agent fixes them in Inner-Loop TDD).

---

## 5. Architecture & Technical Constraints
- **Target Module / Layer**: Deterministic Script Toolkit ([scripts/](../../scripts/)) + Governance Rules ([clean-architecture.json](../../rules/clean-architecture.json)) + Eval Harness ([eval-cases.json](../../evals/eval-cases.json))
- **Clean Architecture Boundaries**: All checks remain stateless, host-project-agnostic, and strictly paired between PowerShell (`.ps1`) and Bash (`.sh`).
- **Safety Invariants**: Scripts never mutate host project source files during Stage-1 linting; OS-native line endings (`CRLF` on Windows, `LF` on Linux/macOS) are preserved.
- **Data Model & Contracts**:
  - `lint-android-contracts.ps1` / `.sh` supports `-WorkingTree`, `-ProjectRoot`, and `-JsonOutput` returning `{ status, scanned_files, errors, warnings }`.
  - `run-fast-gate.ps1` / `.sh` preserves backward-compatible JSON output (`status`, `failed_step`, `duration_ms`, `bypassed_code_gate`, `errors`, `warnings`).

---

## 6. Implementation & Phasing Details
- **Phase**: `1` (Dynamic Project Extension)
- **Estimated Complexity**: `Profile B (Standard)`
- **Prerequisites / Dependencies**: `FEAT-TOOL-001`, `FEAT-GOV-002`

---

## 7. Traceability & Verification
- **Target Test Suite**: `scripts/test-skills.ps1`, `scripts/run-evals.ps1`, `evals/eval-cases.json`
- **Test Types**: Deterministic script invariant tests, `.ps1`/`.sh` parity checks, synthetic Android/Kotlin fixture evals (AAA pattern)
- **Associated Commits / PRs**: `<Filled upon implementation>`

---

## 8. Revision & Delta History
Atomic change log for this specific feature document (avoids full-document diffing):

| Date | Version / Status | Nature of Change | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-11-25 | `PROPOSED` | Initial feature specification derived from Android (`ContentProvider` / Compose) & Copilot CLI audit | User / Agent |
