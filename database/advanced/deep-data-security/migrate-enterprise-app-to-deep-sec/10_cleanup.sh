#!/bin/bash
# =========================================================================================
# Script Name : 10_cleanup.sh
#
# Parameter   : None
#
# Notes       : Task 6 (Optional) - Clean up.
#               Drops all data grants, end user context, roles, end users,
#               and the HR schema created during this lab.
#               Also removes lab_env.sh.
#
# Modified by         Date         Change
# Oracle DB Security  01/04/2026   Creation
# Oracle DB Security  04/28/2026   Entra ID UPN-format end users; source lab_env.sh
# =========================================================================================

# Define colors for readability (only used in Bash, not inside SQL*Plus)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 6 (Optional): Clean Up - Remove All Lab Objects                  ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-pdb1}"
export DBUSR_SYSTEM="${DBUSR_SYSTEM:-system}"
export DBUSR_SYS="${DBUSR_SYS:-sys}"
export DBUSR_PWD="${DBUSR_PWD:-Oracle123}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 0: Stop any running sample apps
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

[ -f "${SCRIPT_DIR}/lab_env.sh" ] && source "${SCRIPT_DIR}/lab_env.sh"
export DOMAIN_NAME="${DOMAIN_NAME:-contoso.com}"

for APP in sample-app-springboot sample-app-django; do
    PIDFILE="$SCRIPT_DIR/apps/$APP/app.pid"
    if [ -f "$PIDFILE" ]; then
        echo -e "${YELLOW}Stopping $APP (PID $(cat "$PIDFILE"))...${NC}"
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
    fi
done

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 1: Drop the context data grant (requires SYS)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 1: Dropping the context data grant (as SYS)...${NC}"
echo -e "${PURPLE}NOTE: This must run as SYS because it was created on a SYS-owned table.${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${DBUSR_SYS}/******@${PDB_NAME} as sysdba${NC}"
echo

sqlplus -s ${DBUSR_SYS}/${DBUSR_PWD}@${PDB_NAME} as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Dropping Data Grant on SYS.END_USER_CONTEXT
prompt ========================================================================

prompt DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT;
DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT;

exit;
EOF

echo
echo -e "${YELLOW}Step 2: Dropping all remaining lab objects (as DBA)...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${DBUSR_SYSTEM}/******@${PDB_NAME}${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 2: Drop everything else (as DBA user)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Dropping Data Grants, Context, Roles, End Users, and HR Schema
prompt  - DROP USER hr CASCADE removes the schema, ctx_pkg package,
prompt    the employees table, and all dependent objects.
prompt ========================================================================

prompt DROP DATA GRANT hr.HRAPP_EMPLOYEES_LOCAL_ACCESS;
DROP DATA GRANT hr.HRAPP_EMPLOYEES_LOCAL_ACCESS;
prompt DROP DATA GRANT hr.HRAPP_MANAGER_LOCAL_ACCESS;
DROP DATA GRANT hr.HRAPP_MANAGER_LOCAL_ACCESS;
prompt DROP END USER CONTEXT HR.EMP_CTX;
DROP END USER CONTEXT HR.EMP_CTX;
prompt DROP ROLE employee_context_admin;
DROP ROLE employee_context_admin;
prompt DROP ROLE direct_logon_role;
DROP ROLE direct_logon_role;
prompt DROP DATA ROLE HRAPP_EMPLOYEES_LOCAL;
DROP DATA ROLE HRAPP_EMPLOYEES_LOCAL;
prompt DROP DATA ROLE HRAPP_MANAGERS_LOCAL;
DROP DATA ROLE HRAPP_MANAGERS_LOCAL;
prompt DROP END USER "emma@${DOMAIN_NAME}";
DROP END USER "emma@${DOMAIN_NAME}";
prompt DROP END USER "marvin@${DOMAIN_NAME}";
DROP END USER "marvin@${DOMAIN_NAME}";
prompt DROP USER hr CASCADE;
DROP USER hr CASCADE;

prompt
prompt ========================================================================
prompt Step 3: Verify Everything Is Removed
prompt  - All queries below should return no rows.
prompt ========================================================================

col data_role   format a25
col mapped_to   format a15
col grant_name  format a35
col username    format a15
col role        format a25

SELECT data_role, mapped_to FROM dba_data_roles
 WHERE data_role IN ('HRAPP_EMPLOYEES_LOCAL', 'HRAPP_MANAGERS_LOCAL');

SELECT grant_name FROM dba_data_grants
 WHERE owner = 'HR';

SELECT username FROM dba_users
 WHERE username = 'HR';

SELECT role FROM dba_roles
 WHERE role IN ('EMPLOYEE_CONTEXT_ADMIN', 'DIRECT_LOGON_ROLE');

exit;
EOF

echo
rm -f "${SCRIPT_DIR}/lab_env.sh"
echo -e "${CYAN}Removed lab_env.sh${NC}"

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 6 Completed: All Lab Objects Removed Successfully!               ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
