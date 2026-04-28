#!/bin/bash
# =========================================================================================
# Script Name : 04_create_role_bindings.sh
#
# Parameter   : None
#
# Notes       : Task 2 (continued) - Create role bindings.
#               Creates the DIRECT_LOGON_ROLE database role with CREATE SESSION
#               and grants it to the data roles so end users can connect.
#
# Modified by         Date         Change
# Oracle DB Security  01/04/2026   Creation
# Oracle DB Security  04/28/2026   Source lab_env.sh for Entra ID domain
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
echo -e "${GREEN}      Task 2 (continued): Create Role Bindings                              ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}End users cannot connect without CREATE SESSION. Instead of granting${NC}"
echo -e "${PURPLE}this directly, you create a database role and bind it to the data roles.${NC}"
echo -e "${PURPLE}When a data role activates, it brings CREATE SESSION with it.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

echo -e "${YELLOW}Creating DIRECT_LOGON_ROLE and binding to data roles...${NC}"
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
prompt Creating DIRECT_LOGON_ROLE
prompt  - Holds CREATE SESSION system privilege.
prompt  - Granted to both data roles so end users can connect.
prompt ========================================================================

prompt CREATE ROLE direct_logon_role;
CREATE ROLE direct_logon_role;
prompt GRANT CREATE SESSION TO direct_logon_role;
GRANT CREATE SESSION TO direct_logon_role;
prompt GRANT direct_logon_role TO hrapp_employees_local;
GRANT direct_logon_role TO hrapp_employees_local;
prompt GRANT direct_logon_role TO hrapp_managers_local;
GRANT direct_logon_role TO hrapp_managers_local;

prompt
prompt ========================================================================
prompt Verifying Data Grants
prompt  - Shows all data grants on HR objects.
prompt ========================================================================

col grant_name    format a35
col object_name   format a20
col privilege     format a10
col grantee       format a25
col predicate     format a50

SELECT grant_name, object_name, privilege, grantee, predicate
  FROM dba_data_grants
 WHERE object_owner = 'HR'
 ORDER BY object_name, grant_name, privilege;

prompt
prompt ========================================================================
prompt Verifying Data Role Grants
prompt  - Shows which end users have which data roles.
prompt ========================================================================

col data_role  format a25
col grantee    format a15

SELECT data_role, grantee
  FROM dba_data_role_grants
 WHERE data_role IN ('HRAPP_EMPLOYEES_LOCAL', 'HRAPP_MANAGERS_LOCAL')
 ORDER BY grantee, data_role;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Role Bindings Created! End users can now connect.                     ${NC}"
echo -e "${GREEN}      Next: run 05_verify_as_marvin.sh                                     ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
