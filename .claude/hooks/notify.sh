#!/usr/bin/env bash
# notify.sh — Send notifications to Telegram + local log
# Called by: Notification hook, other telegram scripts, agents
# Supports multi-session: adds project label, uses queue directory
# Always exit 0 (non-blocking)

# Resolve project root from script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_NAME=$(basename "$PROJECT_ROOT")

# === CONFIGURATION ===
# Source .env from project root (absolute path)
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"
LOG_FILE="$SCRIPT_DIR/hook-log.txt"

# Accept message from argument OR stdin
if [ $# -gt 0 ]; then
  MESSAGE="$*"
else
  # Try to parse JSON from stdin (Claude Code hook format)
  INPUT=$(cat 2>/dev/null || true)
  if [ -n "$INPUT" ]; then
    # Try jq first, fall back to raw input
    if command -v jq &>/dev/null; then
      PARSED=$(echo "$INPUT" | jq -r '.message // .notification // .title // empty' 2>/dev/null || true)
      BODY=$(echo "$INPUT" | jq -r '.body // empty' 2>/dev/null || true)
      if [ -n "$PARSED" ]; then
        MESSAGE="$PARSED"
        [ -n "$BODY" ] && MESSAGE="$MESSAGE: $BODY"
      else
        MESSAGE="$INPUT"
      fi
    else
      MESSAGE="$INPUT"
    fi
  fi
fi

# Fallback if still empty
[ -z "${MESSAGE:-}" ] && MESSAGE="Claude Code notification (no message body)"

# === TIMESTAMP ===
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# === LOG (always, even without Telegram) ===
echo "[$TIMESTAMP] NOTIFY: [$PROJECT_NAME] $MESSAGE" >> "$LOG_FILE" 2>/dev/null || true

# === DETECT QUESTION/APPROVAL PATTERNS → redirect to inline keyboard ===
TELEGRAM_DIR="$PROJECT_ROOT/.claude/telegram"
QUEUE_DIR="$TELEGRAM_DIR/pending-questions"
MSG_LOWER=$(echo "$MESSAGE" | tr '[:upper:]' '[:lower:]')

if echo "$MSG_LOWER" | grep -qE '(waiting for your input|waiting for input|needs your approval|approval for the plan|approve|permission)'; then
  mkdir -p "$QUEUE_DIR"

  # Detect known option patterns from notification message
  OPTIONS_JSON="null"

  # Plan approval (ExitPlanMode) — 3 known options
  if echo "$MSG_LOWER" | grep -qE '(approval for the plan|needs your approval for the plan)'; then
    OPTIONS_JSON='["Yes, bypass permissions","Yes, manually approve","Tell Claude what to change"]'
  # Permission/tool approval
  elif echo "$MSG_LOWER" | grep -qE '(permission to|wants to|allow.*tool)'; then
    OPTIONS_JSON='["Allow","Deny"]'
  fi

  # Write pending question to queue directory
  Q_ID="q-$(date +%s%N | head -c 13)"
  TMUX_TARGET=""
  if [ -n "${TMUX:-}" ]; then
    TMUX_TARGET=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)
  fi

  SESSION_LABEL="${PROJECT_NAME}"
  [ -n "$TMUX_TARGET" ] && SESSION_LABEL="${PROJECT_NAME} (${TMUX_TARGET##*:})"

  PENDING_FILE="$QUEUE_DIR/${Q_ID}.json"
  cat > "$PENDING_FILE" <<QEOF
{
  "id": "$Q_ID",
  "question": $(echo "$MESSAGE" | jq -Rs .),
  "options": ${OPTIONS_JSON},
  "tmux_target": "$TMUX_TARGET",
  "project_name": "$PROJECT_NAME",
  "session_label": "$SESSION_LABEL",
  "timestamp": "$(date -Iseconds)",
  "status": "pending"
}
QEOF

  # Send with inline keyboard buttons instead of plain text
  if [ -x "$TELEGRAM_DIR/notify-question.sh" ]; then
    PENDING_FILE="$PENDING_FILE" bash "$TELEGRAM_DIR/notify-question.sh"
    exit 0
  fi
fi

# === SEND TO TELEGRAM (plain text for non-question notifications) ===
if [ -n "$TOKEN" ] && [ -n "$CHAT_ID" ]; then
  # Add project label prefix
  LABELED_MSG="[${PROJECT_NAME}] ${MESSAGE}"
  # Truncate message if too long (Telegram limit: 4096 chars)
  MSG_TRUNCATED=$(echo "$LABELED_MSG" | head -c 4000)

  # Send synchronously so we catch errors
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${MSG_TRUNCATED}" \
    -d "disable_web_page_preview=true" \
    > /dev/null 2>&1 || true
fi

exit 0
