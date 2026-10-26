#!/usr/bin/env bash
# ==============================================================================
# Sets up agent-skills in a target project or globally in the user configuration.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COPILOT_TEMPLATE="${REPO_ROOT}/.github/copilot-instructions.md"

TARGET_PROJECT=""
FOLDER_TYPE="_agents"
GLOBAL_MODE=false
SKIP_COPILOT=false
INIT_DOCS=false
FORCE=false

print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -p, --project <dir>      Path to target project to integrate into"
  echo "  -g, --global             Install globally in user home (~/.gemini/config)"
  echo "  -t, --folder-type <type> Link name: '_agents' (default), '.agents', or 'both'"
  echo "  --skip-copilot           Skip creating .github/copilot-instructions.md"
  echo "  --init-docs              Scaffold initial ARCHITECTURE.md and docs/ROADMAP.md in target project"
  echo "  -f, --force              Overwrite existing links or files"
  echo "  -h, --help               Show this help message"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      TARGET_PROJECT="$2"
      shift 2
      ;;
    -g|--global)
      GLOBAL_MODE=true
      shift
      ;;
    -t|--folder-type)
      FOLDER_TYPE="$2"
      shift 2
      ;;
    --skip-copilot)
      SKIP_COPILOT=true
      shift
      ;;
    --init-docs)
      INIT_DOCS=true
      shift
      ;;
    -f|--force)
      FORCE=true
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage
      exit 1
      ;;
  esac
done

create_symlink() {
  local link_path="${1%/}"
  local target_path="${2%/}"

  if [[ "$link_path" == "$target_path" ]]; then
    echo "  [OK] Path is already the source repository: ${link_path}"
    return 0
  fi

  if [[ -L "$link_path" || -d "$link_path" ]]; then
    if [[ "$FORCE" != true ]]; then
      echo "  [SKIP] Link already exists: ${link_path} (use --force to overwrite)"
      return 0
    fi
    echo "  [REMOVE] Existing link: ${link_path}"
    rm -rf "$link_path"
  fi

  ln -sfn "$target_path" "$link_path"
  echo "  [OK] Created Symlink: ${link_path} -> ${target_path}"
}

echo "============================================="
echo "Agent Skills Setup & Integration Helper"
echo "============================================="

if [[ "$GLOBAL_MODE" == true ]]; then
  GEMINI_CONFIG_DIR="${HOME}/.gemini/config"
  echo ""
  echo "Configuring Global User Mode in: ${GEMINI_CONFIG_DIR}"

  mkdir -p "${GEMINI_CONFIG_DIR}"

  # 1. Link skills and rules
  create_symlink "${GEMINI_CONFIG_DIR}/skills" "${REPO_ROOT}/skills"
  create_symlink "${GEMINI_CONFIG_DIR}/rules" "${REPO_ROOT}/rules"

  # 2. Setup GitHub Copilot Personal Mode (~/.agents and ~/.copilot/instructions)
  create_symlink "${HOME}/.agents" "$REPO_ROOT"

  COPILOT_INSTRUCTIONS_DIR="${HOME}/.copilot/instructions"
  mkdir -p "${COPILOT_INSTRUCTIONS_DIR}"

  # 3. Generate reference instruction file with YAML frontmatter (applyTo: "**/*")
  USER_INSTRUCTIONS_FILE="${COPILOT_INSTRUCTIONS_DIR}/agent-skills.instructions.md"
  cat <<EOF > "$USER_INSTRUCTIONS_FILE"
---
applyTo: "**/*"
description: "Universal Clean Code, Clean Architecture, and on-demand agent skills"
---

# Personal Agent Skills & Engineering Guidelines

Adhere to the core engineering invariants (Clean Code, Clean Architecture, Safe Rust without unsafe, Inner-Loop TDD, Anti-Ceremony).

## Base Instructions
The baseline rules are defined in:
- ${COPILOT_TEMPLATE}

## Central Skills & Tooling Source
All specialist skills and zero-token automation scripts are located in:
- Skills Root Directory: ${REPO_ROOT}/skills/
- Also accessible via personal skills: ~/.agents/skills/ or ~/.copilot/skills/

When encountering specialized tasks requiring deep domain expertise, consult the corresponding capability pack on demand:
- **Diagnostics, bug RCA, code review, refactoring & profiling**: ${REPO_ROOT}/skills/ask-troubleshooter/SKILL.md
- **Git anomalies, merge/rebase conflicts & recovery (Zero Data Loss)**: ${REPO_ROOT}/skills/ask-git-troubleshooter/SKILL.md
- **Contracts, living specs, API contracts, DB migrations, UI/UX tokens, a11y & i18n**: ${REPO_ROOT}/skills/ask-contract-specialist/SKILL.md
- **Release management, CI/CD, SemVer calculation & security audits**: ${REPO_ROOT}/skills/ask-release-manager/SKILL.md
EOF
  echo "  [OK] Generated Copilot user instructions: ${USER_INSTRUCTIONS_FILE}"

  echo ""
  echo "Antigravity / Gemini Setup:"
  echo "  All skills and rules are now automatically active across all projects via ~/.gemini/config."
  echo ""
  echo "GitHub Copilot CLI Setup:"
  echo "  - Instructions: Auto-discovered from ~/.copilot/instructions/agent-skills.instructions.md"
  echo "  - Skills: Auto-discovered from ~/.agents/skills and ~/.copilot/skills"
  echo "  - Verification commands: 'copilot instruction list' and 'copilot skill list'"
  echo ""
  echo "GitHub Copilot (VS Code User Settings):"
  echo "  Add the following to your VS Code settings.json:"
  echo "  \"github.copilot.chat.codeGeneration.instructions\": ["
  echo "    {"
  echo "      \"file\": \"${USER_INSTRUCTIONS_FILE}\""
  echo "    }"
  echo "  ]"

else
  if [[ -z "$TARGET_PROJECT" ]]; then
    CURRENT_DIR="$(pwd)"
    if [[ "$CURRENT_DIR" == "$REPO_ROOT" ]]; then
      echo "Error: Please specify a --project directory or use --global to install globally." >&2
      exit 1
    fi
    TARGET_PROJECT="$CURRENT_DIR"
  fi

  TARGET_DIR="$(cd "$TARGET_PROJECT" && pwd)"
  echo ""
  echo "Integrating into Project: ${TARGET_DIR}"

  # 1. Create directory link(s)
  if [[ "$FOLDER_TYPE" == "_agents" || "$FOLDER_TYPE" == "both" ]]; then
    create_symlink "${TARGET_DIR}/_agents" "$REPO_ROOT"
  fi
  if [[ "$FOLDER_TYPE" == ".agents" || "$FOLDER_TYPE" == "both" ]]; then
    create_symlink "${TARGET_DIR}/.agents" "$REPO_ROOT"
  fi

  # 2. Setup .github/copilot-instructions.md
  if [[ "$SKIP_COPILOT" != true ]]; then
    mkdir -p "${TARGET_DIR}/.github"
    DEST_COPILOT="${TARGET_DIR}/.github/copilot-instructions.md"
    if [[ -f "$DEST_COPILOT" && "$FORCE" != true ]]; then
      echo "  [SKIP] .github/copilot-instructions.md already exists (use --force to overwrite)"
    else
      cp -f "$COPILOT_TEMPLATE" "$DEST_COPILOT"
      echo "  [OK] Provisioned ${DEST_COPILOT} (Lite Copilot instructions)"
    fi
  fi

  # 3. Optional: Bootstrap Living Modular Documentation (--init-docs)
  if [[ "$INIT_DOCS" == true ]]; then
    echo ""
    echo "Bootstrapping Living Modular Documentation in Target Project..."
    PROJECT_NAME="$(basename "$TARGET_DIR")"
    DATE_STR="$(date +%Y-%m-%d)"
    mkdir -p "${TARGET_DIR}/docs/features" "${TARGET_DIR}/docs/concepts/drafts" "${TARGET_DIR}/docs/concepts/archive" "${TARGET_DIR}/docs/architecture/modules"

    ARCH_FILE="${TARGET_DIR}/ARCHITECTURE.md"
    if [[ -f "$ARCH_FILE" && "$FORCE" != true ]]; then
      echo "  [SKIP] ARCHITECTURE.md already exists"
    else
      cat <<EOF > "$ARCH_FILE"
# System Architecture Baseline: ${PROJECT_NAME}

> **Status**: APPROVED  
> **Last Synchronized**: ${DATE_STR}  

## 1. Clean Architecture & Layer Boundaries

Dependencies point strictly inward:
- **Domain Layer**: Entities, Value Objects, Domain Invariants (zero external framework dependencies).
- **Application Layer**: Use Cases, Service Contracts, DTOs, Port Interfaces.
- **Adapters / Presentation Layer**: Controllers, ViewModels, Presenters, Persistence Mappers.
- **Infrastructure / Drivers Layer**: UI Frameworks, Database Providers, External APIs, CLI/OS Drivers.

## 2. Modular Specifications
- Living Feature Specifications: [docs/ROADMAP.md](docs/ROADMAP.md)
- Module Architecture Specs: \`docs/architecture/modules/\`
EOF
      echo "  [OK] Scaffolded ARCHITECTURE.md"
    fi

    ROADMAP_FILE="${TARGET_DIR}/docs/ROADMAP.md"
    if [[ -f "$ROADMAP_FILE" && "$FORCE" != true ]]; then
      echo "  [SKIP] docs/ROADMAP.md already exists"
    else
      cat <<EOF > "$ROADMAP_FILE"
# Project Roadmap & Living Feature Index (\`docs/ROADMAP.md\`)

> **System Baseline**: ${PROJECT_NAME}  
> **Architecture Specification**: [ARCHITECTURE.md](../ARCHITECTURE.md)  

---

## 1. Feature Registry & Lifecycle Tracker

| Phase | Feature ID | Title | Status | Scope | Specification File | Target Release |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
EOF
      echo "  [OK] Scaffolded docs/ROADMAP.md"
    fi
  fi

  echo ""
  echo "Project Integration Complete!"
  echo "  - Antigravity: Discovers skills via _agents/skills and rules via _agents/rules"
  echo "  - Copilot: Governed cleanly by .github/copilot-instructions.md (Lite mode)"
fi
