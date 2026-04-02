#!/usr/bin/env bash
# file-protect.sh — PreToolUse hook for Write|Edit
# Blocks writes to sensitive files and enforces file-scope-contract.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

LOG_FILE="$SCRIPT_DIR/hook-log.txt"

block() {
  local reason="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] BLOCKED: $reason | file: $FILE_PATH" >> "$LOG_FILE"
  echo "BLOCKED: $reason" >&2
  exit 2
}

# Block: .env files and credentials
if echo "$FILE_PATH" | grep -qE '(^|/)\.env($|\.)'; then
  block "Writing to .env file is forbidden"
fi
if echo "$FILE_PATH" | grep -qiE '(credentials|secrets|private.key|\.pem)'; then
  block "Writing to credentials/secrets file is forbidden"
fi

# Block: agent self-modification
if echo "$FILE_PATH" | grep -qE '\.claude/agents/'; then
  block "Agents cannot self-modify (.claude/agents/ is protected)"
fi

# Allow: docs/, .claude/memory/, .claude/hooks/hook-log.txt
if echo "$FILE_PATH" | grep -qE '^(docs/|\.claude/memory/|\.claude/hooks/hook-log\.txt)'; then
  exit 0
fi

# Enforce file-scope-contract.md if it exists
CONTRACT="$PROJECT_ROOT/docs/file-scope-contract.md"
if [ -f "$CONTRACT" ]; then
  BASENAME=$(basename "$FILE_PATH")
  if grep -q "ALLOWED_MODIFY\|ALLOWED_CREATE" "$CONTRACT"; then
    if ! grep -qF "$FILE_PATH" "$CONTRACT" && ! grep -qF "$BASENAME" "$CONTRACT"; then
      # Check if the file extension/directory is broadly allowed
      if ! echo "$FILE_PATH" | grep -qE '^(docs/|\.claude/|README)'; then
        block "File not in file-scope-contract.md. Check docs/file-scope-contract.md"
      fi
    fi
  fi
fi

exit 0
