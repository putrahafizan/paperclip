#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REASON="${1:-wave-transition}"
WAVE="${2:-}"

"$PROJECT_ROOT/.claude/hooks/notify.sh" "🔄 *Context compacted*
Reason: ${REASON}
Wave: ${WAVE}
Continuing execution..."
