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
elif [[ -f "${PROJECT_ROOT}/Directory.Build.props" ]] || compgen -G "${PROJECT_ROOT}/*.sln" > /dev/null 2>&1 || [[ -n "$(find "$PROJECT_ROOT" -maxdepth 3 -name "*.*proj" -type f 2>/dev/null | head -n 1)" ]]; then
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
    PROJ_FILE=$(find "$PROJECT_ROOT" -maxdepth 3 \( -name "*.csproj" -o -name "*.fsproj" \) -type f 2>/dev/null | head -n 1 || true)
    if [[ -n "$PROJ_FILE" ]]; then
      REL_PROJ="${PROJ_FILE#"${PROJECT_ROOT%/}"/}"
      FORMAT_CHECK_CMD="dotnet format \"${REL_PROJ}\" --verify-no-changes"
      FORMAT_FIX_CMD="dotnet format \"${REL_PROJ}\""
    else
      FORMAT_CHECK_CMD="dotnet format --verify-no-changes"
      FORMAT_FIX_CMD="dotnet format"
    fi
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
elif [[ -f "${PROJECT_ROOT}/build.gradle.kts" ]] || [[ -f "${PROJECT_ROOT}/build.gradle" ]] || [[ -f "${PROJECT_ROOT}/settings.gradle.kts" ]] || [[ -f "${PROJECT_ROOT}/settings.gradle" ]]; then
  GRADLE_CMD="gradle"
  [[ -f "${PROJECT_ROOT}/gradlew" ]] && GRADLE_CMD="./gradlew"
  GRADLE_BUILD_RAW=""
  GRADLE_CATALOG_RAW=""
  while IFS= read -r -d '' gf; do
    if [[ "$(basename "$gf")" == "libs.versions.toml" ]]; then
      GRADLE_CATALOG_RAW+=$'\n'"$(cat "$gf" 2>/dev/null || true)"
    else
      GRADLE_BUILD_RAW+=$'\n'"$(cat "$gf" 2>/dev/null || true)"
    fi
  done < <(find "$PROJECT_ROOT" -maxdepth 3 -type f \
    ! -path "*/.git/*" ! -path "*/.gradle/*" ! -path "*/build/*" ! -path "*/_agents/*" ! -path "*/.agents/*" \
    \( -name "*.gradle" -o -name "*.gradle.kts" -o -name "libs.versions.toml" \) -print0 2>/dev/null)
  GRADLE_RAW="${GRADLE_BUILD_RAW}"$'\n'"${GRADLE_CATALOG_RAW}"

  HAS_SPOTLESS=false
  if grep -qi "spotless" <<< "$GRADLE_RAW"; then HAS_SPOTLESS=true; fi
  HAS_DETEKT=false
  if grep -qi "detekt" <<< "$GRADLE_RAW"; then HAS_DETEKT=true; fi
  HAS_KTLINT=false
  if grep -qi "ktlint" <<< "$GRADLE_RAW"; then HAS_KTLINT=true; fi
  IS_ANDROID=false
  if grep -qiE "com\.android\.(application|library)" <<< "$GRADLE_RAW"; then IS_ANDROID=true; fi

  HAS_KMP_SRC=false
  if [[ -n "$(find "$PROJECT_ROOT" -maxdepth 4 -type d \
    ! -path "*/.git/*" ! -path "*/.gradle/*" ! -path "*/build/*" ! -path "*/_agents/*" ! -path "*/.agents/*" \
    \( -name "commonMain" -o -name "desktopMain" -o -name "jvmMain" \) 2>/dev/null | head -n 1)" ]]; then
    HAS_KMP_SRC=true
  fi
  IS_KMP=false
  if grep -qiE "(kotlin[[:space:]]*\([[:space:]]*[\"']multiplatform[\"'][[:space:]]*\)|org\.jetbrains\.kotlin\.multiplatform|alias[[:space:]]*\([^)]*kotlin[._-]?multiplatform)" <<< "$GRADLE_BUILD_RAW" || \
     grep -qi "org\.jetbrains\.kotlin\.multiplatform" <<< "$GRADLE_CATALOG_RAW" || \
     [[ "$HAS_KMP_SRC" == "true" ]]; then
    IS_KMP=true
  fi

  if [[ "$IS_KMP" == "true" ]] || grep -qi "kotlin" <<< "$GRADLE_RAW" || [[ -n "$(find "$PROJECT_ROOT" -maxdepth 4 -name "*.kt" -type f 2>/dev/null | head -n 1)" ]]; then
    LANG="kotlin"
  else
    LANG="java"
  fi
  SPOTLESS_EXCL=""
  if [[ "$HAS_SPOTLESS" == "true" ]]; then
    SPOTLESS_EXCL=" -x spotlessCheck"
    FORMAT_CHECK_CMD="${GRADLE_CMD} spotlessCheck -q"
    FORMAT_FIX_CMD="${GRADLE_CMD} spotlessApply -q"
  elif [[ "$HAS_KTLINT" == "true" ]]; then
    FORMAT_CHECK_CMD="${GRADLE_CMD} ktlintCheck -q"
    FORMAT_FIX_CMD="${GRADLE_CMD} ktlintFormat -q"
  fi

  if [[ "$IS_KMP" == "true" ]]; then
    STACK="kmp-gradle"
    JVM_TARGETS=()
    while IFS= read -r tname; do
      [[ -z "$tname" ]] && continue
      FOUND_T=false
      if [[ ${#JVM_TARGETS[@]} -gt 0 ]]; then
        for existing in "${JVM_TARGETS[@]}"; do
          [[ "$existing" == "$tname" ]] && FOUND_T=true
        done
      fi
      [[ "$FOUND_T" == "false" ]] && JVM_TARGETS+=("$tname")
    done < <(grep -oiE "(^|[^A-Za-z0-9_.])jvm[[:space:]]*\([[:space:]]*(name[[:space:]]*=[[:space:]]*)?[\"'][A-Za-z][A-Za-z0-9_-]*[\"'][[:space:]]*\)" <<< "$GRADLE_BUILD_RAW" | sed -E "s/.*[\"']([A-Za-z][A-Za-z0-9_-]*)[\"'].*/\1/" || true)

    if grep -qiE "(^|[^A-Za-z0-9_.])jvm[[:space:]]*(\([[:space:]]*\)|\{)" <<< "$GRADLE_BUILD_RAW"; then
      FOUND_JVM=false
      if [[ ${#JVM_TARGETS[@]} -gt 0 ]]; then
        for existing in "${JVM_TARGETS[@]}"; do
          [[ "$existing" == "jvm" ]] && FOUND_JVM=true
        done
      fi
      [[ "$FOUND_JVM" == "false" ]] && JVM_TARGETS+=("jvm")
    fi

    if [[ ${#JVM_TARGETS[@]} -eq 0 ]]; then
      if grep -qiE "(^|[^A-Za-z0-9_])desktopMain([^A-Za-z0-9_]|$)" <<< "$GRADLE_BUILD_RAW" || [[ -n "$(find "$PROJECT_ROOT" -maxdepth 4 -type d ! -path "*/.git/*" ! -path "*/.gradle/*" ! -path "*/build/*" -name "desktopMain" 2>/dev/null | head -n 1)" ]]; then
        JVM_TARGETS+=("desktop")
      fi
      if grep -qiE "(^|[^A-Za-z0-9_])jvmMain([^A-Za-z0-9_]|$)" <<< "$GRADLE_BUILD_RAW" || [[ -n "$(find "$PROJECT_ROOT" -maxdepth 4 -type d ! -path "*/.git/*" ! -path "*/.gradle/*" ! -path "*/build/*" -name "jvmMain" 2>/dev/null | head -n 1)" ]]; then
        JVM_TARGETS+=("jvm")
      fi
    fi

    if [[ ${#JVM_TARGETS[@]} -gt 0 ]]; then
      BUILD_TASKS=""
      TEST_TASKS=""
      for t in "${JVM_TARGETS[@]}"; do
        [[ -n "$BUILD_TASKS" ]] && BUILD_TASKS+=" "
        BUILD_TASKS+="${t}MainClasses ${t}TestClasses"
        [[ -n "$TEST_TASKS" ]] && TEST_TASKS+=" "
        TEST_TASKS+="${t}Test"
      done
      PRIMARY_TARGET="${JVM_TARGETS[0]}"
      BUILD_CMD="${GRADLE_CMD} ${BUILD_TASKS}${SPOTLESS_EXCL} -q"
      TEST_CMD="${GRADLE_CMD} ${TEST_TASKS}${SPOTLESS_EXCL} -q"
      FILTER_SYNTAX="${GRADLE_CMD} ${PRIMARY_TARGET}Test --tests {filter}${SPOTLESS_EXCL} -q"
      if [[ "$HAS_DETEKT" == "true" ]]; then LINT_CMD="${GRADLE_CMD} detekt -q"; else LINT_CMD=""; fi
    elif [[ "$IS_ANDROID" == "true" ]]; then
      BUILD_CMD="${GRADLE_CMD} testDebugUnitTestClasses${SPOTLESS_EXCL} -q"
      TEST_CMD="${GRADLE_CMD} testDebugUnitTest${SPOTLESS_EXCL} -q"
      FILTER_SYNTAX="${GRADLE_CMD} testDebugUnitTest --tests {filter}${SPOTLESS_EXCL} -q"
      LINT_CMD="${GRADLE_CMD} lintDebug -q"
    else
      BUILD_CMD="${GRADLE_CMD} assemble${SPOTLESS_EXCL} -q"
      TEST_CMD="${GRADLE_CMD} allTests${SPOTLESS_EXCL} -q"
      FILTER_SYNTAX="${GRADLE_CMD} allTests${SPOTLESS_EXCL} -q"
      if [[ "$HAS_DETEKT" == "true" ]]; then LINT_CMD="${GRADLE_CMD} detekt -q"; else LINT_CMD=""; fi
    fi
  elif [[ "$IS_ANDROID" == "true" ]]; then
    STACK="android-gradle"
    BUILD_CMD="${GRADLE_CMD} testDebugUnitTestClasses${SPOTLESS_EXCL} -q"
    TEST_CMD="${GRADLE_CMD} testDebugUnitTest${SPOTLESS_EXCL} -q"
    FILTER_SYNTAX="${GRADLE_CMD} testDebugUnitTest --tests {filter}${SPOTLESS_EXCL} -q"
    LINT_CMD="${GRADLE_CMD} lintDebug -q"
  else
    STACK="gradle"
    BUILD_CMD="${GRADLE_CMD} classes testClasses${SPOTLESS_EXCL} -q"
    TEST_CMD="${GRADLE_CMD} test${SPOTLESS_EXCL} -q"
    FILTER_SYNTAX="${GRADLE_CMD} test --tests {filter}${SPOTLESS_EXCL} -q"
    if [[ "$HAS_DETEKT" == "true" ]]; then LINT_CMD="${GRADLE_CMD} detekt -q"; else LINT_CMD=""; fi
  fi
  if [[ -f "${PROJECT_ROOT}/build.gradle.kts" ]]; then MANIFEST="build.gradle.kts"
  elif [[ -f "${PROJECT_ROOT}/build.gradle" ]]; then MANIFEST="build.gradle"
  elif [[ -f "${PROJECT_ROOT}/settings.gradle.kts" ]]; then MANIFEST="settings.gradle.kts"
  else MANIFEST="settings.gradle"; fi
elif [[ -f "${PROJECT_ROOT}/pom.xml" ]]; then
  STACK="maven"
  LANG="java"
  MVN_CMD="mvn"
  [[ -f "${PROJECT_ROOT}/mvnw" ]] && MVN_CMD="./mvnw"
  BUILD_CMD="${MVN_CMD} test-compile -q"
  TEST_CMD="${MVN_CMD} test -q"
  FILTER_SYNTAX="${MVN_CMD} test -q -Dtest={filter}"
  LINT_CMD=""
  if grep -qi "spotless" "${PROJECT_ROOT}/pom.xml" 2>/dev/null; then
    FORMAT_CHECK_CMD="${MVN_CMD} spotless:check -q"
    FORMAT_FIX_CMD="${MVN_CMD} spotless:apply -q"
  fi
  MANIFEST="pom.xml"
elif [[ -f "${PROJECT_ROOT}/CMakeLists.txt" ]] || [[ -f "${PROJECT_ROOT}/CMakePresets.json" ]] || [[ -n "$(find "$PROJECT_ROOT" -maxdepth 3 -name "*.vcxproj" -type f 2>/dev/null | head -n 1)" ]]; then
  LANG="cpp"
  if [[ -f "${PROJECT_ROOT}/CMakeLists.txt" ]] || [[ -f "${PROJECT_ROOT}/CMakePresets.json" ]]; then
    CMAKE_RAW=""
    [[ -f "${PROJECT_ROOT}/CMakeLists.txt" ]] && CMAKE_RAW+=$(cat "${PROJECT_ROOT}/CMakeLists.txt" 2>/dev/null || true)
    [[ -f "${PROJECT_ROOT}/CMakePresets.json" ]] && CMAKE_RAW+=$(cat "${PROJECT_ROOT}/CMakePresets.json" 2>/dev/null || true)
    if echo "$CMAKE_RAW" | grep -qiE "mingw|g\+\+|gcc" || (command -v g++ &>/dev/null && ! command -v cl &>/dev/null); then
      STACK="cmake-mingw"
    else
      STACK="cmake-msvc"
    fi
    BUILD_CMD="cmake --build build"
    TEST_CMD="ctest --test-dir build --output-on-failure"
    FILTER_SYNTAX="ctest --test-dir build --output-on-failure -R {filter}"
    [[ -f "${PROJECT_ROOT}/CMakePresets.json" ]] && MANIFEST="CMakePresets.json" || MANIFEST="CMakeLists.txt"
  else
    STACK="msbuild"
    BUILD_CMD="msbuild -v:quiet"
    TEST_CMD="ctest --output-on-failure"
    FILTER_SYNTAX="ctest --output-on-failure -R {filter}"
    MANIFEST="*.vcxproj"
  fi
  if command -v clang-tidy &>/dev/null; then LINT_CMD="clang-tidy"
  elif command -v cppcheck &>/dev/null; then LINT_CMD="cppcheck --quiet ."
  else LINT_CMD=""; fi
  if command -v clang-format &>/dev/null; then
    FORMAT_CHECK_CMD="clang-format --dry-run --Werror"
    FORMAT_FIX_CMD="clang-format -i"
  fi
fi

SUPPORT_LEVEL="full"
SUPPORT_GAPS_JSON="[]"
ARCH_LANGS="rust csharp typescript javascript python go kotlin java cpp"
GAPS=()

if [[ "$STACK" == "unknown" ]]; then
  SAMPLE_CODE=$(find "$PROJECT_ROOT" -maxdepth 3 -type f \
    ! -path "*/.git/*" ! -path "*/_agents/*" ! -path "*/.agents/*" ! -path "*/node_modules/*" ! -path "*/build/*" ! -path "*/target/*" \
    \( -name "*.dart" -o -name "*.swift" -o -name "*.php" -o -name "*.rb" -o -name "*.zig" -o -name "*.scala" -o -name "*.ex" -o -name "*.exs" \) 2>/dev/null | head -n 1 || true)
  if [[ -n "$SAMPLE_CODE" ]]; then
    case "${SAMPLE_CODE##*.}" in
      dart) LANG="dart" ;; swift) LANG="swift" ;; php) LANG="php" ;; rb) LANG="ruby" ;;
      zig) LANG="zig" ;; scala) LANG="scala" ;; ex|exs) LANG="elixir" ;;
    esac
    GAPS+=("no_build_or_test_runner")
    if [[ ! " $ARCH_LANGS " =~ " $LANG " ]]; then
      GAPS+=("unsupported_clean_arch_or_outline:$LANG")
    fi
    SUPPORT_LEVEL="unsupported"
  fi
else
  if [[ -z "$LINT_CMD" && "$STACK" != "dotnet" ]]; then
    GAPS+=("lint_cmd_missing")
  fi
  if [[ -z "$FORMAT_CHECK_CMD" ]]; then
    GAPS+=("format_check_cmd_missing")
  fi
  if [[ ! " $ARCH_LANGS " =~ " $LANG " ]]; then
    GAPS+=("unsupported_clean_arch_or_outline:$LANG")
  fi
  [[ ${#GAPS[@]} -gt 0 ]] && SUPPORT_LEVEL="partial"
fi

if [[ ${#GAPS[@]} -gt 0 ]]; then
  SUPPORT_GAPS_JSON="["
  for i in "${!GAPS[@]}"; do
    [[ $i -gt 0 ]] && SUPPORT_GAPS_JSON+=","
    SUPPORT_GAPS_JSON+="\"${GAPS[$i]}\""
  done
  SUPPORT_GAPS_JSON+="]"
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
  ESC_FMT_CHECK="${FORMAT_CHECK_CMD//\"/\\\"}"
  ESC_FMT_FIX="${FORMAT_FIX_CMD//\"/\\\"}"
  cat <<EOF
{"stack":"$STACK","language":"$LANG","build_cmd":"$BUILD_CMD","test_cmd":"$TEST_CMD","test_filter_syntax":"$FILTER_SYNTAX","lint_cmd":"$LINT_CMD","format_check_cmd":"$ESC_FMT_CHECK","format_fix_cmd":"$ESC_FMT_FIX","manifest_file":"$MANIFEST","support_level":"$SUPPORT_LEVEL","support_gaps":$SUPPORT_GAPS_JSON}
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
