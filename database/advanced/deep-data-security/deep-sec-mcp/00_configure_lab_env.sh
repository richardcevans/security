#!/bin/bash
# Create the local environment file used by the optional DeepSec MCP scripts.
# This script does not create OCI resources. Use Terraform or the OCI Console
# first, then put the resulting values here.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

usage() {
  cat <<'EOF'
Usage:
  ./00_configure_lab_env.sh

Set values with environment variables before running, or edit .deep-sec-mcp.env
after the script creates it.

Common values:
  DB_NAME                          Autonomous Database name
  ADB_OCID                         Autonomous Database OCID
  ADB_SERVICE                      TNS service, for example deepsec1_low
  ADMIN_PWD                        ADMIN password
  WALLET_DIR                       Local wallet directory
  TNS_ADMIN                        Usually same as WALLET_DIR
  OCI_DOMAIN_URL                   Identity domain URL
  OCI_DB_APP_ID                    DB resource app OCID
  OCI_DB_CLIENT_ID                 DB resource app client id
  OCI_DB_CLIENT_SECRET             DB resource app client secret
  OCI_CLIENT_ID                    OAuth public/confidential client id
  OCI_CLIENT_SECRET                Optional OAuth client secret
  OCI_SCOPE                        Database OAuth scope
  DATA_ROLE_MAPPING_TYPE           IAM_GROUP_NAME for MCP/PoP token path or IAM_OAUTH_GROUP for direct OAuth SQL
  OCI_IAM_EMPLOYEE_GROUP           Employee group name
  OCI_IAM_MANAGER_GROUP            Manager group name
  MARVIN_USERNAME                  Manager test user
  EMMA_USERNAME                    Employee test user
  DATABASE_TOOLS_CONNECTION_ID     Existing Database Tools connection OCID
  MCP_SERVER_ID                    Existing MCP server OCID
  MCP_SERVER_ENDPOINT              MCP server endpoint URL

Optional wallet download:
  DOWNLOAD_WALLET=1 ADB_OCID=<ocid> ADMIN_PWD=<password> ./00_configure_lab_env.sh
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

show_cmd() {
  printf '  $'
  printf ' %q' "$@"
  printf '\n'
}

write_env() {
  umask 077
  cat > "$ENV_FILE" <<EOF
# DeepSec MCP optional command environment.
# Source with: source ./.deep-sec-mcp.env

export DB_NAME="${DB_NAME:-deepsec1}"
export ADB_OCID="${ADB_OCID:-}"
export ADB_SERVICE="${ADB_SERVICE:-${DB_NAME:-deepsec1}_low}"
export ADMIN_PWD="${ADMIN_PWD:-}"
export WALLET_DIR="${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME:-deepsec1}}"
export TNS_ADMIN="${TNS_ADMIN:-${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME:-deepsec1}}}"
export WALLET_PWD="${WALLET_PWD:-Oracle123+}"

export OCI_DOMAIN_URL="${OCI_DOMAIN_URL:-}"
export OCI_DB_APP_ID="${OCI_DB_APP_ID:-}"
export OCI_DB_CLIENT_ID="${OCI_DB_CLIENT_ID:-}"
export OCI_DB_CLIENT_SECRET="${OCI_DB_CLIENT_SECRET:-}"
export OCI_CLIENT_ID="${OCI_CLIENT_ID:-}"
export OCI_CLIENT_SECRET="${OCI_CLIENT_SECRET:-}"
export OCI_SCOPE="${OCI_SCOPE:-}"
export OCI_REDIRECT_URI="${OCI_REDIRECT_URI:-http://localhost:8888/callback}"
export OCI_TOKEN_DIR="${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"

export DATA_ROLE_MAPPING_TYPE="${DATA_ROLE_MAPPING_TYPE:-IAM_GROUP_NAME}"
export OCI_IAM_EMPLOYEE_GROUP="${OCI_IAM_EMPLOYEE_GROUP:-example-domain/deepsec-employees}"
export OCI_IAM_MANAGER_GROUP="${OCI_IAM_MANAGER_GROUP:-example-domain/deepsec-managers}"
export OCI_USERNAME_DOMAIN="${OCI_USERNAME_DOMAIN:-}"
export MARVIN_USERNAME="${MARVIN_USERNAME:-marvin}"
export EMMA_USERNAME="${EMMA_USERNAME:-emma}"

export DATABASE_TOOLS_CONNECTION_ID="${DATABASE_TOOLS_CONNECTION_ID:-}"
export MCP_SERVER_ID="${MCP_SERVER_ID:-}"
export MCP_SERVER_ENDPOINT="${MCP_SERVER_ENDPOINT:-}"
export MCP_BUCKET_NAME="${MCP_BUCKET_NAME:-}"
export MCP_COMPARTMENT_OCID="${MCP_COMPARTMENT_OCID:-}"
export MCP_IDENTITY_DOMAIN_OCID="${MCP_IDENTITY_DOMAIN_OCID:-}"
EOF
}

download_wallet() {
  if [ "${DOWNLOAD_WALLET:-0}" != "1" ]; then
    return 0
  fi

  if [ -z "${ADB_OCID:-}" ]; then
    echo -e "${RED}ERROR: ADB_OCID is required when DOWNLOAD_WALLET=1.${NC}" >&2
    exit 1
  fi

  if ! command -v oci >/dev/null 2>&1; then
    echo -e "${RED}ERROR: OCI CLI is required to download the wallet.${NC}" >&2
    exit 1
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    echo -e "${RED}ERROR: unzip is required to extract the wallet.${NC}" >&2
    exit 1
  fi

  mkdir -p "${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME:-deepsec1}}"
  local wallet_zip="${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME:-deepsec1}}/wallet.zip"

  echo -e "${CYAN}Downloading wallet to ${wallet_zip}${NC}"
  show_cmd oci db autonomous-database generate-wallet --autonomous-database-id "$ADB_OCID" --password '<hidden>' --file "$wallet_zip"
  oci db autonomous-database generate-wallet \
    --autonomous-database-id "$ADB_OCID" \
    --password "${WALLET_PWD:-Oracle123+}" \
    --file "$wallet_zip"

  unzip -o "$wallet_zip" -d "${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME:-deepsec1}}" >/dev/null

  if [ -f "${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME:-deepsec1}}/sqlnet.ora" ]; then
    perl -pi -e "s|DIRECTORY=\\\"\\?/network/admin\\\"|DIRECTORY=\\\"${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME:-deepsec1}}\\\"|g" \
      "${WALLET_DIR:-$HOME/adb_wallet/${DB_NAME:-deepsec1}}/sqlnet.ora"
  fi
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Configure DeepSec MCP Optional Script Environment                      ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

download_wallet
write_env

echo -e "${GREEN}Created ${ENV_FILE}${NC}"
echo
echo -e "${YELLOW}Next:${NC}"
echo "  source ./.deep-sec-mcp.env"
echo "  ./02_create_hr_schema.sh"
echo
