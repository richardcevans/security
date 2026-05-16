#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE="${WEB_HR_PID_FILE:-${SCRIPT_DIR}/.web-hr-app.pid}"
LOG_DIR="${WEB_HR_LOG_DIR:-${SCRIPT_DIR}/logs}"
LOG_FILE="${WEB_HR_LOG_FILE:-${LOG_DIR}/web-hr-app.log}"

if [ ! -f "$PID_FILE" ]; then
  echo "Web HR App is not running. No PID file found."
  exit 0
fi

pid="$(cat "$PID_FILE" 2>/dev/null || true)"
if [ -z "$pid" ]; then
  echo "PID file is empty. Removing it:"
  echo "  ${PID_FILE}"
  rm -f "$PID_FILE"
  exit 0
fi

if ! kill -0 "$pid" >/dev/null 2>&1; then
  echo "Web HR App process is not running. Removing stale PID file."
  echo "  PID = ${pid}"
  rm -f "$PID_FILE"
  exit 0
fi

echo "Stopping Web HR App..."
echo "  PID = ${pid}"
kill "$pid"

for _ in 1 2 3 4 5; do
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    rm -f "$PID_FILE"
    echo "Stopped."
    [ -f "$LOG_FILE" ] && echo "  Log = ${LOG_FILE}"
    exit 0
  fi
  sleep 1
done

echo "Process did not stop after SIGTERM; sending SIGKILL."
kill -9 "$pid" >/dev/null 2>&1 || true
rm -f "$PID_FILE"
echo "Stopped."
[ -f "$LOG_FILE" ] && echo "  Log = ${LOG_FILE}"
