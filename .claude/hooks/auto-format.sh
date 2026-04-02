#!/usr/bin/env bash
# auto-format.sh — PostToolUse hook for Write|Edit
# Auto-formats code files. Always exit 0 (non-blocking).

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Skip non-code files
if echo "$FILE_PATH" | grep -qE '\.(md|json|yml|yaml|txt|template|log|csv|xml)$'; then
  exit 0
fi

EXT="${FILE_PATH##*.}"

case "$EXT" in
  php)
    if command -v php-cs-fixer &>/dev/null; then
      php-cs-fixer fix "$FILE_PATH" --quiet 2>/dev/null || true
    fi
    ;;
  js|ts|jsx|tsx|css|scss)
    if command -v prettier &>/dev/null; then
      prettier --write "$FILE_PATH" --log-level silent 2>/dev/null || true
    elif command -v npx &>/dev/null; then
      npx prettier --write "$FILE_PATH" --log-level silent 2>/dev/null || true
    fi
    ;;
  py)
    if command -v black &>/dev/null; then
      black --quiet "$FILE_PATH" 2>/dev/null || true
    fi
    if command -v ruff &>/dev/null; then
      ruff check --fix --quiet "$FILE_PATH" 2>/dev/null || true
    fi
    ;;
esac

exit 0
