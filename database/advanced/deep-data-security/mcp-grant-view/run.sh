#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENTRA_LAB_ENV="${ENTRA_LAB_ENV:-${SCRIPT_DIR}/../entra-id-data-grants/.entra-id-data-grants.env}"
if [ -f "$ENTRA_LAB_ENV" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENTRA_LAB_ENV"
  set +a
fi

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

export GRANT_VIEW_HOST="${GRANT_VIEW_HOST:-127.0.0.1}"
export GRANT_VIEW_PORT="${GRANT_VIEW_PORT:-8008}"

PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    PYTHON_BIN="python"
  fi
fi

"$PYTHON_BIN" -m app.main
