#!/bin/bash
# =========================================================================================
# Script Name : dg_create_end_users_and_roles.sh
#
# Parameter   : None
#
# Notes       : Task 3 - Create end users and data roles.
#               Creates Marvin and Emma as end users, creates HRAPP_EMPLOYEES
#               and HRAPP_MANAGERS data roles, and grants them appropriately.
#
# Modified by         Date         Change
# Oracle DB Security  18/03/2026   Creation
# =========================================================================================

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 3: Create End Users and Data Roles                               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_SYS="${DBUSR_SYS:-sys}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Steps 1-4: Create end users, data roles, grant roles, and verify
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Steps 1-4: Creating end users, data roles, and assigning roles...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Verify Current Database User and Container
prompt ========================================================================

show user;
show con_name;

prompt
prompt ========================================================================
prompt Step 1: Create Two End Users
prompt  - Marvin (manager) and Emma (employee).
prompt  - End users authenticate directly but do not own schemas.
prompt ========================================================================

prompt CREATE END USER marvin IDENTIFIED BY Oracle123;
CREATE END USER marvin IDENTIFIED BY Oracle123;
prompt CREATE END USER emma IDENTIFIED BY Oracle123;
CREATE END USER emma IDENTIFIED BY Oracle123;

prompt
prompt ========================================================================
prompt Step 2: Create Two Data Roles
prompt  - HRAPP_EMPLOYEES: limited SELECT + phone UPDATE for employees.
prompt  - HRAPP_MANAGERS: broader SELECT + salary/dept UPDATE for managers.
prompt ========================================================================

prompt CREATE OR REPLACE DATA ROLE hrapp_employees;
CREATE OR REPLACE DATA ROLE hrapp_employees;
prompt CREATE OR REPLACE DATA ROLE hrapp_managers;
CREATE OR REPLACE DATA ROLE hrapp_managers;

prompt
prompt ========================================================================
prompt Step 3: Grant Data Roles to End Users
prompt  - Emma gets HRAPP_EMPLOYEES only.
prompt  - Marvin gets both HRAPP_EMPLOYEES and HRAPP_MANAGERS.
prompt ========================================================================

prompt GRANT DATA ROLE hrapp_employees TO emma;
GRANT DATA ROLE hrapp_employees TO emma;
prompt GRANT DATA ROLE hrapp_employees TO marvin;
GRANT DATA ROLE hrapp_employees TO marvin;
prompt GRANT DATA ROLE hrapp_managers TO marvin;
GRANT DATA ROLE hrapp_managers TO marvin;

prompt
prompt ========================================================================
prompt Step 4: Verify Data Roles and Their Mappings
prompt ========================================================================

col data_role           format a20
col mapped_to           format a15
col enabled_by_default  format a20

SELECT data_role, mapped_to, enabled_by_default
  FROM dba_data_roles
 WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS');

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 3 Completed: End Users and Data Roles Created!                   ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
