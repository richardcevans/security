#!/bin/bash
# =========================================================================================
# Script Name : 05_verify_as_marvin.sh
#
# Parameter   : None
#
# Notes       : Task 11 - Connect as Marvin via Entra ID and verify data grants.
#               Uses sqlplus /@hrdb which triggers AZURE_INTERACTIVE browser login.
#               Marvin authenticates as his Entra ID identity and sees 4 rows.
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
echo -e "${GREEN}      Task 11: Connect and Verify as Marvin (via Entra ID)                  ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}Marvin has EMPLOYEES and MANAGERS app roles in Entra ID.${NC}"
echo -e "${PURPLE}Oracle maps these to HRAPP_EMPLOYEES and HRAPP_MANAGERS data roles.${NC}"
echo -e "${PURPLE}Same SQL: SELECT * FROM hr.employees — Marvin sees 4 rows.${NC}"
echo
echo -e "${YELLOW}Connecting as Marvin via Entra ID...${NC}"
echo -e "${CYAN}Executing: sqlplus /@hrdb${NC}"
echo -e "${PURPLE}NOTE: This will open your browser for Entra ID login.${NC}"
echo -e "${PURPLE}      Log in as Marvin's Entra ID account.${NC}"
echo

sqlplus /@hrdb <<EOF

set echo off
set serveroutput on
set lines 160
set pages 9999

prompt
prompt ========================================================================
prompt Marvin's Identity (via Entra ID)
prompt  - CURRENT_USER = XS\$NULL (end user, not a schema user)
prompt  - AUTHENTICATED_IDENTITY = marvin's Entra ID identity
prompt  - AUTH_METHOD = TOKEN (not PASSWORD)
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
prompt Marvin's Active Data Roles
prompt  - HRAPP_EMPLOYEES and HRAPP_MANAGERS should be active
prompt  - Activated automatically from the Entra ID token app roles
prompt ========================================================================

SELECT ROLE_NAME FROM V\$END_USER_DATA_ROLE;

prompt
prompt ========================================================================
prompt Marvin's Query: SELECT * FROM hr.employees
prompt  - Same SQL as Emma. Same SQL as a traditional app.
prompt  - Marvin sees 4 rows: himself + 3 direct reports.
prompt  - SSN is hidden for direct reports (manager grant excludes it).
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
echo -e "${GREEN}      Authenticated via Entra ID. Data grants enforced by the database.     ${NC}"
echo -e "${GREEN}      Next: run 06_verify_as_emma.sh                                        ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
