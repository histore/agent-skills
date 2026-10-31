#!/usr/bin/env bash
# ==============================================================================
# Sets up agent-skills in a target project or globally in the user configuration.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COPILOT_TEMPLATE="${REPO_ROOT}/.github/copilot-instructions.md"

TARGET_PROJECT=""
CLIENT="all"
FOLDER_TYPE=""
FOLDER_TYPE_EXPLICIT=false
CLIENT_EXPLICIT=false
GLOBAL_MODE=false
SKIP_COPILOT=false
INIT_DOCS=false
USER_HOME="${HOME}"
FORCE=false

print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -p, --project <dir>      Path to target project to integrate into"
  echo "  -c, --client <type>      Target client: 'all' (default), 'agy' (_agents), or 'copilot' (.agents)"
  echo "  -g, --global             Install globally in user home (~/_agents for AGY, ~/.agents for Copilot)"
  echo "  -t, --folder-type <type> Explicit link override: '_agents', '.agents', or 'both'"
  echo "  --skip-copilot           Skip Copilot (.agents and .github/copilot-instructions.md)"
  echo "  --init-docs              Scaffold initial ARCHITECTURE.md and docs/ROADMAP.md in target project"
  echo "  --user-home <dir>        Override user HOME directory (for isolated testing)"
  echo "  -f, --force              Overwrite existing links or files"
  echo "  -h, --help               Show this help message"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project)
      TARGET_PROJECT="$2"
      shift 2
      ;;
    -c|--client)
      CLIENT="$2"
      CLIENT_EXPLICIT=true
      shift 2
      ;;
    -g|--global)
      GLOBAL_MODE=true
      shift
      ;;
    -t|--folder-type)
      FOLDER_TYPE="$2"
      FOLDER_TYPE_EXPLICIT=true
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
    --user-home)
      USER_HOME="$2"
      shift 2
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

SETUP_AGY=false
SETUP_COPILOT=false
if [[ "$CLIENT" == "all" || "$CLIENT" == "agy" ]]; then SETUP_AGY=true; fi
if [[ ("$CLIENT" == "all" || "$CLIENT" == "copilot") && "$SKIP_COPILOT" != true ]]; then SETUP_COPILOT=true; fi

if [[ "$FOLDER_TYPE_EXPLICIT" == true ]]; then
  if [[ "$FOLDER_TYPE" == "_agents" ]]; then
    SETUP_AGY=true
    [[ "$SKIP_COPILOT" == true ]] && SETUP_COPILOT=false
  elif [[ "$FOLDER_TYPE" == ".agents" ]]; then
    [[ "$CLIENT_EXPLICIT" != true ]] && SETUP_AGY=false
    [[ "$SKIP_COPILOT" != true ]] && SETUP_COPILOT=true
  else
    SETUP_AGY=true
    [[ "$SKIP_COPILOT" != true ]] && SETUP_COPILOT=true
  fi
else
  if [[ "$SETUP_AGY" == true && "$SETUP_COPILOT" == true ]]; then
    FOLDER_TYPE="both"
  elif [[ "$SETUP_COPILOT" == true ]]; then
    FOLDER_TYPE=".agents"
  else
    FOLDER_TYPE="_agents"
  fi
fi

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
  echo ""
  echo "Configuring Global User Mode (Home: ${USER_HOME}, Client: ${CLIENT})"

  if [[ "$SETUP_AGY" == true ]]; then
    # 1. Antigravity (AGY) User Level via ~/_agents + ~/.gemini/config
    AGY_USER_DIR="${USER_HOME}/_agents"
    create_symlink "$AGY_USER_DIR" "$REPO_ROOT"

    GEMINI_CONFIG_DIR="${USER_HOME}/.gemini/config"
    mkdir -p "${GEMINI_CONFIG_DIR}"
    create_symlink "${GEMINI_CONFIG_DIR}/skills" "${AGY_USER_DIR}/skills"
    create_symlink "${GEMINI_CONFIG_DIR}/rules" "${AGY_USER_DIR}/rules"

    echo ""
    echo "Antigravity / Gemini Setup (~/_agents):"
    echo "  - User Root: ${AGY_USER_DIR}"
    echo "  - Auto-Discovery: ~/.gemini/config/skills & ~/.gemini/config/rules -> ~/_agents"
  fi

  if [[ "$SETUP_COPILOT" == true ]]; then
    # 2. GitHub Copilot User Level via ~/.agents + inlined ~/.copilot/instructions/
    COPILOT_AGENTS_DIR="${USER_HOME}/.agents"
    create_symlink "$COPILOT_AGENTS_DIR" "$REPO_ROOT"

    COPILOT_INSTRUCTIONS_DIR="${USER_HOME}/.copilot/instructions"
    mkdir -p "${COPILOT_INSTRUCTIONS_DIR}"

    USER_INSTRUCTIONS_FILE="${COPILOT_INSTRUCTIONS_DIR}/agent-skills.instructions.md"
    INLINED_BODY=$(sed \
      -e "s|\./\.agents/scripts/|${COPILOT_AGENTS_DIR}/scripts/|g" \
      -e "s|\`\.agents/skills/|\`${COPILOT_AGENTS_DIR}/skills/|g" \
      -e "s|\`\.agents/docs/|\`${COPILOT_AGENTS_DIR}/docs/|g" \
      "$COPILOT_TEMPLATE")

    cat <<EOF > "$USER_INSTRUCTIONS_FILE"
---
applyTo: "**/*"
description: "Universal Clean Code, Clean Architecture, and Zero-Reload Copilot instructions (.agents)"
---

${INLINED_BODY}
EOF
    echo "  [OK] Generated Zero-Reload Copilot user instructions (inlined via .agents): ${USER_INSTRUCTIONS_FILE}"
    echo ""
    echo "GitHub Copilot CLI Setup (~/.agents):"
    echo "  - User Root: ${COPILOT_AGENTS_DIR}"
    echo "  - Instructions (Zero-Reload inlined): ~/.copilot/instructions/agent-skills.instructions.md"
    echo "  - Skills: Auto-discovered from ~/.agents/skills"
    echo "  - Verification commands: 'copilot instruction list' and 'copilot skill list'"
    echo ""
    echo "GitHub Copilot (VS Code User Settings):"
    echo "  Add the following to your VS Code settings.json:"
    echo "  \"github.copilot.chat.codeGeneration.instructions\": ["
    echo "    {"
    echo "      \"file\": \"${USER_INSTRUCTIONS_FILE}\""
    echo "    }"
    echo "  ]"
  fi

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
  echo "Integrating into Project: ${TARGET_DIR} (Client: ${CLIENT}, Links: ${FOLDER_TYPE})"

  # 1. Create directory link(s): _agents for AGY, .agents for Copilot
  if [[ "$FOLDER_TYPE" == "_agents" || "$FOLDER_TYPE" == "both" ]]; then
    create_symlink "${TARGET_DIR}/_agents" "$REPO_ROOT"
  fi
  if [[ "$FOLDER_TYPE" == ".agents" || "$FOLDER_TYPE" == "both" ]]; then
    create_symlink "${TARGET_DIR}/.agents" "$REPO_ROOT"
  fi

  # 2. Setup .github/copilot-instructions.md (configured for .agents/)
  if [[ "$SETUP_COPILOT" == true ]]; then
    mkdir -p "${TARGET_DIR}/.github"
    DEST_COPILOT="${TARGET_DIR}/.github/copilot-instructions.md"
    if [[ -f "$DEST_COPILOT" && "$FORCE" != true ]]; then
      echo "  [SKIP] .github/copilot-instructions.md already exists (use --force to overwrite)"
    else
      cp -f "$COPILOT_TEMPLATE" "$DEST_COPILOT"
      echo "  [OK] Provisioned ${DEST_COPILOT} (configured for .agents/)"
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
  if [[ "$FOLDER_TYPE" == "_agents" || "$FOLDER_TYPE" == "both" ]]; then
    echo "  - Antigravity (AGY): Discovers skills via _agents/skills and rules via _agents/rules"
  fi
  if [[ "$FOLDER_TYPE" == ".agents" || "$FOLDER_TYPE" == "both" ]]; then
    echo "  - GitHub Copilot: Discovers skills via .agents/skills and instructions via .github/copilot-instructions.md"
  fi
fi
