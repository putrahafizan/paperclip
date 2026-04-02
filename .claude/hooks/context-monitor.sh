#!/usr/bin/env bash
# context-monitor.sh — PostToolUse hook for Bash
# Monitors token usage and emits COMPACT_NOW warning when >70% budget.
# Reads token tracking data to estimate context pressure.
# Output to stdout (Claude reads). Always exit 0.

INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Only check periodically (every 10th Bash call) to avoid overhead
COUNTER_FILE="/tmp/context-monitor-counter"
COUNT=$(cat "$COUNTER_FILE" 2>/dev/null || echo "0")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"

# Check every 10 calls
if [ $((COUNT % 10)) -ne 0 ]; then
  exit 0
fi

# Check wave execution state for progress indication
WAVE_STATE="$PROJECT_ROOT/docs/wave-execution-state.md"
if [ ! -f "$WAVE_STATE" ]; then
  exit 0
fi

# Count completed vs total files in wave state
TOTAL_FILES=$(grep -cE '^\s*-\s*\[[ x]\]' "$WAVE_STATE" 2>/dev/null || echo "0")
COMPLETED_FILES=$(grep -cE '^\s*-\s*\[x\]' "$WAVE_STATE" 2>/dev/null || echo "0")

if [ "$TOTAL_FILES" -eq 0 ]; then
  exit 0
fi

# Check token report if available
TOKEN_REPORT="$PROJECT_ROOT/docs/token-reports/current-pipeline.md"
if [ -f "$TOKEN_REPORT" ]; then
  # Try to extract total tokens used
  TOKENS_USED=$(grep -oE 'total.*:.*[0-9]+' "$TOKEN_REPORT" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
  if [ -n "$TOKENS_USED" ] && [ "$TOKENS_USED" -gt 700000 ]; then
    echo "⚠️ CONTEXT MONITOR: Token usage high (~${TOKENS_USED}). COMPACT_NOW — compact context before spawning next agent."
    exit 0
  fi
fi

# Heuristic: if we've processed many files, context is likely pressured
# Wave with 20+ completed files likely needs compaction
if [ "$COMPLETED_FILES" -gt 20 ]; then
  PROGRESS=$((COMPLETED_FILES * 100 / TOTAL_FILES))
  if [ "$PROGRESS" -gt 50 ] && [ "$PROGRESS" -lt 90 ]; then
    echo "⚠️ CONTEXT MONITOR: Progress ${COMPLETED_FILES}/${TOTAL_FILES} files (${PROGRESS}%). Consider COMPACT_NOW between waves."
  fi
fi

exit 0
