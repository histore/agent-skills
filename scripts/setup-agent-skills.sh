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
FORCE=false

print_usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -p, --project <dir>      Path to target project to integrate into"
  echo "  -g, --global             Install globally in user home (~/.gemini/config)"
  echo "  -t, --folder-type <type> Link name: '_agents' (default), '.agents', or 'both'"
  echo "  --skip-copilot           Skip creating .github/copilot-instructions.md"
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
  local link_path="$1"
  local target_path="$2"

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

  # 2. Copy global copilot-instructions.md
  GLOBAL_COPILOT="${GEMINI_CONFIG_DIR}/copilot-instructions.md"
  cp -f "$COPILOT_TEMPLATE" "$GLOBAL_COPILOT"
  echo "  [OK] Copied global Copilot Lite instructions: ${GLOBAL_COPILOT}"

  echo ""
  echo "Antigravity / Gemini Setup:"
  echo "  All skills and rules are now automatically active across all projects."
  echo ""
  echo "GitHub Copilot Setup (VS Code User Settings):"
  echo "  To enable Copilot Lite globally, add the following to your VS Code settings.json:"
  echo "  \"github.copilot.chat.customInstructions\": ["
  echo "    {"
  echo "      \"path\": \"${GLOBAL_COPILOT}\""
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

  echo ""
  echo "Project Integration Complete!"
  echo "  - Antigravity: Discovers skills via _agents/skills and rules via _agents/rules"
  echo "  - Copilot: Governed cleanly by .github/copilot-instructions.md (Lite mode)"
fi
