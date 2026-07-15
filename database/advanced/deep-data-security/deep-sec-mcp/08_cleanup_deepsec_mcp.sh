#!/bin/bash
# Remove local DeepSec MCP demo database objects and token cache.

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
    -h|--help)
      echo "Usage: ./08_cleanup_deepsec_mcp.sh [-f|--force|--DELETE]"
      exit 0
      ;;
    *)
      echo "Usage: ./08_cleanup_deepsec_mcp.sh [-f|--force|--DELETE]" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_deepsec_mcp.sh"
require_adb_env

confirm() {
  if [ "$FORCE" = true ]; then
    return 0
  fi

  echo -n "This removes HR schema, Deep Data Security roles/grants, and local token cache. Type DELETE to continue: "
  read -r answer
  [ "$answer" = "DELETE" ]
}

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Clean Up DeepSec MCP Database Objects                                 ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}ADB_SERVICE = ${ADB_SERVICE}${NC}"
echo

if ! confirm; then
  echo -e "${YELLOW}Skipped cleanup.${NC}"
  exit 0
fi

echo -e "${CYAN}SQL*Plus command:${NC}"
show_cmd sqlplus -L -s "admin/<hidden>@${ADB_SERVICE}"

admin_sqlplus <<'SQL'
set echo off
set serveroutput on
set feedback off
set heading off
whenever sqlerror continue

DECLARE
  TYPE step_list IS TABLE OF VARCHAR2(4000);
  steps step_list := step_list(
    'DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS',
    'DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT',
    'DROP DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS',
    'DROP DATA ROLE hrapp_managers',
    'DROP DATA ROLE hrapp_employees',
    'DROP ROLE direct_logon_role',
    'DROP ROLE employee_context_admin',
    'DROP USER hr CASCADE'
  );
BEGIN
  FOR i IN 1 .. steps.COUNT LOOP
    BEGIN
      DBMS_OUTPUT.PUT_LINE('  ' || steps(i));
      EXECUTE IMMEDIATE steps(i);
      DBMS_OUTPUT.PUT_LINE('    OK');
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('    Skipped or failed: ' || SQLERRM);
    END;
  END LOOP;
END;
/

exit;
SQL

echo
echo -e "${YELLOW}Removing local OAuth token cache ${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}${NC}"
rm -rf "${OCI_TOKEN_DIR:-$HOME/.oci/deep-sec-mcp}"

echo -e "${GREEN}Cleanup completed.${NC}"
echo
