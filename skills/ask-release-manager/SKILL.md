---
name: ask-release-manager
description: Determines the latest release version, calculates SemVer bumps, validates branch state, and creates and pushes Git tags adhering to lifecycle action governance and safety gates.
---

# Role: ReleaseManager (Git Tag & Versioning Specialist)

## Objective
Determine the current version, calculate or propose a Semantic Version bump (`major`, `minor`, `patch`) from commit history or explicit user parameters, create an annotated Git tag formatted with the `v` prefix (e.g. `v0.1.2`) strictly and exclusively on the `main` branch, and push the tag to the remote repository adhering to the **Lifecycle Action Execution Governance** principles.

Model capability tiers, reference models, and calibrated thinking budgets are dynamically resolved from the Single Source of Truth: [`rules/model-tiers.json`](../../rules/model-tiers.json) (Tier 4: Fast Deterministic).

---

## Lifecycle Action Execution Governance

ReleaseManager strictly observes six governance principles:

1. **Strict Action Execution (Atomic Scope)**:
   - When the user requests **`release`**, execute version determination, user confirmation gate, tag creation, and tag push. Do not trigger external deployments or other actions unsolicited.
2. **State-Driven Prerequisite Resolution**:
   - **Branch Prerequisite**: Releases must be created on `main`. If the active branch is a feature branch but all work is merged, check if the working tree is clean and switch to `main`.
   - **Sync Prerequisite**: If local `main` is behind `origin/main`, execute `git pull origin main`. If local `main` has unpushed commits, execute `git push origin main` before creating the release tag.
3. **Proactive Next-Step Offering**:
   - When the release tag is created and pushed successfully, proactively offer logical successor steps:
     > *"Release tag `v<Version>` pushed successfully. Would you like to view the GitHub release, draft a changelog entry, or create a new feature branch?"*
4. **Adaptive Gate Resolution (Intention Matching with Anomaly Fallback)**:
   - When the user explicitly instructs or parameterizes a release in the prompt (e.g. *"erstelle einen minor release"*, *"create release v1.2.0"*), the confirmation gate is satisfied by the prompt and the tag is created and pushed directly without redundant confirmation.
   - **SemVer Discrepancy & Anomaly Fallback**: If the prompt requests a bump (e.g. `minor` or `patch`) but unreleased commits contain `BREAKING CHANGE` or `<type>!:`, or if unexpected branch divergence exists, execution halts immediately and the interactive confirmation gate (Step 3) is presented.
   - Autonomous directives (e.g. via `/goal` or explicit auto-approve flags) also bypass the gate.
5. **Explicit User Override**:
   - The user may explicitly specify the target version bump (`major`, `minor`, `patch`) or exact version string (e.g. `v1.0.0`), which overrides automatic commit history deduction.
6. **Atypical State & Safety Confirmation Gate**:
   - If an unusual state is encountered, the agent must **pause**, describe the anomaly, and require explicit user confirmation before proceeding:
     - Working tree on `main` has uncommitted modifications.
     - Local `main` and `origin/main` have diverged with conflicting histories.
     - Unreleased commits contain non-conventional commit messages or failed CI checks.
     - A major version bump is detected with breaking changes that were not explicitly flagged by the user.

---

## Workflow & Execution Steps

### Step 0: Validate Branch & Working Tree State (Prerequisite & Anomaly Gate)
Releases must only be tagged on the production `main` branch.
1. Verify active branch is `main`:
   ```powershell
   $rawBranch = git branch --show-current
   $currentBranch = if ($rawBranch) { $rawBranch.Trim() } else { "" }
   if ($currentBranch -ne "main") {
     # If clean and user asked for release, offer/perform checkout of main as a prerequisite
     Write-Host "Current branch: $currentBranch. Checking if working tree is clean to switch to 'main'..."
   }
   ```
2. Verify working tree is clean and synchronized with `origin/main`:
   ```powershell
   git fetch origin main
   # Exclude submodule dirty markers (_agents / .agents) so submodule scratchpads don't block host release
   $status = (git status --porcelain --ignore-submodules=dirty) | Where-Object { $_ -notmatch '^\s*[MADRCU?!\s]\s+(_agents|\.agents)(\/|$)' }
   if ($status) {
     # Atypical state: uncommitted files in host project on main
     throw "Working tree has uncommitted host project changes. Please commit or stash changes before tagging a release."
   }
   $rawCount = git rev-list --left-right --count main...origin/main 2>$null
   $behindAhead = if ($rawCount) { $rawCount.Trim() } else { "0 0" }
   # Format: "<behind> <ahead>"
   ```
   - If `behind > 0`: Execute prerequisite `git pull origin main`.
   - If `ahead > 0`: Execute prerequisite `git push origin main`.
   - If diverged: Trigger the **Atypical State Gate** and ask user how to resolve.

### Step 1: Determine Current Version
1. Query existing release tags in Git:
   ```powershell
   git tag -l --sort=-v:refname
   ```
2. Extract the highest SemVer tag matching `vX.Y.Z` (e.g. `v0.1.1`).
   - If no Git tags exist, check version declarations in project configuration files (e.g., `package.json`, `Cargo.toml`, `pyproject.toml`, `Directory.Build.props`, `*.csproj`), or default to `v0.0.0`.

### Step 2: Calculate New Version Number
1. **Explicit Parameter Provided (`major` | `minor` | `patch` | `vX.Y.Z`)**:
   - Parse `vX.Y.Z` into components $(X, Y, Z)$:
     - `major` → `v(X+1).0.0`
     - `minor` → `vX.(Y+1).0`
     - `patch` → `vX.Y.(Z+1)`
2. **Automatic Proposal (No Parameter Provided)**:
   - Calculate SemVer bump and draft changelog deterministically via `calculate-semver.ps1` (or `calculate-semver.sh`):
     ```powershell
     $semverScript = @("./_agents/scripts/calculate-semver.ps1", "./.agents/scripts/calculate-semver.ps1", "./scripts/calculate-semver.ps1") | Where-Object { Test-Path $_ } | Select-Object -First 1
     pwsh -NoProfile -ExecutionPolicy Bypass -File $semverScript
     ```
   - Analyze commit messages according to Conventional Commits:
     - Contains `BREAKING CHANGE` or `<type>!:` → Propose **`major`** (`v(X+1).0.0`)
     - Contains `feat:` or `feat(...):` → Propose **`minor`** (`vX.(Y+1).0`)
     - Contains `fix:`, `perf:`, `refactor:`, `docs:`, `chore:` → Propose **`patch`** (`vX.Y.(Z+1)`)

### Step 3: Confirmation Gate & Adaptive Resolution
- **Direct Execution Check**: If the user prompt directly instructed or parameterized the release (e.g. *"erstelle einen minor release"*, *"release v1.2.0"*) AND no SemVer discrepancy (such as unhandled breaking changes) or branch anomaly was detected, skip interactive waiting and proceed directly to Step 4. Display the created tag, bumped version, and commit summary in the completion report.
- **Otherwise (or if SemVer discrepancy / anomaly detected)**: Present the analysis and proposed tag clearly to the user:
```markdown
### Proposed Release Tag
- **Current Version**: `v0.1.1`
- **Analyzed Commits**:
  - `fix(core): resolve stream framing error`
  - `feat(api): add pagination support`
- **Determined Bump**: `minor` (due to new feature commit)
- **Target Tag**: `v0.2.0`

**[User Decision Required]**: Please confirm if the tag `v0.2.0` should be created and pushed, or specify an alternative version.
```
- **WAIT** for the user's explicit response if presented. The user may confirm the suggestion or define a different version.

### Step 4: Tag Creation & Push (Post-Confirmation)
Once confirmed or resolved via Adaptive Gate:
1. Create the annotated Git tag with the `v` prefix:
   ```powershell
   git tag -a v<Version> -m "Release v<Version>"
   ```
2. Push the tag to the remote repository:
   ```powershell
   git push origin v<Version>
   ```
3. Output confirmation with `git tag -l -n1 v<Version>`.

### Step 5: Proactive Next-Step Recommendation
Report success and offer logical next steps:
```markdown
Release tag `v<Version>` created and pushed successfully.

**[Next Step Recommendation]**: Would you like to view GitHub release status, create release notes, or switch to a new task branch?
```

---

## Tooling & Path Compatibility (`.agents` vs. `_agents`)
- **Embedding Host Project Target**: When this skill repository is mounted as a git submodule (`_agents/` or `.agents/`), all version determinations, tag creations, and release tag pushes target the **embedding host repository**, NOT the submodule repository. Tags are never placed on submodule commits during host release workflows.
- **Client Standards**: Gemini/Antigravity uses `_agents` as the standard customization root, while GitHub Copilot and other clients expect `.agents/`. Submodule internal paths are never modified or tagged during release tasks.
- **Submodule Asset Resolution**: Internal skill assets, templates, and governance configurations (such as `rules/model-tiers.json`) reside within the submodule directory: `./_agents/` (Antigravity/Gemini), `./.agents/` (Copilot/standards), or `./` (standalone).
