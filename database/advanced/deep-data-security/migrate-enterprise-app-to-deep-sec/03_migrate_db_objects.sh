#!/bin/bash
# =========================================================================================
# Script Name : 03_migrate_db_objects.sh
#
# Parameter   : None
#
# Notes       : Task 2 - Migrate the database objects.
#               Converts HR from a traditional schema user to NO AUTHENTICATION,
#               creates end users with Entra ID UPN identities (marvin@domain.com),
#               data roles, data grants, and end user context.
#               This is the bulk of the migration.
#
# Modified by         Date         Change
# Oracle DB Security  01/04/2026   Creation
# Oracle DB Security  04/28/2026   Entra ID UPN-format end users; source lab_env.sh
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
echo -e "${GREEN}      Task 2: Migrate Database Objects to Deep Data Security                ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
echo -e "${PURPLE}This script converts the traditional HR setup to Deep Data Security:${NC}"
echo -e "${PURPLE}  1. Lock the HR schema (NO AUTHENTICATION — schema-only)${NC}"
echo -e "${PURPLE}  2. Create end users (marvin@${DOMAIN_NAME}, emma@${DOMAIN_NAME})${NC}"
echo -e "${PURPLE}  3. Create data roles (hrapp_employees_local, hrapp_managers_local)${NC}"
echo -e "${PURPLE}  4. Create data grants with row/column predicates${NC}"
echo -e "${PURPLE}  5. Create end user context for derived identity values${NC}"
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
# Steps 1-5: Migration as SYSTEM
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
echo -e "${YELLOW}Steps 1-5: Migrating database objects...${NC}"
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
prompt Step 1: Lock the HR Schema
prompt  - HR becomes schema-only. It can no longer log in.
prompt  - Traditional: CREATE USER hr IDENTIFIED BY Oracle123
prompt  - Migration:   ALTER USER hr NO AUTHENTICATION
prompt ========================================================================

prompt ALTER USER hr NO AUTHENTICATION;
ALTER USER hr NO AUTHENTICATION;

prompt REVOKE CREATE SESSION FROM hr;
REVOKE CREATE SESSION FROM hr;

prompt
prompt ========================================================================
prompt Step 2: Create End Users (Entra ID UPN identities)
prompt  - End user names match Entra ID UPNs (marvin@domain.com).
prompt  - In production: end users authenticate via Entra ID OAuth token.
prompt  - In this lab: password auth is used so SQL*Plus verification works.
prompt  - Traditional: CREATE USER marvin IDENTIFIED BY ...
prompt  - Enterprise:  CREATE END USER "marvin@domain.com" IDENTIFIED BY ...
prompt ========================================================================

prompt CREATE END USER "marvin@${DOMAIN_NAME}" IDENTIFIED BY Oracle123;
CREATE END USER "marvin@${DOMAIN_NAME}" IDENTIFIED BY Oracle123;
prompt CREATE END USER "emma@${DOMAIN_NAME}" IDENTIFIED BY Oracle123;
CREATE END USER "emma@${DOMAIN_NAME}" IDENTIFIED BY Oracle123;

prompt
prompt ========================================================================
prompt Step 3: Create Data Roles
prompt  - Data roles replace traditional roles for data access.
prompt  - Traditional: CREATE ROLE manager_role
prompt  - Migration:   CREATE DATA ROLE hrapp_managers_local
prompt ========================================================================

prompt CREATE OR REPLACE DATA ROLE hrapp_employees_local;
CREATE OR REPLACE DATA ROLE hrapp_employees_local;
prompt CREATE OR REPLACE DATA ROLE hrapp_managers_local;
CREATE OR REPLACE DATA ROLE hrapp_managers_local;

prompt
prompt Grant data roles to end users:
prompt  - Emma gets employee role only
prompt  - Marvin gets both employee and manager roles

prompt GRANT DATA ROLE hrapp_employees_local TO "emma@${DOMAIN_NAME}";
GRANT DATA ROLE hrapp_employees_local TO "emma@${DOMAIN_NAME}";
prompt GRANT DATA ROLE hrapp_employees_local TO "marvin@${DOMAIN_NAME}";
GRANT DATA ROLE hrapp_employees_local TO "marvin@${DOMAIN_NAME}";
prompt GRANT DATA ROLE hrapp_managers_local TO "marvin@${DOMAIN_NAME}";
GRANT DATA ROLE hrapp_managers_local TO "marvin@${DOMAIN_NAME}";

prompt
prompt ========================================================================
prompt Step 4: Create Data Grants
prompt  - Data grants combine access + filtering in one statement.
prompt  - Traditional: GRANT SELECT ON hr.employees TO role
prompt  - Migration:   CREATE DATA GRANT ... ON hr.employees
prompt                   WHERE predicate ... TO data_role
prompt ========================================================================

prompt
prompt --- Employee Data Grant: see own row only, update phone_number ---

prompt CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_LOCAL_ACCESS ...;
CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_LOCAL_ACCESS
  AS SELECT (employee_id, first_name, last_name, user_name, department_id, manager_id, ssn, salary, phone_number), UPDATE(phone_number)
  ON hr.employees
  WHERE upper(user_name) = upper(ora_end_user_context.username)
  TO HRAPP_EMPLOYEES_LOCAL;

prompt
prompt ========================================================================
prompt Step 5: Create End User Context and Initialization Package
prompt  - EMP_CTX stores the current user's employee_id.
prompt  - Resolved at session start via o:onFirstRead trigger.
prompt  - Used by the manager data grant predicate.
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
prompt --- Grant context privileges ---

prompt GRANT UPDATE ANY END USER CONTEXT TO HR;
GRANT UPDATE ANY END USER CONTEXT TO HR;
prompt GRANT CREATE ANY END USER CONTEXT TO HR;
GRANT CREATE ANY END USER CONTEXT TO HR;

prompt CREATE ROLE IF NOT EXISTS employee_context_admin;
CREATE ROLE IF NOT EXISTS employee_context_admin;
prompt GRANT EXECUTE ON hr.ctx_pkg TO employee_context_admin;
GRANT EXECUTE ON hr.ctx_pkg TO employee_context_admin;
prompt GRANT employee_context_admin TO HRAPP_EMPLOYEES_LOCAL;
GRANT employee_context_admin TO HRAPP_EMPLOYEES_LOCAL;
prompt GRANT employee_context_admin TO HRAPP_MANAGERS_LOCAL;
GRANT employee_context_admin TO HRAPP_MANAGERS_LOCAL;

exit;
EOF

echo
echo -e "${YELLOW}Creating the data grant on SYS.END_USER_CONTEXT...${NC}"
echo -e "${PURPLE}NOTE: This must run as SYS because it grants access to a SYS-owned table.${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${DBUSR_SYS}/******@${PDB_NAME} as sysdba${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Data grant on SYS.END_USER_CONTEXT (requires SYS)
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
sqlplus -s ${DBUSR_SYS}/${DBUSR_PWD}@${PDB_NAME} as sysdba <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

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
    TO HRAPP_EMPLOYEES_LOCAL, HRAPP_MANAGERS_LOCAL;

exit;
EOF

echo
echo -e "${YELLOW}Creating the manager data grant...${NC}"
echo -e "${CYAN}Executing: sqlplus -s ${CONN_DISPLAY}${NC}"
echo

# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
# Manager data grant as SYSTEM
# --------- ----- ----- ----- ----- ----- ----- ----- ----- ----- ----- -----
sqlplus -s ${DBUSR_SYSTEM}/${DBUSR_PWD}@${PDB_NAME} <<EOF

set echo off
set serveroutput on
set lines 130
set pages 9999

prompt
prompt ========================================================================
prompt Manager Data Grant: see own row + direct reports
prompt  - ALL COLUMNS EXCEPT ssn for direct reports.
prompt  - UPDATE salary and department_id for direct reports.
prompt ========================================================================

prompt CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_LOCAL_ACCESS ...;
CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_LOCAL_ACCESS
  AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id)
  ON hr.employees
  WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
  TO HRAPP_MANAGERS_LOCAL;

exit;
EOF

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Task 2 Completed: Database Objects Migrated!                          ${NC}"
echo -e "${GREEN}      HR can no longer log in. End users, data roles, and data grants       ${NC}"
echo -e "${GREEN}      are in place. Next: run 04_create_role_bindings.sh                    ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo
