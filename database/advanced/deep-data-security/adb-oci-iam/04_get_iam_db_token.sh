#!/bin/bash
# Configure the ADB wallet for OCI IAM token auth and get a db-token.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_env

SQLNET_FILE="${TNS_ADMIN}/sqlnet.ora"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 4: Configure SQL*Plus for OCI IAM db-token Login                 ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}TNS_ADMIN   = ${TNS_ADMIN}${NC}"
echo -e "${CYAN}ADB_SERVICE = ${ADB_SERVICE}${NC}"
echo

if ! command -v oci >/dev/null 2>&1; then
  echo -e "${RED}ERROR: OCI CLI is not available. Run this from OCI Cloud Shell or install OCI CLI.${NC}"
  exit 1
fi

if [ ! -f "$SQLNET_FILE" ]; then
  echo -e "${RED}ERROR: ${SQLNET_FILE} was not found. Re-run ./00_setup_adb.sh to download the ADB wallet.${NC}"
  exit 1
fi

echo -e "${YELLOW}Step 1: Ensuring sqlnet.ora has TOKEN_AUTH=OCI_TOKEN...${NC}"
if grep -Eiq '^[[:space:]]*TOKEN_AUTH[[:space:]]*=' "$SQLNET_FILE"; then
  echo -e "${CYAN}  Updating sqlnet.ora:${NC}"
  show_cmd sed -i.bak-token-auth -E 's/^[[:space:]]*TOKEN_AUTH[[:space:]]*=.*/TOKEN_AUTH=OCI_TOKEN/I' "$SQLNET_FILE"
  sed -i.bak-token-auth -E 's/^[[:space:]]*TOKEN_AUTH[[:space:]]*=.*/TOKEN_AUTH=OCI_TOKEN/I' "$SQLNET_FILE"
  echo -e "${CYAN}  Updated existing TOKEN_AUTH entry.${NC}"
else
  echo -e "${CYAN}  Backing up sqlnet.ora:${NC}"
  show_cmd cp "$SQLNET_FILE" "${SQLNET_FILE}.bak-token-auth"
  cp "$SQLNET_FILE" "${SQLNET_FILE}.bak-token-auth"
  echo -e "${CYAN}  Appending TOKEN_AUTH=OCI_TOKEN to ${SQLNET_FILE}${NC}"
  {
    echo
    echo "# Deep Data Security ADB lab: use OCI IAM db-token for slash login."
    echo "TOKEN_AUTH=OCI_TOKEN"
  } >> "$SQLNET_FILE"
  echo -e "${CYAN}  Added TOKEN_AUTH=OCI_TOKEN.${NC}"
fi

echo
echo -e "${YELLOW}Step 2: Requesting an OCI IAM database token...${NC}"
if [ -n "${OCI_CLI_AUTH:-}" ]; then
  show_cmd oci iam db-token get --auth "$OCI_CLI_AUTH"
  oci iam db-token get --auth "$OCI_CLI_AUTH" >/dev/null
else
  show_cmd oci iam db-token get
  oci iam db-token get >/dev/null
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 4 Completed: OCI IAM db-token Ready                              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Default token location: ${HOME}/.oci/db-token${NC}"
echo "Ready: run ./05_verify_as_cloud_shell_user.sh"
echo
