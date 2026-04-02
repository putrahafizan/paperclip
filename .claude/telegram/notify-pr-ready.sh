#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PR_URL="${1:-}"
BRANCH="${2:-}"
TITLE="${3:-}"

"$PROJECT_ROOT/.claude/hooks/notify.sh" "📋 *PR Ready for Review*
━━━━━━━━━━━━━━━━━━━━━
Title: $TITLE
Branch: \`$BRANCH\` → \`main\`
URL: $PR_URL
━━━━━━━━━━━━━━━━━━━━━
Ketik /approve di sini atau review langsung di URL."
