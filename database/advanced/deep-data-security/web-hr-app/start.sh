#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE="${WEB_HR_PID_FILE:-${SCRIPT_DIR}/.web-hr-app.pid}"
LOG_DIR="${WEB_HR_LOG_DIR:-${SCRIPT_DIR}/logs}"
LOG_FILE="${WEB_HR_LOG_FILE:-${LOG_DIR}/web-hr-app.log}"

if [ -f "$PID_FILE" ]; then
  existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" >/dev/null 2>&1; then
    echo "Web HR App is already running."
    echo "  PID = ${existing_pid}"
    echo "  Log = ${LOG_FILE}"
    exit 0
  fi
  echo "Removing stale PID file: ${PID_FILE}"
  rm -f "$PID_FILE"
fi

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

echo "Starting Web HR App in the background..."
echo "  Log = ${LOG_FILE}"

nohup ./run.sh >>"$LOG_FILE" 2>&1 &
pid="$!"
echo "$pid" > "$PID_FILE"

sleep 1
if kill -0 "$pid" >/dev/null 2>&1; then
  echo "Started."
  echo "  PID = ${pid}"
  echo
  tail -n 8 "$LOG_FILE"
else
  echo "Web HR App did not stay running. Recent log output:"
  tail -n 40 "$LOG_FILE"
  rm -f "$PID_FILE"
  exit 1
fi
