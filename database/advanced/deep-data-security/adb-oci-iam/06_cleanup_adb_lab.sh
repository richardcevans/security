#!/bin/bash
# Remove ADB OCI IAM lab database objects. Optionally delete the ADB instance.

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
require_adb_env

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
echo -e "${GREEN}      Task 6: Clean Up ADB OCI IAM Data Grants Lab                          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}ADB_SERVICE = ${ADB_SERVICE}${NC}"
echo -e "${CYAN}ADB_OCID    = ${ADB_OCID}${NC}"
echo

if confirm "This removes HR, IAM_SHARED_SCHEMA, data roles, and local lab roles."; then
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
    'DROP USER iam_shared_schema',
    'DROP USER hr CASCADE'
  );
  failures SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST();

  PROCEDURE record_failure(statement_text VARCHAR2, err VARCHAR2) IS
  BEGIN
    failures.EXTEND;
    failures(failures.COUNT) := statement_text || ' -> ' || err;
  END;
BEGIN
  DBMS_OUTPUT.PUT_LINE('Running cleanup statements...');

  FOR i IN 1 .. steps.COUNT LOOP
    BEGIN
      DBMS_OUTPUT.PUT_LINE('  ' || steps(i));
      EXECUTE IMMEDIATE steps(i);
      DBMS_OUTPUT.PUT_LINE('    OK');
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE IN (-1918, -1919, -1924, -904, -942, -950) THEN
          DBMS_OUTPUT.PUT_LINE('    Skipped: ' || SQLERRM);
        ELSE
          DBMS_OUTPUT.PUT_LINE('    Failed: ' || SQLERRM);
          record_failure(steps(i), SQLERRM);
        END IF;
    END;
  END LOOP;

  IF failures.COUNT > 0 THEN
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Cleanup completed with failures:');
    FOR i IN 1 .. failures.COUNT LOOP
      DBMS_OUTPUT.PUT_LINE('  - ' || failures(i));
    END LOOP;
  ELSE
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Cleanup completed without blocking failures.');
  END IF;
END;
/

exit;
SQL
else
  echo -e "${YELLOW}Skipped database object cleanup.${NC}"
fi

if [ "$DELETE_ADB" = true ]; then
  if confirm "This deletes the Autonomous Database ${DB_NAME}."; then
    if [ -z "${ROOT_COMP_ID:-}" ]; then
      echo -e "${RED}ERROR: ROOT_COMP_ID is not set; cannot delete ADB safely.${NC}"
      exit 1
    fi

    echo -e "${CYAN}Deleting ADB:${NC}"
    show_cmd oci db autonomous-database delete \
      --autonomous-database-id "$ADB_OCID" \
      --force \
      --wait-for-state TERMINATED
    oci db autonomous-database delete \
      --autonomous-database-id "$ADB_OCID" \
      --force \
      --wait-for-state TERMINATED \
      >/dev/null
    echo -e "${CYAN}Deleted ADB ${DB_NAME}.${NC}"
  else
    echo -e "${YELLOW}Skipped ADB deletion.${NC}"
  fi
fi

echo
echo -e "${GREEN}Task 6 completed.${NC}"
echo
