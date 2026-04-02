#!/usr/bin/env bash
# session-summary.sh — Stop hook
# Reads hook-log.txt, compiles summary stats, sends to Telegram.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

LOG_FILE="$SCRIPT_DIR/hook-log.txt"

if [ ! -f "$LOG_FILE" ]; then
  exit 0
fi

BLOCKED=$(grep -c "BLOCKED" "$LOG_FILE" 2>/dev/null || echo "0")
FORMAT_FIXES=$(grep -c "FORMAT" "$LOG_FILE" 2>/dev/null || echo "0")
TEST_FAILS=$(grep -c "TEST FAIL" "$LOG_FILE" 2>/dev/null || echo "0")
NOTIFICATIONS=$(grep -c "NOTIFY" "$LOG_FILE" 2>/dev/null || echo "0")

SUMMARY="📊 Session Summary:
• Blocked operations: $BLOCKED
• Format fixes: $FORMAT_FIXES
• Test failures: $TEST_FAILS
• Notifications: $NOTIFICATIONS"

# Send via Telegram if configured
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$SUMMARY" >/dev/null 2>&1 || true
fi

# Log the summary
echo "[$(date '+%Y-%m-%d %H:%M:%S')] SESSION_END: $SUMMARY" >> "$LOG_FILE"

# Clean up temporary files (but keep the log)
find /tmp -name "claude-hook-*" -mmin +60 -delete 2>/dev/null || true

# === Update Hook Analytics (cumulative) ===
ANALYTICS="$PROJECT_ROOT/docs/hook-analytics.md"

# Buat dari template jika belum ada
if [ ! -f "$ANALYTICS" ]; then
  cp "$PROJECT_ROOT/docs/hook-analytics.md.template" "$ANALYTICS" 2>/dev/null || true
fi

if [ -f "$ANALYTICS" ]; then
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
  sed -i "s/^## Last Updated:.*/## Last Updated: $TIMESTAMP/" "$ANALYTICS"

  # Count events dari hook-log.txt session ini
  LOG="$SCRIPT_DIR/hook-log.txt"
  if [ -f "$LOG" ]; then
    DESIGN_COUNT=$(grep -c "DESIGN" "$LOG" 2>/dev/null || echo "0")
    SECURITY_COUNT=$(grep -c "BLOCKED" "$LOG" 2>/dev/null || echo "0")
    TEST_COUNT=$(grep -c "TEST FAIL" "$LOG" 2>/dev/null || echo "0")
    FORMAT_COUNT=$(grep -c "formatted\|prettier\|black\|ruff" "$LOG" 2>/dev/null || echo "0")

    # Update summary stats (increment)
    if [ "$DESIGN_COUNT" -gt 0 ] || [ "$SECURITY_COUNT" -gt 0 ]; then
      echo "" >> "$ANALYTICS"
      echo "### Session: $TIMESTAMP" >> "$ANALYTICS"
      echo "- Design violations: $DESIGN_COUNT" >> "$ANALYTICS"
      echo "- Security blocks: $SECURITY_COUNT" >> "$ANALYTICS"
      echo "- Test failures: $TEST_COUNT" >> "$ANALYTICS"
      echo "- Format fixes: $FORMAT_COUNT" >> "$ANALYTICS"
    fi
  fi
fi

exit 0
