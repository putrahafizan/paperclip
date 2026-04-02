#!/usr/bin/env bash
# notify-question.sh — Send AskUserQuestion to Telegram with inline keyboard
# Reads question from PENDING_FILE env var or falls back to most recent in queue

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QUEUE_DIR="$SCRIPT_DIR/pending-questions"

# Support both: explicit PENDING_FILE from ask-question-bridge, or fallback
if [ -z "${PENDING_FILE:-}" ] || [ ! -f "${PENDING_FILE:-}" ]; then
  # Find most recent pending question
  PENDING_FILE=$(ls -t "$QUEUE_DIR"/q-*.json 2>/dev/null | head -1)
fi

# Load config
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"

[ -z "$TOKEN" ] || [ -z "$CHAT_ID" ] && exit 0
[ ! -f "$PENDING_FILE" ] && exit 0

# Read question data
Q_ID=$(jq -r '.id' "$PENDING_FILE" 2>/dev/null)
QUESTION=$(jq -r '.question' "$PENDING_FILE" 2>/dev/null)
OPTIONS=$(jq -c '.options // empty' "$PENDING_FILE" 2>/dev/null)
SESSION_LABEL=$(jq -r '.session_label // empty' "$PENDING_FILE" 2>/dev/null)

[ -z "$QUESTION" ] && exit 0

# Build message text with session label
if [ -n "$SESSION_LABEL" ]; then
  MSG_TEXT=$(printf "🔔 *%s*\n━━━━━━━━━━━━━━━━━━━━━\n%s\n━━━━━━━━━━━━━━━━━━━━━\nTap a button or reply in terminal." "$SESSION_LABEL" "$QUESTION")
else
  MSG_TEXT=$(printf "🔔 *Claude Code — Action Required*\n━━━━━━━━━━━━━━━━━━━━━\n%s\n━━━━━━━━━━━━━━━━━━━━━\nTap a button or reply in terminal." "$QUESTION")
fi

# Build inline keyboard based on available options
build_keyboard() {
  local q_id="$1"

  # If explicit options from AskUserQuestion tool
  if [ -n "$OPTIONS" ] && [ "$OPTIONS" != "null" ] && [ "$OPTIONS" != "[]" ]; then
    local buttons=""
    local i=0
    while IFS= read -r label; do
      [ -z "$label" ] && continue
      # Truncate label for button (max ~40 chars for readability)
      local short_label="${label:0:40}"
      local cb_data="${q_id}:${i}"
      if [ -n "$buttons" ]; then
        buttons="${buttons},"
      fi
      buttons="${buttons}{\"text\":\"${short_label}\",\"callback_data\":\"${cb_data}\"}"
      i=$((i + 1))
    done < <(echo "$OPTIONS" | jq -r '.[]' 2>/dev/null)

    # Arrange buttons: 2 per row max
    local rows=""
    local row=""
    local count=0
    for btn in $(echo "[$buttons]" | jq -c '.[]' 2>/dev/null); do
      if [ -n "$row" ]; then
        row="${row},${btn}"
      else
        row="${btn}"
      fi
      count=$((count + 1))
      if [ $count -ge 2 ]; then
        [ -n "$rows" ] && rows="${rows},"
        rows="${rows}[${row}]"
        row=""
        count=0
      fi
    done
    # Flush remaining
    if [ -n "$row" ]; then
      [ -n "$rows" ] && rows="${rows},"
      rows="${rows}[${row}]"
    fi

    echo "{\"inline_keyboard\":[${rows}]}"
    return
  fi

  # Auto-detect from question text
  local q_lower=$(echo "$QUESTION" | tr '[:upper:]' '[:lower:]')

  # Check for approve/commit/push/proceed patterns
  if echo "$q_lower" | grep -qE '(approve|commit|push|proceed|continue|deploy|merge)'; then
    echo "{\"inline_keyboard\":[[{\"text\":\"✅ Approve\",\"callback_data\":\"${q_id}:approve\"},{\"text\":\"❌ Reject\",\"callback_data\":\"${q_id}:reject\"}]]}"
    return
  fi

  # Check for yes/no patterns
  if echo "$q_lower" | grep -qE '(do you want|shall i|should i|would you|want me to|ready to)'; then
    echo "{\"inline_keyboard\":[[{\"text\":\"✅ Yes\",\"callback_data\":\"${q_id}:yes\"},{\"text\":\"❌ No\",\"callback_data\":\"${q_id}:no\"}]]}"
    return
  fi

  # Default: approve/reject/skip
  echo "{\"inline_keyboard\":[[{\"text\":\"✅ Approve\",\"callback_data\":\"${q_id}:approve\"},{\"text\":\"❌ Reject\",\"callback_data\":\"${q_id}:reject\"},{\"text\":\"⏭ Skip\",\"callback_data\":\"${q_id}:skip\"}]]}"
}

KEYBOARD=$(build_keyboard "$Q_ID")

# Send message with inline keyboard
RESULT=$(curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "{
    \"chat_id\": \"${CHAT_ID}\",
    \"text\": $(echo "$MSG_TEXT" | jq -Rs .),
    \"parse_mode\": \"Markdown\",
    \"disable_web_page_preview\": true,
    \"reply_markup\": ${KEYBOARD}
  }" 2>/dev/null || echo '{"ok":false}')

# Save message_id for later editing (when answered)
MSG_ID=$(echo "$RESULT" | jq -r '.result.message_id // empty' 2>/dev/null)
if [ -n "$MSG_ID" ]; then
  # Update pending file with message_id
  TMP=$(mktemp)
  jq --arg mid "$MSG_ID" '. + {telegram_message_id: $mid}' "$PENDING_FILE" > "$TMP" && mv "$TMP" "$PENDING_FILE"
fi

exit 0
