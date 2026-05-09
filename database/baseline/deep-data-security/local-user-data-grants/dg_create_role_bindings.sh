#!/bin/bash
# =========================================================================================
# Script Name : dg_create_role_bindings.sh
#
# Parameter   : None
#
# Notes       : Task 5 - Create role-to-role bindings and verify.
#               Creates the direct logon role, verifies the complete setup,
#               and confirms DIRECT_LOGON_ROLE configuration.
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
echo -e "${GREEN}      Task 5: Create Role-to-Role Bindings and Verify                       ${NC}"
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
# Steps 1-3: Direct logon role and verification
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Steps 1-3: Creating direct logon role and verifying setup...${NC}"
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
prompt Step 1: Create the Direct Logon Role
prompt  - Grants CREATE SESSION so end users can connect directly.
prompt  - Granted to both data roles.
prompt ========================================================================

prompt CREATE ROLE direct_logon_role;
CREATE ROLE direct_logon_role;
prompt GRANT CREATE SESSION TO direct_logon_role;
GRANT CREATE SESSION TO direct_logon_role;
prompt GRANT direct_logon_role TO hrapp_employees;
GRANT direct_logon_role TO hrapp_employees;
prompt GRANT direct_logon_role TO hrapp_managers;
GRANT direct_logon_role TO hrapp_managers;

prompt
prompt ========================================================================
prompt Step 2: Verify the Complete Setup
prompt  - Data grants on HR.EMPLOYEES
prompt ========================================================================

col grant_name                    format a30
col privilege                     format a10
col grantee                       format a20
col column_name                   format a15
col granted_with_all_columns_except format a30
col predicate                     format a50

SELECT grant_name, privilege, grantee, column_name,
       granted_with_all_columns_except, predicate
  FROM dba_data_grants
 WHERE object_owner = 'HR'
   AND object_name = 'EMPLOYEES'
 ORDER BY grant_name, privilege;

prompt
prompt ========================================================================
prompt Step 3: Verify DIRECT_LOGON_ROLE Configuration
prompt  - Confirm CREATE SESSION privilege
prompt ========================================================================

col privilege     format a20
col grantee       format a25
col granted_role  format a20
col data_role     format a20
col role_type     format a15

SELECT privilege
  FROM dba_sys_privs
 WHERE grantee = 'DIRECT_LOGON_ROLE';

SELECT grantee, granted_role
  FROM dba_role_privs
 WHERE granted_role = 'DIRECT_LOGON_ROLE';

SELECT data_role, role_type, grantee
  FROM dba_data_role_grants
 WHERE data_role = 'DIRECT_LOGON_ROLE'
 ORDER BY grantee;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 5 Completed: Role-to-Role Bindings Created and Verified!         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
