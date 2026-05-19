#!/bin/bash
# Delete the Microsoft Entra ID app registrations created by this ADB lab.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

FORCE=false
for arg in "$@"; do
  case "$arg" in
    -f|--force|--DELETE)
      FORCE=true
      ;;
    *)
      echo "Usage: $0 [-f|--force|--DELETE]" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.adb-entra-id.env"
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

export DB_NAME="${DB_NAME:-deepsec7}"
export ENTRA_DB_APP_NAME="${ENTRA_DB_APP_NAME:-Oracle Database 26ai ADB - ${DB_NAME}}"
export ENTRA_CLIENT_APP_NAME="${ENTRA_CLIENT_APP_NAME:-Oracle Client Interactive ADB - ${DB_NAME}}"

if ! command -v az >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is not installed or not on PATH.${NC}"
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is not logged in.${NC}"
  echo -e "${YELLOW}Run: az login${NC}"
  exit 1
fi

confirm() {
  if [ "$FORCE" = true ]; then
    return 0
  fi
  echo -n "This deletes Entra app registrations for ${DB_NAME}. Type DELETE to continue: "
  read -r answer
  [ "$answer" = "DELETE" ]
}

delete_app_by_name() {
  local display_name="$1"
  local app_id

  app_id=$(az ad app list \
    --display-name "$display_name" \
    --query "[?displayName=='${display_name}'].appId | [0]" \
    --output tsv 2>/dev/null || true)

  if [ -z "$app_id" ]; then
    echo -e "${YELLOW}  App not found: ${display_name}${NC}"
    return
  fi

  echo -e "${CYAN}  Deleting app ${display_name}: ${app_id}${NC}"
  az ad app delete --id "$app_id"
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 8: Clean Up Microsoft Entra ID Objects                           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}ENTRA_DB_APP_NAME     = ${ENTRA_DB_APP_NAME}${NC}"
echo -e "${CYAN}ENTRA_CLIENT_APP_NAME = ${ENTRA_CLIENT_APP_NAME}${NC}"
echo

if confirm; then
  delete_app_by_name "$ENTRA_CLIENT_APP_NAME"
  delete_app_by_name "$ENTRA_DB_APP_NAME"
else
  echo -e "${YELLOW}Skipped Entra ID cleanup.${NC}"
fi

echo
echo -e "${GREEN}Task 8 completed.${NC}"
echo
