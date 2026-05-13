#!/bin/bash
# =========================================================================================
# Script Name : 08_cleanup_db.sh
#
# Parameter   : None
#
# Notes       : Task 8 (Optional) - Clean up database objects.
#               Drops all data grants, end user context, roles, data roles,
#               the HR schema, and resets the identity provider parameters.
#               OCI IAM cleanup (deleting the database application and groups) must be done manually.
#
# Modified by         Date         Change
# Oracle DB Security  04/02/2026   Creation
# =========================================================================================

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
RED='\033[0;31m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 8 (Optional): Clean Up Database Lab Objects                      ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 1: Drop the context data grant (requires SYS)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 1: Dropping SYS-owned objects (as SYS)...${NC}"
echo -e "${PURPLE}NOTE: This must run as SYS because it was created on a SYS-owned table.${NC}"
echo -e "${CYAN}Executing: sqlplus -s / as sysdba${NC}"
echo

if ! sqlplus -s / as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Dropping Data Grant on SYS.END_USER_CONTEXT and OCI IAM credential
prompt ========================================================================

prompt DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT;
DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT;

prompt Drop OCI IAM domain credential if present;
BEGIN
  DBMS_CREDENTIAL.DROP_CREDENTIAL(credential_name => 'OCI_IAM_DOMAIN_DB_CRED$');
EXCEPTION
  WHEN OTHERS THEN NULL;
END;
/

exit;
EOF
then
    echo
    echo -e "${YELLOW}Warning: SYS cleanup block reported an error. Continuing with remaining cleanup.${NC}"
fi

echo
echo -e "${YELLOW}Step 2: Dropping all remaining lab objects (as DBA)...${NC}"
echo -e "${CYAN}Executing: sqlplus -s / as sysdba${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 2: Drop everything else (as DBA user)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
if ! sqlplus -s / as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Dropping Data Grants, Context, Roles, and HR Schema
prompt  - DROP USER hr CASCADE removes the schema, ctx_pkg package,
prompt    the employees table, and all dependent objects.
prompt ========================================================================

prompt DROP DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS;
DROP DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS;
prompt DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS;
DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS;
prompt DROP END USER CONTEXT HR.EMP_CTX;
DROP END USER CONTEXT HR.EMP_CTX;
prompt DROP ROLE employee_context_admin;
DROP ROLE employee_context_admin;
prompt DROP ROLE direct_logon_role;
DROP ROLE direct_logon_role;
prompt DROP DATA ROLE HRAPP_EMPLOYEES;
DROP DATA ROLE HRAPP_EMPLOYEES;
prompt DROP DATA ROLE HRAPP_MANAGERS;
DROP DATA ROLE HRAPP_MANAGERS;
prompt DROP USER hr CASCADE;
DROP USER hr CASCADE;

prompt
prompt ========================================================================
prompt Step 3: Reset Identity Provider Parameters
prompt ========================================================================

prompt ALTER SYSTEM RESET IDENTITY_PROVIDER_OAUTH_CONFIG SCOPE=BOTH;
ALTER SYSTEM RESET IDENTITY_PROVIDER_OAUTH_CONFIG SCOPE=BOTH;
prompt ALTER SYSTEM RESET IDENTITY_PROVIDER_TYPE SCOPE=BOTH;
ALTER SYSTEM RESET IDENTITY_PROVIDER_TYPE SCOPE=BOTH;

prompt
prompt ========================================================================
prompt Step 4: Verify Everything Is Removed
prompt  - All queries below should return no rows.
prompt ========================================================================

col data_role   format a25
col mapped_to   format a30
col grant_name  format a35
col username    format a15
col role        format a25
col name        format a30
col value       format a50

SELECT data_role, mapped_to FROM dba_data_roles
 WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS');

SELECT grant_name FROM dba_data_grants
 WHERE owner = 'HR';

SELECT username FROM dba_users
 WHERE username = 'HR';

SELECT role FROM dba_roles
 WHERE role IN ('EMPLOYEE_CONTEXT_ADMIN', 'DIRECT_LOGON_ROLE');

SELECT name, value
  FROM v\$parameter
 WHERE name IN ('identity_provider_type','identity_provider_oauth_config');

exit;
EOF
then
    echo
    echo -e "${RED}ERROR: Could not clean up database lab objects in ${PDB_NAME}.${NC}"
    exit 1
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 8 Completed: Database Lab Objects Removed!                       ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}      OCI IAM cleanup (manual):                                               ${NC}"
echo -e "${GREEN}      1. Delete the OCI IAM database application if it is lab-only              ${NC}"
echo -e "${GREEN}      2. Delete the EMPLOYEES and MANAGERS groups if they are lab-only                   ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
