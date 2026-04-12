#!/bin/bash
# =========================================================================================
# Script Name : dg_connect_as_emma.sh
#
# Parameter   : None
#
# Notes       : Task 7 - Connect and verify as Emma.
#               Connects as end user Emma, verifies identity, active data roles,
#               runs the same query an AI agent would (sees only her own row),
#               tests UPDATE privileges, and checks per-column authorization.
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
echo -e "${GREEN}      Task 7: Connect and Verify as Emma (Employee)                         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"

CONN_DISPLAY="emma/******@${PDB_NAME}"

echo -e "${YELLOW}Connecting as end user Emma...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

sqlplus -s emma/Oracle123@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Step 2: Verify Emma's Active Data Roles
prompt  - Only HRAPP_EMPLOYEES should be active (no manager role).
prompt ========================================================================

col role_name format a25

SELECT ROLE_NAME FROM V\$END_USER_DATA_ROLE;

prompt
prompt ========================================================================
prompt Step 3: "Show me my employee details" - The AI Agent Query
prompt  - Emma sees only 1 row: herself.
prompt  - Same query Marvin ran, completely different results.
prompt  - Notice her salary reflects the raise Marvin gave her in Task 6.
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
prompt Step 4: Inspect the End User Context
prompt  - Emma's context is empty because the o:onFirstRead trigger
prompt    only fires when ORA_END_USER_CONTEXT.HR.EMP_CTX.ID is read.
prompt  - Emma's grant uses ora_end_user_context.USERNAME instead.
prompt ========================================================================

SELECT ora_end_user_context.HR FROM DUAL;

prompt
prompt ========================================================================
prompt Step 5: Emma Tries to Update Her Own Salary
prompt  - Should update 0 rows. HRAPP_EMPLOYEES only allows
prompt    UPDATE on PHONE_NUMBER, not SALARY.
prompt ========================================================================

prompt UPDATE hr.employees SET salary = 200000 WHERE first_name = 'Emma';
UPDATE hr.employees SET salary = 200000 WHERE first_name = 'Emma';

prompt
prompt ========================================================================
prompt Step 6: Emma Updates Her Phone Number (Allowed)
prompt  - The employee grant allows UPDATE on phone_number for her own row.
prompt ========================================================================

prompt UPDATE hr.employees SET phone_number = '555-555-5555' WHERE first_name = 'Emma';
UPDATE hr.employees SET phone_number = '555-555-5555' WHERE first_name = 'Emma';

prompt
prompt Now attempting to update everyone else's phone number (should be 0 rows):

prompt UPDATE hr.employees SET phone_number = '555-555-5555' WHERE first_name <> 'Emma';
UPDATE hr.employees SET phone_number = '555-555-5555' WHERE first_name <> 'Emma';

prompt
prompt Rolling back to preserve original data:

prompt ROLLBACK;
ROLLBACK;

prompt
prompt ========================================================================
prompt Step 7: Per-Column, Per-Row Authorization Check
prompt  - Emma can view SSN, salary, and phone but only update phone.
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
echo -e "${GREEN}      Task 7 Completed: Emma's Session Verified Successfully!               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
