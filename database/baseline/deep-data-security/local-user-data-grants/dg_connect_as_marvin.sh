#!/bin/bash
# =========================================================================================
# Script Name : dg_connect_as_marvin.sh
#
# Parameter   : None
#
# Notes       : Task 6 - Connect and verify as Marvin.
#               Connects as end user Marvin, verifies identity, active data roles,
#               runs the same query an AI agent would, tests UPDATE privileges,
#               and checks per-column authorization.
#
# Modified by         Date         Change
# Oracle DB Security  18/03/2026   Creation
# =========================================================================================

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 6: Connect and Verify as Marvin (Manager)                        ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"

CONN_DISPLAY="marvin/******@${PDB_NAME}"

echo -e "${YELLOW}Connecting as end user Marvin...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

sqlplus -s marvin/Oracle123@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Step 2: Verify Marvin's Authentication Details
prompt  - CURRENT_USER will show XS\$NULL (end users are not schema users).
prompt  - AUTHENTICATED_IDENTITY shows the end user name.
prompt ========================================================================

col CURRENT_USER          format a15
col AUTHENTICATED_IDENTITY format a25
col ENTERPRISE_IDENTITY   format a20
col AUTH_METHOD            format a10
col ID_TYPE               format a10

SELECT
    SYS_CONTEXT('USERENV','CURRENT_USER')           AS CURRENT_USER,
    SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS AUTHENTICATED_IDENTITY,
    SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY')    AS ENTERPRISE_IDENTITY,
    SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD')  AS AUTH_METHOD,
    SYS_CONTEXT('USERENV','IDENTIFICATION_TYPE')    AS ID_TYPE
FROM DUAL;

prompt
prompt ========================================================================
prompt Step 3: Verify Active Data Roles
prompt  - Both HRAPP_EMPLOYEES and HRAPP_MANAGERS should be active.
prompt ========================================================================

col role_name format a25

SELECT ROLE_NAME FROM V\$END_USER_DATA_ROLE;

prompt
prompt ========================================================================
prompt Step 4: Verify the Username Used by Data Grant Predicates
prompt  - ora_end_user_context.username must match the user_name column
prompt    in hr.employees for the predicate to work.
prompt ========================================================================

SELECT ora_end_user_context.username FROM DUAL;

prompt
prompt ========================================================================
prompt Step 5: Display the Full End User Context (JSON)
prompt  - Shows all context attributes for Marvin's session.
prompt  - Uses json_serialize for readability.
prompt ========================================================================

SET LONG 90000
SELECT json_serialize(
    ora_end_user_context returning varchar2 pretty) AS context
FROM DUAL;

prompt
prompt ========================================================================
prompt Step 6: Verify Active Session Roles
prompt  - DIRECT_LOGON_ROLE and EMPLOYEE_CONTEXT_ADMIN should appear.
prompt ========================================================================

col role format a30

SELECT * FROM SESSION_ROLES ORDER BY 1;

prompt
prompt ========================================================================
prompt Step 7: "Show me my team" - The AI Agent Query
prompt  - Marvin should see 4 rows: himself + 3 direct reports.
prompt  - SSN is NULL for direct reports (manager grant excludes it).
prompt  - Marvin sees his own SSN (employee grant includes it).
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
prompt Step 8: Inspect the End User Context
prompt  - The o:onFirstRead trigger populated Marvin's employee ID.
prompt ========================================================================

SELECT ora_end_user_context.HR FROM DUAL;

prompt
prompt ========================================================================
prompt Step 9: Marvin Updates a Team Member's Salary
prompt  - Manager grant allows UPDATE on salary for direct reports.
prompt ========================================================================

prompt UPDATE hr.employees SET salary = 125000 WHERE first_name = 'Emma';
UPDATE hr.employees
   SET salary = 125000
 WHERE first_name = 'Emma';
prompt COMMIT;
COMMIT;

prompt Verifying Emma's updated salary:

SELECT first_name, salary FROM hr.employees WHERE first_name = 'Emma';

prompt
prompt ========================================================================
prompt Step 10: Marvin Attempts to Update His Own Salary
prompt  - This should update 0 rows. The manager grant predicate only
prompt    matches rows where manager_id = Marvin's employee_id.
prompt  - Marvin's own row has manager_id = 1 (Grace), not 2.
prompt ========================================================================

prompt UPDATE hr.employees SET salary = salary*1.5 WHERE employee_id = 2;
UPDATE hr.employees
   SET salary = salary*1.5
 WHERE employee_id = 2;

prompt ROLLBACK;
ROLLBACK;

prompt
prompt ========================================================================
prompt Step 11: Per-Column, Per-Row Authorization Check
prompt  - ORA_CHECK_DATA_PRIVILEGE shows what Marvin can view or update.
prompt ========================================================================

col first_name    format a12
col view_ssn      format a10
col update_ssn    format a10
col view_salary   format a12
col update_salary format a14
col view_phone    format a10
col update_phone  format a13

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
echo -e "${GREEN}      Task 6 Completed: Marvin's Session Verified Successfully!             ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
