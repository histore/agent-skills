#!/usr/bin/env bash
# ==============================================================================
# Determines project technology stack, language, build, and quiet testrunner commands.
# ==============================================================================
set -euo pipefail

PROJECT_ROOT=""
JSON_OUTPUT=false

for arg in "$@"; do
  case "$arg" in
    --json|-j)
      JSON_OUTPUT=true
      ;;
    -*)
      ;;
    *)
      if [[ -z "$PROJECT_ROOT" ]]; then
        PROJECT_ROOT="$arg"
      fi
      ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(pwd)"
fi

STACK="unknown"
LANG="unknown"
BUILD_CMD=""
TEST_CMD=""
FILTER_SYNTAX=""
LINT_CMD=""
FORMAT_CHECK_CMD=""
FORMAT_FIX_CMD=""
MANIFEST=""

if [[ -f "${PROJECT_ROOT}/Cargo.toml" ]]; then
  STACK="rust"
  LANG="rust"
  BUILD_CMD="cargo check -q"
  TEST_CMD="cargo test -q"
  FILTER_SYNTAX="cargo test -q {filter}"
  LINT_CMD="cargo clippy -q"
  FORMAT_CHECK_CMD="cargo fmt --check"
  FORMAT_FIX_CMD="cargo fmt"
  MANIFEST="Cargo.toml"
elif [[ -f "${PROJECT_ROOT}/Directory.Build.props" ]] || compgen -G "${PROJECT_ROOT}/*.sln" > /dev/null 2>&1 || compgen -G "${PROJECT_ROOT}/*.*proj" > /dev/null 2>&1; then
  STACK="dotnet"
  LANG="csharp"
  BUILD_CMD="dotnet build -v quiet"
  TEST_CMD="dotnet test --verbosity quiet"
  FILTER_SYNTAX="dotnet test --verbosity quiet --filter {filter}"
  LINT_CMD=""
  SLN_FILE=$(compgen -G "${PROJECT_ROOT}/*.sln" | head -n 1 || true)
  if [[ -n "$SLN_FILE" ]]; then
    FORMAT_CHECK_CMD="dotnet format \"$(basename "$SLN_FILE")\" --verify-no-changes"
    FORMAT_FIX_CMD="dotnet format \"$(basename "$SLN_FILE")\""
  else
    FORMAT_CHECK_CMD="dotnet format --verify-no-changes"
    FORMAT_FIX_CMD="dotnet format"
  fi
  MANIFEST="Directory.Build.props / *.csproj / *.sln"
elif [[ -f "${PROJECT_ROOT}/package.json" ]]; then
  STACK="node"
  if [[ -f "${PROJECT_ROOT}/tsconfig.json" ]]; then
    LANG="typescript"
  else
    LANG="javascript"
  fi
  BUILD_CMD="npm run build --if-present"
  TEST_CMD="npm test --silent"
  FILTER_SYNTAX="npm test --silent -- {filter}"
  LINT_CMD="npm run lint --if-present"
  if grep -q '"format:check"[[:space:]]*:' "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    FORMAT_CHECK_CMD="npm run format:check"
  fi
  if grep -q '"format"[[:space:]]*:' "${PROJECT_ROOT}/package.json" 2>/dev/null; then
    FORMAT_FIX_CMD="npm run format"
  fi
  MANIFEST="package.json"
elif [[ -f "${PROJECT_ROOT}/pyproject.toml" ]] || [[ -f "${PROJECT_ROOT}/requirements.txt" ]] || [[ -f "${PROJECT_ROOT}/Pipfile" ]]; then
  STACK="python"
  LANG="python"
  BUILD_CMD="python -m compileall -q ."
  TEST_CMD="pytest -q"
  FILTER_SYNTAX="pytest -q -k {filter}"
  if command -v ruff &>/dev/null; then
    LINT_CMD="ruff check -q"
    FORMAT_CHECK_CMD="ruff format --check -q"
    FORMAT_FIX_CMD="ruff format -q"
  else
    LINT_CMD="flake8 -q"
  fi
  MANIFEST="pyproject.toml / requirements.txt"
elif [[ -f "${PROJECT_ROOT}/go.mod" ]]; then
  STACK="go"
  LANG="go"
  BUILD_CMD="go build ./..."
  TEST_CMD="go test ./..."
  FILTER_SYNTAX="go test -run {filter} ./..."
  LINT_CMD="golangci-lint run"
  FORMAT_CHECK_CMD="gofmt -l ."
  FORMAT_FIX_CMD="gofmt -w ."
  MANIFEST="go.mod"
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  ESC_FMT_CHECK="${FORMAT_CHECK_CMD//\"/\\\"}"
  ESC_FMT_FIX="${FORMAT_FIX_CMD//\"/\\\"}"
  cat <<EOF
{"stack":"$STACK","language":"$LANG","build_cmd":"$BUILD_CMD","test_cmd":"$TEST_CMD","test_filter_syntax":"$FILTER_SYNTAX","lint_cmd":"$LINT_CMD","format_check_cmd":"$ESC_FMT_CHECK","format_fix_cmd":"$ESC_FMT_FIX","manifest_file":"$MANIFEST"}
EOF
else
  echo "============================================="
  echo "Detected Tech Stack & Testrunner CLI"
  echo "Root: $PROJECT_ROOT"
  echo "============================================="
  echo "  Stack:          $STACK"
  echo "  Language:       $LANG"
  echo "  Manifest:       $MANIFEST"
  echo "  Build Command:  $BUILD_CMD"
  echo "  Test Command:   $TEST_CMD"
  echo "  Filter Syntax:  $FILTER_SYNTAX"
  echo "============================================="
fi
