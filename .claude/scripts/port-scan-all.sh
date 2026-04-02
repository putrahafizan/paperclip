#!/usr/bin/env bash
set -euo pipefail

# Usage: port-scan-all.sh
# Reads required services from stdin (JSON) or arguments
# Returns: JSON with assigned ports
#
# Input format (stdin):
# {"services": [
#   {"name": "app", "preferred": 8000, "range_start": 8000, "range_end": 8100},
#   {"name": "frontend", "preferred": 3000, "range_start": 3000, "range_end": 3100},
#   {"name": "db_mysql", "preferred": 3306, "range_start": 3306, "range_end": 3400},
#   {"name": "db_pgsql", "preferred": 5432, "range_start": 5432, "range_end": 5500}
# ]}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/port-scanner.sh"

# Read JSON from stdin or first argument
if [ $# -gt 0 ] && [ -f "$1" ]; then
  INPUT=$(cat "$1")
else
  INPUT=$(cat)
fi

# Validate JSON input
if ! echo "$INPUT" | jq -e '.services' >/dev/null 2>&1; then
  echo '{"error":"Invalid JSON input — missing services array"}' >&2
  exit 1
fi

# Process services and assign ports (no collision)
ASSIGNED_PORTS=""
RESULTS="[]"

while IFS= read -r SERVICE; do
  NAME=$(echo "$SERVICE" | jq -r '.name')
  PREFERRED=$(echo "$SERVICE" | jq -r '.preferred')
  RANGE_START=$(echo "$SERVICE" | jq -r '.range_start')
  RANGE_END=$(echo "$SERVICE" | jq -r '.range_end')

  FOUND=""

  # Try preferred first (if not already assigned in this batch)
  if ! echo "$ASSIGNED_PORTS" | grep -qw "$PREFERRED"; then
    if bash "$SCANNER" "$PREFERRED" "$PREFERRED" "$PREFERRED" >/dev/null 2>&1; then
      FOUND="$PREFERRED"
    fi
  fi

  # If preferred not available or already assigned, scan range
  if [ -z "$FOUND" ]; then
    for port in $(seq "$RANGE_START" "$RANGE_END"); do
      # Skip if already assigned in this batch (anti-collision)
      if echo "$ASSIGNED_PORTS" | grep -qw "$port"; then
        continue
      fi
      if bash "$SCANNER" "$port" "$port" "$port" >/dev/null 2>&1; then
        FOUND="$port"
        break
      fi
    done
  fi

  if [ -z "$FOUND" ]; then
    FOUND="ERROR"
    RESULTS=$(echo "$RESULTS" | jq --arg n "$NAME" --argjson p "$PREFERRED" '. += [{"name":$n,"preferred":$p,"assigned":"ERROR","error":"No available port in range"}]')
  else
    ASSIGNED_PORTS="$ASSIGNED_PORTS $FOUND"
    RESULTS=$(echo "$RESULTS" | jq --arg n "$NAME" --argjson p "$PREFERRED" --argjson a "$FOUND" '. += [{"name":$n,"preferred":$p,"assigned":$a}]')
  fi
done < <(echo "$INPUT" | jq -c '.services[]' 2>/dev/null)

# Output final JSON
jq -n --argjson a "$RESULTS" --arg ts "$(date -Iseconds)" '{"assignments":$a,"scan_timestamp":$ts}'
