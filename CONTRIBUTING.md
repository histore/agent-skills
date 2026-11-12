# Contributing to Agent Skills

Thank you for contributing to this project. To maintain high architectural integrity, clear role boundaries, and clean Git history, please adhere to the following workflow guidelines.

## General Principles

1. **General and Reusable**:
   - Skills and rules in this workspace must contain general workflows and rules only.
   - Do NOT introduce project-specific, language-specific, or library-specific hardcodings (e.g. specific frameworks, languages, or package managers).
   - Technologies must be dynamically discovered from project configuration files and architecture specifications.

2. **Unified Core Lifecycle vs. On-Demand Specialist Capability Packs (V2 Architecture)**:
   - **Unified Core Lifecycle Engineer** (`Control` / `ask-control`) defines the standard workflow (Planning, Architecture Contracts, Inner-Loop TDD, Two-Stage Verification Gate, Atomic Commit & PR Governance) within a single continuous session.
   - **On-Demand Specialist Capability Packs** (`Troubleshooter` / `ask-troubleshooter`, `GitTroubleshooter` / `ask-git-troubleshooter`, `ContractSpecialist` / `ask-contract-specialist`, `ReleaseManager` / `ask-release-manager`, `SkillAuditor` / `ask-skill-auditor`) are bound to technical domains, not specific frameworks. They are invoked conditionally on-demand when deep domain specialization is required.

3. **Documentation Language**:
   - All documentation files, markdown guides, and source code comments must be written in English.

## Lifecycle Action Execution Governance

Operations involving Git and releases (`commit`, `push`, `pr merge`, `release`) adhere to seven governance principles:

1. **Strict Action Execution (Atomic Scope)**: An explicitly requested action executes only that action without unsolicited side-actions (e.g. committing never triggers an automatic push).
2. **State-Driven Prerequisite Resolution**: If an action requires preceding state changes (e.g. uncommitted workspace changes when `push` is requested, or unpushed commits before PR creation), prerequisites are resolved automatically.
3. **Proactive Next-Step Offering**: After completing an action, the logical successor step is proactively recommended to the user for immediate execution.
4. **Adaptive Gate & Commit Modes**: In *Prepare Commit* (default review flow), run `prepare-commit -RevertWhitespaceOnly -FixLineEndings` (single-pass deferred format check + whitespace/line-ending cleanup: `CRLF` on Windows, `LF` on Linux/macOS) and resolve any ambiguous decisions first, then present the commit message for approval; upon acceptance (with no intervening edits), execute `git commit` directly with that exact approved message without re-running `prepare-commit`, formatters (`spotless`), or checks. On a standalone *Direct Commit* or parameterized release instruction, skip redundant confirmation while still executing `prepare-commit -Direct` once (pausing only on out-of-scope changes, ambiguous normalizations, SemVer conflicts, or repository anomalies).
5. **Explicit User Override**: Explicit user instructions can combine or alter default actions at any time.
6. **Atypical State & Safety Confirmation Gate**: If following these instructions produces an unexpected state or requires non-standard measures (e.g. detached HEAD, merge conflicts, unexpected untracked files, unverified release states), the agent halts, describes the situation, and requests explicit user confirmation before proceeding.
7. **Clean Release Tagging Invariant**: Release tags (`vX.Y.Z`) must be applied directly to the existing production/merge commit on `main`. Standalone metadata commits (such as `docs(changelog): release v...`) directly on `main` during release tagging are strictly prohibited. Release notes belong in tag annotations or GitHub Releases.

## Branch & Pull Request Process

All contributions must follow a structured branch and PR workflow:

1. **Dedicated Branches**:
   - Never commit directly to `main`.
   - Create dedicated branches using conventional prefixes:
     - `feat/<feature-name>`: New skills or capabilities
     - `fix/<fix-name>`: Bug fixes or corrections
     - `refactor/<refactor-name>`: Code/skill restructuring
     - `docs/<docs-name>`: Documentation updates
     - `chore/<chore-name>`: Maintenance tasks

2. **Commit Messages**:
   - Follow the Conventional Commits specification (`<type>(<scope>): <summary>`).
   - Detailed bullet points in the body explaining rationale.

3. **Developer Testing & Review Gate**:
   - Before opening a Pull Request, verify that all skill changes pass verification and have been reviewed.

4. **Merging into `main`**:
   - Pull Requests must be squash-merged into `main` after review sign-off and passing all CI checks.
