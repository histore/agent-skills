# Feature Specification: `Pareto Autonomy & Deterministic Verification`

```yaml
---
id: FEAT-GOV-002
title: "Pareto Autonomy & Deterministic Verification"
phase: 1
status: IMPLEMENTED # PROPOSED | APPROVED | IN_PROGRESS | IMPLEMENTED | VERIFIED | DEPRECATED
target_release: "v0.3.0"
scope: "GOV"
depends_on: ["FEAT-GOV-001", "FEAT-TOOL-001", "FEAT-SPEC-001"]
---
```

> **Specification Path**: `docs/features/FEAT-GOV-002-pareto-autonomy-verification.md`  
> **Parent Hub / Index**: [ROADMAP.md](../ROADMAP.md)  
> **Source Concept**: [CONCEPT-GOV-001-pareto-autonomy-verification.md](../concepts/archive/CONCEPT-GOV-001-pareto-autonomy-verification.md)

This document is an **isolated, living feature specification**. It is authored incrementally, updated in-place without rewriting the rest of the documentation, and loaded lazily by AI agents to keep token usage minimal.

---

## 1. Executive Summary & Objective
Erweitert das Agent-Skills-Toolkit um sechs reine **Pareto-Optimierungen** zur Steigerung der autonomen Ergebnisqualität ohne manuelles Zeilen-Review und ohne Mehrkosten bei KV-Cache, Latenz oder Anti-Ceremony. Dazu gehören ein deterministischer `AC-*`-Traceability-Check und ein Diff-Size-Guardrail im Stage-1 Fast-Gate, ein kompakter Zero-Trust Diff-Report in Stage 2, eine verschärfte Progressive-Disclosure-Regel, situative `.agent-state.json`-Snapshots im Scratch-Verzeichnis sowie Regression-Evals.

---

## 2. User Story
> **As a** Entwickler und Orchestrator von `agent-skills` (Antigravity & GitHub Copilot),  
> **I want** deterministische Fast-Gate-Prüfungen für Akzeptanzkriterien und Diff-Größen, einen kompakten Stage-2-Risiko-Report sowie situative Kontext-Hygiene,  
> **so that** autonome Agenten-Läufe zuverlässig ohne stillschweigend ausgelassene Anforderungen und ohne manuelles Zeilen-Review abgeschlossen werden können.

---

## 3. Acceptance Criteria (Given-When-Then)
Each acceptance criterion must be verifiable and formulated using Arrange-Act-Assert / Given-When-Then:

- [x] **AC-1 (`AC-*`-Traceability Stage-1 Fail)**: **Given** eine aktive oder im Working-Tree geänderte Feature-Spezifikation (`docs/features/FEAT-*.md`) mit definierten `AC-*`-IDs, **When** `scripts/run-fast-gate.ps1` oder `scripts/run-fast-gate.sh` ausgeführt wird, **Then** prüft das Skript per Regex, ob jede `AC-*`-ID in mindestens einer Testdatei (Testname oder Kommentar) referenziert wird, und bricht bei fehlender Abdeckung mit `status: fail` (Exit-Code `1`) ab.
- [x] **AC-2 (Anti-Ceremony Bypass in Profile A / ohne Spec)**: **Given** ein Repository oder eine Änderung ohne aktive `FEAT-*.md`-Datei mit `AC-*`-Kriterien (z. B. Profile-A-Bugfix oder reine Dokumentationsänderung), **When** `scripts/run-fast-gate.ps1` / `.sh` ausgeführt wird, **Then** wird der `AC-*`-Traceability-Check ohne Overhead übersprungen.
- [x] **AC-3 (Diff-Size-Guardrail als Warnung)**: **Given** Working-Tree-Änderungen an ausführbarem Code, die den konfigurierten Schwellenwert (Standard: > 400 geänderte Code-Zeilen laut `git diff --numstat`) überschreiten, **When** `scripts/run-fast-gate.ps1` / `.sh` läuft, **Then** wird eine eindeutige Diff-Size-Warnung im Fast-Gate-Output (bzw. JSON-Feld) ausgegeben, ohne den Lauf hart abzubrechen.
- [x] **AC-4 (Zero-Trust Diff-Report in Stage 2)**: **Given** ein abgeschlossener Stage-1 Fast-Gate-Lauf in Profile B oder Profile C, **When** `ask-control` Stage 2 abschließt, **Then** gibt der Agent statt unstrukturiertem Abschluss-Text eine kompakte Risiko-Matrix aus (`Geänderte Dateien`, `AC-*-Status`, `Fast-Gate/Guardrails & Diff-Size-Warnungen`, `Offene Annahmen/Ungetestete Pfade`).
- [x] **AC-5 (Progressive Disclosure & situatives `.agent-state.json`)**: **Given** ein regulärer Single-Thread-Durchlauf in `ask-control`, **When** zwischen Phasen gewechselt wird, **Then** wird **kein** `.agent-state.json` geschrieben und Implementierungsdateien werden erst vollständig gelesen, wenn sie in der aktiven `AC-*` direkt geändert werden (vorher Signaturen via `get-code-outline`); **nur** bei Circuit-Breaker Level 3 (*Context Purge*) oder explizitem Copilot-Thread-Wechsel wird `.agent-state.json` im Scratch-/Temp-Verzeichnis erzeugt.
- [x] **AC-6 (Regression-Evals)**: **Given** neue Benchmark-Fälle in `evals/eval-cases.json` für `AC-*`-Traceability, Diff-Size-Warnung, Zero-Trust Diff-Report und situatives `.agent-state.json`, **When** `scripts/run-evals.ps1` / `.sh` und `scripts/test-skills.ps1` / `.sh` ausgeführt werden, **Then** bestehen 100 % der Prüfungen ohne Fehler und mit voller Cross-File-Synchronisation.

---

## 4. Non-Goals / Out of Scope
Explicitly bound the feature scope to prevent scope creep:
- Permanentes `HANDOVER.md` nach jeder Phase im selben Thread (verletzt KV-Cache-Kontinuität und Anti-Ceremony).
- Sprachagnostisches Regex-Mutation-Testing im Stage-1 Fast-Gate (hohe Laufzeit und False-Positive-Risiko).
- Verpflichtender Fresh-Context-Subagent-Review (`ask-troubleshooter` bleibt in Profile B/C On-Demand).
- Hartes Blockieren bei Diff-Size-Überschreitung (bleibt gemäß `Q-1` eine Warnung).

---

## 5. Architecture & Technical Constraints
- **Target Module / Layer**: Deterministic Script Toolkit (`scripts/`) + Governance Contracts ([AGENTS.md](../../AGENTS.md), [ask-control](../../skills/ask-control/SKILL.md)) + Eval Harness ([eval-cases.json](../../evals/eval-cases.json))
- **Clean Architecture Boundaries**: Alle deterministischen Prüfungen bleiben zustandslos und sprachagnostisch in `scripts/` mit strikter Parität zwischen PowerShell (`.ps1`) und Bash (`.sh`).
- **Safety Invariants**: Skripte verändern keine Host-Repository-Dateien; `.agent-state.json` wird ausschließlich im Scratch-/Temp-Verzeichnis abgelegt, um Git-Noise zu vermeiden.
- **Data Model & Contracts**:
  - `run-fast-gate.ps1` / `.sh` JSON-Output bleibt abwärtskompatibel (`status`, `failed_step`, `duration_ms`, `bypassed_code_gate`, `errors`, optional `warnings`).
  - `.agent-state.json` (Scratch): kompaktes JSON mit `decisions`, `touched_files`, `open_ac_ids`, `constraints`.

---

## 6. Implementation & Phasing Details
- **Phase**: `1` (Dynamic Project Extension)
- **Estimated Complexity**: `Profile B (Standard)`
- **Prerequisites / Dependencies**: `FEAT-GOV-001`, `FEAT-TOOL-001`, `FEAT-SPEC-001`

---

## 7. Traceability & Verification
- **Target Test Suite**: `scripts/test-skills.ps1`, `scripts/run-evals.ps1`, `scripts/lint-docs.ps1`
- **Test Types**: Deterministische Skript-Invarianztests, Cross-File-Sync-Prüfung, Eval-Harness-Regressionstests
- **Associated Commits / PRs**: `<Filled upon implementation>`

---

## 8. Revision & Delta History
Atomic change log for this specific feature document (avoids full-document diffing):

| Date | Version / Status | Nature of Change | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-11-24 | `PROPOSED` | Destilliert aus `CONCEPT-GOV-001` (inkl. geklärter Entscheidungen Q-1, Q-2, Q-3) | User / Agent |
