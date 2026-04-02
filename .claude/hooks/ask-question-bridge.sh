#!/usr/bin/env bash
# ask-question-bridge.sh — PreToolUse hook for AskUserQuestion
# Captures question text, sends to Telegram with inline keyboard
# Supports multi-session: writes to pending-questions/ queue directory
# Does NOT block — exits 0 always so terminal still shows the question

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TELEGRAM_DIR="$PROJECT_ROOT/.claude/telegram"
QUEUE_DIR="$TELEGRAM_DIR/pending-questions"

# Ensure queue directory exists
mkdir -p "$QUEUE_DIR"

# If native channels active, let channel handle Q&A — skip custom bridge
# Channel delivers AskUserQuestion to Telegram natively and routes response
# back into Claude's conversation context (no file queue or tmux needed)
if [ -f "$TELEGRAM_DIR/channel-mode.env" ]; then
  source "$TELEGRAM_DIR/channel-mode.env"
  if [ "${CHANNEL_MODE:-}" = "native" ] && kill -0 "${SESSION_PID:-0}" 2>/dev/null; then
    exit 0
  fi
fi

# Clean up stale pending questions (>10 min old) — don't nuke other sessions' questions
NOW_EPOCH=$(date +%s)
for f in "$QUEUE_DIR"/q-*.json; do
  [ -f "$f" ] || continue
  TS=$(jq -r '.timestamp // empty' "$f" 2>/dev/null)
  [ -z "$TS" ] && continue
  FILE_EPOCH=$(date -d "$TS" +%s 2>/dev/null || echo "0")
  ELAPSED=$((NOW_EPOCH - FILE_EPOCH))
  [ "$ELAPSED" -gt 600 ] && rm -f "$f"
done

# Read JSON from stdin (Claude Code hook format)
INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Extract question data
QUESTION=$(echo "$INPUT" | jq -r '.tool_input.question // .tool_input.questions[0].question // empty' 2>/dev/null || true)
[ -z "$QUESTION" ] && exit 0

# Extract options if available (from AskUserQuestion tool_input.questions[].options[])
OPTIONS_JSON=$(echo "$INPUT" | jq -c '[.tool_input.questions[]?.options[]?.label // empty] | if length == 0 then null else . end' 2>/dev/null || echo "null")

# Generate unique question ID (nanoseconds to avoid collision within same second)
Q_ID="q-$(date +%s%N | head -c 13)"

# Detect tmux pane for response injection
TMUX_TARGET=""
if [ -n "${TMUX:-}" ]; then
  TMUX_TARGET=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)
fi

# Project name for session identification
PROJECT_NAME=$(basename "$PROJECT_ROOT")
SESSION_LABEL="${PROJECT_NAME}"
[ -n "$TMUX_TARGET" ] && SESSION_LABEL="${PROJECT_NAME} (${TMUX_TARGET##*:})"

# Write to queue directory (one file per question)
PENDING_FILE="$QUEUE_DIR/${Q_ID}.json"
cat > "$PENDING_FILE" <<QEOF
{
  "id": "$Q_ID",
  "question": $(echo "$QUESTION" | jq -Rs .),
  "options": ${OPTIONS_JSON:-null},
  "tmux_target": "$TMUX_TARGET",
  "project_name": "$PROJECT_NAME",
  "session_label": "$SESSION_LABEL",
  "timestamp": "$(date -Iseconds)",
  "status": "pending"
}
QEOF

# Send to Telegram (non-blocking, background)
if [ -x "$TELEGRAM_DIR/notify-question.sh" ]; then
  PENDING_FILE="$PENDING_FILE" bash "$TELEGRAM_DIR/notify-question.sh" &
fi

# Always exit 0 — never block AskUserQuestion
exit 0
