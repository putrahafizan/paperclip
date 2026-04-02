#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Dipanggil: security-gate.sh saat exit 2
COMMAND="${1:-unknown}"
AGENT="${2:-unknown}"

"$PROJECT_ROOT/.claude/hooks/notify.sh" "🚫 *SECURITY BLOCK*
━━━━━━━━━━━━━━━━━━━━━
Agent: \`$AGENT\`
Command: \`$COMMAND\`
Action: Blocked. Claude akan coba strategi lain.
━━━━━━━━━━━━━━━━━━━━━"
