#!/bin/bash
# =========================================================================================
# Script Name : dg_marvin_role_change.sh
#
# Parameter   : None
#
# Notes       : Task 9 - Marvin changes roles.
#               Revokes the HRAPP_MANAGERS data role from Marvin, then
#               reconnects as Marvin to show his access is now identical
#               to Emma's — zero code changes required.
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
echo -e "${GREEN}      Task 9: Marvin Changes Roles (Manager -> Employee Only)               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 1: Revoke the HRAPP_MANAGERS data role from Marvin
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 1: Revoking HRAPP_MANAGERS data role from Marvin...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Revoking HRAPP_MANAGERS From Marvin
prompt  - Simulates an org change: Marvin moves to a special project.
prompt  - The change takes effect on his next session.
prompt ========================================================================

prompt REVOKE DATA ROLE hrapp_managers FROM marvin;
REVOKE DATA ROLE hrapp_managers FROM marvin;

exit;
EOF

echo
echo -e "${YELLOW}Step 2: Reconnecting as Marvin with a new session...${NC}"
echo -e "${CYAN}Executing: sqlplus -s marvin/******@${PDB_NAME}${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Steps 2-5: Reconnect as Marvin and verify reduced access
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
sqlplus -s marvin/Oracle123@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Step 3: Verify Only HRAPP_EMPLOYEES Is Active
prompt  - HRAPP_MANAGERS is no longer granted, so it does not activate.
prompt ========================================================================

col role_name format a25

SELECT ROLE_NAME FROM V\$END_USER_DATA_ROLE;

prompt
prompt ========================================================================
prompt Step 4: Run the Same Query as Before
prompt  - Marvin now sees only his own row (identical to Emma).
prompt  - His direct reports are completely gone.
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
prompt Step 5: Verify Column Authorization Has Changed
prompt  - Marvin's authorization now matches Emma's exactly.
prompt  - Manager-level UPDATE on salary is gone.
prompt  - A single REVOKE DATA ROLE statement. No application code changed.
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
echo -e "${GREEN}      Task 9 Completed: Marvin's Access Reduced Successfully!               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo -e "${PURPLE}  This is the power of data roles and data grants: access policy is          ${NC}"
echo -e "${PURPLE}  declared at the database layer and enforced automatically.                 ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
