#!/usr/bin/env bash
# response-injector.sh — Watches for Telegram responses and injects into terminal via tmux
# Supports multi-session: watches responses/ directory, matches against pending-questions/
# Runs as background daemon alongside bot-daemon.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
QUEUE_DIR="$SCRIPT_DIR/pending-questions"
RESPONSES_DIR="$SCRIPT_DIR/responses"
PID_FILE="$SCRIPT_DIR/injector.pid"
NOTIFY="$PROJECT_ROOT/.claude/hooks/notify.sh"

POLL_INTERVAL=1    # seconds between checks
TIMEOUT=600        # 10 minutes max wait

# Ensure directories exist
mkdir -p "$QUEUE_DIR" "$RESPONSES_DIR"

# Write PID for clean shutdown
echo $$ > "$PID_FILE"
trap "rm -f '$PID_FILE'; exit 0" SIGTERM SIGINT

log() { echo "[$(date '+%H:%M:%S')] INJECTOR: $*"; }

log "Response injector started. Watching responses/ directory..."

while true; do
  # Process all response files in the responses/ directory
  for RESPONSE_FILE in "$RESPONSES_DIR"/q-*.json; do
    [ -f "$RESPONSE_FILE" ] || continue

    # Read response data
    RESP_Q_ID=$(jq -r '.id // empty' "$RESPONSE_FILE" 2>/dev/null)
    RESPONSE=$(jq -r '.response // empty' "$RESPONSE_FILE" 2>/dev/null)
    SOURCE=$(jq -r '.source // "unknown"' "$RESPONSE_FILE" 2>/dev/null)

    if [ -z "$RESPONSE" ]; then
      log "Empty response in $(basename "$RESPONSE_FILE"), cleaning up"
      rm -f "$RESPONSE_FILE"
      continue
    fi

    # Find matching pending question
    PENDING_FILE="$QUEUE_DIR/${RESP_Q_ID}.json"
    if [ ! -f "$PENDING_FILE" ]; then
      # Fallback: search by ID field
      PENDING_FILE=""
      for pf in "$QUEUE_DIR"/q-*.json; do
        [ -f "$pf" ] || continue
        PF_ID=$(jq -r '.id // empty' "$pf" 2>/dev/null)
        if [ "$PF_ID" = "$RESP_Q_ID" ]; then
          PENDING_FILE="$pf"
          break
        fi
      done
    fi

    if [ -z "$PENDING_FILE" ] || [ ! -f "$PENDING_FILE" ]; then
      log "No pending question for response $RESP_Q_ID. Discarding."
      rm -f "$RESPONSE_FILE"
      continue
    fi

    TMUX_TARGET=$(jq -r '.tmux_target // empty' "$PENDING_FILE" 2>/dev/null)
    SESSION_LABEL=$(jq -r '.session_label // "unknown"' "$PENDING_FILE" 2>/dev/null)

    # Inject response into terminal
    INJECTED=false

    if [ -n "$TMUX_TARGET" ]; then
      # Try tmux send-keys
      if tmux send-keys -t "$TMUX_TARGET" -- "$RESPONSE" Enter 2>/dev/null; then
        log "Injected '$RESPONSE' via tmux to $TMUX_TARGET ($SESSION_LABEL)"
        INJECTED=true
      else
        log "tmux send-keys failed for target $TMUX_TARGET ($SESSION_LABEL)"
      fi
    fi

    if [ "$INJECTED" = false ]; then
      # Fallback: write to incoming-command.txt for orchestrator polling
      echo "MESSAGE: $RESPONSE" >> "$SCRIPT_DIR/incoming-command.txt"
      log "Wrote response to incoming-command.txt (tmux fallback for $SESSION_LABEL)"
    fi

    # Send confirmation to Telegram
    if [ "$INJECTED" = true ]; then
      bash "$NOTIFY" "✅ [$SESSION_LABEL] Response \"$RESPONSE\" injected into terminal." 2>/dev/null &
    fi

    # Clean up both files
    rm -f "$RESPONSE_FILE" "$PENDING_FILE"
    log "Cleanup done for $RESP_Q_ID ($SESSION_LABEL)"
  done

  # Check for timeout on all pending questions individually
  NOW_EPOCH=$(date +%s)
  for PENDING_FILE in "$QUEUE_DIR"/q-*.json; do
    [ -f "$PENDING_FILE" ] || continue

    PENDING_TS=$(jq -r '.timestamp // empty' "$PENDING_FILE" 2>/dev/null)
    if [ -n "$PENDING_TS" ]; then
      PENDING_EPOCH=$(date -d "$PENDING_TS" +%s 2>/dev/null || echo "0")
      ELAPSED=$((NOW_EPOCH - PENDING_EPOCH))

      if [ "$ELAPSED" -gt "$TIMEOUT" ]; then
        Q_ID=$(jq -r '.id' "$PENDING_FILE" 2>/dev/null)
        SESSION_LABEL=$(jq -r '.session_label // "unknown"' "$PENDING_FILE" 2>/dev/null)
        log "Question $Q_ID ($SESSION_LABEL) timed out after ${ELAPSED}s"
        bash "$NOTIFY" "⏰ [$SESSION_LABEL] Question timed out (${TIMEOUT}s). Please respond in terminal." 2>/dev/null &
        rm -f "$PENDING_FILE"
      fi
    fi
  done

  sleep "$POLL_INTERVAL"
done
