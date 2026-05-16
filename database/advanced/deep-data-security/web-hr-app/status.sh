#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE="${WEB_HR_PID_FILE:-${SCRIPT_DIR}/.web-hr-app.pid}"
LOG_DIR="${WEB_HR_LOG_DIR:-${SCRIPT_DIR}/logs}"
LOG_FILE="${WEB_HR_LOG_FILE:-${LOG_DIR}/web-hr-app.log}"

WEB_HR_PORT="${WEB_HR_PORT:-8012}"
if [ -f .web-hr-app.env ]; then
  set +u
  # shellcheck disable=SC1091
  source ./.web-hr-app.env
  set -u
fi
if [ -f .env ]; then
  set +u
  # shellcheck disable=SC1091
  source ./.env
  set -u
fi
WEB_HR_PORT="${WEB_HR_PORT:-8012}"

if [ ! -f "$PID_FILE" ]; then
  echo "Web HR App is not running. No PID file found."
  echo "  Expected PID file = ${PID_FILE}"
  [ -f "$LOG_FILE" ] && echo "  Log = ${LOG_FILE}"
  if command -v ss >/dev/null 2>&1; then
    listener="$(ss -ltnp 2>/dev/null | grep ":${WEB_HR_PORT} " || true)"
    if [ -n "$listener" ]; then
      echo
      echo "But port ${WEB_HR_PORT} is already in use by another process:"
      echo "$listener"
      echo
      echo "Stop that process, or start Web HR App on another port:"
      echo "  WEB_HR_PORT=<other-port> ./start.sh"
    fi
  fi
  exit 1
fi

pid="$(cat "$PID_FILE" 2>/dev/null || true)"
if [ -z "$pid" ]; then
  echo "Web HR App status is unknown. PID file is empty:"
  echo "  ${PID_FILE}"
  exit 1
fi

if kill -0 "$pid" >/dev/null 2>&1; then
  echo "Web HR App is running."
  echo "  PID  = ${pid}"
  echo "  Port = ${WEB_HR_PORT}"
  echo "  Log  = ${LOG_FILE}"
else
  echo "Web HR App is not running, but a stale PID file exists."
  echo "  Stale PID file = ${PID_FILE}"
  echo "  Stale PID      = ${pid}"
  exit 1
fi

if command -v ss >/dev/null 2>&1; then
  echo
  echo "Listener:"
  ss -ltnp 2>/dev/null | grep ":${WEB_HR_PORT} " || echo "  No listener shown for port ${WEB_HR_PORT}."
fi

if [ -f "$LOG_FILE" ]; then
  echo
  echo "Recent startup log:"
  grep -E "TLS enabled|Web HR App running|Redirect URI|Database mode" "$LOG_FILE" | tail -n 8 || true
fi
