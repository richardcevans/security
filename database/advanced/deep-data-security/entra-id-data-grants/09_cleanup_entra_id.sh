#!/bin/bash
# Remove Microsoft Entra ID applications created for this lab.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -f|--DELETE)
      FORCE=1
      shift
      ;;
    -h|--help)
      echo "Usage: ./09_cleanup_entra_id.sh [-f|--DELETE]"
      exit 0
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}"
      exit 1
      ;;
  esac
done

export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export ENTRA_DB_APP_NAME="${ENTRA_DB_APP_NAME:-Oracle Database 26ai - ${PDB_NAME}}"
export ENTRA_CLIENT_APP_NAME="${ENTRA_CLIENT_APP_NAME:-Oracle Client Interactive - ${PDB_NAME}}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Cleanup Microsoft Entra ID Lab Objects                                ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${YELLOW}This deletes Entra app registrations and their enterprise applications:${NC}"
echo "  ${ENTRA_CLIENT_APP_NAME}"
echo "  ${ENTRA_DB_APP_NAME}"
echo

if ! command -v az >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is not installed or not on PATH.${NC}"
  exit 1
fi

if ! az account show >/dev/null 2>&1; then
  echo -e "${RED}ERROR: Azure CLI is not logged in. Run: az login${NC}"
  exit 1
fi

if [ "$FORCE" -ne 1 ]; then
  read -r -p "Type DELETE to continue: " confirm
  if [ "$confirm" != "DELETE" ]; then
    echo "Cleanup cancelled."
    exit 0
  fi
fi

find_app_id() {
  local display_name="$1"
  APP_NAME="$display_name" az ad app list --display-name "$display_name" -o json | python3 -c '
import json, os, sys
name = os.environ["APP_NAME"]
apps = [a for a in json.load(sys.stdin) if a.get("displayName") == name]
print(apps[0].get("appId", "") if apps else "")
'
}

delete_app() {
  local display_name="$1"
  local app_id
  app_id=$(find_app_id "$display_name")
  if [ -z "$app_id" ]; then
    echo -e "${YELLOW}  App not found: ${display_name}${NC}"
    return
  fi
  echo -e "${CYAN}  Deleting app: ${display_name} (${app_id})${NC}"
  az ad app delete --id "$app_id" >/dev/null
}

delete_app "$ENTRA_CLIENT_APP_NAME"
delete_app "$ENTRA_DB_APP_NAME"

echo
echo -e "${GREEN}Microsoft Entra ID cleanup completed.${NC}"
echo
