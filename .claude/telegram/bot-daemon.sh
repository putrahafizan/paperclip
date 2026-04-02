#!/usr/bin/env bash
# bot-daemon.sh — Long-polling daemon for Telegram bot commands
# Receives /status, /approve, /reject, /log, /retro, /run, /cancel, /queue from programmer
# Also handles document uploads (.docx briefs) for remote pipeline triggering
# Supports multi-session: routes responses via pending-questions/ queue

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load config
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi

TOKEN="${TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"

if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo "ERROR: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not set in .env" >&2
  exit 1
fi

POLL_TIMEOUT=30
COMMAND_FILE="$SCRIPT_DIR/incoming-command.txt"
QUEUE_DIR="$SCRIPT_DIR/pending-questions"
RESPONSES_DIR="$SCRIPT_DIR/responses"
PID_FILE="$SCRIPT_DIR/daemon.pid"
MODE_FILE="$SCRIPT_DIR/channel-mode.env"
TRIGGER_FILE="$SCRIPT_DIR/trigger-task.json"
NOTIFY="$PROJECT_ROOT/.claude/hooks/notify.sh"
LAUNCH="$SCRIPT_DIR/launch-pipeline.sh"

# Ensure directories exist
mkdir -p "$QUEUE_DIR" "$RESPONSES_DIR" "$PROJECT_ROOT/briefs"

# Write PID for clean shutdown
echo $$ > "$PID_FILE"
trap "rm -f '$PID_FILE'; exit 0" SIGTERM SIGINT

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# Send message to Telegram (direct, not via notify.sh — for daemon's own responses)
send_msg() {
  local text="$1"
  curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    --data-urlencode "text=${text}" > /dev/null 2>&1 || true
}

# Find pending question file by Q_ID
find_pending() {
  local q_id="$1"
  local f="$QUEUE_DIR/${q_id}.json"
  [ -f "$f" ] && echo "$f" && return 0
  # Fallback: search all files for matching ID
  for f in "$QUEUE_DIR"/q-*.json; do
    [ -f "$f" ] || continue
    local fid=$(jq -r '.id // empty' "$f" 2>/dev/null)
    [ "$fid" = "$q_id" ] && echo "$f" && return 0
  done
  return 1
}

# Find most recent pending question (for free-text responses)
find_latest_pending() {
  ls -t "$QUEUE_DIR"/q-*.json 2>/dev/null | head -1
}

# Check if a pipeline session is currently running
is_pipeline_running() {
  if [ -f "$MODE_FILE" ]; then
    source "$MODE_FILE"
    kill -0 "${SESSION_PID:-0}" 2>/dev/null && return 0
  fi
  tmux has-session -t "claude-pipeline" 2>/dev/null && return 0
  return 1
}

log "Bot daemon started. Polling Telegram..."

# Get latest update_id to skip old messages
INIT=$(curl -s -m 10 "https://api.telegram.org/bot${TOKEN}/getUpdates?limit=1&offset=-1" 2>/dev/null)
OFFSET=$(echo "$INIT" | jq -r '.result[-1].update_id // 0' 2>/dev/null || echo "0")
[ "$OFFSET" != "0" ] && OFFSET=$((OFFSET + 1))
log "Starting from offset: $OFFSET"

while true; do
  # Long poll Telegram
  RESPONSE=$(curl -s -m $((POLL_TIMEOUT + 5)) \
    "https://api.telegram.org/bot${TOKEN}/getUpdates?offset=${OFFSET}&timeout=${POLL_TIMEOUT}&allowed_updates=%5B%22message%22%2C%22callback_query%22%5D" \
    2>/dev/null || echo '{"ok":false}')

  # Check if response is valid
  OK=$(echo "$RESPONSE" | jq -r '.ok' 2>/dev/null || echo "false")
  if [ "$OK" != "true" ]; then
    sleep 5
    continue
  fi

  # Count results
  COUNT=$(echo "$RESPONSE" | jq -r '.result | length' 2>/dev/null || echo "0")
  [ "$COUNT" = "0" ] && continue

  # Process each update using process substitution (not pipe — preserves OFFSET)
  while IFS= read -r UPDATE; do
    UPDATE_ID=$(echo "$UPDATE" | jq -r '.update_id')

    # Update offset BEFORE processing (so we don't reprocess on crash)
    OFFSET=$((UPDATE_ID + 1))

    # === CALLBACK QUERY (inline keyboard button press) ===
    CALLBACK_ID=$(echo "$UPDATE" | jq -r '.callback_query.id // empty' 2>/dev/null)
    if [ -n "$CALLBACK_ID" ]; then
      CALLBACK_DATA=$(echo "$UPDATE" | jq -r '.callback_query.data // empty')
      CALLBACK_FROM=$(echo "$UPDATE" | jq -r '.callback_query.message.chat.id')
      CALLBACK_MSG_ID=$(echo "$UPDATE" | jq -r '.callback_query.message.message_id')

      # Auth check
      [ "$CALLBACK_FROM" != "$CHAT_ID" ] && continue

      # Parse callback_data: "q-1711300000:approve" or "q-1711300000123:0"
      Q_ID="${CALLBACK_DATA%%:*}"
      CB_RESPONSE="${CALLBACK_DATA#*:}"

      # Find the pending question file for this Q_ID
      PENDING_FILE=$(find_pending "$Q_ID")

      # If response is a numeric index, resolve label from pending question options
      if [[ "$CB_RESPONSE" =~ ^[0-9]+$ ]] && [ -n "$PENDING_FILE" ]; then
        LABEL=$(jq -r --argjson idx "$CB_RESPONSE" '.options[$idx] // empty' "$PENDING_FILE" 2>/dev/null)
        [ -n "$LABEL" ] && CB_RESPONSE="$LABEL"
      fi

      log "Callback: $Q_ID -> $CB_RESPONSE"

      # Write response file to responses/ directory (keyed by Q_ID)
      cat > "$RESPONSES_DIR/${Q_ID}.json" <<CEOF
{"id":"$Q_ID","response":$(echo "$CB_RESPONSE" | jq -Rs .),"source":"telegram","timestamp":"$(date -Iseconds)"}
CEOF

      # Answer callback (removes loading spinner on button)
      curl -s "https://api.telegram.org/bot${TOKEN}/answerCallbackQuery" \
        -d "callback_query_id=$CALLBACK_ID" \
        --data-urlencode "text=Sent: $CB_RESPONSE" > /dev/null 2>&1 || true

      # Edit original message to show answered state
      curl -s -X POST "https://api.telegram.org/bot${TOKEN}/editMessageText" \
        -d "chat_id=$CHAT_ID" \
        -d "message_id=$CALLBACK_MSG_ID" \
        --data-urlencode "text=Answered: $CB_RESPONSE" > /dev/null 2>&1 || true

      continue
    fi

    # === DOCUMENT MESSAGE (brief upload) ===
    DOC_ID=$(echo "$UPDATE" | jq -r '.message.document.file_id // empty' 2>/dev/null)
    FROM_ID=$(echo "$UPDATE" | jq -r '.message.chat.id')

    # Auth check for all message types
    [ "$FROM_ID" != "$CHAT_ID" ] && continue

    if [ -n "$DOC_ID" ]; then
      DOC_NAME=$(echo "$UPDATE" | jq -r '.message.document.file_name // "brief.docx"' 2>/dev/null)
      CAPTION=$(echo "$UPDATE" | jq -r '.message.caption // empty' 2>/dev/null)

      log "Document received: $DOC_NAME"

      # Download file via Telegram API
      FILE_INFO=$(curl -s "https://api.telegram.org/bot${TOKEN}/getFile?file_id=${DOC_ID}" 2>/dev/null)
      FILE_PATH=$(echo "$FILE_INFO" | jq -r '.result.file_path // empty' 2>/dev/null)

      if [ -z "$FILE_PATH" ]; then
        send_msg "Failed to download file. Try again."
        continue
      fi

      BRIEF_PATH="$PROJECT_ROOT/briefs/${DOC_NAME}"
      curl -s "https://api.telegram.org/file/bot${TOKEN}/${FILE_PATH}" \
        -o "$BRIEF_PATH" 2>/dev/null

      if [ ! -f "$BRIEF_PATH" ] || [ ! -s "$BRIEF_PATH" ]; then
        send_msg "Download failed or file is empty."
        continue
      fi

      # Check if pipeline already running
      if is_pipeline_running; then
        send_msg "Pipeline already running. File saved to briefs/${DOC_NAME}. Use /cancel first, then /run with the brief."
        continue
      fi

      # Build task description from caption or filename
      TASK_DESC="${CAPTION:-Implement based on brief: briefs/${DOC_NAME}}"
      send_msg "Brief received: ${DOC_NAME}. Starting pipeline..."

      # Launch pipeline
      bash "$LAUNCH" "$TASK_DESC" &
      log "PIPELINE TRIGGERED (document): $TASK_DESC"
      continue
    fi

    # === REGULAR TEXT MESSAGE ===
    TEXT=$(echo "$UPDATE" | jq -r '.message.text // empty')

    log "Received: $TEXT"

    # Process commands
    case "$TEXT" in
      /status)
        if [ -f "$PROJECT_ROOT/docs/pipeline-state.md" ]; then
          STATE=$(head -30 "$PROJECT_ROOT/docs/pipeline-state.md")
          # Extract current stage if available
          STAGE=$(grep "^stage:" "$PROJECT_ROOT/docs/pipeline-state.md" 2>/dev/null | awk '{print $2}' || echo "unknown")
          WAITING=$(grep "^waiting_for:" "$PROJECT_ROOT/docs/pipeline-state.md" 2>/dev/null | awk '{print $2}' || echo "none")
          LAST_UPDATE=$(grep "^last_update:" "$PROJECT_ROOT/docs/pipeline-state.md" 2>/dev/null | cut -d: -f2- | xargs || echo "unknown")

          if [ "$WAITING" != "none" ] && [ "$WAITING" != "unknown" ]; then
            WAIT_MSG="Waiting for: $WAITING"
          else
            WAIT_MSG=""
          fi

          # Show pending questions count
          PENDING_COUNT=$(ls "$QUEUE_DIR"/q-*.json 2>/dev/null | wc -l)
          PENDING_MSG=""
          [ "$PENDING_COUNT" -gt 0 ] && PENDING_MSG="Pending questions: $PENDING_COUNT"

          # Show channel mode
          CH_MODE="custom"
          [ -f "$MODE_FILE" ] && source "$MODE_FILE" && CH_MODE="${CHANNEL_MODE:-custom}"

          send_msg "Pipeline Status:
Current: $STAGE
Mode: $CH_MODE
$WAIT_MSG
$PENDING_MSG
Updated: $LAST_UPDATE

$STATE"
        else
          # Still show pending questions even without pipeline
          PENDING_COUNT=$(ls "$QUEUE_DIR"/q-*.json 2>/dev/null | wc -l)
          CH_MODE="custom"
          [ -f "$MODE_FILE" ] && source "$MODE_FILE" && CH_MODE="${CHANNEL_MODE:-custom}"

          if [ "$PENDING_COUNT" -gt 0 ]; then
            PENDING_LIST=""
            for f in "$QUEUE_DIR"/q-*.json; do
              [ -f "$f" ] || continue
              LABEL=$(jq -r '.session_label // .project_name // "unknown"' "$f" 2>/dev/null)
              Q=$(jq -r '.question' "$f" 2>/dev/null | head -c 80)
              PENDING_LIST="${PENDING_LIST}
- [${LABEL}] ${Q}"
            done
            send_msg "No active pipeline.
Mode: $CH_MODE
Pending questions ($PENDING_COUNT):$PENDING_LIST"
          else
            send_msg "No active pipeline.
Mode: $CH_MODE
Use /run <task> to start one."
          fi
        fi
        ;;

      /approve)
        echo "APPROVE" > "$COMMAND_FILE"
        send_msg "Approve received. Pipeline will continue."
        log "APPROVE received from Telegram"
        ;;

      /reject)
        echo "REJECT" > "$COMMAND_FILE"
        send_msg "Reject received. Pipeline will stop."
        log "REJECT received from Telegram"
        ;;

      /log)
        HOOK_LOG="$PROJECT_ROOT/.claude/hooks/hook-log.txt"
        if [ -f "$HOOK_LOG" ]; then
          LOGDATA=$(tail -10 "$HOOK_LOG")
          send_msg "Last 10 hook events:
$LOGDATA"
        else
          send_msg "Hook log is empty."
        fi
        ;;

      /retro)
        echo "RETRO" > "$COMMAND_FILE"
        send_msg "Retro command received. Will run in next session."
        log "RETRO received from Telegram"
        ;;

      /run*)
        TASK_DESC="${TEXT#/run }"
        TASK_DESC="${TASK_DESC#/run}"  # Handle /run without space

        if [ -z "$TASK_DESC" ] || [ "$TASK_DESC" = "/run" ]; then
          send_msg "Usage: /run <task description>
Example: /run Fix login page validation bug
Or send a .docx file to start from brief."
          continue
        fi

        # Check if pipeline already running
        if is_pipeline_running; then
          send_msg "Pipeline already running. Use /cancel first, or /status to check progress."
          continue
        fi

        send_msg "Starting pipeline: $TASK_DESC"
        bash "$LAUNCH" "$TASK_DESC" &
        LAUNCH_EXIT=$?

        if [ $LAUNCH_EXIT -eq 0 ]; then
          log "PIPELINE TRIGGERED: $TASK_DESC"
        else
          send_msg "Failed to start pipeline. Check server logs."
          log "PIPELINE LAUNCH FAILED: $TASK_DESC"
        fi
        ;;

      /cancel)
        if tmux has-session -t "claude-pipeline" 2>/dev/null; then
          tmux kill-session -t "claude-pipeline" 2>/dev/null
          rm -f "$MODE_FILE" "$TRIGGER_FILE"
          send_msg "Pipeline session killed."
          log "PIPELINE CANCELLED from Telegram"
        else
          send_msg "No active pipeline session to cancel."
        fi
        ;;

      /queue)
        if [ -f "$TRIGGER_FILE" ]; then
          TASK=$(jq -r '.task // "unknown"' "$TRIGGER_FILE" 2>/dev/null)
          STATUS=$(jq -r '.status // "unknown"' "$TRIGGER_FILE" 2>/dev/null)
          TS=$(jq -r '.timestamp // "unknown"' "$TRIGGER_FILE" 2>/dev/null)
          send_msg "Queued task:
Task: $TASK
Status: $STATUS
Since: $TS"
        else
          send_msg "No queued tasks."
        fi
        ;;

      /start)
        # Ignore /start (Telegram sends this on first bot interaction)
        log "Ignoring /start (Telegram default)"
        ;;

      *)
        if [ -n "$TEXT" ]; then
          # If there are pending questions, route to the most recent one
          LATEST_PENDING=$(find_latest_pending)
          if [ -n "$LATEST_PENDING" ]; then
            Q_ID=$(jq -r '.id' "$LATEST_PENDING" 2>/dev/null)
            SESSION_LABEL=$(jq -r '.session_label // "unknown"' "$LATEST_PENDING" 2>/dev/null)
            cat > "$RESPONSES_DIR/${Q_ID}.json" <<REOF
{"id":"$Q_ID","response":$(echo "$TEXT" | jq -Rs .),"source":"telegram","timestamp":"$(date -Iseconds)"}
REOF
            send_msg "Response for [$SESSION_LABEL]: $TEXT"
            log "Free-text response for $Q_ID ($SESSION_LABEL): $TEXT"
          else
            # No pending questions — suggest /run if no active pipeline
            if is_pipeline_running; then
              echo "MESSAGE: $TEXT" >> "$COMMAND_FILE"
              log "Message forwarded to pipeline: $TEXT"
            else
              send_msg "No active pipeline or pending questions.
Use /run $TEXT to start a pipeline with this task."
            fi
          fi
        fi
        ;;
    esac
  done < <(echo "$RESPONSE" | jq -c '.result[]' 2>/dev/null)
done
