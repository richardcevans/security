#!/bin/bash
# =========================================================================================
# Script Name : 05_verify_as_marvin.sh
#
# Parameter   : None
#
# Notes       : Task 5 - Verify the migration as Marvin.
#               Connects as end user marvin@domain.com via Entra ID token and
#               runs the SAME query the traditional app ran. Marvin sees 4 rows
#               (self + 3 direct reports), not all 7.
#
# Modified by         Date         Change
# Oracle DB Security  01/04/2026   Creation
# Oracle DB Security  04/28/2026   Entra ID UPN-format end user; source lab_env.sh
# =========================================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

[ -f "${SCRIPT_DIR}/lab_env.sh" ] && source "${SCRIPT_DIR}/lab_env.sh"
export DOMAIN_NAME="${DOMAIN_NAME:-contoso.com}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Verify Migration: Connect as Marvin (Manager)                         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}Marvin is an end user with HRAPP_EMPLOYEES_LOCAL and HRAPP_MANAGERS_LOCAL.${NC}"
echo -e "${PURPLE}His Entra ID identity (marvin@${DOMAIN_NAME}) matches the user_name column.${NC}"
echo -e "${PURPLE}The app runs the SAME SQL: SELECT * FROM hr.employees${NC}"
echo -e "${PURPLE}But now Marvin sees only his own row + his direct reports.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"

echo -e "${YELLOW}Connecting as end user marvin@${DOMAIN_NAME}...${NC}"
echo -e "${CYAN}Executing: sqlplus /nolog → CONNECT \"marvin@${DOMAIN_NAME}\"/******@${PDB_NAME}${NC}"
echo

sqlplus -s /nolog <<EOF
CONNECT "marvin@${DOMAIN_NAME}"/Oracle123@${PDB_NAME}

set echo off
set serveroutput on
set lines 160
set pages 9999

prompt
prompt ========================================================================
prompt Marvin's Identity
prompt  - CURRENT_USER = XS\$NULL (end user, not a schema user)
prompt  - AUTHENTICATED_IDENTITY = marvin
prompt ========================================================================

col current_user           format a15
col authenticated_identity format a25
col auth_method            format a15

SELECT
    SYS_CONTEXT('USERENV','CURRENT_USER')           AS CURRENT_USER,
    SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS AUTHENTICATED_IDENTITY,
    SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD')  AS AUTH_METHOD
FROM DUAL;

prompt
prompt ========================================================================
prompt Marvin's Active Data Roles
prompt ========================================================================

SELECT ROLE_NAME FROM V\$END_USER_DATA_ROLE;

prompt
prompt ========================================================================
prompt Marvin's Query: SELECT * FROM hr.employees
prompt  - SAME SQL the traditional app ran.
prompt  - Before migration: 7 rows (everything).
prompt  - After migration: 4 rows (Marvin + 3 direct reports).
prompt ========================================================================

col first_name  format a12
col last_name   format a12
col ssn         format a15
col salary      format 999,999.99

SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
  FROM hr.employees
 ORDER BY employee_id;

prompt
prompt ========================================================================
prompt Marvin's Per-Column Authorization
prompt  - Shows what Marvin can SELECT and UPDATE for each visible row.
prompt ========================================================================

col first_name    format a10
col view_ssn      format a10
col update_ssn    format a10
col view_salary   format a12
col update_salary format a14
col view_phone    format a10
col update_phone  format a12

SELECT first_name,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', ssn)          AS view_ssn,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', ssn)          AS update_ssn,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', salary)       AS view_salary,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary)       AS update_salary,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', phone_number) AS view_phone,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', phone_number) AS update_phone
  FROM hr.employees emp;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Marvin sees 4 rows — not 7. SSN hidden for direct reports.            ${NC}"
echo -e "${GREEN}      Same SQL. Zero filtering code. Database enforces the policy.          ${NC}"
echo -e "${GREEN}      Next: run 06_verify_as_emma.sh                                       ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
