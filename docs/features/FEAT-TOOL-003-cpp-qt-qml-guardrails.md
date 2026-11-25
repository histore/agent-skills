# Feature Specification: `C++ (MinGW / MSVC) & Qt / QtQuick (QML) Toolchain Guardrails`

```yaml
---
id: FEAT-TOOL-003
title: "C++ (MinGW / MSVC) & Qt / QtQuick (QML) Toolchain Guardrails"
phase: 1
status: IMPLEMENTED # PROPOSED | APPROVED | IN_PROGRESS | IMPLEMENTED | VERIFIED | DEPRECATED
target_release: "v0.4.0"
scope: "TOOLING" # e.g. AUTH, CORE, UI, API, STORAGE
depends_on: ["FEAT-TOOL-001", "FEAT-GOV-002"]
---
```

> **Specification Path**: `docs/features/FEAT-TOOL-003-cpp-qt-qml-guardrails.md`  
> **Parent Hub / Index**: [ROADMAP.md](../ROADMAP.md)

This document is an **isolated, living feature specification**. It is authored incrementally, updated in-place without rewriting the rest of the documentation, and loaded lazily by AI agents to keep token usage minimal.

---

## 1. Executive Summary & Objective
Extends the deterministic zero-token script toolkit (`scripts/`) and Clean Architecture rules ([clean-architecture.json](../../rules/clean-architecture.json)) with first-class support for **C++ (MinGW/GCC, MSVC, CMake/Ninja/CTest)** and **Qt / QtQuick / QML**. Eliminates silent failures around compiler/toolchain detection, header/QML dependency boundaries, Qt Meta-Object/signal-slot pitfalls, and QML/C++ contract mismatches during AI-assisted Inner-Loop TDD.

---

## 2. User Story
> **As a** developer and orchestrator working on C++ (MinGW / MSVC) and Qt / QtQuick (QML) applications,  
> **I want** deterministic Stage-1 toolchain detection, Clean Architecture `#include`/`import` checks, AST/QML signature outlining, and Qt/QML-specific contract guardrails,  
> **so that** AI agents catch broken `Q_OBJECT`/`Q_PROPERTY` declarations, legacy `SIGNAL()`/`SLOT()` macros, Qt6 QML regressions, and layer violations at zero LLM token cost.

---

## 3. Acceptance Criteria (Given-When-Then)
Each acceptance criterion must be verifiable and formulated using Arrange-Act-Assert / Given-When-Then:

- [x] **AC-1 (C++ MinGW / MSVC / CMake Toolchain Detection)**: **Given** a repository with `CMakeLists.txt`, `CMakePresets.json`, or `*.sln`/`*.vcxproj`, **When** `scripts/detect-tech-stack.ps1` / `.sh` runs, **Then** it detects the active C++ toolchain (`cmake-mingw`, `cmake-msvc`, or `msbuild`), emits quiet build (`cmake --build ...` / `msbuild -v:q`) and targeted test commands (`ctest --output-on-failure -R {filter}`), detects `clang-tidy` / `cppcheck` for `lint_cmd` when available, and configures `clang-format` for deferred formatting in `prepare-commit`.
- [x] **AC-2 (C++ & QML Clean Architecture Layer Rules)**: **Given** `.c`, `.cpp`, `.cc`, `.cxx`, `.h`, `.hpp`, `.hxx`, or `.qml` files in `domain/` or `application/` layers containing `#include` or QML `import` statements for UI/framework modules (`QtQuick`, `QtWidgets`, `QtQml`, `QQuickItem`, `QWidget`, `windows.h`), **When** `scripts/lint-clean-architecture.ps1` / `.sh` runs against [clean-architecture.json](../../rules/clean-architecture.json), **Then** it parses `#include` and QML `import` directives and fails with exit code `1` on layer boundary violations.
- [x] **AC-3 (C++ & QML AST Signature Outlining)**: **Given** C++ headers/sources (`.h`, `.hpp`, `.cpp`) or `.qml` files, **When** `scripts/get-code-outline.ps1` / `.sh` is invoked, **Then** it extracts `namespace`, `class`, `struct`, `enum class`, `Q_PROPERTY`, `Q_INVOKABLE`, `signals:`/`slots:`, function signatures, and QML component root types/properties/signals/functions without loading implementation bodies into LLM context.
- [x] **AC-4 (Fast-Gate C++/QML Change Detection & Test Discovery)**: **Given** working-tree changes to `.qml`, `.qrc`, `.ui`, `CMakeLists.txt`, `CMakePresets.json`, or `*.vcxproj`, **When** `scripts/run-fast-gate.ps1` / `.sh` runs, **Then** the Change-Detection-Guard treats them as executable artifacts (no `bypassed_code_gate = true`) and `AC-*` traceability discovers `GoogleTest`, `Catch2`, `QTest`, and `QtQuickTest` files (`tst_*.cpp`, `tst_*.qml`, `*_test.cpp`, `*Test.cpp`).
- [x] **AC-5 (CTest / QTest / GoogleTest XML & Coverage Discovery)**: **Given** CTest/GoogleTest/QTest JUnit XML reports (`**/Testing/**/*.xml`, `**/build/**/test-results/*.xml`) or `lcov`/`gcovr` coverage reports, **When** `scripts/collect-test-failures.ps1` / `.sh` or `scripts/check-test-coverage.ps1` / `.sh` runs without explicit paths, **Then** the artifacts are auto-discovered and parsed into compact diagnostics or coverage percentages.
- [x] **AC-6 (Deterministic C++ / Qt / QML Contract Guardrails)**: **Given** modified `.cpp`/`.hpp`/`.h`/`.qml` files in the working tree, **When** `scripts/lint-cpp-qt-contracts.ps1` / `.sh` (invoked by `run-fast-gate` when C++/Qt/QML is detected) runs, **Then** it deterministically flags: (a) `QObject` subclasses missing `Q_OBJECT`, (b) non-`CONSTANT` `Q_PROPERTY` declarations missing a `NOTIFY` signal, (c) legacy string-based `SIGNAL(...)` / `SLOT(...)` macro `connect()` calls instead of functor/member-pointer syntax, (d) Qt 6 deprecated `Connections { on<Signal>: ... }` handlers missing `function on<Signal>(...)`, and (e) raw owning `new` allocations outside smart-pointer factories or parented `QObject` trees (warning).
- [x] **AC-7 (Cross-Script Parity & Regression Evals)**: **Given** `.ps1`/`.sh` parity scripts and new C++/Qt/QML benchmark cases (`EVAL-TOOL-003`) in `evals/eval-cases.json`, **When** `scripts/test-skills.ps1` / `.sh` and `scripts/run-evals.ps1` / `.sh` run, **Then** 100% of cross-file synchronization, script parity, and regression eval checks pass.

---

## 4. Non-Goals / Out of Scope
Explicitly bound the feature scope to prevent scope creep:
- Installing or provisioning MinGW, MSVC Build Tools, or Qt SDKs automatically (assumes host environment provides the compiler/SDK).
- Invoking full `libclang` / `qmllint` AST compilation inside `lint-cpp-qt-contracts` as a hard requirement (zero-dependency PowerShell/Bash regex & structural checks remain the baseline; external linters like `clang-tidy`/`qmllint` integrate optionally via `lint_cmd`).
- Automatic migration of Qt 5 QML syntax to Qt 6 (guardrails report defects; the agent fixes them in Inner-Loop TDD).

---

## 5. Architecture & Technical Constraints
- **Target Module / Layer**: Deterministic Script Toolkit ([scripts/](../../scripts/)) + Governance Rules ([clean-architecture.json](../../rules/clean-architecture.json)) + Eval Harness ([eval-cases.json](../../evals/eval-cases.json))
- **Clean Architecture Boundaries**: All checks remain stateless, host-project-agnostic, and strictly paired between PowerShell (`.ps1`) and Bash (`.sh`).
- **Safety Invariants**: Scripts never mutate host project source files during Stage-1 linting; OS-native line endings (`CRLF` on Windows, `LF` on Linux/macOS) are preserved.
- **Data Model & Contracts**:
  - `lint-cpp-qt-contracts.ps1` / `.sh` supports `-WorkingTree`, `-ProjectRoot`, and `-JsonOutput` returning `{ status, scanned_files, errors, warnings }`.
  - `run-fast-gate.ps1` / `.sh` preserves backward-compatible JSON output (`status`, `failed_step`, `duration_ms`, `bypassed_code_gate`, `errors`, `warnings`).

---

## 6. Implementation & Phasing Details
- **Phase**: `1` (Dynamic Project Extension)
- **Estimated Complexity**: `Profile B (Standard)`
- **Prerequisites / Dependencies**: `FEAT-TOOL-001`, `FEAT-GOV-002`

---

## 7. Traceability & Verification
- **Target Test Suite**: `scripts/test-skills.ps1`, `scripts/run-evals.ps1`, `evals/eval-cases.json`
- **Test Types**: Deterministic script invariant tests, `.ps1`/`.sh` parity checks, synthetic C++/MinGW/MSVC/Qt/QML fixture evals (AAA pattern)
- **Associated Commits / PRs**: `<Filled upon implementation>`

---

## 8. Revision & Delta History
Atomic change log for this specific feature document (avoids full-document diffing):

| Date | Version / Status | Nature of Change | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-11-25 | `PROPOSED` | Initial feature specification for C++ (MinGW/MSVC) and Qt/QtQuick/QML support | User / Agent |
