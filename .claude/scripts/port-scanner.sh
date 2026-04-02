#!/usr/bin/env bash
set -euo pipefail

# Usage: port-scanner.sh [preferred_port] [range_start] [range_end]
# Returns: first available port in range
# Exit 0 + prints port number = success
# Exit 1 = no available port in range

PREFERRED="${1:-8000}"
RANGE_START="${2:-$PREFERRED}"
RANGE_END="${3:-$((RANGE_START + 100))}"

# Function: check if port is available
is_port_available() {
  local port=$1

  # Reject privileged/restricted ports (< 1024 requires root)
  if [ "$port" -lt 1024 ] 2>/dev/null; then
    return 1
  fi

  # Method 1: ss (modern Linux)
  if command -v ss &>/dev/null; then
    ! ss -tlnp 2>/dev/null | grep -q ":${port} " && return 0
  fi

  # Method 2: lsof (macOS / fallback)
  if command -v lsof &>/dev/null; then
    ! lsof -iTCP:${port} -sTCP:LISTEN &>/dev/null && return 0
  fi

  # Method 3: netstat (universal fallback)
  if command -v netstat &>/dev/null; then
    ! netstat -tlnp 2>/dev/null | grep -q ":${port} " && return 0
  fi

  # Method 4: try bind (last resort)
  if command -v python3 &>/dev/null; then
    python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
try:
    s.bind(('127.0.0.1', ${port}))
    s.close()
    exit(0)
except:
    exit(1)
" && return 0
  fi

  return 1
}

# Try preferred port first
if is_port_available "$PREFERRED"; then
  echo "$PREFERRED"
  exit 0
fi

# Scan range for first available
for port in $(seq "$RANGE_START" "$RANGE_END"); do
  if is_port_available "$port"; then
    echo "$port"
    exit 0
  fi
done

# No port available
echo "ERROR: No available port found in range ${RANGE_START}-${RANGE_END}" >&2
exit 1
