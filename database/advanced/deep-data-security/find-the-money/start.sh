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

show_listener() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep ":${FIND_MONEY_PORT} " || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${FIND_MONEY_PORT}" -sTCP:LISTEN 2>/dev/null || true
  fi
}

if [ -f "$PID_FILE" ]; then
  existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$existing_pid" ] && kill -0 "$existing_pid" >/dev/null 2>&1; then
    echo "Find the Money is already running."
    echo "  PID = ${existing_pid}"
    echo "  Log = ${LOG_FILE}"
    exit 0
  fi
  echo "Removing stale PID file: ${PID_FILE}"
  rm -f "$PID_FILE"
fi

listener="$(show_listener)"
if [ -n "$listener" ]; then
  echo "Port ${FIND_MONEY_PORT} is already in use."
  echo
  echo "Listener:"
  echo "$listener"
  echo
  echo "If this is the Find the Money, use:"
  echo "  ./status.sh"
  echo "  ./stop.sh"
  echo
  echo "If it was started outside these scripts, stop that process or choose another port:"
  echo "  FIND_MONEY_PORT=<other-port> ./start.sh"
  exit 1
fi

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

echo "Starting Find the Money in the background..."
echo "  Log = ${LOG_FILE}"

{
  echo
  echo "========================================================================"
  echo "Starting Find the Money: $(date -Is)"
  echo "========================================================================"
} >>"$LOG_FILE"

start_line="$(wc -l < "$LOG_FILE" | tr -d '[:space:]')"
nohup ./run.sh "$@" >>"$LOG_FILE" 2>&1 &
pid="$!"
echo "$pid" > "$PID_FILE"

sleep 1
if kill -0 "$pid" >/dev/null 2>&1; then
  echo "Started."
  echo "  PID = ${pid}"
  echo
  tail -n +"$start_line" "$LOG_FILE"
else
  echo "Find the Money did not stay running. Recent log output:"
  tail -n +"$start_line" "$LOG_FILE"
  rm -f "$PID_FILE"
  exit 1
fi
