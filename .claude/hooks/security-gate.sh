#!/usr/bin/env bash
# security-gate.sh — PreToolUse hook for Bash commands
# Blocks dangerous operations. Exit 2 + stderr = Claude reads and adjusts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

if [ -z "$COMMAND" ]; then
  exit 0
fi

LOG_FILE="$SCRIPT_DIR/hook-log.txt"

log_block() {
  local reason="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] BLOCKED: $reason | cmd: $COMMAND" >> "$LOG_FILE"
  if [ -x ".claude/hooks/notify.sh" ]; then
    echo '{"message":"SECURITY BLOCK: '"$reason"'"}' | .claude/hooks/notify.sh 2>/dev/null || true
  fi
}

# Block: git push to protected branches (main, master, develop, staging)
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*\b(main|master|develop|staging)\b'; then
  log_block "git push to protected branch detected"
  echo "BLOCKED: git push to protected branch detected. Use feature branches and PR instead." >&2
  bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate" 2>/dev/null &
  exit 2
fi

# Block: git push --force
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force'; then
  log_block "git push --force is forbidden"
  echo "BLOCKED: git push --force is forbidden. Use non-destructive push." >&2
  bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate" 2>/dev/null &
  exit 2
fi
if echo "$COMMAND" | grep -qE 'git\s+push\s+-f\b'; then
  log_block "git push -f (force) is forbidden"
  echo "BLOCKED: git push -f (force) is forbidden." >&2
  bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate" 2>/dev/null &
  exit 2
fi

# Block: DROP DATABASE, TRUNCATE, DELETE FROM WHERE 1
if echo "$COMMAND" | grep -qiE 'DROP\s+(DATABASE|TABLE)'; then
  log_block "DROP DATABASE/TABLE detected"
  echo "BLOCKED: DROP DATABASE/TABLE is forbidden." >&2
  bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate" 2>/dev/null &
  exit 2
fi
if echo "$COMMAND" | grep -qiE 'TRUNCATE\s+'; then
  log_block "TRUNCATE detected"
  echo "BLOCKED: TRUNCATE is forbidden." >&2
  bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate" 2>/dev/null &
  exit 2
fi
if echo "$COMMAND" | grep -qiE "DELETE\s+FROM\s+.*WHERE\s+1"; then
  log_block "DELETE FROM WHERE 1 (mass delete) detected"
  echo "BLOCKED: Mass DELETE detected." >&2
  bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate" 2>/dev/null &
  exit 2
fi

# Block: rm -rf at root or important directories
if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+(/|/home|/var|/etc|/usr|\.\.)'; then
  log_block "rm -rf on critical directory detected"
  echo "BLOCKED: rm -rf on critical directory." >&2
  bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate" 2>/dev/null &
  exit 2
fi

# Block: curl/wget to non-allowed URLs
if echo "$COMMAND" | grep -qE '(curl|wget)\s' ; then
  if ! echo "$COMMAND" | grep -qE '(localhost|127\.0\.0\.1|github\.com|gitlab\.com|api\.telegram\.org)'; then
    log_block "curl/wget to external URL not in allowlist"
    echo "BLOCKED: curl/wget to external URL not in allowlist." >&2
    bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate" 2>/dev/null &
    exit 2
  fi
fi

# === DOCKER ENFORCEMENT ===
# Block bare host commands if Docker assessment shows service should be dockerized
DOCKER_ASSESS="$PROJECT_ROOT/docs/docker-assessment.md"
BARE_COMMANDS="^(npm |npx |pip |pip3 |composer |php |python |python3 |pytest |phpunit |jest |node )"

if [ -n "$COMMAND" ] && echo "$COMMAND" | grep -qE "$BARE_COMMANDS"; then
  # Check: is this a docker exec command? If yes, ALLOW
  if ! echo "$COMMAND" | grep -q "docker exec"; then
    # Check: is this service in host_services?
    if [ -f "$DOCKER_ASSESS" ]; then
      CMD_NAME=$(echo "$COMMAND" | awk '{print $1}')
      HOST_SECTION=$(sed -n '/Host Services/,/Execution Rules/p' "$DOCKER_ASSESS" 2>/dev/null)
      if echo "$HOST_SECTION" | grep -qi "$CMD_NAME"; then
        echo "[$(date '+%H:%M:%S')] HOST-ALLOW: $CMD_NAME (in host_services)" >> "$LOG_FILE"
        exit 0
      fi
    fi
    # Service NOT in host_services — BLOCK
    CMD_NAME=$(echo "$COMMAND" | awk '{print $1}')
    echo "BLOCKED: '$CMD_NAME' harus dijalankan di Docker container. Gunakan: docker exec -it [container] $COMMAND" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] BLOCKED: bare $CMD_NAME (must use docker exec)" >> "$LOG_FILE"
    bash "$PROJECT_ROOT/.claude/telegram/notify-blocked.sh" "$COMMAND" "security-gate:docker-enforce" 2>/dev/null &
    exit 2
  fi
fi

exit 0
