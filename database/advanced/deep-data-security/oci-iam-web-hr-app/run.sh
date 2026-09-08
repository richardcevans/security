#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ENV_FILE="${DEEPSEC_MCP_LAB_ENV:-$SCRIPT_DIR/../deep-sec-mcp/.deep-sec-mcp.env}"

if [[ -r "$LAB_ENV_FILE" ]]; then
  set -a
  source "$LAB_ENV_FILE"
  set +a
else
  echo "Missing $LAB_ENV_FILE. Run setup_adbs_oci_iam.sh first or set DEEPSEC_MCP_LAB_ENV." >&2
  exit 1
fi
[[ -r "$SCRIPT_DIR/.env" ]] && { set -a; source "$SCRIPT_DIR/.env"; set +a; }

export WEB_HR_HOST="${WEB_HR_HOST:-0.0.0.0}"
export WEB_HR_PORT="${WEB_HR_PORT:-8012}"
export WEB_HR_REDIRECT_URI="${WEB_HR_REDIRECT_URI:-}"
export WEB_HR_TNS_ALIAS="${WEB_HR_TNS_ALIAS:-$ADB_SERVICE}"

: "${OCI_DOMAIN_URL:?OCI_DOMAIN_URL is missing from the lab environment}"
: "${OCI_CLIENT_ID:?OCI_CLIENT_ID is missing from the lab environment}"
: "${OCI_SCOPE:?OCI_SCOPE is missing from the lab environment}"
: "${TNS_ADMIN:?TNS_ADMIN is missing from the lab environment}"
: "${WALLET_PWD:?WALLET_PWD is missing from the lab environment}"
: "${WEB_HR_REDIRECT_URI:?Set WEB_HR_REDIRECT_URI in .env to the registered OCI IAM callback URI}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
exec "$PYTHON_BIN" "$SCRIPT_DIR/app/main.py"
