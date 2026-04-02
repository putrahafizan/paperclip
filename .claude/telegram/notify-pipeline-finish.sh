#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Dipanggil: orchestrator setelah PR creation
PR_URL="${1:-no URL}"
DURATION="${2:-unknown}"
FEATURES="${3:-}"

"$PROJECT_ROOT/.claude/hooks/notify.sh" "✅ *Pipeline Complete*
━━━━━━━━━━━━━━━━━━━━━
Duration: $DURATION
Features: $FEATURES
PR: $PR_URL
━━━━━━━━━━━━━━━━━━━━━
Review and merge when ready."
