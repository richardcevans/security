#!/bin/bash
# Verify the ADB OCI IAM data grants with the current OCI IAM db-token.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "${SCRIPT_DIR}/lib_adb.sh"
require_adb_env

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 5: Verify as the Current OCI IAM User                            ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${CYAN}Connecting with slash login and OCI IAM db-token:${NC}"
show_cmd sqlplus -L -s "/@${ADB_SERVICE}"
echo

if [ ! -f "${HOME}/.oci/db-token/token" ]; then
  echo -e "${RED}ERROR: OCI IAM db-token was not found at ${HOME}/.oci/db-token/token.${NC}"
  echo -e "${YELLOW}Run ./04_get_iam_db_token.sh first.${NC}"
  exit 1
fi

sqlplus -L -s "/@${ADB_SERVICE}" <<'SQL'
set pagesize 100
set linesize 180
set tab off
set trimspool on
whenever sqlerror exit sql.sqlcode

prompt
prompt ========================================================================
prompt OCI IAM Session Identity
prompt ========================================================================

col current_user format a30
col authenticated_identity format a45
col auth_method format a25

SELECT
  sys_context('USERENV', 'CURRENT_USER') AS current_user,
  sys_context('USERENV', 'AUTHENTICATED_IDENTITY') AS authenticated_identity,
  sys_context('USERENV', 'AUTHENTICATION_METHOD') AS auth_method
FROM dual;

prompt
prompt ========================================================================
prompt Active Roles from OCI IAM Group Mappings
prompt ========================================================================

col role format a30
SELECT role
FROM session_roles
WHERE role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS', 'DIRECT_LOGON_ROLE')
ORDER BY role;

prompt
prompt ========================================================================
prompt Same SQL: SELECT visible HR rows
prompt - Employee grant: own row with SSN visible
prompt - Manager grant: direct reports with SSN hidden
prompt ========================================================================

col first_name format a12
col last_name format a12
col user_name format a32
col ssn format a15
col phone_number format a15
SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number
FROM hr.employees
ORDER BY employee_id;

prompt
prompt ========================================================================
prompt Column Authorization
prompt ========================================================================

col ssn_authorized format a16
SELECT
  first_name,
  DECODE(ORA_IS_COLUMN_AUTHORIZED(ssn), TRUE, 'TRUE', FALSE, 'FALSE') AS ssn_authorized
FROM hr.employees
ORDER BY employee_id;

exit;
SQL

echo
echo -e "${GREEN}Task 5 completed.${NC}"
echo
