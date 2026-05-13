#!/bin/bash
# =========================================================================================
# Script Name : 08_cleanup.sh
#
# Parameter   : None
#
# Notes       : Script 8 (Optional) - Clean up.
#               Drops all data grants, end user context, roles, data roles,
#               the HR schema, and resets the identity provider parameters.
#               Azure cleanup (deleting app registrations) must be done manually.
#
# Modified by         Date         Change
# Oracle DB Security  04/02/2026   Creation
# =========================================================================================

set -euo pipefail

# Define colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Script 8 (Optional): Clean Up Database Lab Objects                    ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"
export PDB_NAME="${PDB_NAME:-FREEPDB1}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 1: Drop the context data grant (requires SYS)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Step 1: Dropping the context data grant (as SYS)...${NC}"
echo -e "${PURPLE}NOTE: This must run as SYS because it was created on a SYS-owned table.${NC}"
echo -e "${CYAN}Executing: sqlplus -s / as sysdba${NC}"
echo

sqlplus -s / as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999
whenever sqlerror exit sql.sqlcode

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Dropping Data Grant on SYS.END_USER_CONTEXT
prompt ========================================================================

prompt DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT;
BEGIN
  EXECUTE IMMEDIATE 'DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT';
  DBMS_OUTPUT.PUT_LINE('Dropped: hr.EMPLOYEE_CONTEXT_GRANT');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Not found or already removed: hr.EMPLOYEE_CONTEXT_GRANT');
END;
/

exit;
EOF

echo
echo -e "${YELLOW}Step 2: Dropping all remaining lab objects (as DBA)...${NC}"
echo -e "${CYAN}Executing: sqlplus -s / as sysdba${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Step 2: Drop everything else (as DBA user)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
sqlplus -s / as sysdba <<EOF

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

DECLARE
  PROCEDURE run_sql(p_sql VARCHAR2, p_label VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p_sql;
    DBMS_OUTPUT.PUT_LINE('Dropped: ' || p_label);
  EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('Not found or already removed: ' || p_label);
  END;
BEGIN
  run_sql('DROP DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS', 'hr.HRAPP_EMPLOYEES_ACCESS');
  run_sql('DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS', 'hr.HRAPP_MANAGER_ACCESS');
  run_sql('DROP END USER CONTEXT HR.EMP_CTX', 'HR.EMP_CTX');
  run_sql('DROP ROLE employee_context_admin', 'employee_context_admin');
  run_sql('DROP ROLE direct_logon_role', 'direct_logon_role');
  run_sql('DROP DATA ROLE HRAPP_EMPLOYEES', 'HRAPP_EMPLOYEES');
  run_sql('DROP DATA ROLE HRAPP_MANAGERS', 'HRAPP_MANAGERS');
  run_sql('DROP USER hr CASCADE', 'hr');
END;
/

prompt
prompt ========================================================================
prompt Step 3: Reset Identity Provider Parameters
prompt ========================================================================

prompt ALTER SYSTEM RESET IDENTITY_PROVIDER_CONFIG SCOPE=BOTH;
BEGIN
  EXECUTE IMMEDIATE 'ALTER SYSTEM RESET IDENTITY_PROVIDER_CONFIG SCOPE=BOTH';
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('IDENTITY_PROVIDER_CONFIG was not set.');
END;
/
prompt ALTER SYSTEM RESET IDENTITY_PROVIDER_TYPE SCOPE=BOTH;
BEGIN
  EXECUTE IMMEDIATE 'ALTER SYSTEM RESET IDENTITY_PROVIDER_TYPE SCOPE=BOTH';
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('IDENTITY_PROVIDER_TYPE was not set.');
END;
/

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
 WHERE name IN ('identity_provider_type','identity_provider_config');

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Script 8 Completed: All Database Lab Objects Removed!                 ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}      Azure cleanup (manual):                                               ${NC}"
echo -e "${GREEN}      1. Delete the Oracle Client Interactive - ${PDB_NAME} app registration              ${NC}"
echo -e "${GREEN}      2. Delete the Oracle Database 26ai - ${PDB_NAME} app registration                   ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
