#!/bin/bash
# Verify the ADB Entra ID data grants with the configured Marvin identity.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_entra_env

ALIAS_NAME="${ADB_ENTRA_ALIAS:-hrdb_entra}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 5: Connect and Verify as Marvin via Microsoft Entra ID           ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}Expected Entra identity:${NC} ${MARVIN_UPN}"
echo -e "${PURPLE}This should open browser-based Entra ID login when the client has GUI access.${NC}"
echo -e "${PURPLE}In headless Cloud Shell, copy the displayed login URL or device flow if prompted.${NC}"
echo
echo -e "${CYAN}Executing: sqlplus /@${ALIAS_NAME}${NC}"
echo

if command -v tnsping >/dev/null 2>&1 && ! tnsping "$ALIAS_NAME" >/dev/null 2>&1; then
  echo -e "${RED}ERROR: TNS alias ${ALIAS_NAME} is not available.${NC}"
  echo -e "${YELLOW}Run ./04_configure_azure_interactive.sh first.${NC}"
  exit 1
fi

sqlplus -L -s "/@${ALIAS_NAME}" <<SQL
set pagesize 100
set linesize 180
set tab off
set trimspool on
whenever sqlerror exit sql.sqlcode

prompt
prompt ========================================================================
prompt Entra ID Session Identity
prompt ========================================================================

col current_user format a30
col authenticated_identity format a55
col auth_method format a25

SELECT
  sys_context('USERENV', 'CURRENT_USER') AS current_user,
  sys_context('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_identity,
  sys_context('USERENV', 'AUTHENTICATION_METHOD') AS auth_method
FROM dual;

DECLARE
  expected VARCHAR2(256) := lower('${MARVIN_UPN}');
  actual   VARCHAR2(512) := lower(SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY'));
BEGIN
  IF expected IS NOT NULL AND actual NOT IN (expected) AND INSTR(actual, expected) = 0 THEN
    RAISE_APPLICATION_ERROR(-20001, 'Expected Marvin identity containing "' || expected || '", got "' || actual || '". Sign out of cached browser sessions or retry with the right Entra account.');
  END IF;
END;
/

prompt
prompt ========================================================================
prompt Active Roles from Entra App Role Mappings
prompt ========================================================================

col role_name format a30
SELECT role_name
FROM v\$end_user_data_role
ORDER BY role_name;

prompt
prompt ========================================================================
prompt Same SQL: SELECT visible HR rows
prompt ========================================================================

col first_name format a12
col last_name format a12
col user_name format a42
col ssn format a15
SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number
FROM hr.employees
ORDER BY employee_id;

prompt
prompt ========================================================================
prompt Per-Column Authorization
prompt ========================================================================

col view_ssn format a10
col update_ssn format a10
col view_salary format a12
col update_salary format a14
SELECT first_name,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', ssn)          AS view_ssn,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', ssn)          AS update_ssn,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', salary)       AS view_salary,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary)       AS update_salary
FROM hr.employees emp
ORDER BY employee_id;

exit;
SQL

echo
echo -e "${GREEN}Task 5 completed. Next: run ./06_verify_as_emma.sh${NC}"
echo
