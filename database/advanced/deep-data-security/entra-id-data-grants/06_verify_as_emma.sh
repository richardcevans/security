#!/bin/bash
# =========================================================================================
# Script Name : 06_verify_as_emma.sh
#
# Parameter   : None
#
# Notes       : Task 12 - Connect as Emma via Entra ID and verify data grants.
#               Uses sqlplus /@hrdb which triggers AZURE_INTERACTIVE browser login.
#               Emma has only the EMPLOYEES app role — sees 1 row (self only).
#
# Modified by         Date         Change
# Oracle DB Security  04/02/2026   Creation
# =========================================================================================

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 12: Connect and Verify as Emma (via Entra ID)                    ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}Emma has only the EMPLOYEES app role in Entra ID.${NC}"
echo -e "${PURPLE}Oracle maps this to HRAPP_EMPLOYEES only — no manager role.${NC}"
echo -e "${PURPLE}Same SQL: SELECT * FROM hr.employees — Emma sees 1 row.${NC}"
echo
echo -e "${YELLOW}Connecting as Emma via Entra ID...${NC}"
echo -e "${CYAN}Executing: sqlplus /@hrdb${NC}"
echo -e "${PURPLE}NOTE: This will open your browser for Entra ID login.${NC}"
echo -e "${PURPLE}      Log in as Emma's Entra ID account.${NC}"
echo

sqlplus -s /@hrdb <<EOF

set echo off
set feedback off
set verify off
set sqlprompt ""
set sqlcontinue ""
set serveroutput on
set lines 160
set pages 9999

prompt
prompt ========================================================================
prompt Emma's Identity (via Entra ID)
prompt ========================================================================

col current_user           format a15
col authenticated_identity format a40
col auth_method            format a15

SELECT
    SYS_CONTEXT('USERENV','CURRENT_USER')           AS CURRENT_USER,
    SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS AUTHENTICATED_IDENTITY,
    SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD')  AS AUTH_METHOD
FROM DUAL;

prompt
prompt ========================================================================
prompt Emma's Active Data Roles
prompt  - Only HRAPP_EMPLOYEES — no manager role.
prompt ========================================================================

col role_name format a30
SELECT ROLE_NAME FROM V\$END_USER_DATA_ROLE;

prompt
prompt ========================================================================
prompt Emma's Query: SELECT * FROM hr.employees
prompt  - SAME SQL as Marvin. SAME SQL as the traditional app.
prompt  - Emma sees 1 row (self only).
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
prompt Emma's Per-Column Authorization
prompt  - Emma can view her SSN and salary but only update phone_number.
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
echo -e "${GREEN}      Emma sees 1 row — not 7.                                              ${NC}"
echo -e "${GREEN}      Same query as Marvin. Same app code. Different data.                  ${NC}"
echo -e "${GREEN}      Authenticated via Entra ID. Database enforces the policy.             ${NC}"
echo -e "${GREEN}      Next: run 07_verify_security_boundary.sh                              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
