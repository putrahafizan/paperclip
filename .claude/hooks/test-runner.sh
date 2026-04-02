#!/usr/bin/env bash
# test-runner.sh — PostToolUse hook for Write|Edit
# Runs related tests for changed files. Output on fail, silent on pass.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Skip non-code files
if echo "$FILE_PATH" | grep -qE '\.(md|json|yml|yaml|txt|template|log|csv|xml|sh)$'; then
  exit 0
fi

# Skip test files themselves (avoid loop)
if echo "$FILE_PATH" | grep -qE '(\.test\.|\.spec\.|_test\.|Test\.php|test_.*\.py|__tests__)'; then
  exit 0
fi

EXT="${FILE_PATH##*.}"
MODULE_NAME=$(basename "$FILE_PATH" | sed 's/\.[^.]*$//')

case "$EXT" in
  php)
    if [ -f "phpunit.xml" ] || [ -f "phpunit.xml.dist" ]; then
      RESULT=$(docker compose exec -T php php vendor/bin/phpunit --filter "$MODULE_NAME" 2>&1) || {
        echo "⚠️ TEST FAIL for $FILE_PATH:"
        echo "$RESULT" | tail -20
      }
    fi
    ;;
  js|ts|jsx|tsx)
    if [ -f "jest.config.js" ] || [ -f "jest.config.ts" ] || [ -f "package.json" ]; then
      RESULT=$(npx jest --findRelatedTests "$FILE_PATH" --passWithNoTests 2>&1) || {
        echo "⚠️ TEST FAIL for $FILE_PATH:"
        echo "$RESULT" | tail -20
      }
    fi
    ;;
  py)
    RESULT=$(docker compose exec -T python pytest -k "$MODULE_NAME" --no-header -q 2>&1) || {
      echo "⚠️ TEST FAIL for $FILE_PATH:"
      echo "$RESULT" | tail -20
    }
    ;;
esac

exit 0
