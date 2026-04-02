#!/usr/bin/env bash
# token-tracker.sh — Stop hook
# Finalizes token usage report from orchestrator-tracked data.
# Orchestrator writes per-agent rows during pipeline; this hook closes the report.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

REPORT_DIR="$PROJECT_ROOT/docs/token-reports"
CURRENT_REPORT="$REPORT_DIR/current-pipeline.md"

# Only finalize if orchestrator created a tracking file
if [ ! -f "$CURRENT_REPORT" ]; then
  exit 0
fi

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
BRANCH=$(cd "$PROJECT_ROOT" && git branch --show-current 2>/dev/null || echo "N/A")

# Calculate totals from the table
TOTAL_TOKENS=$(grep -oP '\d+' "$CURRENT_REPORT" | awk '{s+=$1}END{print s+0}' 2>/dev/null || echo "0")

# Append footer
cat >> "$CURRENT_REPORT" << EOF

---
## Session Totals
- Finalized: $(date '+%Y-%m-%d %H:%M:%S')
- Branch: $BRANCH
- Approximate total tokens: $TOTAL_TOKENS (from agent spawns only)
EOF

# Archive: rename current to timestamped
ARCHIVE="$REPORT_DIR/pipeline-${TIMESTAMP}.md"
cp "$CURRENT_REPORT" "$ARCHIVE"

# Send summary to Telegram if configured
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  AGENT_COUNT=$(grep -c "^|" "$CURRENT_REPORT" 2>/dev/null || echo "0")
  SUMMARY="📊 Token Report: ~${TOTAL_TOKENS} tokens across ${AGENT_COUNT} agent spawns (${BRANCH})"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$SUMMARY" >/dev/null 2>&1 || true
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] TOKEN_REPORT: finalized $ARCHIVE" >> "$SCRIPT_DIR/hook-log.txt"

exit 0
