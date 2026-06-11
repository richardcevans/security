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

show_listener() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep ":${WEB_HR_PORT} " || true
  elif command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${WEB_HR_PORT}" -sTCP:LISTEN 2>/dev/null || true
  fi
}

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

listener="$(show_listener)"
if [ -n "$listener" ]; then
  echo "Port ${WEB_HR_PORT} is already in use."
  echo
  echo "Listener:"
  echo "$listener"
  echo
  echo "If this is the Web HR App, use:"
  echo "  ./status.sh"
  echo "  ./stop.sh"
  echo
  echo "If it was started outside these scripts, stop that process or choose another port:"
  echo "  WEB_HR_PORT=<other-port> ./start.sh"
  exit 1
fi

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

echo "Starting Web HR App in the background..."
echo "  Log = ${LOG_FILE}"

start_line="$(wc -l < "$LOG_FILE" | tr -d '[:space:]')"
start_line="$((start_line + 1))"

{
  echo
  echo "========================================================================"
  echo "Starting Web HR App: $(date -Is)"
  printf 'Command: ./run.sh'
  if [ "$#" -gt 0 ]; then
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
  fi
  printf '\n'
  echo "========================================================================"
} >>"$LOG_FILE"

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
  echo "Web HR App did not stay running. Recent log output:"
  tail -n +"$start_line" "$LOG_FILE"
  rm -f "$PID_FILE"
  exit 1
fi
