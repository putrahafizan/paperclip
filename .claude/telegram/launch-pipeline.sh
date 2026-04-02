#!/usr/bin/env bash
# launch-pipeline.sh — Start a Claude Code pipeline session from Telegram
# Usage: bash launch-pipeline.sh <task description>
# Called by bot-daemon.sh when user sends /run <task> from Telegram
#
# Creates a tmux session with Claude Code + native channels enabled,
# then passes the task to /start for pipeline execution.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE_FILE="$SCRIPT_DIR/channel-mode.env"
TRIGGER_FILE="$SCRIPT_DIR/trigger-task.json"
SESSION_NAME="claude-pipeline"
TASK="$*"

if [ -z "$TASK" ]; then
  echo "ERROR: No task description provided" >&2
  exit 1
fi

# Check if a pipeline session is already running
if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
  # Session exists — check if Claude is still active
  if [ -f "$MODE_FILE" ]; then
    source "$MODE_FILE"
    if kill -0 "${SESSION_PID:-0}" 2>/dev/null; then
      echo "BUSY: Pipeline session already running (PID $SESSION_PID)"
      echo "Use /cancel to stop it first, or /status to check progress."
      exit 1
    fi
  fi
  # Stale session — kill it
  tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
fi

# Write trigger task file (for /queue command visibility)
cat > "$TRIGGER_FILE" <<EOF
{
  "task": $(echo "$TASK" | jq -Rs .),
  "source": "telegram",
  "timestamp": "$(date -Iseconds)",
  "status": "launching"
}
EOF

# Write channel mode indicator
cat > "$MODE_FILE" <<EOF
CHANNEL_MODE=native
SESSION_PID=$$
SESSION_STARTED=$(date -Iseconds)
TASK=$(echo "$TASK" | tr '"' "'" | head -c 200)
EOF

# Build the Claude command with channels and the /start task
# Use -p flag for non-interactive prompt mode
CLAUDE_CMD="cd $PROJECT_ROOT && claude --channels plugin:telegram@claude-plugins-official -p '/start $TASK'"

# Cleanup command appended — removes mode file when Claude exits
FULL_CMD="$CLAUDE_CMD; rm -f '$MODE_FILE' '$TRIGGER_FILE'"

# Launch in new tmux session (detached)
tmux new-session -d -s "$SESSION_NAME" "$FULL_CMD"

echo "Pipeline session started in tmux '$SESSION_NAME'"
echo "Task: $TASK"
