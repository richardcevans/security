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

WEB_HR_ENV_LOADED=0
if [ -f .web-hr-app.env ]; then
  WEB_HR_ENV_LOADED=1
  set -a
  # shellcheck disable=SC1091
  source ./.web-hr-app.env
  set +a
fi

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
fi

if [ -z "${WEB_HR_DB_MODE:-}" ]; then
  if [ "$WEB_HR_ENV_LOADED" -eq 1 ]; then
    export WEB_HR_DB_MODE="oracledb"
  else
    export WEB_HR_DB_MODE="mock"
  fi
fi

PYTHON_BIN="${PYTHON_BIN:-}"
if [ -z "$PYTHON_BIN" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    PYTHON_BIN="python"
  fi
fi

"$PYTHON_BIN" -m app.main
