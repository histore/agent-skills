#!/usr/bin/env bash
# Deterministic code outline and AST signature extractor.
# Extracts structural declarations (classes, interfaces, structs, traits, enums, functions,
# and method signatures) from source files with zero token overhead.

set -euo pipefail

TARGET_PATH=""
RECURSE=true
JSON_OUTPUT=false
REPO_ROOT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path|-p)
            TARGET_PATH="$2"
            shift 2
            ;;
        --recurse)
            RECURSE=true
            shift
            ;;
        --no-recurse)
            RECURSE=false
            shift
            ;;
        --repo-root)
            REPO_ROOT="$2"
            shift 2
            ;;
        --json|-JsonOutput|-json|-j)
            JSON_OUTPUT=true
            shift
            ;;
        -*)
            shift
            ;;
        *)
            if [[ -z "$TARGET_PATH" ]]; then
                TARGET_PATH="$1"
            fi
            shift
            ;;
    esac
done

if [[ -z "$TARGET_PATH" ]]; then
    TARGET_PATH="."
fi

if [[ -z "$REPO_ROOT" ]]; then
    SUPERPROJECT=$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)
    if [[ -n "$SUPERPROJECT" ]]; then
        REPO_ROOT="$SUPERPROJECT"
    else
        TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null || true)
        if [[ -n "$TOPLEVEL" ]]; then
            REPO_ROOT="$TOPLEVEL"
            if [[ "$REPO_ROOT" =~ /(_agents|\.agents)$ ]]; then
                REPO_ROOT="$(dirname "$REPO_ROOT")"
            fi
        else
            REPO_ROOT="$(pwd)"
        fi
    fi
fi

if [[ ! -e "$TARGET_PATH" ]]; then
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo '{"status":"error","message":"Path not found","files":[]}'
    else
        echo "Path not found: $TARGET_PATH" >&2
    fi
    exit 1
fi

if command -v python3 &>/dev/null; then
    python3 - "$TARGET_PATH" "$REPO_ROOT" "$RECURSE" "$JSON_OUTPUT" << 'EOF'
import json
import os
import re
import sys

target_path, repo_root, recurse_str, json_out_str = sys.argv[1:5]
recurse = recurse_str == "true"
json_out = json_out_str == "true"
repo_root_abs = os.path.abspath(repo_root)
target_abs = os.path.abspath(target_path)

ext_lang = {
    ".cs": "csharp",
    ".rs": "rust",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".js": "javascript",
    ".py": "python",
    ".go": "go",
    ".kt": "kotlin",
    ".c": "cpp",
    ".cpp": "cpp",
    ".cc": "cpp",
    ".cxx": "cpp",
    ".h": "cpp",
    ".hpp": "cpp",
    ".hxx": "cpp",
    ".qml": "qml",
    ".ps1": "powershell",
    ".psm1": "powershell",
    ".sh": "bash",
    ".bash": "bash",
}
ignored_dirs = {".git", "_agents", ".agents", "node_modules", "bin", "obj", "target", ".vs", ".pytest_cache"}

files_to_scan = []
if os.path.isfile(target_abs):
    files_to_scan.append(target_abs)
else:
    for root, dirs, files in os.walk(target_abs):
        dirs[:] = [d for d in sorted(dirs) if d not in ignored_dirs]
        for fname in sorted(files):
            ext = os.path.splitext(fname)[1].lower()
            if ext in ext_lang:
                files_to_scan.append(os.path.join(root, fname))
        if not recurse:
            break

def parse_signatures(filepath):
    ext = os.path.splitext(filepath)[1].lower()
    lang = ext_lang.get(ext, "unknown")
    sigs = []
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except Exception:
        lines = []

    for idx, raw in enumerate(lines, 1):
        trimmed = raw.strip()
        if not trimmed or trimmed.startswith(("//", "#", "/*", "*")):
            continue
        kind = None
        sig = None
        vis = "internal"

        if lang == "csharp":
            m = re.match(r'^(public|internal|protected|private)?\s*(static|abstract|sealed|virtual|override)?\s*(interface|class|record|struct|enum)\s+([A-Za-z0-9_<>]+)', trimmed)
            if m:
                kind = m.group(3)
                sig = trimmed.rstrip("{").strip()
                vis = m.group(1) or "internal"
            else:
                m2 = re.match(r'^(public|protected|internal)\s+.*?\s+([A-Za-z0-9_<>]+)\s*\(', trimmed)
                if m2 and not re.search(r'\b(if|while|for|switch|catch)\b', trimmed):
                    kind = "method"
                    sig = trimmed.rstrip("{;").strip()
                    vis = m2.group(1)
        elif lang == "rust":
            m = re.match(r'^(pub(?:\([a-z\s_]+\))?)?\s*(struct|enum|trait|type|union)\s+([A-Za-z0-9_]+)', trimmed)
            if m:
                kind = m.group(2)
                sig = trimmed.rstrip("{").strip()
                vis = m.group(1) or "private"
            else:
                m2 = re.match(r'^(pub(?:\([a-z\s_]+\))?)?\s*(?:async\s+)?(?:const\s+)?fn\s+([A-Za-z0-9_]+)', trimmed)
                if m2:
                    kind = "fn"
                    sig = trimmed.rstrip("{").strip()
                    vis = m2.group(1) or "private"
                else:
                    m3 = re.match(r'^impl(?:<.*?>)?\s+([A-Za-z0-9_<>]+)', trimmed)
                    if m3:
                        kind = "impl"
                        sig = trimmed.rstrip("{").strip()
                        vis = "pub"
        elif lang == "typescript":
            m = re.match(r'^(export\s+)?(?:default\s+)?(interface|type|class|enum)\s+([A-Za-z0-9_<>]+)', trimmed)
            if m:
                kind = m.group(2)
                sig = trimmed.rstrip("{").strip()
                vis = "export" if m.group(1) else "local"
            else:
                m2 = re.match(r'^(export\s+)?(?:async\s+)?function\s+([A-Za-z0-9_<>]+)', trimmed)
                if m2:
                    kind = "function"
                    sig = trimmed.rstrip("{").strip()
                    vis = "export" if m2.group(1) else "local"
        elif lang == "javascript":
            m = re.match(r'^(export\s+)?(class)\s+([A-Za-z0-9_]+)', trimmed)
            if m:
                kind = "class"
                sig = trimmed.rstrip("{").strip()
                vis = "export" if m.group(1) else "local"
            else:
                m2 = re.match(r'^(export\s+)?(?:async\s+)?function\s+([A-Za-z0-9_]+)', trimmed)
                if m2:
                    kind = "function"
                    sig = trimmed.rstrip("{").strip()
                    vis = "export" if m2.group(1) else "local"
        elif lang == "python":
            m = re.match(r'^(class)\s+([A-Za-z0-9_]+)', trimmed)
            if m:
                kind = "class"
                sig = trimmed.rstrip(":").strip()
                vis = "private" if m.group(2).startswith("_") else "public"
            else:
                m2 = re.match(r'^(?:async\s+)?def\s+([A-Za-z0-9_]+)\s*\(', trimmed)
                if m2:
                    kind = "def"
                    sig = trimmed.rstrip(":").strip()
                    vis = "private" if m2.group(1).startswith("_") else "public"
        elif lang == "go":
            m = re.match(r'^type\s+([A-Za-z0-9_]+)\s+(struct|interface)', trimmed)
            if m:
                kind = m.group(2)
                sig = trimmed.rstrip("{").strip()
                vis = "exported" if m.group(1)[0].isupper() else "package"
            else:
                m2 = re.match(r'^func\s+(?:\([A-Za-z0-9_*\s]+\)\s+)?([A-Za-z0-9_]+)\s*\(', trimmed)
                if m2:
                    kind = "func"
                    sig = trimmed.rstrip("{").strip()
                    vis = "exported" if m2.group(1)[0].isupper() else "package"
        elif lang == "kotlin":
            m = re.match(r'^(public|internal|protected|private)?\s*(?:expect\s+|actual\s+)?(?:sealed|data|open|abstract|value|enum|annotation)?\s*(class|interface|object|enum\s+class)\s+([A-Za-z0-9_<>]+)', trimmed)
            if m:
                kind = m.group(2)
                sig = trimmed.rstrip("{").strip()
                vis = m.group(1) or "public"
            else:
                m2 = re.match(r'^(@Composable\s+)?(public|internal|protected|private)?\s*(?:expect\s+|actual\s+|override\s+|inline\s+|suspend\s+|operator\s+|infix\s+)*fun\s+(?:<[^>]+>\s*)?([A-Za-z0-9_.<>]+)\s*\(', trimmed)
                if m2:
                    kind = "composable" if m2.group(1) else "fun"
                    sig = trimmed.rstrip("{=").strip()
                    vis = m2.group(2) or "public"
        elif lang == "cpp":
            m = re.match(r'^(namespace|class|struct|enum\s+class|enum)\s+([A-Za-z0-9_]+)', trimmed)
            if m:
                kind = m.group(1)
                sig = trimmed.rstrip("{;").strip()
                vis = "public"
            elif re.match(r'^(Q_OBJECT|Q_PROPERTY\s*\(|Q_INVOKABLE\b|signals:|slots:|public\s+slots:|private\s+slots:)', trimmed):
                kind = "qt_meta"
                sig = trimmed.rstrip("{").strip()
                vis = "public"
            else:
                m2 = re.match(r'^(?:(?:virtual|static|inline|explicit|constexpr)\s+)*[\w:<>~*&]+\s+([A-Za-z0-9_:~]+)\s*\([^)]*\)', trimmed)
                if m2 and not re.match(r'^(if|while|for|switch|catch|return)\b', trimmed):
                    kind = "function"
                    sig = trimmed.rstrip("{;").strip()
                    vis = "public"
        elif lang == "qml":
            m = re.match(r'^([A-Z][A-Za-z0-9_.]*)\s*\{$', trimmed)
            if m:
                kind = "component"
                sig = m.group(1)
                vis = "public"
            elif re.match(r'^(?:readonly\s+)?property\s+[\w<>]+\s+\w+', trimmed):
                kind = "property"
                sig = trimmed
                vis = "public"
            else:
                m2 = re.match(r'^(signal|function)\s+([A-Za-z0-9_]+)\s*\(', trimmed)
                if m2:
                    kind = m2.group(1)
                    sig = trimmed.rstrip("{").strip()
                    vis = "public"
        elif lang == "powershell":
            m = re.match(r'^(class|enum)\s+([A-Za-z0-9_]+)', trimmed, re.IGNORECASE)
            if m:
                kind = m.group(1).lower()
                sig = trimmed.rstrip("{").strip()
                vis = "public"
            else:
                m2 = re.match(r'^(function|filter)\s+([A-Za-z0-9_:-]+)', trimmed, re.IGNORECASE)
                if m2:
                    kind = m2.group(1).lower()
                    sig = trimmed.rstrip("{").strip()
                    vis = "public"
        elif lang == "bash":
            m = re.match(r'^function\s+([A-Za-z_][A-Za-z0-9_-]*)', trimmed)
            if m:
                kind = "function"
                sig = trimmed.rstrip("{").strip()
                vis = "public"
            else:
                m2 = re.match(r'^([A-Za-z_][A-Za-z0-9_-]*)\s*\(\s*\)\s*\{?', trimmed)
                if m2:
                    kind = "function"
                    sig = trimmed.rstrip("{").strip()
                    vis = "public"

        if kind and sig:
            sigs.append({"line": idx, "kind": kind, "visibility": vis, "signature": sig})

    rel = os.path.relpath(filepath, repo_root_abs).replace("\\", "/")
    return {
        "file": rel,
        "language": lang,
        "signatures_count": len(sigs),
        "signatures": sigs,
    }

results = []
for fp in files_to_scan:
    parsed = parse_signatures(fp)
    if parsed["signatures_count"] > 0:
        results.append(parsed)

if json_out:
    print(json.dumps({"status": "pass", "total_files": len(results), "files": results}, separators=(",", ":")))
else:
    print("=============================================")
    print("Code Outline & Structural AST Inspector")
    print(f"Files: {len(results)} scanned under {target_path}")
    print("=============================================")
    if not results:
        print("No public types or method signatures discovered.")
    else:
        for r in results:
            print(f"\n[{r['language']}] {r['file']}")
            for s in r["signatures"]:
                kind_tag = f"[{s['kind']}]".ljust(11)
                print(f"  L{str(s['line']).ljust(4)} {kind_tag} {s['signature']}")
    print("\n=============================================")
EOF
    exit 0
fi

FILES=()
if [[ -f "$TARGET_PATH" ]]; then
    FILES+=("$TARGET_PATH")
else
    if [[ "$RECURSE" == "true" ]]; then
        while IFS= read -r -d '' file; do
            FILES+=("$file")
        done < <(find "$TARGET_PATH" -type f \( -name "*.cs" -o -name "*.rs" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.py" -o -name "*.go" \) \
            ! -path "*/.git/*" ! -path "*/_agents/*" ! -path "*/.agents/*" ! -path "*/node_modules/*" ! -path "*/bin/*" ! -path "*/obj/*" ! -path "*/target/*" -print0 2>/dev/null || true)
    else
        while IFS= read -r -d '' file; do
            FILES+=("$file")
        done < <(find "$TARGET_PATH" -maxdepth 1 -type f \( -name "*.cs" -o -name "*.rs" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.py" -o -name "*.go" \) \
            ! -path "*/.git/*" ! -path "*/_agents/*" ! -path "*/.agents/*" ! -path "*/node_modules/*" ! -path "*/bin/*" ! -path "*/obj/*" ! -path "*/target/*" -print0 2>/dev/null || true)
    fi
fi

TOTAL_FILES=${#FILES[@]}
if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "{\"status\":\"pass\",\"total_files\":$TOTAL_FILES,\"files\":[]}"
else
    echo "============================================="
    echo "Code Outline & Structural AST Inspector"
    echo "Files: $TOTAL_FILES scanned under $TARGET_PATH"
    echo "============================================="
    for f in "${FILES[@]:-}"; do
        [[ -z "$f" ]] && continue
        rel="${f#"$REPO_ROOT"/}"
        echo -e "\n$rel:"
        grep -nE '^[[:space:]]*(pub(\([a-z[:space:]_]+\))?|public|export|class|def|func|interface|struct|enum|trait|type)' "$f" 2>/dev/null | head -n 30 || true
    done
    echo "============================================="
fi

exit 0
