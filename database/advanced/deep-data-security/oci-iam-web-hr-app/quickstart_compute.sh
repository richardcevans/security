#!/usr/bin/env bash
# Prepare and start OCI IAM Web HR App on the Compute VM.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${VENV_DIR:-/home/opc/deepsec-venv}"
if [[ -r "$SCRIPT_DIR/../.deep-sec-mcp.env" ]]; then
  DEFAULT_LAB_ENV_FILE="$SCRIPT_DIR/../.deep-sec-mcp.env"
else
  DEFAULT_LAB_ENV_FILE="$SCRIPT_DIR/../deep-sec-mcp/.deep-sec-mcp.env"
fi
LAB_ENV_FILE="${DEEPSEC_MCP_LAB_ENV:-$DEFAULT_LAB_ENV_FILE}"

if [[ ! -r "$LAB_ENV_FILE" ]]; then
  echo "Missing DeepSec MCP environment file: $LAB_ENV_FILE" >&2
  echo "Copy .deep-sec-mcp.env and its wallet directory from Cloud Shell, then set DEEPSEC_MCP_LAB_ENV if needed." >&2
  exit 1
fi
[[ -x "$VENV_DIR/bin/python" ]] || { echo "Missing Python virtual environment: $VENV_DIR" >&2; exit 1; }

set -a
source "$LAB_ENV_FILE"
set +a

: "${ADB_SERVICE:?ADB_SERVICE is missing from the lab environment}"
: "${TNS_ADMIN:?TNS_ADMIN is missing from the lab environment}"
: "${WALLET_PWD:?WALLET_PWD is missing from the lab environment}"
: "${OCI_DOMAIN_URL:?OCI_DOMAIN_URL is missing from the lab environment}"
: "${OCI_CLIENT_ID:?OCI_CLIENT_ID is missing from the lab environment}"
: "${OCI_SCOPE:?OCI_SCOPE is missing from the lab environment}"
[[ -f "$TNS_ADMIN/tnsnames.ora" ]] || { echo "Wallet is not available at TNS_ADMIN=$TNS_ADMIN" >&2; exit 1; }

PUBLIC_URL="${WEB_HR_PUBLIC_URL:-}"
if [[ -z "$PUBLIC_URL" ]]; then
  PUBLIC_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$PUBLIC_IP" ]] || { echo "Set WEB_HR_PUBLIC_URL, for example https://app.example.com" >&2; exit 1; }
  PUBLIC_URL="http://${PUBLIC_IP}:8012"
fi
PUBLIC_URL="${PUBLIC_URL%/}"
REDIRECT_URI="${PUBLIC_URL}/callback"

cat >"$SCRIPT_DIR/.env" <<EOF
WEB_HR_HOST=0.0.0.0
WEB_HR_PORT=8012
WEB_HR_REDIRECT_URI=${REDIRECT_URI}
WEB_HR_TNS_ALIAS=${ADB_SERVICE}
EOF
chmod 600 "$SCRIPT_DIR/.env"

"$VENV_DIR/bin/pip" install --upgrade -r "$SCRIPT_DIR/requirements.txt"

echo
echo "OCI IAM Web HR App is configured for: $PUBLIC_URL"
echo "Registered OCI IAM callback required: $REDIRECT_URI"
echo
echo "Before signing in, add that exact callback URI to the OCI IAM public client."
echo "From Cloud Shell, source the lab environment, append it to OCI_REDIRECT_URIS,"
echo "and rerun setup_adbs_oci_iam.sh so it patches the existing public client."
echo
PYTHON_BIN="$VENV_DIR/bin/python" "$SCRIPT_DIR/start.sh"
echo
echo "Open: $PUBLIC_URL"
