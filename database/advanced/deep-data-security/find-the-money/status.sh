#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE="${FIND_MONEY_PID_FILE:-${SCRIPT_DIR}/.find-the-money.pid}"
LOG_DIR="${FIND_MONEY_LOG_DIR:-${SCRIPT_DIR}/logs}"
LOG_FILE="${FIND_MONEY_LOG_FILE:-${LOG_DIR}/find-the-money.log}"

FIND_MONEY_PORT="${FIND_MONEY_PORT:-8013}"
if [ -f .find-the-money.env ]; then
  set +u
  # shellcheck disable=SC1091
  source ./.find-the-money.env
  set -u
fi
if [ -f .env ]; then
  set +u
  # shellcheck disable=SC1091
  source ./.env
  set -u
fi
FIND_MONEY_PORT="${FIND_MONEY_PORT:-8013}"

if [ ! -f "$PID_FILE" ]; then
  echo "Find the Money is not running. No PID file found."
  echo "  Expected PID file = ${PID_FILE}"
  [ -f "$LOG_FILE" ] && echo "  Log = ${LOG_FILE}"
  if command -v ss >/dev/null 2>&1; then
    listener="$(ss -ltnp 2>/dev/null | grep ":${FIND_MONEY_PORT} " || true)"
    if [ -n "$listener" ]; then
      echo
      echo "But port ${FIND_MONEY_PORT} is already in use by another process:"
      echo "$listener"
      echo
      echo "Stop that process, or start Find the Money on another port:"
      echo "  FIND_MONEY_PORT=<other-port> ./start.sh"
    fi
  fi
  exit 1
fi

pid="$(cat "$PID_FILE" 2>/dev/null || true)"
if [ -z "$pid" ]; then
  echo "Find the Money status is unknown. PID file is empty:"
  echo "  ${PID_FILE}"
  exit 1
fi

if kill -0 "$pid" >/dev/null 2>&1; then
  echo "Find the Money is running."
  echo "  PID  = ${pid}"
  echo "  Port = ${FIND_MONEY_PORT}"
  echo "  Log  = ${LOG_FILE}"
else
  echo "Find the Money is not running, but a stale PID file exists."
  echo "  Stale PID file = ${PID_FILE}"
  echo "  Stale PID      = ${pid}"
  exit 1
fi

if command -v ss >/dev/null 2>&1; then
  echo
  echo "Listener:"
  ss -ltnp 2>/dev/null | grep ":${FIND_MONEY_PORT} " || echo "  No listener shown for port ${FIND_MONEY_PORT}."
fi

if [ -f "$LOG_FILE" ]; then
  echo
  echo "Recent startup log:"
  grep -E "TLS enabled|Find the Money running|Redirect URI|Database mode" "$LOG_FILE" | tail -n 8 || true
fi
