---
id: FEAT-CLI-001
title: Dual-Client CLI Evolution (Copilot CLI & AGY 1.5.18) and Deterministic PreToolUse Hooks
status: IMPLEMENTED
phase: 1
scope: CLI
target_release: v0.7.0
---

# Feature Specification: Dual-Client CLI Evolution & Deterministic PreToolUse Hooks (`FEAT-CLI-001`)

## 1. Overview & Motivation
Modernize the `agent-skills` toolkit for the current capabilities of both **GitHub Copilot CLI** (native hooks, `/plan`, `/autopilot`, `/fleet`, `/compact`, path-specific `.instructions.md`) and **Antigravity CLI (`agy 1.5.18`)** (`gemini-4-neon`, `gemini-4-carbon`, `gemini-pro-orchestrator-*`, `hooks.json`, `run_workflow`, `/swarm`, 20,000-token aggregate rules budget) while preserving the saturated `1 + 5` V2 architecture and 75–90% KV-cache efficiency.

## 2. Acceptance Criteria (Given-When-Then)
- **AC-1 (Current AGY Model Lineup & Fixed Detection)**: Given `rules/model-tiers.json` and `scripts/detect-models.ps1/.sh`, when probing AGY models containing `gemini-4-neon-high`, `gemini-4-carbon-medium`, and `gemini-pro-orchestrator-*`, then `model-tiers.json` reflects the live lineup without obsolete `gemini-4-pro-high`/`gemini-4-flash-low`, and `tier_2_analytical` does not select flagship `gemini-4-neon-high`.
- **AC-2 (Dual-Client PreToolUse Safety Hook)**: Given `scripts/hook-pre-tool-guard.ps1/.sh` and templates in `hooks/copilot-guard.json` & `hooks/agy-guard.json`, when invoked with either Copilot CLI or AGY JSON payloads, then `git push --force`, `git reset --hard`, `_agents`/`.agents` staging/committing, and Rust `unsafe` edits are deterministically denied with 0 LLM tokens, while safe commands and `--force-with-lease` are allowed.
- **AC-3 (Opt-In Hook Provisioning & Double-Injection Protection)**: Given `scripts/setup-agent-skills.ps1/.sh`, when invoked with `-WithHooks`/`--with-hooks`, then Copilot CLI and AGY hook configs plus path-specific `.github/instructions/*.instructions.md` are provisioned cleanly, and project Copilot setup warns when global `~/.copilot/instructions/agent-skills.instructions.md` is already present.
- **AC-4 (Native CLI Workflows & Audit Ratchet)**: Given updated governance docs (`AGENTS.md`, `rules/subagents.md`, `.github/copilot-instructions.md`, `COMMON_WORKFLOWS.md`, `README.md`, `ARCHITECTURE.md`) and `scripts/test-skills.ps1/.sh`, then Copilot CLI (`/plan`, `/autopilot`, `/fleet`, `/compact`) and AGY (`run_workflow`, `/swarm`) workflows are aligned with Compound Execution as default, and `test-skills` deterministically enforces README script table & `ARCHITECTURE.md` parity.
