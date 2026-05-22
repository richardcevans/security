#!/bin/bash
# =========================================================================================
# Script Name : 04_create_data_roles_and_grants.sh
#
# Parameter   : None
#
# Notes       : Task 4 - Create data roles, data grants, and end user context.
#               Data roles use MAPPED TO 'IAM_OAUTH_GROUP=...' for OCI IAM integration.
#               No CREATE END USER needed — identity comes from the OAuth2 token.
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
echo -e "${GREEN}      Task 4: Create Data Roles, Data Grants, and End User Context          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}Data roles use MAPPED TO 'IAM_OAUTH_GROUP=...' for automatic activation${NC}"
echo -e "${PURPLE}based on the OCI IAM group membership in the OAuth2 token.${NC}"
echo -e "${PURPLE}No CREATE END USER or GRANT DATA ROLE needed.${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Validate environment variables
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
export PDB_NAME="${PDB_NAME:-FREEPDB1}"
export DB_SID="${DB_SID:-FREE}"
export ORACLE_SID="$DB_SID"

CONN_DISPLAY="/ as sysdba, then ALTER SESSION SET CONTAINER=${PDB_NAME}"
echo -e "${CYAN}ORACLE_SID = ${ORACLE_SID}${NC}"

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Steps 1-5: Create data roles, grants, and context as SYSTEM
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Steps 1-5: Creating data roles, grants, and context...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

if ! sqlplus -s / as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999
whenever sqlerror exit sql.sqlcode

BEGIN
  EXECUTE IMMEDIATE 'ALTER PLUGGABLE DATABASE ${PDB_NAME} OPEN';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -65019 THEN
      RAISE;
    END IF;
END;
/

ALTER SESSION SET CONTAINER = ${PDB_NAME};

prompt
prompt ========================================================================
prompt Step 1: Create Data Roles with MAPPED TO for OCI IAM
prompt  - HRAPP_EMPLOYEES maps to IAM_OAUTH_GROUP=EMPLOYEES
prompt  - HRAPP_MANAGERS maps to IAM_OAUTH_GROUP=MANAGERS
prompt  - When Marvin's token contains MANAGERS group membership, Oracle activates hrapp_managers
prompt ========================================================================

prompt CREATE OR REPLACE DATA ROLE hrapp_employees MAPPED TO 'IAM_OAUTH_GROUP=EMPLOYEES';
CREATE OR REPLACE DATA ROLE hrapp_employees MAPPED TO 'IAM_OAUTH_GROUP=EMPLOYEES';

prompt CREATE OR REPLACE DATA ROLE hrapp_managers MAPPED TO 'IAM_OAUTH_GROUP=MANAGERS';
CREATE OR REPLACE DATA ROLE hrapp_managers MAPPED TO 'IAM_OAUTH_GROUP=MANAGERS';

prompt
prompt Verify data roles:
col data_role  format a20
col mapped_to  format a30
SELECT data_role, mapped_to, enabled_by_default
  FROM dba_data_roles
 WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS');

prompt
prompt ========================================================================
prompt Step 2: Create Employee Data Grant
prompt  - Employees see only their own row (WHERE user_name = username)
prompt  - SELECT on specific columns, UPDATE on phone_number and first_name
prompt ========================================================================

prompt CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS ...;
CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS
  AS SELECT (employee_id, first_name, last_name, user_name, department_id, manager_id, ssn, salary, phone_number), UPDATE(phone_number, first_name)
  ON hr.employees
  WHERE upper(user_name) = upper(ora_end_user_context.username)
  TO HRAPP_EMPLOYEES;

prompt
prompt ========================================================================
prompt Step 3: Create End User Context and Initialization Package
prompt  - EMP_CTX stores the current user's employee_id
prompt  - Resolved lazily via o:onFirstRead trigger
prompt  - Used by the manager data grant predicate
prompt ========================================================================

prompt CREATE OR REPLACE END USER CONTEXT HR.EMP_CTX ...;
CREATE OR REPLACE END USER CONTEXT HR.EMP_CTX USING JSON SCHEMA '{
  "type": "object",
  "properties": {
    "ID": {
      "type": "integer",
      "o:onFirstRead": "HR.ctx_pkg.init_user_context"
    }
  }
}';

prompt CREATE OR REPLACE PACKAGE hr.ctx_pkg ...;
CREATE OR REPLACE PACKAGE hr.ctx_pkg AS
  PROCEDURE init_user_context;
END;
/

prompt CREATE OR REPLACE PACKAGE BODY hr.ctx_pkg ...;
CREATE OR REPLACE PACKAGE BODY hr.ctx_pkg AS
  PROCEDURE init_user_context IS
    sql_stmt VARCHAR2(4000);
  BEGIN
    sql_stmt := '
      UPDATE END_USER_CONTEXT t
      SET t.CONTEXT.ID = (
         SELECT e.employee_id
         FROM hr.employees e
         WHERE upper(e.user_name) = upper(ora_end_user_context.USERNAME)
       )
      WHERE owner = ''HR''
      AND name = ''EMP_CTX'';
    ';
    EXECUTE IMMEDIATE sql_stmt;
  END;
END;
/

prompt
prompt ========================================================================
prompt Step 4: Grant Context Privileges
prompt  - HR needs UPDATE ANY END USER CONTEXT
prompt  - employee_context_admin role bridges EXECUTE to data roles
prompt ========================================================================

prompt GRANT UPDATE ANY END USER CONTEXT TO HR;
GRANT UPDATE ANY END USER CONTEXT TO HR;

prompt CREATE ROLE IF NOT EXISTS employee_context_admin;
CREATE ROLE IF NOT EXISTS employee_context_admin;
prompt GRANT EXECUTE ON hr.ctx_pkg TO employee_context_admin;
GRANT EXECUTE ON hr.ctx_pkg TO employee_context_admin;
prompt GRANT employee_context_admin TO HRAPP_EMPLOYEES;
GRANT employee_context_admin TO HRAPP_EMPLOYEES;
prompt GRANT employee_context_admin TO HRAPP_MANAGERS;
GRANT employee_context_admin TO HRAPP_MANAGERS;

prompt
prompt ========================================================================
prompt Step 5: Create Role Bindings (CREATE SESSION)
prompt  - direct_logon_role holds CREATE SESSION
prompt  - Granted to both data roles so OCI IAM users can connect
prompt ========================================================================

prompt CREATE ROLE IF NOT EXISTS direct_logon_role;
CREATE ROLE IF NOT EXISTS direct_logon_role;
prompt GRANT CREATE SESSION TO direct_logon_role;
GRANT CREATE SESSION TO direct_logon_role;
prompt GRANT direct_logon_role TO hrapp_employees;
GRANT direct_logon_role TO hrapp_employees;
prompt GRANT direct_logon_role TO hrapp_managers;
GRANT direct_logon_role TO hrapp_managers;

exit;
EOF
then
    echo
    echo -e "${RED}ERROR: Could not create data roles, grants, or context in ${PDB_NAME}.${NC}"
    exit 1
fi

echo
echo -e "${YELLOW}Creating the data grant on SYS.END_USER_CONTEXT...${NC}"
echo -e "${PURPLE}NOTE: This must run as SYS because it grants access to a SYS-owned table.${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Data grant on SYS.END_USER_CONTEXT (requires SYS)
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
prompt Creating Data Grant on SYS.END_USER_CONTEXT
prompt  - Allows end user sessions to read their context attributes.
prompt ========================================================================

show user;
show con_name;

prompt CREATE OR REPLACE DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT ...;
CREATE OR REPLACE DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT
  AS SELECT ON SYS.END_USER_CONTEXT
   WHERE OWNER = 'HR' AND NAME = 'EMP_CTX'
    TO HRAPP_EMPLOYEES, HRAPP_MANAGERS;

exit;
EOF
then
    echo
    echo -e "${RED}ERROR: Could not create data grant on SYS.END_USER_CONTEXT in ${PDB_NAME}.${NC}"
    exit 1
fi

echo
echo -e "${YELLOW}Creating the manager data grant...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Manager data grant as SYSTEM
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
prompt Step 6: Manager Data Grant
prompt  - ALL COLUMNS EXCEPT ssn for direct reports
prompt  - UPDATE salary, department_id, and first_name for direct reports
prompt  - Predicate: manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
prompt ========================================================================

prompt CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS ...;
CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
  AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id, first_name)
  ON hr.employees
  WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
  TO HRAPP_MANAGERS;

prompt
prompt ========================================================================
prompt Verify: All Data Grants
prompt ========================================================================

col grant_name  format a35
col privilege   format a10
col grantee     format a20
col predicate   format a50

SELECT grant_name, privilege, grantee, predicate
  FROM dba_data_grants
 WHERE object_owner = 'HR'
   AND object_name = 'EMPLOYEES'
 ORDER BY grant_name, privilege;

exit;
EOF
then
    echo
    echo -e "${RED}ERROR: Could not create manager data grant in ${PDB_NAME}.${NC}"
    exit 1
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 4 Completed: Data Roles, Grants, and Context Created!            ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}  Data roles use MAPPED TO 'IAM_OAUTH_GROUP=...' — no end users needed.          ${NC}"
echo -e "${GREEN}  When Marvin logs in via OCI IAM as a member of the MANAGERS group,              ${NC}"
echo -e "${GREEN}  Oracle automatically activates hrapp_managers for his session.             ${NC}"
echo -e "${GREEN}                                                                            ${NC}"
echo -e "${GREEN}      Next: run 05_verify_as_marvin.sh                                      ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
