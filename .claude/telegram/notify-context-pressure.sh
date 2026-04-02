#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WAVE_NUM="${1:-?}"
FILES_DONE="${2:-0}"
FILES_TOTAL="${3:-0}"

"$PROJECT_ROOT/.claude/hooks/notify.sh" "⚠️ *Context limit approaching*
━━━━━━━━━━━━━━━━━━━━━
Current wave: ${WAVE_NUM}
Progress: ${FILES_DONE}/${FILES_TOTAL} files
State saved to wave-execution-state.md
━━━━━━━━━━━━━━━━━━━━━
Run \`/start resume\` to continue."
