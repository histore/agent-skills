# Concept & RFC Draft: `Pareto Autonomy & Deterministic Verification`

```yaml
---
id: CONCEPT-GOV-001
title: "Pareto Autonomy & Deterministic Verification"
status: ARCHIVED # DRAFT | UNDER_REVIEW | APPROVED | ARCHIVED
scope: "GOV"
target_feature: "FEAT-GOV-002"
author: "User / Agent"
created: "2026-11-24"
---
```

> **Concept Path**: `docs/concepts/archive/CONCEPT-GOV-001-pareto-autonomy-verification.md`  
> **Lifecycle**: Draft / Under Review $\rightarrow$ Distill to `docs/features/FEAT-GOV-002-pareto-autonomy-verification.md` $\rightarrow$ Archive to `docs/concepts/archive/`

---

## 1. Problem Statement & Motivation
- **Context & Need**: Um maximale agentische Autonomie ohne manuelles Zeilen-Review, minimale Rework-Schleifen und konsistente Ergebnisqualität über Plattformgrenzen hinweg (Antigravity Multi-Agent + GitHub Copilot Sequential Persona) zu erreichen, reichen rein sprachliche Regeln ("LLM-Appelle") nicht aus. Gleichzeitig dürfen neue Mechanismen weder die KV-Cache-Kontinuität (75–90 % Discount), die Inner-Loop-Geschwindigkeit noch den Anti-Ceremony-Guardrail aus [AGENTS.md](../../../AGENTS.md) verletzen.
- **Desired Outcome**: Einführung ausschließlich echter **Pareto-Optimierungen** – also deterministischer Skript-Checks, kompakter Output-Schemata und situativer Kontext-Hygiene, die Verifikationssicherheit und Autonomie messbar erhöhen, ohne zusätzliche Token-Kosten, Latenz-Spitzen oder False-Positive-Ceremony zu verursachen.

---

## 2. Solution Approaches & Trade-Offs
Compare viable approaches before solidifying requirements:

### Approach A (Recommended): Strikte Pareto-Optimierungen (Zero-Token-Gates + Situative Hygiene)
- **Description**: Umsetzung von 6 gezielten, risikoarmen Erweiterungen in `scripts/`, `skills/ask-control/`, `AGENTS.md` und `evals/`:
  1. **Deterministischer `AC-*`-Traceability-Check** in `run-fast-gate.ps1`/`.sh` (nur aktiv, wenn aktive Feature-Specs mit `AC-*` existieren).
  2. **Diff-Size-Guardrail** in `run-fast-gate.ps1`/`.sh` (`git diff --numstat`-Schwellenwert-Warnung/-Flag gegen ausufernde Edits).
  3. **Zero-Trust Diff-Report** als kompaktes Stage-2-Abschlussformat in `ask-control` (Dateien, `AC-*`-Status, Guardrails, offene Annahmen).
  4. **Verschärfte Progressive-Disclosure-Regel** (Signaturen via `get-code-outline` zuerst; Full-Read erst bei direkter `AC-*`-Änderung).
  5. **Situatives `.agent-state.json`** ausschließlich bei Context-Purge (Circuit-Breaker Level 3) oder explizitem Copilot-Thread-Wechsel.
  6. **Regression-Evals** in `evals/eval-cases.json` für reale Governance- und Autonomie-Fehlerklassen.
- **Pros**:
  - Nahezu 0 zusätzliche LLM-Tokens und < 20 ms Zusatzlaufzeit im Fast-Gate.
  - Volle Wahrung von *Compound Phased Execution* und *Two-Zone Prompt Cache Architecture*.
  - Kein Eingriff in Profile 0 / Profile A (Anti-Ceremony bleibt 100 % intakt).
- **Cons / Risks**:
  - Deckt keine semantischen Logikfehler ab, die *innerhalb* grüner Alibi-Tests liegen (Mutation-Testing bleibt bewusst außen vor bzw. On-Demand).
  - Cross-Platform-Parität zwischen `.ps1` und `.sh` muss für neue Fast-Gate-Checks gepflegt werden.

### Approach B (Alternative): Maximale Verification mit Non-Pareto-Trade-Offs
- **Description**: Zusätzlich verpflichtender Fresh-Context-Subagent-Review (`ask-troubleshooter`) nach jedem Profile-B/C-Task, Regex-Mutation-Testing im Fast-Gate und permanentes `HANDOVER.md` nach jeder Phase.
- **Pros / Cons**: Höhere theoretische Prüftiefe, aber abgelehnt, da es KV-Cache-Reuse bricht, Latenz und Token-Verbrauch deutlich erhöht und im Inner-Loop zu False Positives sowie Git-Noise führt.

---

## 3. High-Level Architecture & Clean Architecture Boundaries
- **Target Layer**: Infrastructure / Deterministic Tooling (`scripts/`) + Governance Contracts (`AGENTS.md`, `skills/ask-control/SKILL.md`, `evals/eval-cases.json`)
- **Clean Architecture Invariants**: Alle deterministischen Checks leben als sprachagnostische, zustandslose Skripte in `scripts/` (PowerShell `.ps1` + Bash `.sh` Parität) und liefern kompaktes JSON bzw. einzeilige Gate-Ausgaben ohne LLM-Abhängigkeit.
- **Safety Invariants**: Skripte arbeiten strikt read-only auf dem Working-Tree (Ausnahme: explizit situatives `.agent-state.json` im `.gitignore`-Bereich). Submodule (`_agents/`, `.agents/`) bleiben isoliert.
- **Data Flow & Components**:
  - `docs/features/FEAT-*.md` (`AC-*`-IDs) $\rightarrow$ `run-fast-gate.ps1/.sh` (Regex-Traceability + `git diff --numstat` Guardrail) $\rightarrow$ JSON/CLI-Status.
  - `run-fast-gate` + `git diff --stat` $\rightarrow$ `ask-control` Stage 2 $\rightarrow$ **Zero-Trust Diff-Report**.
  - Circuit-Breaker Level 3 / Thread-Wechsel $\rightarrow$ `.agent-state.json` (kompakter State-Snapshot) $\rightarrow$ nächster Thread.

---

## 4. Phased Implementation Plan (Phasenweise Umsetzung)

### Phase 1: Deterministic Fast-Gate Extensions (`AC-*` Traceability & Diff-Size-Guardrail)
- **Scope & Deliverables**:
  - Erweiterung von `scripts/run-fast-gate.ps1` und `scripts/run-fast-gate.sh` um:
    1. `AC-*`-Traceability-Prüfung (nur wenn aktive/geänderte `docs/features/FEAT-*.md` mit `AC-*` vorhanden sind).
    2. `git diff --numstat`-Diff-Size-Check (konfigurierbarer Schwellenwert, z. B. 400 geänderte Code-Zeilen).
  - Unit-/Smoke-Verifikation über `scripts/test-skills.ps1` / `scripts/run-evals.ps1`.
- **Target Feature(s)**: `FEAT-GOV-002`
- **Exit Criteria / DoD**: `.ps1` und `.sh` liefern identisches JSON-Schema, Profile-A-Workflows ohne Feature-Spec werden automatisch gebypasst, `test-skills.ps1` grün.

### Phase 2: Governance, Output-Schema & Context Hygiene (`ask-control` & `AGENTS.md`)
- **Scope & Deliverables**:
  - Integration des kompakten **Zero-Trust Diff-Reports** in Stage 2 von `skills/ask-control/SKILL.md`.
  - Präzisierung der **Progressive-Disclosure-Regel** in `AGENTS.md` und `skills/ask-control/SKILL.md` (Full-Read erst bei direkter `AC-*`-Betroffenheit).
  - Definition des situativen **`.agent-state.json`**-Schemas für Circuit-Breaker Level 3 und Copilot-Thread-Wechsel (inkl. `.gitignore`-Empfehlung).
- **Target Feature(s)**: `FEAT-GOV-002`
- **Exit Criteria / DoD**: Cross-File-Sync über `scripts/test-skills.ps1` zu 100 % bestanden, keine Widersprüche zu bestehenden Invarianten.

### Phase 3: Regression-Evals & Hardening
- **Scope & Deliverables**:
  - Ergänzung von `evals/eval-cases.json` um Regression-Cases für `AC-*`-Traceability, Diff-Size-Guardrail, Zero-Trust Diff-Report und situatives `.agent-state.json`.
  - Anpassung von `scripts/run-evals.ps1` / `scripts/run-evals.sh`, falls neue Invarianten-Typen geprüft werden müssen.
- **Target Feature(s)**: `FEAT-GOV-002`
- **Exit Criteria / DoD**: `run-evals.ps1` und `test-skills.ps1` bestehen 100 %, `lint-docs.ps1` meldet 0 defekte Links.

---

## 5. Open Questions, Edge Cases & Clarifications (Resolved)
- [x] **Q-1 (Diff-Size-Limit)**: **Warnung** – Das Überschreiten des Diff-Size-Limits (z. B. > 400 geänderte Code-Zeilen) erzeugt eine Warnung im Fast-Gate-Output sowie im Zero-Trust Diff-Report (kein harter Fail).
- [x] **Q-2 (`AC-*`-Traceability-Strenge)**: **Option A (Stage-1 Fail)** – Bei aktiver Feature-Spec (`FEAT-*.md` mit `AC-*`) setzt fehlende Test-Abdeckung `run-fast-gate` direkt auf `fail` (Exit-Code `1`), sodass der Fehler maschinell blockiert wird und nicht untergehen kann. Bei Profile A ohne Feature-Spec wird der Check übersprungen.
- [x] **Q-3 (`.agent-state.json` Speicherort)**: **Scratch-Verzeichnis** – Ablage ausschließlich im jeweiligen Scratch-/Temp-Verzeichnis (kein File im Repo-Root, kein Git-Noise).

---

## 6. Distillation Target & Proposed Acceptance Criteria Preview
Preliminary preview of acceptance criteria to be extracted into `docs/features/FEAT-GOV-002-pareto-autonomy-verification.md`:
- **Preview AC-1 (`AC-*`-Traceability)**: Given eine aktive oder geänderte Feature-Spec mit `AC-1` und `AC-2`, When `run-fast-gate` ausgeführt wird, Then prüft das Skript per Regex, ob beide IDs in Testdateien referenziert sind, und meldet fehlende Abdeckung kompakt.
- **Preview AC-2 (Anti-Ceremony Bypass)**: Given ein Profile-A-Bugfix ohne aktive Feature-Spec, When `run-fast-gate` ausgeführt wird, Then wird der `AC-*`-Traceability-Check ohne Overhead übersprungen.
- **Preview AC-3 (Diff-Size-Guardrail)**: Given mehr als der konfigurierte Schwellenwert an geänderten Code-Zeilen im Working-Tree, When `run-fast-gate` läuft, Then wird ein eindeutiger Diff-Size-Hinweis/-Flag ausgegeben.
- **Preview AC-4 (Zero-Trust Diff-Report)**: Given abgeschlossene Stage 1 in Profile B oder C, When `ask-control` Stage 2 abschließt, Then wird die kompakte Risiko-Matrix (Dateien, `AC-*`-Status, Guardrails, offene Annahmen) ausgegeben.
- **Preview AC-5 (Situatives `.agent-state.json`)**: Given ein regulärer Single-Thread-Durchlauf ohne Context-Purge, When Phasen wechseln, Then wird **kein** `.agent-state.json` geschrieben (nur bei Circuit-Breaker Level 3 oder Thread-Wechsel).
- **Preview AC-6 (Regression-Evals)**: Given die neuen Eval-Cases in `evals/eval-cases.json`, When `run-evals.ps1` ausgeführt wird, Then bestehen 100 % der Fälle ohne Fehler.

---

## 7. Revision & Discussion History
| Date | Status | Changes & Decision Notes | Author / Approver |
| :--- | :--- | :--- | :--- |
| 2026-11-24 | `DRAFT` | Initiales Konzept für die 6 Pareto-Optimierungen erstellt | User / Agent |
| 2026-11-24 | `APPROVED` | Q-1 (Warnung), Q-2 (Option A: Stage-1 Fail) und Q-3 (Scratch-Verzeichnis) geklärt und freigegeben | User / Agent |
| 2026-11-24 | `ARCHIVED` | Destilliert nach `docs/features/FEAT-GOV-002-pareto-autonomy-verification.md` | User / Agent |
