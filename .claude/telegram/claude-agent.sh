#!/usr/bin/env bash
# claude-agent.sh — Auto-tmux wrapper for Claude Code with Telegram integration
# Usage: bash .claude/telegram/claude-agent.sh [claude args...]
#
# Automatically:
#   1. Creates/attaches tmux session "claude-agent"
#   2. Detects --channels flag for native channel mode
#   3. Starts bot-daemon (+ response-injector in custom mode only)
#   4. Runs Claude Code
#   5. Cleans up on exit

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_NAME="claude-agent"
MODE_FILE="$SCRIPT_DIR/channel-mode.env"

# Detect if --channels flag is present in arguments
CHANNEL_MODE="custom"
for arg in "$@"; do
  if [[ "$arg" == "--channels" ]] || [[ "$arg" == plugin:telegram* ]]; then
    CHANNEL_MODE="native"
    break
  fi
done

# If NOT inside tmux → create session and re-exec inside it
if [ -z "${TMUX:-}" ]; then
  # Check if session already exists
  if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    echo "Attaching to existing tmux session '$SESSION_NAME'..."
    exec tmux attach-session -t "$SESSION_NAME"
  else
    echo "Creating tmux session '$SESSION_NAME'..."
    exec tmux new-session -s "$SESSION_NAME" "bash $0 $*"
  fi
fi

# === Running inside tmux from here ===

# Write channel mode indicator
cat > "$MODE_FILE" <<EOF
CHANNEL_MODE=$CHANNEL_MODE
SESSION_PID=$$
SESSION_STARTED=$(date -Iseconds)
EOF

# Start daemons based on mode
if [ "$CHANNEL_MODE" = "native" ]; then
  echo "Starting Telegram bot daemon (channel mode: native)..."
  bash "$SCRIPT_DIR/manage.sh" start-channels
else
  echo "Starting Telegram bot + response injector (channel mode: custom)..."
  bash "$SCRIPT_DIR/manage.sh" start
fi

# Cleanup on exit
cleanup() {
  echo ""
  echo "Stopping Telegram daemons..."
  bash "$SCRIPT_DIR/manage.sh" stop
  rm -f "$MODE_FILE"
}
trap cleanup EXIT

# Run Claude Code with any passed arguments
echo "Launching Claude Code..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Telegram mode:  $CHANNEL_MODE"
if [ "$CHANNEL_MODE" = "native" ]; then
  echo "Channel:        native (bidirectional via plugin)"
  echo "Injector:       SKIPPED (channel handles responses)"
else
  echo "Channel:        custom (file-queue + tmux injection)"
  echo "Injector:       ACTIVE"
fi
echo "Tmux session:   $SESSION_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

claude "$@"
