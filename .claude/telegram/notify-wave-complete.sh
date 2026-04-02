#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WAVE_NUM="${1:-?}"
WAVE_TOTAL="${2:-?}"
WAVE_NAME="${3:-}"
FILES_DONE="${4:-0}"
FILES_TOTAL="${5:-0}"

"$PROJECT_ROOT/.claude/hooks/notify.sh" "✅ *Wave ${WAVE_NUM}/${WAVE_TOTAL} complete*
━━━━━━━━━━━━━━━━━━━━━
Wave: ${WAVE_NAME}
Files: ${FILES_DONE}/${FILES_TOTAL}
━━━━━━━━━━━━━━━━━━━━━"
