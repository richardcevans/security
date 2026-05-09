#!/bin/bash
# =========================================================================================
# Script Name : dg_marvin_role_restore.sh
#
# Parameter   : None
#
# Notes       : Re-grants the HRAPP_MANAGERS data role to Marvin after Task 9
#               revoked it, restoring his manager-level access.
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

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Set defaults for environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

CONN_DISPLAY="${DBUSR_SYSTEM}/******@${PDB_NAME}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Restore Marvin's Manager Role                                         ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

echo -e "${YELLOW}Re-granting HRAPP_MANAGERS data role to Marvin...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Granting HRAPP_MANAGERS Back to Marvin
prompt  - Restores manager-level access (direct reports, salary UPDATE).
prompt  - Takes effect on Marvin's next session.
prompt ========================================================================

prompt GRANT DATA ROLE hrapp_managers TO marvin;
GRANT DATA ROLE hrapp_managers TO marvin;

prompt
prompt ========================================================================
prompt Verifying Marvin's Data Role Grants
prompt ========================================================================

col end_user  format a15
col data_role format a20

SELECT grantee AS end_user, data_role
  FROM dba_data_role_grants
 WHERE grantee = 'MARVIN'
   AND data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS')
 ORDER BY data_role;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Marvin's Manager Role Restored Successfully!                          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
