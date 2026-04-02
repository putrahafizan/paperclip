#!/usr/bin/env bash
set -euo pipefail

# Context Monitor — estimasi context usage berdasarkan conversation size
# Output: JSON { estimated_usage_pct, recommendation, files_created, files_remaining }

PROJECT_DIR="${1:-.}"
STATE_FILE="$PROJECT_DIR/docs/pipeline-state.md"
WAVE_PLAN="$PROJECT_DIR/docs/wave-plan.md"
SCOPE_FILE="$PROJECT_DIR/docs/file-scope-contract.md"

# Count files created so far
FILES_CREATED=0
if [ -d "$PROJECT_DIR/src" ] || [ -d "$PROJECT_DIR/app" ]; then
  FILES_CREATED=$(find "$PROJECT_DIR/src" "$PROJECT_DIR/app" "$PROJECT_DIR/tests" \
    -name "*.py" -o -name "*.php" -o -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \
    2>/dev/null | wc -l)
fi

# Estimate total files expected (from wave-plan or pipeline-state)
FILES_TOTAL=0
if [ -f "$WAVE_PLAN" ]; then
  FILES_TOTAL=$(grep -oP '~?\d+(?= files)' "$WAVE_PLAN" 2>/dev/null | head -1 | tr -d '~')
fi
[ -z "$FILES_TOTAL" ] || [ "$FILES_TOTAL" = "0" ] && FILES_TOTAL=50

FILES_REMAINING=$((FILES_TOTAL - FILES_CREATED))
[ "$FILES_REMAINING" -lt 0 ] && FILES_REMAINING=0

# Estimate progress percentage
if [ "$FILES_TOTAL" -gt 0 ]; then
  PROGRESS_PCT=$((FILES_CREATED * 100 / FILES_TOTAL))
else
  PROGRESS_PCT=0
fi

# Determine current wave from pipeline-state
CURRENT_WAVE="unknown"
if [ -f "$STATE_FILE" ]; then
  CURRENT_WAVE=$(grep -oP 'Wave \d+' "$STATE_FILE" 2>/dev/null | tail -1 || echo "unknown")
fi

# Recommendation based on progress vs typical context patterns
RECOMMENDATION="continue"
if [ "$PROGRESS_PCT" -lt 10 ] && [ "$FILES_TOTAL" -gt 30 ]; then
  RECOMMENDATION="compact-before-execution"
elif [ "$PROGRESS_PCT" -gt 50 ] && [ "$FILES_REMAINING" -gt 20 ]; then
  RECOMMENDATION="compact-now"
elif [ "$PROGRESS_PCT" -gt 80 ]; then
  RECOMMENDATION="finishing"
fi

cat << EOF
{
  "files_created": $FILES_CREATED,
  "files_total": $FILES_TOTAL,
  "files_remaining": $FILES_REMAINING,
  "progress_pct": $PROGRESS_PCT,
  "current_wave": "$CURRENT_WAVE",
  "recommendation": "$RECOMMENDATION",
  "timestamp": "$(date -Iseconds)"
}
EOF
