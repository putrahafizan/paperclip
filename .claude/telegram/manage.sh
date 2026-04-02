#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
set -euo pipefail

PID_FILE="$SCRIPT_DIR/daemon.pid"
INJECTOR_PID_FILE="$SCRIPT_DIR/injector.pid"
DAEMON="$SCRIPT_DIR/bot-daemon.sh"
INJECTOR="$SCRIPT_DIR/response-injector.sh"
MODE_FILE="$SCRIPT_DIR/channel-mode.env"

is_running() {
  local pidfile="$1"
  [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null
}

start_daemon() {
  if is_running "$PID_FILE"; then
    echo "Bot daemon already running (PID $(cat $PID_FILE))"
  else
    nohup bash "$DAEMON" > "$SCRIPT_DIR/daemon.log" 2>&1 &
    echo $! > "$PID_FILE"
    echo "Bot daemon started (PID $!)"
  fi
}

start_injector() {
  if is_running "$INJECTOR_PID_FILE"; then
    echo "Response injector already running (PID $(cat $INJECTOR_PID_FILE))"
  else
    nohup bash "$INJECTOR" > "$SCRIPT_DIR/injector.log" 2>&1 &
    echo $! > "$INJECTOR_PID_FILE"
    echo "Response injector started (PID $!)"
  fi
}

case "${1:-}" in
  start)
    # Custom mode: start both daemon and injector
    start_daemon
    start_injector
    ;;

  start-channels)
    # Native channel mode: daemon only (no injector — channel handles responses)
    start_daemon
    echo "Response injector: SKIPPED (native channel mode)"
    ;;

  stop)
    # Stop bot daemon
    if [ -f "$PID_FILE" ]; then
      kill "$(cat $PID_FILE)" 2>/dev/null && echo "Bot daemon stopped" || echo "Daemon not running"
      rm -f "$PID_FILE"
    else
      echo "No daemon PID file found"
    fi

    # Stop response injector
    if [ -f "$INJECTOR_PID_FILE" ]; then
      kill "$(cat $INJECTOR_PID_FILE)" 2>/dev/null && echo "Response injector stopped" || echo "Injector not running"
      rm -f "$INJECTOR_PID_FILE"
    else
      echo "No injector PID file found"
    fi

    # Cleanup channel mode file
    rm -f "$MODE_FILE"
    ;;

  status)
    echo "=== Telegram Bot Status ==="
    if is_running "$PID_FILE"; then
      echo "Bot daemon:        RUNNING (PID $(cat $PID_FILE))"
    else
      echo "Bot daemon:        STOPPED"
    fi

    if is_running "$INJECTOR_PID_FILE"; then
      echo "Response injector: RUNNING (PID $(cat $INJECTOR_PID_FILE))"
    else
      echo "Response injector: STOPPED"
    fi

    # Channel mode detection
    if [ -f "$MODE_FILE" ]; then
      source "$MODE_FILE"
      if kill -0 "${SESSION_PID:-0}" 2>/dev/null; then
        echo "Channel mode:      ${CHANNEL_MODE:-unknown} (PID $SESSION_PID since ${SESSION_STARTED:-unknown})"
      else
        echo "Channel mode:      STALE (session ended)"
        rm -f "$MODE_FILE"
      fi
    else
      echo "Channel mode:      custom (default)"
    fi

    # Tmux detection
    if [ -n "${TMUX:-}" ]; then
      TMUX_INFO=$(tmux display-message -p '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || echo "unknown")
      echo "Tmux session:      $TMUX_INFO"
    else
      echo "Tmux session:      NOT DETECTED (Telegram->terminal injection requires tmux)"
    fi

    # Pending questions (queue directory)
    QUEUE_DIR="$SCRIPT_DIR/pending-questions"
    PENDING_COUNT=$(ls "$QUEUE_DIR"/q-*.json 2>/dev/null | wc -l)
    if [ "$PENDING_COUNT" -gt 0 ]; then
      echo "Pending questions:  $PENDING_COUNT"
      for f in "$QUEUE_DIR"/q-*.json; do
        [ -f "$f" ] || continue
        LABEL=$(jq -r '.session_label // "unknown"' "$f" 2>/dev/null)
        Q=$(jq -r '.question // "unknown"' "$f" 2>/dev/null)
        echo "  * [$LABEL] ${Q:0:50}..."
      done
    else
      echo "Pending questions:  none"
    fi
    ;;

  restart)
    $0 stop
    sleep 1
    $0 start
    ;;

  *)
    echo "Usage: $0 {start|start-channels|stop|status|restart}"
    exit 1
    ;;
esac
