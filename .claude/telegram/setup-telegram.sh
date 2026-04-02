#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Telegram Bot Setup Wizard"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Load existing .env if available
source "$PROJECT_ROOT/.env" 2>/dev/null || true

# Step 1: Get bot token
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  echo "TELEGRAM_BOT_TOKEN found in .env"
  TOKEN="$TELEGRAM_BOT_TOKEN"
else
  echo ""
  echo "Create bot via @BotFather -> /newbot -> copy token"
  read -p "Paste TELEGRAM_BOT_TOKEN: " TOKEN
fi

# Step 2: Validate token
echo ""
echo "Validating token..."
RESULT=$(curl -s "https://api.telegram.org/bot${TOKEN}/getMe" 2>/dev/null)
BOT_OK=$(echo "$RESULT" | jq -r '.ok' 2>/dev/null)

if [ "$BOT_OK" != "true" ]; then
  echo "Token invalid. Check token and try again."
  exit 1
fi

BOT_NAME=$(echo "$RESULT" | jq -r '.result.username')
echo "Bot validated: @${BOT_NAME}"

# Step 3: Get chat ID
if [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
  echo "TELEGRAM_CHAT_ID found in .env: $TELEGRAM_CHAT_ID"
  CHAT_ID="$TELEGRAM_CHAT_ID"
else
  echo ""
  echo "Auto-detecting chat ID..."
  echo "Send any message to @${BOT_NAME} on Telegram, then press Enter here."
  read -p "Press Enter after sending message to bot..."

  UPDATES=$(curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates?limit=1" 2>/dev/null)
  CHAT_ID=$(echo "$UPDATES" | jq -r '.result[0].message.chat.id // empty' 2>/dev/null)

  if [ -z "$CHAT_ID" ]; then
    echo "Cannot auto-detect chat ID."
    read -p "Enter TELEGRAM_CHAT_ID manually (chat @userinfobot): " CHAT_ID
  else
    echo "Chat ID detected: $CHAT_ID"
  fi
fi

# Step 4: Write to .env
if ! grep -q "TELEGRAM_BOT_TOKEN" "$PROJECT_ROOT/.env" 2>/dev/null; then
  echo "" >> "$PROJECT_ROOT/.env"
  echo "# Telegram Bot" >> "$PROJECT_ROOT/.env"
  echo "TELEGRAM_BOT_TOKEN=$TOKEN" >> "$PROJECT_ROOT/.env"
  echo "TELEGRAM_CHAT_ID=$CHAT_ID" >> "$PROJECT_ROOT/.env"
  echo "Written to .env"
else
  echo ".env already has Telegram config -- skipping write"
fi

# Step 5: Register bot commands (including new /run, /cancel, /queue)
echo ""
echo "Registering bot commands..."
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/setMyCommands" \
  -H "Content-Type: application/json" \
  -d '{
    "commands": [
      {"command": "status", "description": "Show current pipeline status and channel mode"},
      {"command": "approve", "description": "Approve pending pipeline"},
      {"command": "reject", "description": "Reject and stop pipeline"},
      {"command": "run", "description": "Start a new pipeline: /run <task description>"},
      {"command": "cancel", "description": "Cancel running pipeline session"},
      {"command": "queue", "description": "Show queued/pending tasks"},
      {"command": "log", "description": "Show last 10 hook log entries"},
      {"command": "retro", "description": "Trigger retrospective analysis"}
    ]
  }' > /dev/null 2>&1

echo "Bot commands registered: /status, /approve, /reject, /run, /cancel, /queue, /log, /retro"

# Step 6: Send test message
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  --data-urlencode "text=Telegram bot ready. Commands: /status /run /approve /reject /cancel /queue /log /retro" \
  > /dev/null 2>&1

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Setup complete!"
echo ""
echo "Start modes:"
echo "  Custom:  bash $SCRIPT_DIR/manage.sh start"
echo "  Channel: bash $SCRIPT_DIR/manage.sh start-channels"
echo "  Auto:    bash $SCRIPT_DIR/claude-agent.sh [--channels plugin:telegram@claude-plugins-official]"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
