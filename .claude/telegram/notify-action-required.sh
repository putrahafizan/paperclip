#!/usr/bin/env bash
# Sends action-required notification to Telegram with options
# Usage: notify-action-required.sh "question" "A) option1" "B) option2" "C) option3"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

QUESTION="${1:-Action required}"
shift
OPTIONS=""
for opt in "$@"; do
  OPTIONS="${OPTIONS}
${opt}"
done

bash "$PROJECT_ROOT/.claude/hooks/notify.sh" "🔔 *Action Required*
━━━━━━━━━━━━━━━━━━━━━
${QUESTION}
${OPTIONS}
━━━━━━━━━━━━━━━━━━━━━
Reply with your choice (A, B, C, etc.) or respond in terminal."
