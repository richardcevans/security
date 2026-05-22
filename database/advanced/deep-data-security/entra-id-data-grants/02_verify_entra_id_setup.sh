#!/bin/bash
# Verify Microsoft Entra ID objects used by this lab.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_env_check.sh"
require_entra_lab_env

export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export ENTRA_DB_APP_NAME="${ENTRA_DB_APP_NAME:-Oracle Database 26ai - ${PDB_NAME}${ENTRA_LAB_INSTANCE_ID:+ - ${ENTRA_LAB_INSTANCE_ID}}}"
export ENTRA_CLIENT_APP_NAME="${ENTRA_CLIENT_APP_NAME:-Oracle Client Interactive - ${PDB_NAME}${ENTRA_LAB_INSTANCE_ID:+ - ${ENTRA_LAB_INSTANCE_ID}}}"
export AZURE_CORE_ONLY_SHOW_ERRORS="${AZURE_CORE_ONLY_SHOW_ERRORS:-true}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify Microsoft Entra ID Setup                                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if ! command -v az >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is not installed or not on PATH.${NC}"
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is not logged in. Run: az login${NC}"
  exit 1
fi

find_app_id() {
  local display_name="$1"
  az ad app list --display-name "$display_name" -o json | APP_NAME="$display_name" python3 -c '
import json, os, sys
name = os.environ["APP_NAME"]
apps = [a for a in json.load(sys.stdin) if a.get("displayName") == name]
print(apps[0].get("appId", "") if apps else "")
'
}

db_app_id="${APP_ID:-$(find_app_id "$ENTRA_DB_APP_NAME")}"
client_app_id="${CLIENT_ID:-$(find_app_id "$ENTRA_CLIENT_APP_NAME")}"

if [ -z "$db_app_id" ]; then
  echo -e "${RED}ERROR: DB app not found: ${ENTRA_DB_APP_NAME}${NC}"
  exit 1
fi

if [ -z "$client_app_id" ]; then
  echo -e "${RED}ERROR: Client app not found: ${ENTRA_CLIENT_APP_NAME}${NC}"
  exit 1
fi

echo -e "${CYAN}DB app:${NC} ${ENTRA_DB_APP_NAME} (${db_app_id})"
az ad app show --id "$db_app_id" \
  --query "{displayName:displayName, appId:appId, identifierUris:identifierUris, appRoles:appRoles[].{displayName:displayName,value:value,isEnabled:isEnabled}, scopes:api.oauth2PermissionScopes[].{value:value,isEnabled:isEnabled}}" \
  --output table

echo
echo -e "${CYAN}Client app:${NC} ${ENTRA_CLIENT_APP_NAME} (${client_app_id})"
az ad app show --id "$client_app_id" \
  --query "{displayName:displayName, appId:appId, publicClient:publicClient.redirectUris, requiredResourceAccess:requiredResourceAccess}" \
  --output json

echo
echo -e "${CYAN}Enterprise applications/service principals:${NC}"
az ad sp show --id "$db_app_id" --query "{displayName:displayName,id:id,appId:appId}" --output table
az ad sp show --id "$client_app_id" --query "{displayName:displayName,id:id,appId:appId}" --output table

echo
echo -e "${GREEN}Microsoft Entra ID setup verification completed.${NC}"
echo
