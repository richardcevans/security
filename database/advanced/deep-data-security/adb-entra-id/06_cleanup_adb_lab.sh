#!/bin/bash
# Remove ADB Microsoft Entra ID lab database objects. Optionally delete the ADB instance.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

DELETE_ADB=false
FORCE=false

for arg in "$@"; do
  case "$arg" in
    --delete-adb)
      DELETE_ADB=true
      ;;
    -f|--force|--DELETE)
      FORCE=true
      ;;
    *)
      echo "Usage: $0 [--delete-adb] [-f|--force|--DELETE]" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_entra_env

confirm() {
  local prompt="$1"
  if [ "$FORCE" = true ]; then
    return 0
  fi
  echo -n "$prompt Type DELETE to continue: "
  read -r answer
  [ "$answer" = "DELETE" ]
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 6: Clean Up ADB Microsoft Entra ID Data Grants Lab               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

if confirm "This removes HR, data roles, and local lab roles."; then
  admin_sqlplus <<'SQL'
set echo on
set serveroutput on
whenever sqlerror exit sql.sqlcode

DROP DATA GRANT IF EXISTS hr.HRAPP_MANAGER_ACCESS;
DROP DATA GRANT IF EXISTS hr.HRAPP_EMPLOYEES_ACCESS;
DROP DATA ROLE IF EXISTS hrapp_managers;
DROP DATA ROLE IF EXISTS hrapp_employees;
DROP ROLE IF EXISTS direct_logon_role;

BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr CASCADE';
EXCEPTION WHEN OTHERS THEN IF SQLCODE != -1918 THEN RAISE; END IF;
END;
/

exit;
SQL
else
  echo -e "${YELLOW}Skipped database object cleanup.${NC}"
fi

if [ "$DELETE_ADB" = true ]; then
  if confirm "This deletes the Autonomous Database ${DB_NAME}."; then
    oci db autonomous-database delete \
      --autonomous-database-id "$ADB_OCID" \
      --force \
      --wait-for-state SUCCEEDED \
      >/dev/null
    echo -e "${CYAN}Deleted ADB ${DB_NAME}.${NC}"
  else
    echo -e "${YELLOW}Skipped ADB deletion.${NC}"
  fi
fi

echo
echo -e "${GREEN}Task 6 completed.${NC}"
echo
