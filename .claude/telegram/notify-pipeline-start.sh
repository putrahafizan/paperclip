#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Dipanggil: orchestrator setelah deteksi tipe dan wave plan
TYPE="${1:-UNKNOWN}"
FEATURES="${2:-}"
WAVES="${3:-1}"

"$PROJECT_ROOT/.claude/hooks/notify.sh" "🚀 *Pipeline Started*
━━━━━━━━━━━━━━━━━━━━━
Type: \`$TYPE\`
Features: $FEATURES
Waves: $WAVES
━━━━━━━━━━━━━━━━━━━━━"
